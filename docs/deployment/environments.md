# 环境隔离

| 环境 | APP_ENV | 数据库 | 对象存储 | 允许的行为 |
| --- | --- | --- | --- | --- |
| dev | `dev` | 本地/临时 PostgreSQL | 可为空，上传接口返回不可用 | 可执行开发 seed，禁止真实 PII |
| staging | `staging` | 独立测试 PostgreSQL | 独立 bucket 和签名密钥 | 运行迁移、smoke、E2E |
| production | `production` | 生产 PostgreSQL | 生产 bucket、版本和生命周期策略 | 只读发布镜像，迁移需审批 |

所有环境通过环境变量注入连接串和密钥；不把 `.env`、数据库密码、对象存储签名密钥提交到仓库。

邮件发送通过 SMTP 环境变量注入。QQ 邮箱使用 `smtp.qq.com:465`、隐式 TLS 和邮箱授权码；
`SMTP_PASSWORD` 只放在服务器密钥管理或运行时环境中，不得提交 Git。`production` 缺少 SMTP 配置时 API 拒绝启动，
开发/测试环境则返回明确的 disabled 错误。
