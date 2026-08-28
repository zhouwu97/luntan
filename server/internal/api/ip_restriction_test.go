package api

import (
	"database/sql"
	"net/http"
	"net/http/httptest"
	"regexp"
	"strings"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestIPRestrictionEnforcement(t *testing.T) {
	t.Run("精确 IP 限制拦截 403", func(t *testing.T) {
		db, mock, err := sqlmock.New()
		if err != nil {
			t.Fatal(err)
		}
		defer db.Close()

		mock.ExpectQuery(regexp.QuoteMeta(`SELECT EXISTS (SELECT 1 FROM ip_restrictions WHERE restriction_type = 'access' AND revoked_at IS NULL AND starts_at <= now() AND (ends_at IS NULL OR ends_at > now()) AND ip_cidr >>= $1::inet)`)).
			WithArgs("198.51.100.10").
			WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(true))

		req := httptest.NewRequest(http.MethodGet, "/api/v1/communities", nil)
		req.RemoteAddr = "198.51.100.10:12345"
		res := httptest.NewRecorder()

		handler := NewHandler(db)
		handler.ServeHTTP(res, req)

		if res.Code != http.StatusForbidden {
			t.Fatalf("expected status 403, got %d", res.Code)
		}
		if !strings.Contains(res.Body.String(), `"code":"IP_RESTRICTED"`) {
			t.Fatalf("expected IP_RESTRICTED error code, got %s", res.Body.String())
		}
		if !strings.Contains(res.Body.String(), "当前网络地址暂不可访问") {
			t.Fatalf("expected human-friendly message, got %s", res.Body.String())
		}
	})

	t.Run("未受限 IP 正常通过", func(t *testing.T) {
		db, mock, err := sqlmock.New()
		if err != nil {
			t.Fatal(err)
		}
		defer db.Close()

		mock.ExpectQuery(regexp.QuoteMeta(`SELECT EXISTS (SELECT 1 FROM ip_restrictions WHERE restriction_type = 'access' AND revoked_at IS NULL AND starts_at <= now() AND (ends_at IS NULL OR ends_at > now()) AND ip_cidr >>= $1::inet)`)).
			WithArgs("203.0.113.1").
			WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(false))

		// 后续业务查询正常进行
		mock.ExpectQuery(regexp.QuoteMeta(`SELECT id, COALESCE(parent_id, ''), name, slug, COALESCE(icon, ''), sort_order, status`)).
			WithArgs("").
			WillReturnRows(sqlmock.NewRows([]string{"id", "parent_id", "name", "slug", "icon", "sort_order", "status"}).
				AddRow("cat-1", "", "数码", "digital", "", 1, "active"))

		req := httptest.NewRequest(http.MethodGet, "/api/v1/community-categories", nil)
		req.RemoteAddr = "203.0.113.1:54321"
		res := httptest.NewRecorder()

		handler := NewHandler(db)
		handler.ServeHTTP(res, req)

		if res.Code != http.StatusOK {
			t.Fatalf("expected status 200, got %d (body: %s)", res.Code, res.Body.String())
		}
		if !strings.Contains(res.Body.String(), `"name":"数码"`) {
			t.Fatalf("expected category data, got %s", res.Body.String())
		}
	})

	t.Run("已过期或已撤销规则不拦截", func(t *testing.T) {
		db, mock, err := sqlmock.New()
		if err != nil {
			t.Fatal(err)
		}
		defer db.Close()

		// 数据库中规则已过期或 revoked_at 不为空，SELECT EXISTS 返回 false
		mock.ExpectQuery(regexp.QuoteMeta(`SELECT EXISTS (SELECT 1 FROM ip_restrictions WHERE restriction_type = 'access' AND revoked_at IS NULL AND starts_at <= now() AND (ends_at IS NULL OR ends_at > now()) AND ip_cidr >>= $1::inet)`)).
			WithArgs("198.51.100.99").
			WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(false))

		mock.ExpectQuery(regexp.QuoteMeta(`SELECT id, COALESCE(parent_id, ''), name, slug, COALESCE(icon, ''), sort_order, status`)).
			WithArgs("").
			WillReturnRows(sqlmock.NewRows([]string{"id", "parent_id", "name", "slug", "icon", "sort_order", "status"}))

		req := httptest.NewRequest(http.MethodGet, "/api/v1/community-categories", nil)
		req.RemoteAddr = "198.51.100.99:12345"
		res := httptest.NewRecorder()

		handler := NewHandler(db)
		handler.ServeHTTP(res, req)

		if res.Code != http.StatusOK {
			t.Fatalf("expected status 200 for expired/revoked restriction, got %d", res.Code)
		}
	})

	t.Run("可信代理 X-Forwarded-For 真实 IP 拦截", func(t *testing.T) {
		db, mock, err := sqlmock.New()
		if err != nil {
			t.Fatal(err)
		}
		defer db.Close()

		// 模拟经过反向代理，ClientIP 解析出 X-Forwarded-For 中的真实客户端 IP 198.51.100.42
		mock.ExpectQuery(regexp.QuoteMeta(`SELECT EXISTS (SELECT 1 FROM ip_restrictions WHERE restriction_type = 'access' AND revoked_at IS NULL AND starts_at <= now() AND (ends_at IS NULL OR ends_at > now()) AND ip_cidr >>= $1::inet)`)).
			WithArgs("198.51.100.42").
			WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(true))

		req := httptest.NewRequest(http.MethodGet, "/api/v1/communities", nil)
		req.RemoteAddr = "198.51.100.42:12345"
		res := httptest.NewRecorder()

		handler := NewHandler(db)
		handler.ServeHTTP(res, req)

		if res.Code != http.StatusForbidden {
			t.Fatalf("expected status 403, got %d", res.Code)
		}
		if !strings.Contains(res.Body.String(), `"code":"IP_RESTRICTED"`) {
			t.Fatalf("expected IP_RESTRICTED, got %s", res.Body.String())
		}
	})
}

func TestIPRestrictionIsIPRestrictedHelper(t *testing.T) {
	t.Run("nil DB 返回 false", func(t *testing.T) {
		s := &Server{}
		req := httptest.NewRequest(http.MethodGet, "/", nil)
		req.RemoteAddr = "1.2.3.4:1234"
		if s.isIPRestricted(req) {
			t.Fatal("expected false for nil db")
		}
	})

	t.Run("未知或空 IP 返回 false", func(t *testing.T) {
		db, _, err := sqlmock.New()
		if err != nil {
			t.Fatal(err)
		}
		defer db.Close()

		s := &Server{db: db}
		req := httptest.NewRequest(http.MethodGet, "/", nil)
		req.RemoteAddr = "invalid-address"
		if s.isIPRestricted(req) {
			t.Fatal("expected false for invalid remote address")
		}
	})

	t.Run("数据库查询错误安全放行", func(t *testing.T) {
		db, mock, err := sqlmock.New()
		if err != nil {
			t.Fatal(err)
		}
		defer db.Close()

		mock.ExpectQuery(regexp.QuoteMeta(`SELECT EXISTS (SELECT 1 FROM ip_restrictions`)).
			WithArgs("1.2.3.4").
			WillReturnError(sql.ErrConnDone)

		s := &Server{db: db}
		req := httptest.NewRequest(http.MethodGet, "/", nil)
		req.RemoteAddr = "1.2.3.4:1234"
		if s.isIPRestricted(req) {
			t.Fatal("expected false on database error to avoid accidental lockouts")
		}
	})
}
