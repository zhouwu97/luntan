# 媒体网关部署闭环

`MEDIA_DELIVERY_MODE=gateway` 只在应用层提供鉴权和变体白名单；对象存储仍必须在部署层设置为私有。生产上线前逐项确认：

1. `media/` bucket 或 prefix 禁止匿名 `GET`，并撤销历史的公开 ACL、CDN Origin Access 和静态目录映射。
2. 先运行 `/app/luntan-media-backfill --dry-run` 检查待回填图片数量，再运行
   `/app/luntan-media-backfill` 投递 `media.process`，等待 worker 消费完成。
   使用下面的查询确认所有 ready 图片均有 ready 的 `original`、`detail`、`thumb`：

   ```sql
   SELECT count(*) AS pending_backfill
   FROM media_assets ma
   WHERE ma.status = 'ready' AND ma.deleted_at IS NULL AND ma.mime_type LIKE 'image/%'
     AND NOT (
       EXISTS (SELECT 1 FROM media_variants mv WHERE mv.media_id = ma.id AND mv.variant = 'original' AND mv.status = 'ready')
       AND EXISTS (SELECT 1 FROM media_variants mv WHERE mv.media_id = ma.id AND mv.variant = 'detail' AND mv.status = 'ready')
       AND EXISTS (SELECT 1 FROM media_variants mv WHERE mv.media_id = ma.id AND mv.variant = 'thumb' AND mv.status = 'ready')
     );
   ```

   `pending_backfill` 必须为 0，且 `outbox_events` 中 `media.process` 与
   `media.delete` 两类事件的 `failed` 数量都必须为 0：

   ```sql
   SELECT event_type, count(*) AS failed_events
   FROM outbox_events
   WHERE event_type IN ('media.process', 'media.delete') AND status = 'failed'
   GROUP BY event_type;
   ```

   QA 使用本地磁盘时，`MEDIA_STORAGE_DIR` 通常指向 `.../imported-media/user-media`。
   历史 `object_key` 若是 `http(s)://旧域名/imported-media/...`，服务会仅按固定
   `imported-media/` 前缀映射到其父目录；该父目录必须允许 Worker 用户写入生成的变体。
3. `STORAGE_INTERNAL_BASE_URL` 只解析到服务端可访问的内网源站，不向浏览器、客户端或公网 DNS 暴露。
4. 若设置 `MEDIA_INTERNAL_ACCEL_PREFIX`，Nginx 的对应 location 必须带 `internal`；公网只能进入 `/api/v1/media-file/`，不能直接进入该前缀。
5. 修改 ACL 后清理 CDN 与浏览器缓存，并用匿名请求分别验证源图、旧 object key、普通变体和 `censored_*` 变体。
   打码媒体的 `/api/v1/media-file/{id}/original` 必须对普通用户和管理员都拒绝；
   管理员源图只能通过带 JWT 的 `/api/v1/admin/media/{id}/source` 获取，审核证据
   预览使用 `/api/v1/admin/media/{id}/preview`，二者都必须返回
   `Cache-Control: private, no-store`。

下面是使用 Nginx 代理内网对象存储的最小模板。请替换 upstream、TLS 和鉴权细节，不要把 `object-storage-internal` 指向公网地址：

```nginx
location ^~ /api/v1/media-file/ {
    proxy_pass http://luntan_api;
}

location ^~ /_protected_media/ {
    internal;
    proxy_pass http://object-storage-internal/;
}

# 用户上传源图不允许通过旧路径直出。
location ^~ /media/ {
    return 404;
}
```

应用配置应同时满足：`MEDIA_DELIVERY_MODE=gateway`、`OBJECT_STORAGE_PUBLIC_BASE_URL` 为空、`STORAGE_INTERNAL_BASE_URL` 已设置。应用启动校验会拒绝不一致的配置，但无法替代对象存储控制台中的匿名访问检查。
