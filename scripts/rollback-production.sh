#!/usr/bin/env bash
# 将生产环境 100% 恢复到上一次已记录的 API/Web 镜像；数据库保持向前迁移。
set -Eeuo pipefail

BASE_DIR="${LUNTAN_PRODUCTION_DIR:-/opt/luntan-production}"
COMPOSE_FILE="$BASE_DIR/production.compose.yml"
ENV_FILE="$BASE_DIR/.env"
PREVIOUS_STATE="$BASE_DIR/.previous-release.env"
INTERNAL_API="${PRODUCTION_INTERNAL_API_URL:-http://127.0.0.1:18080}"

fail() {
    printf 'production rollback failed: %s\n' "$1" >&2
    exit 1
}

[[ "$EUID" == 0 ]] || fail 'must run as root'
[[ -r "$COMPOSE_FILE" && -r "$ENV_FILE" && -r "$PREVIOUS_STATE" ]] || fail 'rollback state is incomplete'
# 该状态文件只由 deploy-production.sh 用经过格式校验的镜像引用写入。
# shellcheck disable=SC1090
. "$PREVIOUS_STATE"
[[ -n "${API_IMAGE_TAG:-}" && -n "${WEB_IMAGE_TAG:-}" ]] || fail 'previous image references are missing'

export API_IMAGE_TAG WEB_IMAGE_TAG
docker compose --project-name luntan-production --env-file "$ENV_FILE" -f "$COMPOSE_FILE" pull api worker web
docker compose --project-name luntan-production --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d --force-recreate api worker web

for attempt in $(seq 1 60); do
    if curl --silent --show-error --fail --max-time 3 --output /dev/null "$INTERNAL_API/health" \
        && curl --silent --show-error --fail --max-time 3 --output /dev/null "$INTERNAL_API/ready"; then
        previous_sha="${API_IMAGE_TAG##*:}"
        if [[ "$previous_sha" =~ ^[0-9a-f]{40}$ ]]; then
            version="$(curl --silent --show-error --fail --max-time 5 "$INTERNAL_API/version")"
            printf '%s' "$version" | grep -Fq "\"commit\":\"$previous_sha\"" || fail 'rolled-back API release SHA mismatch'
        fi
        printf 'production rollback passed: api=%s web=%s\n' "$API_IMAGE_TAG" "$WEB_IMAGE_TAG"
        exit 0
    fi
    sleep 1
done
fail 'rolled-back services did not become ready within 60 seconds'
