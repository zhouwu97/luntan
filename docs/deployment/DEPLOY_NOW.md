# 生产部署说明 - 临时免验证码注册模式

本指南用于指导在生产/预发布服务器上手动启用临时免验证码注册与服务更新。

> [!CAUTION]
> **安全凭据轮换与 GitHub 缓存说明**
> 1. **立即轮换凭据**：若服务器此前使用的登录凭据曾在历史提交中暴露，请务必第一时间在云厂商控制台（阿里云/腾讯云等）更改服务器登录密码，并更新为强密码或基于 SSH Key 的免密登录；凭据轮换是消除实际安全风险的最根本手段。
> 2. **历史 SHA 缓存清理**：虽然仓库 `main` 与所有 refs 历史均已通过 `git-filter-repo` 重写并推送，但 GitHub 官方机制会保留未被引用的悬空对象（Dangling Commits）及直接按 SHA 请求的缓存视图。如需使旧 commit SHA 彻底返回 404，需通过 [GitHub Support Contact](https://support.github.com/contact?tags=rr-sensitive-data) 提交工单（选择 "Remove sensitive data from a repository"），请求执行服务器端深度 GC 与缓存清除。

## 快速部署步骤

### 1. SSH 登录服务器

```bash
ssh root@<server-ip>
# 请使用您的 SSH Key 或服务器密码登录
```

### 2. 配置环境变量与服务更新

```bash
# 进入项目目录
cd /root/luntan

# === 步骤 1: 设置环境变量 ===
echo "=== 备份并设置环境变量 ==="

# 备份现有配置
cp .env .env.backup.$(date +%Y%m%d_%H%M%S)

# 检查是否已有配置
if grep -q "^AUTH_REGISTER_REQUIRE_EMAIL_CODE" .env; then
    sed -i 's/^AUTH_REGISTER_REQUIRE_EMAIL_CODE=.*/AUTH_REGISTER_REQUIRE_EMAIL_CODE=false/' .env
    echo "已更新现有配置"
else
    echo "" >> .env
    echo "# 临时免验证码注册模式" >> .env
    echo "AUTH_REGISTER_REQUIRE_EMAIL_CODE=false" >> .env
    echo "已添加新配置"
fi

# 验证配置
echo "当前配置："
grep AUTH_REGISTER_REQUIRE_EMAIL_CODE .env

# === 步骤 2: 拉取最新代码 ===
git fetch origin && git pull origin main
echo "当前 commit: $(git rev-parse --short HEAD)"

# === 步骤 3: 重新构建并启动服务 ===
docker compose build --no-cache api
docker compose up -d api

# === 步骤 4: 检查服务健康状态 ===
sleep 5
docker compose ps api
docker compose logs --tail 20 api
```
