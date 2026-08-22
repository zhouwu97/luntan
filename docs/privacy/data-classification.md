# 数据分级与 PII 处理

## High Sensitivity

- 密码凭据哈希：只能写入 `user_auth_methods.credential_hash`，禁止日志、接口响应和分析事件携带。
- 身份核验材料：当前版本不落库；若未来增加，必须单独加密存储并限制平台权限。

## Sensitive

- 手机、邮箱、IP、设备标识和登录日志。
- IP 仅用于会话审计、风控和限流；日志展示时应脱敏，保留周期由环境配置决定。
- Refresh token 只以哈希存库，访问日志禁止记录 Authorization 和原始 token。

## Public / Business

- 昵称、头像、社区名称、帖子和评论正文按产品可见性展示。
- 举报描述、审核 reason、audit before/after 属于内部业务数据，不能当作公共内容返回。

## 生命周期与访问

- 删除采用 publication/moderation/deleted_at 分离状态，原始审计记录不因软删除而丢失。
- 生产数据库访问使用最小权限账号；开发 seed 不得包含真实个人信息。
- 新增字段必须在迁移说明中声明敏感级别、用途、访问角色和保留周期。
