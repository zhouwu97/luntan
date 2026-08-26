package api

import (
	"database/sql"
	"net/http"

	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

type communityCategoryResponse struct {
	ID        string `json:"id"`
	ParentID  string `json:"parent_id,omitempty"`
	Name      string `json:"name"`
	Slug      string `json:"slug"`
	Icon      string `json:"icon,omitempty"`
	SortOrder int    `json:"sort_order"`
	Status    string `json:"status"`
}

type communityResponse struct {
	ID             string         `json:"id"`
	CategoryID     string         `json:"category_id"`
	Slug           string         `json:"slug"`
	Name           string         `json:"name"`
	Description    string         `json:"description"`
	AvatarMediaID  string         `json:"avatar_media_id,omitempty"`
	BannerMediaID  string         `json:"banner_media_id,omitempty"`
	Visibility     string         `json:"visibility"`
	JoinPolicy     string         `json:"join_policy"`
	Status         string         `json:"status"`
	MemberCount    int64          `json:"member_count"`
	FollowerCount  int64          `json:"follower_count"`
	PostCount      int64          `json:"post_count"`
	SortOrder      int            `json:"sort_order"`
	CanPublish     bool           `json:"can_publish"`
	CanUploadMedia bool           `json:"can_upload_media"`
	CanCreatePoll  bool           `json:"can_create_poll"`
	ViewerState    map[string]any `json:"viewer_state,omitempty"`
}

func (s *Server) listCategories(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	status := r.URL.Query().Get("status")
	rows, err := s.db.QueryContext(r.Context(), `
		SELECT id, COALESCE(parent_id, ''), name, slug, COALESCE(icon, ''), sort_order, status
		FROM community_categories
		WHERE ($1 = '' OR status = $1)
		ORDER BY sort_order ASC, id ASC`, status)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()
	items := make([]communityCategoryResponse, 0)
	for rows.Next() {
		var item communityCategoryResponse
		if err := rows.Scan(&item.ID, &item.ParentID, &item.Name, &item.Slug, &item.Icon, &item.SortOrder, &item.Status); err != nil {
			writeInternalError(w, r, err)
			return
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (s *Server) listCommunities(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	categoryID := r.URL.Query().Get("category_id")
	status := r.URL.Query().Get("status")
	canPublish := r.URL.Query().Get("can_publish") == "true"
	publishAllowed, uploadAllowed, pollAllowed := false, false, false
	if viewer, ok := s.optionalAuthenticatedUser(r.Context(), r); ok {
		caps := capabilitiesForUser(viewer)
		publishAllowed = caps[capPublish]
		uploadAllowed = caps[capUploadMedia]
		pollAllowed = caps[capCreatePoll]
	}
	if canPublish && !publishAllowed {
		// 发布候选社区属于已登录能力；游客即使能浏览，也不应拿到可发布标记。
		httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": []communityResponse{}})
		return
	}
	query := `
		SELECT id, category_id, slug, name, description, COALESCE(avatar_media_id, ''), COALESCE(banner_media_id, ''), visibility, join_policy, status, member_count, follower_count, post_count, sort_order
		FROM communities
		WHERE deleted_at IS NULL AND ($1 = '' OR category_id = $1) AND ($2 = '' OR status = $2)
	`
	args := []any{categoryID, status}
	if canPublish {
		// 发布页只接收当前可写入的社区；权限细分仍由发帖事务再次校验。
		query += " AND status = 'active'"
	}
	query += " ORDER BY sort_order ASC, id ASC"
	rows, err := s.db.QueryContext(r.Context(), query, args...)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()
	items, err := scanCommunities(rows, publishAllowed, uploadAllowed, pollAllowed)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (s *Server) getCommunity(w http.ResponseWriter, r *http.Request, id string) {
	if !s.requireDatabase(w, r) {
		return
	}
	var item communityResponse
	err := s.db.QueryRowContext(r.Context(), `
		SELECT id, category_id, slug, name, description, COALESCE(avatar_media_id, ''), COALESCE(banner_media_id, ''), visibility, join_policy, status, member_count, follower_count, post_count, sort_order
		FROM communities
		WHERE id = $1 AND deleted_at IS NULL`, id).Scan(&item.ID, &item.CategoryID, &item.Slug, &item.Name, &item.Description, &item.AvatarMediaID, &item.BannerMediaID, &item.Visibility, &item.JoinPolicy, &item.Status, &item.MemberCount, &item.FollowerCount, &item.PostCount, &item.SortOrder)
	if err == sql.ErrNoRows {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusNotFound, Code: "NOT_FOUND", Message: "社区不存在"})
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if viewer, ok := s.optionalAuthenticatedUser(r.Context(), r); ok {
		caps := capabilitiesForUser(viewer)
		item.CanPublish = item.Status == "active" && caps[capPublish]
		item.CanUploadMedia = item.Status == "active" && caps[capUploadMedia]
		item.CanCreatePoll = item.Status == "active" && caps[capCreatePoll]
		item.ViewerState = map[string]any{}
		var isFollowing, isMember bool
		if err := s.db.QueryRowContext(r.Context(), `
			SELECT EXISTS (SELECT 1 FROM community_follows WHERE user_id = $1 AND community_id = $2),
			       EXISTS (SELECT 1 FROM community_members WHERE user_id = $1 AND community_id = $2 AND status = 'active')`, viewer.ID, item.ID).
			Scan(&isFollowing, &isMember); err != nil {
			writeInternalError(w, r, err)
			return
		}
		item.ViewerState["is_following"] = isFollowing
		item.ViewerState["is_member"] = isMember
	} else {
		item.CanPublish = false
		item.CanUploadMedia = false
		item.CanCreatePoll = false
	}
	httpserver.WriteJSON(w, http.StatusOK, item)
}

func scanCommunities(rows *sql.Rows, publishAllowed, uploadAllowed, pollAllowed bool) ([]communityResponse, error) {
	items := make([]communityResponse, 0)
	for rows.Next() {
		var item communityResponse
		if err := rows.Scan(&item.ID, &item.CategoryID, &item.Slug, &item.Name, &item.Description, &item.AvatarMediaID, &item.BannerMediaID, &item.Visibility, &item.JoinPolicy, &item.Status, &item.MemberCount, &item.FollowerCount, &item.PostCount, &item.SortOrder); err != nil {
			return nil, err
		}
		item.CanPublish = item.Status == "active" && publishAllowed
		item.CanUploadMedia = item.Status == "active" && uploadAllowed
		item.CanCreatePoll = item.Status == "active" && pollAllowed
		items = append(items, item)
	}
	return items, rows.Err()
}
