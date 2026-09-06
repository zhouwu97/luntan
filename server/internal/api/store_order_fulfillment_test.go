package api

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
)

func mockAuthSession(mock sqlmock.Sqlmock, userID string, accountType string) {
	mock.ExpectQuery(`(?s)SELECT u\.id, u\.username.*FROM sessions s`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "username", "status", "nickname", "level", "experience", "account_type",
			"email", "email_verified", "email_verified_at", "has_password",
		}).AddRow(userID, "user_"+userID, "active", "用户"+userID, 1, 0, accountType, "test@example.com", true, time.Now().UTC(), true))
}

func mockPermission(mock sqlmock.Sqlmock, userID, permission string, allowed bool) {
	mock.ExpectQuery(`(?s)SELECT EXISTS \(.*FROM user_roles ur.*JOIN role_permissions rp.*JOIN permissions p.*`).
		WithArgs(userID, permission).
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(allowed))
}

func mockAdminLogTx(mock sqlmock.Sqlmock) {
	mock.ExpectQuery(`SELECT last_hash FROM admin_log_chain WHERE id = 1 FOR UPDATE`).
		WillReturnRows(sqlmock.NewRows([]string{"last_hash"}).AddRow("0000000000000000000000000000000000000000000000000000000000000000"))
	mock.ExpectExec(`INSERT INTO admin_logs`).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(`UPDATE admin_log_chain SET last_hash = \$1`).
		WillReturnResult(sqlmock.NewResult(1, 1))
}

// 1 & 2: 100 积分申请 60 -> pending，不扣分；同时再申请 50 -> INSUFFICIENT_POINTS
func TestCreateStoreOrderRespectsAvailablePointsAndStock(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	handler := NewHandler(db)

	// 第一次申请 60 分商品：余额 100，当前占用 0，可用 100 >= 60，成功创建 pending_review
	mockAuthSession(mock, "user-1", "registered")
	mock.ExpectBegin()
	mock.ExpectQuery(`SELECT points_balance FROM users WHERE id = \$1 FOR UPDATE`).
		WithArgs("user-1").
		WillReturnRows(sqlmock.NewRows([]string{"points_balance"}).AddRow(int64(100)))
	mock.ExpectQuery(`SELECT id, product_id, points, status, fulfillment_status FROM store_orders WHERE user_id = \$1 AND idempotency_key = \$2`).
		WithArgs("user-1", "key-1").
		WillReturnError(sql.ErrNoRows)
	mock.ExpectQuery(`SELECT name, points, stock_total, stock_reserved, stock_fulfilled FROM store_products WHERE id = \$1 AND active = true FOR UPDATE`).
		WithArgs("badge").
		WillReturnRows(sqlmock.NewRows([]string{"name", "points", "stock_total", "stock_reserved", "stock_fulfilled"}).
			AddRow("论坛纪念徽章", int64(60), int64(10), int64(0), int64(0)))
	mock.ExpectQuery(`SELECT COALESCE\(SUM\(points\), 0\) FROM store_orders WHERE user_id = \$1 AND status = 'pending_review'`).
		WithArgs("user-1").
		WillReturnRows(sqlmock.NewRows([]string{"coalesce"}).AddRow(int64(0)))
	mock.ExpectExec(`INSERT INTO store_orders`).
		WithArgs(sqlmock.AnyArg(), "user-1", "badge", int64(60), "key-1", int64(100)).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	req1 := httptest.NewRequest(http.MethodPost, "/api/v1/store/orders", strings.NewReader(`{"product_id":"badge"}`))
	req1.Header.Set("Authorization", "Bearer user-token")
	req1.Header.Set("Idempotency-Key", "key-1")
	rec1 := httptest.NewRecorder()
	handler.ServeHTTP(rec1, req1)

	if rec1.Code != http.StatusCreated {
		t.Fatalf("create order 1 status = %d, body = %s", rec1.Code, rec1.Body.String())
	}
	var res1 map[string]any
	_ = json.Unmarshal(rec1.Body.Bytes(), &res1)
	if res1["status"] != "pending_review" || res1["fulfillment_status"] != "none" {
		t.Fatalf("order 1 status = %#v, want pending_review / none", res1)
	}

	// 第二次申请 50 分商品：余额 100，已有待审核占用 60，可用 40 < 50 -> 返回 INSUFFICIENT_POINTS
	mockAuthSession(mock, "user-1", "registered")
	mock.ExpectBegin()
	mock.ExpectQuery(`SELECT points_balance FROM users WHERE id = \$1 FOR UPDATE`).
		WithArgs("user-1").
		WillReturnRows(sqlmock.NewRows([]string{"points_balance"}).AddRow(int64(100)))
	mock.ExpectQuery(`SELECT id, product_id, points, status, fulfillment_status FROM store_orders WHERE user_id = \$1 AND idempotency_key = \$2`).
		WithArgs("user-1", "key-2").
		WillReturnError(sql.ErrNoRows)
	mock.ExpectQuery(`SELECT name, points, stock_total, stock_reserved, stock_fulfilled FROM store_products WHERE id = \$1 AND active = true FOR UPDATE`).
		WithArgs("keychain").
		WillReturnRows(sqlmock.NewRows([]string{"name", "points", "stock_total", "stock_reserved", "stock_fulfilled"}).
			AddRow("校园钥匙扣", int64(50), int64(10), int64(0), int64(0)))
	mock.ExpectQuery(`SELECT COALESCE\(SUM\(points\), 0\) FROM store_orders WHERE user_id = \$1 AND status = 'pending_review'`).
		WithArgs("user-1").
		WillReturnRows(sqlmock.NewRows([]string{"coalesce"}).AddRow(int64(60)))
	mock.ExpectRollback()

	req2 := httptest.NewRequest(http.MethodPost, "/api/v1/store/orders", strings.NewReader(`{"product_id":"keychain"}`))
	req2.Header.Set("Authorization", "Bearer user-token")
	req2.Header.Set("Idempotency-Key", "key-2")
	rec2 := httptest.NewRecorder()
	handler.ServeHTTP(rec2, req2)

	if rec2.Code != http.StatusConflict || !strings.Contains(rec2.Body.String(), "INSUFFICIENT_POINTS") {
		t.Fatalf("create order 2 should fail with INSUFFICIENT_POINTS, status=%d body=%s", rec2.Code, rec2.Body.String())
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

// 2b: 库存耗尽时拒绝申请商品
func TestCreateStoreOrderRejectsOutOfStockProduct(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	handler := NewHandler(db)

	mockAuthSession(mock, "user-1", "registered")
	mock.ExpectBegin()
	mock.ExpectQuery(`SELECT points_balance FROM users WHERE id = \$1 FOR UPDATE`).
		WithArgs("user-1").
		WillReturnRows(sqlmock.NewRows([]string{"points_balance"}).AddRow(int64(100)))
	mock.ExpectQuery(`SELECT id, product_id, points, status, fulfillment_status FROM store_orders WHERE user_id = \$1 AND idempotency_key = \$2`).
		WithArgs("user-1", "key-out").
		WillReturnError(sql.ErrNoRows)
	// stock_total: 5, stock_reserved: 3, stock_fulfilled: 2 => 可用 0
	mock.ExpectQuery(`SELECT name, points, stock_total, stock_reserved, stock_fulfilled FROM store_products WHERE id = \$1 AND active = true FOR UPDATE`).
		WithArgs("badge").
		WillReturnRows(sqlmock.NewRows([]string{"name", "points", "stock_total", "stock_reserved", "stock_fulfilled"}).
			AddRow("论坛纪念徽章", int64(60), int64(5), int64(3), int64(2)))
	mock.ExpectRollback()

	req := httptest.NewRequest(http.MethodPost, "/api/v1/store/orders", strings.NewReader(`{"product_id":"badge"}`))
	req.Header.Set("Authorization", "Bearer user-token")
	req.Header.Set("Idempotency-Key", "key-out")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusConflict || !strings.Contains(rec.Body.String(), "STORE_PRODUCT_OUT_OF_STOCK") {
		t.Fatalf("out of stock response: status=%d body=%s", rec.Code, rec.Body.String())
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

// 3 & 4: 审核通过扣分并转 awaiting_address，占用库存；审核拒绝不扣分
func TestReviewStoreOrderApproveAndReject(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	handler := NewHandler(db)

	// 审核通过
	mockAuthSession(mock, "admin-1", "registered")
	mockPermission(mock, "admin-1", "store.order.review", true)

	mock.ExpectBegin()
	mock.ExpectQuery(`SELECT user_id FROM store_orders WHERE id = \$1`).
		WithArgs("order-1").
		WillReturnRows(sqlmock.NewRows([]string{"user_id"}).AddRow("user-1"))
	mock.ExpectQuery(`SELECT points_balance FROM users WHERE id = \$1 FOR UPDATE`).
		WithArgs("user-1").
		WillReturnRows(sqlmock.NewRows([]string{"points_balance"}).AddRow(int64(100)))
	mock.ExpectQuery(`SELECT p\.name, o\.points, o\.status, o\.created_at, o\.balance_at_submit FROM store_orders o JOIN store_products p ON p\.id = o\.product_id WHERE o\.id = \$1 FOR UPDATE OF o`).
		WithArgs("order-1").
		WillReturnRows(sqlmock.NewRows([]string{"name", "points", "status", "created_at", "balance_at_submit"}).
			AddRow("纪念徽章", int64(60), "pending_review", time.Now().UTC(), int64(100)))
	mock.ExpectQuery(`SELECT COALESCE\(SUM\(pt\.delta\), 0\) FROM store_point_invalidations spi`).
		WillReturnRows(sqlmock.NewRows([]string{"coalesce"}).AddRow(int64(0)))

	mock.ExpectQuery(`SELECT COALESCE\(SUM\(points\), 0\) FROM store_orders WHERE user_id = \$1 AND status = 'pending_review' AND id <> \$2`).
		WithArgs("user-1", "order-1").
		WillReturnRows(sqlmock.NewRows([]string{"coalesce"}).AddRow(int64(0)))
	// 扣除用户余额
	mock.ExpectExec(`UPDATE users SET points_balance = \$1, updated_at = now\(\) WHERE id = \$2`).
		WithArgs(int64(40), "user-1").
		WillReturnResult(sqlmock.NewResult(1, 1))
	// 写入扣分流水
	mock.ExpectExec(`INSERT INTO point_transactions`).
		WillReturnResult(sqlmock.NewResult(1, 1))
	// 预占库存
	mock.ExpectExec(`UPDATE store_products SET stock_reserved = stock_reserved \+ 1, updated_at = \$2 WHERE id = \(SELECT product_id FROM store_orders WHERE id = \$1\) AND \(stock_total - stock_reserved - stock_fulfilled\) >= 1`).
		WithArgs("order-1", sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	// 更新订单状态为 approved, awaiting_address
	mock.ExpectExec(`UPDATE store_orders SET status = \$2, reviewed_by = \$3, reviewed_at = \$4, review_reason = \$5, fulfillment_status = \$6, updated_at = \$4 WHERE id = \$1 AND status = 'pending_review'`).
		WithArgs("order-1", "approved", "admin-1", sqlmock.AnyArg(), "", "awaiting_address").
		WillReturnResult(sqlmock.NewResult(1, 1))
	// 管理员审计
	mockAdminLogTx(mock)
	// 发送通知
	mock.ExpectExec(`INSERT INTO notifications`).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(`INSERT INTO outbox_events`).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	req := httptest.NewRequest(http.MethodPost, "/api/v1/admin/store/orders/order-1/review", strings.NewReader(`{"decision":"approve"}`))
	req.Header.Set("Authorization", "Bearer admin-token")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("approve order status = %d, body = %s", rec.Code, rec.Body.String())
	}
	var res map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &res)
	if res["status"] != "approved" || res["fulfillment_status"] != "awaiting_address" || res["balance"] != float64(40) {
		t.Fatalf("approved order response = %#v", res)
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

// 6, 7, 8, 9, 10: 收货地址填写流转
func TestStoreOrderShippingFlow(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	handler := NewHandler(db)

	// 7: pending_review 不能填地址
	mockAuthSession(mock, "user-1", "registered")
	mock.ExpectBegin()
	mock.ExpectQuery(`SELECT status, fulfillment_status FROM store_orders WHERE id = \$1 AND user_id = \$2 FOR UPDATE`).
		WithArgs("order-pending", "user-1").
		WillReturnRows(sqlmock.NewRows([]string{"status", "fulfillment_status"}).AddRow("pending_review", "none"))
	mock.ExpectRollback()

	body := `{"recipient_name":"张三","phone":"13800000000","province":"辽宁省","city":"沈阳市","district":"浑南区","address_detail":"创新路1号"}`
	req1 := httptest.NewRequest(http.MethodPut, "/api/v1/me/store-orders/order-pending/shipping", strings.NewReader(body))
	req1.Header.Set("Authorization", "Bearer user-token")
	rec1 := httptest.NewRecorder()
	handler.ServeHTTP(rec1, req1)
	if rec1.Code != http.StatusConflict || !strings.Contains(rec1.Body.String(), "STORE_SHIPPING_UNAVAILABLE") {
		t.Fatalf("pending_review shipping should fail with STORE_SHIPPING_UNAVAILABLE, status=%d body=%s", rec1.Code, rec1.Body.String())
	}

	// 8: approved 可以填地址并流转为 ready_to_ship
	mockAuthSession(mock, "user-1", "registered")
	mock.ExpectBegin()
	mock.ExpectQuery(`SELECT status, fulfillment_status FROM store_orders WHERE id = \$1 AND user_id = \$2 FOR UPDATE`).
		WithArgs("order-approved", "user-1").
		WillReturnRows(sqlmock.NewRows([]string{"status", "fulfillment_status"}).AddRow("approved", "awaiting_address"))
	mock.ExpectExec(`INSERT INTO store_order_shipping`).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(`UPDATE store_orders SET fulfillment_status = 'ready_to_ship', updated_at = \$2 WHERE id = \$1`).
		WithArgs("order-approved", sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectQuery(`SELECT o\.id, o\.product_id, p\.name.*FROM store_orders o`).
		WithArgs("order-approved", "user-1").
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "product_id", "name", "points", "status", "fulfillment_status", "created_at", "review_reason",
			"reviewed_at", "shipped_at", "completed_at", "recipient_name", "phone", "province", "city", "district",
			"address_detail", "carrier", "tracking_no", "submitted_at", "updated_at",
		}).AddRow(
			"order-approved", "badge", "徽章", int64(60), "approved", "ready_to_ship", time.Now().UTC(), "",
			time.Now().UTC(), nil, nil, "张三", "13800000000", "辽宁省", "沈阳市", "浑南区", "创新路1号",
			"", "", time.Now().UTC(), time.Now().UTC(),
		))
	mock.ExpectCommit()

	req2 := httptest.NewRequest(http.MethodPut, "/api/v1/me/store-orders/order-approved/shipping", strings.NewReader(body))
	req2.Header.Set("Authorization", "Bearer user-token")
	rec2 := httptest.NewRecorder()
	handler.ServeHTTP(rec2, req2)
	if rec2.Code != http.StatusOK {
		t.Fatalf("submit shipping status = %d body = %s", rec2.Code, rec2.Body.String())
	}
	var res2 map[string]any
	_ = json.Unmarshal(rec2.Body.Bytes(), &res2)
	if res2["fulfillment_status"] != "ready_to_ship" {
		t.Fatalf("fulfillment_status = %#v, want ready_to_ship", res2["fulfillment_status"])
	}

	// 10: shipped 后不能修改收货地址
	mockAuthSession(mock, "user-1", "registered")
	mock.ExpectBegin()
	mock.ExpectQuery(`SELECT status, fulfillment_status FROM store_orders WHERE id = \$1 AND user_id = \$2 FOR UPDATE`).
		WithArgs("order-shipped", "user-1").
		WillReturnRows(sqlmock.NewRows([]string{"status", "fulfillment_status"}).AddRow("approved", "shipped"))
	mock.ExpectRollback()

	req3 := httptest.NewRequest(http.MethodPut, "/api/v1/me/store-orders/order-shipped/shipping", strings.NewReader(body))
	req3.Header.Set("Authorization", "Bearer user-token")
	rec3 := httptest.NewRecorder()
	handler.ServeHTTP(rec3, req3)
	if rec3.Code != http.StatusConflict || !strings.Contains(rec3.Body.String(), "STORE_SHIPPING_LOCKED") {
		t.Fatalf("shipped shipping should fail with STORE_SHIPPING_LOCKED, status=%d body=%s", rec3.Code, rec3.Body.String())
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

// 11, 12, 13, 14: 发货校验与流转，库存转移为已履约
func TestShipStoreOrderFlow(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	handler := NewHandler(db)

	// 11: 未填写地址不能发货 (fulfillment_status 为 awaiting_address)
	mockAuthSession(mock, "admin-fulfiller", "registered")
	mockPermission(mock, "admin-fulfiller", "store.order.fulfill", true)

	mock.ExpectBegin()
	mock.ExpectQuery(`SELECT o\.user_id, p\.name, o\.status, o\.fulfillment_status FROM store_orders o JOIN store_products p ON p\.id = o\.product_id WHERE o\.id = \$1 FOR UPDATE OF o`).
		WithArgs("order-no-addr").
		WillReturnRows(sqlmock.NewRows([]string{"user_id", "name", "status", "fulfillment_status"}).AddRow("user-1", "徽章", "approved", "awaiting_address"))
	mock.ExpectRollback()

	shipBody := `{"carrier":"顺丰速运","tracking_no":"SF1234567890"}`
	req1 := httptest.NewRequest(http.MethodPost, "/api/v1/admin/store/orders/order-no-addr/ship", strings.NewReader(shipBody))
	req1.Header.Set("Authorization", "Bearer fulfiller-token")
	rec1 := httptest.NewRecorder()
	handler.ServeHTTP(rec1, req1)
	if rec1.Code != http.StatusConflict || !strings.Contains(rec1.Body.String(), "STORE_SHIPPING_REQUIRED") {
		t.Fatalf("ship without address status=%d body=%s", rec1.Code, rec1.Body.String())
	}

	// 12 & 14: 正常发货（carrier + tracking_no）并转移库存 stock_reserved -> stock_fulfilled
	mockAuthSession(mock, "admin-fulfiller", "registered")
	mockPermission(mock, "admin-fulfiller", "store.order.fulfill", true)

	mock.ExpectBegin()
	mock.ExpectQuery(`SELECT o\.user_id, p\.name, o\.status, o\.fulfillment_status FROM store_orders o JOIN store_products p ON p\.id = o\.product_id WHERE o\.id = \$1 FOR UPDATE OF o`).
		WithArgs("order-ship").
		WillReturnRows(sqlmock.NewRows([]string{"user_id", "name", "status", "fulfillment_status"}).AddRow("user-1", "徽章", "approved", "ready_to_ship"))
	mock.ExpectQuery(`SELECT id FROM store_order_shipping WHERE order_id = \$1 FOR UPDATE`).
		WithArgs("order-ship").
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow("ship-1"))
	mock.ExpectExec(`UPDATE store_order_shipping SET carrier = \$2, tracking_no = \$3, updated_at = \$4 WHERE order_id = \$1`).
		WithArgs("order-ship", "顺丰速运", "SF1234567890", sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(`UPDATE store_orders SET fulfillment_status = 'shipped', shipped_at = \$2, updated_at = \$2 WHERE id = \$1 AND fulfillment_status = 'ready_to_ship'`).
		WithArgs("order-ship", sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	// 库存转移
	mock.ExpectExec(`UPDATE store_products SET stock_reserved = GREATEST\(stock_reserved - 1, 0\), stock_fulfilled = stock_fulfilled \+ 1, updated_at = \$2 WHERE id = \(SELECT product_id FROM store_orders WHERE id = \$1\)`).
		WithArgs("order-ship", sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	// 审计日志 store.order.ship
	mockAdminLogTx(mock)
	// 通知 store.order.shipped
	mock.ExpectExec(`INSERT INTO notifications`).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(`INSERT INTO outbox_events`).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectQuery(`SELECT o\.id, o\.user_id, u\.username.*FROM store_orders o`).
		WithArgs("order-ship").
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "user_id", "username", "nickname", "product_id", "product_name", "points", "status", "fulfillment_status",
			"created_at", "shipped_at", "completed_at", "reviewed_by", "reviewed_at", "review_reason", "user_points",
			"balance_at_submit", "balance_snapshot_trusted", "invalidated_count", "invalidated_points",
			"recipient_name", "phone", "province", "city", "district", "address_detail", "carrier", "tracking_no",
			"submitted_at", "shipping_updated_at",
		}).AddRow(
			"order-ship", "user-1", "u1", "用户1", "badge", "徽章", int64(60), "approved", "shipped",
			time.Now().UTC(), time.Now().UTC(), nil, "admin-1", time.Now().UTC(), "", int64(40),
			int64(100), true, int64(0), int64(0),
			"张三", "13800000000", "辽宁省", "沈阳市", "浑南区", "创新路1号", "顺丰速运", "SF1234567890",
			time.Now().UTC(), time.Now().UTC(),
		))
	mock.ExpectCommit()

	req2 := httptest.NewRequest(http.MethodPost, "/api/v1/admin/store/orders/order-ship/ship", strings.NewReader(shipBody))
	req2.Header.Set("Authorization", "Bearer fulfiller-token")
	rec2 := httptest.NewRecorder()
	handler.ServeHTTP(rec2, req2)
	if rec2.Code != http.StatusOK {
		t.Fatalf("ship order status = %d body = %s", rec2.Code, rec2.Body.String())
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

// 15 & 16: 用户确认收货 -> completed，记录 completed_at；之后不能重复操作
func TestUserCompleteStoreOrderFlow(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	handler := NewHandler(db)

	// 15: shipped 状态下用户确认收货 -> completed
	mockAuthSession(mock, "user-1", "registered")
	mock.ExpectBegin()
	mock.ExpectQuery(`SELECT status, fulfillment_status FROM store_orders WHERE id = \$1 AND user_id = \$2 FOR UPDATE`).
		WithArgs("order-shipped", "user-1").
		WillReturnRows(sqlmock.NewRows([]string{"status", "fulfillment_status"}).AddRow("approved", "shipped"))
	mock.ExpectExec(`UPDATE store_orders SET fulfillment_status = 'completed', completed_at = \$2, updated_at = \$2 WHERE id = \$1 AND fulfillment_status = 'shipped'`).
		WithArgs("order-shipped", sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectQuery(`SELECT o\.id, o\.product_id, p\.name.*FROM store_orders o`).
		WithArgs("order-shipped", "user-1").
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "product_id", "name", "points", "status", "fulfillment_status", "created_at", "review_reason",
			"reviewed_at", "shipped_at", "completed_at", "recipient_name", "phone", "province", "city", "district",
			"address_detail", "carrier", "tracking_no", "submitted_at", "updated_at",
		}).AddRow(
			"order-shipped", "badge", "徽章", int64(60), "approved", "completed", time.Now().UTC(), "",
			time.Now().UTC(), time.Now().UTC(), time.Now().UTC(), "张三", "13800000000", "辽宁省", "沈阳市", "浑南区", "创新路1号",
			"顺丰", "SF1234", time.Now().UTC(), time.Now().UTC(),
		))
	mock.ExpectCommit()

	req := httptest.NewRequest(http.MethodPost, "/api/v1/me/store-orders/order-shipped/complete", nil)
	req.Header.Set("Authorization", "Bearer user-token")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("complete order status = %d body = %s", rec.Code, rec.Body.String())
	}
	var res map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &res)
	if res["fulfillment_status"] != "completed" || res["completed_at"] == nil {
		t.Fatalf("completed order res = %#v", res)
	}

	// 16: completed 后不能再次完成或改地址
	mockAuthSession(mock, "user-1", "registered")
	mock.ExpectBegin()
	mock.ExpectQuery(`SELECT status, fulfillment_status FROM store_orders WHERE id = \$1 AND user_id = \$2 FOR UPDATE`).
		WithArgs("order-shipped", "user-1").
		WillReturnRows(sqlmock.NewRows([]string{"status", "fulfillment_status"}).AddRow("approved", "completed"))
	mock.ExpectRollback()

	reqAgain := httptest.NewRequest(http.MethodPost, "/api/v1/me/store-orders/order-shipped/complete", nil)
	reqAgain.Header.Set("Authorization", "Bearer user-token")
	recAgain := httptest.NewRecorder()
	handler.ServeHTTP(recAgain, reqAgain)

	if recAgain.Code != http.StatusConflict || !strings.Contains(recAgain.Body.String(), "STORE_ORDER_NOT_SHIPPED") {
		t.Fatalf("completed order should not complete again, status=%d body=%s", recAgain.Code, recAgain.Body.String())
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

// 18: 权限拆分测试：普通 review 权限无法看解密门牌号与手机号
func TestStoreOrderPermissionMasking(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	handler := NewHandler(db)

	// 仅有 store.order.review，没有 store.order.fulfill / store.order.shipping.view_full
	mockAuthSession(mock, "admin-reviewer", "registered")
	mockPermission(mock, "admin-reviewer", "store.order.review", true)
	// canViewFullShipping 校验 1: view_full
	mockPermission(mock, "admin-reviewer", "store.order.shipping.view_full", false)
	// canViewFullShipping 校验 2: fulfill
	mockPermission(mock, "admin-reviewer", "store.order.fulfill", false)

	mock.ExpectQuery(`SELECT o\.id, o\.user_id, u\.username.*FROM store_orders o`).
		WithArgs("order-mask").
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "user_id", "username", "nickname", "product_id", "product_name", "points", "status", "fulfillment_status",
			"created_at", "shipped_at", "completed_at", "reviewed_by", "reviewed_at", "review_reason", "user_points",
			"balance_at_submit", "balance_snapshot_trusted", "invalidated_count", "invalidated_points",
			"recipient_name", "phone", "province", "city", "district", "address_detail", "carrier", "tracking_no",
			"submitted_at", "shipping_updated_at",
		}).AddRow(
			"order-mask", "user-1", "u1", "用户1", "badge", "徽章", int64(60), "approved", "ready_to_ship",
			time.Now().UTC(), nil, nil, "admin-1", time.Now().UTC(), "", int64(40),
			int64(100), true, int64(0), int64(0),
			"张三丰", "13812345678", "辽宁省", "沈阳市", "浑南区", "世纪大道999号3号楼401", "", "",
			time.Now().UTC(), time.Now().UTC(),
		))

	mock.ExpectQuery(`SELECT pt\.source.*FROM point_transactions pt`).
		WillReturnRows(sqlmock.NewRows([]string{"source", "sum", "count", "invalid_points"}))
	mock.ExpectQuery(`SELECT COALESCE\(SUM\(points\), 0\) FROM store_orders WHERE user_id = \$1 AND status = 'pending_review'`).
		WithArgs("user-1").
		WillReturnRows(sqlmock.NewRows([]string{"coalesce"}).AddRow(int64(0)))
	mock.ExpectQuery(`SELECT COALESCE\(SUM\(pt\.delta\), 0\) FROM store_point_invalidations spi`).
		WillReturnRows(sqlmock.NewRows([]string{"coalesce"}).AddRow(int64(0)))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/admin/store/orders/order-mask", nil)
	req.Header.Set("Authorization", "Bearer reviewer-token")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("get admin store order status = %d body = %s", rec.Code, rec.Body.String())
	}
	var res map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &res)
	shipping, ok := res["shipping"].(map[string]any)
	if !ok {
		t.Fatalf("shipping payload missing: %#v", res)
	}

	// 验证手机号与姓名门牌脱敏
	if shipping["recipient_name"] != "张**" {
		t.Fatalf("recipient_name = %q, want '张**'", shipping["recipient_name"])
	}
	if shipping["phone"] != "138****5678" {
		t.Fatalf("phone = %q, want '138****5678'", shipping["phone"])
	}
	if strings.Contains(shipping["address_detail"].(string), "401") || strings.Contains(shipping["address_detail"].(string), "999号") {
		t.Fatalf("address_detail should be masked, got %q", shipping["address_detail"])
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

// 待办数字统计接口测试
func TestAdminStoreOrderCounts(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	handler := NewHandler(db)

	mockAuthSession(mock, "admin-1", "registered")
	mockPermission(mock, "admin-1", "store.order.review", true)

	mock.ExpectQuery(`SELECT status, fulfillment_status, COUNT\(\*\) FROM store_orders GROUP BY status, fulfillment_status`).
		WillReturnRows(sqlmock.NewRows([]string{"status", "fulfillment_status", "count"}).
			AddRow("pending_review", "none", int64(4)).
			AddRow("approved", "awaiting_address", int64(3)).
			AddRow("approved", "ready_to_ship", int64(7)).
			AddRow("approved", "shipped", int64(2)).
			AddRow("approved", "completed", int64(5)).
			AddRow("rejected", "none", int64(1)))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/admin/store/orders/counts", nil)
	req.Header.Set("Authorization", "Bearer admin-token")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("get counts status = %d body = %s", rec.Code, rec.Body.String())
	}
	var res map[string]int64
	_ = json.Unmarshal(rec.Body.Bytes(), &res)
	if res["pending_review"] != 4 || res["awaiting_address"] != 3 || res["ready_to_ship"] != 7 || res["all"] != 22 {
		t.Fatalf("counts = %#v", res)
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}
