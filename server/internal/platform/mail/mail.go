// Package mail 提供论坛后端使用的邮件发送抽象和 SMTP 实现。
package mail

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"io"
	"mime"
	"net"
	stdmail "net/mail"
	"net/smtp"
	"os"
	"strconv"
	"strings"
	"time"
)

var (
	// ErrDisabled 表示当前环境未启用邮件发送，调用方不得将其视为发送成功。
	ErrDisabled = errors.New("mail sending is disabled")
	// ErrConfiguration 表示 SMTP 配置不完整或不合法。
	ErrConfiguration = errors.New("invalid SMTP configuration")
)

// Sender 是业务层依赖的最小邮件发送接口。
type Sender interface {
	Send(ctx context.Context, to, subject, htmlBody string) error
}

// Config 描述 SMTP 连接和发件人配置。
type Config struct {
	AppEnv   string
	Host     string
	Port     string
	Username string
	Password string
	From     string
	FromName string
	TLS      bool
}

// ConfigFromEnv 从环境变量读取 SMTP 配置。SMTP_TLS 未设置时默认启用 TLS。
func ConfigFromEnv(appEnv string) Config {
	tlsEnabled := true
	if raw := os.Getenv("SMTP_TLS"); raw != "" {
		if parsed, err := strconv.ParseBool(raw); err == nil {
			tlsEnabled = parsed
		}
	}
	return Config{
		AppEnv:   appEnv,
		Host:     os.Getenv("SMTP_HOST"),
		Port:     os.Getenv("SMTP_PORT"),
		Username: os.Getenv("SMTP_USERNAME"),
		Password: os.Getenv("SMTP_PASSWORD"),
		From:     os.Getenv("SMTP_FROM"),
		FromName: os.Getenv("SMTP_FROM_NAME"),
		TLS:      tlsEnabled,
	}
}

// NewSender 创建 SMTP sender。非 production 环境配置不完整时返回明确 disabled sender；
// production 环境则直接返回错误，阻止服务带着无效邮件配置启动。
func NewSender(cfg Config) (Sender, error) {
	if err := validateConfig(cfg); err != nil {
		if strings.EqualFold(strings.TrimSpace(cfg.AppEnv), "production") {
			return nil, fmt.Errorf("%w: %v", ErrConfiguration, err)
		}
		return disabledSender{reason: err.Error()}, nil
	}
	return &smtpSender{cfg: cfg}, nil
}

type disabledSender struct {
	reason string
}

func (s disabledSender) Send(context.Context, string, string, string) error {
	return fmt.Errorf("%w: %s", ErrDisabled, s.reason)
}

type smtpSender struct {
	cfg Config
}

func (s *smtpSender) Send(ctx context.Context, to, subject, htmlBody string) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	recipient, err := parseAddress(to)
	if err != nil {
		return fmt.Errorf("invalid recipient: %w", err)
	}
	if strings.ContainsAny(subject, "\r\n") {
		return errors.New("invalid subject: contains CR/LF")
	}

	from, err := parseAddress(s.cfg.From)
	if err != nil {
		return fmt.Errorf("invalid sender: %w", err)
	}
	message := buildMessage(from, s.cfg.FromName, recipient, subject, htmlBody)

	client, stop, err := s.connect(ctx)
	if err != nil {
		return fmt.Errorf("smtp connect: %w", err)
	}
	defer stop()
	defer client.Close()

	if err := client.Auth(smtp.PlainAuth("", s.cfg.Username, s.cfg.Password, s.cfg.Host)); err != nil {
		return fmt.Errorf("smtp auth: %w", err)
	}
	if err := client.Mail(from); err != nil {
		return fmt.Errorf("smtp MAIL FROM: %w", err)
	}
	if err := client.Rcpt(recipient); err != nil {
		return fmt.Errorf("smtp RCPT TO: %w", err)
	}
	writer, err := client.Data()
	if err != nil {
		return fmt.Errorf("smtp DATA: %w", err)
	}
	if _, err := io.WriteString(writer, message); err != nil {
		_ = writer.Close()
		return fmt.Errorf("smtp message write: %w", err)
	}
	if err := writer.Close(); err != nil {
		return fmt.Errorf("smtp message close: %w", err)
	}
	if err := client.Quit(); err != nil {
		return fmt.Errorf("smtp QUIT: %w", err)
	}
	return nil
}

func (s *smtpSender) connect(ctx context.Context) (*smtp.Client, func(), error) {
	port, err := strconv.Atoi(s.cfg.Port)
	if err != nil || port < 1 || port > 65535 {
		return nil, func() {}, fmt.Errorf("invalid SMTP_PORT %q", s.cfg.Port)
	}
	dialer := &net.Dialer{Timeout: 30 * time.Second}
	rawConn, err := dialer.DialContext(ctx, "tcp", net.JoinHostPort(s.cfg.Host, strconv.Itoa(port)))
	if err != nil {
		return nil, func() {}, err
	}
	wireConn := net.Conn(rawConn)
	if s.cfg.TLS {
		tlsConn := tls.Client(rawConn, &tls.Config{
			MinVersion: tls.VersionTLS12,
			ServerName: s.cfg.Host,
		})
		if err := tlsConn.HandshakeContext(ctx); err != nil {
			_ = rawConn.Close()
			return nil, func() {}, err
		}
		wireConn = tlsConn
	}
	stop := watchContext(ctx, wireConn)
	client, err := smtp.NewClient(wireConn, s.cfg.Host)
	if err != nil {
		stop()
		_ = wireConn.Close()
		return nil, func() {}, err
	}
	return client, stop, nil
}

func watchContext(ctx context.Context, conn net.Conn) func() {
	done := make(chan struct{})
	go func() {
		select {
		case <-ctx.Done():
			_ = conn.Close()
		case <-done:
		}
	}()
	return func() { close(done) }
}

func validateConfig(cfg Config) error {
	missing := make([]string, 0, 5)
	if strings.TrimSpace(cfg.Host) == "" {
		missing = append(missing, "SMTP_HOST")
	}
	if strings.TrimSpace(cfg.Port) == "" {
		missing = append(missing, "SMTP_PORT")
	}
	if strings.TrimSpace(cfg.Username) == "" {
		missing = append(missing, "SMTP_USERNAME")
	}
	if cfg.Password == "" {
		missing = append(missing, "SMTP_PASSWORD")
	}
	if strings.TrimSpace(cfg.From) == "" {
		missing = append(missing, "SMTP_FROM")
	}
	if len(missing) > 0 {
		return fmt.Errorf("missing %s", strings.Join(missing, ", "))
	}
	if strings.ContainsAny(cfg.Host+cfg.Username+cfg.From+cfg.FromName, "\r\n") {
		return errors.New("SMTP configuration contains CR/LF")
	}
	port, err := strconv.Atoi(cfg.Port)
	if err != nil || port < 1 || port > 65535 {
		return fmt.Errorf("SMTP_PORT must be a valid TCP port")
	}
	if _, err := parseAddress(cfg.From); err != nil {
		return fmt.Errorf("SMTP_FROM is invalid: %w", err)
	}
	return nil
}

func parseAddress(value string) (string, error) {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" || strings.ContainsAny(trimmed, "\r\n") {
		return "", errors.New("email address is empty or contains CR/LF")
	}
	parsed, err := stdmail.ParseAddress(trimmed)
	if err != nil || parsed.Address == "" {
		if err == nil {
			err = errors.New("email address is empty")
		}
		return "", err
	}
	return parsed.Address, nil
}

func buildMessage(from, fromName, to, subject, htmlBody string) string {
	fromHeader := from
	if fromName != "" {
		fromHeader = (&stdmail.Address{Name: fromName, Address: from}).String()
	}
	return strings.Join([]string{
		"MIME-Version: 1.0",
		"Date: " + time.Now().UTC().Format(time.RFC1123Z),
		"From: " + fromHeader,
		"To: " + to,
		"Subject: " + mime.QEncoding.Encode("UTF-8", subject),
		"Content-Type: text/html; charset=UTF-8",
		"Content-Transfer-Encoding: 8bit",
		"",
		htmlBody,
	}, "\r\n")
}
