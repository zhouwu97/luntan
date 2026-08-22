package api

import (
	"database/sql"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"strings"

	"github.com/zhouwu97/luntan/server/internal/auth"
	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

type Server struct {
	db          *sql.DB
	authService *auth.Service
}

func NewHandler(db *sql.DB, authServices ...*auth.Service) http.Handler {
	authService := auth.NewService(db)
	if len(authServices) > 0 && authServices[0] != nil {
		authService = authServices[0]
	}
	return &Server{db: db, authService: authService}
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
	case strings.HasPrefix(path, "/api/v1/auth/") || path == "/api/v1/me":
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
	case strings.HasPrefix(path, "/api/v1/posts/"):
		s.getPost(w, r, strings.TrimPrefix(path, "/api/v1/posts/"))
	default:
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusNotFound, Code: "NOT_FOUND", Message: "请求资源不存在"})
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
	token, ok := bearerToken(r.Header.Get("Authorization"))
	if !ok {
		writeAuthError(w, r, auth.ErrInvalidToken)
		return
	}
	user, err := s.authService.Me(r.Context(), token)
	if err != nil {
		writeAuthError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, user)
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
	ipAddress := r.RemoteAddr
	if host, _, err := net.SplitHostPort(r.RemoteAddr); err == nil {
		ipAddress = host
	}
	return auth.SessionMetadata{UserAgent: r.UserAgent(), IPAddress: ipAddress}
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
