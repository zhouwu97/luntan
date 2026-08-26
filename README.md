# 杯友酱论坛

基于 Flutter 的玩具交流轻社区 App，采用“贴吧的信息结构 + 社区高效入口 + 浅蓝年轻化视觉”，提供帖子浏览、板块切换、搜索、发布、回复、互动和积分兑换等能力。

当前仓库同时包含：

- Flutter 客户端：Android / iOS / Web
- Go HTTP API：认证、板块、信息流、帖子、媒体、回复和互动接口
- 本地 mock 数据层：无需后端即可运行和验证 UI

## 当前状态

所有平台不传 `API_BASE_URL` 时统一使用本地 `ForumStore` mock 数据；只有显式传入 `API_BASE_URL` 才进入真实 API 模式，避免 Android、Web、桌面端行为不一致。API 模式的访问令牌保存在平台安全存储中，杀掉 App 后会自动恢复登录态，`ForumStore` 不参与正式业务写入。生产构建必须显式设置 `APP_ENV=production` 和 HTTPS API 地址；服务端会拒绝缺少数据库、对象存储或 SMTP 配置的生产启动。

已覆盖的主要功能：

- 首页：头像、搜索、消息、三大板块、快捷入口、推荐 / 最新 / 精华
- Feed：帖子卡片、作者等级、标签、摘要、图片 0 / 1 / 2 / 3 / 4+ 张布局
- 帖子：详情、图片画廊、回复 / 楼中楼、点赞、收藏、编辑、删除、举报、浏览历史
- 搜索：帖子、用户、板块
- 发布：普通帖子、投票、玩法分享；本地草稿持久化、退出前保存/放弃确认、上传中图片删除
- 我的：真实用户信息与统计、我的发帖 / 回帖 / 收藏 / 点赞 / 浏览历史
- 消息：通知列表、通知详情、已读和未读数、前台/下拉刷新
- 认证：邮箱验证码登录、游客模式（后台统一创建 guest user），不在客户端展示密码入口；邮箱验证码发送后锁定邮箱，支持明确“修改邮箱”
- 治理：账号处罚详情、申诉、管理员列表 / 详情 / 角色范围管理、风控中心、IP 限制、不可篡改审计日志
- 兑换商店：商品、积分余额、事务兑换单
- 投票：选项、服务端投票和票数
- 导航：`首页` / `+` / `我的`

首页快捷入口保留产品名称：`排行榜`、`热门帖子`、`穿搭分享`、`活动`、`玩法分享`。`玩法分享`同时作为发布类型和内容入口。

## 环境要求

- Flutter / Dart：以 `pubspec.yaml` 中的 SDK 约束为准
- Go：以 `server/go.mod` 中的版本约束为准
- PostgreSQL：仅在运行真实 API 和数据库迁移时需要

## 快速开始

### 仅运行 Flutter mock 模式

```bash
flutter pub get
flutter run
```

不传 `API_BASE_URL` 时，应用默认使用本地 mock 仓储，不要求启动 Go 服务或 PostgreSQL。真实 API 必须显式传入 `--dart-define=API_BASE_URL=...`。

### 运行 Web

```bash
flutter run -d chrome
```

构建 Release Web：

```bash
flutter build web --release
```

产物位于 `build/web/`。

## 启动 Go API

服务端使用 PostgreSQL。先创建数据库并设置连接串，然后在项目根目录执行：

PowerShell：

```powershell
$env:DATABASE_URL = "postgres://user:password@localhost:5432/luntan?sslmode=disable"
$env:HTTP_PORT = "8080"
go run .\server\cmd\api
```

Bash：

```bash
export DATABASE_URL="postgres://user:password@localhost:5432/luntan?sslmode=disable"
export HTTP_PORT=8080
go run ./server/cmd/api
```

服务启动时会自动执行 `server/migrations/` 下的数据库迁移（包含邮箱验证状态、游客会话、处罚限制、自动审核、风控、管理员角色范围、IP 限制和管理员哈希链日志）。生产环境必须同时配置 `APP_ENV=production`、`SMTP_HOST/SMTP_PORT/SMTP_USERNAME/SMTP_PASSWORD/SMTP_FROM` 以及 `OBJECT_STORAGE_UPLOAD_BASE_URL/OBJECT_STORAGE_SIGNING_SECRET`；可选配置 `PUSH_WEBHOOK_URL/PUSH_WEBHOOK_SECRET` 将通知投递到站外推送，未配置时仍会持久化站内通知。开发环境未配置 SMTP 时，验证码接口会返回 `dev_code` 便于联调，生产环境不会返回验证码。健康检查为 `/ready`，默认地址为 `http://localhost:8080`。

## 连接 Flutter 客户端与 API

`API_BASE_URL` 是编译期 Dart define：

```bash
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8080
```

分享链接使用 `WEB_BASE_URL` 生成真实 Web/Universal Link；未配置时默认使用
`https://luntan.app`。发布环境请替换为已配置域名：

```bash
flutter build apk --release --dart-define=WEB_BASE_URL=https://forum.example.com
```

构建时同样传入：

```bash
flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

Android 模拟器访问宿主机时通常使用 `10.0.2.2`，真机请替换为电脑在局域网中的 IP，并确认服务监听和防火墙规则允许访问。

### 远端占位展示数据

QA 服务器通过 `http://101.42.27.44/api/v1` 提供客户端 API。远端导入了约 100 条帖子、随机化占位用户和帖子图片；图片通过 `/imported-media/` 公开读取。该 HTTP 地址只用于 QA，API、图片媒体和 Web 正式发布必须统一使用 HTTPS。API 模式必须显式传入地址，启动示例：

```bash
flutter run --dart-define=API_BASE_URL=http://101.42.27.44
flutter build apk --debug --dart-define=API_BASE_URL=http://101.42.27.44
```

生产构建必须同时声明 `APP_ENV=production`；客户端会拒绝 HTTP API 地址：

```bash
flutter build web --release --base-href /forum/ \
  --dart-define=APP_ENV=production \
  --dart-define=API_BASE_URL=https://forum.example.com
flutter build apk --release \
  --dart-define=APP_ENV=production \
  --dart-define=API_BASE_URL=https://forum.example.com
```

正式域名还需要由 HTTPS 反向代理统一承载 API、媒体和 Web，并配置证书续期；不要在生产构建中复用 QA 的 `http://101.42.27.44` 地址。

如需重新生成占位数据，使用 `scripts/import_placeholder_content.py`。脚本只写入占位用户名，不会保存源站作者用户名；数据库连接应通过远端进程环境中的 `DATABASE_URL` 提供，不要把连接凭据写入仓库。

## 常用验证命令

Flutter：

```bash
flutter analyze
flutter test
flutter build web --release
flutter build apk --release
```

Go API：

```bash
cd server
go test ./...
```

如果未配置 `DATABASE_URL`，数据库迁移集成测试会自动跳过；其余 API、仓储和控制器测试仍可运行。

## 项目结构

```text
lib/
├── main.dart                         # Flutter 入口
├── app.dart                          # 应用壳、底部导航、全局交互
├── theme/app_theme.dart               # 颜色、圆角、间距、动效 Token
├── controllers/
│   ├── auth_controller.dart           # 登录态
│   ├── comments_controller.dart       # 回复分页与状态
│   ├── feed_controller.dart           # 信息流加载、刷新、分页
│   ├── post_detail_controller.dart    # 帖子详情
│   └── publish_controller.dart        # 发布流程
├── domain/
│   ├── models.dart                    # 用户、板块、帖子、媒体、回复模型
│   └── repositories.dart              # 仓储接口
├── data/
│   ├── mock_forum_data.dart           # 本地 mock 数据和 ForumStore
│   ├── repository_provider.dart       # mock / API 仓储切换
│   └── api/                           # REST 客户端和 API 仓储
├── screens/
│   ├── home_screen.dart
│   ├── post_detail_screen.dart
│   ├── profile_screen.dart
│   ├── feature_page.dart
│   ├── exchange_store_screen.dart
│   ├── notifications_screen.dart
│   ├── governance_screens.dart          # 账号处罚、管理员管理、风控、审计日志
│   ├── moderation_notice_detail_screen.dart
│   ├── appeal_form_screen.dart
│   ├── appeal_detail_screen.dart
│   └── my_appeals_screen.dart
└── widgets/
    ├── forum_post_card.dart
    ├── forum_author_row.dart
    ├── post_media_preview.dart
    └── composer_sheet.dart

server/
├── cmd/api/main.go                     # Go 服务入口
├── internal/api/                       # HTTP 路由和业务处理
├── internal/auth/                      # 认证服务
├── internal/platform/                  # 配置、数据库、日志、HTTP 中间件
├── migrations/                         # PostgreSQL 数据库迁移
└── seeds/dev/                          # 开发数据

test/                                   # Flutter 单元测试和 Widget Test
```

## API 能力概览

服务端 API 前缀为 `/api/v1`，当前包含：

- 认证：邮箱验证码请求 / 校验、游客会话、刷新令牌、退出登录、当前用户；旧密码接口仅作存量兼容
- 社区：分类、社区列表、社区详情、关注、加入 / 退出
- 信息流：最新 Feed、帖子详情
- 帖子：创建、更新、删除、点赞、收藏
- 回复：列表、发表、回复、编辑、删除、点赞
- 媒体：上传凭证、媒体完成回调
- 搜索：帖子、用户、社区和 300ms 防抖搜索
- 通知：列表、未读数、标记已读、全部已读
- 个人中心：资料聚合、发帖 / 回帖 / 点赞 / 收藏 / 历史列表
- 举报：帖子和评论举报落库
- 治理：`/me/account-status`、`/admins`、`/admins/{id}/roles`、`/admin/risk`、`/admin/logs`、`/admin/ip-restrictions`；自动规则识别微信群 / QQ 群 / 手机号 / 淘宝链接 / 外链并进入待审核
- 增长功能：投票、排行榜、积分商品和事务兑换；历史市场表仅保留用于数据兼容，不再创建或展示市场帖子

客户端 API 仓储位于 `lib/data/api/`，默认 mock / API 切换逻辑位于 `lib/data/repository_provider.dart`。

## 真实用户旅程与能力边界

- 首次打开默认可浏览公开内容；游客会话仍使用统一会话体系，但评论、举报、点赞等低风险参与能力与发布、关注、收藏、投票、上传、资料管理严格分开。
- 客户端入口和服务端接口共同读取 `can_comment`、`can_report`、`can_like`、`can_follow`、`can_bookmark`、`can_publish`、`can_upload_media`、`can_vote`、`can_create_poll`、`can_manage_profile` 等能力，服务端始终做最终校验。
- 访问令牌过期或刷新失败不会阻断公开浏览；互动操作会提示重新登录。Feed、评论、搜索、通知、个人列表和审核案件的分页失败均保留可见重试入口。
- 管理员角色支持平台/社区范围、增删和审计；IP 限制默认规范化为单 IP `/32` 或 `/128`，仅 super admin 可获得 IP 封禁能力；禁言支持 1/7/30 天、自定义和永久。

权限回归固定矩阵见 [`docs/capability-regression-matrix.md`](docs/capability-regression-matrix.md)。涉及权限、认证或治理接口的改动必须覆盖五种身份和九类动作，服务端测试入口为 `TestCapabilityMatrix`。

## 设计约束

- 保留既有产品名称：`大型拆箱`、`酱紫社区`、`杂鱼日常`、`兑换商店`、`最近发布` 等
- 首页只保留 `首页` / `+` / `我的` 三段底部导航
- 杯友酱浅蓝品牌色与信息密度优先，避免过度卡片化、夸张阴影和大面积渐变
- UI 重构优先复用现有数据模型、仓储和发布流程，不改变业务含义

## 许可

当前仓库未声明开源许可证。如需对外发布，请补充 LICENSE 以及第三方依赖和素材授权说明。
