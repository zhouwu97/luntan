package api

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

var (
	ErrBookmarkFolderNotFound    = errors.New("bookmark folder not found")
	ErrDefaultBookmarkFolder     = errors.New("default bookmark folder cannot be changed")
	ErrInvalidBookmarkFolderName = errors.New("invalid bookmark folder name")
	ErrBookmarkFolderNameTaken   = errors.New("bookmark folder name already exists")
)

const maxBookmarkFolderNameLength = 40

type bookmarkFolderInput struct {
	Name      *string `json:"name"`
	SortOrder *int    `json:"sort_order"`
}

type bookmarkFolderIDsInput struct {
	FolderIDs []string `json:"folder_ids"`
}

func (s *Server) listBookmarkFolders(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if err := ensureDefaultBookmarkFolder(r.Context(), s.db, user.ID); err != nil {
		writeInternalError(w, r, err)
		return
	}
	limit, err := parseLimit(r.URL.Query().Get("limit"))
	if err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_LIMIT", Message: "limit 必须是 1 到 50 之间的整数"})
		return
	}

	args := []any{user.ID}
	where := "f.user_id = $1"
	if rawCursor := strings.TrimSpace(r.URL.Query().Get("cursor")); rawCursor != "" {
		sortOrder, createdAt, id, decodeErr := decodeBookmarkFolderCursor(rawCursor)
		if decodeErr != nil {
			httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_CURSOR", Message: "cursor 无效"})
			return
		}
		where += " AND (f.sort_order, f.created_at, f.id) > ($2, $3, $4)"
		args = append(args, sortOrder, createdAt, id)
	}
	args = append(args, limit+1)
	rows, err := s.db.QueryContext(r.Context(), fmt.Sprintf(`
		SELECT f.id, f.name, f.is_default, f.sort_order, f.created_at, f.updated_at,
		       COUNT(fi.post_id)
		FROM bookmark_folders f
		LEFT JOIN bookmark_folder_items fi ON fi.folder_id = f.id
		WHERE %s
		GROUP BY f.id
		ORDER BY f.sort_order ASC, f.created_at ASC, f.id ASC
		LIMIT $%d`, where, len(args)), args...)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()
	items := make([]map[string]any, 0, limit+1)
	for rows.Next() {
		var id, name string
		var isDefault bool
		var sortOrder int
		var createdAt, updatedAt time.Time
		var count int64
		if err := rows.Scan(&id, &name, &isDefault, &sortOrder, &createdAt, &updatedAt, &count); err != nil {
			writeInternalError(w, r, err)
			return
		}
		items = append(items, bookmarkFolderJSON(id, name, isDefault, sortOrder, count, createdAt, updatedAt))
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
		last := items[len(items)-1]
		nextCursor = encodeBookmarkFolderCursor(last["sort_order"].(int), last["created_at"].(time.Time), last["id"].(string))
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items, "next_cursor": nextCursor, "has_more": hasMore})
}

func (s *Server) createBookmarkFolder(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.requireRegisteredUser(w, r)
	if !ok {
		return
	}
	var input bookmarkFolderInput
	if err := decodeJSON(r, &input); err != nil {
		writeAuthError(w, r, ErrInvalidBookmarkFolderName)
		return
	}
	if input.Name == nil {
		writeAuthError(w, r, ErrInvalidBookmarkFolderName)
		return
	}
	name, valid := normalizeBookmarkFolderName(*input.Name)
	if !valid {
		writeAuthError(w, r, ErrInvalidBookmarkFolderName)
		return
	}
	if err := ensureDefaultBookmarkFolder(r.Context(), s.db, user.ID); err != nil {
		writeInternalError(w, r, err)
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	idempotencyKey := strings.TrimSpace(r.Header.Get("Idempotency-Key"))
	if len(idempotencyKey) > 128 {
		writeAuthError(w, r, ErrInvalidBookmarkFolderName)
		return
	}
	if idempotencyKey != "" {
		var existingID, existingName string
		var existingDefault bool
		var existingSortOrder int
		var existingCreatedAt, existingUpdatedAt time.Time
		var existingCount int64
		err := tx.QueryRowContext(r.Context(), `
			SELECT f.id, f.name, f.is_default, f.sort_order, f.created_at, f.updated_at,
			       COUNT(fi.post_id)
			FROM bookmark_folders f
			LEFT JOIN bookmark_folder_items fi ON fi.folder_id = f.id
			WHERE f.user_id = $1 AND f.idempotency_key = $2
			GROUP BY f.id`, user.ID, idempotencyKey).
			Scan(&existingID, &existingName, &existingDefault, &existingSortOrder, &existingCreatedAt, &existingUpdatedAt, &existingCount)
		if err == nil {
			if err := tx.Commit(); err != nil {
				writeInternalError(w, r, err)
				return
			}
			httpserver.WriteJSON(w, http.StatusOK, bookmarkFolderJSON(existingID, existingName, existingDefault, existingSortOrder, existingCount, existingCreatedAt, existingUpdatedAt))
			return
		}
		if !errors.Is(err, sql.ErrNoRows) {
			writeInternalError(w, r, err)
			return
		}
	}
	var existingID string
	err = tx.QueryRowContext(r.Context(), `SELECT id FROM bookmark_folders WHERE user_id = $1 AND lower(name) = lower($2)`, user.ID, name).Scan(&existingID)
	if err == nil {
		writeAuthError(w, r, ErrBookmarkFolderNameTaken)
		return
	}
	if !errors.Is(err, sql.ErrNoRows) {
		writeInternalError(w, r, err)
		return
	}
	var maxSort sql.NullInt64
	if err := tx.QueryRowContext(r.Context(), `SELECT MAX(sort_order) FROM bookmark_folders WHERE user_id = $1`, user.ID).Scan(&maxSort); err != nil {
		writeInternalError(w, r, err)
		return
	}
	sortOrder := 1
	if maxSort.Valid {
		sortOrder = int(maxSort.Int64) + 1
	}
	now := time.Now().UTC()
	id := newPostID()
	var idempotencyValue any
	if idempotencyKey != "" {
		idempotencyValue = idempotencyKey
	}
	var insertedID string
	err = tx.QueryRowContext(r.Context(), `INSERT INTO bookmark_folders (id, user_id, name, is_default, sort_order, idempotency_key, created_at, updated_at) VALUES ($1, $2, $3, false, $4, $5, $6, $6) ON CONFLICT (user_id, idempotency_key) WHERE idempotency_key IS NOT NULL DO NOTHING RETURNING id`, id, user.ID, name, sortOrder, idempotencyValue, now).Scan(&insertedID)
	if errors.Is(err, sql.ErrNoRows) && idempotencyKey != "" {
		// 另一个相同请求已经提交；ON CONFLICT DO NOTHING 不会使事务进入 aborted，
		// 可以在当前事务内读取已提交的收藏夹并返回幂等结果。
		var existingID, existingName string
		var existingDefault bool
		var existingSortOrder int
		var existingCreatedAt, existingUpdatedAt time.Time
		var existingCount int64
		err = tx.QueryRowContext(r.Context(), `
			SELECT f.id, f.name, f.is_default, f.sort_order, f.created_at, f.updated_at,
			       COUNT(fi.post_id)
			FROM bookmark_folders f
			LEFT JOIN bookmark_folder_items fi ON fi.folder_id = f.id
			WHERE f.user_id = $1 AND f.idempotency_key = $2
			GROUP BY f.id`, user.ID, idempotencyKey).
			Scan(&existingID, &existingName, &existingDefault, &existingSortOrder, &existingCreatedAt, &existingUpdatedAt, &existingCount)
		if err == nil {
			if err := tx.Commit(); err != nil {
				writeInternalError(w, r, err)
				return
			}
			httpserver.WriteJSON(w, http.StatusOK, bookmarkFolderJSON(existingID, existingName, existingDefault, existingSortOrder, existingCount, existingCreatedAt, existingUpdatedAt))
			return
		}
	}
	if err != nil {
		if isUniqueViolation(err) {
			writeAuthError(w, r, ErrBookmarkFolderNameTaken)
			return
		}
		writeInternalError(w, r, err)
		return
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusCreated, bookmarkFolderJSON(id, name, false, sortOrder, 0, now, now))
}

func (s *Server) updateBookmarkFolder(w http.ResponseWriter, r *http.Request, folderID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.requireRegisteredUser(w, r)
	if !ok {
		return
	}
	var input bookmarkFolderInput
	if err := decodeJSON(r, &input); err != nil {
		writeAuthError(w, r, ErrInvalidBookmarkFolderName)
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	var currentName string
	var isDefault bool
	var currentSortOrder int
	if err := tx.QueryRowContext(r.Context(), `SELECT name, is_default, sort_order FROM bookmark_folders WHERE id = $1 AND user_id = $2 FOR UPDATE`, folderID, user.ID).Scan(&currentName, &isDefault, &currentSortOrder); errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrBookmarkFolderNotFound)
		return
	} else if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if isDefault {
		if input.Name != nil {
			writeAuthError(w, r, ErrDefaultBookmarkFolder)
			return
		}
	}
	name := currentName
	if input.Name != nil {
		var valid bool
		name, valid = normalizeBookmarkFolderName(*input.Name)
		if !valid {
			writeAuthError(w, r, ErrInvalidBookmarkFolderName)
			return
		}
	}
	sortOrder := currentSortOrder
	if input.SortOrder != nil {
		if *input.SortOrder < 0 || *input.SortOrder > 100000 {
			writeAuthError(w, r, ErrInvalidBookmarkFolderName)
			return
		}
		sortOrder = *input.SortOrder
	}
	if _, err := tx.ExecContext(r.Context(), `UPDATE bookmark_folders SET name = $1, sort_order = $2, updated_at = now() WHERE id = $3 AND user_id = $4`, name, sortOrder, folderID, user.ID); err != nil {
		if isUniqueViolation(err) {
			writeAuthError(w, r, ErrBookmarkFolderNameTaken)
			return
		}
		writeInternalError(w, r, err)
		return
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"id": folderID, "name": name, "is_default": isDefault, "sort_order": sortOrder})
}

func (s *Server) deleteBookmarkFolder(w http.ResponseWriter, r *http.Request, folderID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.requireRegisteredUser(w, r)
	if !ok {
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	var isDefault bool
	if err := tx.QueryRowContext(r.Context(), `SELECT is_default FROM bookmark_folders WHERE id = $1 AND user_id = $2 FOR UPDATE`, folderID, user.ID).Scan(&isDefault); errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrBookmarkFolderNotFound)
		return
	} else if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if isDefault {
		writeAuthError(w, r, ErrDefaultBookmarkFolder)
		return
	}
	defaultID, err := ensureDefaultBookmarkFolderTx(r.Context(), tx, user.ID)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if _, err := tx.ExecContext(r.Context(), `
		INSERT INTO bookmark_folder_items (folder_id, post_id, created_at)
		SELECT $1, old.post_id, now()
		FROM bookmark_folder_items old
		WHERE old.folder_id = $2
		  AND NOT EXISTS (
			SELECT 1 FROM bookmark_folder_items other
			WHERE other.post_id = old.post_id AND other.folder_id <> $2
		  )
		ON CONFLICT (folder_id, post_id) DO NOTHING`, defaultID, folderID); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if _, err := tx.ExecContext(r.Context(), `DELETE FROM bookmark_folder_items WHERE folder_id = $1`, folderID); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if _, err := tx.ExecContext(r.Context(), `DELETE FROM bookmark_folders WHERE id = $1 AND user_id = $2`, folderID, user.ID); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) listBookmarkFolderPosts(w http.ResponseWriter, r *http.Request, folderID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	limit, err := parseLimit(r.URL.Query().Get("limit"))
	if err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_LIMIT", Message: "limit 必须是 1 到 50 之间的整数"})
		return
	}
	args := []any{folderID, user.ID}
	where := "fi.folder_id = $1 AND f.user_id = $2 AND p.deleted_at IS NULL AND p.publication_status = 'published' AND p.moderation_status = 'normal'"
	if rawCursor := strings.TrimSpace(r.URL.Query().Get("cursor")); rawCursor != "" {
		createdAt, postID, decodeErr := decodeBookmarkPostCursor(rawCursor)
		if decodeErr != nil {
			httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_CURSOR", Message: "cursor 无效"})
			return
		}
		where += " AND (fi.created_at, fi.post_id) < ($3, $4)"
		args = append(args, createdAt, postID)
	}
	args = append(args, limit+1)
	rows, err := s.db.QueryContext(r.Context(), fmt.Sprintf(`
		SELECT p.id, p.title, LEFT(p.content, 200), p.community_id, c.name,
		       p.comment_count, p.like_count, p.bookmark_count, fi.created_at
		FROM bookmark_folder_items fi
		JOIN bookmark_folders f ON f.id = fi.folder_id
		JOIN posts p ON p.id = fi.post_id
		JOIN communities c ON c.id = p.community_id
		WHERE %s
		ORDER BY fi.created_at DESC, fi.post_id DESC
		LIMIT $%d`, where, len(args)), args...)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()
	items := make([]map[string]any, 0, limit+1)
	for rows.Next() {
		var id, title, content, communityID, communityName string
		var commentCount, likeCount, bookmarkCount int64
		var createdAt time.Time
		if err := rows.Scan(&id, &title, &content, &communityID, &communityName, &commentCount, &likeCount, &bookmarkCount, &createdAt); err != nil {
			writeInternalError(w, r, err)
			return
		}
		items = append(items, map[string]any{"id": id, "title": title, "content_preview": content, "community_id": communityID, "community_name": communityName, "comment_count": commentCount, "like_count": likeCount, "bookmark_count": bookmarkCount, "created_at": createdAt})
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
		last := items[len(items)-1]
		nextCursor = encodeBookmarkPostCursor(last["created_at"].(time.Time), last["id"].(string))
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items, "next_cursor": nextCursor, "has_more": hasMore})
}

func (s *Server) getPostBookmarkFolders(w http.ResponseWriter, r *http.Request, postID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if err := ensureDefaultBookmarkFolder(r.Context(), s.db, user.ID); err != nil {
		writeInternalError(w, r, err)
		return
	}
	rows, err := s.db.QueryContext(r.Context(), `
		SELECT f.id, f.name, f.is_default, f.sort_order, f.created_at, f.updated_at,
		       COUNT(fi_all.post_id), EXISTS (
				SELECT 1 FROM bookmark_folder_items fi_selected
				WHERE fi_selected.folder_id = f.id AND fi_selected.post_id = $1
			)
		FROM bookmark_folders f
		LEFT JOIN bookmark_folder_items fi_all ON fi_all.folder_id = f.id
		WHERE f.user_id = $2
		GROUP BY f.id
		ORDER BY f.sort_order ASC, f.created_at ASC, f.id ASC`, postID, user.ID)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()
	folders := make([]map[string]any, 0)
	selected := make([]string, 0)
	for rows.Next() {
		var id, name string
		var isDefault, isSelected bool
		var sortOrder int
		var createdAt, updatedAt time.Time
		var count int64
		if err := rows.Scan(&id, &name, &isDefault, &sortOrder, &createdAt, &updatedAt, &count, &isSelected); err != nil {
			writeInternalError(w, r, err)
			return
		}
		folders = append(folders, bookmarkFolderJSONWithSelected(id, name, isDefault, sortOrder, count, createdAt, updatedAt, isSelected))
		if isSelected {
			selected = append(selected, id)
		}
	}
	if err := rows.Err(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"folders": folders, "folder_ids": selected})
}

func (s *Server) setPostBookmarkFolders(w http.ResponseWriter, r *http.Request, postID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.requireRegisteredUser(w, r)
	if !ok {
		return
	}
	var input bookmarkFolderIDsInput
	if err := decodeJSON(r, &input); err != nil || len(input.FolderIDs) > 50 {
		writeAuthError(w, r, ErrInvalidBookmarkFolderName)
		return
	}
	folderIDs := uniqueNonEmptyStrings(input.FolderIDs)
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	if err := lockPostForInteraction(r.Context(), tx, postID); err != nil {
		writeAuthError(w, r, err)
		return
	}
	if _, err := ensureDefaultBookmarkFolderTx(r.Context(), tx, user.ID); err != nil {
		writeInternalError(w, r, err)
		return
	}
	// 删除收藏夹会锁住同一行；这里也按稳定顺序锁定所有目标收藏夹，
	// 避免删除与加入并发时出现外键错误，也避免两个请求以相反顺序互相等待。
	lockedFolderIDs := append([]string(nil), folderIDs...)
	sort.Strings(lockedFolderIDs)
	for _, folderID := range lockedFolderIDs {
		var ownedID string
		if err := tx.QueryRowContext(r.Context(), `SELECT id FROM bookmark_folders WHERE id = $1 AND user_id = $2 FOR UPDATE`, folderID, user.ID).Scan(&ownedID); errors.Is(err, sql.ErrNoRows) {
			writeAuthError(w, r, ErrBookmarkFolderNotFound)
			return
		} else if err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	var changed bool
	if len(folderIDs) == 0 {
		result, err := tx.ExecContext(r.Context(), `DELETE FROM bookmarks WHERE post_id = $1 AND user_id = $2`, postID, user.ID)
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
		changed, err = rowsChanged(result, nil)
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
		if _, err := tx.ExecContext(r.Context(), `DELETE FROM bookmark_folder_items WHERE post_id = $1`, postID); err != nil {
			writeInternalError(w, r, err)
			return
		}
	} else {
		result, err := tx.ExecContext(r.Context(), `INSERT INTO bookmarks (post_id, user_id) VALUES ($1, $2) ON CONFLICT (post_id, user_id) DO NOTHING`, postID, user.ID)
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
		changed, err = rowsChanged(result, nil)
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
		if _, err := tx.ExecContext(r.Context(), `DELETE FROM bookmark_folder_items WHERE post_id = $1`, postID); err != nil {
			writeInternalError(w, r, err)
			return
		}
		for _, folderID := range folderIDs {
			if _, err := tx.ExecContext(r.Context(), `INSERT INTO bookmark_folder_items (folder_id, post_id) VALUES ($1, $2) ON CONFLICT (folder_id, post_id) DO NOTHING`, folderID, postID); err != nil {
				writeInternalError(w, r, err)
				return
			}
		}
	}
	if changed {
		operator := "+ 1"
		if len(folderIDs) == 0 {
			operator = "- 1"
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE posts SET bookmark_count = GREATEST(bookmark_count `+operator+`, 0), updated_at = now() WHERE id = $1`, postID); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"active": len(folderIDs) > 0, "folder_ids": folderIDs})
}

func ensureDefaultBookmarkFolder(ctx context.Context, db *sql.DB, userID string) error {
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := ensureDefaultBookmarkFolderTx(ctx, tx, userID); err != nil {
		return err
	}
	return tx.Commit()
}

func ensureDefaultBookmarkFolderTx(ctx context.Context, tx *sql.Tx, userID string) (string, error) {
	var id string
	err := tx.QueryRowContext(ctx, `SELECT id FROM bookmark_folders WHERE user_id = $1 AND is_default = true FOR UPDATE`, userID).Scan(&id)
	if err == nil {
		return id, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return "", err
	}
	id = "folder_default_" + newPostID()
	if _, err := tx.ExecContext(ctx, `INSERT INTO bookmark_folders (id, user_id, name, is_default, sort_order) VALUES ($1, $2, '默认收藏夹', true, 0) ON CONFLICT (user_id) WHERE is_default = true DO NOTHING`, id, userID); err != nil {
		return "", err
	}
	if err := tx.QueryRowContext(ctx, `SELECT id FROM bookmark_folders WHERE user_id = $1 AND is_default = true FOR UPDATE`, userID).Scan(&id); err != nil {
		return "", err
	}
	return id, nil
}

func normalizeBookmarkFolderName(raw string) (string, bool) {
	name := strings.Join(strings.Fields(strings.TrimSpace(raw)), " ")
	if name == "" || len([]rune(name)) > maxBookmarkFolderNameLength {
		return "", false
	}
	return name, true
}

func bookmarkFolderJSON(id, name string, isDefault bool, sortOrder int, count int64, createdAt, updatedAt time.Time) map[string]any {
	return bookmarkFolderJSONWithSelected(id, name, isDefault, sortOrder, count, createdAt, updatedAt, false)
}

func bookmarkFolderJSONWithSelected(id, name string, isDefault bool, sortOrder int, count int64, createdAt, updatedAt time.Time, selected bool) map[string]any {
	return map[string]any{"id": id, "name": name, "is_default": isDefault, "sort_order": sortOrder, "item_count": count, "created_at": createdAt, "updated_at": updatedAt, "selected": selected}
}

func uniqueNonEmptyStrings(values []string) []string {
	seen := make(map[string]struct{}, len(values))
	result := make([]string, 0, len(values))
	for _, value := range values {
		value = strings.TrimSpace(value)
		if value == "" {
			continue
		}
		if _, exists := seen[value]; exists {
			continue
		}
		seen[value] = struct{}{}
		result = append(result, value)
	}
	return result
}

func encodeBookmarkFolderCursor(sortOrder int, createdAt time.Time, id string) string {
	return strconv.Itoa(sortOrder) + ":" + strconv.FormatInt(createdAt.UnixNano(), 10) + ":" + id
}

func decodeBookmarkFolderCursor(value string) (int, time.Time, string, error) {
	parts := strings.SplitN(value, ":", 3)
	if len(parts) != 3 || parts[2] == "" {
		return 0, time.Time{}, "", errors.New("invalid cursor")
	}
	sortOrder, err := strconv.Atoi(parts[0])
	if err != nil {
		return 0, time.Time{}, "", err
	}
	nanos, err := strconv.ParseInt(parts[1], 10, 64)
	if err != nil {
		return 0, time.Time{}, "", err
	}
	return sortOrder, time.Unix(0, nanos).UTC(), parts[2], nil
}

func encodeBookmarkPostCursor(createdAt time.Time, postID string) string {
	return strconv.FormatInt(createdAt.UnixNano(), 10) + ":" + postID
}

func decodeBookmarkPostCursor(value string) (time.Time, string, error) {
	parts := strings.SplitN(value, ":", 2)
	if len(parts) != 2 || parts[1] == "" {
		return time.Time{}, "", errors.New("invalid cursor")
	}
	nanos, err := strconv.ParseInt(parts[0], 10, 64)
	if err != nil {
		return time.Time{}, "", err
	}
	return time.Unix(0, nanos).UTC(), parts[1], nil
}

// isUniqueViolation 只依赖 PostgreSQL 驱动返回错误文本，避免把 pgconn 类型
// 泄漏到 API 包，sqlmock 和真实驱动都能复用同一分支。
func isUniqueViolation(err error) bool {
	return err != nil && strings.Contains(strings.ToLower(err.Error()), "duplicate key")
}
