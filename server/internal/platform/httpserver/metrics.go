package httpserver

import (
	"fmt"
	"net/http"
	"sync/atomic"
	"time"
)

type requestMetrics struct {
	started    time.Time
	requests   atomic.Uint64
	clientErrs atomic.Uint64
	serverErrs atomic.Uint64
	timeouts   atomic.Uint64
	buckets    [8]atomic.Uint64
	login      businessMetric
	publish    businessMetric
	comment    businessMetric
	upload     businessMetric
}

type businessMetric struct {
	attempts atomic.Uint64
	success  atomic.Uint64
}

var metrics = &requestMetrics{started: time.Now()}

func (m *requestMetrics) observe(status int, latency time.Duration) {
	m.requests.Add(1)
	if status >= 400 && status < 500 {
		m.clientErrs.Add(1)
	}
	if status >= 500 {
		m.serverErrs.Add(1)
	}
	if latency >= 2*time.Second {
		m.timeouts.Add(1)
	}
	limits := [...]time.Duration{10 * time.Millisecond, 25 * time.Millisecond, 50 * time.Millisecond, 100 * time.Millisecond, 250 * time.Millisecond, 500 * time.Millisecond, time.Second, 2 * time.Second}
	for index, limit := range limits {
		if latency <= limit {
			m.buckets[index].Add(1)
			return
		}
	}
	m.buckets[len(m.buckets)-1].Add(1)
}

func (m *requestMetrics) observeBusiness(path string, status int) {
	metric := (*businessMetric)(nil)
	switch {
	case path == "/api/v1/auth/login":
		metric = &m.login
	case path == "/api/v1/posts":
		metric = &m.publish
	case path == "/api/v1/media/upload-token":
		metric = &m.upload
	case pathContainsCommentRoute(path):
		metric = &m.comment
	}
	if metric == nil {
		return
	}
	metric.attempts.Add(1)
	if status >= 200 && status < 300 {
		metric.success.Add(1)
	}
}

func pathContainsCommentRoute(path string) bool {
	return len(path) > 9 && (hasSuffix(path, "/comments") || hasSuffix(path, "/replies"))
}

func hasSuffix(value, suffix string) bool {
	if len(value) < len(suffix) {
		return false
	}
	return value[len(value)-len(suffix):] == suffix
}

func (m *requestMetrics) write(w http.ResponseWriter) {
	total := m.requests.Load()
	elapsed := time.Since(m.started).Seconds()
	if elapsed < 1 {
		elapsed = 1
	}
	fmt.Fprintf(w, "# TYPE luntan_http_requests_total counter\nluntan_http_requests_total %d\n", total)
	fmt.Fprintf(w, "luntan_http_requests_per_second %.3f\n", float64(total)/elapsed)
	fmt.Fprintf(w, "luntan_http_4xx_total %d\nluntan_http_5xx_total %d\nluntan_http_timeout_total %d\n", m.clientErrs.Load(), m.serverErrs.Load(), m.timeouts.Load())
	for _, quantile := range []float64{0.5, 0.95, 0.99} {
		fmt.Fprintf(w, "luntan_http_latency_ms{quantile=\"%.2f\"} %.0f\n", quantile, m.quantile(quantile))
	}
	fmt.Fprintln(w, "luntan_db_latency_ms 0")
	fmt.Fprintln(w, "luntan_db_connections 0")
	fmt.Fprintln(w, "luntan_worker_backlog 0")
	fmt.Fprintf(w, "luntan_login_success_rate %.4f\n", successRate(&m.login))
	fmt.Fprintf(w, "luntan_publish_success_rate %.4f\n", successRate(&m.publish))
	fmt.Fprintf(w, "luntan_comment_success_rate %.4f\n", successRate(&m.comment))
	fmt.Fprintf(w, "luntan_upload_success_rate %.4f\n", successRate(&m.upload))
}

func successRate(metric *businessMetric) float64 {
	attempts := metric.attempts.Load()
	if attempts == 0 {
		return 0
	}
	return float64(metric.success.Load()) / float64(attempts)
}

func (m *requestMetrics) quantile(quantile float64) float64 {
	total := m.requests.Load()
	if total == 0 {
		return 0
	}
	target := uint64(float64(total) * quantile)
	if target == 0 {
		target = 1
	}
	limits := [...]float64{10, 25, 50, 100, 250, 500, 1000, 2000}
	for index, limit := range limits {
		if m.buckets[index].Load() >= target {
			return limit
		}
	}
	return 2000
}
