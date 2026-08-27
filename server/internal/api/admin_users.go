package api

import (
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/zhouwu97/luntan/server/internal/auth"
	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

var ErrInvalidManagedUserAction = errors.New("invalid managed user action")

type managedUserCursor struct {
	CreatedAt time.Time `json:"created_at"`
	ID        string    `json:"id"`
}

func (s *Server) requireUserManager(w http.ResponseWriter, r *http.Request) (auth.User, bool) {
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return auth.User{}, false
	}
	if !s.hasAnyPermission(r, user.ID, "user.manage") {
		writeAuthError(w, r, ErrPermissionDenied)
		return auth.User{}, false
	}
	return user, true
}

func (s *Server) listManagedUsers(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	if _, ok := s.requireUserManager(w, r); !ok {
		return
	}
	limit, err := parseLimit(r.URL.Query().Get("limit"))
	if err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_LIMIT", Message: "limit 必须是 1 到 50 之间的整数"})
		return
	}
	queryText := strings.TrimSpace(r.URL.Query().Get("q"))
	status := strings.TrimSpace(r.URL.Query().Get("status"))
	if status != "" && status != "active" && status != "suspended" && status != "deleted" {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_STATUS", Message: "账号状态无效"})
		return
	}
	args := []any{queryText, status}
	where := `WHERE ($1 = '' OR u.id ILIKE '%' || $1 || '%' OR u.username ILIKE '%' || $1 || '%' OR COALESCE(up.nickname, '') ILIKE '%' || $1 || '%' OR COALESCE(u.email, '') ILIKE '%' || $1 || '%')
	           AND ($2 = '' OR u.status = $2)`
	if value := r.URL.Query().Get("cursor"); value != "" {
		data, decodeErr := base64.RawURLEncoding.DecodeString(value)
		var cursor managedUserCursor
		if decodeErr != nil || json.Unmarshal(data, &cursor) != nil || cursor.ID == "" || cursor.CreatedAt.IsZero() {
			httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_CURSOR", Message: "cursor 无效"})
			return
		}
		where += " AND (u.created_at, u.id) < ($3, $4)"
		args = append(args, cursor.CreatedAt, cursor.ID)
	}
	limitPosition := len(args) + 1
	args = append(args, limit+1)
	rows, err := s.db.QueryContext(r.Context(), `
		SELECT u.id, u.username, COALESCE(up.nickname, u.username), COALESCE(u.email, ''),
		       u.status, COALESCE(u.account_type, 'email'), u.created_at,
		       COALESCE((SELECT string_agg(DISTINCT rl.name, ', ' ORDER BY rl.name)
		                 FROM user_roles ur JOIN roles rl ON rl.id = ur.role_id WHERE ur.user_id = u.id), ''),
		       EXISTS (SELECT 1 FROM bans b WHERE b.user_id = u.id AND b.revoked_at IS NULL AND (b.ends_at IS NULL OR b.ends_at > now())),
		       EXISTS (SELECT 1 FROM restrictions mr WHERE mr.user_id = u.id AND mr.restriction_type = 'mute' AND (mr.ends_at IS NULL OR mr.ends_at > now()))
		FROM users u LEFT JOIN user_profiles up ON up.user_id = u.id `+where+` ORDER BY u.created_at DESC, u.id DESC LIMIT $`+strconv.Itoa(limitPosition), args...)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()
	items := make([]map[string]any, 0, limit+1)
	var last managedUserCursor
	for rows.Next() {
		var id, username, nickname, email, statusValue, accountType, roles string
		var createdAt time.Time
		var banned, muted bool
		if err := rows.Scan(&id, &username, &nickname, &email, &statusValue, &accountType, &createdAt, &roles, &banned, &muted); err != nil {
			writeInternalError(w, r, err)
			return
		}
		if len(items) < limit {
			last = managedUserCursor{CreatedAt: createdAt, ID: id}
		}
		roleList := []string{}
		if roles != "" {
			roleList = strings.Split(roles, ", ")
		}
		items = append(items, map[string]any{"id": id, "username": username, "nickname": nickname, "email": email, "status": statusValue, "account_type": accountType, "created_at": createdAt, "roles": roleList, "banned": banned, "muted": muted})
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
	if hasMore {
		data, encodeErr := json.Marshal(last)
		if encodeErr != nil {
			writeInternalError(w, r, encodeErr)
			return
		}
		nextCursor = base64.RawURLEncoding.EncodeToString(data)
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items, "next_cursor": nextCursor, "has_more": hasMore})
}

func (s *Server) getManagedUser(w http.ResponseWriter, r *http.Request, userID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	if _, ok := s.requireUserManager(w, r); !ok {
		return
	}
	var id, username, nickname, email, statusValue, accountType string
	var createdAt time.Time
	var banned, muted bool
	err := s.db.QueryRowContext(r.Context(), `
		SELECT u.id, u.username, COALESCE(up.nickname, u.username), COALESCE(u.email, ''), u.status,
		       COALESCE(u.account_type, 'email'), u.created_at,
		       EXISTS (SELECT 1 FROM bans b WHERE b.user_id = u.id AND b.revoked_at IS NULL AND (b.ends_at IS NULL OR b.ends_at > now())),
		       EXISTS (SELECT 1 FROM restrictions mr WHERE mr.user_id = u.id AND mr.restriction_type = 'mute' AND (mr.ends_at IS NULL OR mr.ends_at > now()))
		FROM users u LEFT JOIN user_profiles up ON up.user_id = u.id
		WHERE u.id = $1`, userID).Scan(&id, &username, &nickname, &email, &statusValue, &accountType, &createdAt, &banned, &muted)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrPermissionDenied)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	roles := make([]map[string]string, 0)
	roleRows, err := s.db.QueryContext(r.Context(), `SELECT rl.name, COALESCE(ur.community_id, '') FROM user_roles ur JOIN roles rl ON rl.id = ur.role_id WHERE ur.user_id = $1 ORDER BY rl.name`, userID)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	for roleRows.Next() {
		var name, communityID string
		if err := roleRows.Scan(&name, &communityID); err != nil {
			roleRows.Close()
			writeInternalError(w, r, err)
			return
		}
		roles = append(roles, map[string]string{"name": name, "community_id": communityID})
	}
	roleRows.Close()
	if err := roleRows.Err(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	punishments := make([]map[string]any, 0)
	punishmentRows, err := s.db.QueryContext(r.Context(), `
		SELECT b.id, 'ban', b.reason, b.starts_at, b.ends_at, b.revoked_at FROM bans b WHERE b.user_id = $1
		UNION ALL
		SELECT mr.id, mr.restriction_type, mr.reason, mr.starts_at, mr.ends_at, NULL FROM restrictions mr WHERE mr.user_id = $1
		ORDER BY starts_at DESC`, userID)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	for punishmentRows.Next() {
		var punishmentID, kind, reason string
		var startsAt time.Time
		var endsAt, revokedAt sql.NullTime
		if err := punishmentRows.Scan(&punishmentID, &kind, &reason, &startsAt, &endsAt, &revokedAt); err != nil {
			punishmentRows.Close()
			writeInternalError(w, r, err)
			return
		}
		punishment := map[string]any{"id": punishmentID, "type": kind, "reason": reason, "starts_at": startsAt}
		if endsAt.Valid {
			punishment["ends_at"] = endsAt.Time
		}
		if revokedAt.Valid {
			punishment["revoked_at"] = revokedAt.Time
		}
		punishments = append(punishments, punishment)
	}
	punishmentRows.Close()
	if err := punishmentRows.Err(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	recentPosts := make([]map[string]any, 0)
	postRows, err := s.db.QueryContext(r.Context(), `SELECT id, title, content, created_at FROM posts WHERE author_id = $1 AND deleted_at IS NULL ORDER BY created_at DESC, id DESC LIMIT 20`, userID)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	for postRows.Next() {
		var postID, title, content string
		var postCreatedAt time.Time
		if err := postRows.Scan(&postID, &title, &content, &postCreatedAt); err != nil {
			postRows.Close()
			writeInternalError(w, r, err)
			return
		}
		recentPosts = append(recentPosts, map[string]any{"id": postID, "title": title, "content": preview(content), "created_at": postCreatedAt})
	}
	postRows.Close()
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"id": id, "username": username, "nickname": nickname, "email": email, "status": statusValue, "account_type": accountType, "created_at": createdAt, "roles": roles, "banned": banned, "muted": muted, "punishments": punishments, "recent_posts": recentPosts})
}

type managedUserActionInput struct {
	Action       string `json:"action"`
	Reason       string `json:"reason"`
	DurationDays int    `json:"duration_days"`
	Permanent    bool   `json:"permanent"`
}

func (s *Server) manageUserAction(w http.ResponseWriter, r *http.Request, targetID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	operator, ok := s.requireUserManager(w, r)
	if !ok {
		return
	}
	if targetID == "" || targetID == operator.ID {
		writeAuthError(w, r, ErrInvalidManagedUserAction)
		return
	}
	var input managedUserActionInput
	if err := decodeJSON(r, &input); err != nil || !validManagedUserAction(input) {
		writeAuthError(w, r, ErrInvalidManagedUserAction)
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	var targetExists string
	if err := tx.QueryRowContext(r.Context(), `SELECT id FROM users WHERE id = $1 AND deleted_at IS NULL FOR UPDATE`, targetID).Scan(&targetExists); errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrInvalidManagedUserAction)
		return
	} else if err != nil {
		writeInternalError(w, r, err)
		return
	}
	caseID := newPostID()
	if _, err := tx.ExecContext(r.Context(), `INSERT INTO moderation_cases (id, target_type, target_id, source, risk_level, status) VALUES ($1, 'user', $2, 'manual_admin', 'low', 'open')`, caseID, targetID); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := applyModerationAction(r, tx, operator.ID, caseID, "user", targetID, moderationActionInput{Action: input.Action, Reason: input.Reason, DurationDays: input.DurationDays, Permanent: input.Permanent}); err != nil {
		writeAuthError(w, r, err)
		return
	}
	now := time.Now().UTC()
	durationDays := input.DurationDays
	if durationDays == 0 && input.Action == "mute" && !input.Permanent {
		durationDays = 7
	}
	var endsAt any
	if durationDays > 0 {
		endsAt = now.Add(time.Duration(durationDays) * 24 * time.Hour)
	}
	actionID := newPostID()
	if _, err := tx.ExecContext(r.Context(), `INSERT INTO moderation_actions (id, case_id, operator_id, action, reason, appealable, duration_days, starts_at, ends_at, created_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $8)`, actionID, caseID, operator.ID, input.Action, strings.TrimSpace(input.Reason), input.Action != "restore", durationDays, now, endsAt); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if _, err := tx.ExecContext(r.Context(), `UPDATE moderation_cases SET status = 'resolved', resolved_at = $2 WHERE id = $1`, caseID, now); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if input.Action == "mute" || input.Action == "ban" {
		if err := enqueueNotificationWithDataTx(tx, targetID, operator.ID, "moderation.action", "moderation_action", actionID, map[string]any{"action": input.Action, "reason": strings.TrimSpace(input.Reason), "appealable": true}, now); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"case_id": caseID, "action_id": actionID, "action": input.Action, "status": "resolved"})
}

func validManagedUserAction(input managedUserActionInput) bool {
	if strings.TrimSpace(input.Reason) == "" || len([]rune(input.Reason)) > 1000 || input.DurationDays < 0 || input.DurationDays > 365 {
		return false
	}
	switch input.Action {
	case "restore":
		return input.DurationDays == 0 && !input.Permanent
	case "mute", "ban":
		return true
	default:
		return false
	}
}
