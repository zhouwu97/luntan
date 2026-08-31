package api

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"os"
	"strings"

	"github.com/zhouwu97/luntan/server/internal/auth"
	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

type Server struct {
	db                 *sql.DB
	authService        *auth.Service
	mediaStorage       mediaStorage
	pointRewards       PointRewardRules
	experienceRewards  ExperienceRewardRules
	mailSender         mailSender
	appEnv             string
	webOrigin          string
	authCodeHashSecret string
	allowDevAuthCode   bool
	// mediaDeliveryMode 控制 /api/v1/media-file 的鉴权模型：direct 维持
	// “公开兜底 + censored 黑名单”的历史行为（回滚安全），gateway 切换为
	// 默认拒绝 + 公开变体白名单的受控媒体网关。
	mediaDeliveryMode string
	// mediaAccelPrefix 非空且处于 gateway 模式时，媒体路由通过
	// X-Accel-Redirect 把字节流交给 Nginx internal location（数据面），
	// Go 只承担鉴权控制面。
	mediaAccelPrefix string
	// moderationSem 限制同步图片打码处理的并发数；超时的处理 goroutine 会
	// 持有名额直到真正结束，防止僵尸解码任务无限堆积。
	moderationSem chan struct{}
}

type authenticatedUserContextKey struct{}

// acquireModerationSlot 限流同步图片打码的并发数。零值 Server（仅测试直接
// 构造）没有初始化 moderationSem，nil channel 会永久阻塞，这里直接放行。
func (s *Server) acquireModerationSlot(ctx context.Context) bool {
	if s.moderationSem == nil {
		return true
	}
	select {
	case s.moderationSem <- struct{}{}:
		return true
	case <-ctx.Done():
		return false
	}
}

func (s *Server) releaseModerationSlot() {
	if s.moderationSem != nil {
		<-s.moderationSem
	}
}

// ReadinessCheck 将业务依赖检查接入统一 /ready 端点。保持构造函数返回
// http.Handler，避免破坏现有测试和调用方，同时允许主进程检查对象存储。
func ReadinessCheck(handler http.Handler) func(context.Context) error {
	server, ok := handler.(*Server)
	if !ok || server == nil {
		return nil
	}
	return server.Ready
}

// storageHealthChecker 由媒体存储按需实现；/ready 借此探测存储后端真实可用，
// 而不是只确认配置存在。
type storageHealthChecker interface {
	HealthCheck(ctx context.Context) error
}

func (s *Server) Ready(ctx context.Context) error {
	if _, unavailable := s.mediaStorage.(unavailableMediaStorage); unavailable {
		if strings.EqualFold(strings.TrimSpace(s.appEnv), "production") {
			return ErrStorageUnavailable
		}
		return nil
	}
	if checker, ok := s.mediaStorage.(storageHealthChecker); ok {
		return checker.HealthCheck(ctx)
	}
	return nil
}

type mailSender interface {
	Send(context.Context, string, string, string) error
}

func NewHandler(db *sql.DB, authServices ...*auth.Service) http.Handler {
	authService := auth.NewService(db)
	if len(authServices) > 0 && authServices[0] != nil {
		authService = authServices[0]
	}
	appEnv := appEnvironment()
	return &Server{
		db:                 db,
		authService:        authService,
		mediaStorage:       newObjectStorageFromEnv(),
		pointRewards:       pointRewardRulesFromEnv(),
		experienceRewards:  defaultExperienceRewardRules(),
		mailSender:         disabledMailSender{},
		appEnv:             appEnv,
		webOrigin:          configuredWebOrigin(),
		authCodeHashSecret: configuredAuthCodeHashSecret(),
		allowDevAuthCode:   devAuthCodeEnabled(appEnv),
		mediaDeliveryMode:  mediaDeliveryModeFromEnv(),
		mediaAccelPrefix:   mediaInternalAccelPrefixFromEnv(),
		moderationSem:      make(chan struct{}, 2),
	}
}

// NewHandlerWithMail 供正式服务注入 SMTP sender；保留 NewHandler 以兼容测试和本地无 SMTP 场景。
func NewHandlerWithMail(db *sql.DB, sender mailSender, appEnvs ...string) http.Handler {
	server := NewHandler(db).(*Server)
	if sender != nil {
		server.mailSender = sender
	}
	if len(appEnvs) > 0 && strings.TrimSpace(appEnvs[0]) != "" {
		server.appEnv = normalizeAppEnvironment(appEnvs[0])
		server.allowDevAuthCode = devAuthCodeEnabled(server.appEnv)
	}
	return server
}

func NewHandlerWithMedia(db *sql.DB, authService *auth.Service, storage mediaStorage) http.Handler {
	if authService == nil {
		authService = auth.NewService(db)
	}
	if storage == nil {
		storage = unavailableMediaStorage{}
	}
	appEnv := appEnvironment()
	return &Server{
		db:                 db,
		authService:        authService,
		mediaStorage:       storage,
		pointRewards:       pointRewardRulesFromEnv(),
		experienceRewards:  defaultExperienceRewardRules(),
		mailSender:         disabledMailSender{},
		appEnv:             appEnv,
		webOrigin:          configuredWebOrigin(),
		authCodeHashSecret: configuredAuthCodeHashSecret(),
		allowDevAuthCode:   devAuthCodeEnabled(appEnv),
		mediaDeliveryMode:  mediaDeliveryModeFromEnv(),
		mediaAccelPrefix:   mediaInternalAccelPrefixFromEnv(),
		moderationSem:      make(chan struct{}, 2),
	}
}

// NewHandlerWithPointRewards 供集成测试和灰度环境显式注入奖励配置。
func NewHandlerWithPointRewards(db *sql.DB, rules PointRewardRules) http.Handler {
	server := NewHandler(db).(*Server)
	server.pointRewards = rules
	return server
}

// NewHandlerWithExperienceRewards 供集成测试显式注入经验奖励配置。
func NewHandlerWithExperienceRewards(db *sql.DB, rules ExperienceRewardRules) http.Handler {
	server := NewHandler(db).(*Server)
	server.experienceRewards = rules
	return server
}

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimSuffix(r.URL.Path, "/")
	if s.isIPRestricted(r) {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusForbidden, Code: "IP_RESTRICTED", Message: "当前网络地址暂不可访问"})
		return
	}
	// 管理路由统一先完成身份认证；各 handler 继续执行自己的全局/社区
	// 权限校验。认证结果放入本次请求上下文，避免重复读取会话。
	if !s.authenticateAdministrativeRoute(w, r, path) {
		return
	}
	switch {
	case r.Method == http.MethodPost && path == "/api/v1/auth/register":
		s.register(w, r)
		return
	case r.Method == http.MethodPost && (path == "/api/v1/auth/login" || path == "/api/v1/auth/login/password"):
		s.login(w, r)
		return
	case r.Method == http.MethodPost && (path == "/api/v1/auth/code/request" || path == "/api/v1/auth/email/request"):
		s.requestEmailCode(w, r)
		return
	case r.Method == http.MethodPost && (path == "/api/v1/auth/login/code" || path == "/api/v1/auth/email/verify"):
		s.loginWithEmailCode(w, r)
		return
	case r.Method == http.MethodPost && path == "/api/v1/auth/guest":
		s.guest(w, r)
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
	case r.Method == http.MethodPost && path == "/api/v1/me/password":
		s.setPassword(w, r)
		return
	case r.Method == http.MethodGet && path == "/api/v1/me/profile":
		s.profile(w, r)
		return
	case r.Method == http.MethodPatch && path == "/api/v1/me/profile":
		s.updateProfile(w, r)
		return
	case r.Method == http.MethodGet && path == "/api/v1/me/account-status":
		s.accountStatus(w, r)
		return
	case r.Method == http.MethodGet && path == "/api/v1/admins":
		s.listAdmins(w, r)
		return
	case r.Method == http.MethodGet && path == "/api/v1/admins/candidates":
		s.listAdminCandidates(w, r)
		return
	case r.Method == http.MethodGet && path == "/api/v1/admin/users":
		s.listManagedUsers(w, r)
		return
	case r.Method == http.MethodGet && strings.HasPrefix(path, "/api/v1/admin/users/"):
		s.getManagedUser(w, r, strings.TrimPrefix(path, "/api/v1/admin/users/"))
		return
	case r.Method == http.MethodPost && strings.HasPrefix(path, "/api/v1/admin/users/") && strings.HasSuffix(path, "/actions"):
		userID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/admin/users/"), "/actions")
		s.manageUserAction(w, r, userID)
		return
	case r.Method == http.MethodPut && strings.HasPrefix(path, "/api/v1/admins/") && strings.HasSuffix(path, "/roles"):
		adminID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/admins/"), "/roles")
		s.updateAdminRoles(w, r, adminID)
		return
	case r.Method == http.MethodGet && path == "/api/v1/admin/ip-restrictions":
		s.listIPRestrictions(w, r)
		return
	case r.Method == http.MethodPost && path == "/api/v1/admin/ip-restrictions":
		s.createIPRestriction(w, r)
		return
	case r.Method == http.MethodDelete && strings.HasPrefix(path, "/api/v1/admin/ip-restrictions/"):
		s.revokeIPRestriction(w, r, strings.TrimPrefix(path, "/api/v1/admin/ip-restrictions/"))
		return
	case r.Method == http.MethodGet && path == "/api/v1/admin/recommendations":
		s.listHomeRecommendations(w, r)
		return
	case r.Method == http.MethodPut && path == "/api/v1/admin/recommendations/reorder":
		s.reorderHomeRecommendations(w, r)
		return
	case r.Method == http.MethodPut && strings.HasPrefix(path, "/api/v1/admin/posts/") && strings.HasSuffix(path, "/hot-suppression"):
		postID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/admin/posts/"), "/hot-suppression")
		s.setPostHotSuppression(w, r, postID)
		return
	case r.Method == http.MethodPut && strings.HasPrefix(path, "/api/v1/admin/media/") && strings.HasSuffix(path, "/moderation"):
		mediaID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/admin/media/"), "/moderation")
		s.moderateMedia(w, r, mediaID)
		return
	case r.Method == http.MethodGet && strings.HasPrefix(path, "/api/v1/admin/media/") && strings.HasSuffix(path, "/source"):
		mediaID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/admin/media/"), "/source")
		s.getAdminMediaSource(w, r, mediaID)
		return
	case r.Method == http.MethodPut && strings.HasPrefix(path, "/api/v1/admin/recommendations/"):
		postID := strings.TrimPrefix(path, "/api/v1/admin/recommendations/")
		s.setHomeRecommendation(w, r, postID)
		return
	case r.Method == http.MethodDelete && strings.HasPrefix(path, "/api/v1/admin/recommendations/"):
		postID := strings.TrimPrefix(path, "/api/v1/admin/recommendations/")
		s.removeHomeRecommendation(w, r, postID)
		return
	case r.Method == http.MethodGet && path == "/api/v1/admin/activities":
		s.listAdminActivities(w, r)
		return
	case r.Method == http.MethodPost && path == "/api/v1/admin/activities":
		s.createAdminActivity(w, r)
		return
	case (r.Method == http.MethodPost || r.Method == http.MethodPut) && strings.HasPrefix(path, "/api/v1/admin/activities/") && strings.HasSuffix(path, "/publish"):
		activityID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/admin/activities/"), "/publish")
		s.publishAdminActivity(w, r, activityID)
		return
	case r.Method == http.MethodPost && strings.HasPrefix(path, "/api/v1/admin/activities/") && strings.HasSuffix(path, "/offline"):
		activityID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/admin/activities/"), "/offline")
		s.offlineAdminActivity(w, r, activityID)
		return
	case r.Method == http.MethodPut && strings.HasPrefix(path, "/api/v1/admin/activities/"):
		activityID := strings.TrimPrefix(path, "/api/v1/admin/activities/")
		s.updateAdminActivity(w, r, activityID)
		return
	case r.Method == http.MethodDelete && strings.HasPrefix(path, "/api/v1/admin/activities/"):
		activityID := strings.TrimPrefix(path, "/api/v1/admin/activities/")
		s.deleteAdminActivity(w, r, activityID)
		return
	case r.Method == http.MethodGet && path == "/api/v1/activities":
		s.listPublicActivities(w, r)
		return
	case r.Method == http.MethodPost && path == "/api/v1/ranking/submissions":
		s.createRankingToySubmission(w, r)
		return
	case r.Method == http.MethodGet && path == "/api/v1/admin/ranking/submissions":
		s.listRankingToySubmissions(w, r)
		return
	case r.Method == http.MethodPost && strings.HasPrefix(path, "/api/v1/admin/ranking/submissions/") && strings.HasSuffix(path, "/review"):
		submissionID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/admin/ranking/submissions/"), "/review")
		s.reviewRankingToySubmission(w, r, submissionID)
		return
	case r.Method == http.MethodPut && path == "/api/v1/admin/ranking/reorder":
		s.reorderRankingToys(w, r)
		return
	case r.Method == http.MethodPut && strings.HasPrefix(path, "/api/v1/admin/ranking/toys/") && strings.HasSuffix(path, "/coupon"):
		toyID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/admin/ranking/toys/"), "/coupon")
		s.setRankingToyCoupon(w, r, toyID)
		return
	case r.Method == http.MethodGet && strings.HasPrefix(path, "/api/v1/admins/"):
		s.getAdmin(w, r, strings.TrimPrefix(path, "/api/v1/admins/"))
		return
	case r.Method == http.MethodGet && strings.HasPrefix(path, "/api/v1/users/") && strings.HasSuffix(path, "/posts"):
		userID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/users/"), "/posts")
		s.listUserPosts(w, r, userID)
		return
	case r.Method == http.MethodGet && strings.HasPrefix(path, "/api/v1/users/") && strings.HasSuffix(path, "/followers"):
		userID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/users/"), "/followers")
		s.listUserRelations(w, r, userID, "followers")
		return
	case r.Method == http.MethodGet && strings.HasPrefix(path, "/api/v1/users/") && strings.HasSuffix(path, "/following"):
		userID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/users/"), "/following")
		s.listUserRelations(w, r, userID, "following")
		return
	case r.Method == http.MethodGet && strings.HasPrefix(path, "/api/v1/users/") && strings.HasSuffix(path, "/comments"):
		userID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/users/"), "/comments")
		s.listUserComments(w, r, userID)
		return
	case r.Method == http.MethodGet && strings.HasPrefix(path, "/api/v1/users/"):
		s.getUserProfile(w, r, strings.TrimPrefix(path, "/api/v1/users/"))
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
		writeAuthError(w, r, ErrMarketDisabled)
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
	case r.Method == http.MethodPut && strings.HasPrefix(path, "/api/v1/comments/") && strings.HasSuffix(path, "/dislike"):
		s.toggleCommentDislike(w, r, strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/comments/"), "/dislike"), true)
		return
	case r.Method == http.MethodDelete && strings.HasPrefix(path, "/api/v1/comments/") && strings.HasSuffix(path, "/dislike"):
		s.toggleCommentDislike(w, r, strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/comments/"), "/dislike"), false)
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
	case r.Method == http.MethodPost && path == "/api/v1/notifications/read-all":
		s.markAllNotificationsRead(w, r)
		return
	case r.Method == http.MethodGet && path == "/api/v1/notifications/unread-count":
		s.unreadNotificationCount(w, r)
		return
	case r.Method == http.MethodPatch && strings.HasPrefix(path, "/api/v1/notifications/") && strings.HasSuffix(path, "/read"):
		notificationID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/notifications/"), "/read")
		s.markNotificationRead(w, r, notificationID)
		return
	case r.Method == http.MethodPost && path == "/api/v1/reports":
		s.createReport(w, r)
		return
	case r.Method == http.MethodPost && strings.HasPrefix(path, "/api/v1/moderation-actions/") && strings.HasSuffix(path, "/appeals"):
		actionID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/moderation-actions/"), "/appeals")
		s.createAppeal(w, r, actionID)
		return
	case r.Method == http.MethodGet && strings.HasPrefix(path, "/api/v1/moderation-actions/"):
		s.getModerationAction(w, r, strings.TrimPrefix(path, "/api/v1/moderation-actions/"))
		return
	case r.Method == http.MethodGet && path == "/api/v1/appeals":
		s.listAppeals(w, r)
		return
	case r.Method == http.MethodGet && strings.HasPrefix(path, "/api/v1/appeals/"):
		s.getAppeal(w, r, strings.TrimPrefix(path, "/api/v1/appeals/"))
		return
	case r.Method == http.MethodGet && path == "/api/v1/moderation/appeals":
		s.listModerationAppeals(w, r)
		return
	case r.Method == http.MethodGet && strings.HasPrefix(path, "/api/v1/moderation/appeals/"):
		s.getModerationAppeal(w, r, strings.TrimPrefix(path, "/api/v1/moderation/appeals/"))
		return
	case r.Method == http.MethodPost && strings.HasPrefix(path, "/api/v1/moderation/appeals/") && strings.HasSuffix(path, "/review"):
		appealID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/moderation/appeals/"), "/review")
		s.reviewAppeal(w, r, appealID)
		return
	case r.Method == http.MethodPost && strings.HasPrefix(path, "/api/v1/moderation/cases/") && strings.HasSuffix(path, "/actions"):
		caseID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/moderation/cases/"), "/actions")
		s.createModerationAction(w, r, caseID)
		return
	case r.Method == http.MethodGet && strings.HasPrefix(path, "/api/v1/moderation/cases/"):
		caseID := strings.TrimPrefix(path, "/api/v1/moderation/cases/")
		s.getModerationCase(w, r, caseID)
		return
	case r.Method == http.MethodPost && path == "/api/v1/media/upload-token":
		s.createMediaUploadToken(w, r)
		return
	case r.Method == http.MethodPut && path == "/api/v1/media/upload":
		s.receiveSignedMediaUpload(w, r)
		return
	case r.Method == http.MethodPost && strings.HasPrefix(path, "/api/v1/media/") && strings.HasSuffix(path, "/complete"):
		mediaID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/media/"), "/complete")
		s.completeMedia(w, r, mediaID)
		return
	case r.Method == http.MethodDelete && strings.HasPrefix(path, "/api/v1/media/"):
		s.deleteMedia(w, r, strings.TrimPrefix(path, "/api/v1/media/"))
		return
	case (r.Method == http.MethodGet || r.Method == http.MethodHead) && strings.HasPrefix(path, "/api/v1/media-file/"):
		s.serveMediaFile(w, r, strings.TrimPrefix(path, "/api/v1/media-file/"))
		return
	case r.Method == http.MethodPut && strings.HasPrefix(path, "/api/v1/ranking/toys/") && strings.HasSuffix(path, "/want"):
		toyID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/ranking/toys/"), "/want")
		s.setRankingToyFlag(w, r, toyID, "wanted", true)
		return
	case r.Method == http.MethodDelete && strings.HasPrefix(path, "/api/v1/ranking/toys/") && strings.HasSuffix(path, "/want"):
		toyID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/ranking/toys/"), "/want")
		s.setRankingToyFlag(w, r, toyID, "wanted", false)
		return
	case r.Method == http.MethodPut && strings.HasPrefix(path, "/api/v1/ranking/toys/") && strings.HasSuffix(path, "/owned"):
		toyID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/ranking/toys/"), "/owned")
		s.setRankingToyFlag(w, r, toyID, "owned", true)
		return
	case r.Method == http.MethodDelete && strings.HasPrefix(path, "/api/v1/ranking/toys/") && strings.HasSuffix(path, "/owned"):
		toyID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/ranking/toys/"), "/owned")
		s.setRankingToyFlag(w, r, toyID, "owned", false)
		return
	case r.Method == http.MethodPost && strings.HasPrefix(path, "/api/v1/ranking/toys/") && strings.HasSuffix(path, "/rating"):
		toyID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/ranking/toys/"), "/rating")
		s.rateRankingToy(w, r, toyID)
		return
	case r.Method == http.MethodPost && strings.HasPrefix(path, "/api/v1/ranking/toys/") && strings.HasSuffix(path, "/comments"):
		toyID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/ranking/toys/"), "/comments")
		s.createRankingToyComment(w, r, toyID)
		return
	case r.Method == http.MethodGet && strings.HasPrefix(path, "/api/v1/ranking/toys/") && strings.HasSuffix(path, "/comments"):
		toyID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/ranking/toys/"), "/comments")
		s.listRankingToyComments(w, r, toyID)
		return
	case r.Method == http.MethodGet && strings.HasPrefix(path, "/api/v1/ranking/toy-comments/") && strings.HasSuffix(path, "/replies"):
		commentID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/ranking/toy-comments/"), "/replies")
		s.listRankingToyReplies(w, r, commentID)
		return
	case r.Method == http.MethodPut && strings.HasPrefix(path, "/api/v1/ranking/toy-comments/") && strings.HasSuffix(path, "/like"):
		commentID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/ranking/toy-comments/"), "/like")
		s.toggleRankingToyCommentLike(w, r, commentID, true)
		return
	case r.Method == http.MethodDelete && strings.HasPrefix(path, "/api/v1/ranking/toy-comments/") && strings.HasSuffix(path, "/like"):
		commentID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/ranking/toy-comments/"), "/like")
		s.toggleRankingToyCommentLike(w, r, commentID, false)
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
	case path == "/api/v1/admin/risk":
		s.riskOverview(w, r)
	case path == "/api/v1/admin/logs":
		s.adminLogs(w, r)
	case path == "/api/v1/search":
		s.search(w, r)
	case path == "/api/v1/ranking/toys":
		s.listRankingToys(w, r)
	case strings.HasPrefix(path, "/api/v1/ranking/toys/") && !strings.Contains(strings.TrimPrefix(path, "/api/v1/ranking/toys/"), "/"):
		s.getRankingToy(w, r, strings.TrimPrefix(path, "/api/v1/ranking/toys/"))
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
	var input struct {
		Email    string `json:"email"`
		Code     string `json:"code"`
		Password string `json:"password"`
		Nickname string `json:"nickname"`
		Username string `json:"username"`
	}
	if err := decodeJSON(r, &input); err != nil {
		writeAuthError(w, r, auth.ErrInvalidInput)
		return
	}
	// 现代邮箱注册流程
	if strings.TrimSpace(input.Email) != "" {
		email := normalizeEmailAddress(input.Email)
		code := strings.TrimSpace(input.Code)
		if !validEmailAddress(email) || len(code) != 6 {
			writeAuthError(w, r, ErrInvalidEmailCode)
			return
		}
		if len([]rune(input.Password)) < 8 {
			writeAuthError(w, r, auth.ErrPasswordTooShort)
			return
		}

		tx, err := s.db.BeginTx(r.Context(), nil)
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
		defer tx.Rollback()

		// 严格校验 purpose = 'register' 验证码
		if err := s.verifyAndConsumeEmailCodeTx(r.Context(), tx, email, code, "register"); err != nil {
			_ = tx.Commit()
			writeAuthError(w, r, err)
			return
		}
		if _, err := tx.ExecContext(r.Context(), `INSERT INTO risk_events (id, event_type, severity, ip_address, metadata, created_at) VALUES ($1, 'email_register_verified', 'low', $2, $3::jsonb, now())`, newPostID(), httpserver.ClientIP(r), emailRiskMetadata(email)); err != nil {
			writeInternalError(w, r, err)
			return
		}
		if err := tx.Commit(); err != nil {
			writeInternalError(w, r, err)
			return
		}

		var guestUserID string
		if token, hasToken := bearerToken(r.Header.Get("Authorization")); hasToken {
			if u, err := s.authService.Me(r.Context(), token); err == nil && u.AccountType == "guest" {
				guestUserID = u.ID
			}
		}

		response, err := s.authService.RegisterWithEmail(r.Context(), auth.EmailRegisterInput{
			Email:       email,
			Password:    input.Password,
			Nickname:    input.Nickname,
			GuestUserID: guestUserID,
		}, requestMetadata(r))
		if err != nil {
			writeAuthError(w, r, err)
			return
		}
		s.writeAuthResponse(w, r, http.StatusCreated, response)
		return
	}

	// 兼容旧 username + password 注册；生产环境默认关闭，防止绕过邮箱验证码批量造号。
	if !legacyRegistrationEnabled(appEnvironment()) {
		writeAuthError(w, r, ErrLegacyRegistrationDisabled)
		return
	}
	response, err := s.authService.Register(r.Context(), auth.RegisterInput{
		Username: input.Username,
		Password: input.Password,
		Nickname: input.Nickname,
	}, requestMetadata(r))
	if err != nil {
		writeAuthError(w, r, err)
		return
	}
	s.writeAuthResponse(w, r, http.StatusCreated, response)
}

func appEnvironment() string {
	value := strings.TrimSpace(os.Getenv("APP_ENV"))
	if value == "" {
		return "development"
	}
	return normalizeAppEnvironment(value)
}

// mediaDeliveryModeFromEnv 读取媒体分发模式；空值与 "direct" 等价（历史行为），
// "gateway" 启用默认拒绝的受控媒体网关。生产启动校验由 config.Validate 承担。
func mediaDeliveryModeFromEnv() string {
	return strings.ToLower(strings.TrimSpace(os.Getenv("MEDIA_DELIVERY_MODE")))
}

// mediaInternalAccelPrefixFromEnv 读取 Nginx internal location 前缀；空值表示
// 网关回退为 Go 进程内拉流。规范化为以 / 开头、不以 / 结尾。
func mediaInternalAccelPrefixFromEnv() string {
	prefix := strings.TrimSpace(os.Getenv("MEDIA_INTERNAL_ACCEL_PREFIX"))
	if prefix == "" {
		return ""
	}
	if !strings.HasPrefix(prefix, "/") {
		prefix = "/" + prefix
	}
	return strings.TrimRight(prefix, "/")
}

func normalizeAppEnvironment(value string) string {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "dev", "development":
		return "development"
	case "test":
		return "test"
	case "qa":
		return "qa"
	case "staging":
		return "staging"
	case "production":
		return "production"
	default:
		return "unknown"
	}
}

func configuredAuthCodeHashSecret() string {
	return strings.TrimSpace(os.Getenv("AUTH_CODE_HASH_SECRET"))
}

func devAuthCodeEnabled(appEnv string) bool {
	if appEnv != "development" && appEnv != "test" {
		return false
	}
	return strings.EqualFold(strings.TrimSpace(os.Getenv("ALLOW_DEV_AUTH_CODE")), "true")
}

// legacyRegistrationEnabled 控制无邮箱验证码的旧 username 注册入口：
// 显式配置优先；未配置时开发/测试环境默认允许，其余环境（含生产）默认关闭。
func legacyRegistrationEnabled(appEnv string) bool {
	switch strings.TrimSpace(strings.ToLower(os.Getenv("ALLOW_LEGACY_USERNAME_REGISTRATION"))) {
	case "true":
		return true
	case "false":
		return false
	}
	return appEnv == "development" || appEnv == "test"
}

func isAdministrativePath(path string) bool {
	return path == "/api/v1/admin" || strings.HasPrefix(path, "/api/v1/admin/") ||
		path == "/api/v1/admins" || strings.HasPrefix(path, "/api/v1/admins/")
}

func (s *Server) authenticateAdministrativeRoute(w http.ResponseWriter, r *http.Request, path string) bool {
	if !isAdministrativePath(path) {
		return true
	}
	if !s.requireDatabase(w, r) {
		return false
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return false
	}
	*r = *r.WithContext(context.WithValue(r.Context(), authenticatedUserContextKey{}, user))
	return true
}

func (s *Server) login(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	var input struct {
		Email    string `json:"email"`
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := decodeJSON(r, &input); err != nil {
		writeAuthError(w, r, auth.ErrInvalidCredentials)
		return
	}
	// 支持邮箱密码登录与旧用户名密码登录
	targetEmail := strings.TrimSpace(input.Email)
	if targetEmail == "" && strings.Contains(input.Username, "@") {
		targetEmail = strings.TrimSpace(input.Username)
	}

	if targetEmail != "" {
		response, err := s.authService.EmailPasswordLogin(r.Context(), targetEmail, input.Password, requestMetadata(r))
		if err != nil {
			writeAuthError(w, r, err)
			return
		}
		s.writeAuthResponse(w, r, http.StatusOK, response)
		return
	}

	response, err := s.authService.Login(r.Context(), auth.LoginInput{
		Username: input.Username,
		Password: input.Password,
	}, requestMetadata(r))
	if err != nil {
		writeAuthError(w, r, err)
		return
	}
	s.writeAuthResponse(w, r, http.StatusOK, response)
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
	webCookieAuth := s.isWebCookieAuthRequest(r)
	// Web 端只接受 HttpOnly Cookie；原生端优先读取 body，兼容没有 Origin
	// 的旧 Web 请求时再回退到 Cookie。
	token := ""
	cookieSourced := false
	if webCookieAuth {
		token = refreshTokenFromRequest(r)
		cookieSourced = token != ""
	} else {
		token = strings.TrimSpace(input.RefreshToken)
		if token == "" {
			token = refreshTokenFromRequest(r)
			cookieSourced = token != ""
		}
	}
	if token == "" {
		writeAuthError(w, r, auth.ErrInvalidToken)
		return
	}
	response, err := s.authService.Refresh(r.Context(), token, requestMetadata(r))
	if err != nil {
		writeAuthError(w, r, err)
		return
	}
	if cookieSourced {
		// Cookie 轮换出的新 refresh token 只通过 Set-Cookie 下发，不进入
		// 响应体，避免 XSS 借一次刷新窃取新的长期会话。
		s.setRefreshTokenCookie(w, r, response.RefreshToken)
		response.RefreshToken = ""
	}
	if s.db != nil && response.User.ID != "" {
		_ = s.populateUserCapabilities(r.Context(), &response.User)
	} else {
		applyBaseCapabilities(&response.User)
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
	webCookieAuth := s.isWebCookieAuthRequest(r)
	token := ""
	if webCookieAuth {
		token = refreshTokenFromRequest(r)
	} else {
		token = strings.TrimSpace(input.RefreshToken)
		if token == "" {
			token = refreshTokenFromRequest(r)
		}
	}
	// 登出必须幂等：token 只存在于已过期的 Cookie 中或完全缺失时，
	// 仍要清除 Cookie 并返回 204，保证 Web 端登出永远能完成本地清理。
	if token != "" {
		if err := s.authService.Logout(r.Context(), token); err != nil {
			writeAuthError(w, r, err)
			return
		}
	}
	if webCookieAuth {
		s.clearRefreshTokenCookie(w, r)
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
	if user.AccountType != "guest" {
		if err := s.claimDailyLoginExperience(r.Context(), user.ID); err != nil {
			log.Printf("daily login experience claim failed: user_id=%s err=%v", user.ID, err)
		}
	}
	if err := s.populateUserCapabilities(r.Context(), &user); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, user)
}

// setPassword 登录用户设置或修改密码；游客账号不支持（应通过注册转正）。
func (s *Server) setPassword(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if user.AccountType == "guest" {
		writeAuthError(w, r, ErrRegisteredAccountRequired)
		return
	}
	var input struct {
		Password        string `json:"password"`
		CurrentPassword string `json:"current_password"`
	}
	if err := decodeJSON(r, &input); err != nil {
		writeAuthError(w, r, auth.ErrInvalidInput)
		return
	}
	accessToken, _ := bearerToken(r.Header.Get("Authorization"))
	if err := s.authService.SetPassword(r.Context(), user.ID, input.Password, input.CurrentPassword, accessToken); err != nil {
		writeAuthError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) authenticatedUser(w http.ResponseWriter, r *http.Request) (auth.User, bool) {
	if user, ok := r.Context().Value(authenticatedUserContextKey{}).(auth.User); ok {
		return user, true
	}
	if s == nil || s.authService == nil {
		writeAuthError(w, r, auth.ErrInvalidToken)
		return auth.User{}, false
	}
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

func applyBaseCapabilities(user *auth.User) {
	if user == nil {
		return
	}
	user.Capabilities = capabilitiesForUser(*user)
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
	case errors.Is(err, auth.ErrInvalidEmail):
		appErr = httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_EMAIL", Message: "邮箱地址不合法"}
	case errors.Is(err, auth.ErrEmailAlreadyRegistered):
		appErr = httpserver.AppError{Status: http.StatusConflict, Code: "EMAIL_ALREADY_REGISTERED", Message: "该邮箱已注册，请直接登录"}
	case errors.Is(err, auth.ErrEmailNotRegistered):
		appErr = httpserver.AppError{Status: http.StatusBadRequest, Code: "EMAIL_NOT_REGISTERED", Message: "该邮箱尚未注册，请先注册"}
	case errors.Is(err, auth.ErrPasswordTooShort):
		appErr = httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_PASSWORD", Message: "密码长度不能少于 8 位"}
	case errors.Is(err, auth.ErrPasswordNotSet):
		appErr = httpserver.AppError{Status: http.StatusConflict, Code: "PASSWORD_NOT_SET", Message: "该账号尚未设置密码，请使用验证码登录"}
	case errors.Is(err, auth.ErrCurrentPasswordRequired):
		appErr = httpserver.AppError{Status: http.StatusBadRequest, Code: "CURRENT_PASSWORD_REQUIRED", Message: "请输入当前密码后再修改"}
	case errors.Is(err, ErrInvalidEmailCode):
		appErr = httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_EMAIL_CODE", Message: "验证码错误或已失效"}
	case errors.Is(err, ErrEmailCodeExpired):
		appErr = httpserver.AppError{Status: http.StatusBadRequest, Code: "EMAIL_CODE_EXPIRED", Message: "验证码已过期，请重新获取"}
	case errors.Is(err, ErrEmailCodeRateLimit):
		appErr = httpserver.AppError{Status: http.StatusTooManyRequests, Code: "EMAIL_CODE_RATE_LIMITED", Message: "验证码发送太频繁，请稍后再试"}
	case errors.Is(err, ErrMailUnavailable):
		appErr = httpserver.AppError{Status: http.StatusServiceUnavailable, Code: "MAIL_UNAVAILABLE", Message: "邮件服务暂时不可用"}
	case errors.Is(err, ErrLegacyRegistrationDisabled):
		appErr = httpserver.AppError{Status: http.StatusForbidden, Code: "LEGACY_REGISTRATION_DISABLED", Message: "当前环境已关闭用户名注册，请使用邮箱验证码注册"}
	case errors.Is(err, auth.ErrInvalidToken):
		appErr = httpserver.AppError{Status: http.StatusUnauthorized, Code: "INVALID_TOKEN", Message: "登录状态已失效"}
	case errors.Is(err, auth.ErrUserDisabled):
		appErr = httpserver.AppError{Status: http.StatusForbidden, Code: "USER_DISABLED", Message: "账户当前不可用"}
	case errors.Is(err, ErrRegisteredAccountRequired):
		appErr = httpserver.AppError{Status: http.StatusForbidden, Code: "REGISTERED_ACCOUNT_REQUIRED", Message: "游客可以评论和举报，登录邮箱账号后才能发布内容"}
	case errors.Is(err, ErrUserMuted):
		appErr = httpserver.AppError{Status: http.StatusForbidden, Code: "USER_MUTED", Message: "账号当前处于禁言状态，暂不能发表评论"}
	case errors.Is(err, ErrCapabilityRequired):
		appErr = httpserver.AppError{Status: http.StatusForbidden, Code: "CAPABILITY_REQUIRED", Message: "当前身份没有执行该操作的权限"}
	case errors.Is(err, ErrAdminRoleManageDenied):
		appErr = httpserver.AppError{Status: http.StatusForbidden, Code: "ADMIN_ROLE_MANAGE_DENIED", Message: "只有超级管理员可以调整管理员权限"}
	case errors.Is(err, ErrInvalidAdminRole):
		appErr = httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_ADMIN_ROLE", Message: "管理员角色或社区范围不合法"}
	case errors.Is(err, ErrLastSuperAdmin):
		appErr = httpserver.AppError{Status: http.StatusConflict, Code: "LAST_SUPER_ADMIN", Message: "不能撤销最后一个超级管理员"}
	case errors.Is(err, ErrInvalidIPRestriction):
		appErr = httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_IP_RESTRICTION", Message: "IP 地址或限制参数不合法"}
	case errors.Is(err, ErrIPRestrictionNotFound):
		appErr = httpserver.AppError{Status: http.StatusNotFound, Code: "IP_RESTRICTION_NOT_FOUND", Message: "IP 限制不存在"}
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
	case errors.Is(err, ErrMarketDisabled):
		appErr = httpserver.AppError{Status: http.StatusGone, Code: "FEATURE_DISABLED", Message: "该帖子类型已停止使用"}
	case errors.Is(err, ErrActivityManagedSeparately):
		appErr = httpserver.AppError{Status: http.StatusConflict, Code: "ACTIVITY_USE_ACTIVITY_API", Message: "活动必须通过活动管理接口创建或编辑"}
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
		appErr = httpserver.AppError{Status: http.StatusConflict, Code: "MEDIA_IN_USE", Message: "媒体已被业务资源使用，请先解除引用"}
	case errors.Is(err, ErrStorageUnavailable):
		appErr = httpserver.AppError{Status: http.StatusServiceUnavailable, Code: "STORAGE_UNAVAILABLE", Message: "媒体存储暂时不可用"}
	case errors.Is(err, ErrCommentNotFound):
		appErr = httpserver.AppError{Status: http.StatusNotFound, Code: "COMMENT_NOT_FOUND", Message: "评论不存在"}
	case errors.Is(err, ErrCommentParentNotFound):
		appErr = httpserver.AppError{Status: http.StatusNotFound, Code: "COMMENT_PARENT_NOT_FOUND", Message: "回复目标不存在"}
	case errors.Is(err, ErrInvalidComment):
		appErr = httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_COMMENT", Message: "评论内容不合法"}
	case errors.Is(err, ErrRankingToyNotFound):
		appErr = httpserver.AppError{Status: http.StatusNotFound, Code: "RANKING_TOY_NOT_FOUND", Message: "榜单商品不存在或已下架"}
	case errors.Is(err, ErrInvalidRankingRating):
		appErr = httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_RANKING_RATING", Message: "评分必须是 1 到 10 的整数"}
	case errors.Is(err, ErrInvalidRankingComment):
		appErr = httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_RANKING_COMMENT", Message: "评论内容不合法"}
	case errors.Is(err, ErrRankingCommentNotFound):
		appErr = httpserver.AppError{Status: http.StatusNotFound, Code: "RANKING_COMMENT_NOT_FOUND", Message: "榜单评论不存在"}
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
	case errors.Is(err, ErrNotificationNotFound):
		appErr = httpserver.AppError{Status: http.StatusNotFound, Code: "NOTIFICATION_NOT_FOUND", Message: "通知不存在"}
	case errors.Is(err, ErrPollAlreadyVoted):
		appErr = httpserver.AppError{Status: http.StatusConflict, Code: "ALREADY_VOTED", Message: "你已经参与过该投票，不能修改选项"}
	case errors.Is(err, ErrPermissionDenied):
		appErr = httpserver.AppError{Status: http.StatusForbidden, Code: "PERMISSION_DENIED", Message: "没有执行该操作的权限"}
	case errors.Is(err, ErrTargetRoleProtected):
		appErr = httpserver.AppError{Status: http.StatusForbidden, Code: "TARGET_ROLE_PROTECTED", Message: "目标账号角色级别不低于操作者，不能执行该处罚"}
	case errors.Is(err, ErrInvalidModerationAction):
		appErr = httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_MODERATION_ACTION", Message: "审核动作不合法"}
	case errors.Is(err, ErrModerationCaseNotFound):
		appErr = httpserver.AppError{Status: http.StatusNotFound, Code: "MODERATION_CASE_NOT_FOUND", Message: "审核案件不存在"}
	case errors.Is(err, ErrAppealNotFound):
		appErr = httpserver.AppError{Status: http.StatusNotFound, Code: "APPEAL_NOT_FOUND", Message: "申诉不存在或已被删除"}
	case errors.Is(err, ErrAppealNotAllowed):
		appErr = httpserver.AppError{Status: http.StatusForbidden, Code: "APPEAL_NOT_ALLOWED", Message: "该处理不支持申诉或不属于当前账号"}
	case errors.Is(err, ErrAppealAlreadyExists):
		appErr = httpserver.AppError{Status: http.StatusConflict, Code: "APPEAL_ALREADY_EXISTS", Message: "该处理已经提交过申诉"}
	case errors.Is(err, ErrAppealAlreadyReviewed):
		appErr = httpserver.AppError{Status: http.StatusConflict, Code: "APPEAL_ALREADY_REVIEWED", Message: "该申诉已经完成复核"}
	case errors.Is(err, ErrInvalidAppeal):
		appErr = httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_APPEAL", Message: "申诉参数不合法"}
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
	log.Printf("internal_error method=%s path=%s err=%v", r.Method, r.URL.Path, err)
	httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusInternalServerError, Code: "INTERNAL_ERROR", Message: "服务暂时不可用", Details: nil})
}
