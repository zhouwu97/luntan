# 圣杯酱论坛

基于 Flutter 的玩具交流轻社区 App，采用“贴吧的信息结构 + 社区高效入口 + 浅蓝年轻化视觉”，提供帖子浏览、板块切换、搜索、发布、回复、互动和积分兑换等能力。

当前仓库同时包含：

- Flutter 客户端：Android / iOS / Web
- Go HTTP API：认证、板块、信息流、帖子、媒体、回复和互动接口
- 本地 mock 数据层：仅用于离线测试和 UI 验证

## 当前状态

正式客户端默认连接自己的 Go API（默认地址为 `https://shengbeijiang.com`），首页默认请求最新帖子并按发帖时间排序；客户端不会在运行时直接请求源站。通过 `API_BASE_URL` 可以覆盖开发、测试或生产环境地址。API 模式的访问令牌保存在平台安全存储中，杀掉 App 后会自动恢复登录态，`ForumStore` 不参与正式业务写入。生产构建必须显式设置 `APP_ENV=production` 和 HTTPS API 地址；服务端会拒绝缺少数据库、对象存储或 SMTP 配置的生产启动。

已覆盖的主要功能：

- 首页：头像、搜索、通知、三大板块、快捷入口、推荐 / 最新 / 精华
- Feed：帖子卡片、作者等级、标签、摘要、图片 0 / 1 / 2 / 3 / 4+ 张布局
- 帖子：详情、图片画廊、回复 / 楼中楼、点赞、收藏、编辑、删除、举报、浏览历史
- 搜索：帖子、用户、板块
- 发布：普通帖子、投票、玩法分享；本地草稿持久化、退出前保存/放弃确认、上传中图片删除
- 我的：真实用户信息与统计、我的发帖 / 回帖 / 收藏 / 点赞 / 浏览历史
- 通知：通知列表、通知详情、已读和未读数、前台/下拉刷新
- 认证：邮箱验证码登录、游客模式（后台统一创建 guest user），不在客户端展示密码入口；邮箱验证码发送后锁定邮箱，支持明确“修改邮箱”
- 治理：账号处罚详情、申诉、管理员列表 / 详情 / 角色范围管理、风控中心、IP 限制、不可篡改审计日志
- 兑换商店：商品、积分余额、事务兑换单
- 投票：选项、服务端投票和票数
- 排行榜：榜单浏览、评分与「想冲」、商品评价树（含配图）、玩具投稿与超管审核、榜单重排
- 导航：`首页` / `+` / `我的`

首页快捷入口保留产品名称：`排行榜`、`热门帖子`、`穿搭分享`、`活动`、`玩法分享`。`玩法分享`同时作为发布类型和内容入口。

## 环境要求

- Flutter / Dart：以 `pubspec.yaml` 中的 SDK 约束为准
- Go：以 `server/go.mod` 中的版本约束为准
- PostgreSQL：仅在运行真实 API 和数据库迁移时需要

## 快速开始

### 运行 Flutter 客户端（默认真实 API）

```bash
flutter pub get
flutter run
```

开发构建不传 `API_BASE_URL` 时默认使用 `https://shengbeijiang.com`，需要改后端地址时再传入 `--dart-define=API_BASE_URL=...`。客户端只请求自己的 API 和媒体地址，不直接依赖源站页面。

### 离线 Mock / 测试模式

单元测试和离线 UI 预览可以显式构造 `ForumRepositories.mock()`；这条路径不会代表正式客户端运行时的数据来源。服务端导入脚本可以在没有客户端参与的情况下，把源站公开内容、图片和安全清洗后的作者/评论数据写入 PostgreSQL 与媒体目录。

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

### 远端 QA 环境与导入数据

QA 服务器 `43.161.249.91` 运行完整后端与 Web 客户端，统一通过 `shengbeijiang.com` HTTPS 域名访问，用于联调与验收：

- API：`https://shengbeijiang.com/api/v1`，健康检查 `/ready`
- Web：`https://shengbeijiang.com/forum/`
- 媒体：源站图片已全部下载到服务器本地媒体目录，由 nginx 通过 HTTPS `/imported-media/` 提供，URL 保存在 `media_assets` 表
- 数据：帖子、评论、榜单商品与评价均来自导入快照，作者为稳定的脱敏本地账号，客户端运行时不直连源站

QA 数据现状（2026-08-29）：90 个榜单商品、1245 条商品评价；310 篇帖子、2284 条评论，全部位于正式板块（酱紫社区 284 / 大型拆箱 14 / 杂鱼日常 12）。QA 也通过 HTTPS 反向代理统一承载 API、媒体和 Web；生产构建仍必须声明 `APP_ENV=production` 并使用正式生产域名。

连接 QA 启动示例：

```bash
flutter run --dart-define=API_BASE_URL=https://shengbeijiang.com
flutter build apk --debug --dart-define=API_BASE_URL=https://shengbeijiang.com
```

生产构建示例：

```bash
flutter build web --release --base-href /forum/ \
  --dart-define=APP_ENV=production \
  --dart-define=API_BASE_URL=https://forum.example.com
flutter build apk --release \
  --dart-define=APP_ENV=production \
  --dart-define=API_BASE_URL=https://forum.example.com
```

QA 服务端通过 `/opt/luntan-qa/.env` 注入配置，关键项：`DATABASE_URL`、`APP_ENV=qa`、`MEDIA_STORAGE_DIR`（本地媒体目录兜底，dev/QA 可用）、`OBJECT_STORAGE_PUBLIC_BASE_URL`（指向 nginx 映射的 `/imported-media/` 公开路径）、`OBJECT_STORAGE_SIGNING_SECRET`；生产环境必须使用外部对象存储。环境矩阵见 [`docs/deployment/environments.md`](docs/deployment/environments.md)。

#### 重新同步导入快照

导入必须在部署服务器上执行，不能只把前端快照打进 APK/Web：

```bash
# 与服务进程一致的环境；以下为 QA 示例，生产环境改为已配置的对象存储。
export DATABASE_URL="postgres://.../luntan_qa?sslmode=disable"
export MEDIA_STORAGE_DIR=/opt/luntan-qa/imported-media/user-media

# 1) 下载杯友酱公开榜单、商品评价和配图到本地快照。
pwsh scripts/sync_beiyoujiang_rankings.ps1

# 2) 导入榜单商品、评价、配图与各筛选视图名次：写 ranking_* 与 media_assets。
cd server
go run ./cmd/ranking-import \
  -snapshot seeds/beiyoujiang_snapshot.json \
  -assets-root ..
cd ..

# 3) 导入帖子、帖子评论与帖子配图：写 posts/comments/media_assets/post_media。
# --media-dir 必须与 nginx 映射到 /imported-media/ 的目录一致；
# --public-media-base 即写入库中的公开前缀（QA 帖子图为 https://shengbeijiang.com/imported-media）。
python3 scripts/import_placeholder_content.py \
  --output-dir /var/lib/luntan/import/posts \
  --media-dir /opt/luntan-qa/imported-media \
  --public-media-base "https://shengbeijiang.com/imported-media" \
  --page-size 100
```

导入语义：

- 幂等：帖子、评论、媒体均使用确定性 ID 配合 `ON CONFLICT` 更新，重复执行不产生重复数据；评论按导入批次清理重建。
- 自动审核兼容：含淘宝链接等关键词的历史内容会命中迁移 000026 的防灌水触发器进入待审核，导入脚本已内置恢复段，导入完成后自动放行并关闭对应 auto_rule 案例。
- 隔离：导入作者不保留源站昵称、头像或账号 ID；用户之后发布的帖子、评论、想冲、买过与评分写入同一套数据库，不会被下次同步覆盖。

#### QA 部署速查

后端（源码上传后在服务器构建；服务器 Go 工具链需设置 `GOPROXY=https://goproxy.cn,direct`）：

1. 先执行 `luntan-migrate` 预应用迁移（迁移均增量幂等，旧进程可继续运行）
2. 备份旧二进制 → 停止旧进程 → 安装新 `luntan-api` / `luntan-worker` → 刷新 `migrations/` 目录
3. 注入 `/opt/luntan-qa/.env` 后启动，验证 `/ready` 与新增路由；发布与恢复演练流程见 [`docs/deployment/release-runbook.md`](docs/deployment/release-runbook.md)

Web 发布：

```bash
flutter build web --release --base-href=/forum/ \
  --dart-define=API_BASE_URL=https://shengbeijiang.com \
  --dart-define=APP_ENV=qa
```

- QA 通过 HTTPS 域名访问，必须显式传 `APP_ENV=qa`：release 构建缺省时客户端按 production 规则强制校验 API 配置，启动即报「应用配置异常」。
- `web/flutter_bootstrap.js` 为入库的自定义引导模板，canvaskit 从应用本地目录加载而不请求 gstatic（国内拉取 wasm 易超时导致白屏），部署时不要删除。
- 产物解压到新发布目录并切换 `/opt/luntan-qa/web` 符号链接，回滚时把链接指回旧目录即可；nginx 对 `/forum/` 已配置协商缓存，发布后浏览器直接拉到新版。

## 配置速查

| 变量 | 作用 | 端 |
| --- | --- | --- |
| `DATABASE_URL` | PostgreSQL 连接串，服务启动时自动执行迁移 | 服务端 |
| `HTTP_PORT` | API 监听端口，默认 `8080` | 服务端 |
| `APP_ENV` | `dev` / `qa` / `staging` / `production`；`production` 要求 HTTPS、SMTP 与对象存储配置齐备 | 双端 |
| `API_BASE_URL` | 客户端 API 地址（编译期 dart-define），默认 `https://shengbeijiang.com` | 客户端 |
| `WEB_BASE_URL` | 分享链接域名，默认 `https://luntan.app` | 客户端 |
| `MEDIA_STORAGE_DIR` | 本地媒体目录兜底（dev/QA），生产使用外部对象存储 | 服务端 |
| `OBJECT_STORAGE_PUBLIC_BASE_URL` | 媒体公开访问前缀 | 服务端 |
| `OBJECT_STORAGE_UPLOAD_BASE_URL` / `OBJECT_STORAGE_SIGNING_SECRET` | 媒体上传地址与 HMAC 签名 | 服务端 |
| `SMTP_HOST` / `SMTP_PORT` / `SMTP_USERNAME` / `SMTP_PASSWORD` / `SMTP_FROM` | 邮箱验证码发送；生产缺失时 API 拒绝启动 | 服务端 |
| `PUSH_WEBHOOK_URL` / `PUSH_WEBHOOK_SECRET` | 通知投递到站外推送，未配置时仅持久化站内通知 | 服务端 |
| `APP_RELEASE_MANIFEST_PATH` | Android 软件内更新发布清单的绝对路径；清单与 APK 同目录 | 服务端 |
| `APP_RELEASE_PUBLIC_BASE_URL` | 安装包公开 API 根地址；留空时复用当前 API 域名 | 服务端 |

环境隔离矩阵与密钥管理约束见 [`docs/deployment/environments.md`](docs/deployment/environments.md)。

### 发布 Android 软件内更新

“检查更新”和 APK 下载都由 Go API 提供，不依赖网页下载页。先构建 APK，再生成服务端可校验的发布清单：

```powershell
flutter build apk --release --build-name 0.01 --build-number 1 `
  --dart-define=APP_ENV=production `
  --dart-define=API_BASE_URL=https://shengbeijiang.com `
  --dart-define=WEB_BASE_URL=https://shengbeijiang.com

.\scripts\prepare_app_release.ps1 `
  -ApkPath .\build\app\outputs\flutter-apk\app-release.apk `
  -OutputDirectory .\artifacts\app-release `
  -VersionName 0.01 `
  -VersionCode 1 `
  -MinimumSupportedVersionCode 1 `
  -Title '圣杯酱 0.01' `
  -Changelog '优化检查更新与安装体验。'
```

把整个 `artifacts/app-release` 目录原样上传到服务器，并设置：

```text
APP_RELEASE_MANIFEST_PATH=/opt/luntan/releases/release.json
APP_RELEASE_PUBLIC_BASE_URL=https://forum.example.com
```

重启 API 后依次验收 `/api/v1/app/releases/latest`、`/api/v1/app/update` 和
响应中的 `/api/v1/app/releases/{version_code}/download`。服务启动会校验清单、APK 大小与 SHA-256；
配置错误时会拒绝启动，避免客户端拿到无法安装的半成品发布。

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
go vet ./...
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
├── cmd/
│   ├── api/                            # Go API 服务入口
│   ├── worker/                         # 后台任务（outbox 通知投递等）
│   ├── migrate/                        # 独立迁移工具
│   ├── ranking-import/                 # 榜单快照导入
│   ├── media-backfill/                 # 媒体补录
│   ├── bootstrap-admin/                # 初始化管理员
│   └── smtp-test/                      # SMTP 连通性自检
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
- 回复：列表、发表、回复、编辑、删除、点赞、点踩；楼中楼支持独立线程页
- 媒体：上传凭证、媒体完成回调
- 搜索：帖子、用户、社区和 300ms 防抖搜索
- 通知：列表、未读数、标记已读、全部已读
- 个人中心：资料聚合、发帖 / 回帖 / 点赞 / 收藏 / 历史列表
- 举报：帖子和评论举报落库
- 治理：`/me/account-status`、`/admins`、`/admins/{id}/roles`、`/admin/risk`、`/admin/logs`、`/admin/ip-restrictions`；自动规则识别微信群 / QQ 群 / 手机号 / 淘宝链接 / 外链并进入待审核
- 增长功能：投票、排行榜（含玩具投稿、超管审核与榜单重排）、积分商品和事务兑换；历史市场表仅保留用于数据兼容，不再创建或展示市场帖子

客户端 API 仓储位于 `lib/data/api/`，运行时默认 API、测试时 Mock 的切换逻辑位于 `lib/data/repository_provider.dart`。

## 真实用户旅程与能力边界

- 首次打开默认可浏览公开内容；游客会话仍使用统一会话体系，但评论、举报、点赞等低风险参与能力与发布、关注、收藏、投票、上传、资料管理严格分开。
- 客户端入口和服务端接口共同读取 `can_comment`、`can_report`、`can_like`、`can_follow`、`can_bookmark`、`can_publish`、`can_upload_media`、`can_vote`、`can_create_poll`、`can_manage_profile` 等能力，服务端始终做最终校验。
- 访问令牌过期或刷新失败不会阻断公开浏览；互动操作会提示重新登录。Feed、评论、搜索、通知、个人列表和审核案件的分页失败均保留可见重试入口。
- 管理员角色支持平台/社区范围、增删和审计；IP 限制默认规范化为单 IP `/32` 或 `/128`，仅 super admin 可获得 IP 封禁能力；禁言支持 1/7/30 天、自定义和永久。

权限回归固定矩阵见 [`docs/capability-regression-matrix.md`](docs/capability-regression-matrix.md)。涉及权限、认证或治理接口的改动必须覆盖五种身份和九类动作，服务端测试入口为 `TestCapabilityMatrix`。

## 设计约束

- 保留既有产品名称：`大型拆箱`、`酱紫社区`、`杂鱼日常`、`兑换商店`、`最近发布` 等
- 首页只保留 `首页` / `+` / `我的` 三段底部导航
- 圣杯酱浅蓝品牌色与信息密度优先，避免过度卡片化、夸张阴影和大面积渐变
- UI 重构优先复用现有数据模型、仓储和发布流程，不改变业务含义

## 许可

当前仓库未声明开源许可证。如需对外发布，请补充 LICENSE 以及第三方依赖和素材授权说明。
