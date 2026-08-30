package api

import (
	"context"
	"database/sql"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

var (
	ErrAppealNotFound        = errors.New("appeal not found")
	ErrAppealNotAllowed      = errors.New("appeal not allowed")
	ErrAppealAlreadyExists   = errors.New("appeal already exists")
	ErrAppealAlreadyReviewed = errors.New("appeal already reviewed")
	ErrInvalidAppeal         = errors.New("invalid appeal")
)

type appealCreateInput struct {
	Reason      string   `json:"reason"`
	Description string   `json:"description"`
	MediaIDs    []string `json:"media_ids"`
}

type appealReviewInput struct {
	Result string `json:"result"`
	Note   string `json:"note"`
}

type moderationActionRecord struct {
	ID            string
	Action        string
	Reason        string
	Appealable    bool
	TargetType    string
	TargetID      string
	OwnerID       string
	TargetTitle   string
	TargetContent string
	CreatedAt     time.Time
}

func (s *Server) getModerationAction(w http.ResponseWriter, r *http.Request, actionID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	record, err := s.findModerationAction(r.Context(), s.db, actionID)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrAppealNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if record.OwnerID != user.ID {
		writeAuthError(w, r, ErrPermissionDenied)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, s.moderationActionJSON(r.Context(), s.db, record))
}

func (s *Server) createAppeal(w http.ResponseWriter, r *http.Request, actionID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	var input appealCreateInput
	if err := decodeJSON(r, &input); err != nil || !validAppealInput(input) {
		writeAuthError(w, r, ErrInvalidAppeal)
		return
	}
	mediaIDs := uniqueStrings(input.MediaIDs)
	if len(mediaIDs) > 3 {
		writeAuthError(w, r, ErrInvalidAppeal)
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	record, err := s.findModerationAction(r.Context(), tx, actionID)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrAppealNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if record.OwnerID != user.ID || !record.Appealable {
		writeAuthError(w, r, ErrAppealNotAllowed)
		return
	}
	var existingID, existingStatus string
	err = tx.QueryRowContext(r.Context(), `SELECT id, status FROM moderation_appeals WHERE moderation_action_id = $1`, actionID).Scan(&existingID, &existingStatus)
	if err == nil {
		writeAuthError(w, r, ErrAppealAlreadyExists)
		return
	}
	if !errors.Is(err, sql.ErrNoRows) {
		writeInternalError(w, r, err)
		return
	}
	for _, mediaID := range mediaIDs {
		var ownedID string
		if err := tx.QueryRowContext(r.Context(), `SELECT id FROM media_assets WHERE id = $1 AND owner_id = $2 AND status = 'ready' AND deleted_at IS NULL`, mediaID, user.ID).Scan(&ownedID); err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				writeAuthError(w, r, ErrInvalidAppeal)
				return
			}
			writeInternalError(w, r, err)
			return
		}
	}
	appealID := newPostID()
	now := time.Now().UTC()
	if _, err := tx.ExecContext(r.Context(), `INSERT INTO moderation_appeals (id, user_id, moderation_action_id, target_type, target_id, reason, description, status, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, $6, $7, 'pending', $8, $8)`, appealID, user.ID, actionID, record.TargetType, record.TargetID, strings.TrimSpace(input.Reason), strings.TrimSpace(input.Description), now); err != nil {
		writeInternalError(w, r, err)
		return
	}
	for index, mediaID := range mediaIDs {
		if _, err := tx.ExecContext(r.Context(), `INSERT INTO moderation_appeal_media (appeal_id, media_id, position) VALUES ($1, $2, $3)`, appealID, mediaID, index); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusCreated, map[string]any{"id": appealID, "status": "pending"})
}

func (s *Server) listAppeals(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	limit, err := parseLimit(r.URL.Query().Get("limit"))
	if err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_LIMIT", Message: "limit 无效"})
		return
	}
	items, hasMore, err := s.queryAppeals(r.Context(), s.db, user.ID, strings.TrimSpace(r.URL.Query().Get("status")), limit)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items, "next_cursor": nil, "has_more": hasMore})
}

func (s *Server) getAppeal(w http.ResponseWriter, r *http.Request, appealID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	item, err := s.loadAppeal(r.Context(), s.db, appealID)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrAppealNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if item["user_id"] != user.ID {
		writeAuthError(w, r, ErrPermissionDenied)
		return
	}
	delete(item, "user_id")
	httpserver.WriteJSON(w, http.StatusOK, item)
}

func (s *Server) listModerationAppeals(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if !s.hasAnyPermission(r, user.ID, "report.review") {
		writeAuthError(w, r, ErrPermissionDenied)
		return
	}
	limit, err := parseLimit(r.URL.Query().Get("limit"))
	if err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_LIMIT", Message: "limit 无效"})
		return
	}
	items, hasMore, err := s.queryModerationAppeals(r.Context(), s.db, user.ID, strings.TrimSpace(r.URL.Query().Get("status")), limit)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items, "next_cursor": nil, "has_more": hasMore})
}

func (s *Server) getModerationAppeal(w http.ResponseWriter, r *http.Request, appealID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if !s.hasAnyPermission(r, user.ID, "report.review") {
		writeAuthError(w, r, ErrPermissionDenied)
		return
	}
	item, err := s.loadAppeal(r.Context(), s.db, appealID)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrAppealNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	communityID, err := moderationAppealCommunityID(r.Context(), s.db, appealID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeAuthError(w, r, ErrAppealNotFound)
			return
		}
		writeInternalError(w, r, err)
		return
	}
	if !s.hasScopedPermission(r, user.ID, "report.review", communityID) {
		writeAuthError(w, r, ErrPermissionDenied)
		return
	}
	delete(item, "user_id")
	httpserver.WriteJSON(w, http.StatusOK, item)
}

func (s *Server) reviewAppeal(w http.ResponseWriter, r *http.Request, appealID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if !s.hasAnyPermission(r, user.ID, "report.review") {
		writeAuthError(w, r, ErrPermissionDenied)
		return
	}
	var input appealReviewInput
	if err := decodeJSON(r, &input); err != nil || !validAppealReview(input) {
		writeAuthError(w, r, ErrInvalidAppeal)
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	var targetType, targetID, action, actionID, ownerID, status string
	if err := tx.QueryRowContext(r.Context(), `SELECT a.target_type, a.target_id, ma.action, a.moderation_action_id, a.user_id, a.status FROM moderation_appeals a JOIN moderation_actions ma ON ma.id = a.moderation_action_id WHERE a.id = $1 FOR UPDATE`, appealID).Scan(&targetType, &targetID, &action, &actionID, &ownerID, &status); errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrAppealNotFound)
		return
	} else if err != nil {
		writeInternalError(w, r, err)
		return
	}
	communityID, err := moderationAppealCommunityID(r.Context(), tx, appealID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeAuthError(w, r, ErrAppealNotFound)
			return
		}
		writeInternalError(w, r, err)
		return
	}
	if !hasScopedPermissionQuery(r.Context(), tx, user.ID, "report.review", communityID) {
		writeAuthError(w, r, ErrPermissionDenied)
		return
	}
	if status != "pending" && status != "reviewing" {
		writeAuthError(w, r, ErrAppealAlreadyReviewed)
		return
	}
	if input.Result == "approved" {
		if err := restoreModerationTargetTx(r.Context(), tx, targetType, targetID, action); err != nil {
			writeAuthError(w, r, err)
			return
		}
	}
	now := time.Now().UTC()
	if _, err := tx.ExecContext(r.Context(), `UPDATE moderation_appeals SET status = $1, reviewer_id = $2, reviewer_note = $3, reviewed_at = $4, updated_at = $4 WHERE id = $5`, input.Result, user.ID, strings.TrimSpace(input.Note), now, appealID); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := enqueueNotificationWithDataTx(tx, ownerID, user.ID, "appeal.result", "moderation_appeal", appealID, map[string]any{
		"appeal_id":            appealID,
		"moderation_action_id": actionID,
		"result":               input.Result,
		"reviewer_note":        strings.TrimSpace(input.Note),
		"action":               action,
	}, now); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"id": appealID, "status": input.Result})
}

type sqlQueryer interface {
	QueryRowContext(context.Context, string, ...any) *sql.Row
	QueryContext(context.Context, string, ...any) (*sql.Rows, error)
}

func (s *Server) findModerationAction(ctx context.Context, queryer sqlQueryer, actionID string) (moderationActionRecord, error) {
	var record moderationActionRecord
	err := queryer.QueryRowContext(ctx, `
		SELECT ma.id, ma.action, ma.reason, ma.appealable, mc.target_type, mc.target_id,
		       COALESCE(p.author_id, c.author_id, u.id, ''),
		       COALESCE(NULLIF(p.title, ''), CASE WHEN c.id IS NOT NULL THEN '评论' WHEN u.id IS NOT NULL THEN '账号处理' ELSE '' END),
		       COALESCE(p.content, c.content, u.username, ''), ma.created_at
		FROM moderation_actions ma
		JOIN moderation_cases mc ON mc.id = ma.case_id
		LEFT JOIN posts p ON mc.target_type = 'post' AND p.id = mc.target_id
		LEFT JOIN comments c ON mc.target_type = 'comment' AND c.id = mc.target_id
		LEFT JOIN users u ON mc.target_type = 'user' AND u.id = mc.target_id
		WHERE ma.id = $1`, actionID).Scan(&record.ID, &record.Action, &record.Reason, &record.Appealable, &record.TargetType, &record.TargetID, &record.OwnerID, &record.TargetTitle, &record.TargetContent, &record.CreatedAt)
	return record, err
}

func (s *Server) moderationActionJSON(ctx context.Context, queryer sqlQueryer, record moderationActionRecord) map[string]any {
	mediaIDs := []string{}
	if record.TargetType == "post" {
		rows, err := s.db.QueryContext(ctx, `SELECT pm.media_id FROM post_media pm WHERE pm.post_id = $1 ORDER BY pm.sort_order ASC`, record.TargetID)
		if err == nil {
			defer rows.Close()
			for rows.Next() {
				var mediaID string
				if rows.Scan(&mediaID) == nil {
					mediaIDs = append(mediaIDs, mediaID)
				}
			}
		}
	}
	return map[string]any{
		"id": record.ID, "action": record.Action, "reason": record.Reason,
		"appealable": record.Appealable, "target_type": record.TargetType, "target_id": record.TargetID,
		"target_title": record.TargetTitle, "target_content": record.TargetContent,
		"media_ids": mediaIDs, "created_at": record.CreatedAt,
	}
}

func (s *Server) queryAppeals(ctx context.Context, queryer sqlQueryer, userID, status string, limit int) ([]map[string]any, bool, error) {
	return s.queryAppealsScoped(ctx, queryer, userID, "", status, limit)
}

func (s *Server) queryModerationAppeals(ctx context.Context, queryer sqlQueryer, reviewerID, status string, limit int) ([]map[string]any, bool, error) {
	return s.queryAppealsScoped(ctx, queryer, "", reviewerID, status, limit)
}

func (s *Server) queryAppealsScoped(ctx context.Context, queryer sqlQueryer, userID, reviewerID, status string, limit int) ([]map[string]any, bool, error) {
	args := []any{}
	conditions := []string{}
	if reviewerID != "" {
		args = append(args, reviewerID)
		conditions = append(conditions, `EXISTS (
			SELECT 1
			FROM user_roles ur
			JOIN role_permissions rp ON rp.role_id = ur.role_id
			JOIN permissions perm ON perm.id = rp.permission_id
			LEFT JOIN posts scoped_post ON a.target_type = 'post' AND scoped_post.id = a.target_id
			LEFT JOIN comments scoped_comment ON a.target_type = 'comment' AND scoped_comment.id = a.target_id
			LEFT JOIN posts scoped_comment_post ON scoped_comment_post.id = scoped_comment.post_id
			WHERE ur.user_id = $1
			  AND perm.name = 'report.review'
			  AND (ur.community_id IS NULL OR ur.community_id = COALESCE(scoped_post.community_id, scoped_comment_post.community_id, ''))
		)`)
	}
	if userID != "" {
		args = append(args, userID)
		conditions = append(conditions, "a.user_id = $"+strconv.Itoa(len(args)))
	}
	if status != "" {
		args = append(args, status)
		conditions = append(conditions, "a.status = $"+strconv.Itoa(len(args)))
	}
	where := ""
	if len(conditions) > 0 {
		where = " WHERE " + strings.Join(conditions, " AND ")
	}
	limitPosition := len(args) + 1
	args = append(args, limit+1)
	query := `SELECT a.id, a.user_id, a.moderation_action_id, a.target_type, a.target_id, a.reason, a.description, a.status, a.reviewer_note, a.created_at, a.reviewed_at, ma.action, ma.reason, ma.created_at, COALESCE(NULLIF(p.title, ''), CASE WHEN c.id IS NOT NULL THEN '评论' WHEN u.id IS NOT NULL THEN '账号处理' ELSE '' END), COALESCE(p.content, c.content, u.username, '') FROM moderation_appeals a JOIN moderation_actions ma ON ma.id = a.moderation_action_id LEFT JOIN posts p ON a.target_type = 'post' AND p.id = a.target_id LEFT JOIN comments c ON a.target_type = 'comment' AND c.id = a.target_id LEFT JOIN users u ON a.target_type = 'user' AND u.id = a.target_id` + where + ` ORDER BY a.created_at DESC, a.id DESC LIMIT $` + strconv.Itoa(limitPosition)
	rows, err := queryer.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, false, err
	}
	defer rows.Close()
	items := make([]map[string]any, 0, limit+1)
	for rows.Next() {
		item, err := scanAppealSummary(rows)
		if err != nil {
			return nil, false, err
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, false, err
	}
	hasMore := len(items) > limit
	if hasMore {
		items = items[:limit]
	}
	return items, hasMore, nil
}

func moderationAppealCommunityID(ctx context.Context, queryer queryRowContext, appealID string) (string, error) {
	var communityID string
	err := queryer.QueryRowContext(ctx, `
		SELECT COALESCE(p.community_id, cp.community_id, '')
		FROM moderation_appeals a
		LEFT JOIN posts p ON a.target_type = 'post' AND p.id = a.target_id
		LEFT JOIN comments c ON a.target_type = 'comment' AND c.id = a.target_id
		LEFT JOIN posts cp ON cp.id = c.post_id
		WHERE a.id = $1`, appealID).Scan(&communityID)
	return communityID, err
}

func (s *Server) loadAppeal(ctx context.Context, queryer sqlQueryer, appealID string) (map[string]any, error) {
	var id, userID, actionID, targetType, targetID, reason, description, status, reviewerID, reviewerNote string
	var createdAt, updatedAt, actionCreatedAt time.Time
	var reviewedAt sql.NullTime
	var action, actionReason, targetTitle, targetContent string
	var appealable bool
	err := queryer.QueryRowContext(ctx, `SELECT a.id, a.user_id, a.moderation_action_id, a.target_type, a.target_id, a.reason, a.description, a.status, COALESCE(a.reviewer_id, ''), a.reviewer_note, a.created_at, a.reviewed_at, a.updated_at, ma.action, ma.reason, ma.appealable, ma.created_at, COALESCE(NULLIF(p.title, ''), CASE WHEN c.id IS NOT NULL THEN '评论' WHEN u.id IS NOT NULL THEN '账号处理' ELSE '' END), COALESCE(p.content, c.content, u.username, '') FROM moderation_appeals a JOIN moderation_actions ma ON ma.id = a.moderation_action_id LEFT JOIN posts p ON a.target_type = 'post' AND p.id = a.target_id LEFT JOIN comments c ON a.target_type = 'comment' AND c.id = a.target_id LEFT JOIN users u ON a.target_type = 'user' AND u.id = a.target_id WHERE a.id = $1`, appealID).Scan(&id, &userID, &actionID, &targetType, &targetID, &reason, &description, &status, &reviewerID, &reviewerNote, &createdAt, &reviewedAt, &updatedAt, &action, &actionReason, &appealable, &actionCreatedAt, &targetTitle, &targetContent)
	if err != nil {
		return nil, err
	}
	mediaIDs := []string{}
	rows, err := s.db.QueryContext(ctx, `SELECT media_id FROM moderation_appeal_media WHERE appeal_id = $1 ORDER BY position ASC`, appealID)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var mediaID string
		if err := rows.Scan(&mediaID); err != nil {
			rows.Close()
			return nil, err
		}
		mediaIDs = append(mediaIDs, mediaID)
	}
	if err := rows.Close(); err != nil {
		return nil, err
	}
	item := map[string]any{
		"id": id, "user_id": userID, "moderation_action_id": actionID, "target_type": targetType, "target_id": targetID,
		"reason": reason, "description": description, "status": status, "reviewer_id": reviewerID, "reviewer_note": reviewerNote,
		"created_at": createdAt, "updated_at": updatedAt, "action": action, "action_reason": actionReason,
		"appealable": appealable, "action_created_at": actionCreatedAt, "target_title": targetTitle, "target_content": targetContent,
		"media_ids": mediaIDs,
	}
	if reviewedAt.Valid {
		item["reviewed_at"] = reviewedAt.Time
	}
	return item, nil
}

type rowScanner interface{ Scan(dest ...any) error }

func scanAppealSummary(row rowScanner) (map[string]any, error) {
	var id, userID, actionID, targetType, targetID, reason, description, status, reviewerNote string
	var createdAt, actionCreatedAt time.Time
	var reviewedAt sql.NullTime
	var action, actionReason, targetTitle, targetContent string
	if err := row.Scan(&id, &userID, &actionID, &targetType, &targetID, &reason, &description, &status, &reviewerNote, &createdAt, &reviewedAt, &action, &actionReason, &actionCreatedAt, &targetTitle, &targetContent); err != nil {
		return nil, err
	}
	item := map[string]any{"id": id, "user_id": userID, "moderation_action_id": actionID, "target_type": targetType, "target_id": targetID, "reason": reason, "description": description, "status": status, "reviewer_note": reviewerNote, "created_at": createdAt, "action": action, "action_reason": actionReason, "action_created_at": actionCreatedAt, "target_title": targetTitle, "target_content": targetContent}
	if reviewedAt.Valid {
		item["reviewed_at"] = reviewedAt.Time
	}
	return item, nil
}

func restoreModerationTargetTx(ctx context.Context, tx *sql.Tx, targetType, targetID, action string) error {
	switch targetType {
	case "post":
		var query string
		if action == "delete" {
			query = `UPDATE posts SET post_status = 'published', deleted_at = NULL, publication_status = 'published', deleted_by = NULL, delete_reason = '', moderation_status = 'normal', moderation_case_id = NULL, visibility_reason = '', published_at = COALESCE(published_at, now()), updated_at = now() WHERE id = $1`
		} else {
			query = `UPDATE posts SET post_status = 'published', moderation_status = 'normal', moderation_case_id = NULL, visibility_reason = '', updated_at = now() WHERE id = $1`
		}
		result, err := tx.ExecContext(ctx, query, targetID)
		if err != nil {
			return err
		}
		count, err := result.RowsAffected()
		if err != nil {
			return err
		}
		if count != 1 {
			return ErrAppealNotFound
		}
		return nil
	case "comment":
		if action != "delete" {
			_, err := tx.ExecContext(ctx, `UPDATE comments SET moderation_status = 'normal', moderation_case_id = NULL, visibility_reason = '', updated_at = now() WHERE id = $1`, targetID)
			return err
		}
		var postID, parentID string
		var deletedAt sql.NullTime
		if err := tx.QueryRowContext(ctx, `SELECT post_id, COALESCE(parent_id, ''), deleted_at FROM comments WHERE id = $1 FOR UPDATE`, targetID).Scan(&postID, &parentID, &deletedAt); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, `UPDATE comments SET deleted_at = NULL, publication_status = 'published', deleted_by = NULL, delete_reason = '', moderation_status = 'normal', moderation_case_id = NULL, visibility_reason = '', updated_at = now() WHERE id = $1`, targetID); err != nil {
			return err
		}
		if deletedAt.Valid {
			if _, err := tx.ExecContext(ctx, `UPDATE posts SET comment_count = comment_count + 1, updated_at = now() WHERE id = $1`, postID); err != nil {
				return err
			}
			if parentID != "" {
				if _, err := tx.ExecContext(ctx, `UPDATE comments SET reply_count = reply_count + 1, updated_at = now() WHERE id = $1`, parentID); err != nil {
					return err
				}
			}
		}
		return nil
	case "user":
		result, err := tx.ExecContext(ctx, `UPDATE users SET status = 'active', updated_at = now() WHERE id = $1 AND deleted_at IS NULL`, targetID)
		if err != nil {
			return err
		}
		count, err := result.RowsAffected()
		if err != nil {
			return err
		}
		if count != 1 {
			return ErrAppealNotFound
		}
		return nil
	default:
		return ErrInvalidAppeal
	}
}

func validAppealInput(input appealCreateInput) bool {
	return strings.TrimSpace(input.Reason) != "" && len([]rune(input.Reason)) <= 100 && len([]rune(input.Description)) <= 3000
}

func validAppealReview(input appealReviewInput) bool {
	if input.Result != "approved" && input.Result != "rejected" {
		return false
	}
	return len([]rune(input.Note)) <= 2000 && (input.Result != "rejected" || strings.TrimSpace(input.Note) != "")
}

func uniqueStrings(values []string) []string {
	seen := make(map[string]struct{}, len(values))
	result := make([]string, 0, len(values))
	for _, value := range values {
		value = strings.TrimSpace(value)
		if value == "" {
			continue
		}
		if _, exists := seen[value]; exists {
			continue
		}
		seen[value] = struct{}{}
		result = append(result, value)
	}
	return result
}
