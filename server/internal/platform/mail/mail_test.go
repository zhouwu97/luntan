package mail

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"net"
	"strconv"
	"strings"
	"testing"
	"time"
)

func TestNewSenderDisablesIncompleteConfigurationOutsideProduction(t *testing.T) {
	sender, err := NewSender(Config{AppEnv: "dev"})
	if err != nil {
		t.Fatalf("expected development configuration to be accepted as disabled, got %v", err)
	}

	err = sender.Send(context.Background(), "receiver@example.com", "test", "body")
	if !errors.Is(err, ErrDisabled) {
		t.Fatalf("expected ErrDisabled, got %v", err)
	}
}

func TestConfigFromEnvReadsSMTPSettingsFromRuntimeEnvironment(t *testing.T) {
	t.Setenv("SMTP_HOST", "smtp.qq.com")
	t.Setenv("SMTP_PORT", "465")
	t.Setenv("SMTP_USERNAME", "sender@example.com")
	t.Setenv("SMTP_PASSWORD", "runtime-only-secret")
	t.Setenv("SMTP_FROM", "sender@example.com")
	t.Setenv("SMTP_FROM_NAME", "论坛")
	t.Setenv("SMTP_TLS", "true")

	cfg := ConfigFromEnv("test")
	if cfg.Host != "smtp.qq.com" || cfg.Port != "465" || cfg.Username != "sender@example.com" ||
		cfg.From != "sender@example.com" || cfg.FromName != "论坛" || !cfg.TLS {
		t.Fatal("environment variables were not mapped to SMTP configuration")
	}
	if cfg.Password != "runtime-only-secret" {
		t.Fatal("SMTP password was not read from the runtime environment")
	}
}

func TestNewSenderRejectsIncompleteConfigurationInProduction(t *testing.T) {
	_, err := NewSender(Config{AppEnv: "production"})
	if !errors.Is(err, ErrConfiguration) {
		t.Fatalf("expected ErrConfiguration, got %v", err)
	}
}

func TestSenderRejectsHeaderInjectionBeforeConnecting(t *testing.T) {
	sender, err := NewSender(Config{
		AppEnv:   "test",
		Host:     "127.0.0.1",
		Port:     "1",
		Username: "sender@example.com",
		Password: "test-secret",
		From:     "sender@example.com",
		TLS:      true,
	})
	if err != nil {
		t.Fatalf("expected valid configuration, got %v", err)
	}

	err = sender.Send(context.Background(), "receiver@example.com", "subject\r\nBcc: attacker@example.com", "body")
	if err == nil {
		t.Fatalf("expected header validation error, got %v", err)
	}
}

func TestSenderSendsMessageThroughSMTPProtocol(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	defer listener.Close()

	_, portText, err := net.SplitHostPort(listener.Addr().String())
	if err != nil {
		t.Fatalf("split listener address: %v", err)
	}
	port, err := strconv.Atoi(portText)
	if err != nil {
		t.Fatalf("parse listener port: %v", err)
	}

	messageCh := make(chan string, 1)
	errCh := make(chan error, 1)
	go serveFakeSMTP(listener, messageCh, errCh)

	sender, err := NewSender(Config{
		AppEnv:   "test",
		Host:     "127.0.0.1",
		Port:     strconv.Itoa(port),
		Username: "sender@example.com",
		Password: "test-secret",
		From:     "sender@example.com",
		FromName: "论坛",
		TLS:      false,
	})
	if err != nil {
		t.Fatalf("create sender: %v", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := sender.Send(ctx, "receiver@example.com", "论坛邮箱服务测试", "测试邮件正文"); err != nil {
		t.Fatalf("send: %v", err)
	}

	select {
	case message := <-messageCh:
		if !strings.Contains(strings.ToLower(message), "from: =?utf-8?") {
			t.Fatalf("expected encoded sender name, got %q", message)
		}
		if !strings.Contains(message, "To: receiver@example.com") || !strings.Contains(message, "测试邮件正文") {
			t.Fatalf("message missing recipient or body: %q", message)
		}
		if strings.Contains(message, "test-secret") {
			t.Fatal("SMTP password leaked into message")
		}
	case err := <-errCh:
		t.Fatalf("fake SMTP server: %v", err)
	case <-time.After(5 * time.Second):
		t.Fatal("timed out waiting for fake SMTP server")
	}
}

func serveFakeSMTP(listener net.Listener, messageCh chan<- string, errCh chan<- error) {
	conn, err := listener.Accept()
	if err != nil {
		errCh <- err
		return
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(5 * time.Second))
	reader := bufio.NewReader(conn)
	if _, err := fmt.Fprint(conn, "220 localhost ESMTP ready\r\n"); err != nil {
		errCh <- err
		return
	}
	for {
		line, err := reader.ReadString('\n')
		if err != nil {
			errCh <- err
			return
		}
		command := strings.ToUpper(strings.TrimSpace(line))
		switch {
		case strings.HasPrefix(command, "EHLO"), strings.HasPrefix(command, "HELO"):
			_, err = fmt.Fprint(conn, "250-localhost\r\n250-AUTH PLAIN\r\n250 OK\r\n")
		case strings.HasPrefix(command, "AUTH PLAIN"):
			_, err = fmt.Fprint(conn, "235 2.7.0 Authentication successful\r\n")
		case strings.HasPrefix(command, "MAIL FROM"):
			_, err = fmt.Fprint(conn, "250 2.1.0 OK\r\n")
		case strings.HasPrefix(command, "RCPT TO"):
			_, err = fmt.Fprint(conn, "250 2.1.5 OK\r\n")
		case command == "DATA":
			if _, err = fmt.Fprint(conn, "354 End data with <CR><LF>.<CR><LF>\r\n"); err == nil {
				var message strings.Builder
				for {
					dataLine, readErr := reader.ReadString('\n')
					if readErr != nil {
						err = readErr
						break
					}
					if dataLine == ".\r\n" {
						break
					}
					message.WriteString(dataLine)
				}
				if err == nil {
					messageCh <- message.String()
					_, err = fmt.Fprint(conn, "250 2.0.0 queued\r\n")
				}
			}
		case command == "QUIT":
			_, err = fmt.Fprint(conn, "221 2.0.0 closing connection\r\n")
			if err == nil {
				return
			}
		default:
			_, err = fmt.Fprint(conn, "250 OK\r\n")
		}
		if err != nil {
			errCh <- err
			return
		}
	}
}
