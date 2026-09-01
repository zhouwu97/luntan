#!/usr/bin/env bash
# 在 systemd + Nginx 目标机上发布一个不可变 staging release。
# 参数：发布归档路径、必须与源码一致的 40 位 Git SHA。
set -Eeuo pipefail

BASE_DIR="${LUNTAN_STAGING_DIR:-/opt/luntan-qa}"
PUBLIC_BASE_URL="${STAGING_BASE_URL:-https://shengbeijiang.com}"
INTERNAL_BASE_URL="${STAGING_INTERNAL_BASE_URL:-http://127.0.0.1:18080}"
DB_OS_USER="${LUNTAN_DB_OS_USER:-postgres}"
ARCHIVE_PATH="${1:-}"
RELEASE_SHA="${2:-}"
CURRENT_LINK="$BASE_DIR/current"
WEB_LINK="$BASE_DIR/web"
LOCK_DIR="$BASE_DIR/.staging-deploy.lock"
WORK_DIR=""
RELEASE_DIR=""
PREVIOUS_CURRENT=""
PREVIOUS_WEB=""
SWITCH_STARTED=0
LOCK_ACQUIRED=0

fail() {
    printf 'staging deploy failed: %s\n' "$1" >&2
    handle_failure 1
}

run_db_tool() {
    local tool="$1"
    shift
    if [[ "$(id -un)" == "$DB_OS_USER" ]]; then
        "$tool" "$@"
        return
    fi
    command -v runuser >/dev/null 2>&1 || fail "runuser is required to execute database commands as $DB_OS_USER"
    runuser -u "$DB_OS_USER" -- "$tool" "$@"
}

cleanup() {
    if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
        rm -rf -- "$WORK_DIR"
    fi
    if [[ "$LOCK_ACQUIRED" == 1 && -d "$LOCK_DIR" ]]; then
        rmdir -- "$LOCK_DIR" || true
    fi
}

rollback_services() {
    if [[ "$SWITCH_STARTED" != 1 || -z "$PREVIOUS_CURRENT" ]]; then
        return 0
    fi
    set +e
    systemctl stop luntan-api.service luntan-worker.service >/dev/null 2>&1
    ln -sfnT -- "$PREVIOUS_CURRENT" "$CURRENT_LINK"
    if [[ -n "$PREVIOUS_WEB" ]]; then
        ln -sfnT -- "$PREVIOUS_WEB" "$WEB_LINK"
    fi
    systemctl start luntan-api.service luntan-worker.service >/dev/null 2>&1
    set -e
}

handle_failure() {
    local status="${1:-1}"
    trap - ERR
    rollback_services
    # 迁移是增量兼容设计，回滚应用版本不会自动回滚数据库，避免破坏已提交数据。
    if [[ "$SWITCH_STARTED" == 1 ]]; then
        printf 'staging deploy rolled back application symlinks; database migrations remain applied\n' >&2
    fi
    cleanup
    exit "$status"
}

trap 'handle_failure "$?"' ERR

[[ "$EUID" == 0 ]] || fail 'must run as root so systemd and release symlinks can be switched'
[[ -n "$ARCHIVE_PATH" && -f "$ARCHIVE_PATH" ]] || fail 'release archive does not exist'
printf '%s\n' "$RELEASE_SHA" | grep -Eq '^[0-9a-f]{40}$' || \
    fail 'release SHA must be a 40-character lowercase hexadecimal string'
case "$PUBLIC_BASE_URL" in
    http://*|https://*) ;;
    *) fail 'STAGING_BASE_URL must be an HTTP(S) URL' ;;
esac
case "$INTERNAL_BASE_URL" in
    http://*|https://*) ;;
    *) fail 'STAGING_INTERNAL_BASE_URL must be an HTTP(S) URL' ;;
esac

command -v tar >/dev/null 2>&1 || fail 'tar is required'
command -v systemctl >/dev/null 2>&1 || fail 'systemctl is required'
command -v curl >/dev/null 2>&1 || fail 'curl is required'
command -v pg_dump >/dev/null 2>&1 || fail 'pg_dump is required for the pre-migration backup'
command -v psql >/dev/null 2>&1 || fail 'psql is required for migration verification'

install -d -m 0755 "$BASE_DIR/staging" "$BASE_DIR/releases" "$BASE_DIR/backups"
if ! mkdir -- "$LOCK_DIR"; then
    fail 'another staging deployment is already running'
fi
LOCK_ACQUIRED=1

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
WORK_DIR="$(mktemp -d "$BASE_DIR/staging/.deploy-${RELEASE_SHA}.XXXXXX")"
RELEASE_DIR="$BASE_DIR/releases/${RELEASE_SHA}-${timestamp}"
BACKUP_DIR="$BASE_DIR/backups/staging-${RELEASE_SHA}-${timestamp}"
install -d -m 0700 "$BACKUP_DIR"

mapfile -t archive_entries < <(tar -tzf "$ARCHIVE_PATH")
(( ${#archive_entries[@]} > 0 )) || fail 'release archive is empty'
for entry in "${archive_entries[@]}"; do
    case "$entry" in
        release|release/|release/*) ;;
        *) fail "unexpected archive path: $entry" ;;
    esac
    case "$entry" in
        */../*|*/..|release/../*) fail "archive path traversal is not allowed: $entry" ;;
    esac
done
tar --extract --gzip --file "$ARCHIVE_PATH" --directory "$WORK_DIR" \
    --no-same-owner --no-same-permissions

PAYLOAD_DIR="$WORK_DIR/release"
[[ -d "$PAYLOAD_DIR" ]] || fail 'release directory is missing from archive'
for binary in luntan-api luntan-worker luntan-migrate; do
    [[ -f "$PAYLOAD_DIR/$binary" ]] || fail "required binary is missing: $binary"
    [[ ! -L "$PAYLOAD_DIR/$binary" ]] || fail "binary must not be a symlink: $binary"
    chmod 0755 "$PAYLOAD_DIR/$binary"
done
[[ -d "$PAYLOAD_DIR/migrations" ]] || fail 'migrations directory is missing from archive'
[[ -f "$PAYLOAD_DIR/staging-smoke.sh" ]] || fail 'staging smoke script is missing from archive'
[[ -f "$PAYLOAD_DIR/web/index.html" ]] || fail 'web/index.html is missing from archive'
if find "$PAYLOAD_DIR" -type l -print -quit | grep -q .; then
    fail 'release archive must not contain symbolic links'
fi

mv -- "$PAYLOAD_DIR" "$RELEASE_DIR"
find "$RELEASE_DIR" -type d -exec chmod 0755 {} +
find "$RELEASE_DIR" -type f -exec chmod 0644 {} +
chmod 0755 "$RELEASE_DIR/luntan-api" "$RELEASE_DIR/luntan-worker" \
    "$RELEASE_DIR/luntan-migrate" "$RELEASE_DIR/staging-smoke.sh"
printf 'commit=%s\ncreated_at=%s\n' "$RELEASE_SHA" "$timestamp" > "$RELEASE_DIR/release-metadata.txt"

[[ -r "$BASE_DIR/.env" ]] || fail "environment file is missing: $BASE_DIR/.env"
set -a
# shellcheck disable=SC1091
. "$BASE_DIR/.env"
set +a
[[ -n "${DATABASE_URL:-}" ]] || fail 'DATABASE_URL is missing from the staging environment'

run_db_tool pg_dump --format=custom --no-owner --file="$BACKUP_DIR/predeploy.dump" "$DATABASE_URL" \
    >"$BACKUP_DIR/pg_dump.log" 2>&1 || fail 'pre-migration database backup failed'
sha256sum "$BACKUP_DIR/predeploy.dump" > "$BACKUP_DIR/predeploy.dump.sha256"

if ! (cd "$RELEASE_DIR" && ./luntan-migrate >"$BACKUP_DIR/migrate.log" 2>&1); then
    fail "database migration failed; see $BACKUP_DIR/migrate.log"
fi

expected_migration_version="$(find "$RELEASE_DIR/migrations" -maxdepth 1 -type f -name '*.up.sql' -printf '%f\n' \
    | cut -d_ -f1 | sort -n | tail -1)"
[[ -n "$expected_migration_version" ]] || fail 'cannot determine expected migration version'
actual_migration_version="$(run_db_tool psql "$DATABASE_URL" --no-psqlrc --quiet --tuples-only --no-align \
    --set=ON_ERROR_STOP=1 --command 'SELECT version FROM schema_migrations ORDER BY version::int DESC LIMIT 1;' \
    | tr -d '[:space:]')"
[[ "$actual_migration_version" == "$expected_migration_version" ]] || \
    fail "migration version is $actual_migration_version, expected $expected_migration_version"

has_dirty_column="$(run_db_tool psql "$DATABASE_URL" --no-psqlrc --quiet --tuples-only --no-align \
    --set=ON_ERROR_STOP=1 --command "SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'schema_migrations' AND column_name = 'dirty') THEN '1' ELSE '0' END;" \
    | tr -d '[:space:]')"
if [[ "$has_dirty_column" == 1 ]]; then
    dirty="$(run_db_tool psql "$DATABASE_URL" --no-psqlrc --quiet --tuples-only --no-align \
        --set=ON_ERROR_STOP=1 --command "SELECT CASE WHEN dirty THEN 't' ELSE 'f' END FROM schema_migrations ORDER BY version::int DESC LIMIT 1;" \
        | tr -d '[:space:]')"
    [[ "$dirty" == f ]] || fail 'latest migration is dirty'
fi

PREVIOUS_CURRENT="$(readlink -f "$CURRENT_LINK" 2>/dev/null || true)"
PREVIOUS_WEB="$(readlink -f "$WEB_LINK" 2>/dev/null || true)"
[[ -d "$PREVIOUS_CURRENT" ]] || fail 'current release symlink does not resolve to a directory'

SWITCH_STARTED=1
systemctl stop luntan-api.service luntan-worker.service
ln -sfnT -- "$RELEASE_DIR" "$CURRENT_LINK"
ln -sfnT -- "$RELEASE_DIR/web" "$WEB_LINK"
systemctl start luntan-api.service luntan-worker.service

wait_for_ready() {
    local attempt
    for attempt in $(seq 1 60); do
        if curl --silent --show-error --fail --max-time 3 --output /dev/null "$INTERNAL_BASE_URL/health" \
            && curl --silent --show-error --fail --max-time 3 --output /dev/null "$INTERNAL_BASE_URL/ready"; then
            return 0
        fi
        sleep 1
    done
    return 1
}

wait_for_ready || fail 'new API did not become healthy and ready within 60 seconds'
STAGING_BASE_URL="$PUBLIC_BASE_URL" \
STAGING_INTERNAL_BASE_URL="$INTERNAL_BASE_URL" \
EXPECTED_RELEASE_SHA="$RELEASE_SHA" \
EXPECTED_MIGRATION_VERSION="$expected_migration_version" \
DATABASE_URL="$DATABASE_URL" \
    "$RELEASE_DIR/staging-smoke.sh" >"$BACKUP_DIR/smoke.log" 2>&1 || {
    tail -n 60 "$BACKUP_DIR/smoke.log" >&2 || true
    fail "staging smoke failed; see $BACKUP_DIR/smoke.log"
}

systemctl is-active --quiet luntan-api.service
systemctl is-active --quiet luntan-worker.service
rm -f -- "$ARCHIVE_PATH"
trap - ERR
cleanup
printf 'staging deploy passed: release=%s migration=%s\n' "$RELEASE_SHA" "$expected_migration_version"
