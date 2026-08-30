package config

import (
	"fmt"
	"net/url"
	"os"
	"strings"
)

type Config struct {
	AppEnv                     string
	HTTPPort                   string
	DatabaseURL                string
	LogLevel                   string
	RedisURL                   string
	ObjectStorageUploadBaseURL string
	ObjectStoragePublicBaseURL string
	ObjectStorageSigningSecret string
	AuthCodeHashSecret         string
	WebOrigin                  string
	RateLimitEnabled           bool
	AllowDevAuthCode           bool
	TrustedProxyCIDRs          []string
	MetricsAllowedCIDRs        []string
	AppReleaseManifestPath     string
	AppReleasePublicBaseURL    string
}

const (
	envDevelopment = "development"
	envTest        = "test"
	envQA          = "qa"
	envStaging     = "staging"
	envProduction  = "production"
)

func Load() Config {
	appEnv := strings.TrimSpace(os.Getenv("APP_ENV"))
	if normalized, err := normalizeAppEnv(appEnv); err == nil {
		appEnv = normalized
	}
	return Config{
		AppEnv:                     appEnv,
		HTTPPort:                   valueOrDefault("HTTP_PORT", "8080"),
		DatabaseURL:                os.Getenv("DATABASE_URL"),
		LogLevel:                   valueOrDefault("LOG_LEVEL", "info"),
		RedisURL:                   os.Getenv("REDIS_URL"),
		ObjectStorageUploadBaseURL: os.Getenv("OBJECT_STORAGE_UPLOAD_BASE_URL"),
		ObjectStoragePublicBaseURL: os.Getenv("OBJECT_STORAGE_PUBLIC_BASE_URL"),
		ObjectStorageSigningSecret: os.Getenv("OBJECT_STORAGE_SIGNING_SECRET"),
		AuthCodeHashSecret:         strings.TrimSpace(os.Getenv("AUTH_CODE_HASH_SECRET")),
		WebOrigin:                  strings.TrimSpace(os.Getenv("WEB_ORIGIN")),
		RateLimitEnabled:           strings.EqualFold(strings.TrimSpace(os.Getenv("RATE_LIMIT_ENABLED")), "true"),
		AllowDevAuthCode:           strings.EqualFold(strings.TrimSpace(os.Getenv("ALLOW_DEV_AUTH_CODE")), "true"),
		TrustedProxyCIDRs:          splitCSV(os.Getenv("TRUSTED_PROXY_CIDRS")),
		MetricsAllowedCIDRs:        splitCSV(os.Getenv("METRICS_ALLOWED_CIDRS")),
		AppReleaseManifestPath:     strings.TrimSpace(os.Getenv("APP_RELEASE_MANIFEST_PATH")),
		AppReleasePublicBaseURL:    strings.TrimRight(strings.TrimSpace(os.Getenv("APP_RELEASE_PUBLIC_BASE_URL")), "/"),
	}
}

// Validate 检查会导致线上服务以“半可用”状态启动的配置。APP_ENV 必须
// 显式设置为白名单值；开发环境保留本地数据库/邮件/对象存储的可选性，
// 生产环境则必须显式配置完整依赖，由启动进程直接失败。
func (c Config) Validate() error {
	appEnv, err := normalizeAppEnv(c.AppEnv)
	if err != nil {
		return err
	}
	if c.AllowDevAuthCode && appEnv != envDevelopment && appEnv != envTest {
		return fmt.Errorf("ALLOW_DEV_AUTH_CODE is only allowed in development or test")
	}
	if appEnv != envProduction {
		return nil
	}
	if strings.TrimSpace(c.DatabaseURL) == "" {
		return fmt.Errorf("production requires DATABASE_URL")
	}
	if !c.RateLimitEnabled {
		return fmt.Errorf("production requires RATE_LIMIT_ENABLED=true")
	}
	if strings.TrimSpace(c.RedisURL) == "" {
		return fmt.Errorf("production requires REDIS_URL to back the rate limiter")
	}
	if len([]byte(strings.TrimSpace(c.AuthCodeHashSecret))) < 32 {
		return fmt.Errorf("production requires AUTH_CODE_HASH_SECRET with at least 32 bytes")
	}
	storageURL := strings.TrimSpace(c.ObjectStorageUploadBaseURL)
	if storageURL == "" || strings.TrimSpace(c.ObjectStorageSigningSecret) == "" {
		return fmt.Errorf("production requires object storage URL and signing secret")
	}
	parsed, err := url.Parse(storageURL)
	if err != nil || parsed.Scheme == "" || parsed.Host == "" ||
		(parsed.Scheme != "http" && parsed.Scheme != "https") {
		return fmt.Errorf("OBJECT_STORAGE_UPLOAD_BASE_URL must be a complete HTTP(S) URL")
	}
	// 上传与公开地址都会直接暴露给浏览器/客户端，生产环境一旦允许 HTTP，
	// Web 端会因 mixed content 被拦截，媒体也会走明文链路。
	if parsed.Scheme != "https" {
		return fmt.Errorf("OBJECT_STORAGE_UPLOAD_BASE_URL must use HTTPS in production")
	}
	publicURL := strings.TrimSpace(c.ObjectStoragePublicBaseURL)
	if publicURL == "" {
		return fmt.Errorf("production requires OBJECT_STORAGE_PUBLIC_BASE_URL")
	}
	parsedPublic, err := url.Parse(publicURL)
	if err != nil || parsedPublic.Scheme == "" || parsedPublic.Host == "" ||
		(parsedPublic.Scheme != "http" && parsedPublic.Scheme != "https") {
		return fmt.Errorf("OBJECT_STORAGE_PUBLIC_BASE_URL must be a complete HTTP(S) URL")
	}
	if parsedPublic.Scheme != "https" {
		return fmt.Errorf("OBJECT_STORAGE_PUBLIC_BASE_URL must use HTTPS in production")
	}
	// STORAGE_INTERNAL_BASE_URL 只在服务端与存储服务之间的内网链路使用，
	// 不进入客户端，允许按内网拓扑继续使用 HTTP。
	if internalURL := strings.TrimSpace(os.Getenv("STORAGE_INTERNAL_BASE_URL")); internalURL != "" {
		parsedInternal, err := url.Parse(internalURL)
		if err != nil || parsedInternal.Scheme == "" || parsedInternal.Host == "" ||
			(parsedInternal.Scheme != "http" && parsedInternal.Scheme != "https") {
			return fmt.Errorf("STORAGE_INTERNAL_BASE_URL must be a complete HTTP(S) URL")
		}
	}
	if publicBaseURL := strings.TrimSpace(c.AppReleasePublicBaseURL); publicBaseURL != "" {
		parsedReleaseURL, err := url.Parse(publicBaseURL)
		if err != nil || parsedReleaseURL.Scheme == "" || parsedReleaseURL.Host == "" ||
			(parsedReleaseURL.Scheme != "http" && parsedReleaseURL.Scheme != "https") {
			return fmt.Errorf("APP_RELEASE_PUBLIC_BASE_URL must be a complete HTTP(S) URL")
		}
		if parsedReleaseURL.Scheme != "https" {
			return fmt.Errorf("APP_RELEASE_PUBLIC_BASE_URL must use HTTPS in production")
		}
	}
	return nil
}

// normalizeAppEnv 只接受仓库定义的环境名称；prod/prd 等近似值必须显式报错，
// 避免部署拼写错误时误走开发分支。
func normalizeAppEnv(value string) (string, error) {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "dev", envDevelopment:
		return envDevelopment, nil
	case envTest:
		return envTest, nil
	case envQA:
		return envQA, nil
	case envStaging:
		return envStaging, nil
	case envProduction:
		return envProduction, nil
	default:
		return "", fmt.Errorf("invalid APP_ENV %q", value)
	}
}

func splitCSV(value string) []string {
	parts := strings.Split(value, ",")
	result := make([]string, 0, len(parts))
	for _, part := range parts {
		if trimmed := strings.TrimSpace(part); trimmed != "" {
			result = append(result, trimmed)
		}
	}
	return result
}

func valueOrDefault(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
