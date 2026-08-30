package api

import (
	"net/http"
	"net/url"
	"os"
	"strings"

	"github.com/zhouwu97/luntan/server/internal/auth"
	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

const refreshTokenCookieName = "luntan_refresh"

const defaultWebOrigin = "https://shengbeijiang.com"

// 必须与 auth.refreshTokenLifetime（30 天）保持一致：Cookie 存活超过令牌
// 本身只会留下永远无法使用的过期 Cookie。
const refreshTokenCookieMaxAge = 30 * 24 * 60 * 60

func (s *Server) writeAuthResponse(w http.ResponseWriter, r *http.Request, status int, response auth.AuthResponse) {
	if s.isWebCookieAuthRequest(r) {
		// Web 端长期 refresh token 只允许通过 HttpOnly Cookie 携带，不能
		// 通过 JSON 暴露给 JavaScript；原生客户端仍保持 body-token 契约。
		s.setRefreshTokenCookie(w, r, response.RefreshToken)
		response.RefreshToken = ""
	}
	applyBaseCapabilities(&response.User)
	httpserver.WriteJSON(w, status, response)
}

func (s *Server) setRefreshTokenCookie(w http.ResponseWriter, r *http.Request, token string) {
	if strings.TrimSpace(token) == "" {
		return
	}
	http.SetCookie(w, &http.Cookie{
		Name:     refreshTokenCookieName,
		Value:    token,
		Path:     "/api/v1/auth",
		MaxAge:   refreshTokenCookieMaxAge,
		HttpOnly: true,
		Secure:   s.refreshCookieSecure(r),
		SameSite: http.SameSiteLaxMode,
	})
}

func (s *Server) clearRefreshTokenCookie(w http.ResponseWriter, r *http.Request) {
	http.SetCookie(w, &http.Cookie{
		Name:     refreshTokenCookieName,
		Value:    "",
		Path:     "/api/v1/auth",
		MaxAge:   -1,
		HttpOnly: true,
		Secure:   s.refreshCookieSecure(r),
		SameSite: http.SameSiteLaxMode,
	})
}

func (s *Server) refreshCookieSecure(r *http.Request) bool {
	// 生产环境的 Web 入口固定为 HTTPS，即使请求没有经过可信代理也不能
	// 因 X-Forwarded-Proto 缺失而降级为不安全 Cookie。
	return strings.EqualFold(strings.TrimSpace(s.appEnv), "production") || requestIsHTTPS(r)
}

func configuredWebOrigin() string {
	if value := strings.TrimSpace(os.Getenv("WEB_ORIGIN")); value != "" {
		return value
	}
	return defaultWebOrigin
}

func normalizedOrigin(value string) string {
	parsed, err := url.Parse(strings.TrimSpace(value))
	if err != nil || parsed.Scheme == "" || parsed.Host == "" || parsed.User != nil ||
		(parsed.Path != "" && parsed.Path != "/") || parsed.RawQuery != "" || parsed.Fragment != "" {
		return ""
	}
	return strings.ToLower(parsed.Scheme) + "://" + strings.ToLower(parsed.Host)
}

func (s *Server) isWebCookieAuthRequest(r *http.Request) bool {
	if r == nil {
		return false
	}
	configured := defaultWebOrigin
	if s != nil && strings.TrimSpace(s.webOrigin) != "" {
		configured = s.webOrigin
	}
	requestOrigin := normalizedOrigin(r.Header.Get("Origin"))
	configuredOrigin := normalizedOrigin(configured)
	return requestOrigin != "" && configuredOrigin != "" && requestOrigin == configuredOrigin
}

func refreshTokenFromRequest(r *http.Request) string {
	if cookie, err := r.Cookie(refreshTokenCookieName); err == nil {
		return strings.TrimSpace(cookie.Value)
	}
	return ""
}

// 反向代理终结 TLS 时通过 X-Forwarded-Proto 传递原始协议。
func requestIsHTTPS(r *http.Request) bool {
	if r.TLS != nil {
		return true
	}
	return strings.EqualFold(strings.TrimSpace(r.Header.Get("X-Forwarded-Proto")), "https")
}
