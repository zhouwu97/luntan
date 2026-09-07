# 环境隔离

| 环境 | APP_ENV | 数据库 | 对象存储 | 允许的行为 |
| --- | --- | --- | --- | --- |
| dev | `dev` | 本地/临时 PostgreSQL | 可为空，上传接口返回不可用 | 可执行开发 seed，禁止真实 PII |
| staging | `staging` | 独立测试 PostgreSQL | 独立 bucket 和签名密钥 | 运行迁移、smoke、E2E |
| production | `production` | 生产 PostgreSQL | 私有生产 bucket、版本和生命周期策略 | 只读发布镜像，迁移需审批 |

所有环境通过环境变量注入连接串和密钥；不把 `.env`、数据库密码、对象存储签名密钥提交到仓库。

生产发布只能通过 `.github/workflows/deploy-production.yml`，使用人工批准的
`production` environment、精确的 `release_sha` 和同 SHA 的 GHCR 镜像；部署命令
从 `PRODUCTION_DEPLOY_COMMAND` secret 注入，禁止使用 `latest`。

生产媒体默认建议使用 `MEDIA_DELIVERY_MODE=gateway`：`media/` 源图所在 bucket/prefix 必须关闭匿名读取，`STORAGE_INTERNAL_BASE_URL` 仅供 API/Nginx 访问，且 `MEDIA_INTERNAL_ACCEL_PREFIX` 对应的 Nginx location 必须使用 `internal`。上线前的 ACL、CDN 缓存和匿名请求检查见 [`media-gateway.md`](media-gateway.md)。

`APP_ENV` 只接受 `dev`、`development`、`test`、`qa`、`staging` 和 `production`；`prod`、`prd` 等近似拼写会直接阻止服务启动。验证码哈希使用独立的 `AUTH_CODE_HASH_SECRET`，生产环境至少 32 字节。`ALLOW_DEV_AUTH_CODE` 默认关闭，只有 development/test 可显式开启，且不会被 production 配置接受。

`/metrics` 默认只允许 localhost；部署到反向代理或独立监控网段时，必须通过 `METRICS_ALLOWED_CIDRS` 明确配置允许的 CIDR，并通过 `TRUSTED_PROXY_CIDRS` 明确配置可信代理网段。

邮件发送通过 SMTP 环境变量注入。QQ 邮箱使用 `smtp.qq.com:465`、隐式 TLS 和邮箱授权码；
`SMTP_PASSWORD` 只放在服务器密钥管理或运行时环境中，不得提交 Git。`production` 缺少 SMTP 配置时 API 拒绝启动，
开发/测试环境只有显式开启 `ALLOW_DEV_AUTH_CODE=true` 才允许本地验证码回显，否则返回明确的 disabled 错误。

邮件投递指标由 `/metrics` 暴露：`luntan_mail_delivery_total{status="sent|failed"}`。
监控系统应按增量而非绝对值告警，例如 5 分钟内失败次数达到 3 次时告警：
`increase(luntan_mail_delivery_total{status="failed"}[5m]) >= 3`。
邮件失败日志事件为 `mail_delivery_failed`，包含 `purpose`、`smtp_host`、`error_stage`、
`smtp_code` 和 `request_id`，不记录收件地址、验证码或 SMTP 凭据。
