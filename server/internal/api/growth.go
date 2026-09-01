package api

import (
	"context"
	"database/sql"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

var ErrInsufficientPoints = errors.New("insufficient points")
var ErrPollAlreadyVoted = errors.New("poll already voted")

type pollInput struct {
	Question      string     `json:"question"`
	Options       []string   `json:"options"`
	AllowMultiple bool       `json:"allow_multiple"`
	EndsAt        *time.Time `json:"ends_at"`
}

func (s *Server) createPoll(w http.ResponseWriter, r *http.Request, postID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.requireRegisteredUser(w, r)
	if !ok {
		return
	}
	if !s.requireCapability(w, r, user, capCreatePoll) {
		return
	}
	var input pollInput
	if err := decodeJSON(r, &input); err != nil || !validPollInput(&input) {
		writeAuthError(w, r, ErrInvalidPost)
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	var existing string
	err = tx.QueryRowContext(r.Context(), `SELECT id FROM posts WHERE id = $1 AND author_id = $2 AND type = 'poll' AND deleted_at IS NULL FOR UPDATE`, postID, user.ID).Scan(&existing)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrPostNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := insertPollTx(r.Context(), tx, postID, &input); err != nil {
		writeInternalError(w, r, err)
		return
	}
	var pollID string
	if err := tx.QueryRowContext(r.Context(), `SELECT id FROM polls WHERE post_id = $1`, postID).Scan(&pollID); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusCreated, map[string]any{"id": pollID, "post_id": postID, "question": input.Question, "allow_multiple": input.AllowMultiple, "options": input.Options})
}

func (s *Server) getPoll(w http.ResponseWriter, r *http.Request, postID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	var pollID, question string
	var allowMultiple bool
	var endsAt sql.NullTime
	err := s.db.QueryRowContext(r.Context(), `SELECT id, question, allow_multiple, ends_at FROM polls WHERE post_id = $1`, postID).Scan(&pollID, &question, &allowMultiple, &endsAt)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrPostNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	rows, err := s.db.QueryContext(r.Context(), `SELECT id, label, sort_order, vote_count FROM poll_options WHERE poll_id = $1 ORDER BY sort_order ASC, id ASC`, pollID)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()
	options := make([]map[string]any, 0)
	for rows.Next() {
		var id, label string
		var sortOrder int
		var voteCount int64
		if err := rows.Scan(&id, &label, &sortOrder, &voteCount); err != nil {
			writeInternalError(w, r, err)
			return
		}
		options = append(options, map[string]any{"id": id, "label": label, "sort_order": sortOrder, "vote_count": voteCount})
	}
	if err := rows.Err(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	viewerState := map[string]any{
		"has_voted":               false,
		"option_ids":              []string{},
		"can_vote":                false,
		"authentication_required": true,
	}
	if viewer, ok := s.optionalAuthenticatedUser(r.Context(), r); ok {
		viewerState["authentication_required"] = false
		viewerState["can_vote"] = capabilitiesForUser(viewer)[capVote] && !(endsAt.Valid && !endsAt.Time.After(time.Now()))
		votedRows, queryErr := s.db.QueryContext(r.Context(), `SELECT option_id FROM poll_votes WHERE poll_id = $1 AND user_id = $2 ORDER BY option_id ASC`, pollID, viewer.ID)
		if queryErr != nil {
			writeInternalError(w, r, queryErr)
			return
		}
		votedOptionIDs := make([]string, 0)
		for votedRows.Next() {
			var optionID string
			if scanErr := votedRows.Scan(&optionID); scanErr != nil {
				votedRows.Close()
				writeInternalError(w, r, scanErr)
				return
			}
			votedOptionIDs = append(votedOptionIDs, optionID)
		}
		if rowsErr := votedRows.Err(); rowsErr != nil {
			votedRows.Close()
			writeInternalError(w, r, rowsErr)
			return
		}
		votedRows.Close()
		viewerState["has_voted"] = len(votedOptionIDs) > 0
		viewerState["option_ids"] = votedOptionIDs
		viewerState["can_vote"] = len(votedOptionIDs) == 0 && viewerState["can_vote"].(bool)
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"id": pollID, "post_id": postID, "question": question, "allow_multiple": allowMultiple, "ends_at": nullableTime(endsAt), "options": options, "viewer_state": viewerState})
}

func (s *Server) votePoll(w http.ResponseWriter, r *http.Request, pollID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if !s.requireCapability(w, r, user, capVote) {
		return
	}
	var input struct {
		OptionIDs []string `json:"option_ids"`
	}
	if err := decodeJSON(r, &input); err != nil || len(input.OptionIDs) == 0 || len(input.OptionIDs) > 10 {
		writeAuthError(w, r, ErrInvalidPost)
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	var allowMultiple bool
	var endsAt sql.NullTime
	err = tx.QueryRowContext(r.Context(), `SELECT allow_multiple, ends_at FROM polls WHERE id = $1 FOR UPDATE`, pollID).Scan(&allowMultiple, &endsAt)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrPostNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if endsAt.Valid && !endsAt.Time.After(time.Now()) {
		writeAuthError(w, r, ErrInvalidPost)
		return
	}
	if !allowMultiple && len(input.OptionIDs) != 1 {
		writeAuthError(w, r, ErrInvalidPost)
		return
	}
	seen := map[string]struct{}{}
	for _, optionID := range input.OptionIDs {
		if _, duplicate := seen[optionID]; duplicate {
			writeAuthError(w, r, ErrInvalidPost)
			return
		}
		seen[optionID] = struct{}{}
		var existing string
		err := tx.QueryRowContext(r.Context(), `SELECT id FROM poll_options WHERE id = $1 AND poll_id = $2`, optionID, pollID).Scan(&existing)
		if errors.Is(err, sql.ErrNoRows) {
			writeAuthError(w, r, ErrInvalidPost)
			return
		}
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	var existingOptionIDs []string
	existingRows, err := tx.QueryContext(r.Context(), `SELECT option_id FROM poll_votes WHERE poll_id = $1 AND user_id = $2 ORDER BY option_id ASC`, pollID, user.ID)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	for existingRows.Next() {
		var optionID string
		if err := existingRows.Scan(&optionID); err != nil {
			existingRows.Close()
			writeInternalError(w, r, err)
			return
		}
		existingOptionIDs = append(existingOptionIDs, optionID)
	}
	if err := existingRows.Err(); err != nil {
		existingRows.Close()
		writeInternalError(w, r, err)
		return
	}
	existingRows.Close()
	if len(existingOptionIDs) > 0 {
		if !sameStringSet(existingOptionIDs, input.OptionIDs) {
			httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusConflict, Code: "ALREADY_VOTED", Message: "你已经参与过该投票，不能修改选项"})
			return
		}
		if err := tx.Commit(); err != nil {
			writeInternalError(w, r, err)
			return
		}
		httpserver.WriteJSON(w, http.StatusOK, map[string]any{"poll_id": pollID, "option_ids": input.OptionIDs, "already_voted": true})
		return
	}
	for _, optionID := range input.OptionIDs {
		result, err := tx.ExecContext(r.Context(), `INSERT INTO poll_votes (poll_id, option_id, user_id) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING`, pollID, optionID, user.ID)
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
		changed, err := result.RowsAffected()
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
		if changed == 1 {
			if _, err := tx.ExecContext(r.Context(), `UPDATE poll_options SET vote_count = vote_count + 1 WHERE id = $1 AND poll_id = $2`, optionID, pollID); err != nil {
				writeInternalError(w, r, err)
				return
			}
		}
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"poll_id": pollID, "option_ids": input.OptionIDs})
}

func sameStringSet(first, second []string) bool {
	if len(first) != len(second) {
		return false
	}
	seen := make(map[string]struct{}, len(first))
	for _, value := range first {
		seen[value] = struct{}{}
	}
	if len(seen) != len(second) {
		return false
	}
	for _, value := range second {
		if _, ok := seen[value]; !ok {
			return false
		}
	}
	return true
}

func validPollInput(input *pollInput) bool {
	if input == nil || strings.TrimSpace(input.Question) == "" || len([]rune(input.Question)) > 200 || len(input.Options) < 2 || len(input.Options) > 10 {
		return false
	}
	seen := make(map[string]struct{}, len(input.Options))
	for _, option := range input.Options {
		option = strings.TrimSpace(option)
		if option == "" || len([]rune(option)) > 200 {
			return false
		}
		if _, exists := seen[option]; exists {
			return false
		}
		seen[option] = struct{}{}
	}
	return true
}

func insertPollTx(ctx context.Context, tx *sql.Tx, postID string, input *pollInput) error {
	if !validPollInput(input) {
		return ErrInvalidPost
	}
	question := strings.TrimSpace(input.Question)
	pollID := newPostID()
	if _, err := tx.ExecContext(ctx, `INSERT INTO polls (id, post_id, question, allow_multiple, ends_at) VALUES ($1, $2, $3, $4, $5)`, pollID, postID, question, input.AllowMultiple, input.EndsAt); err != nil {
		return err
	}
	for index, label := range input.Options {
		label = strings.TrimSpace(label)
		if _, err := tx.ExecContext(ctx, `INSERT INTO poll_options (id, poll_id, label, sort_order) VALUES ($1, $2, $3, $4)`, newPostID(), pollID, label, index); err != nil {
			return err
		}
	}
	return nil
}

func replacePollTx(ctx context.Context, tx *sql.Tx, postID string, input *pollInput) error {
	if err := deletePollTx(ctx, tx, postID); err != nil {
		return err
	}
	return insertPollTx(ctx, tx, postID, input)
}

func deletePollTx(ctx context.Context, tx *sql.Tx, postID string) error {
	if _, err := tx.ExecContext(ctx, `
		DELETE FROM poll_votes
		WHERE poll_id IN (SELECT id FROM polls WHERE post_id = $1)`, postID); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `
		DELETE FROM poll_options
		WHERE poll_id IN (SELECT id FROM polls WHERE post_id = $1)`, postID); err != nil {
		return err
	}
	_, err := tx.ExecContext(ctx, `DELETE FROM polls WHERE post_id = $1`, postID)
	return err
}

func (s *Server) ranking(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	window := r.URL.Query().Get("window")
	interval := "24 hours"
	switch window {
	case "1h":
		interval = "1 hour"
	case "7d":
		interval = "7 days"
	case "24h", "":
	default:
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_WINDOW", Message: "window 必须是 1h、24h 或 7d"})
		return
	}
	limit, err := parseLimit(r.URL.Query().Get("limit"))
	if err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_LIMIT", Message: "limit 无效"})
		return
	}
	rows, err := s.db.QueryContext(r.Context(), `SELECT id, title, community_id, (like_count * 3 + comment_count * 4 + bookmark_count * 2 + view_count * 0.1) / (1 + EXTRACT(EPOCH FROM (now() - published_at)) / 3600) AS score FROM posts WHERE publication_status = 'published' AND moderation_status = 'normal' AND type <> 'market' AND deleted_at IS NULL AND published_at >= now() - $1::interval ORDER BY score DESC, id DESC LIMIT $2`, interval, limit)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()
	items := make([]map[string]any, 0)
	for rows.Next() {
		var id, title, communityID string
		var score float64
		if err := rows.Scan(&id, &title, &communityID, &score); err != nil {
			writeInternalError(w, r, err)
			return
		}
		items = append(items, map[string]any{"id": id, "title": title, "community_id": communityID, "score": score})
	}
	if err := rows.Err(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"window": windowOrDefault(window, "24h"), "items": items})
}

func (s *Server) points(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	var balance int64
	if err := s.db.QueryRowContext(r.Context(), `SELECT points_balance FROM users WHERE id = $1`, user.ID).Scan(&balance); err != nil {
		writeInternalError(w, r, err)
		return
	}
	rows, err := s.db.QueryContext(r.Context(), `SELECT id, source, delta, balance_after, reason, created_at FROM point_transactions WHERE user_id = $1 ORDER BY created_at DESC, id DESC LIMIT 50`, user.ID)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()
	items := make([]map[string]any, 0)
	for rows.Next() {
		var id, source, reason string
		var delta, balanceAfter int64
		var createdAt time.Time
		if err := rows.Scan(&id, &source, &delta, &balanceAfter, &reason, &createdAt); err != nil {
			writeInternalError(w, r, err)
			return
		}
		items = append(items, map[string]any{"id": id, "source": source, "delta": delta, "balance_after": balanceAfter, "reason": reason, "created_at": createdAt})
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"balance": balance, "transactions": items})
}

func (s *Server) storeProducts(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	rows, err := s.db.QueryContext(r.Context(), `
		SELECT p.id, p.name, p.description, p.emoji, p.points, p.color,
		       COUNT(o.id) FILTER (WHERE o.status IN ('claimed', 'completed')) AS redeemed_count
		FROM store_products p
		LEFT JOIN store_orders o ON o.product_id = p.id
		WHERE p.active = true
		GROUP BY p.id, p.name, p.description, p.emoji, p.points, p.color
		ORDER BY redeemed_count DESC, p.points ASC, p.id ASC`)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()
	items := make([]map[string]any, 0)
	for rows.Next() {
		var id, name, description, emoji string
		var points int64
		var color int
		var redeemedCount int64
		if err := rows.Scan(&id, &name, &description, &emoji, &points, &color, &redeemedCount); err != nil {
			writeInternalError(w, r, err)
			return
		}
		items = append(items, map[string]any{
			"id":             id,
			"name":           name,
			"description":    description,
			"emoji":          emoji,
			"points":         points,
			"color":          color,
			"image_url":      storeProductImageURL(id),
			"redeemed_count": redeemedCount,
		})
	}
	if err := rows.Err(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (s *Server) storeOrders(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	rows, err := s.db.QueryContext(r.Context(), `SELECT o.id, o.product_id, p.name, o.points, o.status, o.created_at, o.review_reason, o.reviewed_at FROM store_orders o JOIN store_products p ON p.id = o.product_id WHERE o.user_id = $1 ORDER BY o.created_at DESC, o.id DESC LIMIT 50`, user.ID)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()
	items := make([]map[string]any, 0)
	for rows.Next() {
		var id, productID, name, status, reviewReason string
		var points int64
		var createdAt time.Time
		var reviewedAt sql.NullTime
		if err := rows.Scan(&id, &productID, &name, &points, &status, &createdAt, &reviewReason, &reviewedAt); err != nil {
			writeInternalError(w, r, err)
			return
		}
		item := map[string]any{"id": id, "product_id": productID, "product_name": name, "points": points, "status": status, "created_at": createdAt, "review_reason": reviewReason}
		if reviewedAt.Valid {
			item["reviewed_at"] = reviewedAt.Time
		}
		items = append(items, item)
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (s *Server) createStoreOrder(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.requireRegisteredUser(w, r)
	if !ok {
		return
	}
	idempotencyKey := strings.TrimSpace(r.Header.Get("Idempotency-Key"))
	if idempotencyKey == "" {
		writeAuthError(w, r, ErrIdempotencyKeyRequired)
		return
	}
	var input struct {
		ProductID string `json:"product_id"`
	}
	if err := decodeJSON(r, &input); err != nil || strings.TrimSpace(input.ProductID) == "" {
		writeAuthError(w, r, ErrInvalidPost)
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	var balance int64
	if err := tx.QueryRowContext(r.Context(), `SELECT points_balance FROM users WHERE id = $1 FOR UPDATE`, user.ID).Scan(&balance); err != nil {
		writeInternalError(w, r, err)
		return
	}
	var existingOrderID, existingProductID, existingStatus string
	var existingPoints int64
	err = tx.QueryRowContext(r.Context(), `SELECT id, product_id, points, status FROM store_orders WHERE user_id = $1 AND idempotency_key = $2`, user.ID, idempotencyKey).Scan(&existingOrderID, &existingProductID, &existingPoints, &existingStatus)
	if err == nil {
		if err := tx.Commit(); err != nil {
			writeInternalError(w, r, err)
			return
		}
		httpserver.WriteJSON(w, http.StatusOK, map[string]any{"id": existingOrderID, "product_id": existingProductID, "points": existingPoints, "balance": balance, "status": existingStatus})
		return
	}
	if !errors.Is(err, sql.ErrNoRows) {
		writeInternalError(w, r, err)
		return
	}
	var pendingOrderID string
	err = tx.QueryRowContext(r.Context(), `
		SELECT id
		FROM store_orders
		WHERE user_id = $1 AND status = 'pending_review'
		LIMIT 1`, user.ID).Scan(&pendingOrderID)
	if err == nil {
		writeAuthError(w, r, ErrStoreOrderReviewPending)
		return
	}
	if !errors.Is(err, sql.ErrNoRows) {
		writeInternalError(w, r, err)
		return
	}
	var productName string
	var points int64
	if err := tx.QueryRowContext(r.Context(), `SELECT name, points FROM store_products WHERE id = $1 AND active = true FOR UPDATE`, input.ProductID).Scan(&productName, &points); err == sql.ErrNoRows {
		writeAuthError(w, r, ErrInvalidPost)
		return
	} else if err != nil {
		writeInternalError(w, r, err)
		return
	}
	var reserved int64
	if err := tx.QueryRowContext(r.Context(), `
		SELECT COALESCE(SUM(points), 0)
		FROM store_orders
		WHERE user_id = $1 AND status = 'pending_review'`, user.ID).Scan(&reserved); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if balance-reserved < points {
		writeAuthError(w, r, ErrInsufficientPoints)
		return
	}
	orderID := newPostID()
	if _, err := tx.ExecContext(r.Context(), `INSERT INTO store_orders (id, user_id, product_id, points, status, idempotency_key, balance_at_submit) VALUES ($1, $2, $3, $4, 'pending_review', $5, $6)`, orderID, user.ID, input.ProductID, points, idempotencyKey, balance); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusCreated, map[string]any{"id": orderID, "product_id": input.ProductID, "points": points, "balance": balance, "status": "pending_review"})
}

func windowOrDefault(value, fallback string) string {
	if value == "" {
		return fallback
	}
	return value
}
