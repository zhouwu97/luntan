#!/usr/bin/env bash
# 使用同一 release SHA 的不可变镜像执行一次性生产切换。
set -Eeuo pipefail

BASE_DIR="${LUNTAN_PRODUCTION_DIR:-/opt/luntan-production}"
COMPOSE_FILE="$BASE_DIR/production.compose.yml"
ENV_FILE="$BASE_DIR/.env"
LOCK_DIR="$BASE_DIR/.deploy.lock"
BACKUP_DIR="$BASE_DIR/backups"
CURRENT_STATE="$BASE_DIR/.current-release.env"
PREVIOUS_STATE="$BASE_DIR/.previous-release.env"
INTERNAL_API="${PRODUCTION_INTERNAL_API_URL:-http://127.0.0.1:18080}"
RELEASE_SHA="${RELEASE_SHA:-}"
API_IMAGE_TAG="${API_IMAGE_TAG:-}"
WEB_IMAGE_TAG="${WEB_IMAGE_TAG:-}"
SWITCH_STARTED=0

fail() {
    printf 'production deploy failed: %s\n' "$1" >&2
    exit 1
}

cleanup() {
    rmdir -- "$LOCK_DIR" 2>/dev/null || true
}

handle_failure() {
    local status="${1:-1}"
    trap - ERR
    if [[ "$SWITCH_STARTED" == 1 && -r "$PREVIOUS_STATE" ]]; then
        LUNTAN_PRODUCTION_DIR="$BASE_DIR" "$BASE_DIR/rollback-production.sh" || true
    fi
    cleanup
    exit "$status"
}
trap 'handle_failure "$?"' ERR

[[ "$EUID" == 0 ]] || fail 'must run as root'
printf '%s\n' "$RELEASE_SHA" | grep -Eq '^[0-9a-f]{40}$' || fail 'RELEASE_SHA must be a lowercase 40-character SHA'
[[ "$API_IMAGE_TAG" == *":$RELEASE_SHA" ]] || fail 'API image tag must end with the release SHA'
[[ "$WEB_IMAGE_TAG" == *":$RELEASE_SHA" ]] || fail 'Web image tag must end with the release SHA'
[[ -r "$COMPOSE_FILE" && -r "$ENV_FILE" ]] || fail 'production compose or environment file is missing'
for tool in docker curl pg_dump sha256sum; do command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"; done
docker compose version >/dev/null

install -d -m 0700 "$BACKUP_DIR"
mkdir -- "$LOCK_DIR" || fail 'another production deployment is running'

if [[ -r "$CURRENT_STATE" ]]; then
    cp -- "$CURRENT_STATE" "$PREVIOUS_STATE"
else
    previous_api="$(docker inspect --format '{{.Config.Image}}' luntan-api 2>/dev/null || true)"
    previous_web="$(docker inspect --format '{{.Config.Image}}' luntan-web 2>/dev/null || true)"
    if [[ -n "$previous_api" && -n "$previous_web" ]]; then
        printf 'API_IMAGE_TAG=%q\nWEB_IMAGE_TAG=%q\n' "$previous_api" "$previous_web" > "$PREVIOUS_STATE"
    fi
fi

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a
[[ -n "${DATABASE_URL:-}" ]] || fail 'DATABASE_URL is missing from production environment'
[[ "${AUTH_REGISTER_REQUIRE_EMAIL_CODE:-}" == "true" ]] || fail 'production registration must require an email verification code'

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup="$BACKUP_DIR/predeploy-${RELEASE_SHA}-${timestamp}.dump"
pg_dump --format=custom --no-owner --file="$backup" "$DATABASE_URL"
[[ -s "$backup" ]] || fail 'database backup is empty'
sha256sum "$backup" > "$backup.sha256"
sha256sum --check "$backup.sha256"

export API_IMAGE_TAG WEB_IMAGE_TAG
docker compose --project-name luntan-production --env-file "$ENV_FILE" -f "$COMPOSE_FILE" pull migrate api worker web
docker compose --project-name luntan-production --env-file "$ENV_FILE" -f "$COMPOSE_FILE" run --rm migrate

SWITCH_STARTED=1
docker compose --project-name luntan-production --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d --force-recreate api worker web
for attempt in $(seq 1 60); do
    if curl --silent --show-error --fail --max-time 3 --output /dev/null "$INTERNAL_API/health" \
        && curl --silent --show-error --fail --max-time 3 --output /dev/null "$INTERNAL_API/ready"; then
        break
    fi
    [[ "$attempt" != 60 ]] || fail 'new services did not become ready within 60 seconds'
    sleep 1
done

version="$(curl --silent --show-error --fail --max-time 5 "$INTERNAL_API/version")"
printf '%s' "$version" | grep -Fq "\"commit\":\"$RELEASE_SHA\"" || fail 'internal API release SHA mismatch'
[[ "$(docker inspect --format '{{.State.Running}}' luntan-worker)" == "true" ]] || fail 'worker is not running'
printf 'API_IMAGE_TAG=%q\nWEB_IMAGE_TAG=%q\nRELEASE_SHA=%q\n' "$API_IMAGE_TAG" "$WEB_IMAGE_TAG" "$RELEASE_SHA" > "$CURRENT_STATE"

trap - ERR
cleanup
printf 'production deploy passed: release=%s backup=%s\n' "$RELEASE_SHA" "$backup"
