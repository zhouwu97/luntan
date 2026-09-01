#!/usr/bin/env bash
# Staging 发布后的只读冒烟检查。脚本必须在目标机上运行，以便同时检查
# 公网 Nginx、localhost API、数据库迁移和媒体处理积压。
set -Eeuo pipefail

BASE_URL="${STAGING_BASE_URL:-https://shengbeijiang.com}"
INTERNAL_BASE_URL="${STAGING_INTERNAL_BASE_URL:-http://127.0.0.1:18080}"
DATABASE_URL="${DATABASE_URL:-}"
DB_OS_USER="${LUNTAN_DB_OS_USER:-postgres}"
EXPECTED_RELEASE_SHA="${EXPECTED_RELEASE_SHA:-}"
EXPECTED_MIGRATION_VERSION="${EXPECTED_MIGRATION_VERSION:-}"
CURL_TIMEOUT_SECONDS="${STAGING_SMOKE_CURL_TIMEOUT_SECONDS:-10}"

fail() {
    printf 'staging smoke failed: %s\n' "$1" >&2
    exit 1
}

case "$BASE_URL" in
    http://*|https://*) ;;
    *) fail "STAGING_BASE_URL must be an HTTP(S) URL" ;;
esac
case "$INTERNAL_BASE_URL" in
    http://*|https://*) ;;
    *) fail "STAGING_INTERNAL_BASE_URL must be an HTTP(S) URL" ;;
esac

BASE_URL="${BASE_URL%/}"
INTERNAL_BASE_URL="${INTERNAL_BASE_URL%/}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf -- "$WORK_DIR"' EXIT

request() {
    local url="$1"
    local body_file="$WORK_DIR/body"
    local status

    if ! status="$(curl --silent --show-error --max-time "$CURL_TIMEOUT_SECONDS" \
        --retry 4 --retry-delay 1 --retry-connrefused \
        --output "$body_file" --write-out '%{http_code}' "$url")"; then
        fail "HTTP request failed: $url"
    fi
    printf '%s\n' "$status"
}

expect_status() {
    local name="$1"
    local url="$2"
    local expected="$3"
    local actual

    actual="$(request "$url")"
    if [[ "$actual" != "$expected" ]]; then
        fail "$name returned HTTP $actual, expected $expected"
    fi
    printf 'PASS %-28s HTTP %s\n' "$name" "$actual"
}

expect_status_in() {
    local name="$1"
    local url="$2"
    shift 2
    local actual

    actual="$(request "$url")"
    for expected in "$@"; do
        if [[ "$actual" == "$expected" ]]; then
            printf 'PASS %-28s HTTP %s\n' "$name" "$actual"
            return 0
        fi
    done
    fail "$name returned unexpected HTTP $actual"
}

expect_body_contains() {
    local name="$1"
    local url="$2"
    local needle="$3"
    local actual

    actual="$(request "$url")"
    if ! grep -Fq -- "$needle" "$WORK_DIR/body"; then
        fail "$name response does not contain expected marker: $needle"
    fi
    printf 'PASS %-28s HTTP %s\n' "$name" "$actual"
}

query() {
    run_db_tool psql "$DATABASE_URL" --no-psqlrc --quiet --tuples-only --no-align \
        --set=ON_ERROR_STOP=1 --command "$1" | tr -d '[:space:]'
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

if [[ -n "$EXPECTED_RELEASE_SHA" ]]; then
    printf '%s\n' "$EXPECTED_RELEASE_SHA" | grep -Eq '^[0-9a-f]{40}$' || \
        fail "EXPECTED_RELEASE_SHA must be a 40-character lowercase SHA"
    expect_body_contains "internal release commit" "$INTERNAL_BASE_URL/version" \
        "\"commit\":\"$EXPECTED_RELEASE_SHA\""
fi

expect_body_contains "public health" "$BASE_URL/health" '"status":"ok"'
expect_body_contains "public readiness" "$BASE_URL/ready" '"status":"ready"'
expect_status "public feed" "$BASE_URL/api/v1/feed/latest?limit=1" 200
expect_status "store products" "$BASE_URL/api/v1/store/products" 200
expect_status "release manifest" "$BASE_URL/api/v1/app/releases/latest" 200
expect_status "admin authentication" "$BASE_URL/api/v1/admin/users" 401
expect_status_in "metrics protection" "$BASE_URL/metrics" 403 404
expect_status "legacy media path" "$BASE_URL/media/staging-smoke.invalid" 404
expect_status_in "internal media path" "$BASE_URL/_protected_media/staging-smoke.invalid" 403 404
expect_status "public imported user media" "$BASE_URL/imported-media/user-media/staging-smoke.invalid" 404

[[ -n "$DATABASE_URL" ]] || fail "DATABASE_URL is required for staging smoke"
command -v psql >/dev/null 2>&1 || fail "psql is required for staging smoke"

pending_backfill="$(query "
    SELECT count(*)
    FROM media_assets ma
    WHERE ma.status = 'ready' AND ma.deleted_at IS NULL AND ma.mime_type LIKE 'image/%'
      AND NOT (
        EXISTS (SELECT 1 FROM media_variants mv WHERE mv.media_id = ma.id AND mv.variant = 'original' AND mv.status = 'ready')
        AND EXISTS (SELECT 1 FROM media_variants mv WHERE mv.media_id = ma.id AND mv.variant = 'detail' AND mv.status = 'ready')
        AND EXISTS (SELECT 1 FROM media_variants mv WHERE mv.media_id = ma.id AND mv.variant = 'thumb' AND mv.status = 'ready')
      );
" )"
[[ "$pending_backfill" == "0" ]] || fail "pending media variants: $pending_backfill"
printf 'PASS %-28s pending_backfill=0\n' "media backfill"

failed_events="$(query "
    SELECT count(*)
    FROM outbox_events
    WHERE event_type IN ('media.process', 'media.delete') AND status = 'failed';
" )"
[[ "$failed_events" == "0" ]] || fail "failed media outbox events: $failed_events"
printf 'PASS %-28s failed_events=0\n' "media outbox"

latest_migration="$(query "SELECT version FROM schema_migrations ORDER BY version::int DESC LIMIT 1;")"
[[ -n "$latest_migration" ]] || fail "schema_migrations has no applied version"
if [[ -n "$EXPECTED_MIGRATION_VERSION" && "$latest_migration" != "$EXPECTED_MIGRATION_VERSION" ]]; then
    fail "latest migration is $latest_migration, expected $EXPECTED_MIGRATION_VERSION"
fi
printf 'PASS %-28s version=%s\n' "database migration" "$latest_migration"

has_dirty_column="$(query "
    SELECT CASE WHEN EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'schema_migrations' AND column_name = 'dirty'
    ) THEN '1' ELSE '0' END;
")"
if [[ "$has_dirty_column" == "1" ]]; then
    dirty="$(query "SELECT CASE WHEN dirty THEN 't' ELSE 'f' END FROM schema_migrations ORDER BY version::int DESC LIMIT 1;")"
    [[ "$dirty" == "f" ]] || fail "latest migration is dirty"
    printf 'PASS %-28s dirty=false\n' "migration cleanliness"
fi

public_media_id="$(query "
    SELECT m.id
    FROM media_assets m
    WHERE m.status = 'ready' AND m.deleted_at IS NULL AND m.mime_type LIKE 'image/%'
      AND EXISTS (
        SELECT 1 FROM media_variants mv
        WHERE mv.media_id = m.id AND mv.variant = 'thumb' AND mv.status = 'ready'
      )
      AND (
        EXISTS (
          SELECT 1 FROM post_media pm
          JOIN posts p ON p.id = pm.post_id
          WHERE pm.media_id = m.id AND p.deleted_at IS NULL
            AND p.publication_status = 'published' AND p.moderation_status = 'normal'
        ) OR EXISTS (
          SELECT 1 FROM comment_media cm
          JOIN comments c ON c.id = cm.comment_id
          WHERE cm.media_id = m.id AND c.deleted_at IS NULL
            AND c.publication_status = 'published' AND c.moderation_status = 'normal'
        )
      )
    ORDER BY m.created_at DESC, m.id DESC
    LIMIT 1;
")"
[[ -n "$public_media_id" ]] || fail "no public ready media fixture is available"
expect_status "media gateway" "$BASE_URL/api/v1/media-file/$public_media_id/thumb" 200

printf 'staging smoke passed: release=%s migration=%s\n' \
    "${EXPECTED_RELEASE_SHA:-unverified}" "$latest_migration"
