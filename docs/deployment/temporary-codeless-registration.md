# 临时免验证码注册方案

## 背景

QQ SMTP 服务不稳定，邮箱验证码经常发送失败，导致新用户无法注册。为了保证用户体验，实施临时免验证码注册方案，通过环境变量开关控制，后续 SMTP 稳定后可一键恢复。

## 实施方案

### 核心设计原则

1. **不破坏现有架构**：保留完整的验证码注册流程代码
2. **环境变量开关**：通过 `AUTH_REGISTER_REQUIRE_EMAIL_CODE` 控制
3. **正确的数据语义**：免验证码注册的账号标记为 `email_verified=false`
4. **可随时回退**：改环境变量即可恢复验证码注册

### 后端改动 (Go)

#### 1. 新增环境变量开关

**文件**: `internal/api/api.go`

```go
// emailCodeRequiredForRegistration 控制邮箱注册是否必须验证码。
// 显式配置优先；未配置时默认要求验证码（true）。设为 false 启用临时
// 免验证码注册模式，账号创建为 email_verified=false。
func emailCodeRequiredForRegistration() bool {
	switch strings.TrimSpace(strings.ToLower(os.Getenv("AUTH_REGISTER_REQUIRE_EMAIL_CODE"))) {
	case "false":
		return false
	case "true":
		return true
	}
	return true
}
```

#### 2. 修改注册 API 处理器

**文件**: `internal/api/api.go` - `/api/v1/auth/register`

- 根据开关决定是否校验验证码
- 验证码模式：调用 `RegisterWithEmail`（创建 verified 账号）
- 免验证码模式：调用 `RegisterWithUnverifiedEmail`（创建 unverified 账号）
- 客户端 `code` 字段可选，兼容新旧客户端

#### 3. Service 层拆分

**文件**: `internal/auth/service.go`

```go
// RegisterWithEmail 创建已验证邮箱账号（经过验证码验证）
func (s *Service) RegisterWithEmail(...) (AuthResponse, error) {
	return s.registerWithEmail(ctx, input, metadata, true)
}

// RegisterWithUnverifiedEmail 创建未验证邮箱账号（免验证码）
func (s *Service) RegisterWithUnverifiedEmail(...) (AuthResponse, error) {
	return s.registerWithEmail(ctx, input, metadata, false)
}

// registerWithEmail 内部共享实现
func (s *Service) registerWithEmail(..., emailVerified bool) (AuthResponse, error) {
	// 根据 emailVerified 参数决定：
	// - email_verified = true/false
	// - email_verified_at = now/NULL
}
```

#### 4. 修复密码登录 Bug

**文件**: `internal/auth/service.go` - `LoginWithPassword`

删除了强制设置 `user.EmailVerified = true` 的代码，保持数据库查询的原始值。

### 前端改动 (Flutter)

#### 1. 修改 Repository

**文件**: `lib/data/api/auth_repository.dart`

```dart
Future<AuthSession> register({
  required String email,
  required String password,
  String? nickname,
  String? code,  // 改为可选
}) async {
  final payload = await _client.postJson(
    '/api/v1/auth/register',
    body: {
      'email': email.trim(),
      'password': password,
      if (code != null && code.trim().isNotEmpty)
        'code': code.trim(),
      if (nickname != null && nickname.trim().isNotEmpty)
        'nickname': nickname.trim(),
    },
  );
  return _saveSession(payload);
}
```

#### 2. 修改 Controller

**文件**: `lib/controllers/auth_controller.dart`

```dart
Future<bool> register({
  required String email,
  required String password,
  String? nickname,
  String? code,  // 改为可选
}) async {
  // ...
}
```

#### 3. UI 层改动

**文件**: `lib/screens/auth_screen.dart`

**登录页默认方法**：
```dart
LoginMethod _loginMethod = LoginMethod.password;  // 改为密码登录
```

**注册页去掉验证码**：
- 移除 `_buildCodeField(busy)` 调用
- 移除验证码长度校验
- 直接调用 `controller.register(email, password, nickname)`

### 数据库语义

#### 验证码注册（开关为 true）
```sql
account_type = 'email'
email = 'user@qq.com'
email_verified = true
email_verified_at = '2026-09-03 12:00:00'
```

#### 免验证码注册（开关为 false）
```sql
account_type = 'email'
email = 'user@qq.com'
email_verified = false
email_verified_at = NULL
```

### 环境变量配置

**.env.example**:
```bash
# 控制邮箱注册是否需要验证码；true（默认）需要验证码，false 启用临时免验证模式
AUTH_REGISTER_REQUIRE_EMAIL_CODE=true
```

**启用免验证码注册**：
```bash
AUTH_REGISTER_REQUIRE_EMAIL_CODE=false
```

## 权限模型兼容性

现有权限模型主要判断：
```go
registered := user.AccountType != "guest"
```

因此 `email_verified=false` 的邮箱账号依然可以：
- 发帖、评论、投票
- 上传附件
- 关注、收藏
- 修改资料

这正是我们想要的：**先让用户能正常使用论坛，邮箱验证暂时不作为门槛**。

## 产品代价与后续计划

### 当前代价

1. 用户可以使用**不属于自己的邮箱**注册
2. 忘记密码/邮箱找回对这些账号暂时不可用

### 后续优化路径

1. SMTP 稳定后，将 `AUTH_REGISTER_REQUIRE_EMAIL_CODE` 改回 `true`
2. 在"账号安全"页增加**验证邮箱**功能
3. 已注册的 `email_verified=false` 账号可补充验证
4. 验证成功后更新：
   ```sql
   UPDATE users SET 
     email_verified = true,
     email_verified_at = now()
   WHERE id = $1
   ```

## 测试验证

### 后端
```bash
go build -o /dev/null ./cmd/api
# ✓ 编译通过
```

### 前端
```bash
flutter analyze
# ✓ No issues found!
```

### API 兼容性

**旧客户端**（带验证码）：
```json
POST /api/v1/auth/register
{
  "email": "test@qq.com",
  "code": "123456",
  "password": "password123",
  "nickname": "测试"
}
```

**新客户端**（免验证码）：
```json
POST /api/v1/auth/register
{
  "email": "test@qq.com",
  "password": "password123",
  "nickname": "测试"
}
```

两种请求格式服务端都支持，由环境变量决定验证码是否必须。

## 部署步骤

1. 合并代码到 main
2. 构建新版本镜像
3. 更新服务器环境变量：
   ```bash
   AUTH_REGISTER_REQUIRE_EMAIL_CODE=false
   ```
4. 重启服务
5. 发布新版客户端

## 回滚方案

如需恢复验证码注册：

1. 服务器环境变量改为：
   ```bash
   AUTH_REGISTER_REQUIRE_EMAIL_CODE=true
   ```
2. 重启服务
3. 客户端无需更新（仍支持验证码注册）

## 文件清单

### 后端修改
- `internal/api/api.go`
- `internal/auth/service.go`
- `.env.example`

### 前端修改
- `lib/data/api/auth_repository.dart`
- `lib/controllers/auth_controller.dart`
- `lib/screens/auth_screen.dart`

所有修改均已完成并通过编译验证。
