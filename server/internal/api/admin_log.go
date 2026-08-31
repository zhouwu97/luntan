package api

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"time"
)

// appendAdminLogTx 将管理员动作写入 append-only hash 链。链头在单行表上加锁，
// 保证并发操作也只有一个合法 previous_hash，删除或篡改历史会被数据库触发器拒绝。
func appendAdminLogTx(ctx context.Context, tx *sql.Tx, operatorID, action, targetType, targetID, reason, requestID, ipAddress string, payload map[string]any, now time.Time) error {
	var previousHash string
	if err := tx.QueryRowContext(ctx, `SELECT last_hash FROM admin_log_chain WHERE id = 1 FOR UPDATE`).Scan(&previousHash); err != nil {
		return err
	}
	data, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	id := newPostID()
	canonical := fmt.Sprintf("%s|%s|%s|%s|%s|%s|%s|%s|%s", id, previousHash, operatorID, action, targetType, targetID, reason, requestID, now.UTC().Format(time.RFC3339Nano))
	digest := sha256.Sum256(append([]byte(canonical+"|"), data...))
	hash := hex.EncodeToString(digest[:])
	if _, err := tx.ExecContext(ctx, `INSERT INTO admin_logs (id, operator_id, action, target_type, target_id, reason, payload, previous_hash, hash, request_id, ip_address, created_at) VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8, $9, $10, $11, $12)`, id, operatorID, action, targetType, targetID, reason, data, previousHash, hash, requestID, ipAddress, now); err != nil {
		return err
	}
	_, err = tx.ExecContext(ctx, `UPDATE admin_log_chain SET last_hash = $1 WHERE id = 1`, hash)
	return err
}

func appendAdminLog(ctx context.Context, db *sql.DB, operatorID, action, targetType, targetID, reason, requestID, ipAddress string, payload map[string]any, now time.Time) error {
	if db == nil {
		return nil
	}
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if err := appendAdminLogTx(ctx, tx, operatorID, action, targetType, targetID, reason, requestID, ipAddress, payload, now); err != nil {
		return err
	}
	return tx.Commit()
}
