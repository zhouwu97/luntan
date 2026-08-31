package api

import (
	"context"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/zhouwu97/luntan/server/internal/auth"
	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

var (
	ErrInvalidStoreOrderReview = errors.New("invalid store order review")
	ErrStoreOrderNotFound      = errors.New("store order not found")
	ErrStoreOrderAlreadyReview = errors.New("store order already reviewed")
	ErrStoreOrderReviewPending = errors.New("store order review pending")
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

type storeOrderCursor struct {
	CreatedAt time.Time `json:"created_at"`
	ID        string    `json:"id"`
}

func encodeStoreOrderCursor(cursor storeOrderCursor) string {
	data, _ := json.Marshal(cursor)
	return base64.RawURLEncoding.EncodeToString(data)
}

func decodeStoreOrderCursor(value string) (storeOrderCursor, error) {
	data, err := base64.RawURLEncoding.DecodeString(value)
	if err != nil {
		return storeOrderCursor{}, err
	}
	var cursor storeOrderCursor
	if err := json.Unmarshal(data, &cursor); err != nil || cursor.ID == "" || cursor.CreatedAt.IsZero() {
		return storeOrderCursor{}, errors.New("invalid store order cursor")
	}
	return cursor, nil
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
	args := []any{status}
	where := "o.status = $1"
	if rawCursor := strings.TrimSpace(r.URL.Query().Get("cursor")); rawCursor != "" {
		cursor, decodeErr := decodeStoreOrderCursor(rawCursor)
		if decodeErr != nil {
			httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_CURSOR", Message: "兑换订单游标无效"})
			return
		}
		where += " AND (o.created_at, o.id) < ($2, $3)"
		args = append(args, cursor.CreatedAt, cursor.ID)
	}
	limitPosition := len(args) + 1
	args = append(args, limit+1)
	rows, err := s.db.QueryContext(r.Context(), `
		SELECT o.id, o.user_id, u.username, COALESCE(up.nickname, u.username),
		       p.id, p.name, o.points, o.status, o.created_at,
		       COALESCE(o.reviewed_by, ''), o.reviewed_at, o.review_reason,
		       u.points_balance
		FROM store_orders o
		JOIN users u ON u.id = o.user_id
		LEFT JOIN user_profiles up ON up.user_id = u.id
		JOIN store_products p ON p.id = o.product_id
		WHERE `+where+`
		ORDER BY o.created_at DESC, o.id DESC
		LIMIT $`+strconv.Itoa(limitPosition), args...)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()
	items := make([]map[string]any, 0, limit+1)
	var lastCursor storeOrderCursor
	for rows.Next() {
		item, err := scanAdminStoreOrder(rows)
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
		if len(items) < limit {
			lastCursor = storeOrderCursor{
				CreatedAt: item["created_at"].(time.Time),
				ID:        item["id"].(string),
			}
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	hasMore := len(items) > limit
	if hasMore {
		items = items[:limit]
	}
	var nextCursor any
	if hasMore {
		nextCursor = encodeStoreOrderCursor(lastCursor)
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items, "next_cursor": nextCursor, "has_more": hasMore})
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

// getAdminStoreOrderRewardContent 将正向积分流水按业务幂等键还原到原始内容。
// 这里不复用普通用户主页查询，因为普通查询会隐藏已删除、待审核和被编辑后的内容。
func (s *Server) getAdminStoreOrderRewardContent(w http.ResponseWriter, r *http.Request, orderID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	if _, ok := s.requireStoreOrderReviewer(w, r); !ok {
		return
	}
	var userID string
	if err := s.db.QueryRowContext(r.Context(), `SELECT user_id FROM store_orders WHERE id = $1`, orderID).Scan(&userID); errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrStoreOrderNotFound)
		return
	} else if err != nil {
		writeInternalError(w, r, err)
		return
	}

	rows, err := s.db.QueryContext(r.Context(), `
		SELECT pt.id, pt.source, pt.delta, pt.reason, pt.created_at, pt.idempotency_key,
		       p.id, p.title, p.content,
		       pr.id, COALESCE(pr.title, p.title), COALESCE(pr.content, p.content),
		       c.id, c.content, COALESCE(NULLIF(c.original_content, ''), c.content),
		       parent.title,
		       CASE
		         WHEN pt.source = 'post' AND p.id IS NULL THEN 'missing'
		         WHEN pt.source = 'post' AND (p.deleted_at IS NOT NULL OR p.publication_status = 'deleted' OR p.post_status = 'deleted') THEN 'deleted'
		         WHEN pt.source = 'post' AND (p.publication_status <> 'published' OR p.moderation_status <> 'normal' OR p.post_status <> 'published') THEN 'unavailable'
		         WHEN pt.source = 'comment' AND c.id IS NULL THEN 'missing'
		         WHEN pt.source = 'comment' AND (c.deleted_at IS NOT NULL OR c.publication_status = 'deleted') THEN 'deleted'
		         WHEN pt.source = 'comment' AND (c.publication_status <> 'published' OR c.moderation_status <> 'normal') THEN 'unavailable'
		         ELSE 'normal'
		       END,
		       CASE
		         WHEN pt.source = 'post' THEN COALESCE(pr.title, p.title) IS DISTINCT FROM p.title
		              OR COALESCE(pr.content, p.content) IS DISTINCT FROM p.content
		         WHEN pt.source = 'comment' THEN COALESCE(NULLIF(c.original_content, ''), c.content) IS DISTINCT FROM c.content
		         ELSE false
		       END
		FROM point_transactions pt
		LEFT JOIN posts p
		       ON pt.source = 'post'
		      AND pt.idempotency_key = 'post:create:' || p.id
		      AND p.author_id = pt.user_id
		LEFT JOIN LATERAL (
			SELECT pr0.id, pr0.title, pr0.content
			FROM post_revisions pr0
			WHERE pr0.post_id = p.id
			ORDER BY pr0.created_at ASC, pr0.id ASC
			LIMIT 1
		) pr ON true
		LEFT JOIN comments c
		       ON pt.source = 'comment'
		      AND pt.idempotency_key = 'comment:create:' || c.id
		      AND c.author_id = pt.user_id
		LEFT JOIN posts parent ON parent.id = c.post_id
		WHERE pt.user_id = $1
		  AND pt.delta > 0
		  AND ((pt.source = 'post' AND pt.idempotency_key LIKE 'post:create:%')
		    OR (pt.source = 'comment' AND pt.idempotency_key LIKE 'comment:create:%'))
		ORDER BY pt.created_at DESC, pt.id DESC`, userID)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()

	items := make([]map[string]any, 0)
	for rows.Next() {
		var transactionID, source, reason, idempotencyKey string
		var delta int64
		var earnedAt time.Time
		var postID, postTitle, postContent, postRevisionID, rewardTitle, rewardContent sql.NullString
		var commentID, commentContent, commentOriginalContent, parentTitle sql.NullString
		var currentStatus sql.NullString
		var edited bool
		if err := rows.Scan(
			&transactionID, &source, &delta, &reason, &earnedAt, &idempotencyKey,
			&postID, &postTitle, &postContent, &postRevisionID, &rewardTitle, &rewardContent,
			&commentID, &commentContent, &commentOriginalContent, &parentTitle,
			&currentStatus, &edited,
		); err != nil {
			writeInternalError(w, r, err)
			return
		}

		targetID := strings.TrimPrefix(idempotencyKey, source+":create:")
		titleAtReward := ""
		contentAtReward := ""
		currentTitle := ""
		currentContent := ""
		snapshotAvailable := false
		if source == "post" {
			if postID.Valid {
				targetID = postID.String
			}
			titleAtReward = rewardTitle.String
			contentAtReward = rewardContent.String
			currentTitle = postTitle.String
			currentContent = postContent.String
			snapshotAvailable = postRevisionID.Valid
		} else {
			if commentID.Valid {
				targetID = commentID.String
			}
			titleAtReward = parentTitle.String
			if commentOriginalContent.Valid {
				contentAtReward = commentOriginalContent.String
			} else {
				contentAtReward = commentContent.String
			}
			currentTitle = parentTitle.String
			currentContent = commentContent.String
			snapshotAvailable = commentOriginalContent.Valid || commentContent.Valid
		}
		if targetID == "" {
			currentStatus = sql.NullString{String: "missing", Valid: true}
		}
		items = append(items, map[string]any{
			"id":                  transactionID,
			"source":              source,
			"target_type":         source,
			"target_id":           targetID,
			"points":              delta,
			"reason":              reason,
			"earned_at":           earnedAt,
			"title_at_reward":     titleAtReward,
			"content_at_reward":   contentAtReward,
			"current_title":       currentTitle,
			"current_content":     currentContent,
			"current_status":      currentStatus.String,
			"edited_since_reward": edited,
			"snapshot_available":  snapshotAvailable,
		})
	}
	if err := rows.Err(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items})
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
			`, newPostID(), userID, -points, newBalance, productName, "store:approve:"+orderID); err != nil {
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
