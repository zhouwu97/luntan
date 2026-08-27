package api

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"net/http"
	"strings"
	"time"

	"github.com/zhouwu97/luntan/server/internal/auth"
	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

var (
	ErrInvalidEmailCode   = errors.New("invalid email code")
	ErrEmailCodeExpired   = errors.New("email code expired")
	ErrEmailCodeRateLimit = errors.New("email code rate limited")
	ErrMailUnavailable    = errors.New("mail service unavailable")
)

const emailCodeLifetime = 10 * time.Minute

type disabledMailSender struct{}

func (disabledMailSender) Send(context.Context, string, string, string) error {
	return ErrMailUnavailable
}

type emailCodeInput struct {
	Email   string `json:"email"`
	Scene   string `json:"scene"`
	Purpose string `json:"purpose"`
}

type emailCodeLoginInput struct {
	Email string `json:"email"`
	Code  string `json:"code"`
}

func (s *Server) requestEmailCode(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	var input emailCodeInput
	if err := decodeJSON(r, &input); err != nil {
		writeAuthError(w, r, auth.ErrInvalidEmail)
		return
	}
	email := normalizeEmailAddress(input.Email)
	if !validEmailAddress(email) {
		writeAuthError(w, r, auth.ErrInvalidEmail)
		return
	}
	purpose := strings.TrimSpace(input.Scene)
	if purpose == "" {
		purpose = strings.TrimSpace(input.Purpose)
	}
	if purpose == "" {
		purpose = "login"
	}
	if purpose != "login" && purpose != "register" && purpose != "password_reset" {
		writeAuthError(w, r, auth.ErrInvalidInput)
		return
	}

	// 场景语义检查：登录时必须已注册，注册时必须未注册
	registered, err := s.authService.IsEmailRegistered(r.Context(), email)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if purpose == "login" && !registered {
		writeAuthError(w, r, auth.ErrEmailNotRegistered)
		return
	}
	if purpose == "register" && registered {
		writeAuthError(w, r, auth.ErrEmailAlreadyRegistered)
		return
	}

	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	var advisoryLock any
	if err := tx.QueryRowContext(r.Context(), `SELECT pg_advisory_xact_lock(hashtext('email-code:' || $1 || ':' || $2))`, email, purpose).Scan(&advisoryLock); err != nil {
		writeInternalError(w, r, err)
		return
	}
	var recent bool
	if err := tx.QueryRowContext(r.Context(), `SELECT EXISTS (SELECT 1 FROM email_codes WHERE lower(email) = $1 AND purpose = $2 AND status IN ('created', 'sending', 'sent') AND consumed_at IS NULL AND created_at > now() - interval '60 seconds')`, email, purpose).Scan(&recent); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if recent {
		writeAuthError(w, r, ErrEmailCodeRateLimit)
		return
	}
	code, err := newEmailCode()
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	now := time.Now().UTC()
	// 旧同 purpose 验证码作废，保证同一邮箱同一场景只有最后一次请求有效。
	if _, err := tx.ExecContext(r.Context(), `UPDATE email_codes SET consumed_at = COALESCE(consumed_at, $1), status = CASE WHEN status IN ('created', 'sending', 'sent') THEN 'expired' ELSE status END WHERE lower(email) = $2 AND purpose = $3 AND consumed_at IS NULL`, now, email, purpose); err != nil {
		writeInternalError(w, r, err)
		return
	}
	codeID := newPostID()
	if _, err := tx.ExecContext(r.Context(), `INSERT INTO email_codes (id, email, purpose, code_hash, expires_at, requested_ip, status, created_at) VALUES ($1, $2, $3, $4, $5, $6, 'sending', $7)`, codeID, email, purpose, emailCodeHash(code), now.Add(emailCodeLifetime), httpserver.ClientIP(r), now); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if _, err := tx.ExecContext(r.Context(), `INSERT INTO risk_events (id, event_type, severity, ip_address, metadata, created_at) VALUES ($1, 'email_code_requested', 'low', $2, $3::jsonb, $4)`, newPostID(), httpserver.ClientIP(r), emailRiskMetadata(email), now); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}

	devCode := ""
	if s.mailSender == nil {
		s.mailSender = disabledMailSender{}
	}
	subject := "杯友酱登录验证码"
	actionText := "登录"
	if purpose == "register" {
		subject = "杯友酱注册验证码"
		actionText = "注册"
	} else if purpose == "password_reset" {
		subject = "杯友酱密码重置验证码"
		actionText = "密码重置"
	}

	mailErr := s.mailSender.Send(r.Context(), email, subject, fmt.Sprintf(`<p>你的杯友酱%s验证码是：</p><p style="font-size:28px;font-weight:700;letter-spacing:8px">%s</p><p>验证码 10 分钟内有效。如非本人操作，请忽略此邮件。</p>`, actionText, html.EscapeString(code)))
	if mailErr != nil {
		_, _ = s.db.ExecContext(r.Context(), `UPDATE email_codes SET status = 'delivery_failed', failure_reason = $1 WHERE id = $2`, mailErr.Error(), codeID)
		if strings.EqualFold(s.appEnv, "production") {
			writeAuthError(w, r, ErrMailUnavailable)
			return
		}
		// 本地开发无 SMTP 时返回开发验证码，生产环境永不返回，便于联调而不降低线上安全性。
		devCode = code
	} else {
		if _, err := s.db.ExecContext(r.Context(), `UPDATE email_codes SET status = 'sent', sent_at = now() WHERE id = $1`, codeID); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	response := map[string]any{"expires_in": int(emailCodeLifetime.Seconds()), "retry_after": 60, "delivery": "email"}
	if devCode != "" {
		response["dev_code"] = devCode
		response["delivery"] = "development"
	}
	httpserver.WriteJSON(w, http.StatusOK, response)
}

// verifyAndConsumeEmailCodeTx 校验并在事务内消耗特定 purpose 的验证码。
func (s *Server) verifyAndConsumeEmailCodeTx(ctx context.Context, tx *sql.Tx, email, code, purpose string) error {
	var id, codeHash string
	var expiresAt time.Time
	var attempts int
	err := tx.QueryRowContext(ctx, `SELECT id, code_hash, expires_at, attempts FROM email_codes WHERE lower(email) = $1 AND purpose = $2 AND status IN ('created', 'sending', 'sent') AND consumed_at IS NULL ORDER BY created_at DESC, id DESC LIMIT 1 FOR UPDATE`, email, purpose).Scan(&id, &codeHash, &expiresAt, &attempts)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrInvalidEmailCode
	}
	if err != nil {
		return err
	}
	if !expiresAt.After(time.Now().UTC()) {
		_, _ = tx.ExecContext(ctx, `UPDATE email_codes SET consumed_at = now(), status = 'expired' WHERE id = $1`, id)
		return ErrEmailCodeExpired
	}
	expected := emailCodeHash(code)
	if subtle.ConstantTimeCompare([]byte(expected), []byte(codeHash)) != 1 {
		attempts++
		_, _ = tx.ExecContext(ctx, `UPDATE email_codes SET attempts = $1, status = CASE WHEN $1 >= 5 THEN 'expired' ELSE status END, consumed_at = CASE WHEN $1 >= 5 THEN now() ELSE consumed_at END WHERE id = $2`, attempts, id)
		return ErrInvalidEmailCode
	}
	if _, err := tx.ExecContext(ctx, `UPDATE email_codes SET consumed_at = now(), status = 'verified', verified_at = now() WHERE id = $1`, id); err != nil {
		return err
	}
	return nil
}

func (s *Server) loginWithEmailCode(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	var input emailCodeLoginInput
	if err := decodeJSON(r, &input); err != nil {
		writeAuthError(w, r, ErrInvalidEmailCode)
		return
	}
	email := normalizeEmailAddress(input.Email)
	code := strings.TrimSpace(input.Code)
	if !validEmailAddress(email) || len(code) != 6 {
		writeAuthError(w, r, ErrInvalidEmailCode)
		return
	}

	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()

	if err := s.verifyAndConsumeEmailCodeTx(r.Context(), tx, email, code, "login"); err != nil {
		_ = tx.Commit()
		writeAuthError(w, r, err)
		return
	}
	if _, err := tx.ExecContext(r.Context(), `INSERT INTO risk_events (id, event_type, severity, ip_address, metadata, created_at) VALUES ($1, 'email_login_verified', 'low', $2, $3::jsonb, now())`, newPostID(), httpserver.ClientIP(r), emailRiskMetadata(email)); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}

	response, err := s.authService.EmailCodeLogin(r.Context(), email, requestMetadata(r))
	if err != nil {
		writeAuthError(w, r, err)
		return
	}
	applyBaseCapabilities(&response.User)
	httpserver.WriteJSON(w, http.StatusOK, response)
}

func (s *Server) guest(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	response, err := s.authService.CreateGuest(r.Context(), requestMetadata(r))
	if err != nil {
		writeAuthError(w, r, err)
		return
	}
	applyBaseCapabilities(&response.User)
	httpserver.WriteJSON(w, http.StatusCreated, response)
}

func newEmailCode() (string, error) {
	var raw [4]byte
	if _, err := rand.Read(raw[:]); err != nil {
		return "", err
	}
	number := (uint32(raw[0])<<24 | uint32(raw[1])<<16 | uint32(raw[2])<<8 | uint32(raw[3])) % 1000000
	return fmt.Sprintf("%06d", number), nil
}

func emailCodeHash(code string) string {
	hash := sha256.Sum256([]byte(code))
	return hex.EncodeToString(hash[:])
}

func normalizeEmailAddress(value string) string { return strings.ToLower(strings.TrimSpace(value)) }

func validEmailAddress(value string) bool {
	if len(value) < 5 || len(value) > 320 || strings.ContainsAny(value, "\r\n\\\"") {
		return false
	}
	at := strings.LastIndex(value, "@")
	return at > 0 && at < len(value)-1 && strings.Contains(value[at+1:], ".")
}

func emailRiskMetadata(email string) []byte {
	data, _ := json.Marshal(map[string]string{"email": email})
	return data
}
