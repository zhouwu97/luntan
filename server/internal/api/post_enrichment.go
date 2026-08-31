package api

import (
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/url"
	"os"
	"strings"

	"github.com/zhouwu97/luntan/server/internal/auth"
	"github.com/zhouwu97/luntan/server/internal/media"
)

type mediaVariantResponse struct {
	URL       string `json:"url"`
	Width     int    `json:"width"`
	Height    int    `json:"height"`
	SizeBytes int64  `json:"size,omitempty"`
	MimeType  string `json:"mime_type,omitempty"`
}

type postMediaResponse struct {
	ID               string                `json:"id"`
	Type             string                `json:"type"`
	URL              string                `json:"url,omitempty"`
	Width            int                   `json:"width"`
	Height           int                   `json:"height"`
	AltText          string                `json:"alt_text,omitempty"`
	MimeType         string                `json:"mime_type,omitempty"`
	ModerationStatus string                `json:"moderation_status,omitempty"`
	MaskRegions      []media.MaskRegion    `json:"mask_regions,omitempty"`
	Thumb            *mediaVariantResponse `json:"thumb,omitempty"`
	Detail           *mediaVariantResponse `json:"detail,omitempty"`
	Original         *mediaVariantResponse `json:"original,omitempty"`
}

type viewerPostState struct {
	HasLiked             bool `json:"has_liked"`
	HasBookmarked        bool `json:"has_bookmarked"`
	IsFollowingAuthor    bool `json:"is_following_author"`
	IsFollowingCommunity bool `json:"is_following_community"`
	IsCommunityMember    bool `json:"is_community_member"`
	CanEdit              bool `json:"can_edit"`
	CanDelete            bool `json:"can_delete"`
	CanReport            bool `json:"can_report"`
}

// enrichPostResponse 只在客户端明确请求 include_details=1 时执行，保持旧
// 的轻量 Feed 查询与已有运维/SQL mock 兼容，同时让移动端拿到可渲染的图片
// 元数据和当前用户状态。
func (s *Server) enrichPostResponse(ctx context.Context, r *http.Request, response *postResponse, includeViewer bool) error {
	rows, err := s.db.QueryContext(ctx, `
		SELECT ma.id, ma.mime_type, ma.width, ma.height, ma.original_name, ma.object_key,
		       COALESCE(ma.moderation_status, 'normal'), COALESCE(ma.mask_regions::text, '[]')
		FROM post_media pm
		JOIN media_assets ma ON ma.id = pm.media_id
		WHERE pm.post_id = $1 AND ma.status = 'ready' AND ma.deleted_at IS NULL
		ORDER BY pm.sort_order ASC, ma.id ASC`, response.ID)
	if err != nil {
		return err
	}
	defer rows.Close()
	type mediaItemWithKey struct {
		item             postMediaResponse
		objectKey        string
		moderationStatus string
		rawMaskRegions   string
	}
	items := make([]mediaItemWithKey, 0)
	for rows.Next() {
		var it mediaItemWithKey
		if err := rows.Scan(&it.item.ID, &it.item.MimeType, &it.item.Width, &it.item.Height, &it.item.AltText, &it.objectKey, &it.moderationStatus, &it.rawMaskRegions); err != nil {
			return err
		}
		if strings.HasPrefix(it.item.MimeType, "video/") {
			it.item.Type = "video"
		} else {
			it.item.Type = "image"
		}
		it.item.ModerationStatus = it.moderationStatus
		// censored 媒体的源 object key 永远不进入公开响应；后面的逻辑只会
		// 选择 censored_* 变体。这样即使对象存储配置了公开前缀，Feed
		// 也不会继续给出原图直链。
		if it.moderationStatus != "censored" {
			it.item.URL = publicMediaURL(it.objectKey)
		}
		if it.rawMaskRegions != "" && it.rawMaskRegions != "[]" {
			var regions []media.MaskRegion
			if jsonErr := json.Unmarshal([]byte(it.rawMaskRegions), &regions); jsonErr == nil {
				it.item.MaskRegions = regions
			}
		}
		items = append(items, it)
	}
	if err := rows.Err(); err != nil {
		return err
	}
	_ = rows.Close()

	if len(items) > 0 {
		variantsMap := make(map[string]map[string]*mediaVariantResponse)
		vRows, err := s.db.QueryContext(ctx, `
			SELECT mv.media_id, mv.variant, mv.object_key, mv.mime_type, mv.width, mv.height, mv.size_bytes
			FROM media_variants mv
			JOIN post_media pm ON pm.media_id = mv.media_id
			WHERE pm.post_id = $1 AND mv.status = 'ready'`, response.ID)
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
		for _, it := range items {
			item := it.item
			isCensored := it.moderationStatus == "censored"
			vmap := variantsMap[item.ID]

			if isCensored {
				// 严格 fail-closed：打码图片若缺少打码变体，绝对禁止回退未打码原图/普通变体
				if vmap != nil {
					item.Thumb = vmap["censored_thumb"]
					item.Detail = vmap["censored_detail"]
					item.Original = vmap["censored_original"]
				} else {
					item.Thumb = nil
					item.Detail = nil
					item.Original = nil
				}
				if item.Detail != nil {
					item.URL = item.Detail.URL
				} else if item.Thumb != nil {
					item.URL = item.Thumb.URL
				} else if item.Original != nil {
					item.URL = item.Original.URL
				} else {
					item.URL = "" // 无有效打码变体时不输出任何可能泄漏原图的 URL
				}
			} else {
				if vmap != nil {
					item.Thumb = vmap["thumb"]
					item.Detail = vmap["detail"]
					item.Original = vmap["original"]
					// 有受控变体时 URL 指向变体而非源图；backfill 完成后旧
					// objectKey 源地址会被网关拒绝，这里必须同步切换。
					if item.Detail != nil {
						item.URL = item.Detail.URL
					} else if item.Thumb != nil {
						item.URL = item.Thumb.URL
					} else if item.Original != nil {
						item.URL = item.Original.URL
					}
				}
				if item.Thumb == nil && item.URL != "" {
					item.Thumb = &mediaVariantResponse{
						URL:      item.URL,
						Width:    item.Width,
						Height:   item.Height,
						MimeType: item.MimeType,
					}
				}
				if item.Detail == nil && item.URL != "" {
					item.Detail = &mediaVariantResponse{
						URL:      item.URL,
						Width:    item.Width,
						Height:   item.Height,
						MimeType: item.MimeType,
					}
				}
				if item.Original == nil && item.URL != "" {
					item.Original = &mediaVariantResponse{
						URL:      item.URL,
						Width:    item.Width,
						Height:   item.Height,
						MimeType: item.MimeType,
					}
				}
				if item.URL == "" {
					if item.Detail != nil {
						item.URL = item.Detail.URL
					} else if item.Thumb != nil {
						item.URL = item.Thumb.URL
					} else if item.Original != nil {
						item.URL = item.Original.URL
					}
				}
			}
			response.Media = append(response.Media, item)
		}
	}

	var hotSuppressed bool
	var hotSuppressedReason, hotSuppressedBy sql.NullString
	var hotSuppressedAt sql.NullTime
	if err := s.db.QueryRowContext(ctx, `SELECT COALESCE(hot_suppressed, false), COALESCE(hot_suppressed_reason, ''), hot_suppressed_at, COALESCE(hot_suppressed_by, '') FROM posts WHERE id = $1`, response.ID).Scan(&hotSuppressed, &hotSuppressedReason, &hotSuppressedAt, &hotSuppressedBy); err == nil {
		viewer, hasViewer := s.optionalAuthenticatedUser(ctx, r)
		isAdmin := hasViewer && s.canModerate(r, viewer)

		if isAdmin {
			response.HotSuppressed = hotSuppressed
			if hotSuppressedReason.Valid {
				response.HotSuppressedReason = hotSuppressedReason.String
			}
			if hotSuppressedAt.Valid {
				response.HotSuppressedAt = &hotSuppressedAt.Time
			}
			if hotSuppressedBy.Valid {
				response.HotSuppressedBy = hotSuppressedBy.String
			}
		} else {
			response.HotSuppressed = false
			response.HotSuppressedReason = ""
			response.HotSuppressedAt = nil
			response.HotSuppressedBy = ""
		}
	}

	response.Author.Level = 1
	var avatarMediaID, objectKey sql.NullString
	if err := s.db.QueryRowContext(ctx, `
		SELECT CASE WHEN u.account_type = 'guest' THEN 0 ELSE COALESCE(up.level, 1) END,
		       COALESCE(up.avatar_media_id, ''),
		       COALESCE(ma.object_key, '')
		FROM users u
		LEFT JOIN user_profiles up ON up.user_id = u.id
		LEFT JOIN media_assets ma ON ma.id = up.avatar_media_id AND ma.status = 'ready' AND ma.deleted_at IS NULL
		WHERE u.id = $1`, response.Author.ID).Scan(&response.Author.Level, &avatarMediaID, &objectKey); err != nil && err != sql.ErrNoRows {
		return err
	}
	if avatarMediaID.Valid && avatarMediaID.String != "" {
		response.Author.AvatarMediaID = avatarMediaID.String
	}
	if objectKey.Valid && objectKey.String != "" {
		response.Author.AvatarURL = mediaVariantURL(avatarMediaID.String, objectKey.String, "thumb")
	}
	if !includeViewer {
		return nil
	}
	// 公开 Feed 允许无 token 访问；无效 token 不阻断内容读取，只是不返回
	// viewer_state。
	viewer, ok := s.optionalAuthenticatedUser(ctx, r)
	if !ok {
		return nil
	}
	var state viewerPostState
	err = s.db.QueryRowContext(ctx, `
		SELECT
			EXISTS (SELECT 1 FROM post_reactions WHERE post_id = $1 AND user_id = $2),
			EXISTS (SELECT 1 FROM bookmarks WHERE post_id = $1 AND user_id = $2),
			EXISTS (SELECT 1 FROM user_follows WHERE follower_id = $2 AND followee_id = $3),
			EXISTS (SELECT 1 FROM community_follows WHERE community_id = $4 AND user_id = $2),
			EXISTS (SELECT 1 FROM community_members WHERE community_id = $4 AND user_id = $2)
	`, response.ID, viewer.ID, response.Author.ID, response.Community.ID).Scan(
		&state.HasLiked,
		&state.HasBookmarked,
		&state.IsFollowingAuthor,
		&state.IsFollowingCommunity,
		&state.IsCommunityMember,
	)
	if err != nil {
		return err
	}
	state.CanEdit = viewer.ID == response.Author.ID
	state.CanDelete = state.CanEdit
	state.CanReport = capabilitiesForUser(viewer)[capReport] && viewer.ID != response.Author.ID
	response.ViewerState = &state
	return nil
}

func (s *Server) optionalAuthenticatedUser(ctx context.Context, r *http.Request) (user auth.User, ok bool) {
	if user, ok := r.Context().Value(authenticatedUserContextKey{}).(auth.User); ok {
		return user, true
	}
	token, hasToken := bearerToken(r.Header.Get("Authorization"))
	if !hasToken || s == nil || s.authService == nil {
		return auth.User{}, false
	}
	user, err := s.authService.Me(ctx, token)
	if err != nil {
		return auth.User{}, false
	}
	return user, true
}

func publicMediaURL(objectKey string) string {
	base := strings.TrimRight(strings.TrimSpace(os.Getenv("OBJECT_STORAGE_PUBLIC_BASE_URL")), "/")
	// 历史导入包曾把完整媒体 URL 写入 object_key。自有媒体如果仍指向
	// HTTP/IP 源站，Web 会触发 mixed content，Android 也会被明文策略拦截；
	// 只替换自有媒体路径的 scheme/host，外部资源和其他绝对 URL 保持不变。
	if parsed, err := url.Parse(objectKey); err == nil && parsed.IsAbs() {
		if normalized := normalizeAbsoluteMediaURL(parsed, base); normalized != "" {
			return normalized
		}
		return objectKey
	}
	key := strings.TrimLeft(objectKey, "/")
	// 用户上传媒体的源图和派生图统一走应用媒体路由。对象存储公开前缀
	// 只适用于 ranking/imported 等已明确公开的资源，不能成为 media/ 下
	// 原图的第二条绕过审核鉴权的路径。
	if strings.HasPrefix(key, "media/") {
		return "/api/v1/media-file/" + key
	}
	if base != "" {
		return base + "/" + key
	}
	// 未配置对象存储公开域名时退回 API 自带的媒体下载兜底路由；根相对
	// 地址由客户端按 API base 补全，浏览器同源访问时也能直接命中。
	return "/api/v1/media-file/" + key
}

// gatewayMediaURL 受控网关形态地址；客户端不接触内部 objectKey。
func gatewayMediaURL(mediaID, variant string) string {
	return "/api/v1/media-file/" + mediaID + "/" + variant
}

// mediaVariantURL 优先下发 {mediaID}/{variant} 网关地址；媒体 ID 缺失时
// 回退历史 objectKey 形态，作为 media-backfill 完成前的过渡兜底。
func mediaVariantURL(mediaID, objectKey, variant string) string {
	if mediaID != "" {
		return gatewayMediaURL(mediaID, variant)
	}
	if objectKey == "" {
		return ""
	}
	return publicMediaURL(objectKey)
}

func normalizeAbsoluteMediaURL(mediaURL *url.URL, publicBase string) string {
	baseURL, err := url.Parse(publicBase)
	if err != nil || baseURL.Scheme != "https" || baseURL.Host == "" {
		return ""
	}
	if (mediaURL.Scheme != "http" && mediaURL.Scheme != "https") ||
		!isAppMediaPath(mediaURL.Path) {
		return ""
	}
	mediaURL.Scheme = baseURL.Scheme
	mediaURL.Host = baseURL.Host
	mediaURL.User = nil
	return mediaURL.String()
}

func isAppMediaPath(path string) bool {
	return strings.HasPrefix(path, "/imported-media/") ||
		strings.HasPrefix(path, "/api/v1/media-file/")
}

func includePostDetails(r *http.Request) bool {
	return r.URL.Query().Get("include_details") == "1"
}
