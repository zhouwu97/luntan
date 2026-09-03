#!/bin/bash
# 一键部署脚本 - 在服务器上执行
# 使用方法: bash deploy.sh

set -e

cd /root/luntan

echo "=== 1. 设置环境变量 ==="
cp .env .env.backup.$(date +%Y%m%d_%H%M%S)

if grep -q "^AUTH_REGISTER_REQUIRE_EMAIL_CODE" .env; then
    sed -i 's/^AUTH_REGISTER_REQUIRE_EMAIL_CODE=.*/AUTH_REGISTER_REQUIRE_EMAIL_CODE=false/' .env
else
    echo "" >> .env
    echo "AUTH_REGISTER_REQUIRE_EMAIL_CODE=false" >> .env
fi

echo "当前配置:"
grep AUTH_REGISTER_REQUIRE_EMAIL_CODE .env

echo ""
echo "=== 2. 拉取代码 ==="
git fetch origin && git pull origin main
echo "当前 commit: $(git rev-parse --short HEAD)"

echo ""
echo "=== 3. 重新构建 ==="
docker compose build --no-cache api
docker compose up -d api

echo "等待启动..."
sleep 5

echo ""
echo "=== 4. 验证 ==="
docker compose ps api
docker compose exec api printenv | grep AUTH_REGISTER_REQUIRE_EMAIL_CODE
docker compose logs --tail 20 api

echo ""
echo "✅ 部署完成！请在本地运行: bash docs/deployment/test-codeless-registration.sh"
