package httpserver

import (
	"compress/gzip"
	"io"
	"net/http"
	"strings"
)

// gzipMiddleware 对 JSON API 响应启用 gzip 压缩，明显减小榜单、帖子流等
// 大型 JSON 载荷的传输体积。媒体文件（/api/v1/media-file/）本身已是压缩
// 格式且需要支持 Range 请求，跳过压缩以节省 CPU。
func gzipMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodHead || !acceptsGzip(r) || isMediaPath(r.URL.Path) {
			next.ServeHTTP(w, r)
			return
		}
		gzw := &gzipResponseWriter{ResponseWriter: w, header: w.Header()}
		next.ServeHTTP(gzw, r)
		if gzw.gz != nil {
			_ = gzw.gz.Close()
		}
	})
}

func acceptsGzip(r *http.Request) bool {
	for _, part := range strings.Split(r.Header.Get("Accept-Encoding"), ",") {
		if strings.TrimSpace(strings.SplitN(part, ";", 2)[0]) == "gzip" {
			return true
		}
	}
	return false
}

func isMediaPath(path string) bool {
	return strings.HasPrefix(path, "/api/v1/media-file/")
}

type gzipResponseWriter struct {
	http.ResponseWriter
	header      http.Header
	gz          *gzip.Writer
	wroteHeader bool
}

func (g *gzipResponseWriter) Header() http.Header { return g.header }

func (g *gzipResponseWriter) WriteHeader(status int) {
	if g.wroteHeader {
		return
	}
	g.wroteHeader = true
	// 仅压缩 2xx 的 JSON 响应；错误响应体积小且行为需要尽量直观。
	if status >= 300 || !strings.HasPrefix(g.header.Get("Content-Type"), "application/json") {
		g.ResponseWriter.WriteHeader(status)
		return
	}
	g.header.Add("Vary", "Accept-Encoding")
	g.header.Set("Content-Encoding", "gzip")
	g.header.Del("Content-Length")
	g.gz = gzip.NewWriter(g.ResponseWriter)
	g.ResponseWriter.WriteHeader(status)
}

func (g *gzipResponseWriter) Write(p []byte) (int, error) {
	if !g.wroteHeader {
		g.WriteHeader(http.StatusOK)
	}
	if g.gz != nil {
		return g.gz.Write(p)
	}
	return g.ResponseWriter.Write(p)
}

var _ http.ResponseWriter = (*gzipResponseWriter)(nil)
var _ io.Writer = (*gzipResponseWriter)(nil)
