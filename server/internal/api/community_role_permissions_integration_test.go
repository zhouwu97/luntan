package api

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"
)

func assignScopedIntegrationRole(t *testing.T, db *sql.DB, email, roleName, communityID string) string {
	t.Helper()
	var userID, roleID string
	if err := db.QueryRow(`SELECT id FROM users WHERE lower(email) = $1`, email).Scan(&userID); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRow(`SELECT id FROM roles WHERE name = $1`, roleName).Scan(&roleID); err != nil {
		t.Fatal(err)
	}
	roleAssignmentID := fmt.Sprintf("itest-scoped-ur-%d", time.Now().UnixNano())
	if _, err := db.Exec(`
		INSERT INTO user_roles (id, user_id, role_id, community_id)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT DO NOTHING`, roleAssignmentID, userID, roleID, communityID); err != nil {
		t.Fatal(err)
	}
	return userID
}

func insertCommunityModerationFixture(t *testing.T, db *sql.DB, postID, authorID, communityID, caseID string, createdAt time.Time) {
	t.Helper()
	if _, err := db.Exec(`
		INSERT INTO posts (
			id, author_id, community_id, type, publication_status, moderation_status,
			title, content, created_at, updated_at, published_at
		) VALUES ($1, $2, $3, 'normal', 'published', 'normal', $4, $5, $6, $6, $6)`,
		postID, authorID, communityID, "社区权限回归帖子 "+postID, "用于验证社区审核作用域", createdAt); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`
		INSERT INTO moderation_cases (id, target_type, target_id, source, risk_level, status, created_at)
		VALUES ($1, 'post', $2, 'integration_test', 'low', 'open', $3)`, caseID, postID, createdAt); err != nil {
		t.Fatal(err)
	}
}

func TestCommunityRolePermissionsAreScopedAndOperational(t *testing.T) {
	s := feedIntegrationServer(t)
	handler := NewHandler(s.db)
	suffix := time.Now().UnixNano()

	// 先验证 migration 确实把社区角色接到了审核入口所需的权限集合。
	wantPermissions := map[string][]string{
		"role-community-moderator": {"post.hide.community", "comment.hide.community", "member.mute", "moderation.action", "report.review"},
		"role-community-owner":     {"post.hide.community", "comment.hide.community", "member.mute", "member.ban", "community.edit", "moderation.action", "report.review"},
	}
	for roleID, names := range wantPermissions {
		for _, permissionName := range names {
			var exists bool
			if err := s.db.QueryRow(`
				SELECT EXISTS (
					SELECT 1
					FROM role_permissions rp
					JOIN permissions p ON p.id = rp.permission_id
					WHERE rp.role_id = $1 AND p.name = $2
				)`, roleID, permissionName).Scan(&exists); err != nil {
				t.Fatal(err)
			}
			if !exists {
				t.Fatalf("角色 %s 缺少社区权限 %s", roleID, permissionName)
			}
		}
	}

	moderatorEmail := fmt.Sprintf("itest-community-moderator-%d@example.com", suffix)
	moderatorName := fmt.Sprintf("itest_community_moderator_%d", suffix%100000000)
	moderatorToken := registerAndLogin(t, handler, moderatorEmail, moderatorName, "password123")
	moderatorID := assignScopedIntegrationRole(t, s.db, moderatorEmail, "community_moderator", "community-campus")
	_ = moderatorID

	authorOneEmail := fmt.Sprintf("itest-community-author-one-%d@example.com", suffix)
	authorOneName := fmt.Sprintf("itest_community_author_one_%d", suffix%100000000)
	registerAndLogin(t, handler, authorOneEmail, authorOneName, "password123")
	authorOneID := userIDByEmail(t, s.db, authorOneEmail)

	authorTwoEmail := fmt.Sprintf("itest-community-author-two-%d@example.com", suffix)
	authorTwoName := fmt.Sprintf("itest_community_author_two_%d", suffix%100000000)
	registerAndLogin(t, handler, authorTwoEmail, authorTwoName, "password123")
	authorTwoID := userIDByEmail(t, s.db, authorTwoEmail)

	now := time.Now().UTC()
	postInScope := fmt.Sprintf("itest-community-post-in-%d", suffix)
	caseInScope := fmt.Sprintf("itest-community-case-in-%d", suffix)
	insertCommunityModerationFixture(t, s.db, postInScope, authorOneID, "community-campus", caseInScope, now)

	postOutOfScope := fmt.Sprintf("itest-community-post-out-%d", suffix)
	caseOutOfScope := fmt.Sprintf("itest-community-case-out-%d", suffix)
	insertCommunityModerationFixture(t, s.db, postOutOfScope, authorTwoID, "community-daily", caseOutOfScope, now.Add(time.Second))

	status, body := callBusinessAPI(handler, http.MethodGet, "/api/v1/moderation/cases?status=open&limit=50", moderatorToken, nil, nil)
	if status != http.StatusOK {
		t.Fatalf("社区审核员读取案件列表应成功，实际 status=%d body=%s", status, body)
	}
	var list struct {
		Items []struct {
			ID          string `json:"id"`
			CommunityID string `json:"community_id"`
		} `json:"items"`
	}
	if err := json.Unmarshal(body, &list); err != nil {
		t.Fatal(err)
	}
	foundInScope, foundOutOfScope := false, false
	for _, item := range list.Items {
		if item.ID == caseInScope && item.CommunityID == "community-campus" {
			foundInScope = true
		}
		if item.ID == caseOutOfScope {
			foundOutOfScope = true
		}
	}
	if !foundInScope || foundOutOfScope {
		t.Fatalf("社区案件列表作用域错误：in_scope=%v out_of_scope=%v body=%s", foundInScope, foundOutOfScope, body)
	}

	status, body = callBusinessAPI(handler, http.MethodGet, "/api/v1/moderation/cases/"+caseOutOfScope, moderatorToken, nil, nil)
	if status != http.StatusForbidden || !strings.Contains(string(body), `"code":"PERMISSION_DENIED"`) {
		t.Fatalf("社区审核员读取其他社区案件应被拒绝，实际 status=%d body=%s", status, body)
	}
	status, body = callBusinessAPI(handler, http.MethodPost, "/api/v1/moderation/cases/"+caseOutOfScope+"/actions", moderatorToken, map[string]any{
		"action": "hide", "reason": "跨社区作用域回归测试",
	}, nil)
	if status != http.StatusForbidden || !strings.Contains(string(body), `"code":"PERMISSION_DENIED"`) {
		t.Fatalf("社区审核员处罚其他社区帖子应被拒绝，实际 status=%d body=%s", status, body)
	}
	assertPostNotModerated(t, s.db, postOutOfScope)

	status, body = callBusinessAPI(handler, http.MethodPost, "/api/v1/moderation/cases/"+caseInScope+"/actions", moderatorToken, map[string]any{
		"action": "hide", "reason": "本社区作用域回归测试",
	}, nil)
	if status != http.StatusOK {
		t.Fatalf("社区审核员处罚本社区帖子应成功，实际 status=%d body=%s", status, body)
	}
	var postStatus, moderationStatus string
	if err := s.db.QueryRow(`SELECT post_status, moderation_status FROM posts WHERE id = $1`, postInScope).Scan(&postStatus, &moderationStatus); err != nil {
		t.Fatal(err)
	}
	if postStatus != "hidden" || moderationStatus != "hidden" {
		t.Fatalf("本社区处罚未落库：post_status=%q moderation_status=%q", postStatus, moderationStatus)
	}

	// 申诉审核同样复用 report.review，但也必须按原处罚目标所在社区过滤。
	appealActionIn := fmt.Sprintf("itest-community-appeal-action-in-%d", suffix)
	appealActionOut := fmt.Sprintf("itest-community-appeal-action-out-%d", suffix)
	appealIn := fmt.Sprintf("itest-community-appeal-in-%d", suffix)
	appealOut := fmt.Sprintf("itest-community-appeal-out-%d", suffix)
	appealTime := now.Add(2 * time.Second)
	for actionID, caseID := range map[string]string{appealActionIn: caseInScope, appealActionOut: caseOutOfScope} {
		if _, err := s.db.Exec(`
			INSERT INTO moderation_actions (id, case_id, operator_id, action, reason, appealable, created_at)
			VALUES ($1, $2, $3, 'hide', '申诉作用域回归测试', true, $4)`, actionID, caseID, moderatorID, appealTime); err != nil {
			t.Fatal(err)
		}
	}
	type appealSeed struct {
		appealID string
		actionID string
		targetID string
		ownerID  string
	}
	for _, seed := range []appealSeed{
		{appealID: appealIn, actionID: appealActionIn, targetID: postInScope, ownerID: authorOneID},
		{appealID: appealOut, actionID: appealActionOut, targetID: postOutOfScope, ownerID: authorTwoID},
	} {
		appealID, actionID, targetID, ownerID := seed.appealID, seed.actionID, seed.targetID, seed.ownerID
		if _, err := s.db.Exec(`
			INSERT INTO moderation_appeals (id, user_id, moderation_action_id, target_type, target_id, reason, description, status, created_at, updated_at)
			VALUES ($1, $2, $3, 'post', $4, '申诉理由', '申诉描述', 'pending', $5, $5)`, appealID, ownerID, actionID, targetID, appealTime); err != nil {
			t.Fatal(err)
		}
	}

	status, body = callBusinessAPI(handler, http.MethodGet, "/api/v1/moderation/appeals?status=pending&limit=50", moderatorToken, nil, nil)
	if status != http.StatusOK {
		t.Fatalf("社区审核员读取申诉列表应成功，实际 status=%d body=%s", status, body)
	}
	var appealList struct {
		Items []struct {
			ID string `json:"id"`
		} `json:"items"`
	}
	if err := json.Unmarshal(body, &appealList); err != nil {
		t.Fatal(err)
	}
	foundAppealIn, foundAppealOut := false, false
	for _, item := range appealList.Items {
		if item.ID == appealIn {
			foundAppealIn = true
		}
		if item.ID == appealOut {
			foundAppealOut = true
		}
	}
	if !foundAppealIn || foundAppealOut {
		t.Fatalf("社区申诉列表作用域错误：in_scope=%v out_of_scope=%v body=%s", foundAppealIn, foundAppealOut, body)
	}

	status, body = callBusinessAPI(handler, http.MethodGet, "/api/v1/moderation/appeals/"+appealIn, moderatorToken, nil, nil)
	if status != http.StatusOK {
		t.Fatalf("社区审核员读取本社区申诉应成功，实际 status=%d body=%s", status, body)
	}
	status, body = callBusinessAPI(handler, http.MethodGet, "/api/v1/moderation/appeals/"+appealOut, moderatorToken, nil, nil)
	if status != http.StatusForbidden || !strings.Contains(string(body), `"code":"PERMISSION_DENIED"`) {
		t.Fatalf("社区审核员读取其他社区申诉应被拒绝，实际 status=%d body=%s", status, body)
	}
	status, body = callBusinessAPI(handler, http.MethodPost, "/api/v1/moderation/appeals/"+appealOut+"/review", moderatorToken, map[string]string{
		"result": "rejected", "note": "跨社区申诉作用域回归测试",
	}, nil)
	if status != http.StatusForbidden || !strings.Contains(string(body), `"code":"PERMISSION_DENIED"`) {
		t.Fatalf("社区审核员处理其他社区申诉应被拒绝，实际 status=%d body=%s", status, body)
	}
	var appealStatus string
	if err := s.db.QueryRow(`SELECT status FROM moderation_appeals WHERE id = $1`, appealOut).Scan(&appealStatus); err != nil {
		t.Fatal(err)
	}
	if appealStatus != "pending" {
		t.Fatalf("被拒绝的跨社区申诉不应改变状态，实际 %q", appealStatus)
	}

	for _, path := range []string{"/api/v1/admin/activities", "/api/v1/admin/recommendations", "/api/v1/admin/users"} {
		status, body = callBusinessAPI(handler, http.MethodGet, path, moderatorToken, nil, nil)
		if status != http.StatusForbidden || !strings.Contains(string(body), `"code":"PERMISSION_DENIED"`) {
			t.Fatalf("社区角色不应访问平台接口 %s，实际 status=%d body=%s", path, status, body)
		}
	}
}

func userIDByEmail(t *testing.T, db *sql.DB, email string) string {
	t.Helper()
	var userID string
	if err := db.QueryRow(`SELECT id FROM users WHERE lower(email) = $1`, email).Scan(&userID); err != nil {
		t.Fatal(err)
	}
	return userID
}

func assertPostNotModerated(t *testing.T, db *sql.DB, postID string) {
	t.Helper()
	var postStatus, moderationStatus string
	if err := db.QueryRow(`SELECT post_status, moderation_status FROM posts WHERE id = $1`, postID).Scan(&postStatus, &moderationStatus); err != nil {
		t.Fatal(err)
	}
	if postStatus != "published" || moderationStatus != "normal" {
		t.Fatalf("被拒绝的跨社区处罚产生了帖子副作用：post_status=%q moderation_status=%q", postStatus, moderationStatus)
	}
}
