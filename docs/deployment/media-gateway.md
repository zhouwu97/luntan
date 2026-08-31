# 媒体网关部署闭环

`MEDIA_DELIVERY_MODE=gateway` 只在应用层提供鉴权和变体白名单；对象存储仍必须在部署层设置为私有。生产上线前逐项确认：

1. `media/` bucket 或 prefix 禁止匿名 `GET`，并撤销历史的公开 ACL、CDN Origin Access 和静态目录映射。
2. `STORAGE_INTERNAL_BASE_URL` 只解析到服务端可访问的内网源站，不向浏览器、客户端或公网 DNS 暴露。
3. 若设置 `MEDIA_INTERNAL_ACCEL_PREFIX`，Nginx 的对应 location 必须带 `internal`；公网只能进入 `/api/v1/media-file/`，不能直接进入该前缀。
4. 修改 ACL 后清理 CDN 与浏览器缓存，并用匿名请求分别验证源图、普通变体和 `censored_*` 变体。

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
