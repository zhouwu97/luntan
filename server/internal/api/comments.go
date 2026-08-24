package api

import (
	"context"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/zhouwu97/luntan/server/internal/auth"
	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

var (
	ErrCommentNotFound       = errors.New("comment not found")
	ErrCommentParentNotFound = errors.New("comment parent not found")
	ErrInvalidComment        = errors.New("invalid comment")
)

type commentResponse struct {
	ID            string              `json:"id"`
	PostID        string              `json:"post_id"`
	Author        userSummary         `json:"author"`
	RootID        *string             `json:"root_id,omitempty"`
	ParentID      *string             `json:"parent_id,omitempty"`
	ReplyToUserID *string             `json:"reply_to_user_id,omitempty"`
	Content       string              `json:"content"`
	LikeCount     int64               `json:"like_count"`
	ReplyCount    int64               `json:"reply_count"`
	Publication   string              `json:"publication_status"`
	Moderation    string              `json:"moderation_status"`
	CreatedAt     time.Time           `json:"created_at"`
	UpdatedAt     time.Time           `json:"updated_at"`
	ViewerState   *viewerCommentState `json:"viewer_state,omitempty"`
}

type viewerCommentState struct {
	HasLiked bool `json:"has_liked"`
}

type commentInput struct {
	Content       string `json:"content"`
	ParentID      string `json:"parent_id"`
	ReplyToUserID string `json:"reply_to_user_id"`
}

type commentCursor struct {
	CreatedAt time.Time `json:"created_at"`
	ID        string    `json:"id"`
}

func (s *Server) listComments(w http.ResponseWriter, r *http.Request, postID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	limit, err := parseLimit(r.URL.Query().Get("limit"))
	if err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_LIMIT", Message: "limit 必须是 1 到 50 之间的整数"})
		return
	}
	var exists string
	err = s.db.QueryRowContext(r.Context(), `SELECT id FROM posts WHERE id = $1 AND publication_status = 'published' AND moderation_status = 'normal' AND deleted_at IS NULL`, postID).Scan(&exists)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrPostNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	var cursor *commentCursor
	if value := r.URL.Query().Get("cursor"); value != "" {
		decoded, decodeErr := decodeCommentCursor(value)
		if decodeErr != nil {
			httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_CURSOR", Message: "cursor 无效"})
			return
		}
		cursor = &decoded
	}
	args := []any{postID}
	viewerExpression := "false"
	viewer, hasViewer := s.optionalAuthenticatedUser(r.Context(), r)
	if hasViewer {
		viewerExpression = fmt.Sprintf(`EXISTS (
			SELECT 1 FROM comment_reactions cr
			WHERE cr.comment_id = c.id AND cr.user_id = $%d AND cr.reaction_type = 'like'
		)`, len(args)+1)
		args = append(args, viewer.ID)
		hasViewer = true
	}
	query := fmt.Sprintf(`
		SELECT c.id, c.post_id, c.author_id, u.username, COALESCE(up.nickname, u.username),
		       COALESCE(c.root_id, ''), COALESCE(c.parent_id, ''), COALESCE(c.reply_to_user_id, ''),
		       c.content, c.like_count, c.reply_count, c.publication_status, c.moderation_status,
		       c.created_at, c.updated_at, %s AS viewer_has_liked
		FROM comments c
		JOIN users u ON u.id = c.author_id
		LEFT JOIN user_profiles up ON up.user_id = u.id
		WHERE c.post_id = $1 AND c.deleted_at IS NULL AND c.publication_status = 'published' AND c.moderation_status = 'normal'`, viewerExpression)
	if hasViewer {
		query += fmt.Sprintf(` AND NOT EXISTS (
			SELECT 1 FROM blocks b
			WHERE (b.blocker_id = $%d AND b.blocked_id = c.author_id)
			   OR (b.blocker_id = c.author_id AND b.blocked_id = $%d)
		)`, len(args)+1, len(args)+1)
		args = append(args, viewer.ID)
	}
	if cursor != nil {
		query += fmt.Sprintf(" AND (c.created_at, c.id) > ($%d, $%d)", len(args)+1, len(args)+2)
		args = append(args, cursor.CreatedAt, cursor.ID)
	}
	limitPosition := len(args) + 1
	query += fmt.Sprintf(" ORDER BY c.created_at ASC, c.id ASC LIMIT $%d", limitPosition)
	args = append(args, limit+1)
	rows, err := s.db.QueryContext(r.Context(), query, args...)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()
	items := make([]commentResponse, 0, limit+1)
	for rows.Next() {
		var item commentResponse
		var authorID, rootID, parentID, replyTo string
		var viewerHasLiked bool
		if err := rows.Scan(&item.ID, &item.PostID, &authorID, &item.Author.Username, &item.Author.Nickname, &rootID, &parentID, &replyTo, &item.Content, &item.LikeCount, &item.ReplyCount, &item.Publication, &item.Moderation, &item.CreatedAt, &item.UpdatedAt, &viewerHasLiked); err != nil {
			writeInternalError(w, r, err)
			return
		}
		item.Author.ID = authorID
		item.RootID, item.ParentID, item.ReplyToUserID = optionalString(rootID), optionalString(parentID), optionalString(replyTo)
		if hasViewer {
			item.ViewerState = &viewerCommentState{HasLiked: viewerHasLiked}
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	hasMore := len(items) > limit
	if hasMore {
		items = items[:limit]
	}
	var nextCursor any
	if hasMore && len(items) > 0 {
		encoded, encodeErr := encodeCommentCursor(commentCursor{CreatedAt: items[len(items)-1].CreatedAt, ID: items[len(items)-1].ID})
		if encodeErr != nil {
			writeInternalError(w, r, encodeErr)
			return
		}
		nextCursor = encoded
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items, "next_cursor": nextCursor, "has_more": hasMore})
}

func (s *Server) listCommentReplies(w http.ResponseWriter, r *http.Request, commentID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	limit, err := parseLimit(r.URL.Query().Get("limit"))
	if err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_LIMIT", Message: "limit 必须是 1 到 50 之间的整数"})
		return
	}
	var rootID string
	err = s.db.QueryRowContext(r.Context(), `SELECT COALESCE(root_id, id) FROM comments WHERE id = $1 AND deleted_at IS NULL`, commentID).Scan(&rootID)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrCommentNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	var cursor *commentCursor
	if value := r.URL.Query().Get("cursor"); value != "" {
		decoded, decodeErr := decodeCommentCursor(value)
		if decodeErr != nil {
			httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_CURSOR", Message: "cursor 无效"})
			return
		}
		cursor = &decoded
	}
	args := []any{rootID}
	viewerExpression := "false"
	viewer, hasViewer := s.optionalAuthenticatedUser(r.Context(), r)
	if hasViewer {
		viewerExpression = fmt.Sprintf(`EXISTS (
			SELECT 1 FROM comment_reactions cr
			WHERE cr.comment_id = c.id AND cr.user_id = $%d AND cr.reaction_type = 'like'
		)`, len(args)+1)
		args = append(args, viewer.ID)
	}
	query := fmt.Sprintf(`
		SELECT c.id, c.post_id, c.author_id, u.username, COALESCE(up.nickname, u.username),
		       COALESCE(c.root_id, ''), COALESCE(c.parent_id, ''), COALESCE(c.reply_to_user_id, ''),
		       c.content, c.like_count, c.reply_count, c.publication_status, c.moderation_status,
		       c.created_at, c.updated_at, %s AS viewer_has_liked
		FROM comments c
		JOIN users u ON u.id = c.author_id
		LEFT JOIN user_profiles up ON up.user_id = u.id
		WHERE c.root_id = $1 AND c.id <> $1 AND c.deleted_at IS NULL
		  AND c.publication_status = 'published' AND c.moderation_status = 'normal'`, viewerExpression)
	if hasViewer {
		query += fmt.Sprintf(` AND NOT EXISTS (
			SELECT 1 FROM blocks b
			WHERE (b.blocker_id = $%d AND b.blocked_id = c.author_id)
			   OR (b.blocker_id = c.author_id AND b.blocked_id = $%d)
		)`, len(args)+1, len(args)+1)
		args = append(args, viewer.ID)
	}
	if cursor != nil {
		query += fmt.Sprintf(" AND (c.created_at, c.id) > ($%d, $%d)", len(args)+1, len(args)+2)
		args = append(args, cursor.CreatedAt, cursor.ID)
	}
	limitPosition := len(args) + 1
	query += fmt.Sprintf(" ORDER BY c.created_at ASC, c.id ASC LIMIT $%d", limitPosition)
	args = append(args, limit+1)
	rows, err := s.db.QueryContext(r.Context(), query, args...)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()
	items := make([]commentResponse, 0, limit+1)
	for rows.Next() {
		var item commentResponse
		var authorID, rowRootID, parentID, replyTo string
		var viewerHasLiked bool
		if err := rows.Scan(&item.ID, &item.PostID, &authorID, &item.Author.Username, &item.Author.Nickname, &rowRootID, &parentID, &replyTo, &item.Content, &item.LikeCount, &item.ReplyCount, &item.Publication, &item.Moderation, &item.CreatedAt, &item.UpdatedAt, &viewerHasLiked); err != nil {
			writeInternalError(w, r, err)
			return
		}
		item.Author.ID = authorID
		item.RootID, item.ParentID, item.ReplyToUserID = optionalString(rowRootID), optionalString(parentID), optionalString(replyTo)
		if hasViewer {
			item.ViewerState = &viewerCommentState{HasLiked: viewerHasLiked}
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	hasMore := len(items) > limit
	if hasMore {
		items = items[:limit]
	}
	var nextCursor any
	if hasMore && len(items) > 0 {
		encoded, encodeErr := encodeCommentCursor(commentCursor{CreatedAt: items[len(items)-1].CreatedAt, ID: items[len(items)-1].ID})
		if encodeErr != nil {
			writeInternalError(w, r, encodeErr)
			return
		}
		nextCursor = encoded
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items, "next_cursor": nextCursor, "has_more": hasMore})
}

func (s *Server) createComment(w http.ResponseWriter, r *http.Request, postID, forcedParentID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	s.createCommentForUser(w, r, user, postID, forcedParentID)
}

func (s *Server) createReply(w http.ResponseWriter, r *http.Request, parentID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	var postID string
	err := s.db.QueryRowContext(r.Context(), `SELECT post_id FROM comments WHERE id = $1 AND deleted_at IS NULL`, parentID).Scan(&postID)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrCommentParentNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	s.createCommentForUser(w, r, user, postID, parentID)
}

func (s *Server) createCommentForUser(w http.ResponseWriter, r *http.Request, user auth.User, postID, forcedParentID string) {
	idempotencyKey := strings.TrimSpace(r.Header.Get("Idempotency-Key"))
	if idempotencyKey == "" || len(idempotencyKey) > 128 {
		writeAuthError(w, r, ErrIdempotencyKeyRequired)
		return
	}
	var input commentInput
	if err := decodeJSON(r, &input); err != nil {
		writeAuthError(w, r, ErrInvalidComment)
		return
	}
	input.Content = strings.TrimSpace(input.Content)
	if input.Content == "" || len([]rune(input.Content)) > 5000 {
		writeAuthError(w, r, ErrInvalidComment)
		return
	}
	parentID := strings.TrimSpace(forcedParentID)
	if parentID == "" {
		parentID = strings.TrimSpace(input.ParentID)
	}
	var relationTargetID string
	if parentID != "" {
		if err := s.db.QueryRowContext(r.Context(), `SELECT author_id FROM comments WHERE id = $1 AND deleted_at IS NULL`, parentID).Scan(&relationTargetID); err != nil && !errors.Is(err, sql.ErrNoRows) {
			writeInternalError(w, r, err)
			return
		}
	} else if err := s.db.QueryRowContext(r.Context(), `SELECT author_id FROM posts WHERE id = $1 AND deleted_at IS NULL`, postID).Scan(&relationTargetID); err != nil && !errors.Is(err, sql.ErrNoRows) {
		writeInternalError(w, r, err)
		return
	}
	if relationTargetID != "" {
		blocked, err := usersBlockEachOther(r.Context(), s.db, user.ID, relationTargetID)
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
		if blocked {
			writeAuthError(w, r, ErrBlocked)
			return
		}
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	commentID := newPostID()
	var existingCommentID string
	err = tx.QueryRowContext(r.Context(), `
		INSERT INTO comment_idempotency_keys (user_id, idempotency_key, comment_id, created_at)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT (user_id, idempotency_key) DO NOTHING
		RETURNING comment_id`, user.ID, idempotencyKey, commentID, time.Now().UTC()).Scan(&existingCommentID)
	if errors.Is(err, sql.ErrNoRows) {
		if err := tx.QueryRowContext(r.Context(), `SELECT comment_id FROM comment_idempotency_keys WHERE user_id = $1 AND idempotency_key = $2`, user.ID, idempotencyKey).Scan(&existingCommentID); err != nil {
			writeInternalError(w, r, err)
			return
		}
		response, loadErr := loadCommentResponseTx(r.Context(), tx, existingCommentID)
		if loadErr != nil {
			writeInternalError(w, r, loadErr)
			return
		}
		if err := tx.Commit(); err != nil {
			writeInternalError(w, r, err)
			return
		}
		httpserver.WriteJSON(w, http.StatusOK, response)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	var postExists string
	err = tx.QueryRowContext(r.Context(), `SELECT id FROM posts WHERE id = $1 AND publication_status = 'published' AND moderation_status = 'normal' AND deleted_at IS NULL FOR UPDATE`, postID).Scan(&postExists)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrPostNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	rootID := commentID
	if parentID != "" {
		var parentPostID, parentRootID, parentAuthorID string
		err = tx.QueryRowContext(r.Context(), `SELECT post_id, COALESCE(root_id, id), author_id FROM comments WHERE id = $1 AND deleted_at IS NULL`, parentID).Scan(&parentPostID, &parentRootID, &parentAuthorID)
		if err != nil && !errors.Is(err, sql.ErrNoRows) {
			writeInternalError(w, r, err)
			return
		}
		if errors.Is(err, sql.ErrNoRows) || parentPostID != postID {
			writeAuthError(w, r, ErrCommentParentNotFound)
			return
		}
		rootID = parentRootID
		if input.ReplyToUserID == "" {
			input.ReplyToUserID = parentAuthorID
		}
	}
	now := time.Now().UTC()
	if _, err := tx.ExecContext(r.Context(), `UPDATE comment_idempotency_keys SET comment_id = $1 WHERE user_id = $2 AND idempotency_key = $3`, commentID, user.ID, idempotencyKey); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if _, err := tx.ExecContext(r.Context(), `INSERT INTO comments (id, post_id, author_id, root_id, parent_id, reply_to_user_id, content, publication_status, moderation_status, created_at, updated_at, published_at) VALUES ($1, $2, $3, $4, NULLIF($5, ''), NULLIF($6, ''), $7, 'published', 'normal', $8, $8, $8)`, commentID, postID, user.ID, rootID, parentID, strings.TrimSpace(input.ReplyToUserID), input.Content, now); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if parentID != "" {
		if _, err := tx.ExecContext(r.Context(), `UPDATE comments SET reply_count = reply_count + 1, updated_at = $1 WHERE id = $2`, now, parentID); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	if _, err := tx.ExecContext(r.Context(), `UPDATE posts SET comment_count = comment_count + 1, updated_at = $1 WHERE id = $2`, now, postID); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if parentID != "" && input.ReplyToUserID != "" {
		if err := enqueueNotificationTx(tx, input.ReplyToUserID, user.ID, "reply", "comment", parentID, now); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	if err := awardPointsTx(r.Context(), tx, user.ID, "comment", "参与回复", "comment:create:"+commentID, s.pointRewards.CommentCreate); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	response := commentResponse{ID: commentID, PostID: postID, Author: userSummary{ID: user.ID, Username: user.Username, Nickname: user.Nickname}, RootID: optionalString(rootID), ParentID: optionalString(parentID), ReplyToUserID: optionalString(strings.TrimSpace(input.ReplyToUserID)), Content: input.Content, Publication: "published", Moderation: "normal", CreatedAt: now, UpdatedAt: now, ViewerState: &viewerCommentState{}}
	httpserver.WriteJSON(w, http.StatusCreated, response)
}

func loadCommentResponseTx(ctx context.Context, tx *sql.Tx, commentID string) (commentResponse, error) {
	var response commentResponse
	var authorID, rootID, parentID, replyTo string
	err := tx.QueryRowContext(ctx, `
		SELECT c.id, c.post_id, c.author_id, u.username, COALESCE(up.nickname, u.username),
		       COALESCE(c.root_id, ''), COALESCE(c.parent_id, ''), COALESCE(c.reply_to_user_id, ''),
		       c.content, c.like_count, c.reply_count, c.publication_status, c.moderation_status,
		       c.created_at, c.updated_at
		FROM comments c
		JOIN users u ON u.id = c.author_id
		LEFT JOIN user_profiles up ON up.user_id = c.author_id
		WHERE c.id = $1`, commentID).Scan(
		&response.ID, &response.PostID, &authorID, &response.Author.Username, &response.Author.Nickname,
		&rootID, &parentID, &replyTo, &response.Content, &response.LikeCount, &response.ReplyCount,
		&response.Publication, &response.Moderation, &response.CreatedAt, &response.UpdatedAt,
	)
	if err != nil {
		return commentResponse{}, err
	}
	response.Author.ID = authorID
	response.RootID = optionalString(rootID)
	response.ParentID = optionalString(parentID)
	response.ReplyToUserID = optionalString(replyTo)
	response.ViewerState = &viewerCommentState{}
	return response, nil
}

func (s *Server) updateComment(w http.ResponseWriter, r *http.Request, commentID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	var input commentInput
	if err := decodeJSON(r, &input); err != nil {
		writeAuthError(w, r, ErrInvalidComment)
		return
	}
	input.Content = strings.TrimSpace(input.Content)
	if input.Content == "" || len([]rune(input.Content)) > 5000 {
		writeAuthError(w, r, ErrInvalidComment)
		return
	}
	var authorID string
	err := s.db.QueryRowContext(r.Context(), `SELECT author_id FROM comments WHERE id = $1 AND deleted_at IS NULL`, commentID).Scan(&authorID)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrCommentNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if authorID != user.ID {
		writeAuthError(w, r, ErrForbidden)
		return
	}
	if _, err := s.db.ExecContext(r.Context(), `UPDATE comments SET content = $1, updated_at = now() WHERE id = $2 AND deleted_at IS NULL`, input.Content, commentID); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"id": commentID, "content": input.Content})
}

func (s *Server) deleteComment(w http.ResponseWriter, r *http.Request, commentID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	var authorID string
	var deletedAt sql.NullTime
	err = tx.QueryRowContext(r.Context(), `SELECT author_id, deleted_at FROM comments WHERE id = $1 FOR UPDATE`, commentID).Scan(&authorID, &deletedAt)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrCommentNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if authorID != user.ID {
		writeAuthError(w, r, ErrForbidden)
		return
	}
	if !deletedAt.Valid {
		if _, err := softDeleteCommentTx(r.Context(), tx, commentID, user.ID, "", ""); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// softDeleteCommentTx 是用户删除和审核删除共用的计数守恒入口。
// 它只在首次软删除时扣减帖子/父评论聚合计数，重复调用不会重复扣减。
func softDeleteCommentTx(ctx context.Context, tx *sql.Tx, commentID, deletedBy, reason, caseID string) (bool, error) {
	var postID, parentID string
	var deletedAt sql.NullTime
	err := tx.QueryRowContext(ctx, `SELECT post_id, COALESCE(parent_id, ''), deleted_at FROM comments WHERE id = $1 FOR UPDATE`, commentID).Scan(&postID, &parentID, &deletedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return false, ErrCommentNotFound
	}
	if err != nil {
		return false, err
	}
	if deletedAt.Valid {
		return false, nil
	}
	result, err := tx.ExecContext(ctx, `UPDATE comments SET deleted_at = now(), publication_status = 'deleted', deleted_by = NULLIF($2, ''), delete_reason = $3, moderation_case_id = NULLIF($4, ''), updated_at = now() WHERE id = $1 AND deleted_at IS NULL`, commentID, deletedBy, strings.TrimSpace(reason), caseID)
	if err != nil {
		return false, err
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return false, err
	}
	if affected == 0 {
		return false, nil
	}
	if parentID != "" {
		if _, err := tx.ExecContext(ctx, `UPDATE comments SET reply_count = GREATEST(reply_count - 1, 0), updated_at = now() WHERE id = $1`, parentID); err != nil {
			return false, err
		}
	}
	if _, err := tx.ExecContext(ctx, `UPDATE posts SET comment_count = GREATEST(comment_count - 1, 0), updated_at = now() WHERE id = $1`, postID); err != nil {
		return false, err
	}
	return true, nil
}

func encodeCommentCursor(cursor commentCursor) (string, error) {
	data, err := json.Marshal(cursor)
	if err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(data), nil
}

func decodeCommentCursor(value string) (commentCursor, error) {
	data, err := base64.RawURLEncoding.DecodeString(value)
	if err != nil {
		return commentCursor{}, err
	}
	var cursor commentCursor
	if err := json.Unmarshal(data, &cursor); err != nil || cursor.ID == "" || cursor.CreatedAt.IsZero() {
		return commentCursor{}, errors.New("invalid comment cursor")
	}
	return cursor, nil
}

func optionalString(value string) *string {
	if value == "" {
		return nil
	}
	copy := value
	return &copy
}
