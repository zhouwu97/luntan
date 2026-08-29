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

type commentAttachmentResponse struct {
	ID           string `json:"id"`
	Type         string `json:"type"`
	URL          string `json:"url,omitempty"`
	ThumbnailURL string `json:"thumbnail_url,omitempty"`
	Width        int    `json:"width,omitempty"`
	Height       int    `json:"height,omitempty"`
	StickerID    string `json:"sticker_id,omitempty"`
}

type commentAttachmentInput struct {
	Type    string `json:"type"`
	MediaID string `json:"media_id"`
}

type commentResponse struct {
	ID            string                      `json:"id"`
	PostID        string                      `json:"post_id"`
	Author        userSummary                 `json:"author"`
	ReplyToUser   *userSummary                `json:"reply_to_user,omitempty"`
	RootID        *string                     `json:"root_id,omitempty"`
	ParentID      *string                     `json:"parent_id,omitempty"`
	ReplyToUserID *string                     `json:"reply_to_user_id,omitempty"`
	Content       string                      `json:"content"`
	Media         []postMediaResponse         `json:"media,omitempty"`
	StickerID     *string                     `json:"sticker_id,omitempty"`
	Attachments   []commentAttachmentResponse `json:"attachments,omitempty"`
	LikeCount     int64                       `json:"like_count"`
	ReplyCount    int64                       `json:"reply_count"`
	Publication   string                      `json:"publication_status"`
	Moderation    string                      `json:"moderation_status"`
	CreatedAt     time.Time                   `json:"created_at"`
	UpdatedAt     time.Time                   `json:"updated_at"`
	ViewerState   *viewerCommentState         `json:"viewer_state,omitempty"`
}

type viewerCommentState struct {
	HasLiked bool `json:"has_liked"`
}

type commentInput struct {
	Content       string                   `json:"content"`
	ParentID      string                   `json:"parent_id"`
	ReplyToUserID string                   `json:"reply_to_user_id"`
	MediaIDs      []string                 `json:"media_ids"`
	StickerID     string                   `json:"sticker_id"`
	Attachments   []commentAttachmentInput `json:"attachments"`
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
		       c.content, COALESCE(c.sticker_id, ''), c.like_count, c.reply_count, c.publication_status, c.moderation_status,
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
		var authorID, rootID, parentID, replyTo, stickerID string
		var viewerHasLiked bool
		if err := rows.Scan(&item.ID, &item.PostID, &authorID, &item.Author.Username, &item.Author.Nickname, &rootID, &parentID, &replyTo, &item.Content, &stickerID, &item.LikeCount, &item.ReplyCount, &item.Publication, &item.Moderation, &item.CreatedAt, &item.UpdatedAt, &viewerHasLiked); err != nil {
			writeInternalError(w, r, err)
			return
		}
		item.Author.ID = authorID
		item.RootID, item.ParentID, item.ReplyToUserID = optionalString(rootID), optionalString(parentID), optionalString(replyTo)
		item.StickerID = optionalString(stickerID)
		if err := enrichReplyToUser(r.Context(), s.db, &item); err != nil {
			writeInternalError(w, r, err)
			return
		}
		if hasViewer {
			item.ViewerState = &viewerCommentState{HasLiked: viewerHasLiked}
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := enrichCommentsMedia(r.Context(), s.db, items); err != nil {
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
		       c.content, COALESCE(c.sticker_id, ''), c.like_count, c.reply_count, c.publication_status, c.moderation_status,
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
		var authorID, rowRootID, parentID, replyTo, stickerID string
		var viewerHasLiked bool
		if err := rows.Scan(&item.ID, &item.PostID, &authorID, &item.Author.Username, &item.Author.Nickname, &rowRootID, &parentID, &replyTo, &item.Content, &stickerID, &item.LikeCount, &item.ReplyCount, &item.Publication, &item.Moderation, &item.CreatedAt, &item.UpdatedAt, &viewerHasLiked); err != nil {
			writeInternalError(w, r, err)
			return
		}
		item.Author.ID = authorID
		item.RootID, item.ParentID, item.ReplyToUserID = optionalString(rowRootID), optionalString(parentID), optionalString(replyTo)
		item.StickerID = optionalString(stickerID)
		if err := enrichReplyToUser(r.Context(), s.db, &item); err != nil {
			writeInternalError(w, r, err)
			return
		}
		if hasViewer {
			item.ViewerState = &viewerCommentState{HasLiked: viewerHasLiked}
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := enrichCommentsMedia(r.Context(), s.db, items); err != nil {
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
	if !s.requireCapability(w, r, user, capComment) {
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
	if !s.requireCapability(w, r, user, capComment) {
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
	if len([]rune(input.Content)) > 5000 {
		writeAuthError(w, r, ErrInvalidComment)
		return
	}
	mediaIDs := make([]string, 0, len(input.MediaIDs)+len(input.Attachments))
	for _, id := range input.MediaIDs {
		trimmed := strings.TrimSpace(id)
		if trimmed != "" && !sliceContains(mediaIDs, trimmed) {
			mediaIDs = append(mediaIDs, trimmed)
		}
	}
	for _, att := range input.Attachments {
		if att.Type == "image" || att.Type == "" {
			trimmed := strings.TrimSpace(att.MediaID)
			if trimmed != "" && !sliceContains(mediaIDs, trimmed) {
				mediaIDs = append(mediaIDs, trimmed)
			}
		}
	}
	stickerID := strings.TrimSpace(input.StickerID)
	if stickerID == "" {
		for _, att := range input.Attachments {
			if att.Type == "sticker" && strings.TrimSpace(att.MediaID) != "" {
				stickerID = strings.TrimSpace(att.MediaID)
				break
			}
		}
	}
	if input.Content == "" && len(mediaIDs) == 0 && stickerID == "" {
		writeAuthError(w, r, ErrInvalidComment)
		return
	}
	if len(mediaIDs) > 9 || len(stickerID) > 128 || (len(mediaIDs) > 0 && stickerID != "") {
		writeAuthError(w, r, ErrInvalidComment)
		return
	}

	for _, mid := range mediaIDs {
		var ownerID, status, mimeType string
		err := s.db.QueryRowContext(r.Context(), `SELECT owner_id, status, mime_type FROM media_assets WHERE id = $1 AND deleted_at IS NULL`, mid).Scan(&ownerID, &status, &mimeType)
		if errors.Is(err, sql.ErrNoRows) || ownerID != user.ID || status != "ready" || !strings.HasPrefix(strings.ToLower(mimeType), "image/") {
			writeAuthError(w, r, ErrInvalidMedia)
			return
		}
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
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
	if _, err := tx.ExecContext(r.Context(), `
		INSERT INTO comments (id, post_id, author_id, root_id, parent_id, reply_to_user_id, content, sticker_id, publication_status, moderation_status, created_at, updated_at, published_at)
		VALUES ($1, $2, $3, $4, NULLIF($5, ''), NULLIF($6, ''), $7, NULLIF($8, ''), 'published', 'normal', $9, $9, $9)`,
		commentID, postID, user.ID, rootID, parentID, strings.TrimSpace(input.ReplyToUserID), input.Content, stickerID, now,
	); err != nil {
		writeInternalError(w, r, err)
		return
	}
	for idx, mid := range mediaIDs {
		if _, err := tx.ExecContext(r.Context(), `INSERT INTO comment_media (comment_id, media_id, sort_order, created_at) VALUES ($1, $2, $3, $4)`, commentID, mid, idx, now); err != nil {
			writeInternalError(w, r, err)
			return
		}
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
		if err := enqueueNotificationWithDataTx(tx, input.ReplyToUserID, user.ID, "reply", "post", postID, map[string]any{"comment_id": parentID}, now); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	if err := awardPointsTx(r.Context(), tx, user.ID, "comment", "参与回复", "comment:create:"+commentID, s.pointRewards.CommentCreate); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := awardExperienceTx(r.Context(), tx, user.ID, "comment", "参与回复", "comment:create:"+commentID, s.experienceRewards.CommentCreate, s.experienceRewards.CommentCreateDailyLimit); err != nil {
		writeInternalError(w, r, err)
		return
	}

	response, err := loadCommentResponseTx(r.Context(), tx, commentID)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}

	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusCreated, response)
}

func loadCommentResponseTx(ctx context.Context, tx *sql.Tx, commentID string) (commentResponse, error) {
	var response commentResponse
	var authorID, rootID, parentID, replyTo, stickerID string
	err := tx.QueryRowContext(ctx, `
		SELECT c.id, c.post_id, c.author_id, u.username, COALESCE(up.nickname, u.username),
		       COALESCE(c.root_id, ''), COALESCE(c.parent_id, ''), COALESCE(c.reply_to_user_id, ''),
		       c.content, COALESCE(c.sticker_id, ''), c.like_count, c.reply_count, c.publication_status, c.moderation_status,
		       c.created_at, c.updated_at
		FROM comments c
		JOIN users u ON u.id = c.author_id
		LEFT JOIN user_profiles up ON up.user_id = c.author_id
		WHERE c.id = $1`, commentID).Scan(
		&response.ID, &response.PostID, &authorID, &response.Author.Username, &response.Author.Nickname,
		&rootID, &parentID, &replyTo, &response.Content, &stickerID, &response.LikeCount, &response.ReplyCount,
		&response.Publication, &response.Moderation, &response.CreatedAt, &response.UpdatedAt,
	)
	if err != nil {
		return commentResponse{}, err
	}
	response.Author.ID = authorID
	response.RootID = optionalString(rootID)
	response.ParentID = optionalString(parentID)
	response.ReplyToUserID = optionalString(replyTo)
	response.StickerID = optionalString(stickerID)
	if err := enrichReplyToUser(ctx, tx, &response); err != nil {
		return commentResponse{}, err
	}
	responseList := []commentResponse{response}
	if err := enrichCommentsMedia(ctx, tx, responseList); err != nil {
		return commentResponse{}, err
	}
	response = responseList[0]
	response.ViewerState = &viewerCommentState{}
	return response, nil
}

type databaseQueryer interface {
	QueryContext(ctx context.Context, query string, args ...any) (*sql.Rows, error)
}

func enrichCommentsMedia(ctx context.Context, db databaseQueryer, items []commentResponse) error {
	if len(items) == 0 {
		return nil
	}
	commentIDs := make([]any, len(items))
	idToIdx := make(map[string]int, len(items))
	for i := range items {
		commentIDs[i] = items[i].ID
		idToIdx[items[i].ID] = i
		if items[i].Media == nil {
			items[i].Media = make([]postMediaResponse, 0)
		}
		if items[i].Attachments == nil {
			items[i].Attachments = make([]commentAttachmentResponse, 0)
		}
		if items[i].StickerID != nil && *items[i].StickerID != "" {
			items[i].Attachments = append(items[i].Attachments, commentAttachmentResponse{
				ID:        *items[i].StickerID,
				Type:      "sticker",
				StickerID: *items[i].StickerID,
			})
		}
	}

	placeholders := make([]string, len(commentIDs))
	for i := range placeholders {
		placeholders[i] = fmt.Sprintf("$%d", i+1)
	}

	query := fmt.Sprintf(`
		SELECT cm.comment_id, ma.id, ma.mime_type, ma.width, ma.height, ma.original_name, ma.object_key
		FROM comment_media cm
		JOIN media_assets ma ON ma.id = cm.media_id
		WHERE cm.comment_id IN (%s) AND ma.status = 'ready' AND ma.deleted_at IS NULL
		ORDER BY cm.comment_id ASC, cm.sort_order ASC, ma.id ASC`, strings.Join(placeholders, ", "))

	rows, err := db.QueryContext(ctx, query, commentIDs...)
	if err != nil {
		return err
	}
	defer rows.Close()

	type mediaWithKey struct {
		commentID string
		media     postMediaResponse
		objectKey string
	}
	mediaList := make([]mediaWithKey, 0)
	mediaIDs := make([]any, 0)
	seenMedia := make(map[string]struct{})

	for rows.Next() {
		var mk mediaWithKey
		if err := rows.Scan(&mk.commentID, &mk.media.ID, &mk.media.MimeType, &mk.media.Width, &mk.media.Height, &mk.media.AltText, &mk.objectKey); err != nil {
			return err
		}
		if strings.HasPrefix(mk.media.MimeType, "video/") {
			mk.media.Type = "video"
		} else {
			mk.media.Type = "image"
		}
		mk.media.URL = publicMediaURL(mk.objectKey)
		mediaList = append(mediaList, mk)
		if _, ok := seenMedia[mk.media.ID]; !ok {
			seenMedia[mk.media.ID] = struct{}{}
			mediaIDs = append(mediaIDs, mk.media.ID)
		}
	}
	if err := rows.Err(); err != nil {
		return err
	}
	_ = rows.Close()

	variantsMap := make(map[string]map[string]*mediaVariantResponse)
	if len(mediaIDs) > 0 {
		vPlaceholders := make([]string, len(mediaIDs))
		for i := range vPlaceholders {
			vPlaceholders[i] = fmt.Sprintf("$%d", i+1)
		}
		vQuery := fmt.Sprintf(`
			SELECT mv.media_id, mv.variant, mv.object_key, mv.mime_type, mv.width, mv.height, mv.size_bytes
			FROM media_variants mv
			WHERE mv.media_id IN (%s) AND mv.status = 'ready'`, strings.Join(vPlaceholders, ", "))
		vRows, err := db.QueryContext(ctx, vQuery, mediaIDs...)
		if err == nil {
			for vRows.Next() {
				var mid, variant, objKey, mimeType string
				var width, height int
				var sizeBytes int64
				if err := vRows.Scan(&mid, &variant, &objKey, &mimeType, &width, &height, &sizeBytes); err == nil {
					if variantsMap[mid] == nil {
						variantsMap[mid] = make(map[string]*mediaVariantResponse)
					}
					variantsMap[mid][variant] = &mediaVariantResponse{
						URL:       publicMediaURL(objKey),
						Width:     width,
						Height:    height,
						SizeBytes: sizeBytes,
						MimeType:  mimeType,
					}
				}
			}
			vRows.Close()
		}
	}

	for _, mk := range mediaList {
		idx, ok := idToIdx[mk.commentID]
		if !ok {
			continue
		}
		m := mk.media
		if vmap, ok := variantsMap[m.ID]; ok {
			m.Thumb = vmap["thumb"]
			m.Detail = vmap["detail"]
			m.Original = vmap["original"]
		}
		if m.Thumb == nil && m.URL != "" {
			m.Thumb = &mediaVariantResponse{
				URL:      m.URL,
				Width:    m.Width,
				Height:   m.Height,
				MimeType: m.MimeType,
			}
		}
		items[idx].Media = append(items[idx].Media, m)
		thumbURL := m.URL
		if m.Thumb != nil && m.Thumb.URL != "" {
			thumbURL = m.Thumb.URL
		}
		items[idx].Attachments = append(items[idx].Attachments, commentAttachmentResponse{
			ID:           m.ID,
			Type:         m.Type,
			URL:          m.URL,
			ThumbnailURL: thumbURL,
			Width:        m.Width,
			Height:       m.Height,
		})
	}
	return nil
}

func sliceContains(slice []string, target string) bool {
	for _, s := range slice {
		if s == target {
			return true
		}
	}
	return false
}

type userSummaryQueryer interface {
	QueryRowContext(context.Context, string, ...any) *sql.Row
}

// enrichReplyToUser 返回回复目标的稳定快照，前端可以直接渲染真实昵称。
// 目标用户被删除时保留 reply_to_user_id，但不阻断整条评论返回。
func enrichReplyToUser(ctx context.Context, queryer userSummaryQueryer, item *commentResponse) error {
	if item == nil || item.ReplyToUserID == nil || *item.ReplyToUserID == "" {
		return nil
	}
	summary, err := loadUserSummary(ctx, queryer, *item.ReplyToUserID)
	if err != nil {
		return err
	}
	item.ReplyToUser = summary
	return nil
}

func loadUserSummary(ctx context.Context, queryer userSummaryQueryer, userID string) (*userSummary, error) {
	var summary userSummary
	var objectKey string
	err := queryer.QueryRowContext(ctx, `
		SELECT u.id, u.username, COALESCE(up.nickname, u.username),
		       COALESCE(up.level, 1), COALESCE(up.avatar_media_id, ''),
		       COALESCE(ma.object_key, '')
		FROM users u
		LEFT JOIN user_profiles up ON up.user_id = u.id
		LEFT JOIN media_assets ma ON ma.id = up.avatar_media_id
		WHERE u.id = $1 AND u.deleted_at IS NULL`, userID).Scan(
		&summary.ID, &summary.Username, &summary.Nickname, &summary.Level, &summary.AvatarMediaID, &objectKey,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	if objectKey != "" {
		summary.AvatarURL = publicMediaURL(objectKey)
	}
	return &summary, nil
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
