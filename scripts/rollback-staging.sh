#!/usr/bin/env bash
# 将 staging 回指到指定的历史 release；不自动回滚数据库迁移。
# 参数可省略，省略时选择 releases 目录中除 current 外最近的一份。
set -Eeuo pipefail

BASE_DIR="${LUNTAN_STAGING_DIR:-/opt/luntan-qa}"
INTERNAL_BASE_URL="${STAGING_INTERNAL_BASE_URL:-http://127.0.0.1:18080}"
CURRENT_LINK="$BASE_DIR/current"
WEB_LINK="$BASE_DIR/web"
RELEASES_DIR="$BASE_DIR/releases"
TARGET="${1:-}"

fail() {
    printf 'staging rollback failed: %s\n' "$1" >&2
    exit 1
}

[[ "$EUID" == 0 ]] || fail 'must run as root'
command -v systemctl >/dev/null 2>&1 || fail 'systemctl is required'
command -v curl >/dev/null 2>&1 || fail 'curl is required'
[[ -d "$RELEASES_DIR" ]] || fail 'releases directory does not exist'

current="$(readlink -f "$CURRENT_LINK" 2>/dev/null || true)"
if [[ -z "$TARGET" ]]; then
    while IFS= read -r candidate; do
        candidate="$(readlink -f "$candidate")"
        if [[ "$candidate" != "$current" ]]; then
            TARGET="$candidate"
            break
        fi
    done < <(find "$RELEASES_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -nr | cut -d' ' -f2-)
fi

[[ -n "$TARGET" ]] || fail 'no rollback release was found'
TARGET="$(readlink -f "$TARGET" 2>/dev/null || true)"
[[ -d "$TARGET" ]] || fail 'rollback target is not a directory'
RELEASES_ROOT="$(readlink -f "$RELEASES_DIR")"
case "$TARGET" in
    "$RELEASES_ROOT"/*) ;;
    *) fail 'rollback target must stay inside the releases directory' ;;
esac
[[ -f "$TARGET/luntan-api" && -f "$TARGET/luntan-worker" ]] || fail 'rollback target is incomplete'

systemctl stop luntan-api.service luntan-worker.service
ln -sfnT -- "$TARGET" "$CURRENT_LINK"
if [[ -d "$TARGET/web" ]]; then
    ln -sfnT -- "$TARGET/web" "$WEB_LINK"
fi
systemctl start luntan-api.service luntan-worker.service

for attempt in $(seq 1 60); do
    if curl --silent --show-error --fail --max-time 3 --output /dev/null "$INTERNAL_BASE_URL/health" \
        && curl --silent --show-error --fail --max-time 3 --output /dev/null "$INTERNAL_BASE_URL/ready"; then
        printf 'staging rollback passed: current=%s\n' "$TARGET"
        exit 0
    fi
    sleep 1
done

fail 'rolled-back API did not become healthy and ready within 60 seconds'
