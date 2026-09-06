package api

import (
	"context"
	"database/sql"
	"net/http"
	"strings"
	"time"

	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

func (s *Server) createCommunityAnnouncement(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if !s.canModerate(r, user) {
		writeAuthError(w, r, ErrPermissionDenied)
		return
	}
	var input struct {
		ID      string `json:"id"`
		Title   string `json:"title"`
		Content string `json:"content"`
	}
	if err := decodeJSON(r, &input); err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_ANNOUNCEMENT", Message: "公告数据格式错误"})
		return
	}
	input.Title, input.Content = strings.TrimSpace(input.Title), strings.TrimSpace(input.Content)
	if len(input.ID) < 16 || len(input.ID) > 128 || len([]rune(input.Title)) == 0 || len([]rune(input.Title)) > 100 || len([]rune(input.Content)) == 0 || len([]rune(input.Content)) > 10000 {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_ANNOUNCEMENT", Message: "公告标题或正文不合法"})
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	now := time.Now().UTC()
	result, err := tx.ExecContext(r.Context(), `INSERT INTO community_announcements (id, actor_id, title, content, created_at)
        VALUES ($1, $2, $3, $4, $5) ON CONFLICT (id) DO NOTHING`, input.ID, user.ID, input.Title, input.Content, now)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	changed, err := rowsChanged(result, nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if changed {
		if err := enqueueCommunityBroadcastTx(r.Context(), tx, user.ID, "community.announcement", "system", input.ID, input.Title, input.Content, now); err != nil {
			writeInternalError(w, r, err)
			return
		}
	} else {
		var same bool
		if err := tx.QueryRowContext(r.Context(), `SELECT actor_id = $2 AND title = $3 AND content = $4 FROM community_announcements WHERE id = $1`, input.ID, user.ID, input.Title, input.Content).Scan(&same); err != nil {
			writeInternalError(w, r, err)
			return
		}
		if !same {
			httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusConflict, Code: "ANNOUNCEMENT_CONFLICT", Message: "公告已发布，请勿使用同一编号修改内容"})
			return
		}
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"id": input.ID})
}

// 广播和 outbox 批量写入同一事务，失败时不会留下已发布但没有通知的记录。
func enqueueCommunityBroadcastTx(ctx context.Context, tx *sql.Tx, actorID, kind, targetType, targetID, title, content string, now time.Time) error {
	_, err := tx.ExecContext(ctx, `WITH created AS (
        INSERT INTO notifications (id, user_id, type, actor_id, target_type, target_id, target_data, is_read, created_at)
        SELECT md5($1 || u.id), u.id, $7, $2, $8, $3,
            jsonb_build_object('title', $4::text, 'content', $5::text), false, $6
        FROM users u WHERE u.status = 'active' AND u.deleted_at IS NULL AND u.id <> $2
          AND NOT EXISTS (SELECT 1 FROM blocks b WHERE
            (b.blocker_id = u.id AND b.blocked_id = $2) OR (b.blocker_id = $2 AND b.blocked_id = u.id))
        RETURNING *
    ) INSERT INTO outbox_events (id, event_type, aggregate_type, aggregate_id, payload, status, available_at, created_at)
      SELECT md5(id || $1), 'notification.created', 'notification', id,
        jsonb_build_object('recipient_id', user_id, 'actor_id', actor_id, 'type', type,
            'target_type', target_type, 'target_id', target_id, 'target_data', target_data),
        'pending', $6, $6 FROM created`, newPostID(), actorID, targetID, title, content, now, kind, targetType)
	return err
}
