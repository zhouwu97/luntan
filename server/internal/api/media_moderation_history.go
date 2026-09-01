package api

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"time"

	"github.com/zhouwu97/luntan/server/internal/media"
	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

// listMediaModerationHistory 返回媒体的只读版本链。存储对象键只在服务端
// 留存，不返回给客户端，避免把原图或内部对象路径泄露到管理端以外的范围。
func (s *Server) listMediaModerationHistory(w http.ResponseWriter, r *http.Request, mediaID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if !s.canModerate(r, user) {
		writeAuthError(w, r, ErrPermissionDenied)
		return
	}

	rows, err := s.db.QueryContext(r.Context(), `
		SELECT id, version_no, moderation_status, mask_regions::text,
		       operator_id, reason, created_at
		FROM media_moderation_versions
		WHERE media_id = $1
		ORDER BY version_no ASC`, mediaID)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()

	items := make([]map[string]any, 0)
	for rows.Next() {
		var id, status, rawRegions, reason string
		var versionNo int
		var operatorID sql.NullString
		var createdAt time.Time
		if err := rows.Scan(&id, &versionNo, &status, &rawRegions, &operatorID, &reason, &createdAt); err != nil {
			writeInternalError(w, r, err)
			return
		}
		regions := make([]media.MaskRegion, 0)
		if rawRegions != "" {
			if err := json.Unmarshal([]byte(rawRegions), &regions); err != nil {
				writeInternalError(w, r, err)
				return
			}
		}
		item := map[string]any{
			"id":                id,
			"media_id":          mediaID,
			"version_no":        versionNo,
			"moderation_status": status,
			"mask_regions":      regions,
			"reason":            reason,
			"is_initial":        versionNo == 1,
			"created_at":        createdAt,
		}
		if operatorID.Valid && operatorID.String != "" {
			item["operator_id"] = operatorID.String
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items})
}
