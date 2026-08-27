package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"time"
)

var (
	ErrInvalidInput       = errors.New("invalid auth input")
	ErrUsernameTaken      = errors.New("username is already taken")
	ErrInvalidCredentials = errors.New("invalid credentials")
	ErrInvalidToken       = errors.New("invalid token")
	ErrUserDisabled       = errors.New("user is disabled")
	ErrInvalidEmail       = errors.New("invalid email")
)

const (
	accessTokenLifetime  = 15 * time.Minute
	refreshTokenLifetime = 30 * 24 * time.Hour
)

type User struct {
	ID                     string          `json:"id"`
	Username               string          `json:"username"`
	Nickname               string          `json:"nickname"`
	Level                  int             `json:"level"`
	Experience             int64           `json:"experience"`
	Status                 string          `json:"status"`
	AccountType            string          `json:"account_type"`
	Email                  string          `json:"email,omitempty"`
	EmailVerified          bool            `json:"email_verified"`
	EmailVerifiedAt        *time.Time      `json:"email_verified_at,omitempty"`
	CommentRestricted      bool            `json:"comment_restricted,omitempty"`
	CommentRestrictedUntil *time.Time      `json:"comment_restricted_until,omitempty"`
	Capabilities           map[string]bool `json:"capabilities,omitempty"`
}

type RegisterInput struct {
	Username string `json:"username"`
	Password string `json:"password"`
	Nickname string `json:"nickname"`
}

type LoginInput struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

type SessionMetadata struct {
	UserAgent string
	IPAddress string
}

type TokenPair struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	TokenType    string `json:"token_type"`
	ExpiresIn    int64  `json:"expires_in"`
}

type AuthResponse struct {
	TokenPair
	User User `json:"user"`
}

type Service struct {
	db     *sql.DB
	hasher BcryptPasswordHasher
	clock  func() time.Time
}

func NewService(db *sql.DB) *Service {
	return &Service{db: db, clock: time.Now}
}

func (s *Service) Register(ctx context.Context, input RegisterInput, metadata SessionMetadata) (AuthResponse, error) {
	username, nickname, err := validateRegistration(input)
	if err != nil {
		return AuthResponse{}, err
	}
	if s == nil || s.db == nil {
		return AuthResponse{}, sql.ErrConnDone
	}
	hash, err := s.hasher.Hash(input.Password)
	if err != nil {
		return AuthResponse{}, fmt.Errorf("hash password: %w", err)
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return AuthResponse{}, err
	}
	defer tx.Rollback()

	var existingID string
	err = tx.QueryRowContext(ctx, `SELECT id FROM users WHERE username = $1 AND deleted_at IS NULL`, username).Scan(&existingID)
	if err == nil {
		return AuthResponse{}, ErrUsernameTaken
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return AuthResponse{}, err
	}

	now := s.clock().UTC()
	user := User{ID: newID("usr"), Username: username, Nickname: nickname, Level: 1, Status: "active", AccountType: "email"}
	if _, err := tx.ExecContext(ctx, `INSERT INTO users (id, username, status, created_at, updated_at) VALUES ($1, $2, $3, $4, $4)`, user.ID, user.Username, user.Status, now); err != nil {
		return AuthResponse{}, err
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO user_profiles (user_id, nickname, level, created_at, updated_at) VALUES ($1, $2, $3, $4, $4)`, user.ID, user.Nickname, user.Level, now); err != nil {
		return AuthResponse{}, err
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO user_auth_methods (id, user_id, provider, identifier, credential_hash, created_at) VALUES ($1, $2, 'password', $3, $4, $5)`, newID("uam"), user.ID, user.Username, hash, now); err != nil {
		return AuthResponse{}, err
	}
	pair, err := s.createSessionTx(ctx, tx, user.ID, metadata, now)
	if err != nil {
		return AuthResponse{}, err
	}
	if err := tx.Commit(); err != nil {
		return AuthResponse{}, err
	}
	return AuthResponse{TokenPair: pair, User: user}, nil
}

// levelForExperience 计算累计经验对应的正式等级（1~8 级）。
func levelForExperience(exp int64) int {
	if exp <= 0 {
		return 1
	}
	for lvl := 8; lvl >= 1; lvl-- {
		if exp >= int64(50*lvl*(lvl-1)) {
			return lvl
		}
	}
	return 1
}

// LoginByEmail 为邮箱验证码登录完成会话创建。验证码的校验由 API 层完成，
// 这里负责查找或创建正式邮箱账号并签发会话。若当前会话为游客且邮箱尚未被注册，
// 则原地将游客账号升级为正式账号，无缝保留全部历史数据与经验。
func (s *Service) LoginByEmail(ctx context.Context, email, nickname, guestUserID string, metadata SessionMetadata) (AuthResponse, error) {
	email = normalizeEmail(email)
	if !validEmail(email) {
		return AuthResponse{}, ErrInvalidEmail
	}
	if s == nil || s.db == nil {
		return AuthResponse{}, sql.ErrConnDone
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return AuthResponse{}, err
	}
	defer tx.Rollback()
	var user User
	var verifiedAt sql.NullTime
	var exp int64
	err = tx.QueryRowContext(ctx, `
		SELECT u.id, u.username, u.status, COALESCE(up.nickname, u.username),
		       CASE WHEN u.account_type = 'guest' THEN 0 ELSE COALESCE(up.level, 1) END,
		       COALESCE(u.account_type, 'email'), u.email, u.email_verified, u.email_verified_at,
		       COALESCE(up.experience, 0)
		FROM users u LEFT JOIN user_profiles up ON up.user_id = u.id
		WHERE lower(u.email) = $1 AND u.deleted_at IS NULL
		FOR UPDATE OF u`, email).Scan(&user.ID, &user.Username, &user.Status, &user.Nickname, &user.Level, &user.AccountType, &user.Email, &user.EmailVerified, &verifiedAt, &exp)
	if errors.Is(err, sql.ErrNoRows) {
		now := s.clock().UTC()
		upgraded := false
		if strings.TrimSpace(guestUserID) != "" {
			var guestUsername, guestNickname, guestStatus string
			var guestExp int64
			err := tx.QueryRowContext(ctx, `
				SELECT u.username, u.status, COALESCE(up.nickname, u.username), COALESCE(up.experience, 0)
				FROM users u LEFT JOIN user_profiles up ON up.user_id = u.id
				WHERE u.id = $1 AND u.account_type = 'guest' AND u.deleted_at IS NULL
				FOR UPDATE OF u`, guestUserID).Scan(&guestUsername, &guestStatus, &guestNickname, &guestExp)
			if err == nil && guestStatus == "active" {
				targetLevel := levelForExperience(guestExp)
				targetNickname := strings.TrimSpace(nickname)
				if targetNickname == "" || targetNickname == "游客" || strings.EqualFold(targetNickname, email) {
					targetNickname = guestNickname
				}
				if targetNickname == "" || targetNickname == "游客" {
					targetNickname = generatedNickname(guestUserID)
				}
				if _, err := tx.ExecContext(ctx, `UPDATE users SET account_type = 'email', email = $1, email_verified = true, email_verified_at = $2, updated_at = $2 WHERE id = $3`, email, now, guestUserID); err != nil {
					return AuthResponse{}, err
				}
				if _, err := tx.ExecContext(ctx, `UPDATE user_profiles SET nickname = $1, level = $2, updated_at = $3 WHERE user_id = $4`, targetNickname, targetLevel, now, guestUserID); err != nil {
					return AuthResponse{}, err
				}
				user = User{
					ID:              guestUserID,
					Username:        guestUsername,
					Nickname:        targetNickname,
					Level:           targetLevel,
					Status:          "active",
					AccountType:     "email",
					Email:           email,
					EmailVerified:   true,
					EmailVerifiedAt: &now,
				}
				upgraded = true
			}
		}

		if !upgraded {
			user = User{ID: newID("usr"), Username: "email_" + newID("acct")[5:17], Nickname: strings.TrimSpace(nickname), Level: 1, Status: "active", AccountType: "email", Email: email, EmailVerified: true, EmailVerifiedAt: &now}
			if user.Nickname == "" || strings.EqualFold(user.Nickname, email) {
				user.Nickname = generatedNickname(user.ID)
			}
			if _, err := tx.ExecContext(ctx, `INSERT INTO users (id, username, status, email, email_verified, email_verified_at, account_type, created_at, updated_at) VALUES ($1, $2, 'active', $3, true, $4, 'email', $4, $4)`, user.ID, user.Username, email, now); err != nil {
				return AuthResponse{}, err
			}
			if _, err := tx.ExecContext(ctx, `INSERT INTO user_profiles (user_id, nickname, level, experience, created_at, updated_at) VALUES ($1, $2, 1, 0, $3, $3)`, user.ID, user.Nickname, now); err != nil {
				return AuthResponse{}, err
			}
		}
	} else if err != nil {
		return AuthResponse{}, err
	} else {
		if verifiedAt.Valid {
			user.EmailVerifiedAt = &verifiedAt.Time
		}
		if user.AccountType == "" {
			user.AccountType = "email"
		}
		if strings.TrimSpace(user.Nickname) == "" || strings.EqualFold(strings.TrimSpace(user.Nickname), email) {
			user.Nickname = generatedNickname(user.ID)
			if _, err := tx.ExecContext(ctx, `UPDATE user_profiles SET nickname = $1, updated_at = $2 WHERE user_id = $3`, user.Nickname, s.clock().UTC(), user.ID); err != nil {
				return AuthResponse{}, err
			}
		}
		if user.Status != "active" {
			return AuthResponse{}, ErrUserDisabled
		}
		if _, err := tx.ExecContext(ctx, `UPDATE users SET email_verified = true, email_verified_at = COALESCE(email_verified_at, $1), updated_at = $1 WHERE id = $2`, s.clock().UTC(), user.ID); err != nil {
			return AuthResponse{}, err
		}
		user.EmailVerified = true
		user.Email = email
	}
	now := s.clock().UTC()
	pair, err := s.createSessionTx(ctx, tx, user.ID, metadata, now)
	if err != nil {
		return AuthResponse{}, err
	}
	if err := tx.Commit(); err != nil {
		return AuthResponse{}, err
	}
	return AuthResponse{TokenPair: pair, User: user}, nil
}

// CreateGuest 为游客模式创建可追踪的后台身份。游客仍然使用统一 users/sessions
// 体系，account_type=guest 且等级固定为 Lv.0。
func (s *Service) CreateGuest(ctx context.Context, metadata SessionMetadata) (AuthResponse, error) {
	if s == nil || s.db == nil {
		return AuthResponse{}, sql.ErrConnDone
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return AuthResponse{}, err
	}
	defer tx.Rollback()
	now := s.clock().UTC()
	user := User{ID: newID("usr"), Username: "guest_" + newID("acct")[5:17], Nickname: "游客", Level: 0, Status: "active", AccountType: "guest"}
	if _, err := tx.ExecContext(ctx, `INSERT INTO users (id, username, status, account_type, created_at, updated_at) VALUES ($1, $2, 'active', 'guest', $3, $3)`, user.ID, user.Username, now); err != nil {
		return AuthResponse{}, err
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO user_profiles (user_id, nickname, level, experience, created_at, updated_at) VALUES ($1, '游客', 0, 0, $2, $2)`, user.ID, now); err != nil {
		return AuthResponse{}, err
	}
	pair, err := s.createSessionTx(ctx, tx, user.ID, metadata, now)
	if err != nil {
		return AuthResponse{}, err
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO guest_sessions (id, user_id, session_id, ip_address, user_agent, expires_at, created_at) SELECT $1, $2, id, $3, $4, expires_at, $5 FROM sessions WHERE user_id = $2 ORDER BY created_at DESC LIMIT 1`, newID("gst"), user.ID, metadata.IPAddress, metadata.UserAgent, now); err != nil {
		return AuthResponse{}, err
	}
	if err := tx.Commit(); err != nil {
		return AuthResponse{}, err
	}
	return AuthResponse{TokenPair: pair, User: user}, nil
}

func (s *Service) Login(ctx context.Context, input LoginInput, metadata SessionMetadata) (AuthResponse, error) {
	username := normalizeUsername(input.Username)
	if username == "" || input.Password == "" {
		return AuthResponse{}, ErrInvalidCredentials
	}
	if s == nil || s.db == nil {
		return AuthResponse{}, sql.ErrConnDone
	}
	var (
		user       User
		authMethod string
		credential string
	)
	err := s.db.QueryRowContext(ctx, `
		SELECT u.id, u.username, u.status, COALESCE(up.nickname, u.username),
		       CASE WHEN u.account_type = 'guest' THEN 0 ELSE COALESCE(up.level, 1) END,
		       COALESCE(up.experience, 0), a.id, a.credential_hash
		FROM users u
		JOIN user_auth_methods a ON a.user_id = u.id AND a.provider = 'password' AND a.identifier = $1
		LEFT JOIN user_profiles up ON up.user_id = u.id
		WHERE u.deleted_at IS NULL`, username).Scan(&user.ID, &user.Username, &user.Status, &user.Nickname, &user.Level, &user.Experience, &authMethod, &credential)
	if errors.Is(err, sql.ErrNoRows) {
		return AuthResponse{}, ErrInvalidCredentials
	}
	if err != nil {
		return AuthResponse{}, err
	}
	if s.hasher.Compare(credential, input.Password) != nil {
		return AuthResponse{}, ErrInvalidCredentials
	}
	if user.Status != "active" {
		return AuthResponse{}, ErrUserDisabled
	}
	user.AccountType = "email"

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return AuthResponse{}, err
	}
	defer tx.Rollback()
	now := s.clock().UTC()
	if _, err := tx.ExecContext(ctx, `UPDATE user_auth_methods SET last_used_at = $1 WHERE id = $2`, now, authMethod); err != nil {
		return AuthResponse{}, err
	}
	pair, err := s.createSessionTx(ctx, tx, user.ID, metadata, now)
	if err != nil {
		return AuthResponse{}, err
	}
	if err := tx.Commit(); err != nil {
		return AuthResponse{}, err
	}
	return AuthResponse{TokenPair: pair, User: user}, nil
}

func (s *Service) Refresh(ctx context.Context, refreshToken string, metadata SessionMetadata) (AuthResponse, error) {
	if strings.TrimSpace(refreshToken) == "" || s == nil || s.db == nil {
		if s == nil || s.db == nil {
			return AuthResponse{}, sql.ErrConnDone
		}
		return AuthResponse{}, ErrInvalidToken
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return AuthResponse{}, err
	}
	defer tx.Rollback()
	var (
		oldRefreshID string
		sessionID    string
		user         User
		expiresAt    time.Time
		verifiedAt   sql.NullTime
	)
	err = tx.QueryRowContext(ctx, `
		SELECT rt.id, rt.session_id, u.id, u.username, u.status, COALESCE(up.nickname, u.username),
		       CASE WHEN u.account_type = 'guest' THEN 0 ELSE COALESCE(up.level, 1) END,
		       COALESCE(up.experience, 0),
		       COALESCE(u.account_type, 'email'), COALESCE(u.email, ''), u.email_verified, u.email_verified_at, rt.expires_at
		FROM refresh_tokens rt
		JOIN users u ON u.id = rt.user_id
		LEFT JOIN user_profiles up ON up.user_id = u.id
		WHERE rt.token_hash = $1 AND rt.revoked_at IS NULL AND u.deleted_at IS NULL
		FOR UPDATE OF rt`, tokenHash(refreshToken)).Scan(&oldRefreshID, &sessionID, &user.ID, &user.Username, &user.Status, &user.Nickname, &user.Level, &user.Experience, &user.AccountType, &user.Email, &user.EmailVerified, &verifiedAt, &expiresAt)
	if errors.Is(err, sql.ErrNoRows) {
		return AuthResponse{}, ErrInvalidToken
	}
	if err != nil {
		return AuthResponse{}, err
	}
	if !expiresAt.After(s.clock()) {
		return AuthResponse{}, ErrInvalidToken
	}
	if user.Status != "active" {
		return AuthResponse{}, ErrUserDisabled
	}
	if verifiedAt.Valid {
		user.EmailVerifiedAt = &verifiedAt.Time
	}
	now := s.clock().UTC()
	accessToken, err := newOpaqueToken()
	if err != nil {
		return AuthResponse{}, err
	}
	newRefreshToken, err := newOpaqueToken()
	if err != nil {
		return AuthResponse{}, err
	}
	accessExpires := now.Add(accessTokenLifetime)
	refreshExpires := now.Add(refreshTokenLifetime)
	newRefreshID := newID("rft")
	if _, err := tx.ExecContext(ctx, `UPDATE refresh_tokens SET revoked_at = $1, last_used_at = $1 WHERE id = $2`, now, oldRefreshID); err != nil {
		return AuthResponse{}, err
	}
	if _, err := tx.ExecContext(ctx, `UPDATE sessions SET access_token_hash = $1, expires_at = $2, last_used_at = $3, user_agent = $4, ip_address = $5 WHERE id = $6 AND revoked_at IS NULL`, tokenHash(accessToken), accessExpires, now, metadata.UserAgent, metadata.IPAddress, sessionID); err != nil {
		return AuthResponse{}, err
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO refresh_tokens (id, session_id, user_id, token_hash, expires_at, created_at, last_used_at) VALUES ($1, $2, $3, $4, $5, $6, $6)`, newRefreshID, sessionID, user.ID, tokenHash(newRefreshToken), refreshExpires, now); err != nil {
		return AuthResponse{}, err
	}
	if _, err := tx.ExecContext(ctx, `UPDATE refresh_tokens SET replaced_by_id = $1 WHERE id = $2`, newRefreshID, oldRefreshID); err != nil {
		return AuthResponse{}, err
	}
	if err := tx.Commit(); err != nil {
		return AuthResponse{}, err
	}
	return AuthResponse{TokenPair: TokenPair{AccessToken: accessToken, RefreshToken: newRefreshToken, TokenType: "Bearer", ExpiresIn: int64(accessTokenLifetime.Seconds())}, User: user}, nil
}

func (s *Service) Logout(ctx context.Context, refreshToken string) error {
	if strings.TrimSpace(refreshToken) == "" {
		return nil
	}
	if s == nil || s.db == nil {
		return sql.ErrConnDone
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `UPDATE refresh_tokens SET revoked_at = COALESCE(revoked_at, now()), last_used_at = now() WHERE token_hash = $1`, tokenHash(refreshToken)); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `UPDATE sessions SET revoked_at = COALESCE(revoked_at, now()) WHERE id IN (SELECT session_id FROM refresh_tokens WHERE token_hash = $1)`, tokenHash(refreshToken)); err != nil {
		return err
	}
	return tx.Commit()
}

func (s *Service) Me(ctx context.Context, accessToken string) (User, error) {
	if strings.TrimSpace(accessToken) == "" {
		return User{}, ErrInvalidToken
	}
	if s == nil || s.db == nil {
		return User{}, sql.ErrConnDone
	}
	var user User
	var verifiedAt sql.NullTime
	err := s.db.QueryRowContext(ctx, `
		SELECT u.id, u.username, u.status, COALESCE(up.nickname, u.username),
		       CASE WHEN u.account_type = 'guest' THEN 0 ELSE COALESCE(up.level, 1) END,
		       COALESCE(up.experience, 0),
		       COALESCE(u.account_type, 'email'), COALESCE(u.email, ''), u.email_verified, u.email_verified_at
		FROM sessions s
		JOIN users u ON u.id = s.user_id
		LEFT JOIN user_profiles up ON up.user_id = u.id
		WHERE s.access_token_hash = $1 AND s.revoked_at IS NULL AND s.expires_at > now() AND u.deleted_at IS NULL`, tokenHash(accessToken)).Scan(
		&user.ID,
		&user.Username,
		&user.Status,
		&user.Nickname,
		&user.Level,
		&user.Experience,
		&user.AccountType,
		&user.Email,
		&user.EmailVerified,
		&verifiedAt,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return User{}, ErrInvalidToken
	}
	if err != nil {
		return User{}, err
	}
	if user.Status != "active" {
		return User{}, ErrUserDisabled
	}
	if user.AccountType == "" {
		user.AccountType = "email"
	}
	if verifiedAt.Valid {
		user.EmailVerifiedAt = &verifiedAt.Time
	}
	return user, nil
}

func (s *Service) createSessionTx(ctx context.Context, tx *sql.Tx, userID string, metadata SessionMetadata, now time.Time) (TokenPair, error) {
	accessToken, err := newOpaqueToken()
	if err != nil {
		return TokenPair{}, err
	}
	refreshToken, err := newOpaqueToken()
	if err != nil {
		return TokenPair{}, err
	}
	accessExpires := now.Add(accessTokenLifetime)
	refreshExpires := now.Add(refreshTokenLifetime)
	sessionID := newID("ses")
	if _, err := tx.ExecContext(ctx, `INSERT INTO sessions (id, user_id, access_token_hash, expires_at, user_agent, ip_address, created_at, last_used_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $7)`, sessionID, userID, tokenHash(accessToken), accessExpires, metadata.UserAgent, metadata.IPAddress, now); err != nil {
		return TokenPair{}, err
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO refresh_tokens (id, session_id, user_id, token_hash, expires_at, created_at, last_used_at) VALUES ($1, $2, $3, $4, $5, $6, $6)`, newID("rft"), sessionID, userID, tokenHash(refreshToken), refreshExpires, now); err != nil {
		return TokenPair{}, err
	}
	return TokenPair{AccessToken: accessToken, RefreshToken: refreshToken, TokenType: "Bearer", ExpiresIn: int64(accessTokenLifetime.Seconds())}, nil
}

func validateRegistration(input RegisterInput) (string, string, error) {
	username := normalizeUsername(input.Username)
	nickname := strings.TrimSpace(input.Nickname)
	if len([]rune(username)) < 3 || len([]rune(username)) > 64 || strings.IndexFunc(username, func(r rune) bool { return r == ' ' || r == '\t' || r == '\n' || r == '\r' }) >= 0 {
		return "", "", ErrInvalidInput
	}
	if len([]rune(input.Password)) < 8 {
		return "", "", ErrInvalidInput
	}
	if nickname == "" {
		nickname = username
	}
	if len([]rune(nickname)) > 64 {
		return "", "", ErrInvalidInput
	}
	return username, nickname, nil
}

func normalizeUsername(username string) string {
	return strings.ToLower(strings.TrimSpace(username))
}

func normalizeEmail(email string) string {
	return strings.ToLower(strings.TrimSpace(email))
}

func validEmail(email string) bool {
	if len(email) < 5 || len(email) > 320 || strings.ContainsAny(email, "\r\n") {
		return false
	}
	at := strings.LastIndex(email, "@")
	return at > 0 && at < len(email)-1 && strings.Contains(email[at+1:], ".")
}

func newOpaqueToken() (string, error) {
	var raw [32]byte
	if _, err := rand.Read(raw[:]); err != nil {
		return "", err
	}
	return hex.EncodeToString(raw[:]), nil
}

func tokenHash(token string) string {
	hash := sha256.Sum256([]byte(token))
	return hex.EncodeToString(hash[:])
}

func newID(prefix string) string {
	token, err := newOpaqueToken()
	if err != nil {
		return prefix + "_fallback"
	}
	return prefix + "_" + token[:24]
}

func generatedNickname(userID string) string {
	clean := strings.TrimSpace(userID)
	if len(clean) >= 4 {
		return "杯友_" + strings.ToUpper(clean[len(clean)-4:])
	}
	return "用户_A81C"
}
