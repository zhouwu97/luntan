package api

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/zhouwu97/luntan/server/internal/auth"
	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

var (
	ErrInvalidStoreOrderReview = errors.New("invalid store order review")
	ErrStoreOrderNotFound      = errors.New("store order not found")
	ErrStoreOrderAlreadyReview = errors.New("store order already reviewed")
)

func (s *Server) requireStoreOrderReviewer(w http.ResponseWriter, r *http.Request) (auth.User, bool) {
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return auth.User{}, false
	}
	if !s.hasGlobalPermission(r, user.ID, "store.order.review") {
		writeAuthError(w, r, ErrPermissionDenied)
		return auth.User{}, false
	}
	return user, true
}

func validStoreOrderStatus(status string) bool {
	switch status {
	case "pending_review", "approved", "rejected", "pending", "claimed", "completed", "cancelled":
		return true
	default:
		return false
	}
}

func (s *Server) listAdminStoreOrders(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	if _, ok := s.requireStoreOrderReviewer(w, r); !ok {
		return
	}
	status := strings.TrimSpace(r.URL.Query().Get("status"))
	if status == "" {
		status = "pending_review"
	}
	if !validStoreOrderStatus(status) {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_STATUS", Message: "兑换订单状态无效"})
		return
	}
	limit, err := parseLimit(r.URL.Query().Get("limit"))
	if err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_LIMIT", Message: "limit 必须是 1 到 50 之间的整数"})
		return
	}
	rows, err := s.db.QueryContext(r.Context(), `
		SELECT o.id, o.user_id, u.username, COALESCE(up.nickname, u.username),
		       p.id, p.name, o.points, o.status, o.created_at,
		       COALESCE(o.reviewed_by, ''), o.reviewed_at, o.review_reason,
		       u.points_balance
		FROM store_orders o
		JOIN users u ON u.id = o.user_id
		LEFT JOIN user_profiles up ON up.user_id = u.id
		JOIN store_products p ON p.id = o.product_id
		WHERE o.status = $1
		ORDER BY o.created_at DESC, o.id DESC
		LIMIT $2`, status, limit)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()
	items := make([]map[string]any, 0, limit)
	for rows.Next() {
		item, err := scanAdminStoreOrder(rows)
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items})
}

type storeOrderRowScanner interface {
	Scan(dest ...any) error
}

func scanAdminStoreOrder(scanner storeOrderRowScanner) (map[string]any, error) {
	var id, userID, username, nickname, productID, productName, status, reviewedBy, reviewReason string
	var points, userPoints int64
	var createdAt time.Time
	var reviewedAt sql.NullTime
	if err := scanner.Scan(&id, &userID, &username, &nickname, &productID, &productName, &points, &status, &createdAt, &reviewedBy, &reviewedAt, &reviewReason, &userPoints); err != nil {
		return nil, err
	}
	item := map[string]any{
		"id": id, "user_id": userID, "username": username, "nickname": nickname,
		"product_id": productID, "product_name": productName, "points": points,
		"status": status, "created_at": createdAt, "reviewed_by": reviewedBy,
		"review_reason": reviewReason, "user_points": userPoints,
	}
	if reviewedAt.Valid {
		item["reviewed_at"] = reviewedAt.Time
	}
	return item, nil
}

func (s *Server) getAdminStoreOrder(w http.ResponseWriter, r *http.Request, orderID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	if _, ok := s.requireStoreOrderReviewer(w, r); !ok {
		return
	}
	order, err := s.loadAdminStoreOrder(r.Context(), s.db, orderID)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrStoreOrderNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	var sourceRows *sql.Rows
	sourceRows, err = s.db.QueryContext(r.Context(), `
		SELECT source, COALESCE(SUM(delta), 0), COUNT(*)
		FROM point_transactions
		WHERE user_id = $1 AND delta > 0
		GROUP BY source
		ORDER BY SUM(delta) DESC, source ASC`, order["user_id"])
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer sourceRows.Close()
	sources := make([]map[string]any, 0)
	for sourceRows.Next() {
		var source string
		var points, count int64
		if err := sourceRows.Scan(&source, &points, &count); err != nil {
			writeInternalError(w, r, err)
			return
		}
		sources = append(sources, map[string]any{"source": source, "points": points, "count": count})
	}
	if err := sourceRows.Err(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	var reserved int64
	if err := s.db.QueryRowContext(r.Context(), `SELECT COALESCE(SUM(points), 0) FROM store_orders WHERE user_id = $1 AND status = 'pending_review'`, order["user_id"]).Scan(&reserved); err != nil {
		writeInternalError(w, r, err)
		return
	}
	order["reserved_points"] = reserved
	order["available_points"] = order["user_points"].(int64) - reserved
	order["point_sources"] = sources
	httpserver.WriteJSON(w, http.StatusOK, order)
}

func (s *Server) loadAdminStoreOrder(ctx context.Context, queryer interface {
	QueryRowContext(context.Context, string, ...any) *sql.Row
}, orderID string) (map[string]any, error) {
	// 该辅助函数只用于复用列表字段；context 类型由调用方保证为 request.Context。
	row := queryer.QueryRowContext(ctx, `
		SELECT o.id, o.user_id, u.username, COALESCE(up.nickname, u.username),
		       p.id, p.name, o.points, o.status, o.created_at,
		       COALESCE(o.reviewed_by, ''), o.reviewed_at, o.review_reason,
		       u.points_balance
		FROM store_orders o
		JOIN users u ON u.id = o.user_id
		LEFT JOIN user_profiles up ON up.user_id = u.id
		JOIN store_products p ON p.id = o.product_id
		WHERE o.id = $1`, orderID)
	return scanAdminStoreOrder(row)
}

func (s *Server) reviewAdminStoreOrder(w http.ResponseWriter, r *http.Request, orderID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	operator, ok := s.requireStoreOrderReviewer(w, r)
	if !ok {
		return
	}
	var input struct {
		Decision string `json:"decision"`
		Reason   string `json:"reason"`
	}
	if err := decodeJSON(r, &input); err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_BODY", Message: "请求体格式错误"})
		return
	}
	input.Decision = strings.TrimSpace(input.Decision)
	input.Reason = strings.TrimSpace(input.Reason)
	if (input.Decision != "approve" && input.Decision != "reject") || len([]rune(input.Reason)) > 1000 || (input.Decision == "reject" && input.Reason == "") {
		writeAuthError(w, r, ErrInvalidStoreOrderReview)
		return
	}

	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	var userID string
	if err := tx.QueryRowContext(r.Context(), `SELECT user_id FROM store_orders WHERE id = $1`, orderID).Scan(&userID); errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrStoreOrderNotFound)
		return
	} else if err != nil {
		writeInternalError(w, r, err)
		return
	}
	var balance int64
	if err := tx.QueryRowContext(r.Context(), `SELECT points_balance FROM users WHERE id = $1 FOR UPDATE`, userID).Scan(&balance); err != nil {
		writeInternalError(w, r, err)
		return
	}
	var productName string
	var points int64
	var currentStatus string
	if err := tx.QueryRowContext(r.Context(), `
		SELECT p.name, o.points, o.status
		FROM store_orders o JOIN store_products p ON p.id = o.product_id
		WHERE o.id = $1
		FOR UPDATE OF o`, orderID).Scan(&productName, &points, &currentStatus); errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrStoreOrderNotFound)
		return
	} else if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if currentStatus != "pending_review" {
		writeAuthError(w, r, ErrStoreOrderAlreadyReview)
		return
	}
	now := time.Now().UTC()
	newStatus := "rejected"
	newBalance := balance
	if input.Decision == "approve" {
		var otherReserved int64
		if err := tx.QueryRowContext(r.Context(), `
			SELECT COALESCE(SUM(points), 0)
			FROM store_orders
			WHERE user_id = $1 AND status = 'pending_review' AND id <> $2`, userID, orderID).Scan(&otherReserved); err != nil {
			writeInternalError(w, r, err)
			return
		}
		if balance-otherReserved < points {
			writeAuthError(w, r, ErrInsufficientPoints)
			return
		}
		newStatus = "approved"
		newBalance = balance - points
		if _, err := tx.ExecContext(r.Context(), `UPDATE users SET points_balance = $1, updated_at = now() WHERE id = $2`, newBalance, userID); err != nil {
			writeInternalError(w, r, err)
			return
		}
		if _, err := tx.ExecContext(r.Context(), `
			INSERT INTO point_transactions (id, user_id, source, delta, balance_after, reason, idempotency_key)
			VALUES ($1, $2, 'store', $3, $4, $5, $6)
			ON CONFLICT (user_id, idempotency_key) WHERE idempotency_key IS NOT NULL DO NOTHING`, newPostID(), userID, -points, newBalance, productName, "store:approve:"+orderID); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	if _, err := tx.ExecContext(r.Context(), `
		UPDATE store_orders
		SET status = $2, reviewed_by = $3, reviewed_at = $4, review_reason = $5, updated_at = $4
		WHERE id = $1 AND status = 'pending_review'`, orderID, newStatus, operator.ID, now, input.Reason); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := appendAdminLogTx(r.Context(), tx, operator.ID, "store.order."+input.Decision, "store_order", orderID, input.Reason, requestIDFromRequest(r), httpserver.ClientIP(r), map[string]any{
		"user_id": userID, "product_name": productName, "points": points, "from_status": "pending_review", "to_status": newStatus,
	}, now); err != nil {
		writeInternalError(w, r, err)
		return
	}
	message := fmt.Sprintf("你申请兑换「%s」已通过，已扣除 %d 积分，请留意领取通知。", productName, points)
	if input.Decision == "reject" {
		message = fmt.Sprintf("你申请兑换「%s」未通过审核。原因：%s；本次相关积分不计入兑换资格。\n如继续正常参与论坛讨论，后续仍可重新申请兑换。", productName, input.Reason)
	}
	if err := enqueueNotificationWithDataTx(tx, userID, operator.ID, "store.order.reviewed", "store_order", orderID, map[string]any{
		"title":        "兑换申请审核结果",
		"message":      message,
		"status":       newStatus,
		"product_name": productName,
		"points":       points,
		"reason":       input.Reason,
	}, now); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"id": orderID, "status": newStatus, "balance": newBalance, "review_reason": input.Reason})
}
