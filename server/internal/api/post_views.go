package api

import (
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

const postViewVisitorCookie = "luntan_visitor_id"

func (s *Server) recordPostView(w http.ResponseWriter, r *http.Request, postID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	viewerKey, setCookie := s.postViewViewerKey(r)
	if viewerKey == "" {
		writeInternalError(w, r, errors.New("generate post view visitor failed"))
		return
	}
	if setCookie != nil {
		http.SetCookie(w, setCookie)
	}

	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()

	var viewCount int64
	err = tx.QueryRowContext(r.Context(), `
		SELECT view_count
		FROM posts
		WHERE id = $1
		  AND publication_status = 'published'
		  AND moderation_status = 'normal'
		  AND type <> 'market'
		  AND deleted_at IS NULL
		FOR UPDATE`, postID).Scan(&viewCount)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrPostNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}

	viewDate := time.Now().UTC().Truncate(24 * time.Hour)
	result, err := tx.ExecContext(r.Context(), `
		INSERT INTO post_view_events (post_id, viewer_key, view_date)
		VALUES ($1, $2, $3)
		ON CONFLICT (post_id, viewer_key, view_date) DO NOTHING`, postID, viewerKey, viewDate)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	affected, err := result.RowsAffected()
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	recorded := affected == 1
	if recorded {
		if err := tx.QueryRowContext(r.Context(), `
			UPDATE posts
			SET view_count = view_count + 1, updated_at = now()
			WHERE id = $1
			RETURNING view_count`, postID).Scan(&viewCount); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{
		"post_id":    postID,
		"recorded":   recorded,
		"view_count": viewCount,
	})
}

func (s *Server) postViewViewerKey(r *http.Request) (string, *http.Cookie) {
	if viewer, ok := s.optionalAuthenticatedUser(r.Context(), r); ok && strings.TrimSpace(viewer.ID) != "" {
		return boundedPostViewKey("u:", viewer.ID), nil
	}
	if cookie, err := r.Cookie(postViewVisitorCookie); err == nil {
		if visitorID := sanitizeVisitorID(cookie.Value); visitorID != "" {
			return boundedPostViewKey("a:", visitorID), nil
		}
	}
	visitorID, err := newVisitorID()
	if err != nil {
		return "", nil
	}
	secure := r.TLS != nil || strings.EqualFold(r.Header.Get("X-Forwarded-Proto"), "https")
	return boundedPostViewKey("a:", visitorID), &http.Cookie{
		Name:     postViewVisitorCookie,
		Value:    visitorID,
		Path:     "/",
		MaxAge:   60 * 60 * 24 * 365,
		Expires:  time.Now().UTC().AddDate(1, 0, 0),
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
		Secure:   secure,
	}
}

func boundedPostViewKey(prefix, value string) string {
	clean := strings.TrimSpace(value)
	if clean == "" {
		return ""
	}
	if len(prefix)+len(clean) <= 160 {
		return prefix + clean
	}
	sum := sha256.Sum256([]byte(clean))
	return prefix + hex.EncodeToString(sum[:])
}

func sanitizeVisitorID(value string) string {
	value = strings.TrimSpace(value)
	if len(value) < 16 || len(value) > 96 {
		return ""
	}
	for _, ch := range value {
		if ch >= 'a' && ch <= 'z' || ch >= 'A' && ch <= 'Z' || ch >= '0' && ch <= '9' || ch == '_' || ch == '-' {
			continue
		}
		return ""
	}
	return value
}

func newVisitorID() (string, error) {
	var raw [16]byte
	if _, err := rand.Read(raw[:]); err != nil {
		return "", err
	}
	return hex.EncodeToString(raw[:]), nil
}
