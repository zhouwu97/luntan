package outbox

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestNotificationHandlerSendsChinesePushPayload(t *testing.T) {
	var receivedBody []byte
	var receivedContentType string
	pushServer := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		receivedContentType = request.Header.Get("Content-Type")
		receivedBody, _ = io.ReadAll(request.Body)
		writer.WriteHeader(http.StatusAccepted)
	}))
	defer pushServer.Close()

	payload, err := json.Marshal(map[string]any{
		"recipient_id": "user-1",
		"actor_id":     "user-2",
		"type":         "comment.replied",
		"target_type":  "post",
		"target_id":    "post-1",
		"target_data":  map[string]any{"content": "你好，世界"},
	})
	if err != nil {
		t.Fatal(err)
	}

	handler := NotificationHandler{
		WebhookURL: pushServer.URL,
		Client:     pushServer.Client(),
	}
	if err := handler.Handle(context.Background(), Event{
		ID:          "event-1",
		EventType:   "notification.created",
		AggregateID: "notification-1",
		Payload:     payload,
	}); err != nil {
		t.Fatalf("推送通知失败：%v", err)
	}

	if receivedContentType != "application/json; charset=utf-8" {
		t.Fatalf("中文推送必须声明 UTF-8 Content-Type，实际为 %q", receivedContentType)
	}
	var pushPayload struct {
		Locale string `json:"locale"`
		Title  string `json:"title"`
		Body   string `json:"body"`
		Data   struct {
			NotificationID string `json:"notification_id"`
			TargetID       string `json:"target_id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(receivedBody, &pushPayload); err != nil {
		t.Fatalf("推送 JSON 无法解析：%v", err)
	}
	if pushPayload.Locale != "zh-CN" || pushPayload.Title == "" || pushPayload.Body != "你好，世界" {
		t.Fatalf("中文推送内容不完整：%s", receivedBody)
	}
	if pushPayload.Data.NotificationID != "notification-1" || pushPayload.Data.TargetID != "post-1" {
		t.Fatalf("推送跳转数据不完整：%s", receivedBody)
	}
	if !strings.Contains(string(receivedBody), "你好，世界") {
		t.Fatalf("推送正文没有以 UTF-8 写入：%s", receivedBody)
	}
}
