package outbox

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
)

// NotificationHandler 负责把通知事件从 outbox 投递到可选的推送网关。
// 通知正文已经在业务事务中写入 notifications，因此未配置网关时仍然
// 具备站内通知能力；配置 PUSH_WEBHOOK_URL 后，worker 会对外投递并在
// 非 2xx 时返回错误，让 outbox 按退避策略重试。
type NotificationHandler struct {
	DB         *sql.DB
	WebhookURL string
	Secret     string
	Client     *http.Client
}

func (h NotificationHandler) Handle(ctx context.Context, event Event) error {
	if event.EventType != "notification.created" {
		// 其他事件当前没有外部消费者，保留 succeeded 状态，避免无意义重试。
		return nil
	}
	var payload struct {
		RecipientID string `json:"recipient_id"`
		Type        string `json:"type"`
		TargetID    string `json:"target_id"`
	}
	if err := json.Unmarshal(event.Payload, &payload); err != nil {
		return fmt.Errorf("decode notification event: %w", err)
	}
	if payload.RecipientID == "" || payload.Type == "" {
		return fmt.Errorf("notification event is missing recipient or type")
	}
	if h.DB != nil {
		var exists bool
		if err := h.DB.QueryRowContext(ctx, `SELECT EXISTS (SELECT 1 FROM notifications WHERE id = $1 AND user_id = $2)`, event.AggregateID, payload.RecipientID).Scan(&exists); err != nil {
			return fmt.Errorf("verify notification: %w", err)
		}
		if !exists {
			return fmt.Errorf("notification %s no longer exists", event.AggregateID)
		}
	}
	if strings.TrimSpace(h.WebhookURL) == "" {
		return nil
	}
	body, err := json.Marshal(map[string]any{
		"event_id":        event.ID,
		"event_type":      event.EventType,
		"notification_id": event.AggregateID,
		"recipient_id":    payload.RecipientID,
		"type":            payload.Type,
		"target_id":       payload.TargetID,
	})
	if err != nil {
		return err
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, h.WebhookURL, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("create notification webhook request: %w", err)
	}
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("X-Event-ID", event.ID)
	if strings.TrimSpace(h.Secret) != "" {
		mac := hmac.New(sha256.New, []byte(h.Secret))
		_, _ = mac.Write(body)
		request.Header.Set("X-Event-Signature", "sha256="+hex.EncodeToString(mac.Sum(nil)))
	}
	client := h.Client
	if client == nil {
		client = http.DefaultClient
	}
	response, err := client.Do(request)
	if err != nil {
		return fmt.Errorf("deliver notification: %w", err)
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return fmt.Errorf("notification webhook returned status %d", response.StatusCode)
	}
	return nil
}
