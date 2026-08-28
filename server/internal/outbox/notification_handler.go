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
		RecipientID string         `json:"recipient_id"`
		ActorID     string         `json:"actor_id"`
		Type        string         `json:"type"`
		TargetType  string         `json:"target_type"`
		TargetID    string         `json:"target_id"`
		TargetData  map[string]any `json:"target_data"`
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
	pushBodyText := notificationPushBody(payload.TargetData)
	body, err := json.Marshal(map[string]any{
		"event_id":        event.ID,
		"event_type":      event.EventType,
		"notification_id": event.AggregateID,
		"recipient_id":    payload.RecipientID,
		"locale":          "zh-CN",
		"title":           notificationPushTitle(payload.Type, payload.TargetData),
		"body":            pushBodyText,
		"data": map[string]any{
			"notification_id": event.AggregateID,
			"type":            payload.Type,
			"actor_id":        payload.ActorID,
			"target_type":     payload.TargetType,
			"target_id":       payload.TargetID,
			"target_data":     payload.TargetData,
		},
	})
	if err != nil {
		return err
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, h.WebhookURL, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("create notification webhook request: %w", err)
	}
	// 明确声明 UTF-8，避免部分推送网关按默认字符集解码中文标题和正文。
	request.Header.Set("Content-Type", "application/json; charset=utf-8")
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

func notificationPushTitle(notificationType string, targetData map[string]any) string {
	if customTitle := notificationDataString(targetData, "title"); customTitle != "" {
		return customTitle
	}
	switch notificationType {
	case "like", "post.liked":
		return "收到新的点赞"
	case "bookmark", "post.bookmarked":
		return "收到新的收藏"
	case "comment.created", "comment.replied", "reply":
		return "收到新的评论回复"
	case "follow", "user.followed":
		return "收到新的关注"
	case "moderation.action":
		switch notificationDataString(targetData, "action") {
		case "mute":
			return "账号禁言通知"
		case "ban":
			return "账号封禁通知"
		case "delete":
			return "帖子处理通知"
		case "hide":
			return "内容处理通知"
		default:
			return "内容处理通知"
		}
	case "appeal.result":
		switch notificationDataString(targetData, "status") {
		case "approved":
			return "申诉已通过"
		case "rejected":
			return "申诉未通过"
		default:
			return "申诉结果通知"
		}
	case "announcement", "community.announcement":
		return "社区公告"
	case "event", "community.event":
		return "活动通知"
	default:
		return "你有一条新通知"
	}
}

func notificationPushBody(targetData map[string]any) string {
	for _, key := range []string{"content", "snippet", "message", "body", "reason", "post_title", "description"} {
		if value := notificationDataString(targetData, key); value != "" {
			return value
		}
	}
	return "打开圣杯酱查看详情"
}

func notificationDataString(data map[string]any, key string) string {
	value, ok := data[key].(string)
	if !ok {
		return ""
	}
	return strings.TrimSpace(value)
}
