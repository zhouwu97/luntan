package api

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"sync"
	"testing"
	"time"

	"github.com/zhouwu97/luntan/server/internal/auth"
)

func aftercareSession(t *testing.T, s *Server, name string) auth.AuthResponse {
	t.Helper()
	session, err := auth.NewService(s.db).Register(context.Background(), auth.RegisterInput{
		Username: fmt.Sprintf("aftercare_%s_%d", name, time.Now().UnixNano()), Password: "安全密码12345", Nickname: name,
	}, auth.SessionMetadata{UserAgent: "aftercare-integration", IPAddress: "127.0.0.1"})
	if err != nil {
		t.Fatal(err)
	}
	// 只清理本用例的通知队列，避免多次运行占满其他用例的 worker 批次。
	t.Cleanup(func() {
		if _, err := s.db.Exec(`DELETE FROM outbox_events WHERE event_type = 'notification.created' AND (payload->>'recipient_id' = $1 OR payload->>'actor_id' = $1)`, session.User.ID); err != nil {
			t.Errorf("清理通知队列: %v", err)
		}
		if _, err := s.db.Exec(`DELETE FROM notifications WHERE user_id = $1 OR actor_id = $1`, session.User.ID); err != nil {
			t.Errorf("清理通知: %v", err)
		}
	})
	return session
}

func TestStoreAftercareAgainstPostgres(t *testing.T) {
	s := feedIntegrationServer(t)
	t.Cleanup(func() { s.db.Close() })
	handler := NewHandler(s.db)
	owner, admin, other := aftercareSession(t, s, "owner"), aftercareSession(t, s, "admin"), aftercareSession(t, s, "other")
	if _, err := s.db.Exec(`INSERT INTO user_roles (id, user_id, role_id) VALUES ($1, $2, 'role-super-admin')`, newPostID(), admin.User.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`UPDATE users SET points_balance = 5000 WHERE id = $1`, owner.User.ID); err != nil {
		t.Fatal(err)
	}
	productID := newPostID()
	if _, err := s.db.Exec(`INSERT INTO store_products (id, name, points, stock_total) VALUES ($1, '售后测试徽章', 60, 20)`, productID); err != nil {
		t.Fatal(err)
	}
	call := func(method, path, token string, body any, key string, want int) map[string]any {
		t.Helper()
		code, response := callBusinessAPI(handler, method, path, token, body, map[string]string{"Idempotency-Key": key})
		if code != want {
			t.Fatalf("%s %s status=%d want=%d body=%s", method, path, code, want, response)
		}
		var result map[string]any
		if err := json.Unmarshal(response, &result); err != nil {
			t.Fatal(err)
		}
		return result
	}
	create := func() string {
		return call("POST", "/api/v1/store/orders", owner.AccessToken, map[string]string{"product_id": productID}, newPostID(), 201)["id"].(string)
	}
	approve := func(id string) {
		call("POST", "/api/v1/admin/store/orders/"+id+"/review", admin.AccessToken, map[string]string{"decision": "approve"}, "", 200)
	}
	address := func(id string) {
		call("PUT", "/api/v1/me/store-orders/"+id+"/shipping", owner.AccessToken, map[string]string{"recipient_name": "测试", "phone": "13800000000", "province": "辽宁", "city": "沈阳", "address_detail": "测试宿舍 101"}, "", 200)
	}
	ship := func(id string) {
		address(id)
		call("POST", "/api/v1/admin/store/orders/"+id+"/ship", admin.AccessToken, map[string]string{"carrier": "测试物流", "tracking_no": "OUT123"}, "", 200)
	}
	reverse := func(id, action, token string, adminPath bool, key string, want int) map[string]any {
		prefix := "/api/v1/me/store-orders/"
		if adminPath {
			prefix = "/api/v1/admin/store/orders/"
		}
		return call("POST", prefix+id+"/reverse", token, map[string]any{"action": action, "reason": "测试操作", "return_received": action == "refund", "restock": action == "refund"}, key, want)
	}
	snapshot := func() (int64, int, int) {
		t.Helper()
		var balance int64
		var reserved, fulfilled int
		if err := s.db.QueryRow(`SELECT points_balance FROM users WHERE id = $1`, owner.User.ID).Scan(&balance); err != nil {
			t.Fatal(err)
		}
		if err := s.db.QueryRow(`SELECT stock_reserved, stock_fulfilled FROM store_products WHERE id = $1`, productID).Scan(&reserved, &fulfilled); err != nil {
			t.Fatal(err)
		}
		return balance, reserved, fulfilled
	}
	assertRestored := func() {
		t.Helper()
		b, r, f := snapshot()
		if b != 5000 || r != 0 || f != 0 {
			t.Fatalf("余额/库存未恢复: %d/%d/%d", b, r, f)
		}
	}

	for _, state := range []string{"pending_review", "awaiting_address", "ready_to_ship"} {
		t.Run("cancel_"+state, func(t *testing.T) {
			id := create()
			if state != "pending_review" {
				approve(id)
			}
			if state == "ready_to_ship" {
				address(id)
			}
			reverse(id, "cancel", other.AccessToken, false, newPostID(), 404)
			reverse(id, "refund", owner.AccessToken, false, newPostID(), 403)
			key := newPostID()
			token, adminPath := owner.AccessToken, false
			if state == "ready_to_ship" {
				token, adminPath = admin.AccessToken, true
			}
			got := reverse(id, "cancel", token, adminPath, key, 200)
			if got["status"] != "cancelled" {
				t.Fatal(got)
			}
			reverse(id, "cancel", token, adminPath, key, 200)
			reverse(id, "request_return", token, adminPath, key, 409)
			reverse(id, "cancel", token, adminPath, newPostID(), 409)
			assertRestored()
			var refunds, notifications, logs int
			s.db.QueryRow(`SELECT COUNT(*) FROM point_transactions WHERE idempotency_key = $1`, "store:refund:"+id).Scan(&refunds)
			s.db.QueryRow(`SELECT COUNT(*) FROM notifications WHERE target_id = $1 AND type = 'store.order.cancel'`, id).Scan(&notifications)
			s.db.QueryRow(`SELECT COUNT(*) FROM admin_logs WHERE target_id = $1 AND action = 'store.order.cancel'`, id).Scan(&logs)
			wantRefunds := 1
			if state == "pending_review" {
				wantRefunds = 0
			}
			if refunds != wantRefunds || notifications != 1 || logs != 1 {
				t.Fatalf("重复副作用: refund=%d notification=%d log=%d", refunds, notifications, logs)
			}
		})
	}
	for _, completed := range []bool{false, true} {
		t.Run(fmt.Sprintf("return_completed_%v", completed), func(t *testing.T) {
			id := create()
			approve(id)
			ship(id)
			original := "shipped"
			if completed {
				call("POST", "/api/v1/me/store-orders/"+id+"/complete", owner.AccessToken, nil, "", 200)
				original = "completed"
			}
			reverse(id, "cancel", admin.AccessToken, true, newPostID(), 409)
			reverse(id, "refund", admin.AccessToken, true, newPostID(), 409)
			reverse(id, "request_return", owner.AccessToken, false, newPostID(), 200)
			got := reverse(id, "reject_return", admin.AccessToken, true, newPostID(), 200)
			if got["fulfillment_status"] != original {
				t.Fatal(got)
			}
			reverse(id, "request_return", owner.AccessToken, false, newPostID(), 200)
			reverse(id, "approve_return", admin.AccessToken, true, newPostID(), 200)
			call("POST", "/api/v1/admin/store/orders/"+id+"/reverse", admin.AccessToken, map[string]string{"action": "refund", "reason": "尚未收到退货"}, newPostID(), 409)
			call("POST", "/api/v1/me/store-orders/"+id+"/reverse", owner.AccessToken, map[string]string{"action": "return_shipping", "reason": "已寄回", "carrier": "回寄物流", "tracking_no": "RETURN123"}, newPostID(), 200)
			data := call("GET", "/api/v1/me/store-orders/"+id+"/aftercare", owner.AccessToken, nil, "", 200)
			if data["tracking_no"] != "RETURN123" {
				t.Fatal(data)
			}
			// 两个并发重试共用一个请求键，只能产生一笔退款。
			key := newPostID()
			var wg sync.WaitGroup
			codes := make(chan int, 2)
			for range 2 {
				wg.Add(1)
				go func() {
					defer wg.Done()
					code, _ := callBusinessAPI(handler, "POST", "/api/v1/admin/store/orders/"+id+"/reverse", admin.AccessToken, map[string]any{"action": "refund", "reason": "已收回", "return_received": true, "restock": true}, map[string]string{"Idempotency-Key": key})
					codes <- code
				}()
			}
			wg.Wait()
			close(codes)
			for code := range codes {
				if code != 200 {
					t.Fatalf("并发退款返回 %d", code)
				}
			}
			assertRestored()
			call("POST", "/api/v1/me/store-orders/"+id+"/complete", owner.AccessToken, nil, "", 409)
		})
	}
	t.Run("cancel_races_with_shipping", func(t *testing.T) {
		id := create()
		approve(id)
		address(id)
		var cancelCode, shipCode int
		var wg sync.WaitGroup
		wg.Add(2)
		go func() {
			defer wg.Done()
			cancelCode, _ = callBusinessAPI(handler, "POST", "/api/v1/me/store-orders/"+id+"/reverse", owner.AccessToken, map[string]string{"action": "cancel", "reason": "发货前取消"}, map[string]string{"Idempotency-Key": newPostID()})
		}()
		go func() {
			defer wg.Done()
			shipCode, _ = callBusinessAPI(handler, "POST", "/api/v1/admin/store/orders/"+id+"/ship", admin.AccessToken, map[string]string{"carrier": "物流", "tracking_no": "RACE123"}, nil)
		}()
		wg.Wait()
		if cancelCode == 200 && shipCode == 409 {
			assertRestored()
			return
		}
		if cancelCode != 409 || shipCode != 200 {
			t.Fatalf("取消/发货并发状态异常: %d/%d", cancelCode, shipCode)
		}
		b, r, f := snapshot()
		if b != 4940 || r != 0 || f != 1 {
			t.Fatalf("并发发货账实不符: %d/%d/%d", b, r, f)
		}
		reverse(id, "request_return", owner.AccessToken, false, newPostID(), 200)
		reverse(id, "approve_return", admin.AccessToken, true, newPostID(), 200)
		reverse(id, "refund", admin.AccessToken, true, newPostID(), 200)
		assertRestored()
	})
	t.Run("rollback_on_stock_mismatch", func(t *testing.T) {
		id := create()
		approve(id)
		if _, err := s.db.Exec(`UPDATE store_products SET stock_reserved = 0 WHERE id = $1`, productID); err != nil {
			t.Fatal(err)
		}
		reverse(id, "cancel", admin.AccessToken, true, newPostID(), 409)
		b, _, _ := snapshot()
		if b != 4940 {
			t.Fatalf("失败事务没有回滚退款: %d", b)
		}
		data := call("GET", "/api/v1/me/store-orders/"+id+"/aftercare", owner.AccessToken, nil, "", 200)
		if data["fulfillment_status"] != "awaiting_address" || data["refunded_points"] != float64(0) {
			t.Fatal(data)
		}
		if _, err := s.db.Exec(`UPDATE store_products SET stock_reserved = 1 WHERE id = $1`, productID); err != nil {
			t.Fatal(err)
		}
		reverse(id, "cancel", admin.AccessToken, true, newPostID(), 200)
		assertRestored()
	})
	t.Run("damaged_return_does_not_restock", func(t *testing.T) {
		id := create()
		approve(id)
		ship(id)
		reverse(id, "request_return", owner.AccessToken, false, newPostID(), 200)
		reverse(id, "approve_return", admin.AccessToken, true, newPostID(), 200)
		call("POST", "/api/v1/admin/store/orders/"+id+"/reverse", admin.AccessToken, map[string]any{"action": "refund", "reason": "商品破损，仅退款", "return_received": true, "restock": false}, newPostID(), 200)
		b, r, f := snapshot()
		if b != 5000 || r != 0 || f != 1 {
			t.Fatalf("损坏退货不应重新入库: %d/%d/%d", b, r, f)
		}
	})
}

func TestCommentNotificationsAgainstPostgres(t *testing.T) {
	s := feedIntegrationServer(t)
	t.Cleanup(func() { s.db.Close() })
	owner, commenter := aftercareSession(t, s, "author"), aftercareSession(t, s, "commenter")
	_, posts := insertFeedFixtures(t, s)
	var postID string
	for _, id := range posts {
		postID = id
		break
	}
	if _, err := s.db.Exec(`UPDATE posts SET author_id = $2 WHERE id = $1`, postID, owner.User.ID); err != nil {
		t.Fatal(err)
	}
	handler := NewHandler(s.db)
	comment := func(token, parent, key string, want int) string {
		t.Helper()
		code, body := callBusinessAPI(handler, http.MethodPost, "/api/v1/posts/"+postID+"/comments", token, map[string]string{"content": "通知链路测试", "parent_id": parent, "reply_to_user_id": owner.User.ID}, map[string]string{"Idempotency-Key": key})
		if code != want {
			t.Fatalf("comment status=%d body=%s", code, body)
		}
		var result struct {
			ID string `json:"id"`
		}
		json.Unmarshal(body, &result)
		return result.ID
	}
	key := newPostID()
	root := comment(commenter.AccessToken, "", key, 201)
	if got := comment(commenter.AccessToken, "", key, 200); got != root {
		t.Fatal("幂等重试生成了新评论")
	}
	comment(owner.AccessToken, "", newPostID(), 201)
	var count int
	var data []byte
	if err := s.db.QueryRow(`SELECT COUNT(*) FROM notifications WHERE target_id=$1 AND user_id=$2 AND type='comment.created'`, postID, owner.User.ID).Scan(&count); err != nil {
		t.Fatal(err)
	}
	if count != 1 {
		t.Fatalf("一级评论通知数=%d", count)
	}
	if err := s.db.QueryRow(`SELECT target_data FROM notifications WHERE target_id=$1 AND user_id=$2 AND type='comment.created'`, postID, owner.User.ID).Scan(&data); err != nil {
		t.Fatal(err)
	}
	var target map[string]string
	json.Unmarshal(data, &target)
	if target["comment_id"] != root {
		t.Fatal(target)
	}
	reply := comment(owner.AccessToken, root, newPostID(), 201)
	if err := s.db.QueryRow(`SELECT target_data FROM notifications WHERE target_id=$1 AND user_id=$2 AND type='reply'`, postID, commenter.User.ID).Scan(&data); err != nil {
		t.Fatal(err)
	}
	json.Unmarshal(data, &target)
	if target["comment_id"] != root || target["reply_id"] != reply {
		t.Fatal(target)
	}
}
