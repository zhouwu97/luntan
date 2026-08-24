# 浅蓝论坛 API 契约（v1）

> 这份契约是 Flutter 客户端与服务端之间的事实基准。任何端点行为变更都必须
> 同步更新本文件。完整清单以 `server/internal/api/api.go` 的路由为准。

## 通用约定

- **Base URL**：`$API_BASE_URL/api/v1`（`API_BASE_URL` 编译期注入）。
- **认证**：除公开读接口外，均需 `Authorization: Bearer <access_token>`。
  access token 过期返回 `401`，客户端用 refresh token 走 `/auth/refresh`
  （服务端轮换 refresh token）。只有服务端明确返回 refresh token 失效时才清理本端凭证；网络超时、断网和 5xx 保留会话，等待重试。
- **错误响应**：`HTTP 4xx/5xx` + JSON
  ```json
  { "code": "INVALID_CURSOR", "message": "cursor 无效", "request_id": "req_xxx", "details": null }
  ```
  `code` 稳定可枚举，`message` 面向用户、可本地化；客户端保留 `code`、`request_id` 和 `details`。
- **分页**：键集游标，不返回 offset。
  - `latest`：游标 `(published_at, id)`，保序键即发布时间。
  - `recommended` / `hot` / `featured`：游标 `(score, published_at, id)`，
    评分随互动计数实时变化，游标存在轻微漂移上限；跨排序复用游标会被拒绝。
  - 响应 `next_cursor` 为空表示没有更多；`has_more` 辅助是否显示“加载中”。
- **幂等**：创建类接口支持 `Idempotency-Key` 请求头。重复提交（含重试/连点）
  返回同一条资源，不产生重复数据。缺失幂等键的创建接口返回
  `IDEMPOTENCY_KEY_REQUIRED`。
- **时间**：RFC3339（`timestamptz` 原样序列化）。

## 端点

### 认证 Auth

| 方法 | 路径 | 登录 | 说明 |
|---|---|---|---|
| POST | `/auth/register` | 否 | 注册并返回会话 |
| POST | `/auth/login` | 否 | 登录，返回会话 |
| POST | `/auth/refresh` | 否 | 轮换 refresh token，返回新会话 |
| POST | `/auth/logout` | 是 | 撤销当前会话 |
| GET | `/me` | 是 | 当前用户概要 |

注册/登录请求：
```json
{ "username": "string", "password": "string", "nickname": "string(可选)" }
```
响应（会话）：
```json
{
  "access_token": "string",
  "refresh_token": "string",
  "user": { "id": "string", "username": "string", "nickname": "string", "level": 1 }
}
```

### Feed

| 方法 | 路径 | 登录 | 说明 |
|---|---|---|---|
| GET | `/feed/latest` | 否 | 按排序返回帖子列表 |

参数：

| 参数 | 类型 | 说明 |
|---|---|---|
| `limit` | int | 1–50，默认 20 |
| `cursor` | string | 上一页 `next_cursor` |
| `community_id` | string | 按板块过滤 |
| `sort` | string | `latest`(默认) / `recommended` / `featured` / `hot` |

排序语义：

- `latest`：`published_at DESC`。
- `recommended`：加权互动（like/comment/bookmark/share/view）+ 平缓时间衰减，
  与 `latest` 不同源。
- `hot`：更快衰减的热度排序，倾向近期热点。
- `featured`：加权互动分，不叠加时间衰减，不再只按评论数；当前阶段由
  服务端公式排序（策展列随阶段6“加精”动作接入）。

响应：
```json
{
  "items": [ /* postResponse，见下 */ ],
  "next_cursor": "string|null",
  "has_more": true
}
```

`postResponse` 关键字段：`id`、`author{id,username,nickname,level}`、
`community{id,slug,name}`、`type`、`title`、`content_preview`、`comment_count`、
`like_count`、`bookmark_count`、`share_count`、`view_count`、`created_at`、
`updated_at`、`published_at`、`moderation_status`、`viewer_state{liked,bookmarked,...}`
（登录且 `include_details=1` 时返回）。

### 帖子 Post

| 方法 | 路径 | 登录 | 说明 |
|---|---|---|---|
| POST | `/posts` | 是 | 发帖（需幂等键；投票/集市正文与帖子原子创建） |
| GET | `/posts/{id}?include_details=1` | 否 | 详情 |
| PATCH | `/posts/{id}` | 是 | 编辑 |
| DELETE | `/posts/{id}` | 是 | 删除 |
| PUT/DELETE | `/posts/{id}/like` | 是 | 点赞/取消 |
| PUT/DELETE | `/posts/{id}/bookmark` | 是 | 收藏/取消 |
| GET | `/posts/{id}/bookmark-folders` | 是 | 获取帖子所在收藏夹 |
| PUT | `/posts/{id}/bookmark-folders` | 是 | 覆盖帖子收藏夹归属；空数组表示取消收藏 |
| POST | `/posts/{id}/history` | 是 | 记录浏览历史 |
| POST | `/posts/{id}/poll` | 是 | 创建投票 |
| POST | `/posts/{id}/market` | 是 | 创建集市帖 |

发帖请求：
```json
{
  "community_id": "string",
  "type": "normal|game_share|poll|market|question",
  "title": "string",
  "content": "string",
  "media_ids": ["string"],
  "poll": {
    "question": "string",
    "options": ["A", "B"],
    "allow_multiple": false,
    "ends_at": "RFC3339|null"
  },
  "market": {
    "price": 12.5,
    "currency": "CNY",
    "condition": "九成新",
    "delivery": "面交"
  }
}
```
头：`Idempotency-Key: <uuid>`。响应：`{ "id": "string", ... }`。
`type=poll` 时 `poll` 必填，`type=market` 时 `market` 必填；所有子资源在同一事务中提交，任一步失败全部回滚。

### 收藏夹 Bookmark Folders

| 方法 | 路径 | 登录 | 说明 |
|---|---|---|---|
| GET | `/me/bookmark-folders?cursor=&limit=` | 是 | 收藏夹列表及内容数量 |
| POST | `/me/bookmark-folders` | 是 | 新建收藏夹 |
| PATCH | `/me/bookmark-folders/{id}` | 是 | 重命名或调整 `sort_order` |
| DELETE | `/me/bookmark-folders/{id}` | 是 | 删除自定义收藏夹；默认收藏夹不可删除 |
| GET | `/me/bookmark-folders/{id}/posts?cursor=&limit=` | 是 | 收藏夹内容分页 |

`bookmarks(post_id, user_id)` 仍表示唯一的收藏事实；
`bookmark_folder_items(folder_id, post_id)` 只表示分类关系。一个帖子进入多个收藏夹
只增加一次 `bookmark_count`。旧的 bookmark PUT 会自动归入默认收藏夹，旧 DELETE
会清除所有收藏夹归属并取消收藏。删除自定义收藏夹时，没有其他归属的帖子会回到默认收藏夹。

### 评论 Comments

| 方法 | 路径 | 登录 | 说明 |
|---|---|---|---|
| GET | `/posts/{id}/comments?cursor=&limit=` | 是 | 按帖分页 |
| POST | `/posts/{id}/comments` | 是 | 发布评论（支持 `parent_id` 楼中楼，需幂等键） |
| POST | `/comments/{id}/replies` | 是 | 回复评论（需幂等键） |
| PATCH | `/comments/{id}` | 是 | 编辑 |
| DELETE | `/comments/{id}` | 是 | 删除 |
| PUT/DELETE | `/comments/{id}/like` | 是 | 评论点赞/取消 |

分页结构与 feed 一致（`{items, next_cursor, has_more}`）。
评论创建请求必须带 `Idempotency-Key`；服务端按 `(user_id, idempotency_key)` 去重，重试返回首次创建的评论。

### 媒体 Media

| 方法 | 路径 | 登录 | 说明 |
|---|---|---|---|
| POST | `/media/upload-token` | 是 | 申请上传凭证 |
| POST | `/media/{id}/complete` | 是 | 完成校验（所有权/SHA-256/MIME/大小） |

上传流程：本地压缩 → 计算 SHA-256 → `upload-token` 换取对象存储直传地址 →
直传 → `complete` → `posts` 引用 `media_ids`。未 `complete` 的媒体视为
pending，服务端有清理接口。

### 积分商店 Store

| 方法 | 路径 | 登录 | 说明 |
|---|---|---|---|
| GET | `/store/products` | 是 | 商品列表 |
| GET | `/me/points` | 是 | 我的积分余额与流水 |
| POST | `/store/orders` | 是 | 兑换（需幂等键） |
| GET | `/me/store-orders` | 是 | 我的兑换记录 |

兑换请求头 `Idempotency-Key` 与正文 `{ "product_id": "string" }` 共同保证
幂等；重复请求返回既有订单，不重复扣分。错误码含 `INSUFFICIENT_POINTS`、
`PRODUCT_UNAVAILABLE`。

`/me/points` 响应包含：
```json
{
  "balance": 3980,
  "transactions": [{
    "id": "string", "source": "store", "delta": -350,
    "balance_after": 3980, "reason": "主题贴纸包",
    "created_at": "2026-08-24T08:00:00Z"
  }]
}
```

发帖与评论奖励统一通过幂等事件键写入流水；奖励数值由
`POINT_REWARD_POST_CREATE`、`POINT_REWARD_COMMENT_CREATE` 配置，未配置时为 0，
避免在规则确认前擅自改变积分余额。

### 通知与搜索

| 方法 | 路径 | 登录 | 说明 |
|---|---|---|---|
| GET | `/notifications?cursor=` | 是 | 通知分页 |
| POST | `/notifications/read-all` | 是 | 全部已读 |
| PATCH | `/notifications/{id}/read` | 是 | 单条已读 |
| GET | `/notifications/unread-count` | 是 | 未读数 |
| GET | `/search?q=&type=&cursor=` | 是 | 搜索；选择帖子/用户/社区分类后使用 cursor 分页，综合搜索不接受 cursor |

## 已知错误码

错误统一由 `writeAuthError` / `httpserver.WriteAppError` 输出，代码表如下
（完整映射见 `server/internal/api/api.go`）：

| code | HTTP | 说明 |
|---|---|---|
| `INVALID_INPUT` | 400 | 请求参数不合法 |
| `INVALID_CREDENTIALS` | 401 | 用户名或密码错误 |
| `INVALID_TOKEN` | 401 | 登录状态已失效（含 refresh token 失效） |
| `USERNAME_TAKEN` | 409 | 用户名不可用 |
| `USER_DISABLED` | 403 | 账户当前不可用 |
| `FORBIDDEN` / `PERMISSION_DENIED` | 403 | 无权限 |
| `COMMUNITY_NOT_FOUND` | 404 | 社区不存在或不可用 |
| `POST_NOT_FOUND` | 404 | 帖子不存在 |
| `COMMENT_NOT_FOUND` / `COMMENT_PARENT_NOT_FOUND` | 404 | 评论/回复目标不存在 |
| `MEDIA_NOT_FOUND` / `MEDIA_NOT_OWNED` | 404/403 | 媒体不存在 / 非本人媒体 |
| `IDEMPOTENCY_KEY_REQUIRED` | 400 | 创建接口缺失幂等键 |
| `INVALID_POST` / `INVALID_COMMENT` / `INVALID_MEDIA` | 400 | 内容不合法 |
| `INVALID_LIMIT` / `INVALID_CURSOR` / `INVALID_WINDOW` | 400 | 分页/窗口参数不合法 |
| `INSUFFICIENT_POINTS` | 409 | 积分不足 |
| `BOOKMARK_FOLDER_NOT_FOUND` | 404 | 收藏夹不存在 |
| `BOOKMARK_FOLDER_NAME_TAKEN` | 409 | 收藏夹名称已存在 |
| `DEFAULT_BOOKMARK_FOLDER_PROTECTED` | 400 | 默认收藏夹不能删除或重命名 |
| `INVALID_BOOKMARK_FOLDER_NAME` | 400 | 收藏夹名称不合法 |
| `STORAGE_UNAVAILABLE` / `DATABASE_UNAVAILABLE` | 503 | 依赖服务不可用 |
| `BLOCKED` | 403 | 该互动已被阻止 |

> 客户端统一经 `ApiClient` 将 `code` 映射为 `ApiErrorType`，不直接依赖
> `message` 文案。
