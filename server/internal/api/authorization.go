package api

import (
	"context"
	"database/sql"
	"errors"
	"net/http"

	"github.com/zhouwu97/luntan/server/internal/auth"
)

var ErrRegisteredAccountRequired = errors.New("registered account required")

// capabilitiesForUser 是未查询角色权限前的基础能力集合。
// 游客仍然是可追踪的正式 users 记录，因此参与型能力保持开放；
// 发布、投票和收藏夹管理必须绑定邮箱账号，避免游客身份变成可批量生产内容的入口。
func capabilitiesForUser(user auth.User) map[string]bool {
	registered := user.AccountType != "guest"
	return map[string]bool{
		"can_publish":          registered,
		"can_create_poll":      registered,
		"can_manage_bookmarks": registered,
		"can_comment":          true,
		"can_like":             true,
		"can_report":           true,
		"can_moderate":         false,
		"can_manage_admins":    false,
		"can_ban_ip":           false,
		"can_view_admin_logs":  false,
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
		switch permission {
		case "moderation.action", "report.review":
			caps["can_moderate"] = true
		case "audit.read":
			caps["can_view_admin_logs"] = true
		case "user.ban.global":
			caps["can_ban_ip"] = true
		}
		if role == "super_admin" {
			caps["can_manage_admins"] = true
		}
	}
	if err := rows.Err(); err != nil {
		return err
	}
	user.Capabilities = caps
	return nil
}
