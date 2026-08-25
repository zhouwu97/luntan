package api

import (
	"net/http"
	"time"
)

// deleteAccount 执行可追溯的账号注销：保留公开内容的作者关系，清理账号身份与私密状态，
// 同时在同一事务中失效所有会话，避免注销后旧 token 继续可用。
func (s *Server) deleteAccount(w http.ResponseWriter, r *http.Request) {
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

	if _, err := tx.ExecContext(r.Context(), `
		UPDATE users
		SET status = 'deleted', deleted_at = COALESCE(deleted_at, now()),
		    username = 'deleted_' || id, updated_at = now()
		WHERE id = $1 AND deleted_at IS NULL`, user.ID); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if _, err := tx.ExecContext(r.Context(), `
		UPDATE user_profiles
		SET nickname = '已注销用户', avatar_media_id = NULL, bio = '', updated_at = now()
		WHERE user_id = $1`, user.ID); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if _, err := tx.ExecContext(r.Context(), `UPDATE sessions SET revoked_at = COALESCE(revoked_at, now()) WHERE user_id = $1`, user.ID); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if _, err := tx.ExecContext(r.Context(), `UPDATE refresh_tokens SET revoked_at = COALESCE(revoked_at, now()) WHERE user_id = $1`, user.ID); err != nil {
		writeInternalError(w, r, err)
		return
	}
	// 认证凭据属于高敏感数据，注销后不再保留。
	if _, err := tx.ExecContext(r.Context(), `DELETE FROM user_auth_methods WHERE user_id = $1`, user.ID); err != nil {
		writeInternalError(w, r, err)
		return
	}
	// 删除可回溯到个人的互动与通知；帖子、评论保留为公开内容，但作者已匿名化。
	for _, statement := range []string{
		`WITH removed AS (DELETE FROM post_reactions WHERE user_id = $1 RETURNING post_id), counts AS (SELECT post_id, count(*) AS amount FROM removed GROUP BY post_id) UPDATE posts p SET like_count = GREATEST(p.like_count - counts.amount, 0), updated_at = now() FROM counts WHERE p.id = counts.post_id`,
		`WITH removed AS (DELETE FROM comment_reactions WHERE user_id = $1 RETURNING comment_id), counts AS (SELECT comment_id, count(*) AS amount FROM removed GROUP BY comment_id) UPDATE comments c SET like_count = GREATEST(c.like_count - counts.amount, 0), updated_at = now() FROM counts WHERE c.id = counts.comment_id`,
		`WITH removed AS (DELETE FROM bookmarks WHERE user_id = $1 RETURNING post_id), counts AS (SELECT post_id, count(*) AS amount FROM removed GROUP BY post_id) UPDATE posts p SET bookmark_count = GREATEST(p.bookmark_count - counts.amount, 0), updated_at = now() FROM counts WHERE p.id = counts.post_id`,
		`DELETE FROM bookmark_folders WHERE user_id = $1`,
		`DELETE FROM user_follows WHERE follower_id = $1 OR followee_id = $1`,
		`WITH removed AS (DELETE FROM community_follows WHERE user_id = $1 RETURNING community_id), counts AS (SELECT community_id, count(*) AS amount FROM removed GROUP BY community_id) UPDATE communities c SET follower_count = GREATEST(c.follower_count - counts.amount, 0), updated_at = now() FROM counts WHERE c.id = counts.community_id`,
		`WITH removed AS (DELETE FROM community_members WHERE user_id = $1 RETURNING community_id), counts AS (SELECT community_id, count(*) AS amount FROM removed GROUP BY community_id) UPDATE communities c SET member_count = GREATEST(c.member_count - counts.amount, 0), updated_at = now() FROM counts WHERE c.id = counts.community_id`,
		`DELETE FROM blocks WHERE blocker_id = $1 OR blocked_id = $1`,
		`DELETE FROM poll_votes WHERE user_id = $1`,
		`DELETE FROM notifications WHERE user_id = $1 OR actor_id = $1`,
		`DELETE FROM user_roles WHERE user_id = $1`,
		`UPDATE media_assets SET status = 'deleted', deleted_at = COALESCE(deleted_at, now()), updated_at = now() WHERE owner_id = $1 AND deleted_at IS NULL`,
	} {
		if _, err := tx.ExecContext(r.Context(), statement, user.ID); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	if _, err := tx.ExecContext(r.Context(), `
		INSERT INTO audit_logs (id, operator_id, action, target_type, target_id, reason, request_id, created_at)
		VALUES ($1, $2, 'account.delete', 'user', $2, 'user_requested', $3, now())`, newPostID(), user.ID, requestIDFromRequest(r)); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := appendAdminLogTx(r.Context(), tx, user.ID, "account.delete", "user", user.ID, "user_requested", requestIDFromRequest(r), map[string]any{"status": "deleted"}, time.Now().UTC()); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func requestIDFromRequest(r *http.Request) string {
	return r.Header.Get("X-Request-ID")
}
