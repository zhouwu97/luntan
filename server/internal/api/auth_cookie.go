package api

import (
	"net/http"
	"strings"

	"github.com/zhouwu97/luntan/server/internal/auth"
	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

// Web 端长期 refresh token 通过 HttpOnly Cookie 携带，不再落入 JS 可读的
// localStorage，XSS 无法直接窃取长期会话；原生客户端仍从响应体读取 token，
// 行为保持不变。
const refreshTokenCookieName = "luntan_refresh"

// 必须与 auth.refreshTokenLifetime（30 天）保持一致：Cookie 存活超过令牌
// 本身只会留下永远无法使用的过期 Cookie。
const refreshTokenCookieMaxAge = 30 * 24 * 60 * 60

func writeAuthResponse(w http.ResponseWriter, r *http.Request, status int, response auth.AuthResponse) {
	setRefreshTokenCookie(w, r, response.RefreshToken)
	applyBaseCapabilities(&response.User)
	httpserver.WriteJSON(w, status, response)
}

func setRefreshTokenCookie(w http.ResponseWriter, r *http.Request, token string) {
	if strings.TrimSpace(token) == "" {
		return
	}
	http.SetCookie(w, &http.Cookie{
		Name:     refreshTokenCookieName,
		Value:    token,
		Path:     "/api/v1/auth",
		MaxAge:   refreshTokenCookieMaxAge,
		HttpOnly: true,
		Secure:   requestIsHTTPS(r),
		SameSite: http.SameSiteLaxMode,
	})
}

func clearRefreshTokenCookie(w http.ResponseWriter, r *http.Request) {
	http.SetCookie(w, &http.Cookie{
		Name:     refreshTokenCookieName,
		Value:    "",
		Path:     "/api/v1/auth",
		MaxAge:   -1,
		HttpOnly: true,
		Secure:   requestIsHTTPS(r),
		SameSite: http.SameSiteLaxMode,
	})
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
