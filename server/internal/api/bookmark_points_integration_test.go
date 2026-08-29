package api

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/zhouwu97/luntan/server/internal/auth"
	"github.com/zhouwu97/luntan/server/internal/platform/database"
)

// businessIntegrationFixture 只在配置 DATABASE_URL 时运行，避免普通单元测试依赖外部数据库。
// 测试数据使用纳秒后缀，并在测试结束后按外键顺序清理。
func businessIntegrationFixture(t *testing.T, rules PointRewardRules) (*Server, *sql.DB, auth.AuthResponse, string) {
	t.Helper()
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		t.Skip("DATABASE_URL 未配置，跳过真实 PostgreSQL 收藏/积分集成测试")
	}
	db, err := database.Open(databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	if err := database.Migrate(context.Background(), db, filepath.Join("..", "..", "migrations")); err != nil {
		db.Close()
		t.Fatal(err)
	}

	suffix := fmt.Sprintf("%d", time.Now().UnixNano())
	authResponse, err := auth.NewService(db).Register(context.Background(), auth.RegisterInput{
		Username: "biz_integration_" + suffix,
		Password: "安全密码12345",
		Nickname: "业务集成测试",
	}, auth.SessionMetadata{UserAgent: "bookmark-points-integration", IPAddress: "127.0.0.1"})
	if err != nil {
		db.Close()
		t.Fatal(err)
	}
	categoryID := "biz-category-" + suffix
	communityID := "biz-community-" + suffix
	postID := "biz-post-" + suffix
	if _, err := db.Exec(`INSERT INTO community_categories (id, name, slug) VALUES ($1, $2, $3)`, categoryID, "业务集成", "biz-"+suffix); err != nil {
		db.Close()
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO communities (id, category_id, slug, name, status) VALUES ($1, $2, $3, $4, 'active')`, communityID, categoryID, "biz-community-"+suffix, "业务集成社区"); err != nil {
		db.Close()
		t.Fatal(err)
	}
	if _, err := db.Exec(`
		INSERT INTO posts (id, author_id, community_id, type, publication_status, moderation_status,
			title, content, created_at, updated_at, published_at)
		VALUES ($1, $2, $3, 'normal', 'published', 'normal', '业务集成帖子', '用于验证并发关系', now(), now(), now())`, postID, authResponse.User.ID, communityID); err != nil {
		db.Close()
		t.Fatal(err)
	}

	t.Cleanup(func() {
		// 测试只创建下列业务数据；清理失败不掩盖主测试结果，但会留下可定位日志。
		cleanupQueries := []struct {
			query string
			args  []any
		}{
			{`DELETE FROM bookmark_folders WHERE user_id = $1`, []any{authResponse.User.ID}},
			{`DELETE FROM bookmarks WHERE user_id = $1`, []any{authResponse.User.ID}},
			{`DELETE FROM point_transactions WHERE user_id = $1`, []any{authResponse.User.ID}},
			{`DELETE FROM outbox_events WHERE aggregate_id = $1`, []any{postID}},
			{`DELETE FROM post_revisions WHERE post_id = $1`, []any{postID}},
			{`DELETE FROM posts WHERE id = $1`, []any{postID}},
			{`DELETE FROM communities WHERE id = $1`, []any{communityID}},
			{`DELETE FROM community_categories WHERE id = $1`, []any{categoryID}},
			{`DELETE FROM refresh_tokens WHERE user_id = $1`, []any{authResponse.User.ID}},
			{`DELETE FROM sessions WHERE user_id = $1`, []any{authResponse.User.ID}},
			{`DELETE FROM user_auth_methods WHERE user_id = $1`, []any{authResponse.User.ID}},
			{`DELETE FROM user_profiles WHERE user_id = $1`, []any{authResponse.User.ID}},
			{`DELETE FROM users WHERE id = $1`, []any{authResponse.User.ID}},
		}
		for _, item := range cleanupQueries {
			if _, err := db.Exec(item.query, item.args...); err != nil {
				t.Logf("清理测试数据失败 query=%q err=%v", item.query, err)
			}
		}
		db.Close()
	})

	return NewHandlerWithPointRewards(db, rules).(*Server), db, authResponse, postID
}

func callBusinessAPI(handler http.Handler, method, path, token string, payload any, headers map[string]string) (int, []byte) {
	var body *bytes.Reader
	if payload == nil {
		body = bytes.NewReader(nil)
	} else {
		encoded, err := json.Marshal(payload)
		if err != nil {
			return http.StatusInternalServerError, []byte(err.Error())
		}
		body = bytes.NewReader(encoded)
	}
	req := httptest.NewRequest(method, path, body)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	for key, value := range headers {
		req.Header.Set(key, value)
	}
	res := httptest.NewRecorder()
	handler.ServeHTTP(res, req)
	return res.Code, res.Body.Bytes()
}

func createBusinessFolder(t *testing.T, handler http.Handler, token, name, idempotencyKey string) string {
	t.Helper()
	status, body := callBusinessAPI(handler, http.MethodPost, "/api/v1/me/bookmark-folders", token, map[string]string{"name": name}, map[string]string{"Idempotency-Key": idempotencyKey})
	if status != http.StatusCreated {
		t.Fatalf("创建收藏夹 status=%d body=%s", status, body)
	}
	var response struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(body, &response); err != nil {
		t.Fatal(err)
	}
	if response.ID == "" {
		t.Fatalf("创建收藏夹缺少 id: %s", body)
	}
	return response.ID
}

func TestBookmarkFoldersAreSafeAgainstConcurrentWritesAgainstPostgres(t *testing.T) {
	server, db, authResponse, postID := businessIntegrationFixture(t, PointRewardRules{})
	defaultID := ""
	status, body := callBusinessAPI(server, http.MethodGet, "/api/v1/me/bookmark-folders", authResponse.AccessToken, nil, nil)
	if status != http.StatusOK {
		t.Fatalf("读取默认收藏夹 status=%d body=%s", status, body)
	}
	var foldersResponse struct {
		Items []struct {
			ID        string `json:"id"`
			IsDefault bool   `json:"is_default"`
		} `json:"items"`
	}
	if err := json.Unmarshal(body, &foldersResponse); err != nil {
		t.Fatal(err)
	}
	for _, folder := range foldersResponse.Items {
		if folder.IsDefault {
			defaultID = folder.ID
		}
	}
	if defaultID == "" {
		t.Fatal("首次读取没有自动创建默认收藏夹")
	}
	folderA := createBusinessFolder(t, server, authResponse.AccessToken, "并发 A", "folder-a-"+postID)
	folderB := createBusinessFolder(t, server, authResponse.AccessToken, "并发 B", "folder-b-"+postID)

	// 同一个幂等键并发创建只能得到一个收藏夹；其余请求应返回已创建资源，而不是 409。
	var createWG sync.WaitGroup
	createErrors := make(chan string, 10)
	for i := 0; i < 10; i++ {
		createWG.Add(1)
		go func() {
			defer createWG.Done()
			status, body := callBusinessAPI(server, http.MethodPost, "/api/v1/me/bookmark-folders", authResponse.AccessToken, map[string]string{"name": "幂等收藏夹"}, map[string]string{"Idempotency-Key": "same-folder-key-" + postID})
			if status != http.StatusCreated && status != http.StatusOK {
				createErrors <- fmt.Sprintf("status=%d body=%s", status, body)
			}
		}()
	}
	createWG.Wait()
	close(createErrors)
	for err := range createErrors {
		t.Error("并发创建收藏夹失败: " + err)
	}
	var sameNameCount int
	if err := db.QueryRow(`SELECT COUNT(*) FROM bookmark_folders WHERE user_id = $1 AND name = '幂等收藏夹'`, authResponse.User.ID).Scan(&sameNameCount); err != nil {
		t.Fatal(err)
	}
	if sameNameCount != 1 {
		t.Fatalf("相同幂等键创建了 %d 个收藏夹，want 1", sameNameCount)
	}

	concurrentSet := func(folderIDs []string, count int) {
		t.Helper()
		var wg sync.WaitGroup
		errs := make(chan string, count)
		for i := 0; i < count; i++ {
			wg.Add(1)
			go func() {
				defer wg.Done()
				status, body := callBusinessAPI(server, http.MethodPut, "/api/v1/posts/"+postID+"/bookmark-folders", authResponse.AccessToken, map[string]any{"folder_ids": folderIDs}, nil)
				if status != http.StatusOK {
					errs <- fmt.Sprintf("status=%d body=%s", status, body)
				}
			}()
		}
		wg.Wait()
		close(errs)
		for err := range errs {
			t.Error("并发设置收藏夹失败: " + err)
		}
	}

	// 旧 bookmark API 与同一帖子并发收藏，只能形成一条收藏事实和一次计数增加。
	var bookmarkWG sync.WaitGroup
	bookmarkErrors := make(chan string, 10)
	for i := 0; i < 10; i++ {
		bookmarkWG.Add(1)
		go func() {
			defer bookmarkWG.Done()
			status, body := callBusinessAPI(server, http.MethodPut, "/api/v1/posts/"+postID+"/bookmark", authResponse.AccessToken, nil, nil)
			if status != http.StatusOK {
				bookmarkErrors <- fmt.Sprintf("status=%d body=%s", status, body)
			}
		}()
	}
	bookmarkWG.Wait()
	close(bookmarkErrors)
	for err := range bookmarkErrors {
		t.Error("并发旧收藏接口失败: " + err)
	}

	concurrentSet([]string{folderA, folderB}, 12)
	var bookmarkCount, relationCount int
	if err := db.QueryRow(`SELECT COUNT(*) FROM bookmarks WHERE post_id = $1 AND user_id = $2`, postID, authResponse.User.ID).Scan(&bookmarkCount); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRow(`SELECT COUNT(*) FROM bookmark_folder_items fi JOIN bookmark_folders f ON f.id = fi.folder_id WHERE fi.post_id = $1 AND f.user_id = $2`, postID, authResponse.User.ID).Scan(&relationCount); err != nil {
		t.Fatal(err)
	}
	if bookmarkCount != 1 || relationCount != 2 {
		t.Fatalf("多收藏夹关系不正确 bookmarks=%d relations=%d", bookmarkCount, relationCount)
	}
	if err := db.QueryRow(`SELECT bookmark_count FROM posts WHERE id = $1`, postID).Scan(&bookmarkCount); err != nil {
		t.Fatal(err)
	}
	if bookmarkCount != 1 {
		t.Fatalf("多收藏夹重复增加 bookmark_count=%d, want 1", bookmarkCount)
	}

	// 从 B 移到 A 仍是收藏；只有清空最后一个关系才取消收藏。
	concurrentSet([]string{folderA}, 1)
	if err := db.QueryRow(`SELECT COUNT(*) FROM bookmarks WHERE post_id = $1 AND user_id = $2`, postID, authResponse.User.ID).Scan(&bookmarkCount); err != nil {
		t.Fatal(err)
	}
	if bookmarkCount != 1 {
		t.Fatalf("移动收藏夹错误取消收藏，count=%d", bookmarkCount)
	}

	// 删除仍有内容的自定义收藏夹时，帖子必须回退到默认夹而不能丢失收藏事实。
	status, body = callBusinessAPI(server, http.MethodDelete, "/api/v1/me/bookmark-folders/"+folderA, authResponse.AccessToken, nil, nil)
	if status != http.StatusNoContent {
		t.Fatalf("删除自定义收藏夹 status=%d body=%s", status, body)
	}
	if err := db.QueryRow(`SELECT COUNT(*) FROM bookmarks WHERE post_id = $1 AND user_id = $2`, postID, authResponse.User.ID).Scan(&bookmarkCount); err != nil {
		t.Fatal(err)
	}
	if bookmarkCount != 1 {
		t.Fatal("删除收藏夹错误删除 bookmarks 收藏事实")
	}
	var defaultItems int
	if err := db.QueryRow(`SELECT COUNT(*) FROM bookmark_folder_items WHERE folder_id = $1 AND post_id = $2`, defaultID, postID).Scan(&defaultItems); err != nil {
		t.Fatal(err)
	}
	if defaultItems != 1 {
		t.Fatalf("孤立帖子没有回退到默认收藏夹，items=%d", defaultItems)
	}

	status, body = callBusinessAPI(server, http.MethodPut, "/api/v1/posts/"+postID+"/bookmark-folders", authResponse.AccessToken, map[string]any{"folder_ids": []string{}}, nil)
	if status != http.StatusOK {
		t.Fatalf("清空最后收藏关系 status=%d body=%s", status, body)
	}
	if err := db.QueryRow(`SELECT COUNT(*) FROM bookmarks WHERE post_id = $1 AND user_id = $2`, postID, authResponse.User.ID).Scan(&bookmarkCount); err != nil {
		t.Fatal(err)
	}
	if bookmarkCount != 0 {
		t.Fatalf("清空最后收藏关系后仍保留 bookmarks=%d", bookmarkCount)
	}
	if err := db.QueryRow(`SELECT bookmark_count FROM posts WHERE id = $1`, postID).Scan(&bookmarkCount); err != nil {
		t.Fatal(err)
	}
	if bookmarkCount != 0 {
		t.Fatalf("取消最后收藏后 bookmark_count=%d, want 0", bookmarkCount)
	}

	// 删除默认收藏夹必须被业务层拒绝。
	status, body = callBusinessAPI(server, http.MethodDelete, "/api/v1/me/bookmark-folders/"+defaultID, authResponse.AccessToken, nil, nil)
	if status != http.StatusBadRequest {
		t.Fatalf("删除默认收藏夹 status=%d body=%s", status, body)
	}
}

func TestAwardPointsTxIsIdempotentAgainstConcurrentTransactionsAgainstPostgres(t *testing.T) {
	_, db, authResponse, postID := businessIntegrationFixture(t, PointRewardRules{})
	const workers = 10
	var wg sync.WaitGroup
	errs := make(chan error, workers)
	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			tx, err := db.BeginTx(context.Background(), nil)
			if err != nil {
				errs <- err
				return
			}
			if err := awardPointsTx(context.Background(), tx, authResponse.User.ID, "post", "并发奖励", "post:create:"+postID, 10, 0); err != nil {
				_ = tx.Rollback()
				errs <- err
				return
			}
			if err := tx.Commit(); err != nil {
				errs <- err
			}
		}()
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		t.Error("并发奖励事务失败: " + err.Error())
	}

	var balance int64
	if err := db.QueryRow(`SELECT points_balance FROM users WHERE id = $1`, authResponse.User.ID).Scan(&balance); err != nil {
		t.Fatal(err)
	}
	if balance != 10 {
		t.Fatalf("同一积分事件重复请求后的余额=%d, want 10", balance)
	}
	var transactionCount int
	if err := db.QueryRow(`SELECT COUNT(*) FROM point_transactions WHERE user_id = $1 AND idempotency_key = $2`, authResponse.User.ID, "post:create:"+postID).Scan(&transactionCount); err != nil {
		t.Fatal(err)
	}
	if transactionCount != 1 {
		t.Fatalf("同一积分事件生成 %d 条流水，want 1", transactionCount)
	}
}
