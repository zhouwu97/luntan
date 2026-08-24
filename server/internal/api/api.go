package api

import (
	"database/sql"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"

	"github.com/zhouwu97/luntan/server/internal/auth"
	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

type Server struct {
	db           *sql.DB
	authService  *auth.Service
	mediaStorage mediaStorage
	pointRewards PointRewardRules
}

func NewHandler(db *sql.DB, authServices ...*auth.Service) http.Handler {
	authService := auth.NewService(db)
	if len(authServices) > 0 && authServices[0] != nil {
		authService = authServices[0]
	}
	return &Server{db: db, authService: authService, mediaStorage: newObjectStorageFromEnv(), pointRewards: pointRewardRulesFromEnv()}
}

func NewHandlerWithMedia(db *sql.DB, authService *auth.Service, storage mediaStorage) http.Handler {
	if authService == nil {
		authService = auth.NewService(db)
	}
	if storage == nil {
		storage = unavailableMediaStorage{}
	}
	return &Server{db: db, authService: authService, mediaStorage: storage, pointRewards: pointRewardRulesFromEnv()}
}

// NewHandlerWithPointRewards 供集成测试和灰度环境显式注入奖励配置。
func NewHandlerWithPointRewards(db *sql.DB, rules PointRewardRules) http.Handler {
	server := NewHandler(db).(*Server)
	server.pointRewards = rules
	return server
}

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimSuffix(r.URL.Path, "/")
	switch {
	case r.Method == http.MethodPost && path == "/api/v1/auth/register":
		s.register(w, r)
		return
	case r.Method == http.MethodPost && path == "/api/v1/auth/login":
		s.login(w, r)
		return
	case r.Method == http.MethodPost && path == "/api/v1/auth/refresh":
		s.refresh(w, r)
		return
	case r.Method == http.MethodPost && path == "/api/v1/auth/logout":
		s.logout(w, r)
		return
	case r.Method == http.MethodGet && path == "/api/v1/me":
		s.me(w, r)
		return
	case r.Method == http.MethodGet && path == "/api/v1/me/profile":
		s.profile(w, r)
		return
	case r.Method == http.MethodGet && path == "/api/v1/me/bookmark-folders":
		s.listBookmarkFolders(w, r)
		return
	case r.Method == http.MethodPost && path == "/api/v1/me/bookmark-folders":
		s.createBookmarkFolder(w, r)
		return
	case r.Method == http.MethodGet && strings.HasPrefix(path, "/api/v1/me/bookmark-folders/") && strings.HasSuffix(path, "/posts"):
		folderID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/me/bookmark-folders/"), "/posts")
		s.listBookmarkFolderPosts(w, r, folderID)
		return
	case r.Method == http.MethodPatch && strings.HasPrefix(path, "/api/v1/me/bookmark-folders/"):
		s.updateBookmarkFolder(w, r, strings.TrimPrefix(path, "/api/v1/me/bookmark-folders/"))
		return
	case r.Method == http.MethodDelete && strings.HasPrefix(path, "/api/v1/me/bookmark-folders/"):
		s.deleteBookmarkFolder(w, r, strings.TrimPrefix(path, "/api/v1/me/bookmark-folders/"))
		return
	case r.Method == http.MethodGet && isProfileListPath(path):
		s.profileList(w, r, strings.TrimPrefix(path, "/api/v1/me/"))
		return
	case r.Method == http.MethodDelete && path == "/api/v1/me/history":
		s.clearHistory(w, r)
		return
	case r.Method == http.MethodDelete && path == "/api/v1/me":
		s.deleteAccount(w, r)
		return
	case r.Method == http.MethodPost && path == "/api/v1/posts":
		s.createPost(w, r)
		return
	case r.Method == http.MethodPost && path == "/api/v1/store/orders":
		s.createStoreOrder(w, r)
		return
	case r.Method == http.MethodPatch && strings.HasPrefix(path, "/api/v1/posts/"):
		s.updatePost(w, r, strings.TrimPrefix(path, "/api/v1/posts/"))
		return
	case r.Method == http.MethodPut && strings.HasPrefix(path, "/api/v1/posts/") && strings.HasSuffix(path, "/like"):
		s.togglePostLike(w, r, strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/posts/"), "/like"), true)
		return
	case r.Method == http.MethodDelete && strings.HasPrefix(path, "/api/v1/posts/") && strings.HasSuffix(path, "/like"):
		s.togglePostLike(w, r, strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/posts/"), "/like"), false)
		return
	case r.Method == http.MethodGet && strings.HasPrefix(path, "/api/v1/posts/") && strings.HasSuffix(path, "/bookmark-folders"):
		s.getPostBookmarkFolders(w, r, strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/posts/"), "/bookmark-folders"))
		return
	case r.Method == http.MethodPut && strings.HasPrefix(path, "/api/v1/posts/") && strings.HasSuffix(path, "/bookmark-folders"):
		s.setPostBookmarkFolders(w, r, strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/posts/"), "/bookmark-folders"))
		return
	case r.Method == http.MethodPut && strings.HasPrefix(path, "/api/v1/posts/") && strings.HasSuffix(path, "/bookmark"):
		s.toggleBookmark(w, r, strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/posts/"), "/bookmark"), true)
		return
	case r.Method == http.MethodDelete && strings.HasPrefix(path, "/api/v1/posts/") && strings.HasSuffix(path, "/bookmark"):
		s.toggleBookmark(w, r, strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/posts/"), "/bookmark"), false)
		return
	case r.Method == http.MethodDelete && strings.HasPrefix(path, "/api/v1/posts/"):
		s.deletePost(w, r, strings.TrimPrefix(path, "/api/v1/posts/"))
		return
	case r.Method == http.MethodPost && strings.HasPrefix(path, "/api/v1/posts/") && strings.HasSuffix(path, "/comments"):
		postID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/posts/"), "/comments")
		s.createComment(w, r, postID, "")
		return
	case r.Method == http.MethodPost && strings.HasPrefix(path, "/api/v1/posts/") && strings.HasSuffix(path, "/history"):
		postID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/posts/"), "/history")
		s.recordHistory(w, r, postID)
		return
	case r.Method == http.MethodPost && strings.HasPrefix(path, "/api/v1/posts/") && strings.HasSuffix(path, "/poll"):
		postID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/posts/"), "/poll")
		s.createPoll(w, r, postID)
		return
	case r.Method == http.MethodPost && strings.HasPrefix(path, "/api/v1/posts/") && strings.HasSuffix(path, "/market"):
		postID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/posts/"), "/market")
		s.createMarketItem(w, r, postID)
		return
	case r.Method == http.MethodPut && strings.HasPrefix(path, "/api/v1/polls/") && strings.HasSuffix(path, "/vote"):
		pollID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/polls/"), "/vote")
		s.votePoll(w, r, pollID)
		return
	case r.Method == http.MethodGet && strings.HasPrefix(path, "/api/v1/comments/") && strings.HasSuffix(path, "/replies"):
		commentID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/comments/"), "/replies")
		s.listCommentReplies(w, r, commentID)
		return
	case r.Method == http.MethodPost && strings.HasPrefix(path, "/api/v1/comments/") && strings.HasSuffix(path, "/replies"):
		commentID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/comments/"), "/replies")
		s.createReply(w, r, commentID)
		return
	case r.Method == http.MethodPatch && strings.HasPrefix(path, "/api/v1/comments/"):
		s.updateComment(w, r, strings.TrimPrefix(path, "/api/v1/comments/"))
		return
	case r.Method == http.MethodPut && strings.HasPrefix(path, "/api/v1/comments/") && strings.HasSuffix(path, "/like"):
		s.toggleCommentLike(w, r, strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/comments/"), "/like"), true)
		return
	case r.Method == http.MethodDelete && strings.HasPrefix(path, "/api/v1/comments/") && strings.HasSuffix(path, "/like"):
		s.toggleCommentLike(w, r, strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/comments/"), "/like"), false)
		return
	case r.Method == http.MethodDelete && strings.HasPrefix(path, "/api/v1/comments/"):
		s.deleteComment(w, r, strings.TrimPrefix(path, "/api/v1/comments/"))
		return
	case r.Method == http.MethodPut && strings.HasPrefix(path, "/api/v1/users/") && strings.HasSuffix(path, "/follow"):
		s.toggleUserFollow(w, r, strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/users/"), "/follow"), true)
		return
	case r.Method == http.MethodDelete && strings.HasPrefix(path, "/api/v1/users/") && strings.HasSuffix(path, "/follow"):
		s.toggleUserFollow(w, r, strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/users/"), "/follow"), false)
		return
	case r.Method == http.MethodPut && strings.HasPrefix(path, "/api/v1/communities/") && strings.HasSuffix(path, "/follow"):
		s.toggleCommunityFollow(w, r, strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/communities/"), "/follow"), true)
		return
	case r.Method == http.MethodDelete && strings.HasPrefix(path, "/api/v1/communities/") && strings.HasSuffix(path, "/follow"):
		s.toggleCommunityFollow(w, r, strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/communities/"), "/follow"), false)
		return
	case r.Method == http.MethodPut && strings.HasPrefix(path, "/api/v1/communities/") && strings.HasSuffix(path, "/membership"):
		s.toggleCommunityMembership(w, r, strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/communities/"), "/membership"), true)
		return
	case r.Method == http.MethodDelete && strings.HasPrefix(path, "/api/v1/communities/") && strings.HasSuffix(path, "/membership"):
		s.toggleCommunityMembership(w, r, strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/communities/"), "/membership"), false)
		return
	case r.Method == http.MethodPut && strings.HasPrefix(path, "/api/v1/users/") && strings.HasSuffix(path, "/block"):
		s.toggleBlock(w, r, strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/users/"), "/block"), true)
		return
	case r.Method == http.MethodDelete && strings.HasPrefix(path, "/api/v1/users/") && strings.HasSuffix(path, "/block"):
		s.toggleBlock(w, r, strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/users/"), "/block"), false)
		return
	case (r.Method == http.MethodPost || r.Method == http.MethodPatch) && path == "/api/v1/notifications/read-all":
		s.markAllNotificationsRead(w, r)
		return
	case r.Method == http.MethodGet && path == "/api/v1/notifications/unread-count":
		s.unreadNotificationCount(w, r)
		return
	case (r.Method == http.MethodPost || r.Method == http.MethodPatch) && strings.HasPrefix(path, "/api/v1/notifications/"):
		s.markNotificationRead(w, r, strings.TrimPrefix(path, "/api/v1/notifications/"))
		return
	case r.Method == http.MethodPost && path == "/api/v1/reports":
		s.createReport(w, r)
		return
	case r.Method == http.MethodPost && strings.HasPrefix(path, "/api/v1/moderation/cases/") && strings.HasSuffix(path, "/actions"):
		caseID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/moderation/cases/"), "/actions")
		s.createModerationAction(w, r, caseID)
		return
	case r.Method == http.MethodPost && path == "/api/v1/media/upload-token":
		s.createMediaUploadToken(w, r)
		return
	case r.Method == http.MethodPost && strings.HasPrefix(path, "/api/v1/media/") && strings.HasSuffix(path, "/complete"):
		mediaID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/media/"), "/complete")
		s.completeMedia(w, r, mediaID)
		return
	case r.Method == http.MethodDelete && strings.HasPrefix(path, "/api/v1/media/"):
		s.deleteMedia(w, r, strings.TrimPrefix(path, "/api/v1/media/"))
		return
	case strings.HasPrefix(path, "/api/v1/auth/") || strings.HasPrefix(path, "/api/v1/media/") || strings.HasPrefix(path, "/api/v1/comments/") || strings.HasPrefix(path, "/api/v1/users/") || strings.HasPrefix(path, "/api/v1/notifications/") || path == "/api/v1/me":
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusMethodNotAllowed, Code: "METHOD_NOT_ALLOWED", Message: "请求方法不支持"})
		return
	case r.Method != http.MethodGet:
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusMethodNotAllowed, Code: "METHOD_NOT_ALLOWED", Message: "请求方法不支持"})
		return
	}
	switch {
	case path == "/api/v1/community-categories":
		s.listCategories(w, r)
	case path == "/api/v1/communities":
		s.listCommunities(w, r)
	case strings.HasPrefix(path, "/api/v1/communities/"):
		s.getCommunity(w, r, strings.TrimPrefix(path, "/api/v1/communities/"))
	case path == "/api/v1/feed/latest":
		s.latestFeed(w, r)
	case path == "/api/v1/home":
		s.home(w, r)
	case path == "/api/v1/notifications":
		s.listNotifications(w, r)
	case path == "/api/v1/moderation/cases":
		s.listModerationCases(w, r)
	case path == "/api/v1/search":
		s.search(w, r)
	case path == "/api/v1/ranking":
		s.ranking(w, r)
	case path == "/api/v1/me/points":
		s.points(w, r)
	case path == "/api/v1/me/store-orders":
		s.storeOrders(w, r)
	case path == "/api/v1/store/products":
		s.storeProducts(w, r)
	case strings.HasPrefix(path, "/api/v1/posts/") && strings.HasSuffix(path, "/poll"):
		s.getPoll(w, r, strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/posts/"), "/poll"))
	case strings.HasPrefix(path, "/api/v1/posts/") && strings.HasSuffix(path, "/comments"):
		postID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/posts/"), "/comments")
		s.listComments(w, r, postID)
	case strings.HasPrefix(path, "/api/v1/posts/"):
		s.getPost(w, r, strings.TrimPrefix(path, "/api/v1/posts/"))
	default:
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusNotFound, Code: "NOT_FOUND", Message: "请求资源不存在"})
	}
}

func isProfileListPath(path string) bool {
	switch path {
	case "/api/v1/me/posts", "/api/v1/me/comments", "/api/v1/me/likes", "/api/v1/me/bookmarks", "/api/v1/me/history":
		return true
	default:
		return false
	}
}

func (s *Server) register(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	var input auth.RegisterInput
	if err := decodeJSON(r, &input); err != nil {
		writeAuthError(w, r, auth.ErrInvalidInput)
		return
	}
	response, err := s.authService.Register(r.Context(), input, requestMetadata(r))
	if err != nil {
		writeAuthError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusCreated, response)
}

func (s *Server) login(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	var input auth.LoginInput
	if err := decodeJSON(r, &input); err != nil {
		writeAuthError(w, r, auth.ErrInvalidCredentials)
		return
	}
	response, err := s.authService.Login(r.Context(), input, requestMetadata(r))
	if err != nil {
		writeAuthError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, response)
}

func (s *Server) refresh(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	var input struct {
		RefreshToken string `json:"refresh_token"`
	}
	if err := decodeJSON(r, &input); err != nil {
		writeAuthError(w, r, auth.ErrInvalidToken)
		return
	}
	response, err := s.authService.Refresh(r.Context(), input.RefreshToken, requestMetadata(r))
	if err != nil {
		writeAuthError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, response)
}

func (s *Server) logout(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	var input struct {
		RefreshToken string `json:"refresh_token"`
	}
	if err := decodeJSON(r, &input); err != nil {
		writeAuthError(w, r, auth.ErrInvalidInput)
		return
	}
	if err := s.authService.Logout(r.Context(), input.RefreshToken); err != nil {
		writeAuthError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) me(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, user)
}

func (s *Server) authenticatedUser(w http.ResponseWriter, r *http.Request) (auth.User, bool) {
	token, ok := bearerToken(r.Header.Get("Authorization"))
	if !ok {
		writeAuthError(w, r, auth.ErrInvalidToken)
		return auth.User{}, false
	}
	user, err := s.authService.Me(r.Context(), token)
	if err != nil {
		writeAuthError(w, r, err)
		return auth.User{}, false
	}
	return user, true
}

func decodeJSON(r *http.Request, target any) error {
	decoder := json.NewDecoder(io.LimitReader(r.Body, 1<<20))
	if err := decoder.Decode(target); err != nil {
		return err
	}
	return nil
}

func bearerToken(header string) (string, bool) {
	parts := strings.Fields(header)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "bearer") || parts[1] == "" {
		return "", false
	}
	return parts[1], true
}

func requestMetadata(r *http.Request) auth.SessionMetadata {
	return auth.SessionMetadata{UserAgent: r.UserAgent(), IPAddress: httpserver.ClientIP(r)}
}

func writeAuthError(w http.ResponseWriter, r *http.Request, err error) {
	appErr := httpserver.AppError{Status: http.StatusInternalServerError, Code: "INTERNAL_ERROR", Message: "服务暂时不可用"}
	switch {
	case errors.Is(err, auth.ErrInvalidInput):
		appErr = httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_INPUT", Message: "请求参数不合法"}
	case errors.Is(err, auth.ErrUsernameTaken):
		appErr = httpserver.AppError{Status: http.StatusConflict, Code: "USERNAME_TAKEN", Message: "用户名不可用"}
	case errors.Is(err, auth.ErrInvalidCredentials):
		appErr = httpserver.AppError{Status: http.StatusUnauthorized, Code: "INVALID_CREDENTIALS", Message: "用户名或密码错误"}
	case errors.Is(err, auth.ErrInvalidToken):
		appErr = httpserver.AppError{Status: http.StatusUnauthorized, Code: "INVALID_TOKEN", Message: "登录状态已失效"}
	case errors.Is(err, auth.ErrUserDisabled):
		appErr = httpserver.AppError{Status: http.StatusForbidden, Code: "USER_DISABLED", Message: "账户当前不可用"}
	case errors.Is(err, ErrCommunityNotFound):
		appErr = httpserver.AppError{Status: http.StatusNotFound, Code: "COMMUNITY_NOT_FOUND", Message: "社区不存在或不可用"}
	case errors.Is(err, ErrPostNotFound):
		appErr = httpserver.AppError{Status: http.StatusNotFound, Code: "POST_NOT_FOUND", Message: "帖子不存在"}
	case errors.Is(err, ErrForbidden):
		appErr = httpserver.AppError{Status: http.StatusForbidden, Code: "FORBIDDEN", Message: "没有执行该操作的权限"}
	case errors.Is(err, ErrIdempotencyKeyRequired):
		appErr = httpserver.AppError{Status: http.StatusBadRequest, Code: "IDEMPOTENCY_KEY_REQUIRED", Message: "缺少 Idempotency-Key"}
	case errors.Is(err, ErrInvalidPost):
		appErr = httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_POST", Message: "帖子内容不合法"}
	case errors.Is(err, ErrInsufficientPoints):
		appErr = httpserver.AppError{Status: http.StatusConflict, Code: "INSUFFICIENT_POINTS", Message: "积分不足"}
	case errors.Is(err, ErrBookmarkFolderNotFound):
		appErr = httpserver.AppError{Status: http.StatusNotFound, Code: "BOOKMARK_FOLDER_NOT_FOUND", Message: "收藏夹不存在"}
	case errors.Is(err, ErrDefaultBookmarkFolder):
		appErr = httpserver.AppError{Status: http.StatusBadRequest, Code: "DEFAULT_BOOKMARK_FOLDER_PROTECTED", Message: "默认收藏夹不能删除或重命名"}
	case errors.Is(err, ErrInvalidBookmarkFolderName):
		appErr = httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_BOOKMARK_FOLDER_NAME", Message: "收藏夹名称不能为空且不能超过 40 个字"}
	case errors.Is(err, ErrBookmarkFolderNameTaken):
		appErr = httpserver.AppError{Status: http.StatusConflict, Code: "BOOKMARK_FOLDER_NAME_TAKEN", Message: "收藏夹名称已存在"}
	case errors.Is(err, ErrInvalidMedia):
		appErr = httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_MEDIA", Message: "媒体参数不合法"}
	case errors.Is(err, ErrMediaNotFound):
		appErr = httpserver.AppError{Status: http.StatusNotFound, Code: "MEDIA_NOT_FOUND", Message: "媒体不存在"}
	case errors.Is(err, ErrMediaNotOwned):
		appErr = httpserver.AppError{Status: http.StatusForbidden, Code: "MEDIA_NOT_OWNED", Message: "没有操作该媒体的权限"}
	case errors.Is(err, ErrMediaInUse):
		appErr = httpserver.AppError{Status: http.StatusConflict, Code: "MEDIA_IN_USE", Message: "媒体已被帖子使用，请先在帖子编辑中移除"}
	case errors.Is(err, ErrStorageUnavailable):
		appErr = httpserver.AppError{Status: http.StatusServiceUnavailable, Code: "STORAGE_UNAVAILABLE", Message: "媒体存储暂时不可用"}
	case errors.Is(err, ErrCommentNotFound):
		appErr = httpserver.AppError{Status: http.StatusNotFound, Code: "COMMENT_NOT_FOUND", Message: "评论不存在"}
	case errors.Is(err, ErrCommentParentNotFound):
		appErr = httpserver.AppError{Status: http.StatusNotFound, Code: "COMMENT_PARENT_NOT_FOUND", Message: "回复目标不存在"}
	case errors.Is(err, ErrInvalidComment):
		appErr = httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_COMMENT", Message: "评论内容不合法"}
	case errors.Is(err, ErrInteractionTargetNotFound):
		appErr = httpserver.AppError{Status: http.StatusNotFound, Code: "TARGET_NOT_FOUND", Message: "目标不存在或不可用"}
	case errors.Is(err, ErrSelfFollow):
		appErr = httpserver.AppError{Status: http.StatusBadRequest, Code: "SELF_FOLLOW_NOT_ALLOWED", Message: "不能关注自己"}
	case errors.Is(err, ErrBlockTargetNotFound):
		appErr = httpserver.AppError{Status: http.StatusNotFound, Code: "BLOCK_TARGET_NOT_FOUND", Message: "用户不存在或不可用"}
	case errors.Is(err, ErrBlocked):
		appErr = httpserver.AppError{Status: http.StatusForbidden, Code: "BLOCKED", Message: "该互动已被阻止"}
	case errors.Is(err, ErrInvalidReport):
		appErr = httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_REPORT", Message: "举报参数不合法"}
	case errors.Is(err, ErrReportTargetNotFound):
		appErr = httpserver.AppError{Status: http.StatusNotFound, Code: "REPORT_TARGET_NOT_FOUND", Message: "举报目标不存在"}
	case errors.Is(err, ErrPermissionDenied):
		appErr = httpserver.AppError{Status: http.StatusForbidden, Code: "PERMISSION_DENIED", Message: "没有执行该操作的权限"}
	case errors.Is(err, ErrInvalidModerationAction):
		appErr = httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_MODERATION_ACTION", Message: "审核动作不合法"}
	case errors.Is(err, ErrModerationCaseNotFound):
		appErr = httpserver.AppError{Status: http.StatusNotFound, Code: "MODERATION_CASE_NOT_FOUND", Message: "审核案件不存在"}
	case errors.Is(err, sql.ErrConnDone):
		appErr = httpserver.AppError{Status: http.StatusServiceUnavailable, Code: "DATABASE_UNAVAILABLE", Message: "服务暂时不可用"}
	}
	httpserver.WriteAppError(w, r, appErr)
}

func (s *Server) requireDatabase(w http.ResponseWriter, r *http.Request) bool {
	if s.db != nil {
		return true
	}
	httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusServiceUnavailable, Code: "DATABASE_UNAVAILABLE", Message: "服务暂时不可用"})
	return false
}

func writeInternalError(w http.ResponseWriter, r *http.Request, err error) {
	httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusInternalServerError, Code: "INTERNAL_ERROR", Message: "服务暂时不可用", Details: nil})
}
