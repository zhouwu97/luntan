package api

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"math"
	"net/http"
	"strings"
	"time"

	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

var (
	ErrRankingToyNotFound     = errors.New("ranking toy not found")
	ErrInvalidRankingRating   = errors.New("invalid ranking rating")
	ErrInvalidRankingComment  = errors.New("invalid ranking comment")
	ErrRankingCommentNotFound = errors.New("ranking comment not found")
)

type rankingToyRecord struct {
	ID               string
	Rank             int
	Name             string
	Merchant         string
	ReleaseYear      int
	Description      string
	Tags             []string
	AssetKey         string
	WantCount        int64
	RatingTotalCenti int64
	RatingCount      int64
	Wanted           bool
	Owned            bool
	Rating           sql.NullInt64
}

type rankingToyScanner interface {
	Scan(dest ...any) error
}

type rankingToyComment struct {
	ID             string
	AuthorID       string
	Username       string
	Nickname       string
	Level          int
	Content        string
	LikeCount      int64
	ViewerHasLiked bool
	CreatedAt      time.Time
	RootID         sql.NullString
	ParentID       sql.NullString
	ReplyToUserID  sql.NullString
	ReplyCount     int64
}

func (s *Server) listRankingToys(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	viewerID := ""
	if viewer, ok := s.optionalAuthenticatedUser(r.Context(), r); ok {
		viewerID = viewer.ID
	}
	rows, err := s.db.QueryContext(r.Context(), `
		SELECT t.id, t.rank, t.name, t.merchant, t.release_year, t.description,
		       array_to_json(t.tags), t.asset_key, t.want_count,
		       t.rating_total_centi, t.rating_count,
		       COALESCE(us.wanted, false), COALESCE(us.owned, false), us.rating
		FROM ranking_toys t
		LEFT JOIN ranking_toy_user_states us
		  ON us.toy_id = t.id AND us.user_id = $1
		WHERE t.active = true
		ORDER BY t.rank ASC`, viewerID)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()
	items := make([]map[string]any, 0)
	for rows.Next() {
		item, scanErr := scanRankingToy(rows)
		if scanErr != nil {
			writeInternalError(w, r, scanErr)
			return
		}
		items = append(items, item.response())
	}
	if err := rows.Err(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (s *Server) getRankingToy(w http.ResponseWriter, r *http.Request, toyID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	viewerID := ""
	if viewer, ok := s.optionalAuthenticatedUser(r.Context(), r); ok {
		viewerID = viewer.ID
	}
	item, err := s.loadRankingToy(r.Context(), toyID, viewerID)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrRankingToyNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	sort := r.URL.Query().Get("comment_sort")
	if sort == "" {
		sort = "weight"
	}
	if sort != "weight" && sort != "latest" {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_COMMENT_SORT", Message: "评论排序参数无效"})
		return
	}
	comments, err := s.listRankingToyComments(r, toyID, viewerID, sort)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	response := item.response()
	response["comments"] = comments
	response["comment_sort"] = sort
	httpserver.WriteJSON(w, http.StatusOK, response)
}

func (s *Server) loadRankingToy(ctx context.Context, toyID, viewerID string) (rankingToyRecord, error) {
	return scanRankingToy(s.db.QueryRowContext(ctx, `
		SELECT t.id, t.rank, t.name, t.merchant, t.release_year, t.description,
		       array_to_json(t.tags), t.asset_key, t.want_count,
		       t.rating_total_centi, t.rating_count,
		       COALESCE(us.wanted, false), COALESCE(us.owned, false), us.rating
		FROM ranking_toys t
		LEFT JOIN ranking_toy_user_states us
		  ON us.toy_id = t.id AND us.user_id = $2
		WHERE t.id = $1 AND t.active = true`, toyID, viewerID))
}

func scanRankingToy(scanner rankingToyScanner) (rankingToyRecord, error) {
	var item rankingToyRecord
	var tagsRaw []byte
	if err := scanner.Scan(
		&item.ID,
		&item.Rank,
		&item.Name,
		&item.Merchant,
		&item.ReleaseYear,
		&item.Description,
		&tagsRaw,
		&item.AssetKey,
		&item.WantCount,
		&item.RatingTotalCenti,
		&item.RatingCount,
		&item.Wanted,
		&item.Owned,
		&item.Rating,
	); err != nil {
		return rankingToyRecord{}, err
	}
	if len(tagsRaw) > 0 {
		if err := json.Unmarshal(tagsRaw, &item.Tags); err != nil {
			return rankingToyRecord{}, err
		}
	}
	if item.Tags == nil {
		item.Tags = []string{}
	}
	return item, nil
}

func (item rankingToyRecord) response() map[string]any {
	return map[string]any{
		"id":           item.ID,
		"rank":         item.Rank,
		"name":         item.Name,
		"merchant":     item.Merchant,
		"release_year": item.ReleaseYear,
		"description":  item.Description,
		"tags":         item.Tags,
		"asset_key":    item.AssetKey,
		"want_count":   item.WantCount,
		"rating_count": item.RatingCount,
		"score":        item.score(),
		"viewer_state": map[string]any{
			"wanted": item.Wanted,
			"owned":  item.Owned,
			"rating": nullableInt(item.Rating),
		},
	}
}

func (item rankingToyRecord) score() float64 {
	if item.RatingCount == 0 {
		return 0
	}
	return math.Round(float64(item.RatingTotalCenti)/float64(item.RatingCount)/10) / 10
}

func nullableInt(value sql.NullInt64) any {
	if !value.Valid {
		return nil
	}
	return value.Int64
}

func (s *Server) listRankingToyComments(r *http.Request, toyID, viewerID, sort string) ([]map[string]any, error) {
	orderBy := "c.like_count DESC, c.created_at DESC, c.id DESC"
	if sort == "latest" {
		orderBy = "c.created_at DESC, c.id DESC"
	}
	query := `SELECT c.id, c.author_id, u.username, COALESCE(up.nickname, u.username),
	                 COALESCE(up.level, 1), c.content, c.like_count,
	                 EXISTS (SELECT 1 FROM ranking_toy_comment_likes l WHERE l.comment_id = c.id AND l.user_id = $2),
	                 c.created_at, c.root_id, c.parent_id, c.reply_to_user_id, c.reply_count
	          FROM ranking_toy_comments c
	          JOIN users u ON u.id = c.author_id
	          LEFT JOIN user_profiles up ON up.user_id = c.author_id
	          WHERE c.toy_id = $1 AND c.deleted_at IS NULL
	          ORDER BY ` + orderBy + ` LIMIT 100`
	rows, err := s.db.QueryContext(r.Context(), query, toyID, viewerID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := make([]map[string]any, 0)
	for rows.Next() {
		var item rankingToyComment
		if err := rows.Scan(
			&item.ID,
			&item.AuthorID,
			&item.Username,
			&item.Nickname,
			&item.Level,
			&item.Content,
			&item.LikeCount,
			&item.ViewerHasLiked,
			&item.CreatedAt,
			&item.RootID,
			&item.ParentID,
			&item.ReplyToUserID,
			&item.ReplyCount,
		); err != nil {
			return nil, err
		}
		items = append(items, item.response())
	}
	return items, rows.Err()
}

func (item rankingToyComment) response() map[string]any {
	return map[string]any{
		"id":               item.ID,
		"content":          item.Content,
		"like_count":       item.LikeCount,
		"root_id":          rankingNullableString(item.RootID),
		"parent_id":        rankingNullableString(item.ParentID),
		"reply_to_user_id": rankingNullableString(item.ReplyToUserID),
		"reply_count":      item.ReplyCount,
		"created_at":       item.CreatedAt,
		"author": map[string]any{
			"id":       item.AuthorID,
			"username": item.Username,
			"nickname": item.Nickname,
			"level":    item.Level,
		},
		"viewer_state": map[string]any{"has_liked": item.ViewerHasLiked},
	}
}

func rankingNullableString(value sql.NullString) any {
	if !value.Valid || value.String == "" {
		return nil
	}
	return value.String
}

func (s *Server) setRankingToyFlag(w http.ResponseWriter, r *http.Request, toyID, field string, active bool) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if field != "wanted" && field != "owned" {
		writeInternalError(w, r, ErrInvalidRankingComment)
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	if err := lockRankingToy(r, tx, toyID); err != nil {
		writeAuthError(w, r, err)
		return
	}
	previous := false
	stateErr := tx.QueryRowContext(r.Context(), `SELECT `+field+` FROM ranking_toy_user_states WHERE toy_id = $1 AND user_id = $2`, toyID, user.ID).Scan(&previous)
	if errors.Is(stateErr, sql.ErrNoRows) {
		stateErr = nil
	}
	if stateErr != nil {
		writeInternalError(w, r, stateErr)
		return
	}
	query := `INSERT INTO ranking_toy_user_states (toy_id, user_id, ` + field + `)
		VALUES ($1, $2, $3)
		ON CONFLICT (toy_id, user_id) DO UPDATE SET ` + field + ` = EXCLUDED.` + field + `, updated_at = now()`
	if _, err := tx.ExecContext(r.Context(), query, toyID, user.ID, active); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if field == "wanted" && previous != active {
		delta := 1
		if !active {
			delta = -1
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE ranking_toys SET want_count = GREATEST(want_count + $2, 0), updated_at = now() WHERE id = $1`, toyID, delta); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	var count int64
	countQuery := `SELECT count(*) FROM ranking_toy_user_states WHERE toy_id = $1 AND ` + field + ` = true`
	if field == "wanted" {
		countQuery = `SELECT want_count FROM ranking_toys WHERE id = $1`
	}
	if err := tx.QueryRowContext(r.Context(), countQuery, toyID).Scan(&count); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"active": active, "count": count})
}

func lockRankingToy(r *http.Request, tx *sql.Tx, toyID string) error {
	var id string
	err := tx.QueryRowContext(r.Context(), `SELECT id FROM ranking_toys WHERE id = $1 AND active = true FOR UPDATE`, toyID).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrRankingToyNotFound
	}
	return err
}

func (s *Server) rateRankingToy(w http.ResponseWriter, r *http.Request, toyID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	var input struct {
		Score int `json:"score"`
	}
	if err := decodeJSON(r, &input); err != nil || input.Score < 1 || input.Score > 10 {
		writeAuthError(w, r, ErrInvalidRankingRating)
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	if err := lockRankingToy(r, tx, toyID); err != nil {
		writeAuthError(w, r, err)
		return
	}
	var previous sql.NullInt64
	err = tx.QueryRowContext(r.Context(), `SELECT rating FROM ranking_toy_user_states WHERE toy_id = $1 AND user_id = $2 FOR UPDATE`, toyID, user.ID).Scan(&previous)
	if errors.Is(err, sql.ErrNoRows) {
		if _, err := tx.ExecContext(r.Context(), `INSERT INTO ranking_toy_user_states (toy_id, user_id, rating) VALUES ($1, $2, $3)`, toyID, user.ID, input.Score); err != nil {
			writeInternalError(w, r, err)
			return
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE ranking_toys SET rating_total_centi = rating_total_centi + $2, rating_count = rating_count + 1, updated_at = now() WHERE id = $1`, toyID, input.Score*100); err != nil {
			writeInternalError(w, r, err)
			return
		}
	} else if err != nil {
		writeInternalError(w, r, err)
		return
	} else {
		if _, err := tx.ExecContext(r.Context(), `UPDATE ranking_toy_user_states SET rating = $3, updated_at = now() WHERE toy_id = $1 AND user_id = $2`, toyID, user.ID, input.Score); err != nil {
			writeInternalError(w, r, err)
			return
		}
		previousValue := int(previous.Int64)
		if !previous.Valid {
			if _, err := tx.ExecContext(r.Context(), `UPDATE ranking_toys SET rating_total_centi = rating_total_centi + $2, rating_count = rating_count + 1, updated_at = now() WHERE id = $1`, toyID, input.Score*100); err != nil {
				writeInternalError(w, r, err)
				return
			}
		} else if _, err := tx.ExecContext(r.Context(), `UPDATE ranking_toys SET rating_total_centi = GREATEST(rating_total_centi + $2, 0), updated_at = now() WHERE id = $1`, toyID, (input.Score-previousValue)*100); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	item, err := s.loadRankingToy(r.Context(), toyID, user.ID)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, item.response())
}

func (s *Server) createRankingToyComment(w http.ResponseWriter, r *http.Request, toyID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	idempotencyKey := strings.TrimSpace(r.Header.Get("Idempotency-Key"))
	if idempotencyKey == "" || len(idempotencyKey) > 128 {
		writeAuthError(w, r, ErrIdempotencyKeyRequired)
		return
	}
	var input struct {
		Content       string `json:"content"`
		ParentID      string `json:"parent_id"`
		ReplyToUserID string `json:"reply_to_user_id"`
	}
	if err := decodeJSON(r, &input); err != nil {
		writeAuthError(w, r, ErrInvalidRankingComment)
		return
	}
	input.Content = strings.TrimSpace(input.Content)
	if input.Content == "" || len([]rune(input.Content)) > 5000 {
		writeAuthError(w, r, ErrInvalidRankingComment)
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	if err := lockRankingToy(r, tx, toyID); err != nil {
		writeAuthError(w, r, err)
		return
	}
	parentID := strings.TrimSpace(input.ParentID)
	replyToUserID := strings.TrimSpace(input.ReplyToUserID)
	rootID := ""
	if parentID != "" {
		var parentToyID string
		var parentRootID sql.NullString
		err := tx.QueryRowContext(r.Context(), `
			SELECT toy_id, root_id FROM ranking_toy_comments
			WHERE id = $1 AND deleted_at IS NULL FOR UPDATE`, parentID).Scan(&parentToyID, &parentRootID)
		if errors.Is(err, sql.ErrNoRows) {
			writeAuthError(w, r, ErrRankingCommentNotFound)
			return
		}
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
		if parentToyID != toyID {
			writeAuthError(w, r, ErrInvalidRankingComment)
			return
		}
		if parentRootID.Valid && parentRootID.String != "" {
			rootID = parentRootID.String
		} else {
			rootID = parentID
		}
	}
	commentID := newPostID()
	if rootID == "" {
		rootID = commentID
	}
	var insertedID string
	created := true
	err = tx.QueryRowContext(r.Context(), `
		INSERT INTO ranking_toy_comments (id, toy_id, author_id, content, idempotency_key, root_id, parent_id, reply_to_user_id)
		VALUES ($1, $2, $3, $4, $5, $6, NULLIF($7, ''), NULLIF($8, ''))
		ON CONFLICT (author_id, idempotency_key) WHERE idempotency_key IS NOT NULL DO NOTHING
		RETURNING id`, commentID, toyID, user.ID, input.Content, idempotencyKey, rootID, parentID, replyToUserID).Scan(&insertedID)
	if errors.Is(err, sql.ErrNoRows) {
		created = false
		if err := tx.QueryRowContext(r.Context(), `SELECT id FROM ranking_toy_comments WHERE author_id = $1 AND idempotency_key = $2`, user.ID, idempotencyKey).Scan(&insertedID); err != nil {
			writeInternalError(w, r, err)
			return
		}
	} else if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if created && parentID != "" {
		if _, err := tx.ExecContext(r.Context(), `UPDATE ranking_toy_comments SET reply_count = reply_count + 1, updated_at = now() WHERE id = $1`, parentID); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	comment, err := s.loadRankingToyComment(r, insertedID, user.ID)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrRankingCommentNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusCreated, comment.response())
}

func (s *Server) loadRankingToyComment(r *http.Request, commentID, viewerID string) (rankingToyComment, error) {
	var item rankingToyComment
	err := s.db.QueryRowContext(r.Context(), `
		SELECT c.id, c.author_id, u.username, COALESCE(up.nickname, u.username),
		       COALESCE(up.level, 1), c.content, c.like_count,
		       EXISTS (SELECT 1 FROM ranking_toy_comment_likes l WHERE l.comment_id = c.id AND l.user_id = $2),
		       c.created_at, c.root_id, c.parent_id, c.reply_to_user_id, c.reply_count
		FROM ranking_toy_comments c
		JOIN users u ON u.id = c.author_id
		LEFT JOIN user_profiles up ON up.user_id = c.author_id
		WHERE c.id = $1 AND c.deleted_at IS NULL`, commentID, viewerID).Scan(
		&item.ID, &item.AuthorID, &item.Username, &item.Nickname, &item.Level,
		&item.Content, &item.LikeCount, &item.ViewerHasLiked, &item.CreatedAt,
		&item.RootID, &item.ParentID, &item.ReplyToUserID, &item.ReplyCount,
	)
	return item, err
}

func (s *Server) toggleRankingToyCommentLike(w http.ResponseWriter, r *http.Request, commentID string, active bool) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	var existingID string
	if err := tx.QueryRowContext(r.Context(), `SELECT id FROM ranking_toy_comments WHERE id = $1 AND deleted_at IS NULL FOR UPDATE`, commentID).Scan(&existingID); errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrRankingCommentNotFound)
		return
	} else if err != nil {
		writeInternalError(w, r, err)
		return
	}
	changed := false
	if active {
		result, err := tx.ExecContext(r.Context(), `INSERT INTO ranking_toy_comment_likes (comment_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`, commentID, user.ID)
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
		affected, err := result.RowsAffected()
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
		changed = affected > 0
	} else {
		result, err := tx.ExecContext(r.Context(), `DELETE FROM ranking_toy_comment_likes WHERE comment_id = $1 AND user_id = $2`, commentID, user.ID)
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
		affected, err := result.RowsAffected()
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
		changed = affected > 0
	}
	if changed {
		operator := "+ 1"
		if !active {
			operator = "- 1"
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE ranking_toy_comments SET like_count = GREATEST(like_count `+operator+`, 0), updated_at = now() WHERE id = $1`, commentID); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	var count int64
	if err := tx.QueryRowContext(r.Context(), `SELECT like_count FROM ranking_toy_comments WHERE id = $1`, commentID).Scan(&count); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"active": active, "like_count": count})
}
