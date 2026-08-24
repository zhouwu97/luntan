package api

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

var (
	ErrCommunityNotFound      = errors.New("community not found")
	ErrPostNotFound           = errors.New("post not found")
	ErrForbidden              = errors.New("forbidden")
	ErrIdempotencyKeyRequired = errors.New("idempotency key required")
	ErrInvalidPost            = errors.New("invalid post")
)

type postWriteInput struct {
	CommunityID string       `json:"community_id"`
	Type        string       `json:"type"`
	Title       string       `json:"title"`
	Content     string       `json:"content"`
	MediaIDs    []string     `json:"media_ids"`
	Poll        *pollInput   `json:"poll"`
	Market      *marketInput `json:"market"`
}

type postMutationResponse struct {
	ID                string     `json:"id"`
	AuthorID          string     `json:"author_id"`
	CommunityID       string     `json:"community_id"`
	Type              string     `json:"type"`
	Title             string     `json:"title"`
	Content           string     `json:"content"`
	PublicationStatus string     `json:"publication_status"`
	ModerationStatus  string     `json:"moderation_status"`
	CreatedAt         time.Time  `json:"created_at"`
	UpdatedAt         time.Time  `json:"updated_at"`
	PublishedAt       *time.Time `json:"published_at,omitempty"`
	MediaIDs          []string   `json:"media_ids,omitempty"`
}

type postRecord struct {
	postMutationResponse
	DeletedAt sql.NullTime
}

type queryRowContext interface {
	QueryRowContext(context.Context, string, ...any) *sql.Row
}

func (s *Server) createPost(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	idempotencyKey := strings.TrimSpace(r.Header.Get("Idempotency-Key"))
	if idempotencyKey == "" || len(idempotencyKey) > 128 {
		writeAuthError(w, r, ErrIdempotencyKeyRequired)
		return
	}
	var input postWriteInput
	if err := decodeJSON(r, &input); err != nil || !validPostInput(input) {
		writeAuthError(w, r, ErrInvalidPost)
		return
	}

	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	// 同一用户对同一幂等键的并发发布必须串行化，避免两个事务同时查不到记录后竞争唯一键。
	var advisoryLock any
	if err := tx.QueryRowContext(r.Context(), `SELECT pg_advisory_xact_lock(hashtext($1 || ':' || $2))`, user.ID, idempotencyKey).Scan(&advisoryLock); err != nil {
		writeInternalError(w, r, err)
		return
	}
	var existingPostID string
	err = tx.QueryRowContext(r.Context(), `SELECT post_id FROM post_idempotency_keys WHERE user_id = $1 AND idempotency_key = $2`, user.ID, idempotencyKey).Scan(&existingPostID)
	if err == nil {
		response, loadErr := loadPostMutation(r.Context(), tx, existingPostID)
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
	if !errors.Is(err, sql.ErrNoRows) {
		writeInternalError(w, r, err)
		return
	}
	if err := ensureCommunity(r.Context(), tx, input.CommunityID); err != nil {
		writeAuthError(w, r, err)
		return
	}
	now := time.Now().UTC()
	postID := newPostID()
	if _, err := tx.ExecContext(r.Context(), `INSERT INTO posts (id, author_id, community_id, type, publication_status, moderation_status, title, content, created_at, updated_at, published_at) VALUES ($1, $2, $3, $4, 'published', 'normal', $5, $6, $7, $7, $7)`, postID, user.ID, input.CommunityID, input.Type, input.Title, input.Content, now); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := insertPostRevision(r.Context(), tx, postID, user.ID, input, now); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := attachMedia(r.Context(), tx, postID, user.ID, input.MediaIDs, now); err != nil {
		writeAuthError(w, r, err)
		return
	}
	if input.Type == "poll" {
		if err := insertPollTx(r.Context(), tx, postID, input.Poll); err != nil {
			writeAuthError(w, r, err)
			return
		}
	}
	if input.Type == "market" {
		if err := insertMarketItemTx(r.Context(), tx, postID, user.ID, input.Market); err != nil {
			writeAuthError(w, r, err)
			return
		}
	}
	if _, err := tx.ExecContext(r.Context(), `INSERT INTO post_idempotency_keys (user_id, idempotency_key, post_id, created_at) VALUES ($1, $2, $3, $4)`, user.ID, idempotencyKey, postID, now); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := awardPointsTx(r.Context(), tx, user.ID, "post", "发布帖子", "post:create:"+postID, s.pointRewards.PostCreate); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := enqueueOutboxTx(tx, "post.created", "post", postID, map[string]any{
		"author_id":    user.ID,
		"community_id": input.CommunityID,
	}, now); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	response := postMutationResponse{ID: postID, AuthorID: user.ID, CommunityID: input.CommunityID, Type: input.Type, Title: input.Title, Content: input.Content, PublicationStatus: "published", ModerationStatus: "normal", CreatedAt: now, UpdatedAt: now, PublishedAt: &now}
	response.MediaIDs = append([]string(nil), input.MediaIDs...)
	httpserver.WriteJSON(w, http.StatusCreated, response)
}

func (s *Server) updatePost(w http.ResponseWriter, r *http.Request, postID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if strings.TrimSpace(postID) == "" {
		writeAuthError(w, r, ErrPostNotFound)
		return
	}
	var input postWriteInput
	if err := decodeJSON(r, &input); err != nil || !validPostInput(input) {
		writeAuthError(w, r, ErrInvalidPost)
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	var current postRecord
	var publishedAt sql.NullTime
	err = tx.QueryRowContext(r.Context(), `SELECT id, author_id, community_id, type, title, content, publication_status, moderation_status, created_at, updated_at, published_at, deleted_at FROM posts WHERE id = $1 FOR UPDATE`, postID).Scan(&current.ID, &current.AuthorID, &current.CommunityID, &current.Type, &current.Title, &current.Content, &current.PublicationStatus, &current.ModerationStatus, &current.CreatedAt, &current.UpdatedAt, &publishedAt, &current.DeletedAt)
	if errors.Is(err, sql.ErrNoRows) || current.DeletedAt.Valid {
		writeAuthError(w, r, ErrPostNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if current.AuthorID != user.ID {
		writeAuthError(w, r, ErrForbidden)
		return
	}
	if err := ensureCommunity(r.Context(), tx, input.CommunityID); err != nil {
		writeAuthError(w, r, err)
		return
	}
	now := time.Now().UTC()
	if _, err := tx.ExecContext(r.Context(), `UPDATE posts SET community_id = $1, type = $2, title = $3, content = $4, updated_at = $5 WHERE id = $6`, input.CommunityID, input.Type, input.Title, input.Content, now, postID); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := insertPostRevision(r.Context(), tx, postID, user.ID, input, now); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := replaceMedia(r.Context(), tx, postID, user.ID, input.MediaIDs, now); err != nil {
		writeAuthError(w, r, err)
		return
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if publishedAt.Valid {
		current.PublishedAt = &publishedAt.Time
	}
	current.CommunityID, current.Type, current.Title, current.Content, current.UpdatedAt = input.CommunityID, input.Type, input.Title, input.Content, now
	current.MediaIDs = append([]string(nil), input.MediaIDs...)
	httpserver.WriteJSON(w, http.StatusOK, current.postMutationResponse)
}

func (s *Server) deletePost(w http.ResponseWriter, r *http.Request, postID string) {
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
	err = tx.QueryRowContext(r.Context(), `SELECT author_id FROM posts WHERE id = $1 FOR UPDATE`, postID).Scan(&authorID)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrPostNotFound)
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
	if _, err := tx.ExecContext(r.Context(), `UPDATE posts SET deleted_at = COALESCE(deleted_at, now()), publication_status = 'deleted', updated_at = now() WHERE id = $1`, postID); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func validPostInput(input postWriteInput) bool {
	if strings.TrimSpace(input.CommunityID) == "" || strings.TrimSpace(input.Title) == "" || strings.TrimSpace(input.Content) == "" {
		return false
	}
	if len([]rune(input.Title)) > 200 || len([]rune(input.Content)) > 200000 {
		return false
	}
	switch input.Type {
	case "normal", "guide", "question", "game_share", "activity":
		return true
	case "poll":
		return validPollInput(input.Poll)
	case "market":
		return validMarketInput(input.Market)
	default:
		return false
	}
}

func ensureCommunity(ctx context.Context, queryer queryRowContext, communityID string) error {
	var id string
	err := queryer.QueryRowContext(ctx, `SELECT id FROM communities WHERE id = $1 AND status = 'active' AND deleted_at IS NULL`, communityID).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrCommunityNotFound
	}
	return err
}

func insertPostRevision(ctx context.Context, tx *sql.Tx, postID, editorID string, input postWriteInput, now time.Time) error {
	_, err := tx.ExecContext(ctx, `INSERT INTO post_revisions (id, post_id, editor_id, community_id, type, title, content, created_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`, newPostID(), postID, editorID, input.CommunityID, input.Type, input.Title, input.Content, now)
	return err
}

func loadPostMutation(ctx context.Context, queryer queryRowContext, postID string) (postMutationResponse, error) {
	var response postMutationResponse
	var publishedAt sql.NullTime
	err := queryer.QueryRowContext(ctx, `SELECT id, author_id, community_id, type, title, content, publication_status, moderation_status, created_at, updated_at, published_at FROM posts WHERE id = $1 AND deleted_at IS NULL`, postID).Scan(&response.ID, &response.AuthorID, &response.CommunityID, &response.Type, &response.Title, &response.Content, &response.PublicationStatus, &response.ModerationStatus, &response.CreatedAt, &response.UpdatedAt, &publishedAt)
	if err != nil {
		return postMutationResponse{}, err
	}
	if publishedAt.Valid {
		response.PublishedAt = &publishedAt.Time
	}
	return response, nil
}

func newPostID() string {
	var raw [16]byte
	if _, err := rand.Read(raw[:]); err != nil {
		return "post_fallback"
	}
	return "post_" + hex.EncodeToString(raw[:])
}

func attachMedia(ctx context.Context, tx *sql.Tx, postID, ownerID string, mediaIDs []string, now time.Time) error {
	if len(mediaIDs) == 0 {
		return nil
	}
	if len(mediaIDs) > 9 {
		return ErrInvalidPost
	}
	seen := make(map[string]struct{}, len(mediaIDs))
	for index, mediaID := range mediaIDs {
		if _, exists := seen[mediaID]; exists || strings.TrimSpace(mediaID) == "" {
			return ErrInvalidPost
		}
		seen[mediaID] = struct{}{}
		var id string
		err := tx.QueryRowContext(ctx, `SELECT id FROM media_assets WHERE id = $1 AND owner_id = $2 AND status = 'ready' AND deleted_at IS NULL FOR UPDATE`, mediaID, ownerID).Scan(&id)
		if errors.Is(err, sql.ErrNoRows) {
			return ErrInvalidPost
		}
		if err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, `INSERT INTO post_media (post_id, media_id, sort_order, created_at) VALUES ($1, $2, $3, $4)`, postID, mediaID, index, now); err != nil {
			return err
		}
	}
	return nil
}

func replaceMedia(ctx context.Context, tx *sql.Tx, postID, ownerID string, mediaIDs []string, now time.Time) error {
	if _, err := tx.ExecContext(ctx, `DELETE FROM post_media WHERE post_id = $1`, postID); err != nil {
		return err
	}
	return attachMedia(ctx, tx, postID, ownerID, mediaIDs, now)
}

func (s *Server) getPost(w http.ResponseWriter, r *http.Request, id string) {
	if !s.requireDatabase(w, r) {
		return
	}
	var row postResponse
	var deletedAt sql.NullTime
	var publishedAt sql.NullTime
	err := s.db.QueryRowContext(r.Context(), `
		SELECT p.id, p.author_id, u.username, COALESCE(up.nickname, u.username), p.community_id, c.slug, c.name,
		       p.type, p.title, p.content, p.comment_count, p.like_count, p.bookmark_count, p.share_count, p.view_count,
		p.created_at, p.updated_at, p.published_at, p.publication_status, p.moderation_status, p.deleted_at
		FROM posts p
		JOIN users u ON u.id = p.author_id
		LEFT JOIN user_profiles up ON up.user_id = u.id
		JOIN communities c ON c.id = p.community_id
		WHERE p.id = $1`, id).Scan(&row.ID, &row.Author.ID, &row.Author.Username, &row.Author.Nickname, &row.Community.ID, &row.Community.Slug, &row.Community.Name, &row.Type, &row.Title, &row.Content, &row.CommentCount, &row.LikeCount, &row.BookmarkCount, &row.ShareCount, &row.ViewCount, &row.CreatedAt, &row.UpdatedAt, &publishedAt, &row.Publication, &row.Moderation, &deletedAt)
	if err == sql.ErrNoRows {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusNotFound, Code: "NOT_FOUND", Message: "帖子不存在"})
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if deletedAt.Valid || row.Publication != "published" || row.Moderation != "normal" {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusNotFound, Code: "NOT_FOUND", Message: "帖子不存在"})
		return
	}
	if publishedAt.Valid {
		row.PublishedAt = &publishedAt.Time
	}
	if includePostDetails(r) {
		if err := s.enrichPostResponse(r.Context(), r, &row, true); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	httpserver.WriteJSON(w, http.StatusOK, row)
}
