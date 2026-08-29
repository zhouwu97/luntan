package api

import (
	"context"
	"database/sql"
	"net/http"
	"os"
	"strings"

	"github.com/zhouwu97/luntan/server/internal/auth"
)

type mediaVariantResponse struct {
	URL       string `json:"url"`
	Width     int    `json:"width"`
	Height    int    `json:"height"`
	SizeBytes int64  `json:"size,omitempty"`
	MimeType  string `json:"mime_type,omitempty"`
}

type postMediaResponse struct {
	ID       string                `json:"id"`
	Type     string                `json:"type"`
	URL      string                `json:"url,omitempty"`
	Width    int                   `json:"width"`
	Height   int                   `json:"height"`
	AltText  string                `json:"alt_text,omitempty"`
	MimeType string                `json:"mime_type,omitempty"`
	Thumb    *mediaVariantResponse `json:"thumb,omitempty"`
	Detail   *mediaVariantResponse `json:"detail,omitempty"`
	Original *mediaVariantResponse `json:"original,omitempty"`
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
		SELECT ma.id, ma.mime_type, ma.width, ma.height, ma.original_name, ma.object_key
		FROM post_media pm
		JOIN media_assets ma ON ma.id = pm.media_id
		WHERE pm.post_id = $1 AND ma.status = 'ready' AND ma.deleted_at IS NULL
		ORDER BY pm.sort_order ASC, ma.id ASC`, response.ID)
	if err != nil {
		return err
	}
	defer rows.Close()
	type mediaItemWithKey struct {
		item      postMediaResponse
		objectKey string
	}
	items := make([]mediaItemWithKey, 0)
	for rows.Next() {
		var it mediaItemWithKey
		if err := rows.Scan(&it.item.ID, &it.item.MimeType, &it.item.Width, &it.item.Height, &it.item.AltText, &it.objectKey); err != nil {
			return err
		}
		if strings.HasPrefix(it.item.MimeType, "video/") {
			it.item.Type = "video"
		} else {
			it.item.Type = "image"
		}
		it.item.URL = publicMediaURL(it.objectKey)
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
						URL:       publicMediaURL(objKey),
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
			if vmap, ok := variantsMap[item.ID]; ok {
				item.Thumb = vmap["thumb"]
				item.Detail = vmap["detail"]
				item.Original = vmap["original"]
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
			response.Media = append(response.Media, item)
		}
	}

	response.Author.Level = 1
	if err := s.db.QueryRowContext(ctx, `
		SELECT CASE WHEN u.account_type = 'guest' THEN 0 ELSE COALESCE(up.level, 1) END
		FROM users u
		LEFT JOIN user_profiles up ON up.user_id = u.id
		WHERE u.id = $1`, response.Author.ID).Scan(&response.Author.Level); err != nil && err != sql.ErrNoRows {
		return err
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
	token, hasToken := bearerToken(r.Header.Get("Authorization"))
	if !hasToken {
		return auth.User{}, false
	}
	user, err := s.authService.Me(ctx, token)
	if err != nil {
		return auth.User{}, false
	}
	return user, true
}

func publicMediaURL(objectKey string) string {
	// 历史导入包曾把完整媒体 URL 写入 object_key；保留该 URL，避免再拼接公开前缀。
	if strings.HasPrefix(objectKey, "http://") || strings.HasPrefix(objectKey, "https://") {
		return objectKey
	}
	base := strings.TrimRight(strings.TrimSpace(os.Getenv("OBJECT_STORAGE_PUBLIC_BASE_URL")), "/")
	if base == "" {
		return objectKey
	}
	return base + "/" + strings.TrimLeft(objectKey, "/")
}

func includePostDetails(r *http.Request) bool {
	return r.URL.Query().Get("include_details") == "1"
}
