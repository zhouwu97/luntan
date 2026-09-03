# 生产部署说明 - 临时免验证码注册模式

本指南用于指导在生产/预发布服务器上手动启用临时免验证码注册与服务更新。

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
