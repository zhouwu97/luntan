package api

import (
	"database/sql"
	"net/http"
	"strings"

	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

type Server struct {
	db *sql.DB
}

func NewHandler(db *sql.DB) http.Handler {
	return &Server{db: db}
}

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimSuffix(r.URL.Path, "/")
	if r.Method != http.MethodGet {
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
