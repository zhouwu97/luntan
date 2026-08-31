package api

import (
	"context"
	"database/sql"
	"errors"
	"net/http"

	"github.com/zhouwu97/luntan/server/internal/auth"
)

var ErrRegisteredAccountRequired = errors.New("registered account required")
var ErrCapabilityRequired = errors.New("capability required")
var ErrUserMuted = errors.New("user is muted")

const (
	capPublish           = "can_publish"
	capCreatePoll        = "can_create_poll"
	capManageBookmarks   = "can_manage_bookmarks"
	capBookmark          = "can_bookmark"
	capComment           = "can_comment"
	capLike              = "can_like"
	capReport            = "can_report"
	capFollow            = "can_follow"
	capUploadMedia       = "can_upload_media"
	capVote              = "can_vote"
	capManageProfile     = "can_manage_profile"
	capModerate          = "can_moderate"
	capManageAdmins      = "can_manage_admins"
	capBanIP             = "can_ban_ip"
	capViewAdminLogs     = "can_view_admin_logs"
	capManageUsers       = "can_manage_users"
	capReviewStoreOrders = "can_review_store_orders"
)

// capabilitiesForUser 是未查询角色权限前的基础能力集合。
// 游客仍然是可追踪的正式 users 记录，因此评论和举报保持开放；
// 点赞、关注、发布、投票、收藏、上传和资料管理必须绑定邮箱账号，
// 所有客户端入口都以这份集合为准，后端仍是最终权限边界。
func capabilitiesForUser(user auth.User) map[string]bool {
	if user.ID == "" && user.Username == "" && user.AccountType == "" {
		return map[string]bool{
			capPublish:           false,
			capCreatePoll:        false,
			capManageBookmarks:   false,
			capBookmark:          false,
			capComment:           false,
			capLike:              false,
			capReport:            false,
			capFollow:            false,
			capUploadMedia:       false,
			capVote:              false,
			capManageProfile:     false,
			capModerate:          false,
			capManageAdmins:      false,
			capBanIP:             false,
			capViewAdminLogs:     false,
			capManageUsers:       false,
			capReviewStoreOrders: false,
		}
	}
	registered := user.AccountType != "guest"
	return map[string]bool{
		capPublish:         registered,
		capCreatePoll:      registered,
		capManageBookmarks: registered,
		capBookmark:        registered,
		capComment:         true,
		// 游客点赞属于低风险参与行为，保留历史产品规则；发布、收藏、关注等
		// 会形成长期账户资产或扩散关系的能力仍需邮箱账号。
		capLike:              true,
		capReport:            true,
		capFollow:            registered,
		capUploadMedia:       registered,
		capVote:              registered,
		capManageProfile:     registered,
		capModerate:          false,
		capManageAdmins:      false,
		capBanIP:             false,
		capViewAdminLogs:     false,
		capManageUsers:       false,
		capReviewStoreOrders: false,
	}
}

func applyPermissionCapability(caps map[string]bool, role, permission string) {
	switch permission {
	case "moderation.action", "report.review":
		caps[capModerate] = true
	case "audit.read":
		caps[capViewAdminLogs] = true
	case "user.ban.global":
		// IP 封禁影响网络范围，产品规则只允许 super_admin；平台管理员
		// 仍可处理账号级封禁，但不能获得 can_ban_ip 能力。
		if role == "super_admin" {
			caps[capBanIP] = true
		}
	case "user.manage":
		// 多角色聚合时行序不定，capability 只能从 false → true 累积，不能被回写。
		caps[capManageUsers] = caps[capManageUsers] || role == "platform_admin" || role == "super_admin"
	case "store.order.review":
		caps[capReviewStoreOrders] = true
	}
	if role == "super_admin" {
		caps[capManageAdmins] = true
	}
}

// canModerate 是所有平台审核能力的唯一授权入口。
// 客户端 capability 只用于控制界面展示，不能代替数据库中的全局权限判断。
func (s *Server) canModerate(r *http.Request, user auth.User) bool {
	return s != nil && s.db != nil && s.hasGlobalPermission(r, user.ID, "moderation.action")
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

func (s *Server) requireCapability(w http.ResponseWriter, r *http.Request, user auth.User, capability string) bool {
	caps := capabilitiesForUser(user)
	if capability == capComment {
		if err := s.applyActiveMute(r.Context(), &user, caps); err != nil {
			writeInternalError(w, r, err)
			return false
		}
		if user.CommentRestricted {
			writeAuthError(w, r, ErrUserMuted)
			return false
		}
	}
	if !caps[capability] {
		writeAuthError(w, r, ErrCapabilityRequired)
		return false
	}
	return true
}

func (s *Server) populateUserCapabilities(ctx context.Context, user *auth.User) error {
	if user == nil {
		return sql.ErrNoRows
	}
	var avatarMediaID, objectKey sql.NullString
	var exp int64
	var level int
	var accountType string
	if err := s.db.QueryRowContext(ctx, `
		SELECT COALESCE(up.avatar_media_id, ''), COALESCE(ma.object_key, ''),
		       COALESCE(up.experience, 0),
		       CASE WHEN u.account_type = 'guest' THEN 0 ELSE COALESCE(up.level, 1) END,
		       COALESCE(u.account_type, 'email')
		FROM users u
		LEFT JOIN user_profiles up ON up.user_id = u.id
		LEFT JOIN media_assets ma ON ma.id = up.avatar_media_id AND ma.status = 'ready' AND ma.deleted_at IS NULL
		WHERE u.id = $1`, user.ID).Scan(&avatarMediaID, &objectKey, &exp, &level, &accountType); err == nil {
		if avatarMediaID.Valid && avatarMediaID.String != "" {
			user.AvatarMediaID = avatarMediaID.String
		}
		if objectKey.Valid && objectKey.String != "" {
			user.AvatarURL = mediaVariantURL(avatarMediaID.String, objectKey.String, "thumb")
		}
		user.Experience = exp
		user.Level = level
		user.AccountType = accountType
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
	if err := s.applyActiveMute(ctx, user, caps); err != nil {
		return err
	}
	user.Capabilities = caps
	return nil
}

// applyActiveMute 将账号级禁言纳入统一能力结果。禁言不修改 users.status，
// 因此用户仍可浏览、查看通知和提交申诉，但所有评论入口都会被服务端拦截。
func (s *Server) applyActiveMute(ctx context.Context, user *auth.User, caps map[string]bool) error {
	if s == nil || s.db == nil || user == nil || user.ID == "" {
		return nil
	}
	user.CommentRestricted = false
	user.CommentRestrictedUntil = nil
	var endsAt sql.NullTime
	err := s.db.QueryRowContext(ctx, `
		SELECT ends_at
		FROM restrictions
		WHERE user_id = $1 AND restriction_type = 'mute'
		  AND starts_at <= now() AND (ends_at IS NULL OR ends_at > now())
		ORDER BY starts_at DESC, created_at DESC
		LIMIT 1`, user.ID).Scan(&endsAt)
	if errors.Is(err, sql.ErrNoRows) {
		return nil
	}
	if err != nil {
		return err
	}
	caps[capComment] = false
	user.CommentRestricted = true
	if endsAt.Valid {
		until := endsAt.Time
		user.CommentRestrictedUntil = &until
	}
	return nil
}
