package api

import (
	"context"
	"database/sql"
	"errors"
	"net/http"

	"github.com/zhouwu97/luntan/server/internal/auth"
)

var ErrRegisteredAccountRequired = errors.New("registered account required")

const (
	capPublish         = "can_publish"
	capCreatePoll      = "can_create_poll"
	capManageBookmarks = "can_manage_bookmarks"
	capComment         = "can_comment"
	capLike            = "can_like"
	capReport          = "can_report"
	capModerate        = "can_moderate"
	capManageAdmins    = "can_manage_admins"
	capBanIP           = "can_ban_ip"
	capViewAdminLogs   = "can_view_admin_logs"
)

// capabilitiesForUser 是未查询角色权限前的基础能力集合。
// 游客仍然是可追踪的正式 users 记录，因此参与型能力保持开放；
// 发布、投票和收藏夹管理必须绑定邮箱账号，避免游客身份变成可批量生产内容的入口。
func capabilitiesForUser(user auth.User) map[string]bool {
	if user.ID == "" && user.Username == "" && user.AccountType == "" {
		return map[string]bool{
			capPublish:         false,
			capCreatePoll:      false,
			capManageBookmarks: false,
			capComment:         false,
			capLike:            false,
			capReport:          false,
			capModerate:        false,
			capManageAdmins:    false,
			capBanIP:           false,
			capViewAdminLogs:   false,
		}
	}
	registered := user.AccountType != "guest"
	return map[string]bool{
		capPublish:         registered,
		capCreatePoll:      registered,
		capManageBookmarks: registered,
		capComment:         true,
		capLike:            true,
		capReport:          true,
		capModerate:        false,
		capManageAdmins:    false,
		capBanIP:           false,
		capViewAdminLogs:   false,
	}
}

func applyPermissionCapability(caps map[string]bool, role, permission string) {
	switch permission {
	case "moderation.action", "report.review":
		caps[capModerate] = true
	case "audit.read":
		caps[capViewAdminLogs] = true
	case "user.ban.global":
		caps[capBanIP] = true
	}
	if role == "super_admin" {
		caps[capManageAdmins] = true
	}
}

func (s *Server) requireRegisteredUser(w http.ResponseWriter, r *http.Request) (auth.User, bool) {
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return auth.User{}, false
	}
	if !capabilitiesForUser(user)["can_publish"] {
		writeAuthError(w, r, ErrRegisteredAccountRequired)
		return auth.User{}, false
	}
	return user, true
}

func (s *Server) populateUserCapabilities(ctx context.Context, user *auth.User) error {
	if user == nil {
		return sql.ErrNoRows
	}
	caps := capabilitiesForUser(*user)
	rows, err := s.db.QueryContext(ctx, `
		SELECT DISTINCT rl.name, p.name
		FROM user_roles ur
		JOIN roles rl ON rl.id = ur.role_id
		JOIN role_permissions rp ON rp.role_id = ur.role_id
		JOIN permissions p ON p.id = rp.permission_id
		WHERE ur.user_id = $1`, user.ID)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var role, permission string
		if err := rows.Scan(&role, &permission); err != nil {
			return err
		}
		applyPermissionCapability(caps, role, permission)
	}
	if err := rows.Err(); err != nil {
		return err
	}
	user.Capabilities = caps
	return nil
}
