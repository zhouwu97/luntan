package api

import (
	"database/sql"
	"errors"
	"net/http"

	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

// recordPostShare 记录正式账号对帖子的终身首次分享。share_count 包含上线前历史基线，
// 因此事件表只负责驱动增量，不能被当作完整聚合来源。
func (s *Server) recordPostShare(w http.ResponseWriter, r *http.Request, postID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.requireRegisteredUser(w, r)
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
	var shareCount int64
	err = tx.QueryRowContext(r.Context(), `
		SELECT author_id, share_count
		FROM posts
		WHERE id = $1
		  AND publication_status = 'published'
		  AND moderation_status = 'normal'
		  AND type <> 'market'
		  AND deleted_at IS NULL
		  AND published_at IS NOT NULL
		FOR UPDATE`, postID).Scan(&authorID, &shareCount)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrPostNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}

	recorded := false
	if authorID != user.ID {
		result, err := tx.ExecContext(r.Context(), `
			INSERT INTO post_share_events (post_id, user_id)
			VALUES ($1, $2)
			ON CONFLICT (post_id, user_id) DO NOTHING`, postID, user.ID)
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
		affected, err := result.RowsAffected()
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
		recorded = affected == 1
		if recorded {
			if err := tx.QueryRowContext(r.Context(), `
				UPDATE posts
				SET share_count = share_count + 1, updated_at = now()
				WHERE id = $1
				RETURNING share_count`, postID).Scan(&shareCount); err != nil {
				writeInternalError(w, r, err)
				return
			}
		}
	}

	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{
		"post_id":     postID,
		"recorded":    recorded,
		"share_count": shareCount,
	})
}
