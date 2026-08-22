package api

import (
	"context"
	"database/sql"
	"errors"
	"net/http"
	"strings"

	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

var (
	ErrInteractionTargetNotFound = errors.New("interaction target not found")
	ErrSelfFollow                = errors.New("self follow is not allowed")
)

func (s *Server) togglePostLike(w http.ResponseWriter, r *http.Request, postID string, active bool) {
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
	if err := lockPostForInteraction(r.Context(), tx, postID); err != nil {
		writeAuthError(w, r, err)
		return
	}
	changed, err := setPostReaction(r.Context(), tx, postID, user.ID, "like", active)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if changed {
		operator := "+ 1"
		if !active {
			operator = "- 1"
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE posts SET like_count = GREATEST(like_count `+operator+`, 0), updated_at = now() WHERE id = $1`, postID); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"active": active})
}

func (s *Server) toggleBookmark(w http.ResponseWriter, r *http.Request, postID string, active bool) {
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
	if err := lockPostForInteraction(r.Context(), tx, postID); err != nil {
		writeAuthError(w, r, err)
		return
	}
	changed, err := setBookmark(r.Context(), tx, postID, user.ID, active)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if changed {
		operator := "+ 1"
		if !active {
			operator = "- 1"
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE posts SET bookmark_count = GREATEST(bookmark_count `+operator+`, 0), updated_at = now() WHERE id = $1`, postID); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"active": active})
}

func (s *Server) toggleCommentLike(w http.ResponseWriter, r *http.Request, commentID string, active bool) {
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
	if err := lockCommentForInteraction(r.Context(), tx, commentID); err != nil {
		writeAuthError(w, r, err)
		return
	}
	changed, err := setCommentReaction(r.Context(), tx, commentID, user.ID, "like", active)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if changed {
		operator := "+ 1"
		if !active {
			operator = "- 1"
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE comments SET like_count = GREATEST(like_count `+operator+`, 0), updated_at = now() WHERE id = $1`, commentID); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"active": active})
}

func (s *Server) toggleUserFollow(w http.ResponseWriter, r *http.Request, targetUserID string, active bool) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if strings.TrimSpace(targetUserID) == "" {
		writeAuthError(w, r, ErrInteractionTargetNotFound)
		return
	}
	if user.ID == targetUserID {
		writeAuthError(w, r, ErrSelfFollow)
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	if err := lockUserForInteraction(r.Context(), tx, targetUserID); err != nil {
		writeAuthError(w, r, err)
		return
	}
	if _, err := setUserFollow(r.Context(), tx, user.ID, targetUserID, active); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"active": active})
}

func (s *Server) toggleCommunityFollow(w http.ResponseWriter, r *http.Request, communityID string, active bool) {
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
	if err := lockCommunityForInteraction(r.Context(), tx, communityID); err != nil {
		writeAuthError(w, r, err)
		return
	}
	changed, err := setCommunityFollow(r.Context(), tx, user.ID, communityID, active)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if changed {
		operator := "+ 1"
		if !active {
			operator = "- 1"
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE communities SET follower_count = GREATEST(follower_count `+operator+`, 0), updated_at = now() WHERE id = $1`, communityID); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"active": active})
}

func (s *Server) toggleCommunityMembership(w http.ResponseWriter, r *http.Request, communityID string, active bool) {
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
	if err := lockCommunityForInteraction(r.Context(), tx, communityID); err != nil {
		writeAuthError(w, r, err)
		return
	}
	changed, err := setCommunityMembership(r.Context(), tx, user.ID, communityID, active)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if changed {
		operator := "+ 1"
		if !active {
			operator = "- 1"
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE communities SET member_count = GREATEST(member_count `+operator+`, 0), updated_at = now() WHERE id = $1`, communityID); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"active": active})
}

func lockPostForInteraction(ctx context.Context, tx *sql.Tx, postID string) error {
	var id string
	err := tx.QueryRowContext(ctx, `SELECT id FROM posts WHERE id = $1 AND publication_status = 'published' AND moderation_status = 'normal' AND deleted_at IS NULL FOR UPDATE`, postID).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrInteractionTargetNotFound
	}
	return err
}

func lockCommentForInteraction(ctx context.Context, tx *sql.Tx, commentID string) error {
	var id string
	err := tx.QueryRowContext(ctx, `SELECT id FROM comments WHERE id = $1 AND publication_status = 'published' AND moderation_status = 'normal' AND deleted_at IS NULL FOR UPDATE`, commentID).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrInteractionTargetNotFound
	}
	return err
}

func lockUserForInteraction(ctx context.Context, tx *sql.Tx, userID string) error {
	var id string
	err := tx.QueryRowContext(ctx, `SELECT id FROM users WHERE id = $1 AND status = 'active' AND deleted_at IS NULL FOR UPDATE`, userID).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrInteractionTargetNotFound
	}
	return err
}

func lockCommunityForInteraction(ctx context.Context, tx *sql.Tx, communityID string) error {
	var id string
	err := tx.QueryRowContext(ctx, `SELECT id FROM communities WHERE id = $1 AND status = 'active' AND deleted_at IS NULL FOR UPDATE`, communityID).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrInteractionTargetNotFound
	}
	return err
}

func setPostReaction(ctx context.Context, tx *sql.Tx, postID, userID, reactionType string, active bool) (bool, error) {
	if active {
		result, err := tx.ExecContext(ctx, `INSERT INTO post_reactions (post_id, user_id, reaction_type) VALUES ($1, $2, $3) ON CONFLICT (post_id, user_id, reaction_type) DO NOTHING`, postID, userID, reactionType)
		return rowsChanged(result, err)
	}
	result, err := tx.ExecContext(ctx, `DELETE FROM post_reactions WHERE post_id = $1 AND user_id = $2 AND reaction_type = $3`, postID, userID, reactionType)
	return rowsChanged(result, err)
}

func setCommentReaction(ctx context.Context, tx *sql.Tx, commentID, userID, reactionType string, active bool) (bool, error) {
	if active {
		result, err := tx.ExecContext(ctx, `INSERT INTO comment_reactions (comment_id, user_id, reaction_type) VALUES ($1, $2, $3) ON CONFLICT (comment_id, user_id, reaction_type) DO NOTHING`, commentID, userID, reactionType)
		return rowsChanged(result, err)
	}
	result, err := tx.ExecContext(ctx, `DELETE FROM comment_reactions WHERE comment_id = $1 AND user_id = $2 AND reaction_type = $3`, commentID, userID, reactionType)
	return rowsChanged(result, err)
}

func setBookmark(ctx context.Context, tx *sql.Tx, postID, userID string, active bool) (bool, error) {
	if active {
		result, err := tx.ExecContext(ctx, `INSERT INTO bookmarks (post_id, user_id) VALUES ($1, $2) ON CONFLICT (post_id, user_id) DO NOTHING`, postID, userID)
		return rowsChanged(result, err)
	}
	result, err := tx.ExecContext(ctx, `DELETE FROM bookmarks WHERE post_id = $1 AND user_id = $2`, postID, userID)
	return rowsChanged(result, err)
}

func setUserFollow(ctx context.Context, tx *sql.Tx, followerID, followeeID string, active bool) (bool, error) {
	if active {
		result, err := tx.ExecContext(ctx, `INSERT INTO user_follows (follower_id, followee_id) VALUES ($1, $2) ON CONFLICT (follower_id, followee_id) DO NOTHING`, followerID, followeeID)
		return rowsChanged(result, err)
	}
	result, err := tx.ExecContext(ctx, `DELETE FROM user_follows WHERE follower_id = $1 AND followee_id = $2`, followerID, followeeID)
	return rowsChanged(result, err)
}

func setCommunityFollow(ctx context.Context, tx *sql.Tx, userID, communityID string, active bool) (bool, error) {
	if active {
		result, err := tx.ExecContext(ctx, `INSERT INTO community_follows (user_id, community_id) VALUES ($1, $2) ON CONFLICT (user_id, community_id) DO NOTHING`, userID, communityID)
		return rowsChanged(result, err)
	}
	result, err := tx.ExecContext(ctx, `DELETE FROM community_follows WHERE user_id = $1 AND community_id = $2`, userID, communityID)
	return rowsChanged(result, err)
}

func setCommunityMembership(ctx context.Context, tx *sql.Tx, userID, communityID string, active bool) (bool, error) {
	if active {
		result, err := tx.ExecContext(ctx, `INSERT INTO community_members (community_id, user_id, role, status) VALUES ($1, $2, 'member', 'active') ON CONFLICT (community_id, user_id) DO NOTHING`, communityID, userID)
		return rowsChanged(result, err)
	}
	result, err := tx.ExecContext(ctx, `DELETE FROM community_members WHERE community_id = $1 AND user_id = $2`, communityID, userID)
	return rowsChanged(result, err)
}

func rowsChanged(result sql.Result, err error) (bool, error) {
	if err != nil {
		return false, err
	}
	rows, err := result.RowsAffected()
	return rows == 1, err
}
