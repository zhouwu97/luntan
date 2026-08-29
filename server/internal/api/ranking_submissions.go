package api

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

var rankingToySubmissionCategories = map[string]struct{}{
	"cup":        {},
	"small_hip":  {},
	"large_hip":  {},
	"half_body":  {},
	"lubricant":  {},
}

func newRankingToyID() string {
	var raw [16]byte
	if _, err := rand.Read(raw[:]); err != nil {
		return "toy_fallback"
	}
	return "toy_" + hex.EncodeToString(raw[:])
}

// 与导入任务共用同一把名次锁：审核通过写入新 rank、超管重排 rank 都必须
// 与 ranking_toys 导入互斥，否则并发下 rank 会出现重复或跳号。
const rankingToyRankLock = `SELECT pg_advisory_xact_lock(hashtext('luntan:ranking_toys_rank'))`

func (s *Server) createRankingToySubmission(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.requireRegisteredUser(w, r)
	if !ok {
		return
	}
	var input struct {
		Name         string `json:"name"`
		Category     string `json:"category"`
		Merchant     string `json:"merchant"`
		ReleaseYear  *int   `json:"release_year"`
		Description  string `json:"description"`
		CoverMediaID string `json:"cover_media_id"`
	}
	if err := decodeJSON(r, &input); err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_BODY", Message: "请求体格式错误"})
		return
	}
	input.Name = strings.TrimSpace(input.Name)
	input.Category = strings.TrimSpace(input.Category)
	input.Merchant = strings.TrimSpace(input.Merchant)
	input.Description = strings.TrimSpace(input.Description)
	input.CoverMediaID = strings.TrimSpace(input.CoverMediaID)

	if runes := len([]rune(input.Name)); runes < 1 || runes > 50 {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_SUBMISSION_NAME", Message: "玩具名称必须为 1 到 50 个字符"})
		return
	}
	if _, ok := rankingToySubmissionCategories[input.Category]; !ok {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_SUBMISSION_CATEGORY", Message: "品类无效"})
		return
	}
	if runes := len([]rune(input.Merchant)); runes > 60 {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_SUBMISSION_MERCHANT", Message: "品牌不能超过 60 个字符"})
		return
	}
	if runes := len([]rune(input.Description)); runes > 2000 {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_SUBMISSION_DESCRIPTION", Message: "介绍不能超过 2000 个字符"})
		return
	}
	if input.ReleaseYear != nil && (*input.ReleaseYear < 1970 || *input.ReleaseYear > 2100) {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_SUBMISSION_YEAR", Message: "年份必须在 1970 到 2100 之间"})
		return
	}
	var pendingCount int
	if err := s.db.QueryRowContext(r.Context(), `SELECT count(*) FROM ranking_toy_submissions WHERE submitter_id = $1 AND status = 'pending'`, user.ID).Scan(&pendingCount); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if pendingCount >= 5 {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "SUBMISSION_LIMIT", Message: "待审核投稿已达上限，请等待审核结果后再提交"})
		return
	}
	if input.CoverMediaID != "" {
		var mediaID string
		err := s.db.QueryRowContext(r.Context(), `SELECT id FROM media_assets WHERE id = $1 AND owner_id = $2 AND status = 'ready' AND deleted_at IS NULL`, input.CoverMediaID, user.ID).Scan(&mediaID)
		if errors.Is(err, sql.ErrNoRows) {
			httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_SUBMISSION_COVER", Message: "封面不存在或无权使用"})
			return
		}
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	id := newRankingToyID()
	if _, err := s.db.ExecContext(r.Context(), `
		INSERT INTO ranking_toy_submissions (id, submitter_id, name, category, merchant, release_year, description, cover_media_id)
		VALUES ($1, $2, $3, $4, $5, $6, $7, NULLIF($8, ''))`,
		id, user.ID, input.Name, input.Category, input.Merchant, input.ReleaseYear, input.Description, input.CoverMediaID); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusCreated, map[string]any{"id": id, "status": "pending"})
}

func (s *Server) listRankingToySubmissions(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	if _, ok := s.requireAdminRoleManager(w, r); !ok {
		return
	}
	status := strings.TrimSpace(r.URL.Query().Get("status"))
	if status == "" {
		status = "pending"
	}
	if status != "pending" && status != "approved" && status != "rejected" {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_SUBMISSION_STATUS", Message: "status 参数无效"})
		return
	}
	rows, err := s.db.QueryContext(r.Context(), `
		SELECT sub.id, sub.name, sub.category, sub.merchant, sub.release_year, sub.description,
		       COALESCE(cover.object_key, ''), sub.status, sub.review_note, sub.reviewed_at,
		       sub.toy_id, sub.created_at, sub.submitter_id, u.username, COALESCE(up.nickname, u.username)
		FROM ranking_toy_submissions sub
		JOIN users u ON u.id = sub.submitter_id
		LEFT JOIN user_profiles up ON up.user_id = sub.submitter_id
		LEFT JOIN media_assets cover ON cover.id = sub.cover_media_id AND cover.status = 'ready' AND cover.deleted_at IS NULL
		WHERE sub.status = $1
		ORDER BY sub.created_at DESC
		LIMIT 50`, status)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()
	items := make([]map[string]any, 0)
	for rows.Next() {
		var id, name, category, merchant, description, coverKey, itemStatus, submitterID, username, nickname string
		var releaseYear sql.NullInt64
		var reviewNote string
		var reviewedAt sql.NullTime
		var toyID sql.NullString
		var createdAt time.Time
		if err := rows.Scan(&id, &name, &category, &merchant, &releaseYear, &description,
			&coverKey, &itemStatus, &reviewNote, &reviewedAt,
			&toyID, &createdAt, &submitterID, &username, &nickname); err != nil {
			writeInternalError(w, r, err)
			return
		}
		item := map[string]any{
			"id":           id,
			"name":         name,
			"category":     category,
			"merchant":     merchant,
			"release_year": nullableInt(releaseYear),
			"description":  description,
			"cover_url":    mediaURLOrEmpty(coverKey),
			"status":       itemStatus,
			"review_note":  reviewNote,
			"reviewed_at":  nullableTime(reviewedAt),
			"toy_id":       rankingNullableString(toyID),
			"created_at":   createdAt,
			"submitter": map[string]any{
				"id":       submitterID,
				"username": username,
				"nickname": nickname,
			},
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (s *Server) reviewRankingToySubmission(w http.ResponseWriter, r *http.Request, submissionID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	reviewer, ok := s.requireAdminRoleManager(w, r)
	if !ok {
		return
	}
	var input struct {
		Action string `json:"action"`
		Note   string `json:"note"`
	}
	if err := decodeJSON(r, &input); err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_BODY", Message: "请求体格式错误"})
		return
	}
	input.Action = strings.TrimSpace(input.Action)
	input.Note = strings.TrimSpace(input.Note)
	if input.Action != "approve" && input.Action != "reject" {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_REVIEW_ACTION", Message: "action 必须是 approve 或 reject"})
		return
	}

	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	var advisoryLock any
	if err := tx.QueryRowContext(r.Context(), rankingToyRankLock).Scan(&advisoryLock); err != nil {
		writeInternalError(w, r, err)
		return
	}

	newStatus := "rejected"
	if input.Action == "approve" {
		newStatus = "approved"
	}
	var name, category, merchant, description, coverMediaID string
	var releaseYear sql.NullInt64
	// 抢占式流转：仅 pending 可被审核，0 行说明已处理或不存在，天然防双审。
	err = tx.QueryRowContext(r.Context(), `
		UPDATE ranking_toy_submissions
		SET status = $2, review_note = $3, reviewed_by = $4, reviewed_at = now(), updated_at = now()
		WHERE id = $1 AND status = 'pending'
		RETURNING name, category, merchant, COALESCE(release_year, 2026), description, COALESCE(cover_media_id, '')`,
		submissionID, newStatus, input.Note, reviewer.ID).Scan(&name, &category, &merchant, &releaseYear, &description, &coverMediaID)
	if errors.Is(err, sql.ErrNoRows) {
		var existingStatus string
		if statusErr := tx.QueryRowContext(r.Context(), `SELECT status FROM ranking_toy_submissions WHERE id = $1`, submissionID).Scan(&existingStatus); errors.Is(statusErr, sql.ErrNoRows) {
			httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusNotFound, Code: "SUBMISSION_NOT_FOUND", Message: "投稿不存在"})
			return
		} else if statusErr != nil {
			writeInternalError(w, r, statusErr)
			return
		}
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusConflict, Code: "SUBMISSION_ALREADY_REVIEWED", Message: "该提交已被处理"})
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}

	toyID := ""
	if input.Action == "approve" {
		toyID = newRankingToyID()
		if _, err := tx.ExecContext(r.Context(), `
			INSERT INTO ranking_toys (id, rank, name, merchant, release_year, description, category, cover_media_id, asset_key, active)
			VALUES ($1, COALESCE((SELECT MAX(rank) + 1 FROM ranking_toys), 1), $2, $3, $4, $5, $6, NULLIF($7, ''), '', true)`,
			toyID, name, merchant, int(releaseYear.Int64), description, category, coverMediaID); err != nil {
			writeInternalError(w, r, err)
			return
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE ranking_toy_submissions SET toy_id = $2, updated_at = now() WHERE id = $1`, submissionID, toyID); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	if err := appendAdminLogTx(r.Context(), tx, reviewer.ID, "ranking_toy_submission."+input.Action, "ranking_toy_submission", submissionID, input.Note, requestIDFromRequest(r), httpserver.ClientIP(r), map[string]any{
		"name": name, "category": category, "toy_id": toyID,
	}, time.Now().UTC()); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	response := map[string]any{"id": submissionID, "status": newStatus}
	if toyID != "" {
		response["toy_id"] = toyID
	}
	httpserver.WriteJSON(w, http.StatusOK, response)
}

func (s *Server) reorderRankingToys(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	operator, ok := s.requireAdminRoleManager(w, r)
	if !ok {
		return
	}
	var input struct {
		ToyIDs []string `json:"toy_ids"`
	}
	if err := decodeJSON(r, &input); err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_BODY", Message: "请求体格式错误"})
		return
	}

	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	var advisoryLock any
	if err := tx.QueryRowContext(r.Context(), rankingToyRankLock).Scan(&advisoryLock); err != nil {
		writeInternalError(w, r, err)
		return
	}

	rows, err := tx.QueryContext(r.Context(), `SELECT id FROM ranking_toys WHERE active = true`)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()
	existing := make(map[string]struct{})
	var existingCount int
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			writeInternalError(w, r, err)
			return
		}
		existing[id] = struct{}{}
		existingCount++
	}
	if err := rows.Err(); err != nil {
		writeInternalError(w, r, err)
		return
	}

	if len(input.ToyIDs) != existingCount {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusConflict, Code: "RANKING_REORDER_STALE", Message: "榜单有更新，请刷新后重试"})
		return
	}
	seen := make(map[string]struct{}, len(input.ToyIDs))
	for _, id := range input.ToyIDs {
		if _, dup := seen[id]; dup {
			httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusConflict, Code: "RANKING_REORDER_STALE", Message: "榜单有更新，请刷新后重试"})
			return
		}
		if _, ok := existing[id]; !ok {
			httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusConflict, Code: "RANKING_REORDER_STALE", Message: "榜单有更新，请刷新后重试"})
			return
		}
		seen[id] = struct{}{}
	}

	values := make([]string, 0, len(input.ToyIDs))
	args := make([]any, 0, len(input.ToyIDs)*2)
	for i, id := range input.ToyIDs {
		values = append(values, fmt.Sprintf("($%d::text, $%d::integer)", i*2+1, i*2+2))
		args = append(args, id, i+1)
	}
	if len(values) > 0 {
		query := `UPDATE ranking_toys AS t SET rank = v.rank, updated_at = now() FROM (VALUES ` + strings.Join(values, ", ") + `) AS v(id, rank) WHERE t.id = v.id`
		if _, err := tx.ExecContext(r.Context(), query, args...); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	if err := appendAdminLogTx(r.Context(), tx, operator.ID, "ranking_toy.reorder", "system", "ranking_toys", "", requestIDFromRequest(r), httpserver.ClientIP(r), map[string]any{
		"count": len(input.ToyIDs),
	}, time.Now().UTC()); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"success": true, "updated": len(input.ToyIDs)})
}
