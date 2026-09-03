#!/bin/bash
# 临时免验证码注册部署脚本
# 服务器: 43.161.249.91
# 用户: root
# 密码: <your-server-password>

set -e

echo "=== 步骤 1: 检查并设置环境变量 ==="
cd /root/luntan

# 检查当前配置
echo "当前环境变量:"
grep -E "AUTH_REGISTER_REQUIRE_EMAIL_CODE" .env || echo "未配置"

# 备份环境文件
cp .env .env.backup.$(date +%Y%m%d_%H%M%S)
echo "已备份 .env"

# 设置环境变量
if grep -q "AUTH_REGISTER_REQUIRE_EMAIL_CODE" .env; then
    # 已存在，修改值
    sed -i 's/^AUTH_REGISTER_REQUIRE_EMAIL_CODE=.*/AUTH_REGISTER_REQUIRE_EMAIL_CODE=false/' .env
    echo "已更新 AUTH_REGISTER_REQUIRE_EMAIL_CODE=false"
else
    # 不存在，添加
    echo "" >> .env
    echo "# 临时免验证码注册模式" >> .env
    echo "AUTH_REGISTER_REQUIRE_EMAIL_CODE=false" >> .env
    echo "已添加 AUTH_REGISTER_REQUIRE_EMAIL_CODE=false"
fi

echo ""
echo "=== 步骤 2: 拉取最新代码 ==="
git fetch origin
git pull origin main

# 验证 commit
CURRENT_COMMIT=$(git rev-parse --short HEAD)
echo "当前 commit: $CURRENT_COMMIT"

if [ "$CURRENT_COMMIT" != "c47ddf2" ]; then
    echo "⚠️  警告: 当前 commit 不是 c47ddf2，请检查"
    git log --oneline -1
fi

echo ""
echo "=== 步骤 3: 重新构建并重启服务 ==="

# 检查部署方式
if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
    echo "检测到 Docker Compose 部署"

    # 构建新镜像
    docker compose build --no-cache api

    # 重启服务
    docker compose up -d api

    # 等待服务启动
    echo "等待服务启动..."
    sleep 5

    # 检查服务状态
    docker compose ps api
    docker compose logs --tail 20 api

elif systemctl list-units --type=service | grep -q luntan; then
    echo "检测到 systemd 服务"

    # 重新编译
    cd /root/luntan
    go build -o ./bin/api ./cmd/api

    # 重启服务
    sudo systemctl restart luntan

    # 检查状态
    sleep 3
    sudo systemctl status luntan --no-pager -l
else
    echo "❌ 无法识别部署方式，请手动部署"
    exit 1
fi

echo ""
echo "=== 步骤 4: 健康检查 ==="
sleep 2

# 基础健康检查
echo "检查 API 健康状态..."
curl -s http://localhost:8080/health || echo "健康检查失败"

echo ""
echo "=== 部署完成 ==="
echo ""
echo "⚠️  重要: 现在必须进行完整的注册链路测试！"
echo ""
echo "请在本地执行以下测试脚本验证部署："
echo "  bash .qa/test-codeless-registration.sh"
echo ""
