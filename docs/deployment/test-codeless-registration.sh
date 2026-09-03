#!/bin/bash
# 临时免验证码注册验证测试脚本
# 在本地执行，测试服务器 API

set -e

# 配置
API_BASE="https://shengbeijiang.com"
TEST_EMAIL="test-$(date +%s)@example.com"
TEST_PASSWORD="Test12345678"
TEST_NICKNAME="注册测试$(date +%H%M%S)"

echo "==================================================="
echo "临时免验证码注册功能验证"
echo "==================================================="
echo "API: $API_BASE"
echo "测试邮箱: $TEST_EMAIL"
echo ""

# 测试 1: 无验证码注册
echo ">>> 测试 1: 免验证码注册"
echo "POST $API_BASE/api/v1/auth/register"
echo ""

REGISTER_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API_BASE/api/v1/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{
    \"email\":\"$TEST_EMAIL\",
    \"password\":\"$TEST_PASSWORD\",
    \"nickname\":\"$TEST_NICKNAME\"
  }")

HTTP_CODE=$(echo "$REGISTER_RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$REGISTER_RESPONSE" | head -n-1)

echo "HTTP 状态码: $HTTP_CODE"
echo "响应内容:"
echo "$RESPONSE_BODY" | jq '.' 2>/dev/null || echo "$RESPONSE_BODY"
echo ""

if [ "$HTTP_CODE" != "201" ]; then
    echo "❌ 测试 1 失败: 期望 HTTP 201，实际 $HTTP_CODE"
    echo ""
    echo "可能原因:"
    echo "1. 服务器未设置 AUTH_REGISTER_REQUIRE_EMAIL_CODE=false"
    echo "2. 该邮箱已经注册过"
    echo "3. API 服务未正常启动"
    exit 1
fi

# 提取 token 和 email_verified
ACCESS_TOKEN=$(echo "$RESPONSE_BODY" | jq -r '.access_token' 2>/dev/null)
EMAIL_VERIFIED=$(echo "$RESPONSE_BODY" | jq -r '.user.email_verified' 2>/dev/null)

echo "✅ 测试 1 通过: 注册成功"
echo ""

# 测试 2: 验证 email_verified 为 false
echo ">>> 测试 2: 验证 email_verified=false"
echo "注册响应中的 email_verified: $EMAIL_VERIFIED"
echo ""

if [ "$EMAIL_VERIFIED" != "false" ]; then
    echo "❌ 测试 2 失败: email_verified 应为 false，实际为 $EMAIL_VERIFIED"
    echo ""
    echo "这说明后端没有正确创建未验证账号"
    exit 1
fi

echo "✅ 测试 2 通过: email_verified 正确为 false"
echo ""

# 测试 3: 密码登录
echo ">>> 测试 3: 使用相同账号密码登录"
echo "POST $API_BASE/api/v1/auth/login"
echo ""

LOGIN_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API_BASE/api/v1/auth/login" \
  -H 'Content-Type: application/json' \
  --data "{
    \"email\":\"$TEST_EMAIL\",
    \"password\":\"$TEST_PASSWORD\"
  }")

LOGIN_HTTP_CODE=$(echo "$LOGIN_RESPONSE" | tail -n1)
LOGIN_BODY=$(echo "$LOGIN_RESPONSE" | head -n-1)

echo "HTTP 状态码: $LOGIN_HTTP_CODE"
echo "响应内容:"
echo "$LOGIN_BODY" | jq '.' 2>/dev/null || echo "$LOGIN_BODY"
echo ""

if [ "$LOGIN_HTTP_CODE" != "200" ]; then
    echo "❌ 测试 3 失败: 期望 HTTP 200，实际 $LOGIN_HTTP_CODE"
    echo ""
    echo "密码登录失败"
    exit 1
fi

echo "✅ 测试 3 通过: 密码登录成功"
echo ""

# 测试 4: 验证登录后 email_verified 仍为 false
echo ">>> 测试 4: 验证登录后 email_verified 仍为 false"
LOGIN_EMAIL_VERIFIED=$(echo "$LOGIN_BODY" | jq -r '.user.email_verified' 2>/dev/null)
echo "登录响应中的 email_verified: $LOGIN_EMAIL_VERIFIED"
echo ""

if [ "$LOGIN_EMAIL_VERIFIED" != "false" ]; then
    echo "❌ 测试 4 失败: 登录后 email_verified 应仍为 false，实际为 $LOGIN_EMAIL_VERIFIED"
    echo ""
    echo "这说明密码登录仍在强制设置 email_verified=true（BUG 未修复）"
    exit 1
fi

echo "✅ 测试 4 通过: 登录后 email_verified 保持 false"
echo ""

# 测试 5: 使用 token 获取用户信息
echo ">>> 测试 5: 使用 token 获取用户信息"
echo "GET $API_BASE/api/v1/auth/me"
echo ""

ME_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "$API_BASE/api/v1/auth/me" \
  -H "Authorization: Bearer $ACCESS_TOKEN")

ME_HTTP_CODE=$(echo "$ME_RESPONSE" | tail -n1)
ME_BODY=$(echo "$ME_RESPONSE" | head -n-1)

echo "HTTP 状态码: $ME_HTTP_CODE"
echo "响应内容:"
echo "$ME_BODY" | jq '.' 2>/dev/null || echo "$ME_BODY"
echo ""

if [ "$ME_HTTP_CODE" != "200" ]; then
    echo "❌ 测试 5 失败: token 验证失败"
    exit 1
fi

ME_EMAIL_VERIFIED=$(echo "$ME_BODY" | jq -r '.email_verified' 2>/dev/null)
ME_ACCOUNT_TYPE=$(echo "$ME_BODY" | jq -r '.account_type' 2>/dev/null)
ME_HAS_PASSWORD=$(echo "$ME_BODY" | jq -r '.has_password' 2>/dev/null)

echo "账号类型: $ME_ACCOUNT_TYPE"
echo "有密码: $ME_HAS_PASSWORD"
echo "邮箱已验证: $ME_EMAIL_VERIFIED"
echo ""

if [ "$ME_EMAIL_VERIFIED" != "false" ]; then
    echo "❌ 测试 5 失败: /me 接口返回的 email_verified 应为 false"
    exit 1
fi

if [ "$ME_ACCOUNT_TYPE" != "email" ]; then
    echo "❌ 测试 5 失败: account_type 应为 email，实际为 $ME_ACCOUNT_TYPE"
    exit 1
fi

if [ "$ME_HAS_PASSWORD" != "true" ]; then
    echo "❌ 测试 5 失败: has_password 应为 true，实际为 $ME_HAS_PASSWORD"
    exit 1
fi

echo "✅ 测试 5 通过: 用户信息正确"
echo ""

echo "==================================================="
echo "🎉 所有测试通过！"
echo "==================================================="
echo ""
echo "验证结果总结:"
echo "  ✅ 无验证码注册成功 (HTTP 201)"
echo "  ✅ 注册账号 email_verified=false"
echo "  ✅ 密码登录成功 (HTTP 200)"
echo "  ✅ 登录后 email_verified 保持 false"
echo "  ✅ Token 有效且用户信息正确"
echo ""
echo "测试账号:"
echo "  邮箱: $TEST_EMAIL"
echo "  密码: $TEST_PASSWORD"
echo ""
echo "⚠️  注意: 这是一个未验证邮箱的测试账号"
echo ""
