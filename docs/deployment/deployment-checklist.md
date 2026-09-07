# 部署检查清单

## 关键风险点

### ⚠️ 部署顺序问题

**当前状态**：
- 代码已推送到 `main` (commit `c47ddf2`)
- Flutter 客户端已移除注册页验证码输入框
- 后端环境变量默认 `AUTH_REGISTER_REQUIRE_EMAIL_CODE=true`

**风险**：
如果服务器忘记设置环境变量为 `false`，新版客户端将**全部注册失败**。

## 正确部署流程

### 第 1 步：设置环境变量（必须先做）

```bash
# SSH 登录服务器
ssh root@43.161.249.91
# 密码: <your-server-password>

# 进入部署目录
cd /root/luntan

# 备份现有配置
cp .env .env.backup.$(date +%Y%m%d_%H%M%S)

# 方式 1: 如果已有该配置项，修改它
sed -i 's/^AUTH_REGISTER_REQUIRE_EMAIL_CODE=.*/AUTH_REGISTER_REQUIRE_EMAIL_CODE=false/' .env

# 方式 2: 如果没有该配置项，添加它
echo "" >> .env
echo "# 临时免验证码注册模式" >> .env
echo "AUTH_REGISTER_REQUIRE_EMAIL_CODE=false" >> .env

# 验证配置
grep AUTH_REGISTER_REQUIRE_EMAIL_CODE .env
# 应该显示: AUTH_REGISTER_REQUIRE_EMAIL_CODE=false
```

### 第 2 步：拉取代码

```bash
# 拉取最新代码
git fetch origin
git pull origin main

# 验证 commit
git rev-parse --short HEAD
# 应该显示: c47ddf2

# 查看提交信息
git log --oneline -1
# 应该显示: c47ddf2 feat(auth): 支持临时免验证码注册模式
```

### 第 3 步：重新构建并部署

#### 如果使用 Docker Compose

```bash
# 重新构建 API 镜像（无缓存）
docker compose build --no-cache api

# 重启服务
docker compose up -d api

# 等待启动
sleep 5

# 检查服务状态
docker compose ps api
docker compose logs --tail 50 api

# 确认环境变量已加载
docker compose exec api printenv | grep AUTH_REGISTER_REQUIRE_EMAIL_CODE
# 应该显示: AUTH_REGISTER_REQUIRE_EMAIL_CODE=false
```

#### 如果使用 systemd

```bash
# 重新编译
go build -o ./bin/api ./cmd/api

# 重启服务
sudo systemctl restart luntan

# 检查状态
sleep 3
sudo systemctl status luntan --no-pager -l

# 查看日志
sudo journalctl -u luntan -n 50 --no-pager
```

### 第 4 步：基础健康检查

```bash
# 检查服务是否响应
curl -i http://localhost:8080/health

# 或者从外部
curl -i https://shengbeijiang.com/health
```

## 第 5 步：完整功能验证（最重要）

**不要只测 `/health`**，必须验证完整注册链路！

在**本地电脑**运行测试脚本：

```bash
# Windows Git Bash
cd /e/AI/bb
bash .qa/test-codeless-registration.sh

# 或者手动测试
```

### 手动测试步骤

#### 测试 1: 免验证码注册

```bash
curl -i -X POST 'https://shengbeijiang.com/api/v1/auth/register' \
  -H 'Content-Type: application/json' \
  --data '{
    "email":"test-'$(date +%s)'@example.com",
    "password":"Test12345678",
    "nickname":"注册测试"
  }'
```

**期望结果**：
```
HTTP/1.1 201 Created

{
  "access_token": "...",
  "refresh_token": "...",
  "user": {
    "email": "test-...@example.com",
    "email_verified": false,  ← 必须是 false
    "has_password": true,
    "account_type": "email"
  }
}
```

如果返回 `400` 或 `"验证码无效"`，说明服务器未设置 `AUTH_REGISTER_REQUIRE_EMAIL_CODE=false`！

#### 测试 2: 密码登录

使用刚注册的账号：

```bash
curl -i -X POST 'https://shengbeijiang.com/api/v1/auth/login' \
  -H 'Content-Type: application/json' \
  --data '{
    "email":"test-刚才的时间戳@example.com",
    "password":"Test12345678"
  }'
```

**期望结果**：
```
HTTP/1.1 200 OK

{
  "access_token": "...",
  "user": {
    "email_verified": false  ← 仍然必须是 false
  }
}
```

如果这里 `email_verified: true`，说明密码登录的 bug 没修复！

#### 测试 3: 数据库验证

```bash
# 登录服务器
ssh root@43.161.249.91

# 连接数据库
psql -U luntan -d luntan

# 查询刚注册的用户
SELECT
    email,
    account_type,
    email_verified,
    email_verified_at,
    status
FROM users
WHERE email LIKE 'test-%@example.com'
ORDER BY created_at DESC
LIMIT 1;
```

**期望结果**：
```
email              | test-...@example.com
account_type       | email
email_verified     | f        ← false
email_verified_at  | null     ← NULL
status             | active
```

## 验收标准

只有以下 4 项**全部通过**，才算部署成功：

- [ ] 新邮箱无验证码注册返回 `HTTP 201`
- [ ] 注册响应中 `email_verified: false`
- [ ] 相同账号密码登录返回 `HTTP 200`
- [ ] 登录响应中 `email_verified: false`（验证 bug 已修复）

## 常见问题排查

### 问题 1: 注册返回 400 "验证码无效"

**原因**：服务器未设置 `AUTH_REGISTER_REQUIRE_EMAIL_CODE=false`

**解决**：
```bash
# 1. 检查环境变量
docker compose exec api printenv | grep AUTH_REGISTER_REQUIRE_EMAIL_CODE

# 2. 如果没有或为 true，修改 .env
echo "AUTH_REGISTER_REQUIRE_EMAIL_CODE=false" >> .env

# 3. 重启服务
docker compose restart api

# 4. 再次验证
docker compose exec api printenv | grep AUTH_REGISTER_REQUIRE_EMAIL_CODE
```

### 问题 2: 登录后 email_verified 变成 true

**原因**：代码未正确合并或服务未重启

**解决**：
```bash
# 1. 验证代码版本
git log --oneline -1
# 必须是: c47ddf2 feat(auth): 支持临时免验证码注册模式

# 2. 检查关键代码
grep -A5 "user.Experience = exp" internal/auth/service.go
# 应该看不到 user.EmailVerified = true 这一行

# 3. 如果代码正确但问题仍存在，强制重新构建
docker compose down api
docker compose build --no-cache api
docker compose up -d api
```

### 问题 3: 服务启动失败

```bash
# 查看详细日志
docker compose logs api

# 或
sudo journalctl -u luntan -n 100 --no-pager

# 常见原因:
# - .env 文件语法错误
# - 数据库连接失败
# - 端口被占用
```

## 回滚方案

如果部署失败需要紧急回滚：

```bash
# 1. 回滚代码
git reset --hard b8babf7  # 上一个 commit

# 2. 重新构建
docker compose build --no-cache api
docker compose up -d api

# 3. 或者只改环境变量（如果旧版客户端还在使用）
# 注意：新版客户端已无验证码输入框，改回 true 会导致新客户端无法注册
```

**重要提示**：当前新版客户端已移除验证码输入框，所以回滚环境变量为 `true` 会导致新客户端注册失败。真正的回滚需要同时回滚客户端版本。

## 关于后续完善

当前实现的开关是**服务端单向控制**：
- 后端可以通过环境变量切换验证码/免验证码
- 但前端已写死为免验证码注册 UI

建议未来增加配置接口：

```
GET /api/v1/auth/config
Response: {
  "registration_require_email_code": false
}
```

前端根据此字段动态决定是否显示验证码输入框，这样才能做到**只改服务器配置不发版就能切换注册策略**。
