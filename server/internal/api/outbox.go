package api

import (
	"database/sql"
	"encoding/json"
	"time"
)

// enqueueOutboxTx 只负责在业务事务内落库；Worker 负责后续异步投递和重试。
func enqueueOutboxTx(tx *sql.Tx, eventType, aggregateType, aggregateID string, payload any, createdAt time.Time) error {
	body, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	_, err = tx.Exec(`
		INSERT INTO outbox_events (id, event_type, aggregate_type, aggregate_id, payload, status, available_at, created_at)
		VALUES ($1, $2, $3, $4, $5::jsonb, 'pending', $6, $6)`, newPostID(), eventType, aggregateType, aggregateID, body, createdAt)
	return err
}

func enqueueNotificationTx(tx *sql.Tx, recipientID, actorID, notificationType, targetType, targetID string, createdAt time.Time) error {
	return enqueueNotificationWithDataTx(tx, recipientID, actorID, notificationType, targetType, targetID, nil, createdAt)
}

func enqueueNotificationWithDataTx(tx *sql.Tx, recipientID, actorID, notificationType, targetType, targetID string, targetData map[string]any, createdAt time.Time) error {
	if recipientID == "" || recipientID == actorID {
		return nil
	}
	notificationID := newPostID()
	if targetData == nil {
		if _, err := tx.Exec(`
			INSERT INTO notifications (id, user_id, type, actor_id, target_type, target_id, is_read, created_at)
			VALUES ($1, $2, $3, $4, $5, $6, false, $7)`, notificationID, recipientID, notificationType, actorID, targetType, targetID, createdAt); err != nil {
			return err
		}
	} else if _, err := tx.Exec(`
		INSERT INTO notifications (id, user_id, type, actor_id, target_type, target_id, target_data, is_read, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, false, $8)`, notificationID, recipientID, notificationType, actorID, targetType, targetID, nullableJSON(targetData), createdAt); err != nil {
		return err
	}
	return enqueueOutboxTx(tx, "notification.created", "notification", notificationID, map[string]any{
		"recipient_id": recipientID,
		"actor_id":     actorID,
		"type":         notificationType,
		"target_type":  targetType,
		"target_id":    targetID,
		"target_data":  targetData,
	}, createdAt)
}

func nullableJSON(value map[string]any) any {
	if value == nil {
		return nil
	}
	body, err := json.Marshal(value)
	if err != nil {
		return nil
	}
	return body
}
