package api

import (
	"database/sql"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

type pollInput struct {
	Question      string     `json:"question"`
	Options       []string   `json:"options"`
	AllowMultiple bool       `json:"allow_multiple"`
	EndsAt        *time.Time `json:"ends_at"`
}

type marketInput struct {
	Price     float64 `json:"price"`
	Currency  string  `json:"currency"`
	Condition string  `json:"condition"`
	Delivery  string  `json:"delivery"`
}

func (s *Server) createPoll(w http.ResponseWriter, r *http.Request, postID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	var input pollInput
	if err := decodeJSON(r, &input); err != nil || strings.TrimSpace(input.Question) == "" || len(input.Options) < 2 || len(input.Options) > 10 {
		writeAuthError(w, r, ErrInvalidPost)
		return
	}
	for index := range input.Options {
		input.Options[index] = strings.TrimSpace(input.Options[index])
		if input.Options[index] == "" || len([]rune(input.Options[index])) > 200 {
			writeAuthError(w, r, ErrInvalidPost)
			return
		}
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
	pollID := newPostID()
	if _, err := tx.ExecContext(r.Context(), `INSERT INTO polls (id, post_id, question, allow_multiple, ends_at) VALUES ($1, $2, $3, $4, $5)`, pollID, postID, strings.TrimSpace(input.Question), input.AllowMultiple, input.EndsAt); err != nil {
		writeInternalError(w, r, err)
		return
	}
	for index, label := range input.Options {
		if _, err := tx.ExecContext(r.Context(), `INSERT INTO poll_options (id, poll_id, label, sort_order) VALUES ($1, $2, $3, $4)`, newPostID(), pollID, label, index); err != nil {
			writeInternalError(w, r, err)
			return
		}
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
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"id": pollID, "post_id": postID, "question": question, "allow_multiple": allowMultiple, "ends_at": nullableTime(endsAt), "options": options})
}

func (s *Server) votePoll(w http.ResponseWriter, r *http.Request, pollID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
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

func (s *Server) createMarketItem(w http.ResponseWriter, r *http.Request, postID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	var input marketInput
	if err := decodeJSON(r, &input); err != nil || input.Price < 0 || strings.TrimSpace(input.Condition) == "" || len([]rune(input.Condition)) > 100 {
		writeAuthError(w, r, ErrInvalidPost)
		return
	}
	if input.Currency == "" {
		input.Currency = "CNY"
	}
	var existing string
	err := s.db.QueryRowContext(r.Context(), `SELECT id FROM posts WHERE id = $1 AND author_id = $2 AND type = 'market' AND deleted_at IS NULL`, postID, user.ID).Scan(&existing)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrPostNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	itemID := newPostID()
	if _, err := s.db.ExecContext(r.Context(), `INSERT INTO market_items (id, post_id, seller_id, price, currency, item_condition, delivery) VALUES ($1, $2, $3, $4, $5, $6, $7)`, itemID, postID, user.ID, input.Price, input.Currency, input.Condition, strings.TrimSpace(input.Delivery)); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusCreated, map[string]any{"id": itemID, "post_id": postID, "seller_id": user.ID, "price": input.Price, "currency": input.Currency, "condition": input.Condition, "sold": false, "delivery": input.Delivery})
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
	rows, err := s.db.QueryContext(r.Context(), `SELECT id, title, community_id, (like_count * 3 + comment_count * 4 + bookmark_count * 2 + view_count * 0.1) / (1 + EXTRACT(EPOCH FROM (now() - published_at)) / 3600) AS score FROM posts WHERE publication_status = 'published' AND moderation_status = 'normal' AND deleted_at IS NULL AND published_at >= now() - $1::interval ORDER BY score DESC, id DESC LIMIT $2`, interval, limit)
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

func windowOrDefault(value, fallback string) string {
	if value == "" {
		return fallback
	}
	return value
}
