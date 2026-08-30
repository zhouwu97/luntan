package httpserver

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"net/netip"
	"strings"
)

type clientIPContextKey struct{}

type clientIPResolver struct {
	trusted []netip.Prefix
}

func newClientIPResolver(values []string) (*clientIPResolver, error) {
	resolver := &clientIPResolver{trusted: make([]netip.Prefix, 0, len(values))}
	for _, raw := range values {
		value := strings.TrimSpace(raw)
		if value == "" {
			continue
		}
		prefix, err := netip.ParsePrefix(value)
		if err != nil {
			return nil, fmt.Errorf("invalid trusted proxy CIDR %q: %w", value, err)
		}
		if prefix.Bits() == 0 {
			return nil, fmt.Errorf("trusted proxy CIDR %q is too broad", value)
		}
		resolver.trusted = append(resolver.trusted, prefix.Masked())
	}
	return resolver, nil
}

func (r *clientIPResolver) Resolve(request *http.Request) string {
	peer, ok := parseRemoteAddress(request.RemoteAddr)
	if !ok {
		return "unknown"
	}
	if !r.isTrusted(peer) {
		return peer.String()
	}

	if forwarded := strings.TrimSpace(request.Header.Get("X-Forwarded-For")); forwarded != "" {
		parts := strings.Split(forwarded, ",")
		hops := make([]netip.Addr, 0, len(parts))
		for _, part := range parts {
			hop, err := netip.ParseAddr(strings.TrimSpace(part))
			if err != nil {
				return peer.String()
			}
			hops = append(hops, hop.Unmap())
		}
		current := peer
		for index := len(hops) - 1; index >= 0; index-- {
			if !r.isTrusted(current) {
				return current.String()
			}
			current = hops[index]
		}
		return current.String()
	}

	if realIP := strings.TrimSpace(request.Header.Get("X-Real-IP")); realIP != "" {
		if parsed, err := netip.ParseAddr(realIP); err == nil {
			return parsed.Unmap().String()
		}
	}
	return peer.String()
}

func (r *clientIPResolver) isTrusted(address netip.Addr) bool {
	for _, prefix := range r.trusted {
		if prefix.Contains(address) {
			return true
		}
	}
	return false
}

func parseRemoteAddress(value string) (netip.Addr, bool) {
	host := value
	if parsedHost, _, err := net.SplitHostPort(value); err == nil {
		host = parsedHost
	}
	address, err := netip.ParseAddr(strings.TrimSpace(host))
	if err != nil {
		return netip.Addr{}, false
	}
	return address.Unmap(), true
}

func clientIPMiddleware(next http.Handler, resolver *clientIPResolver) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := context.WithValue(r.Context(), clientIPContextKey{}, resolver.Resolve(r))
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// ClientIP 返回经过可信代理链解析的客户端地址。
// 未经过 HTTP 根处理器的请求会安全地退回直连地址。
func ClientIP(r *http.Request) string {
	if value, ok := r.Context().Value(clientIPContextKey{}).(string); ok && value != "" {
		return value
	}
	if address, ok := parseRemoteAddress(r.RemoteAddr); ok {
		return address.String()
	}
	return "unknown"
}
