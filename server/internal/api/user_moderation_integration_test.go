package api

import (
	"database/sql"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"
)

func assignIntegrationRole(t *testing.T, db *sql.DB, email, roleName string) string {
	t.Helper()
	var userID, roleID string
	if err := db.QueryRow(`SELECT id FROM users WHERE lower(email) = $1`, email).Scan(&userID); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRow(`SELECT id FROM roles WHERE name = $1`, roleName).Scan(&roleID); err != nil {
		t.Fatal(err)
	}
	roleAssignmentID := fmt.Sprintf("itest-ur-%d-%s-%s", time.Now().UnixNano(), userID, roleName)
	if _, err := db.Exec(`
		INSERT INTO user_roles (id, user_id, role_id, community_id)
		VALUES ($1, $2, $3, NULL)
		ON CONFLICT DO NOTHING`, roleAssignmentID, userID, roleID); err != nil {
		t.Fatal(err)
	}
	return userID
}

func assertNoUserModerationMutation(t *testing.T, db *sql.DB, targetID string) {
	t.Helper()
	var status string
	if err := db.QueryRow(`SELECT status FROM users WHERE id = $1`, targetID).Scan(&status); err != nil {
		t.Fatal(err)
	}
	if status != "active" {
		t.Fatalf("被拒绝的用户处罚不应改变 users.status，实际 %q", status)
	}
	var bans, restrictions, actions, cases, auditLogs, adminLogs int
	if err := db.QueryRow(`SELECT count(*) FROM bans WHERE user_id = $1`, targetID).Scan(&bans); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRow(`SELECT count(*) FROM restrictions WHERE user_id = $1`, targetID).Scan(&restrictions); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRow(`
		SELECT count(*)
		FROM moderation_actions ma
		JOIN moderation_cases mc ON mc.id = ma.case_id
		WHERE mc.target_type = 'user' AND mc.target_id = $1`, targetID).Scan(&actions); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRow(`SELECT count(*) FROM moderation_cases WHERE target_type = 'user' AND target_id = $1`, targetID).Scan(&cases); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRow(`SELECT count(*) FROM audit_logs WHERE target_type = 'user' AND target_id = $1`, targetID).Scan(&auditLogs); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRow(`SELECT count(*) FROM admin_logs WHERE target_type = 'user' AND target_id = $1`, targetID).Scan(&adminLogs); err != nil {
		t.Fatal(err)
	}
	if bans != 0 || restrictions != 0 || actions != 0 || cases != 0 || auditLogs != 0 || adminLogs != 0 {
		t.Fatalf("被拒绝的用户处罚产生了副作用: bans=%d restrictions=%d actions=%d cases=%d audit_logs=%d admin_logs=%d", bans, restrictions, actions, cases, auditLogs, adminLogs)
	}
}

func TestUserModerationEnforcesTargetRoleHierarchy(t *testing.T) {
	s := feedIntegrationServer(t)
	handler := NewHandler(s.db)
	suffix := time.Now().UnixNano()

	adminEmail := fmt.Sprintf("itest-role-admin-%d@example.com", suffix)
	adminName := fmt.Sprintf("itest_role_admin_%d", suffix%100000000)
	adminToken := registerAndLogin(t, handler, adminEmail, adminName, "password123")
	assignIntegrationRole(t, s.db, adminEmail, "platform_admin")

	superEmail := fmt.Sprintf("itest-role-super-%d@example.com", suffix)
	superName := fmt.Sprintf("itest_role_super_%d", suffix%100000000)
	registerAndLogin(t, handler, superEmail, superName, "password123")
	superID := assignIntegrationRole(t, s.db, superEmail, "super_admin")

	for _, action := range []string{"ban", "mute", "restore"} {
		status, body := callBusinessAPI(handler, http.MethodPost, "/api/v1/admin/users/"+superID+"/actions", adminToken, map[string]any{
			"action":        action,
			"reason":        "角色层级回归测试",
			"permanent":     action != "restore",
			"duration_days": 0,
		}, nil)
		if status != http.StatusForbidden || !strings.Contains(string(body), `"code":"TARGET_ROLE_PROTECTED"`) {
			t.Fatalf("platform_admin %s super_admin 应返回 TARGET_ROLE_PROTECTED，实际 status=%d body=%s", action, status, body)
		}
		assertNoUserModerationMutation(t, s.db, superID)
	}

	equalAdminEmail := fmt.Sprintf("itest-role-admin-peer-%d@example.com", suffix)
	equalAdminName := fmt.Sprintf("itest_role_admin_peer_%d", suffix%100000000)
	registerAndLogin(t, handler, equalAdminEmail, equalAdminName, "password123")
	equalAdminID := assignIntegrationRole(t, s.db, equalAdminEmail, "platform_admin")
	status, body := callBusinessAPI(handler, http.MethodPost, "/api/v1/admin/users/"+equalAdminID+"/actions", adminToken, map[string]any{
		"action": "ban", "reason": "同级角色回归测试", "permanent": true,
	}, nil)
	if status != http.StatusForbidden || !strings.Contains(string(body), `"code":"TARGET_ROLE_PROTECTED"`) {
		t.Fatalf("platform_admin 不应处罚同级 platform_admin，实际 status=%d body=%s", status, body)
	}
	assertNoUserModerationMutation(t, s.db, equalAdminID)

	normalEmail := fmt.Sprintf("itest-role-normal-%d@example.com", suffix)
	normalName := fmt.Sprintf("itest_role_normal_%d", suffix%100000000)
	normalToken := registerAndLogin(t, handler, normalEmail, normalName, "password123")
	normalID := assignIntegrationRole(t, s.db, normalEmail, "user")
	status, body = callBusinessAPI(handler, http.MethodPost, "/api/v1/admin/users/"+superID+"/actions", normalToken, map[string]any{
		"action": "ban", "reason": "普通用户越权回归测试", "permanent": true,
	}, nil)
	if status != http.StatusForbidden || !strings.Contains(string(body), `"code":"PERMISSION_DENIED"`) {
		t.Fatalf("normal 用户不应调用管理员处罚接口，实际 status=%d body=%s", status, body)
	}
	_ = normalID
	assertNoUserModerationMutation(t, s.db, superID)

	superOperatorEmail := fmt.Sprintf("itest-role-super-operator-%d@example.com", suffix)
	superOperatorName := fmt.Sprintf("itest_role_super_operator_%d", suffix%100000000)
	superOperatorToken := registerAndLogin(t, handler, superOperatorEmail, superOperatorName, "password123")
	superOperatorID := assignIntegrationRole(t, s.db, superOperatorEmail, "super_admin")
	_ = superOperatorID

	targetNormalEmail := fmt.Sprintf("itest-role-target-normal-%d@example.com", suffix)
	targetNormalName := fmt.Sprintf("itest_role_target_normal_%d", suffix%100000000)
	registerAndLogin(t, handler, targetNormalEmail, targetNormalName, "password123")
	targetNormalID := assignIntegrationRole(t, s.db, targetNormalEmail, "user")
	status, body = callBusinessAPI(handler, http.MethodPost, "/api/v1/admin/users/"+targetNormalID+"/actions", superOperatorToken, map[string]any{
		"action": "ban", "reason": "超级管理员正常治理回归测试", "permanent": true,
	}, nil)
	if status != http.StatusOK {
		t.Fatalf("super_admin 处罚普通用户应成功，实际 status=%d body=%s", status, body)
	}
	var targetStatus string
	if err := s.db.QueryRow(`SELECT status FROM users WHERE id = $1`, targetNormalID).Scan(&targetStatus); err != nil {
		t.Fatal(err)
	}
	if targetStatus != "suspended" {
		t.Fatalf("super_admin ban 后目标状态=%q，期望 suspended", targetStatus)
	}
}
