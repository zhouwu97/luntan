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
	ErrInvalidStoreReward      = errors.New("invalid store reward content")
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
	case "all", "pending_review", "approved", "rejected", "pending", "claimed", "completed", "cancelled":
		return true
	default:
		return false
	}
}

type storeOrderCursor struct {
	CreatedAt time.Time `json:"created_at"`
	ID        string    `json:"id"`
}

type storeRewardContentCursor struct {
	Priority int       `json:"priority"`
	EarnedAt time.Time `json:"earned_at"`
	ID       string    `json:"id"`
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

func encodeStoreRewardContentCursor(cursor storeRewardContentCursor) (string, error) {
	data, err := json.Marshal(cursor)
	if err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(data), nil
}

func decodeStoreRewardContentCursor(value string) (storeRewardContentCursor, error) {
	data, err := base64.RawURLEncoding.DecodeString(value)
	if err != nil {
		return storeRewardContentCursor{}, err
	}
	var cursor storeRewardContentCursor
	if err := json.Unmarshal(data, &cursor); err != nil || cursor.ID == "" || cursor.EarnedAt.IsZero() || cursor.Priority < 0 || cursor.Priority > 2 {
		return storeRewardContentCursor{}, errors.New("invalid store reward content cursor")
	}
	return cursor, nil
}

func validStoreRewardContentSource(source string) bool {
	return source == "" || source == "post" || source == "comment"
}

func validStoreRewardContentStatus(status string) bool {
	switch status {
	case "", "normal", "deleted", "unavailable", "missing":
		return true
	default:
		return false
	}
}

func rewardContentPriority(status string, edited bool) int {
	if status == "deleted" || status == "unavailable" || status == "missing" {
		return 2
	}
	if edited {
		return 1
	}
	return 0
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
	args := make([]any, 0, 3)
	where := "TRUE"
	if status != "all" {
		args = append(args, status)
		where = "o.status = $1"
	}
	if rawCursor := strings.TrimSpace(r.URL.Query().Get("cursor")); rawCursor != "" {
		cursor, decodeErr := decodeStoreOrderCursor(rawCursor)
		if decodeErr != nil {
			httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_CURSOR", Message: "兑换订单游标无效"})
			return
		}
		createdAtPosition := len(args) + 1
		idPosition := createdAtPosition + 1
		where += " AND (o.created_at, o.id) < ($" + strconv.Itoa(createdAtPosition) + ", $" + strconv.Itoa(idPosition) + ")"
		args = append(args, cursor.CreatedAt, cursor.ID)
	}
	limitPosition := len(args) + 1
	args = append(args, limit+1)
	rows, err := s.db.QueryContext(r.Context(), `
		SELECT o.id, o.user_id, u.username, COALESCE(up.nickname, u.username),
		       p.id, p.name, o.points, o.status, o.created_at,
		       COALESCE(o.reviewed_by, ''), o.reviewed_at, o.review_reason,
		       u.points_balance, o.balance_at_submit, o.balance_snapshot_trusted,
		       COALESCE((SELECT COUNT(*) FROM store_point_invalidations spi
		                 WHERE spi.source_order_id = o.id), 0),
		       COALESCE((SELECT SUM(pt.delta)
		                 FROM store_point_invalidations spi
		                 JOIN point_transactions pt ON pt.id = spi.point_transaction_id
		                 WHERE spi.source_order_id = o.id), 0)
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
	var points, userPoints, balanceAtSubmit, invalidatedCount, invalidatedPoints int64
	var balanceSnapshotTrusted bool
	var createdAt time.Time
	var reviewedAt sql.NullTime
	if err := scanner.Scan(&id, &userID, &username, &nickname, &productID, &productName, &points, &status, &createdAt, &reviewedBy, &reviewedAt, &reviewReason, &userPoints, &balanceAtSubmit, &balanceSnapshotTrusted, &invalidatedCount, &invalidatedPoints); err != nil {
		return nil, err
	}
	item := map[string]any{
		"id": id, "user_id": userID, "username": username, "nickname": nickname,
		"product_id": productID, "product_name": productName, "points": points,
		"status": status, "created_at": createdAt, "reviewed_by": reviewedBy,
		"review_reason": reviewReason, "user_points": userPoints,
		"balance_at_submit":        balanceAtSubmit,
		"balance_snapshot_trusted": balanceSnapshotTrusted,
		"invalidated_count":        invalidatedCount,
		"invalidated_points":       invalidatedPoints,
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
		SELECT pt.source, COALESCE(SUM(pt.delta), 0), COUNT(*),
		       COALESCE(SUM(CASE WHEN spi.point_transaction_id IS NOT NULL THEN pt.delta ELSE 0 END), 0)
		FROM point_transactions pt
		JOIN store_orders scope ON scope.id = $1 AND scope.user_id = pt.user_id
		LEFT JOIN store_point_invalidations spi ON spi.point_transaction_id = pt.id
		WHERE pt.user_id = $2 AND pt.delta > 0 AND pt.created_at <= scope.created_at
		GROUP BY pt.source
		ORDER BY SUM(pt.delta) DESC, pt.source ASC`, orderID, order["user_id"])
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer sourceRows.Close()
	sources := make([]map[string]any, 0)
	for sourceRows.Next() {
		var source string
		var points, count, invalidPoints int64
		if err := sourceRows.Scan(&source, &points, &count, &invalidPoints); err != nil {
			writeInternalError(w, r, err)
			return
		}
		sources = append(sources, map[string]any{"source": source, "points": points, "count": count, "invalid_points": invalidPoints})
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
	var invalidatedPoints int64
	if err := s.db.QueryRowContext(r.Context(), `
		SELECT COALESCE(SUM(pt.delta), 0)
		FROM store_point_invalidations spi
		JOIN point_transactions pt ON pt.id = spi.point_transaction_id
		WHERE spi.user_id = $1 AND pt.delta > 0 AND pt.created_at <= $2`, order["user_id"], order["created_at"]).Scan(&invalidatedPoints); err != nil {
		writeInternalError(w, r, err)
		return
	}
	order["historical_invalidated_points"] = invalidatedPoints
	balanceAtSubmit := order["balance_at_submit"].(int64)
	order["eligible_points_at_submit"] = balanceAtSubmit - invalidatedPoints
	httpserver.WriteJSON(w, http.StatusOK, order)
}

// getAdminStoreOrderRewardContent 将正向积分流水按业务幂等键还原到原始内容。
// 这里不复用普通用户主页查询，因为普通查询会隐藏已删除、待审核和被编辑后的内容。
// 查询范围固定在订单创建时，避免管理员等待审核期间出现新的奖励流水。
func (s *Server) getAdminStoreOrderRewardContent(w http.ResponseWriter, r *http.Request, orderID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	if _, ok := s.requireStoreOrderReviewer(w, r); !ok {
		return
	}
	source := strings.TrimSpace(r.URL.Query().Get("source"))
	status := strings.TrimSpace(r.URL.Query().Get("status"))
	if !validStoreRewardContentSource(source) {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_SOURCE", Message: "积分内容来源无效"})
		return
	}
	if !validStoreRewardContentStatus(status) {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_CONTENT_STATUS", Message: "积分内容状态无效"})
		return
	}
	limit, err := parseLimit(r.URL.Query().Get("limit"))
	if err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_LIMIT", Message: "limit 必须是 1 到 50 之间的整数"})
		return
	}
	var cursor *storeRewardContentCursor
	if rawCursor := strings.TrimSpace(r.URL.Query().Get("cursor")); rawCursor != "" {
		decoded, decodeErr := decodeStoreRewardContentCursor(rawCursor)
		if decodeErr != nil {
			httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_CURSOR", Message: "积分内容游标无效"})
			return
		}
		cursor = &decoded
	}

	var userID string
	if err := s.db.QueryRowContext(r.Context(), `SELECT user_id FROM store_orders WHERE id = $1`, orderID).Scan(&userID); errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrStoreOrderNotFound)
		return
	} else if err != nil {
		writeInternalError(w, r, err)
		return
	}

	args := []any{orderID, source, status}
	where := "($2 = '' OR source = $2) AND ($3 = '' OR current_status = $3)"
	if cursor != nil {
		where += " AND (review_priority < $4 OR (review_priority = $4 AND earned_at < $5) OR (review_priority = $4 AND earned_at = $5 AND id < $6))"
		args = append(args, cursor.Priority, cursor.EarnedAt, cursor.ID)
	}
	limitPosition := len(args) + 1
	args = append(args, limit+1)
	rows, err := s.db.QueryContext(r.Context(), `
		WITH reward_rows AS (
			SELECT pt.id, pt.source, pt.delta, pt.reason, pt.created_at AS earned_at, pt.idempotency_key,
			       p.id AS post_id, p.title AS post_title, p.content AS post_content,
			       pr.id AS post_revision_id,
			       COALESCE(pr.title, p.title) AS reward_title,
			       COALESCE(pr.content, p.content) AS reward_content,
			       c.id AS comment_id, c.content AS comment_content,
			       COALESCE(NULLIF(c.original_content, ''), c.content) AS comment_original_content,
			       parent.title AS parent_title,
			       CASE
			         WHEN pt.source = 'post' AND p.id IS NULL THEN 'missing'
			         WHEN pt.source = 'post' AND (p.deleted_at IS NOT NULL OR p.publication_status = 'deleted' OR p.post_status = 'deleted') THEN 'deleted'
			         WHEN pt.source = 'post' AND (p.publication_status <> 'published' OR p.moderation_status <> 'normal' OR p.post_status <> 'published') THEN 'unavailable'
			         WHEN pt.source = 'comment' AND c.id IS NULL THEN 'missing'
			         WHEN pt.source = 'comment' AND (c.deleted_at IS NOT NULL OR c.publication_status = 'deleted') THEN 'deleted'
			         WHEN pt.source = 'comment' AND (c.publication_status <> 'published' OR c.moderation_status <> 'normal') THEN 'unavailable'
			         ELSE 'normal'
			       END AS current_status,
			       CASE
			         WHEN pt.source = 'post' THEN COALESCE(pr.title, p.title) IS DISTINCT FROM p.title
			              OR COALESCE(pr.content, p.content) IS DISTINCT FROM p.content
			         WHEN pt.source = 'comment' THEN COALESCE(NULLIF(c.original_content, ''), c.content) IS DISTINCT FROM c.content
			         ELSE false
			       END AS edited_since_reward,
			       (spi.point_transaction_id IS NOT NULL) AS invalidated,
			       COALESCE(spi.reason, '') AS invalidation_reason
			FROM point_transactions pt
			JOIN store_orders scope ON scope.id = $1 AND scope.user_id = pt.user_id
			LEFT JOIN store_point_invalidations spi ON spi.point_transaction_id = pt.id
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
			WHERE pt.delta > 0
			  AND pt.created_at <= scope.created_at
			  AND ((pt.source = 'post' AND pt.idempotency_key LIKE 'post:create:%')
			    OR (pt.source = 'comment' AND pt.idempotency_key LIKE 'comment:create:%'))
		), ranked AS (
			SELECT reward_rows.*,
			       CASE
			         WHEN current_status IN ('deleted', 'unavailable', 'missing') THEN 2
			         WHEN edited_since_reward THEN 1
			         ELSE 0
			       END AS review_priority
			FROM reward_rows
		)
		SELECT id, source, delta, reason, earned_at, idempotency_key,
		       post_id, post_title, post_content, post_revision_id, reward_title, reward_content,
		       comment_id, comment_content, comment_original_content, parent_title,
		       current_status, edited_since_reward, invalidated, invalidation_reason, review_priority
		FROM ranked
		WHERE `+where+`
		ORDER BY review_priority DESC, earned_at DESC, id DESC
		LIMIT $`+strconv.Itoa(limitPosition), args...)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()

	items := make([]map[string]any, 0, limit+1)
	var lastCursor storeRewardContentCursor
	for rows.Next() {
		var transactionID, source, reason, idempotencyKey, currentStatus, invalidationReason string
		var delta int64
		var earnedAt time.Time
		var postID, postTitle, postContent, postRevisionID, rewardTitle, rewardContent sql.NullString
		var commentID, commentContent, commentOriginalContent, parentTitle sql.NullString
		var edited, invalidated bool
		var priority int
		if err := rows.Scan(
			&transactionID, &source, &delta, &reason, &earnedAt, &idempotencyKey,
			&postID, &postTitle, &postContent, &postRevisionID, &rewardTitle, &rewardContent,
			&commentID, &commentContent, &commentOriginalContent, &parentTitle,
			&currentStatus, &edited, &invalidated, &invalidationReason, &priority,
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
			"current_status":      currentStatus,
			"edited_since_reward": edited,
			"snapshot_available":  snapshotAvailable,
			"invalidated":         invalidated,
			"invalidation_reason": invalidationReason,
			"review_priority":     priority,
		})
		if len(items) <= limit {
			lastCursor = storeRewardContentCursor{Priority: priority, EarnedAt: earnedAt, ID: transactionID}
		}
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
	if hasMore && len(items) > 0 {
		encoded, encodeErr := encodeStoreRewardContentCursor(lastCursor)
		if encodeErr != nil {
			writeInternalError(w, r, encodeErr)
			return
		}
		nextCursor = encoded
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items, "next_cursor": nextCursor, "has_more": hasMore})
}

func (s *Server) loadAdminStoreOrder(ctx context.Context, queryer interface {
	QueryRowContext(context.Context, string, ...any) *sql.Row
}, orderID string) (map[string]any, error) {
	// 该辅助函数只用于复用列表字段；context 类型由调用方保证为 request.Context。
	row := queryer.QueryRowContext(ctx, `
		SELECT o.id, o.user_id, u.username, COALESCE(up.nickname, u.username),
		       p.id, p.name, o.points, o.status, o.created_at,
		       COALESCE(o.reviewed_by, ''), o.reviewed_at, o.review_reason,
		       u.points_balance, o.balance_at_submit, o.balance_snapshot_trusted,
		       COALESCE((SELECT COUNT(*) FROM store_point_invalidations spi
		                 WHERE spi.source_order_id = o.id), 0),
		       COALESCE((SELECT SUM(pt.delta)
		                 FROM store_point_invalidations spi
		                 JOIN point_transactions pt ON pt.id = spi.point_transaction_id
		                 WHERE spi.source_order_id = o.id), 0)
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
		Decision              string   `json:"decision"`
		Reason                string   `json:"reason"`
		InvalidTransactionIDs []string `json:"invalid_transaction_ids"`
	}
	if err := decodeJSON(r, &input); err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_BODY", Message: "请求体格式错误"})
		return
	}
	input.Decision = strings.TrimSpace(input.Decision)
	input.Reason = strings.TrimSpace(input.Reason)
	if (input.Decision != "approve" && input.Decision != "reject") || len([]rune(input.Reason)) > 1000 || (input.Decision == "reject" && input.Reason == "") || len(input.InvalidTransactionIDs) > 2000 {
		writeAuthError(w, r, ErrInvalidStoreOrderReview)
		return
	}
	seenInvalidations := make(map[string]struct{}, len(input.InvalidTransactionIDs))
	transactionIDs := make([]string, 0, len(input.InvalidTransactionIDs))
	for _, id := range input.InvalidTransactionIDs {
		id = strings.TrimSpace(id)
		if id == "" {
			writeAuthError(w, r, ErrInvalidStoreReward)
			return
		}
		if _, exists := seenInvalidations[id]; exists {
			writeAuthError(w, r, ErrInvalidStoreReward)
			return
		}
		seenInvalidations[id] = struct{}{}
		transactionIDs = append(transactionIDs, id)
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
	var points, balanceAtSubmit int64
	var orderCreatedAt time.Time
	var currentStatus string
	if err := tx.QueryRowContext(r.Context(), `
		SELECT p.name, o.points, o.status, o.created_at, o.balance_at_submit
		FROM store_orders o JOIN store_products p ON p.id = o.product_id
		WHERE o.id = $1
		FOR UPDATE OF o`, orderID).Scan(&productName, &points, &currentStatus, &orderCreatedAt, &balanceAtSubmit); errors.Is(err, sql.ErrNoRows) {
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
	var historicalInvalidatedPoints int64
	if err := tx.QueryRowContext(r.Context(), `
		SELECT COALESCE(SUM(pt.delta), 0)
		FROM store_point_invalidations spi
		JOIN point_transactions pt ON pt.id = spi.point_transaction_id
		WHERE spi.user_id = $1 AND pt.delta > 0 AND pt.created_at <= $2`, userID, orderCreatedAt).Scan(&historicalInvalidatedPoints); err != nil {
		writeInternalError(w, r, err)
		return
	}
	newInvalidatedPoints, err := validateStoreRewardSelections(r.Context(), tx, userID, orderID, orderCreatedAt, transactionIDs)
	if errors.Is(err, ErrInvalidStoreReward) {
		writeAuthError(w, r, err)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	newInvalidatedCount := len(transactionIDs)
	eligiblePoints := balanceAtSubmit - historicalInvalidatedPoints - newInvalidatedPoints
	if input.Decision == "approve" && eligiblePoints < points {
		writeAuthError(w, r, ErrInsufficientPoints)
		return
	}
	if len(transactionIDs) > 0 {
		invalidationReason := input.Reason
		if invalidationReason == "" {
			invalidationReason = "管理员判定该奖励不计入兑换资格"
		}
		if err := insertStorePointInvalidations(r.Context(), tx, userID, orderID, operator.ID, invalidationReason, transactionIDs); err != nil {
			writeInternalError(w, r, err)
			return
		}
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
		"balance_at_submit": balanceAtSubmit, "historical_invalidated_points": historicalInvalidatedPoints,
		"new_invalidated_count": newInvalidatedCount, "new_invalidated_points": newInvalidatedPoints,
		"eligible_points_at_submit": eligiblePoints,
	}, now); err != nil {
		writeInternalError(w, r, err)
		return
	}
	message := storeOrderReviewNotification(
		productName,
		input.Decision,
		input.Reason,
		points,
		newInvalidatedCount,
		newInvalidatedPoints,
	)
	if err := enqueueNotificationWithDataTx(tx, userID, operator.ID, "store.order.reviewed", "store_order", orderID, map[string]any{
		"title":                  "兑换申请审核结果",
		"message":                message,
		"status":                 newStatus,
		"product_name":           productName,
		"points":                 points,
		"reason":                 input.Reason,
		"invalidated_count":      newInvalidatedCount,
		"invalidated_points":     newInvalidatedPoints,
		"new_invalidated_count":  newInvalidatedCount,
		"new_invalidated_points": newInvalidatedPoints,
	}, now); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{
		"id":                            orderID,
		"status":                        newStatus,
		"balance":                       newBalance,
		"review_reason":                 input.Reason,
		"balance_at_submit":             balanceAtSubmit,
		"historical_invalidated_points": historicalInvalidatedPoints,
		"new_invalidated_count":         newInvalidatedCount,
		"new_invalidated_points":        newInvalidatedPoints,
		"eligible_points_at_submit":     eligiblePoints,
	})
}

// storeOrderReviewNotification 只描述本次审核实际发生的状态变化，避免拒绝订单
// 时把“没有失效处理”误写成“相关积分不计入资格”。
func storeOrderReviewNotification(productName, decision, reason string, points int64, invalidatedCount int, invalidatedPoints int64) string {
	if decision == "approve" {
		message := fmt.Sprintf("你申请兑换「%s」已通过审核，已扣除 %d 积分，请留意领取通知。", productName, points)
		if invalidatedCount > 0 {
			message += fmt.Sprintf("本次另认定 %d 条奖励记录无效，对应 %d 积分不再计入后续兑换资格。", invalidatedCount, invalidatedPoints)
		}
		return message
	}

	message := fmt.Sprintf("你申请兑换「%s」未通过审核。\n原因：%s\n", productName, reason)
	if invalidatedCount > 0 {
		message += fmt.Sprintf("本次共认定 %d 条奖励记录无效，对应 %d 积分不再计入兑换资格。\n", invalidatedCount, invalidatedPoints)
	} else {
		message += "本次审核未对你的历史积分作失效处理。\n"
	}
	return message + "你后续新获得的有效积分仍可正常用于兑换。"
}

func validateStoreRewardSelections(ctx context.Context, tx *sql.Tx, userID, orderID string, orderCreatedAt time.Time, transactionIDs []string) (int64, error) {
	if len(transactionIDs) == 0 {
		return 0, nil
	}
	placeholders := make([]string, 0, len(transactionIDs))
	args := []any{userID, orderID, orderCreatedAt}
	for index, id := range transactionIDs {
		placeholders = append(placeholders, "$"+strconv.Itoa(index+4))
		args = append(args, id)
	}
	var count, points int64
	err := tx.QueryRowContext(ctx, `
		SELECT COUNT(*), COALESCE(SUM(pt.delta), 0)
		FROM point_transactions pt
		LEFT JOIN store_point_invalidations spi ON spi.point_transaction_id = pt.id
		WHERE pt.user_id = $1
		  AND pt.id IN (`+strings.Join(placeholders, ",")+`)
		  AND pt.delta > 0
		  AND spi.point_transaction_id IS NULL
		  AND ((pt.source = 'post' AND pt.idempotency_key LIKE 'post:create:%')
		    OR (pt.source = 'comment' AND pt.idempotency_key LIKE 'comment:create:%'))
		  AND pt.created_at <= $3
		  AND EXISTS (SELECT 1 FROM store_orders WHERE id = $2 AND user_id = pt.user_id AND created_at = $3)`, args...).Scan(&count, &points)
	if err != nil {
		return 0, err
	}
	if count != int64(len(transactionIDs)) {
		return 0, ErrInvalidStoreReward
	}
	return points, nil
}

func insertStorePointInvalidations(ctx context.Context, tx *sql.Tx, userID, orderID, reviewerID, reason string, transactionIDs []string) error {
	placeholders := make([]string, 0, len(transactionIDs))
	args := []any{userID, orderID, reviewerID, reason}
	for index, id := range transactionIDs {
		placeholders = append(placeholders, "$"+strconv.Itoa(index+5))
		args = append(args, id)
	}
	_, err := tx.ExecContext(ctx, `
		INSERT INTO store_point_invalidations (point_transaction_id, user_id, source_order_id, reason, reviewed_by)
		SELECT pt.id, pt.user_id, $2, $4, $3
		FROM point_transactions pt
		WHERE pt.user_id = $1 AND pt.id IN (`+strings.Join(placeholders, ",")+`)
		ON CONFLICT (point_transaction_id) DO NOTHING`, args...)
	return err
}
