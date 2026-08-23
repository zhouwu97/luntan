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
)

const (
	accessTokenLifetime  = 15 * time.Minute
	refreshTokenLifetime = 30 * 24 * time.Hour
)

type User struct {
	ID       string `json:"id"`
	Username string `json:"username"`
	Nickname string `json:"nickname"`
	Level    int    `json:"level"`
	Status   string `json:"status"`
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
	user := User{ID: newID("usr"), Username: username, Nickname: nickname, Level: 1, Status: "active"}
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
		SELECT u.id, u.username, u.status, COALESCE(up.nickname, u.username), COALESCE(up.level, 1), a.id, a.credential_hash
		FROM users u
		JOIN user_auth_methods a ON a.user_id = u.id AND a.provider = 'password' AND a.identifier = $1
		LEFT JOIN user_profiles up ON up.user_id = u.id
		WHERE u.deleted_at IS NULL`, username).Scan(&user.ID, &user.Username, &user.Status, &user.Nickname, &user.Level, &authMethod, &credential)
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
	)
	err = tx.QueryRowContext(ctx, `
		SELECT rt.id, rt.session_id, u.id, u.username, u.status, COALESCE(up.nickname, u.username), COALESCE(up.level, 1), rt.expires_at
		FROM refresh_tokens rt
		JOIN users u ON u.id = rt.user_id
		LEFT JOIN user_profiles up ON up.user_id = u.id
		WHERE rt.token_hash = $1 AND rt.revoked_at IS NULL AND u.deleted_at IS NULL
		FOR UPDATE OF rt`, tokenHash(refreshToken)).Scan(&oldRefreshID, &sessionID, &user.ID, &user.Username, &user.Status, &user.Nickname, &user.Level, &expiresAt)
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
	err := s.db.QueryRowContext(ctx, `
		SELECT u.id, u.username, u.status, COALESCE(up.nickname, u.username), COALESCE(up.level, 1)
		FROM sessions s
		JOIN users u ON u.id = s.user_id
		LEFT JOIN user_profiles up ON up.user_id = u.id
		WHERE s.access_token_hash = $1 AND s.revoked_at IS NULL AND s.expires_at > now() AND u.deleted_at IS NULL`, tokenHash(accessToken)).Scan(&user.ID, &user.Username, &user.Status, &user.Nickname, &user.Level)
	if errors.Is(err, sql.ErrNoRows) {
		return User{}, ErrInvalidToken
	}
	if err != nil {
		return User{}, err
	}
	if user.Status != "active" {
		return User{}, ErrUserDisabled
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
