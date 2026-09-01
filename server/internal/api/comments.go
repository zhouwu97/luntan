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
	ErrCommentNotFound       = errors.New("comment not found")
	ErrCommentParentNotFound = errors.New("comment parent not found")
	ErrInvalidComment        = errors.New("invalid comment")
)

type commentAttachmentResponse struct {
	ID           string `json:"id"`
	Type         string `json:"type"`
	URL          string `json:"url,omitempty"`
	ThumbnailURL string `json:"thumbnail_url,omitempty"`
	Width        int    `json:"width,omitempty"`
	Height       int    `json:"height,omitempty"`
	StickerID    string `json:"sticker_id,omitempty"`
}

type commentAttachmentInput struct {
	Type    string `json:"type"`
	MediaID string `json:"media_id"`
}

type commentResponse struct {
	ID            string                      `json:"id"`
	PostID        string                      `json:"post_id"`
	Author        userSummary                 `json:"author"`
	ReplyToUser   *userSummary                `json:"reply_to_user,omitempty"`
	RootID        *string                     `json:"root_id,omitempty"`
	ParentID      *string                     `json:"parent_id,omitempty"`
	ReplyToUserID *string                     `json:"reply_to_user_id,omitempty"`
	Content       string                      `json:"content"`
	Media         []postMediaResponse         `json:"media,omitempty"`
	StickerID     *string                     `json:"sticker_id,omitempty"`
	Attachments   []commentAttachmentResponse `json:"attachments,omitempty"`
	LikeCount     int64                       `json:"like_count"`
	DislikeCount  int64                       `json:"dislike_count"`
	ReplyCount    int64                       `json:"reply_count"`
	Floor         *int                        `json:"floor,omitempty"`
	ReplyPreview  []commentResponse           `json:"reply_preview,omitempty"`
	Publication   string                      `json:"publication_status"`
	Moderation    string                      `json:"moderation_status"`
	CreatedAt     time.Time                   `json:"created_at"`
	UpdatedAt     time.Time                   `json:"updated_at"`
	ViewerState   *viewerCommentState         `json:"viewer_state,omitempty"`
}

type viewerCommentState struct {
	HasLiked    bool `json:"has_liked"`
	HasDisliked bool `json:"has_disliked"`
}

type commentInput struct {
	Content       string                   `json:"content"`
	ParentID      string                   `json:"parent_id"`
	ReplyToUserID string                   `json:"reply_to_user_id"`
	MediaIDs      []string                 `json:"media_ids"`
	StickerID     string                   `json:"sticker_id"`
	Attachments   []commentAttachmentInput `json:"attachments"`
}

type commentCursor struct {
	CreatedAt time.Time `json:"created_at"`
	ID        string    `json:"id"`
}

// floorNumberExpr 计算楼层号：对所有可见根评论按发布顺序编号，
// 在拉黑/只看楼主等过滤之前计算，保证楼层号对任何观看者都稳定。
const floorNumberExpr = `ROW_NUMBER() OVER (ORDER BY c.created_at ASC, c.id ASC)`

// commentFloorColumns 是楼层/回复共用的 SELECT 列集，
// 与 (*Server).collectCommentFloorRows 的 Scan 顺序一一对应。
const commentFloorColumns = `t.id, t.post_id, t.author_id, u.username, COALESCE(up.nickname, u.username),
		       COALESCE(up.level, 1), COALESCE(ma.id, ''), COALESCE(ma.object_key, ''), t.content,
		       t.like_count, t.dislike_count, t.reply_count, t.created_at, t.updated_at,
		       t.floor_no, COALESCE(t.root_id, t.id), COALESCE(t.parent_id, ''),
		       COALESCE(t.reply_to_user_id, ''), COALESCE(t.sticker_id, ''), t.publication_status`

const commentFloorJoins = `JOIN users u ON u.id = t.author_id
		LEFT JOIN user_profiles up ON up.user_id = t.author_id
		LEFT JOIN media_assets ma ON ma.id = up.avatar_media_id`

// viewerReactionExprs 生成观看者点赞/点踩存在性表达式，viewerPos 是观看者参数位。
func viewerReactionExprs(viewerPos int) (string, string) {
	liked := fmt.Sprintf(`EXISTS (
			SELECT 1 FROM comment_reactions cr
			WHERE cr.comment_id = t.id AND cr.user_id = $%d AND cr.reaction_type = 'like'
		)`, viewerPos)
	disliked := strings.Replace(liked, "'like'", "'dislike'", 1)
	return liked, disliked
}

func (s *Server) listComments(w http.ResponseWriter, r *http.Request, postID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	limit, err := parseLimit(r.URL.Query().Get("limit"))
	if err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_LIMIT", Message: "limit 必须是 1 到 50 之间的整数"})
		return
	}
	offset := 0
	if value := r.URL.Query().Get("offset"); value != "" {
		parsed, parseErr := strconv.Atoi(value)
		if parseErr != nil || parsed < 0 || parsed > 1000000 {
			httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_OFFSET", Message: "offset 必须是非负整数"})
			return
		}
		offset = parsed
	}
	sortKey := strings.TrimSpace(r.URL.Query().Get("sort"))
	switch sortKey {
	case "":
		sortKey = "asc"
	case "asc", "desc", "hot":
	default:
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_SORT", Message: "sort 仅支持 asc、desc、hot"})
		return
	}
	// 评论列表的可见性必须与帖子详情保持一致：公开帖子对所有人可读，
	// 作者本人和审核人员也可以读取自己有权限查看的待审核帖子。
	// 如果这里仍只检查 published/normal，作者打开自己的待审核帖子时会
	// 得到 POST_NOT_FOUND，客户端就会显示“评论加载失败”。
	var postAuthorID, communityID, publicationStatus, moderationStatus string
	err = s.db.QueryRowContext(r.Context(), `
		SELECT author_id, community_id, publication_status, moderation_status
		FROM posts
		WHERE id = $1 AND deleted_at IS NULL`, postID).
		Scan(&postAuthorID, &communityID, &publicationStatus, &moderationStatus)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrPostNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if publicationStatus != "published" || moderationStatus != "normal" {
		viewer, ok := resolveOptionalViewer(s, r)
		canReview := ok && viewer.ID != "" && s.hasScopedPermission(r, viewer.ID, "report.review", communityID)
		if !ok || (viewer.ID != postAuthorID && !canReview) {
			writeAuthError(w, r, ErrPostNotFound)
			return
		}
	}

	args := []any{postID}
	likedExpr, dislikedExpr := "false", "false"
	filterSQL := ""
	viewer, hasViewer := s.optionalAuthenticatedUser(r.Context(), r)
	if hasViewer {
		// 观看者统一绑定一个参数位（EXISTS 表达式与 blocks 过滤复用），
		// 否则 COUNT 查询里该参数未被引用会导致 42P18 无法推断类型。
		likedExpr, dislikedExpr = viewerReactionExprs(len(args) + 1)
		args = append(args, viewer.ID)
		filterSQL = fmt.Sprintf(` AND NOT EXISTS (
			SELECT 1 FROM blocks b
			WHERE (b.blocker_id = $%d AND b.blocked_id = t.author_id)
			   OR (b.blocker_id = t.author_id AND b.blocked_id = $%d)
		)`, len(args), len(args))
	}
	// 只看楼主：客户端传作者的 user id。
	if authorID := strings.TrimSpace(r.URL.Query().Get("author_id")); authorID != "" {
		filterSQL += fmt.Sprintf(" AND t.author_id = $%d", len(args)+1)
		args = append(args, authorID)
	}

	orderBy := map[string]string{
		"asc":  "t.floor_no ASC, t.id ASC",
		"desc": "t.floor_no DESC, t.id DESC",
		"hot":  "t.like_count DESC, t.floor_no ASC",
	}[sortKey]

	baseQuery := fmt.Sprintf(`
		FROM (
			SELECT c.id, c.post_id, c.author_id, c.root_id, c.parent_id, c.reply_to_user_id, c.sticker_id,
			       CASE WHEN c.publication_status = 'deleted' THEN '' ELSE c.content END AS content,
			       c.like_count, c.dislike_count, c.reply_count,
			       c.created_at, c.updated_at, c.publication_status, %s AS floor_no
			FROM comments c
			WHERE c.post_id = $1 AND (
				    (c.deleted_at IS NULL AND c.publication_status = 'published' AND c.moderation_status = 'normal')
				 OR (c.deleted_at IS NOT NULL AND c.publication_status = 'deleted' AND EXISTS (
					SELECT 1 FROM comments cr
					WHERE cr.root_id = c.id AND cr.id <> c.id
					  AND cr.deleted_at IS NULL
					  AND cr.publication_status = 'published' AND cr.moderation_status = 'normal'))
			 )
			  AND (c.root_id IS NULL OR c.root_id = c.id)
		) t
		%s
		WHERE 1 = 1%s`, floorNumberExpr, commentFloorJoins, filterSQL)

	var total int64
	if err := s.db.QueryRowContext(r.Context(), "SELECT COUNT(*)"+baseQuery, args...).Scan(&total); err != nil {
		writeInternalError(w, r, err)
		return
	}

	query := fmt.Sprintf(`SELECT %s, %s, %s %s ORDER BY %s OFFSET %d LIMIT %d`,
		commentFloorColumns, likedExpr, dislikedExpr, baseQuery, orderBy, offset, limit)
	rows, err := s.db.QueryContext(r.Context(), query, args...)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	items, err := s.collectCommentFloorRows(r.Context(), rows, hasViewer, true)
	if closeErr := rows.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}

	previewReplies, err := s.loadCommentReplyPreviews(r.Context(), items, viewer, hasViewer)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := enrichCommentsMedia(r.Context(), s.db, items); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := enrichCommentsMedia(r.Context(), s.db, previewReplies); err != nil {
		writeInternalError(w, r, err)
		return
	}
	attachReplyPreviews(items, previewReplies)

	for i := range items {
		if items[i].Publication == "deleted" {
			items[i].Content = ""
			items[i].StickerID = nil
			items[i].Media = nil
			items[i].Attachments = nil
			items[i].ReplyToUser = nil
			items[i].ReplyToUserID = nil
		}
	}

	httpserver.WriteJSON(w, http.StatusOK, map[string]any{
		"items":    items,
		"total":    total,
		"has_more": int64(offset+len(items)) < total,
	})
}

// loadCommentReplyPreviews 为每个楼层取前 3 条回复（按时间正序），
// 同样应用观看者拉黑过滤。
func (s *Server) loadCommentReplyPreviews(ctx context.Context, items []commentResponse, viewer auth.User, hasViewer bool) ([]commentResponse, error) {
	if len(items) == 0 {
		return nil, nil
	}
	replyArgs := make([]any, 0, len(items)+1)
	placeholders := make([]string, len(items))
	for i, item := range items {
		replyArgs = append(replyArgs, item.ID)
		placeholders[i] = fmt.Sprintf("$%d", i+1)
	}
	likedExpr, dislikedExpr := "false", "false"
	blockSQL := ""
	if hasViewer {
		likedExpr, dislikedExpr = viewerReactionExprs(len(replyArgs) + 1)
		replyArgs = append(replyArgs, viewer.ID)
		blockSQL = fmt.Sprintf(` AND NOT EXISTS (
			SELECT 1 FROM blocks b
			WHERE (b.blocker_id = $%d AND b.blocked_id = c.author_id)
			   OR (b.blocker_id = c.author_id AND b.blocked_id = $%d)
		)`, len(replyArgs), len(replyArgs))
	}
	query := fmt.Sprintf(`
		SELECT %s, %s, %s
		FROM (
			SELECT c.*, NULL::bigint AS floor_no, ROW_NUMBER() OVER (PARTITION BY c.root_id ORDER BY c.created_at ASC, c.id ASC) AS rn
			FROM comments c
			WHERE c.root_id IN (%s) AND c.id <> c.root_id AND c.deleted_at IS NULL
			  AND c.publication_status = 'published' AND c.moderation_status = 'normal'%s
		) t
		%s
		WHERE t.rn <= 3
		ORDER BY t.root_id ASC, t.rn ASC`, commentFloorColumns, likedExpr, dislikedExpr, strings.Join(placeholders, ", "), blockSQL, commentFloorJoins)
	rows, err := s.db.QueryContext(ctx, query, replyArgs...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return s.collectCommentFloorRows(ctx, rows, hasViewer, false)
}

// collectCommentFloorRows 统一扫描楼层/回复行；withFloor 时把 floor_no
// 写入响应（回复行的 floor_no 恒为 NULL，不写）。
func (s *Server) collectCommentFloorRows(ctx context.Context, rows *sql.Rows, hasViewer, withFloor bool) ([]commentResponse, error) {
	items := make([]commentResponse, 0, 16)
	for rows.Next() {
		var item commentResponse
		var postID, authorID, rootID, parentID, replyTo, stickerID, avatarMediaID, avatarKey string
		var floorNo sql.NullInt64
		var hasLiked, hasDisliked bool
		if err := rows.Scan(
			&item.ID, &postID, &authorID, &item.Author.Username, &item.Author.Nickname,
			&item.Author.Level, &avatarMediaID, &avatarKey, &item.Content,
			&item.LikeCount, &item.DislikeCount, &item.ReplyCount,
			&item.CreatedAt, &item.UpdatedAt, &floorNo,
			&rootID, &parentID, &replyTo, &stickerID, &item.Publication,
			&hasLiked, &hasDisliked,
		); err != nil {
			return nil, err
		}
		item.PostID = postID
		item.Author.ID = authorID
		if avatarKey != "" {
			item.Author.AvatarURL = mediaVariantURL(avatarMediaID, avatarKey, "thumb")
		}
		item.RootID, item.ParentID, item.ReplyToUserID = optionalString(rootID), optionalString(parentID), optionalString(replyTo)
		item.StickerID = optionalString(stickerID)
		if withFloor && floorNo.Valid {
			floor := int(floorNo.Int64)
			item.Floor = &floor
		}
		if hasViewer {
			item.ViewerState = &viewerCommentState{HasLiked: hasLiked, HasDisliked: hasDisliked}
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	for i := range items {
		if err := enrichReplyToUser(ctx, s.db, &items[i]); err != nil {
			return nil, err
		}
	}
	return items, nil
}

// attachReplyPreviews 把预览回复按 root_id 挂到对应楼层。
func attachReplyPreviews(items []commentResponse, replies []commentResponse) {
	if len(items) == 0 || len(replies) == 0 {
		return
	}
	byRoot := make(map[string][]commentResponse, len(items))
	for _, reply := range replies {
		if reply.RootID == nil {
			continue
		}
		byRoot[*reply.RootID] = append(byRoot[*reply.RootID], reply)
	}
	for i := range items {
		if preview := byRoot[items[i].ID]; len(preview) > 0 {
			items[i].ReplyPreview = preview
		}
	}
}

func (s *Server) listCommentReplies(w http.ResponseWriter, r *http.Request, commentID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	limit, err := parseLimit(r.URL.Query().Get("limit"))
	if err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_LIMIT", Message: "limit 必须是 1 到 50 之间的整数"})
		return
	}
	var rootID string
	err = s.db.QueryRowContext(r.Context(), `SELECT COALESCE(root_id, id) FROM comments WHERE id = $1 AND (
		(deleted_at IS NULL AND publication_status = 'published' AND moderation_status = 'normal')
	 OR (deleted_at IS NOT NULL AND publication_status = 'deleted'))`, commentID).Scan(&rootID)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrCommentNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	var cursor *commentCursor
	if value := r.URL.Query().Get("cursor"); value != "" {
		decoded, decodeErr := decodeCommentCursor(value)
		if decodeErr != nil {
			httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_CURSOR", Message: "cursor 无效"})
			return
		}
		cursor = &decoded
	}
	args := []any{rootID}
	likedExpr, dislikedExpr := "false", "false"
	filterSQL := ""
	viewer, hasViewer := s.optionalAuthenticatedUser(r.Context(), r)
	if hasViewer {
		likedExpr, dislikedExpr = viewerReactionExprs(len(args) + 1)
		args = append(args, viewer.ID)
		filterSQL = fmt.Sprintf(` AND NOT EXISTS (
			SELECT 1 FROM blocks b
			WHERE (b.blocker_id = $%d AND b.blocked_id = t.author_id)
			   OR (b.blocker_id = t.author_id AND b.blocked_id = $%d)
		)`, len(args)+1, len(args)+1)
		args = append(args, viewer.ID)
	}
	if cursor != nil {
		filterSQL += fmt.Sprintf(" AND (t.created_at, t.id) > ($%d, $%d)", len(args)+1, len(args)+2)
		args = append(args, cursor.CreatedAt, cursor.ID)
	}
	limitPosition := len(args) + 1
	query := fmt.Sprintf(`SELECT %s, %s, %s
		FROM (
			SELECT c.id, c.post_id, c.author_id, c.root_id, c.parent_id, c.reply_to_user_id, c.sticker_id,
			       c.content, c.like_count, c.dislike_count, c.reply_count,
			       c.created_at, c.updated_at, c.publication_status, NULL::bigint AS floor_no
			FROM comments c
			WHERE c.root_id = $1 AND c.id <> $1 AND c.deleted_at IS NULL
			  AND c.publication_status = 'published' AND c.moderation_status = 'normal'
		) t
		%s
		WHERE 1 = 1%s
		ORDER BY t.created_at ASC, t.id ASC LIMIT $%d`,
		commentFloorColumns, likedExpr, dislikedExpr, commentFloorJoins, filterSQL, limitPosition)
	args = append(args, limit+1)
	rows, err := s.db.QueryContext(r.Context(), query, args...)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	items, err := s.collectCommentFloorRows(r.Context(), rows, hasViewer, false)
	if closeErr := rows.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := enrichCommentsMedia(r.Context(), s.db, items); err != nil {
		writeInternalError(w, r, err)
		return
	}
	hasMore := len(items) > limit
	if hasMore {
		items = items[:limit]
	}
	var nextCursor any
	if hasMore && len(items) > 0 {
		encoded, encodeErr := encodeCommentCursor(commentCursor{CreatedAt: items[len(items)-1].CreatedAt, ID: items[len(items)-1].ID})
		if encodeErr != nil {
			writeInternalError(w, r, encodeErr)
			return
		}
		nextCursor = encoded
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items, "next_cursor": nextCursor, "has_more": hasMore})
}

func (s *Server) createComment(w http.ResponseWriter, r *http.Request, postID, forcedParentID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if !s.requireCapability(w, r, user, capComment) {
		return
	}
	s.createCommentForUser(w, r, user, postID, forcedParentID)
}

func (s *Server) createReply(w http.ResponseWriter, r *http.Request, parentID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if !s.requireCapability(w, r, user, capComment) {
		return
	}
	var postID string
	err := s.db.QueryRowContext(r.Context(), `SELECT post_id FROM comments WHERE id = $1 AND deleted_at IS NULL AND publication_status = 'published' AND moderation_status = 'normal'`, parentID).Scan(&postID)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrCommentParentNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	s.createCommentForUser(w, r, user, postID, parentID)
}

func (s *Server) createCommentForUser(w http.ResponseWriter, r *http.Request, user auth.User, postID, forcedParentID string) {
	idempotencyKey := strings.TrimSpace(r.Header.Get("Idempotency-Key"))
	if idempotencyKey == "" || len(idempotencyKey) > 128 {
		writeAuthError(w, r, ErrIdempotencyKeyRequired)
		return
	}
	var input commentInput
	if err := decodeJSON(r, &input); err != nil {
		writeAuthError(w, r, ErrInvalidComment)
		return
	}
	input.Content = strings.TrimSpace(input.Content)
	if len([]rune(input.Content)) > 5000 {
		writeAuthError(w, r, ErrInvalidComment)
		return
	}
	mediaIDs := make([]string, 0, len(input.MediaIDs)+len(input.Attachments))
	for _, id := range input.MediaIDs {
		trimmed := strings.TrimSpace(id)
		if trimmed != "" && !sliceContains(mediaIDs, trimmed) {
			mediaIDs = append(mediaIDs, trimmed)
		}
	}
	for _, att := range input.Attachments {
		if att.Type == "image" || att.Type == "" {
			trimmed := strings.TrimSpace(att.MediaID)
			if trimmed != "" && !sliceContains(mediaIDs, trimmed) {
				mediaIDs = append(mediaIDs, trimmed)
			}
		}
	}
	stickerID := strings.TrimSpace(input.StickerID)
	if stickerID == "" {
		for _, att := range input.Attachments {
			if att.Type == "sticker" && strings.TrimSpace(att.MediaID) != "" {
				stickerID = strings.TrimSpace(att.MediaID)
				break
			}
		}
	}
	if input.Content == "" && len(mediaIDs) == 0 && stickerID == "" {
		writeAuthError(w, r, ErrInvalidComment)
		return
	}
	if len(mediaIDs) > 9 || len(stickerID) > 128 || (len(mediaIDs) > 0 && stickerID != "") {
		writeAuthError(w, r, ErrInvalidComment)
		return
	}

	for _, mid := range mediaIDs {
		var ownerID, status, mimeType string
		err := s.db.QueryRowContext(r.Context(), `SELECT owner_id, status, mime_type FROM media_assets WHERE id = $1 AND deleted_at IS NULL`, mid).Scan(&ownerID, &status, &mimeType)
		if errors.Is(err, sql.ErrNoRows) || ownerID != user.ID || status != "ready" || !strings.HasPrefix(strings.ToLower(mimeType), "image/") {
			writeAuthError(w, r, ErrInvalidMedia)
			return
		}
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
	}

	parentID := strings.TrimSpace(forcedParentID)
	if parentID == "" {
		parentID = strings.TrimSpace(input.ParentID)
	}
	var relationTargetID string
	if parentID != "" {
		if err := s.db.QueryRowContext(r.Context(), `SELECT author_id FROM comments WHERE id = $1 AND deleted_at IS NULL`, parentID).Scan(&relationTargetID); err != nil && !errors.Is(err, sql.ErrNoRows) {
			writeInternalError(w, r, err)
			return
		}
	} else if err := s.db.QueryRowContext(r.Context(), `SELECT author_id FROM posts WHERE id = $1 AND deleted_at IS NULL`, postID).Scan(&relationTargetID); err != nil && !errors.Is(err, sql.ErrNoRows) {
		writeInternalError(w, r, err)
		return
	}
	if relationTargetID != "" {
		blocked, err := usersBlockEachOther(r.Context(), s.db, user.ID, relationTargetID)
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
		if blocked {
			writeAuthError(w, r, ErrBlocked)
			return
		}
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	commentID := newPostID()
	var existingCommentID string
	err = tx.QueryRowContext(r.Context(), `
		INSERT INTO comment_idempotency_keys (user_id, idempotency_key, comment_id, created_at)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT (user_id, idempotency_key) DO NOTHING
		RETURNING comment_id`, user.ID, idempotencyKey, commentID, time.Now().UTC()).Scan(&existingCommentID)
	if errors.Is(err, sql.ErrNoRows) {
		if err := tx.QueryRowContext(r.Context(), `SELECT comment_id FROM comment_idempotency_keys WHERE user_id = $1 AND idempotency_key = $2`, user.ID, idempotencyKey).Scan(&existingCommentID); err != nil {
			writeInternalError(w, r, err)
			return
		}
		response, loadErr := loadCommentResponseTx(r.Context(), tx, existingCommentID, user.ID)
		if loadErr != nil {
			writeInternalError(w, r, loadErr)
			return
		}
		if err := tx.Commit(); err != nil {
			writeInternalError(w, r, err)
			return
		}
		httpserver.WriteJSON(w, http.StatusOK, response)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	var postExists string
	err = tx.QueryRowContext(r.Context(), `SELECT id FROM posts WHERE id = $1 AND publication_status = 'published' AND moderation_status = 'normal' AND deleted_at IS NULL FOR UPDATE`, postID).Scan(&postExists)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrPostNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	rootID := commentID
	if parentID != "" {
		var parentPostID, parentRootID, parentAuthorID string
		err = tx.QueryRowContext(r.Context(), `SELECT post_id, COALESCE(root_id, id), author_id FROM comments WHERE id = $1 AND deleted_at IS NULL AND publication_status = 'published' AND moderation_status = 'normal'`, parentID).Scan(&parentPostID, &parentRootID, &parentAuthorID)
		if err != nil && !errors.Is(err, sql.ErrNoRows) {
			writeInternalError(w, r, err)
			return
		}
		if errors.Is(err, sql.ErrNoRows) || parentPostID != postID {
			writeAuthError(w, r, ErrCommentParentNotFound)
			return
		}
		rootID = parentRootID
		// 回复通知目标由服务端按 parent 推导，忽略客户端传值，防止伪造通知接收人。
		input.ReplyToUserID = parentAuthorID
	}
	now := time.Now().UTC()
	if _, err := tx.ExecContext(r.Context(), `UPDATE comment_idempotency_keys SET comment_id = $1 WHERE user_id = $2 AND idempotency_key = $3`, commentID, user.ID, idempotencyKey); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if _, err := tx.ExecContext(r.Context(), `
		INSERT INTO comments (id, post_id, author_id, root_id, parent_id, reply_to_user_id, content, sticker_id, publication_status, moderation_status, created_at, updated_at, published_at)
		VALUES ($1, $2, $3, $4, NULLIF($5, ''), NULLIF($6, ''), $7, NULLIF($8, ''), 'published', 'normal', $9, $9, $9)`,
		commentID, postID, user.ID, rootID, parentID, strings.TrimSpace(input.ReplyToUserID), input.Content, stickerID, now,
	); err != nil {
		writeInternalError(w, r, err)
		return
	}
	for idx, mid := range mediaIDs {
		if _, err := tx.ExecContext(r.Context(), `INSERT INTO comment_media (comment_id, media_id, sort_order, created_at) VALUES ($1, $2, $3, $4)`, commentID, mid, idx, now); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	if parentID != "" {
		// reply_count 语义：根评论统计楼中楼全部可见后代，与 replies 接口返回集一致。
		if _, err := tx.ExecContext(r.Context(), `UPDATE comments SET reply_count = reply_count + 1, updated_at = $1 WHERE id = $2`, now, rootID); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	if _, err := tx.ExecContext(r.Context(), `UPDATE posts SET comment_count = comment_count + 1, updated_at = $1 WHERE id = $2`, now, postID); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if parentID != "" && input.ReplyToUserID != "" {
		if err := enqueueNotificationWithDataTx(tx, input.ReplyToUserID, user.ID, "reply", "post", postID, map[string]any{"comment_id": parentID}, now); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	if err := awardExperienceTx(r.Context(), tx, user.ID, "comment", "参与回复", "comment:create:"+commentID, s.experienceRewards.CommentCreate, s.experienceRewards.CommentCreateDailyLimit); err != nil {
		writeInternalError(w, r, err)
		return
	}

	response, err := loadCommentResponseTx(r.Context(), tx, commentID, user.ID)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}

	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusCreated, response)
}

func loadCommentResponseTx(ctx context.Context, tx *sql.Tx, commentID, viewerID string) (commentResponse, error) {
	var response commentResponse
	var authorID, rootID, parentID, replyTo, stickerID, avatarMediaID string
	var floorNo sql.NullInt64
	err := tx.QueryRowContext(ctx, `
		SELECT c.id, c.post_id, c.author_id, u.username, COALESCE(up.nickname, u.username),
		       COALESCE(up.level, 1), COALESCE(ma.id, ''), COALESCE(ma.object_key, ''),
		       COALESCE(c.root_id, ''), COALESCE(c.parent_id, ''), COALESCE(c.reply_to_user_id, ''),
		       c.content, COALESCE(c.sticker_id, ''), c.like_count, c.dislike_count, c.reply_count,
		       c.publication_status, c.moderation_status,
		       c.created_at, c.updated_at,
		       CASE WHEN c.root_id = c.id THEN (
		           SELECT COUNT(*) FROM comments c2
		           WHERE c2.post_id = c.post_id AND c2.deleted_at IS NULL
		             AND c2.publication_status = 'published' AND c2.moderation_status = 'normal'
		             AND (c2.root_id IS NULL OR c2.root_id = c2.id)
		             AND (c2.created_at, c2.id) <= (c.created_at, c.id)
		       ) END
		FROM comments c
		JOIN users u ON u.id = c.author_id
		LEFT JOIN user_profiles up ON up.user_id = c.author_id
		LEFT JOIN media_assets ma ON ma.id = up.avatar_media_id
		WHERE c.id = $1`, commentID).Scan(
		&response.ID, &response.PostID, &authorID, &response.Author.Username, &response.Author.Nickname,
		&response.Author.Level, &avatarMediaID, &response.Author.AvatarURL,
		&rootID, &parentID, &replyTo, &response.Content, &stickerID, &response.LikeCount, &response.DislikeCount,
		&response.ReplyCount, &response.Publication, &response.Moderation, &response.CreatedAt, &response.UpdatedAt,
		&floorNo,
	)
	if err != nil {
		return commentResponse{}, err
	}
	if floorNo.Valid {
		floor := int(floorNo.Int64)
		response.Floor = &floor
	}
	response.Author.ID = authorID
	if response.Author.AvatarURL != "" {
		response.Author.AvatarURL = mediaVariantURL(avatarMediaID, response.Author.AvatarURL, "thumb")
	}
	response.RootID = optionalString(rootID)
	response.ParentID = optionalString(parentID)
	response.ReplyToUserID = optionalString(replyTo)
	response.StickerID = optionalString(stickerID)
	if err := enrichReplyToUser(ctx, tx, &response); err != nil {
		return commentResponse{}, err
	}
	responseList := []commentResponse{response}
	if err := enrichCommentsMedia(ctx, tx, responseList); err != nil {
		return commentResponse{}, err
	}
	response = responseList[0]
	if viewerID != "" {
		var hasLiked, hasDisliked bool
		if err := tx.QueryRowContext(ctx, `SELECT
		       EXISTS (SELECT 1 FROM comment_reactions cr WHERE cr.comment_id = c.id AND cr.user_id = $2 AND cr.reaction_type = 'like'),
		       EXISTS (SELECT 1 FROM comment_reactions cr WHERE cr.comment_id = c.id AND cr.user_id = $2 AND cr.reaction_type = 'dislike')
		       FROM comments c WHERE c.id = $1`, commentID, viewerID).Scan(&hasLiked, &hasDisliked); err != nil {
			return commentResponse{}, err
		}
		response.ViewerState = &viewerCommentState{HasLiked: hasLiked, HasDisliked: hasDisliked}
	} else {
		response.ViewerState = &viewerCommentState{}
	}
	return response, nil
}

type databaseQueryer interface {
	QueryContext(ctx context.Context, query string, args ...any) (*sql.Rows, error)
}

func enrichCommentsMedia(ctx context.Context, db databaseQueryer, items []commentResponse) error {
	if len(items) == 0 {
		return nil
	}
	commentIDs := make([]any, len(items))
	idToIdx := make(map[string]int, len(items))
	for i := range items {
		commentIDs[i] = items[i].ID
		idToIdx[items[i].ID] = i
		if items[i].Media == nil {
			items[i].Media = make([]postMediaResponse, 0)
		}
		if items[i].Attachments == nil {
			items[i].Attachments = make([]commentAttachmentResponse, 0)
		}
		if items[i].StickerID != nil && *items[i].StickerID != "" {
			items[i].Attachments = append(items[i].Attachments, commentAttachmentResponse{
				ID:        *items[i].StickerID,
				Type:      "sticker",
				StickerID: *items[i].StickerID,
			})
		}
	}

	placeholders := make([]string, len(commentIDs))
	for i := range placeholders {
		placeholders[i] = fmt.Sprintf("$%d", i+1)
	}

	query := fmt.Sprintf(`
		SELECT cm.comment_id, ma.id, ma.mime_type, ma.width, ma.height, ma.original_name, ma.object_key
		FROM comment_media cm
		JOIN media_assets ma ON ma.id = cm.media_id
		WHERE cm.comment_id IN (%s) AND ma.status = 'ready' AND ma.deleted_at IS NULL
		ORDER BY cm.comment_id ASC, cm.sort_order ASC, ma.id ASC`, strings.Join(placeholders, ", "))

	rows, err := db.QueryContext(ctx, query, commentIDs...)
	if err != nil {
		return err
	}
	defer rows.Close()

	type mediaWithKey struct {
		commentID string
		media     postMediaResponse
		objectKey string
	}
	mediaList := make([]mediaWithKey, 0)
	mediaIDs := make([]any, 0)
	seenMedia := make(map[string]struct{})

	for rows.Next() {
		var mk mediaWithKey
		if err := rows.Scan(&mk.commentID, &mk.media.ID, &mk.media.MimeType, &mk.media.Width, &mk.media.Height, &mk.media.AltText, &mk.objectKey); err != nil {
			return err
		}
		if strings.HasPrefix(mk.media.MimeType, "video/") {
			mk.media.Type = "video"
		} else {
			mk.media.Type = "image"
		}
		mk.media.URL = publicMediaURL(mk.objectKey)
		mediaList = append(mediaList, mk)
		if _, ok := seenMedia[mk.media.ID]; !ok {
			seenMedia[mk.media.ID] = struct{}{}
			mediaIDs = append(mediaIDs, mk.media.ID)
		}
	}
	if err := rows.Err(); err != nil {
		return err
	}
	_ = rows.Close()

	variantsMap := make(map[string]map[string]*mediaVariantResponse)
	if len(mediaIDs) > 0 {
		vPlaceholders := make([]string, len(mediaIDs))
		for i := range vPlaceholders {
			vPlaceholders[i] = fmt.Sprintf("$%d", i+1)
		}
		vQuery := fmt.Sprintf(`
			SELECT mv.media_id, mv.variant, mv.object_key, mv.mime_type, mv.width, mv.height, mv.size_bytes
			FROM media_variants mv
			WHERE mv.media_id IN (%s) AND mv.status = 'ready'`, strings.Join(vPlaceholders, ", "))
		vRows, err := db.QueryContext(ctx, vQuery, mediaIDs...)
		if err == nil {
			for vRows.Next() {
				var mid, variant, objKey, mimeType string
				var width, height int
				var sizeBytes int64
				if err := vRows.Scan(&mid, &variant, &objKey, &mimeType, &width, &height, &sizeBytes); err == nil {
					if variantsMap[mid] == nil {
						variantsMap[mid] = make(map[string]*mediaVariantResponse)
					}
					variantsMap[mid][variant] = &mediaVariantResponse{
						URL:       gatewayMediaURL(mid, variant),
						Width:     width,
						Height:    height,
						SizeBytes: sizeBytes,
						MimeType:  mimeType,
					}
				}
			}
			vRows.Close()
		}
	}

	for _, mk := range mediaList {
		idx, ok := idToIdx[mk.commentID]
		if !ok {
			continue
		}
		m := mk.media
		if vmap, ok := variantsMap[m.ID]; ok {
			// 与 Feed 相同的 fail-closed 语义：存在打码变体就绝不回退未打码
			// 源图/普通变体；URL 统一改指变体，backfill 后旧源地址会被拒绝。
			m.Thumb = vmap["censored_thumb"]
			m.Detail = vmap["censored_detail"]
			m.Original = vmap["censored_original"]
			if m.Thumb == nil && m.Detail == nil && m.Original == nil {
				m.Thumb = vmap["thumb"]
				m.Detail = vmap["detail"]
				m.Original = vmap["original"]
			}
			switch {
			case m.Detail != nil:
				m.URL = m.Detail.URL
			case m.Thumb != nil:
				m.URL = m.Thumb.URL
			case m.Original != nil:
				m.URL = m.Original.URL
			case vmap["censored_thumb"] != nil || vmap["censored_detail"] != nil || vmap["censored_original"] != nil:
				m.URL = ""
			}
		}
		if m.Thumb == nil && m.URL != "" {
			m.Thumb = &mediaVariantResponse{
				URL:      m.URL,
				Width:    m.Width,
				Height:   m.Height,
				MimeType: m.MimeType,
			}
		}
		items[idx].Media = append(items[idx].Media, m)
		thumbURL := m.URL
		if m.Thumb != nil && m.Thumb.URL != "" {
			thumbURL = m.Thumb.URL
		}
		items[idx].Attachments = append(items[idx].Attachments, commentAttachmentResponse{
			ID:           m.ID,
			Type:         m.Type,
			URL:          m.URL,
			ThumbnailURL: thumbURL,
			Width:        m.Width,
			Height:       m.Height,
		})
	}
	return nil
}

func sliceContains(slice []string, target string) bool {
	for _, s := range slice {
		if s == target {
			return true
		}
	}
	return false
}

type userSummaryQueryer interface {
	QueryRowContext(context.Context, string, ...any) *sql.Row
}

// enrichReplyToUser 返回回复目标的稳定快照，前端可以直接渲染真实昵称。
// 目标用户被删除时保留 reply_to_user_id，但不阻断整条评论返回。
func enrichReplyToUser(ctx context.Context, queryer userSummaryQueryer, item *commentResponse) error {
	if item == nil || item.ReplyToUserID == nil || *item.ReplyToUserID == "" {
		return nil
	}
	summary, err := loadUserSummary(ctx, queryer, *item.ReplyToUserID)
	if err != nil {
		return err
	}
	item.ReplyToUser = summary
	return nil
}

func loadUserSummary(ctx context.Context, queryer userSummaryQueryer, userID string) (*userSummary, error) {
	var summary userSummary
	var objectKey string
	err := queryer.QueryRowContext(ctx, `
		SELECT u.id, u.username, COALESCE(up.nickname, u.username),
		       COALESCE(up.level, 1), COALESCE(up.avatar_media_id, ''),
		       COALESCE(ma.object_key, '')
		FROM users u
		LEFT JOIN user_profiles up ON up.user_id = u.id
		LEFT JOIN media_assets ma ON ma.id = up.avatar_media_id
		WHERE u.id = $1 AND u.deleted_at IS NULL`, userID).Scan(
		&summary.ID, &summary.Username, &summary.Nickname, &summary.Level, &summary.AvatarMediaID, &objectKey,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	if objectKey != "" {
		summary.AvatarURL = mediaVariantURL(summary.AvatarMediaID, objectKey, "thumb")
	}
	return &summary, nil
}

func (s *Server) updateComment(w http.ResponseWriter, r *http.Request, commentID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	var input commentInput
	if err := decodeJSON(r, &input); err != nil {
		writeAuthError(w, r, ErrInvalidComment)
		return
	}
	input.Content = strings.TrimSpace(input.Content)
	if input.Content == "" || len([]rune(input.Content)) > 5000 {
		writeAuthError(w, r, ErrInvalidComment)
		return
	}
	var authorID string
	err := s.db.QueryRowContext(r.Context(), `SELECT author_id FROM comments WHERE id = $1 AND deleted_at IS NULL`, commentID).Scan(&authorID)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrCommentNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if authorID != user.ID {
		writeAuthError(w, r, ErrForbidden)
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	result, err := tx.ExecContext(r.Context(), `UPDATE comments SET content = $1, updated_at = now() WHERE id = $2 AND deleted_at IS NULL`, input.Content, commentID)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if affected, affErr := result.RowsAffected(); affErr == nil && affected == 0 {
		writeAuthError(w, r, ErrCommentNotFound)
		return
	}
	// PATCH 与 create/GET 返回同一份完整 Comment DTO，客户端编辑后可直接替换本地状态。
	response, err := loadCommentResponseTx(r.Context(), tx, commentID, user.ID)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, response)
}

func (s *Server) deleteComment(w http.ResponseWriter, r *http.Request, commentID string) {
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
	var authorID string
	var deletedAt sql.NullTime
	err = tx.QueryRowContext(r.Context(), `SELECT author_id, deleted_at FROM comments WHERE id = $1 FOR UPDATE`, commentID).Scan(&authorID, &deletedAt)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrCommentNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if authorID != user.ID {
		writeAuthError(w, r, ErrForbidden)
		return
	}
	if !deletedAt.Valid {
		if _, err := softDeleteCommentTx(r.Context(), tx, commentID, user.ID, "", ""); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// softDeleteCommentTx 是用户删除和审核删除共用的计数守恒入口。
// 它只在首次软删除时扣减帖子/根评论聚合计数，重复调用不会重复扣减。
func softDeleteCommentTx(ctx context.Context, tx *sql.Tx, commentID, deletedBy, reason, caseID string) (bool, error) {
	var postID, rootID string
	var deletedAt sql.NullTime
	err := tx.QueryRowContext(ctx, `SELECT post_id, COALESCE(root_id, id), deleted_at FROM comments WHERE id = $1 FOR UPDATE`, commentID).Scan(&postID, &rootID, &deletedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return false, ErrCommentNotFound
	}
	if err != nil {
		return false, err
	}
	if deletedAt.Valid {
		return false, nil
	}
	result, err := tx.ExecContext(ctx, `UPDATE comments SET deleted_at = now(), publication_status = 'deleted', deleted_by = NULLIF($2, ''), delete_reason = $3, moderation_case_id = NULLIF($4, ''), updated_at = now() WHERE id = $1 AND deleted_at IS NULL`, commentID, deletedBy, strings.TrimSpace(reason), caseID)
	if err != nil {
		return false, err
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return false, err
	}
	if affected == 0 {
		return false, nil
	}
	if rootID != commentID {
		if _, err := tx.ExecContext(ctx, `UPDATE comments SET reply_count = GREATEST(reply_count - 1, 0), updated_at = now() WHERE id = $1`, rootID); err != nil {
			return false, err
		}
	}
	if _, err := tx.ExecContext(ctx, `UPDATE posts SET comment_count = GREATEST(comment_count - 1, 0), updated_at = now() WHERE id = $1`, postID); err != nil {
		return false, err
	}
	return true, nil
}

func encodeCommentCursor(cursor commentCursor) (string, error) {
	data, err := json.Marshal(cursor)
	if err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(data), nil
}

func decodeCommentCursor(value string) (commentCursor, error) {
	data, err := base64.RawURLEncoding.DecodeString(value)
	if err != nil {
		return commentCursor{}, err
	}
	var cursor commentCursor
	if err := json.Unmarshal(data, &cursor); err != nil || cursor.ID == "" || cursor.CreatedAt.IsZero() {
		return commentCursor{}, errors.New("invalid comment cursor")
	}
	return cursor, nil
}

func optionalString(value string) *string {
	if value == "" {
		return nil
	}
	copy := value
	return &copy
}
