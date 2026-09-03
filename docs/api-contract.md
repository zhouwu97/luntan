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

Web 端请求必须带与服务端 `WEB_ORIGIN`（默认 `https://shengbeijiang.com`）完全一致的
`Origin`。此时 `refresh_token` 字段为空，长期令牌只通过 `HttpOnly`、`SameSite=Lax`
的 Cookie 下发和轮换；`/auth/refresh` 不再接受 JSON 中的 refresh token。原生端不带该
Web Origin，继续从响应体读取 `refresh_token`，且服务端不设置 refresh Cookie。

### 活动 Activities

| 方法 | 路径 | 登录 | 说明 |
|---|---|---|---|
| GET | `/activities` | 否 | 只返回已发布活动 |
| GET | `/admin/activities` | 平台管理员 | 管理活动，可按 `status` 筛选 |
| POST | `/admin/activities` | 平台管理员 | 创建活动 |
| PUT | `/admin/activities/{id}` | 平台管理员 | 更新活动 |
| POST | `/admin/activities/{id}/publish` | 平台管理员 | 发布活动 |
| POST | `/admin/activities/{id}/offline` | 平台管理员 | 下架活动 |
| DELETE | `/admin/activities/{id}` | 平台管理员 | 软删除活动 |

活动响应同时返回 `publication_status`（`draft|published|offline`）和
`phase`（已发布时为 `upcoming|active|ended`）。兼容字段 `status` 在草稿/下架时表示
发布状态，在已发布时表示按 `start_at/end_at` 动态计算的阶段；时间阶段不会写回发布状态。

活动是独立业务实体，不是普通帖子的 `type`。客户端创建或编辑活动必须使用上述
`/admin/activities` 接口；向 `/posts` 写入 `type=activity` 会返回
`ACTIVITY_USE_ACTIVITY_API`（409）。历史帖子中的该类型仅作读取兼容。

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
| `latest_by` | string | `comment`(默认，按最近回复) / `post`(按发布时间) |

排序语义：

- `latest`：默认按最近回复时间倒序；指定 `latest_by=post` 时按 `published_at DESC`。
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
| ~~POST~~ | ~~`/posts/{id}/market`~~ | ~~是~~ | ~~创建集市帖~~ **已禁用** |

发帖请求：
```json
{
  "community_id": "string",
  "type": "normal|game_share|poll|question",
  "title": "string",
  "content": "string",
  "media_ids": ["string"],
  "poll": {
    "question": "string",
    "options": ["A", "B"],
    "allow_multiple": false,
    "ends_at": "RFC3339|null"
  }
}
```
头：`Idempotency-Key: <uuid>`。响应：`{ "id": "string", ... }`。
`type=poll` 时 `poll` 必填；所有子资源在同一事务中提交，任一步失败全部回滚。

> **注意**: `type=market` 和 `/posts/{id}/market` 端点已禁用。历史市场帖数据仅保留用于兼容，不再创建或展示新的市场帖子。

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

### 个人中心列表 Profile Lists

`GET /me/profile` 与公开的 `GET /users/{id}` 都返回 `public_id` 字符串。
正式账号在注册或游客绑定邮箱时从 `10000` 起按序分配；游客返回空字符串，
客户端展示为“注册后生成”。内部 `id` 仍是资源关联使用的 UUID，不直接展示给用户。

| 方法 | 路径 | 登录 | 说明 |
|---|---|---|---|
| GET | `/me/posts?cursor=&limit=&include_details=` | 是 | 我的发帖列表 |
| GET | `/me/comments?cursor=&limit=&include_details=` | 是 | 我的评论列表（返回收到回复的帖子） |
| GET | `/me/likes?cursor=&limit=&include_details=` | 是 | 我的点赞列表 |
| GET | `/me/bookmarks?cursor=&limit=&include_details=` | 是 | 我的收藏列表（跨收藏夹） |
| GET | `/me/history?cursor=&limit=&include_details=` | 是 | 浏览历史 |
| DELETE | `/me/history` | 是 | 清空浏览历史 |

所有端点返回 `{items: [ProfilePostItem], next_cursor, has_more}`。

`ProfilePostItem` 字段：
- `id`, `title`, `content_preview`, `community_id`, `community_name`
- `comment_count`, `like_count`, `bookmark_count`, `published_at`
- `comment_id` (仅 `/me/comments` 返回，标识用户在该帖中的评论)
- `activity_at` (用户最后互动时间，用于 `/me/comments` 排序)

`include_details=1` 时返回完整帖子字段（作者、媒体、viewer_state），适合直接渲染卡片。
默认返回轻量版本，适合列表展示。

### 评论 Comments

| 方法 | 路径 | 登录 | 说明 |
|---|---|---|---|
| GET | `/posts/{id}/comments?sort=&cursor=&limit=` | 否 | 按帖分页；`sort=desc` 默认新发布楼层优先，`asc` 为早发布楼层优先，`hot` 为热度排序 |
| POST | `/posts/{id}/comments` | 是 | 发布评论（支持 `parent_id` 楼中楼，需幂等键） |
| POST | `/comments/{id}/replies` | 是 | 回复评论（需幂等键） |
| PATCH | `/comments/{id}` | 是 | 编辑 |
| DELETE | `/comments/{id}` | 是（管理权限） | 管理员软删除评论 |
| PUT/DELETE | `/comments/{id}/like` | 是 | 评论点赞/取消 |

分页结构与 feed 一致（`{items, next_cursor, has_more}`）。
评论创建请求必须带 `Idempotency-Key`；服务端按 `(user_id, idempotency_key)` 去重，重试返回首次创建的评论。

### 榜单评价 Ranking Toy Comments

| 方法 | 路径 | 登录 | 说明 |
|---|---|---|---|
| GET | `/ranking/toys/{id}/comments?sort=weight\|latest&cursor=&limit=` | 否 | 只分页一级评价 |
| GET | `/ranking/toy-comments/{id}/replies?cursor=&limit=` | 否 | 按 `root_id` 分页整座楼的扁平回复 |
| POST | `/ranking/toys/{id}/comments` | 是 | 发布一级评价或指定 `parent_id` 回复 |
| PUT/DELETE | `/ranking/toy-comments/{id}/like` | 是 | 评价或楼中楼回复点赞/取消 |
| DELETE | `/ranking/toy-comments/{id}` | 是（管理权限） | 管理员软删除一级评价或楼中楼回复（删一级评价级联软删除整楼回复），守恒维护 reply_count |

榜单根评价的 `reply_count` 表示整座楼的回复总数；回复二级评论时仍保持原始
`parent_id`，但客户端在独立楼中楼中按 `root_id` 平铺展示。

### 媒体 Media

| 方法 | 路径 | 登录 | 说明 |
|---|---|---|---|
| POST | `/media/upload-token` | 是 | 申请上传凭证 |
| POST | `/media/{id}/complete` | 是 | 完成校验（所有权/SHA-256/MIME/大小） |

上传流程：本地压缩 → 计算 SHA-256 → `upload-token` 换取对象存储直传地址 →
直传 → `complete` → `posts` 引用 `media_ids`。未 `complete` 的媒体视为
pending，服务端有清理接口。媒体响应不返回对象存储内部 `object_key`；客户端只应
保存 `media_id` 并通过受控媒体 URL 展示。帖子、评论只有在已发布且审核状态为
`normal` 时才能使媒体公开可见。

### 积分商店 Store

| 方法 | 路径 | 登录 | 说明 |
|---|---|---|---|
| GET | `/store/products` | 是 | 商品列表 |
| GET | `/me/points` | 是 | 我的积分余额与流水 |
| POST | `/store/orders` | 是 | 兑换（需幂等键） |
| GET | `/me/store-orders` | 是 | 我的兑换记录 |
| GET | `/admin/store/orders` | 管理员 | 兑换申请分页；`status` 支持 `pending_review`、`approved`、`rejected`、`all` |
| GET | `/admin/store/orders/{id}` | 管理员 | 申请快照、历史无效积分与兑换资格 |
| GET | `/admin/store/orders/{id}/reward-content` | 管理员 | 按申请时间截止的发帖/评论奖励证据分页 |
| POST | `/admin/store/orders/{id}/review` | 管理员 | 审核并提交不计入兑换的积分流水 |

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

发帖、点赞与评论奖励统一通过幂等事件键写入流水。固定规则为：发帖 +5、
点赞 +1、评论 +1，并按北京时间自然日限制每位用户最多获得 20 积分；
当日剩余额度不足时只补足到 20，兑换扣分不占用当日获取额度。

兑换审核的 `POST /admin/store/orders/{id}/review` 请求体为：
```json
{
  "decision": "approve",
  "reason": "存在无实质内容的回复",
  "invalid_transaction_ids": ["point-transaction-id"]
}
```
`invalid_transaction_ids` 只能选择该申请提交时已经产生的发帖/评论奖励流水。
服务端会将其持久化为兑换资格无效记录，并按
`balance_at_submit - 历史无效积分 - 本次新判定无效积分` 计算有效积分；
新获得的积分不能补足本次申请。奖励证据接口支持 `cursor`、`limit`、`source`
和 `status` 参数，默认按删除/不可见、已编辑、正常内容优先返回。
审核结果响应会返回 `new_invalidated_count` 与 `new_invalidated_points`；兑换审核
列表还会返回审核时间、审核人、该订单新增的无效奖励数/积分，以及
`balance_snapshot_trusted`。迁移前订单的余额只能作为参考，不能视为真实提交时余额。
商品列表中的 `redeemed_count` 只统计 `claimed` 与 `completed` 订单，不统计待审核、
驳回、取消或仅审核通过但尚未领取的订单。

### 通知与搜索

| 方法 | 路径 | 登录 | 说明 |
|---|---|---|---|
| GET | `/notifications?cursor=` | 是 | 通知分页 |
| POST | `/notifications/read-all` | 是 | 全部已读 |
| PATCH | `/notifications/{id}/read` | 是 | 单条已读 |
| GET | `/notifications/unread-count` | 是 | 未读数 |
| GET | `/search?q=&type=&cursor=` | 是 | 搜索；选择帖子/用户/社区分类后使用 cursor 分页，综合搜索不接受 cursor |

通知分类使用 `all`、`interaction`、`community`、`moderation`；处罚通知的
`target_data` 带有 `moderation_action_id` 和 `appealable`，客户端据此进入正式处理详情。

### 审核案件 Moderation Cases

| 方法 | 路径 | 登录 | 说明 |
|---|---|---|---|
| GET | `/moderation/cases?status=&source=&cursor=&limit=` | 管理员 | 案件游标分页；`source` 支持 `user_report`、`auto_rule`、`manual_admin`，筛选在服务端分页前执行 |
| GET | `/moderation/cases/{id}` | 管理员 | 返回案件目标、举报汇总、账号信息和 `target.media` 图片/视频证据 |
| POST | `/moderation/cases/{id}/actions` | 管理员 | 提交隐藏、恢复、删除、禁言或封禁处置 |
| GET | `/admin/media/{id}/preview` | 管理员 | 私有审核预览；支持 pending/hidden 附件，响应 `Cache-Control: private, no-store` |
| GET | `/admin/media/{id}/source` | 管理员 | 私有审核源图；仅供打码编辑器读取，响应 `Cache-Control: private, no-store` |

`target.media` 中每项包含 `id`、`type`、`width`、`height`、`moderation_status`、
`thumb_url`、`detail_url` 和 `preview_url`。这些 URL 均指向管理员私有预览路由，
不暴露对象存储 `object_key`，也不依赖公开媒体网关的帖子/评论可见性。
普通媒体审核预览优先使用 `detail` 变体；已打码媒体优先使用
`censored_detail`，缺失时才回退到管理员可见的源对象。

### 处罚与申诉 Moderation Appeals

| 方法 | 路径 | 登录 | 说明 |
|---|---|---|---|
| GET | `/moderation-actions/{id}` | 是 | 当前用户查看自己的可申诉处理详情 |
| POST | `/moderation-actions/{id}/appeals` | 是 | 针对一个处罚动作提交一次申诉，最多 3 个 `media_ids` |
| GET | `/appeals` | 是 | 查看自己的申诉记录，可按 `status` 过滤 |
| GET | `/appeals/{id}` | 是 | 查看自己的申诉详情和复核状态 |
| GET | `/moderation/appeals` | 管理员 | 管理员查看申诉案件 |
| GET | `/moderation/appeals/{id}` | 管理员 | 查看原内容、处罚和证据 |
| POST | `/moderation/appeals/{id}/review` | 管理员 | 提交 `{ "result": "approved|rejected", "note": "..." }` |

申诉动作、内容恢复、申诉结果通知和 outbox 事件在同一事务中提交；同一
`moderation_action_id` 只能存在一条申诉，已完成的申诉不允许重复提交。

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
| `TARGET_ROLE_PROTECTED` | 403 | 操作者不能处罚同级或更高角色账号 |
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
| `APPEAL_NOT_FOUND` | 404 | 申诉或处罚动作不存在 |
| `APPEAL_NOT_ALLOWED` | 403 | 该处理不可申诉或不属于当前用户 |
| `APPEAL_ALREADY_EXISTS` / `APPEAL_ALREADY_REVIEWED` | 409 | 申诉重复或已完成复核 |

> 客户端统一经 `ApiClient` 将 `code` 映射为 `ApiErrorType`，不直接依赖
> `message` 文案。
