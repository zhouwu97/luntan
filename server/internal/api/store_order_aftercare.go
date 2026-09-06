package api

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/zhouwu97/luntan/server/internal/auth"
	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

type storeReverseInput struct {
	Action         string `json:"action"`
	Reason         string `json:"reason"`
	Carrier        string `json:"carrier"`
	TrackingNo     string `json:"tracking_no"`
	ReturnReceived bool   `json:"return_received"`
	Restock        bool   `json:"restock"`
}

func (s *Server) storeAftercareUser(w http.ResponseWriter, r *http.Request, admin bool) (auth.User, bool) {
	if admin {
		return s.requireStoreOrderFulfiller(w, r)
	}
	return s.requireRegisteredUser(w, r)
}

func (s *Server) getStoreOrderAftercare(w http.ResponseWriter, r *http.Request, orderID string, admin bool) {
	if !s.requireDatabase(w, r) {
		return
	}
	var user auth.User
	var ok bool
	if admin {
		user, ok = s.requireStoreOrderReviewer(w, r)
	} else {
		user, ok = s.requireRegisteredUser(w, r)
	}
	if !ok {
		return
	}
	var payload []byte
	err := s.db.QueryRowContext(r.Context(), `SELECT jsonb_build_object(
        'status', status, 'fulfillment_status', fulfillment_status,
        'reason', reverse_reason, 'return_instructions', return_instructions,
        'carrier', return_carrier, 'tracking_no', return_tracking_no, 'refunded_points', refunded_points)
        FROM store_orders WHERE id = $1 AND ($2 OR user_id = $3)`, orderID, admin, user.ID).Scan(&payload)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrStoreOrderNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, json.RawMessage(payload))
}

func (s *Server) reverseStoreOrder(w http.ResponseWriter, r *http.Request, orderID string, admin bool) {
	if !s.requireDatabase(w, r) {
		return
	}
	actor, ok := s.storeAftercareUser(w, r, admin)
	if !ok {
		return
	}
	fail := func(code, message string) {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusConflict, Code: code, Message: message})
	}
	var input storeReverseInput
	key := strings.TrimSpace(r.Header.Get("Idempotency-Key"))
	if err := decodeJSON(r, &input); err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: 400, Code: "INVALID_BODY", Message: "请求体格式错误"})
		return
	}
	input.Reason = strings.TrimSpace(input.Reason)
	input.Carrier = strings.TrimSpace(input.Carrier)
	input.TrackingNo = strings.TrimSpace(input.TrackingNo)
	if !validRuneLength(key, 1, 128) || !validRuneLength(input.Reason, 1, 1000) {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: 400, Code: "INVALID_REVERSE_REQUEST", Message: "请填写操作说明并提供有效幂等键"})
		return
	}
	switch input.Action {
	case "cancel", "request_return":
	case "return_shipping":
		if !validRuneLength(input.Carrier, 1, 40) || !validRuneLength(input.TrackingNo, 1, 80) {
			writeAuthError(w, r, ErrInvalidStoreShipping)
			return
		}
	case "approve_return", "reject_return", "refund":
		if !admin {
			writeAuthError(w, r, ErrPermissionDenied)
			return
		}
	default:
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: 400, Code: "INVALID_REVERSE_ACTION", Message: "售后操作无效"})
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	var owner string
	err = tx.QueryRowContext(r.Context(), `SELECT user_id FROM store_orders WHERE id = $1 AND ($2 OR user_id = $3)`, orderID, admin, actor.ID).Scan(&owner)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrStoreOrderNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	// 与审核统一采用用户、订单、商品的锁顺序；余额不修改主键，
	// 使用 NO KEY UPDATE，避免发货通知的用户外键检查与订单锁形成死锁。
	var balance int64
	if err = tx.QueryRowContext(r.Context(), `SELECT points_balance FROM users WHERE id = $1 FOR NO KEY UPDATE`, owner).Scan(&balance); err != nil {
		writeInternalError(w, r, err)
		return
	}
	var status, fulfillment, previous, productID, productName string
	var points int64
	err = tx.QueryRowContext(r.Context(), `SELECT o.status, o.fulfillment_status, o.reverse_previous_status, o.product_id, p.name, o.points
        FROM store_orders o JOIN store_products p ON p.id = o.product_id WHERE o.id = $1 FOR UPDATE OF o`, orderID).
		Scan(&status, &fulfillment, &previous, &productID, &productName, &points)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	request, _ := json.Marshal(input)
	var sameRequest bool
	err = tx.QueryRowContext(r.Context(), `SELECT request = $4::jsonb FROM store_order_reverse_requests
        WHERE order_id = $1 AND actor_id = $2 AND idempotency_key = $3`, orderID, actor.ID, key, string(request)).Scan(&sameRequest)
	if err == nil {
		if !sameRequest {
			fail("IDEMPOTENCY_CONFLICT", "同一幂等键不能用于不同操作")
			return
		}
		httpserver.WriteJSON(w, 200, map[string]any{"id": orderID, "status": status, "fulfillment_status": fulfillment})
		return
	}
	if !errors.Is(err, sql.ErrNoRows) {
		writeInternalError(w, r, err)
		return
	}
	nextStatus, nextFulfillment := status, fulfillment
	refund, release, restock := false, false, false
	switch input.Action {
	case "cancel":
		if status == "pending_review" && fulfillment == "none" {
			nextStatus, nextFulfillment = "cancelled", "cancelled"
		} else if status == "approved" && (fulfillment == "awaiting_address" || fulfillment == "ready_to_ship") {
			nextStatus, nextFulfillment, refund, release = "cancelled", "cancelled", true, true
		} else {
			fail("STORE_REVERSE_STATE", "当前订单不能取消，已发货订单请申请退货")
			return
		}
	case "request_return":
		if status != "approved" || (fulfillment != "shipped" && fulfillment != "completed") {
			fail("STORE_REVERSE_STATE", "当前订单不能申请退货")
			return
		}
		previous, nextFulfillment = fulfillment, "return_requested"
	case "approve_return", "reject_return":
		if status != "approved" || fulfillment != "return_requested" {
			fail("STORE_REVERSE_STATE", "订单没有待审核的退货申请")
			return
		}
		nextFulfillment = "refund_pending"
		if input.Action == "reject_return" {
			nextFulfillment = previous
		}
	case "return_shipping":
		if status != "approved" || fulfillment != "refund_pending" {
			fail("STORE_REVERSE_STATE", "请等待管理员同意退货后填写回寄物流")
			return
		}
	case "refund":
		if status != "approved" || fulfillment != "refund_pending" || !input.ReturnReceived {
			fail("STORE_REVERSE_STATE", "仅可在同意退货并确认收到退货后退款")
			return
		}
		nextFulfillment, refund, restock = "refunded", true, input.Restock
	}
	now := time.Now().UTC()
	if refund {
		// 只退实际扣款，不把退款当成赚取积分；不受每日奖励上限影响。
		var charged int64
		err = tx.QueryRowContext(r.Context(), `SELECT COALESCE(-SUM(delta), 0) FROM point_transactions
            WHERE user_id = $1 AND idempotency_key = $2 AND source = 'store'`, owner, "store:approve:"+orderID).Scan(&charged)
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
		if charged != points {
			fail("STORE_REFUND_LEDGER_MISMATCH", "订单扣款流水异常，请核实后再退款")
			return
		}
		balance += points
		if _, err = tx.ExecContext(r.Context(), `INSERT INTO point_transactions (id, user_id, source, delta, balance_after, reason, idempotency_key)
            VALUES ($1, $2, 'store_refund', $3, $4, $5, $6)`, newPostID(), owner, points, balance, productName+"："+input.Reason, "store:refund:"+orderID); err != nil {
			writeInternalError(w, r, err)
			return
		}
		if _, err = tx.ExecContext(r.Context(), `UPDATE users SET points_balance = $2, updated_at = $3 WHERE id = $1`, owner, balance, now); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	if release || restock {
		column := "stock_reserved"
		if restock {
			column = "stock_fulfilled"
		}
		result, stockErr := tx.ExecContext(r.Context(), `UPDATE store_products SET `+column+` = `+column+` - 1, updated_at = $2 WHERE id = $1 AND `+column+` > 0`, productID, now)
		if stockErr != nil {
			writeInternalError(w, r, stockErr)
			return
		}
		affected, _ := result.RowsAffected()
		if affected != 1 {
			fail("STORE_STOCK_MISMATCH", "库存记录异常，操作未生效")
			return
		}
	}
	if _, err = tx.ExecContext(r.Context(), `UPDATE store_orders SET status = $2, fulfillment_status = $3,
        reverse_previous_status = $4, reverse_reason = $5,
        return_instructions = CASE WHEN $6 = 'approve_return' THEN $5 WHEN $6 = 'request_return' THEN '' ELSE return_instructions END,
        return_carrier = CASE WHEN $6 = 'return_shipping' THEN $7 WHEN $6 = 'request_return' THEN '' ELSE return_carrier END,
        return_tracking_no = CASE WHEN $6 = 'return_shipping' THEN $8 WHEN $6 = 'request_return' THEN '' ELSE return_tracking_no END,
        refunded_points = CASE WHEN $9 THEN points ELSE refunded_points END, updated_at = $10 WHERE id = $1`,
		orderID, nextStatus, nextFulfillment, previous, input.Reason, input.Action, input.Carrier, input.TrackingNo, refund, now); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if _, err = tx.ExecContext(r.Context(), `INSERT INTO store_order_reverse_requests (order_id, actor_id, idempotency_key, request)
        VALUES ($1, $2, $3, $4::jsonb)`, orderID, actor.ID, key, string(request)); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err = appendAdminLogTx(r.Context(), tx, actor.ID, "store.order."+input.Action, "store_order", orderID, input.Reason,
		requestIDFromRequest(r), httpserver.ClientIP(r), map[string]any{"from_status": fulfillment, "to_status": nextFulfillment, "refund": refund, "restock": restock, "return_received": input.ReturnReceived, "user_id": owner}, now); err != nil {
		writeInternalError(w, r, err)
		return
	}
	// 用户主动操作也保留站内回执，actor 留空以区别他人互动并避免自通知过滤。
	notificationActor := actor.ID
	if owner == actor.ID {
		notificationActor = ""
	}
	if err = enqueueNotificationWithDataTx(tx, owner, notificationActor, "store.order."+input.Action, "store_order", orderID,
		map[string]any{"title": "兑换订单售后更新", "message": fmt.Sprintf("「%s」%s，详情请查看订单。", productName, storeAftercareLabel(nextFulfillment)), "order_id": orderID, "fulfillment_status": nextFulfillment}, now); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err = tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, 200, map[string]any{"id": orderID, "status": nextStatus, "fulfillment_status": nextFulfillment, "balance": balance})
}

func storeAftercareLabel(status string) string {
	switch status {
	case "cancelled":
		return "已取消，已扣积分原路返还"
	case "return_requested":
		return "已申请退货，等待审核"
	case "refund_pending":
		return "已同意退货，确认收到退货后返还积分"
	case "refunded":
		return "已退款，积分已返还"
	default:
		return "退货申请未通过"
	}
}
