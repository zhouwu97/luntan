#!/usr/bin/env python3
"""把杯友酱公开榜单、评价和配图同步到本项目的 PostgreSQL 与媒体目录。

客户端只访问本项目 API：商品、排行榜视图、脱敏作者、评价树与图片都通过
本库的 ranking_toys、ranking_toy_comments、media_assets 等表提供。脚本保留
源站的商品、名次、正文和评分，不保存源站作者昵称、头像或账号标识。
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import html
import json
import mimetypes
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


SOURCE_PROVIDER = "beiyoujiang"
SOURCE_TOY_API = "https://beiyoujiang.com/api/toy/getToy"
SOURCE_REVIEWS_API = "https://beiyoujiang.com/api/toyComment/getToyAllReview"
SOURCE_IMAGE_BASE = "https://beiyoujiang.com/ToyImg/"
SYSTEM_USER_ID = "user-ranking-import-system"
SOURCE_USER_PREFIX = "user-ranking-import-"

DISPLAY_NAME_PREFIXES = ("慢玩", "软萌", "夜猫", "温水", "清洗", "收纳", "开箱", "杯友")
DISPLAY_NAME_SUFFIXES = ("观察员", "研究员", "试用员", "记录本", "小分队", "体验官", "玩家", "拿铁")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--snapshot",
        type=Path,
        default=Path("assets/ranking/beiyoujiang_snapshot.json"),
        help="由 sync_beiyoujiang_rankings.ps1 生成的榜单快照",
    )
    parser.add_argument("--output-dir", type=Path, required=True, help="CSV 与导入清单输出目录")
    parser.add_argument("--media-dir", type=Path, required=True, help="服务器静态媒体根目录")
    parser.add_argument("--db-url", default=os.environ.get("DATABASE_URL", ""))
    parser.add_argument("--skip-db", action="store_true", help="只生成导入包，不调用 psql")
    parser.add_argument("--toy-limit", type=int, default=0, help="仅用于联调；0 表示同步全部商品")
    parser.add_argument("--review-delay", type=float, default=0.15, help="每个商品评价请求间隔秒数")
    return parser.parse_args()


def post_json(url: str, body: dict[str, Any]) -> dict[str, Any]:
    payload = json.dumps(body, ensure_ascii=False).encode("utf-8")
    for attempt in range(5):
        request = urllib.request.Request(
            url,
            data=payload,
            headers={"Content-Type": "application/json", "User-Agent": "luntan-ranking-import/1.0"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                value: Any = json.loads(response.read().decode("utf-8"))
            if isinstance(value, str):
                value = json.loads(value)
            if not isinstance(value, dict):
                raise RuntimeError("源站返回不是对象")
            return value
        except urllib.error.HTTPError as error:
            if error.code != 429 or attempt == 4:
                raise
            time.sleep(max(1.0, float(error.headers.get("Retry-After") or 1)))
    raise RuntimeError("源站请求重试耗尽")


def clean_content(value: Any) -> str:
    text = str(value or "")
    text = re.sub(r"<img\b[^>]*>", "", text, flags=re.IGNORECASE)
    text = re.sub(r"<\s*(br|/p|/div|/li)\s*/?>", "\n", text, flags=re.IGNORECASE)
    text = re.sub(r"<[^>]+>", "", text)
    text = html.unescape(text).replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"[ \t]+\n", "\n", text)
    text = re.sub(r"\n{3,}", "\n\n", text).strip()
    return text or "（此评价未提供文字内容）"


def source_time(value: Any, fallback: datetime) -> datetime:
    if isinstance(value, str) and value.strip():
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
            if parsed.tzinfo is None:
                parsed = parsed.replace(tzinfo=timezone.utc)
            return parsed.astimezone(timezone.utc)
        except ValueError:
            pass
    return fallback


def iso(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat()


def safe_id(value: Any) -> str:
    return re.sub(r"[^A-Za-z0-9_-]", "_", str(value or "")) or "unknown"


def imported_user_id(source_user_id: Any) -> str:
    return f"{SOURCE_USER_PREFIX}{safe_id(source_user_id)}"


def display_name(source_user_id: Any) -> str:
    digest = hashlib.sha256(f"ranking-import:{source_user_id}".encode("utf-8")).hexdigest()
    prefix = DISPLAY_NAME_PREFIXES[int(digest[:2], 16) % len(DISPLAY_NAME_PREFIXES)]
    suffix = DISPLAY_NAME_SUFFIXES[int(digest[2:4], 16) % len(DISPLAY_NAME_SUFFIXES)]
    return f"{prefix}{suffix}_{int(digest[4:10], 16) % 10000:04d}"


def json_list(value: Any) -> list[str]:
    if isinstance(value, list):
        return [str(item) for item in value if str(item).strip()]
    if isinstance(value, str) and value.strip():
        try:
            decoded = json.loads(value)
            return json_list(decoded)
        except json.JSONDecodeError:
            return []
    return []


def source_image_name(value: Any) -> str:
    name = Path(str(value or "")).name
    if not name or name in {".", ".."} or name != str(value):
        raise ValueError(f"不安全的源图片名称：{value!r}")
    return name


def image_extension(name: str) -> str:
    extension = Path(name).suffix.lower()
    return extension if extension in {".webp", ".jpg", ".jpeg", ".png", ".gif"} else ".webp"


def media_metadata(path: Path, source_name: str) -> tuple[int, str, str]:
    data = path.read_bytes()
    if not data:
        raise RuntimeError(f"媒体文件为空：{path}")
    mime_type = mimetypes.guess_type(source_name)[0] or "image/webp"
    return len(data), mime_type, hashlib.sha256(data).hexdigest()


def download_image(source_name: str, media_root: Path, object_key: str) -> tuple[int, str, str]:
    source_name = source_image_name(source_name)
    destination = media_root / object_key
    destination.parent.mkdir(parents=True, exist_ok=True)
    if not destination.exists() or destination.stat().st_size == 0:
        url = SOURCE_IMAGE_BASE + urllib.parse.quote(source_name)
        request = urllib.request.Request(url, headers={"User-Agent": "luntan-ranking-import/1.0"})
        with urllib.request.urlopen(request, timeout=60) as response:
            data = response.read()
        if not data:
            raise RuntimeError(f"图片下载为空：{source_name}")
        destination.write_bytes(data)
    return media_metadata(destination, source_name)


def write_csv(path: Path, headers: list[str], rows: list[list[Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(headers)
        writer.writerows(rows)


def source_toy_id(item: dict[str, Any]) -> str:
    return safe_id(item.get("id"))


def toy_db_id(item: dict[str, Any]) -> str:
    return f"toy-{SOURCE_PROVIDER}-{source_toy_id(item)}"


def first_image(item: dict[str, Any], key: str) -> str | None:
    values = json_list(item.get(key))
    return values[0] if values else None


def collect_snapshot(snapshot: dict[str, Any], toy_limit: int) -> tuple[dict[str, dict[str, Any]], list[dict[str, Any]]]:
    raw_views = snapshot.get("views")
    if not isinstance(raw_views, dict):
        raise RuntimeError("榜单快照缺少 views")
    toys: dict[str, dict[str, Any]] = {}
    view_rows: list[dict[str, Any]] = []
    for view_key, raw_view in raw_views.items():
        if not isinstance(raw_view, dict):
            continue
        parts = str(view_key).split("|", maxsplit=1)
        tab_key, category_key = (parts + [""])[:2]
        entries: list[tuple[dict[str, Any], bool]] = []
        weekly_top = raw_view.get("weekly_top")
        if isinstance(weekly_top, dict):
            entries.append((weekly_top, True))
        items = raw_view.get("items")
        if isinstance(items, list):
            entries.extend((item, False) for item in items if isinstance(item, dict))
        for item, is_weekly_top in entries:
            source_id = source_toy_id(item)
            if source_id == "unknown":
                continue
            toys.setdefault(source_id, item)
            rank = int(item.get("rank") or 0)
            if rank <= 0:
                rank = len(view_rows) + 1
            view_rows.append(
                {
                    "view_key": str(view_key), "tab_key": tab_key, "category_key": category_key,
                    "toy_source_id": source_id, "rank": rank, "is_weekly_top": is_weekly_top,
                }
            )
    if toy_limit > 0:
        selected = set(sorted(toys, key=lambda value: int(value) if value.isdigit() else value)[:toy_limit])
        toys = {key: item for key, item in toys.items() if key in selected}
        view_rows = [row for row in view_rows if row["toy_source_id"] in selected]
    return toys, view_rows


def build_bundle(args: argparse.Namespace) -> dict[str, int]:
    snapshot = json.loads(args.snapshot.read_text(encoding="utf-8-sig"))
    if not isinstance(snapshot, dict):
        raise RuntimeError("榜单快照格式错误")
    fetched_at = source_time(snapshot.get("fetched_at"), datetime.now(timezone.utc))
    raw_toys, source_ranks = collect_snapshot(snapshot, args.toy_limit)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    args.media_dir.mkdir(parents=True, exist_ok=True)

    users: dict[str, list[Any]] = {
        SYSTEM_USER_ID: [SYSTEM_USER_ID, "榜单资料库", "active", iso(fetched_at), iso(fetched_at)]
    }
    profiles: dict[str, list[Any]] = {
        SYSTEM_USER_ID: [SYSTEM_USER_ID, "榜单资料库", "", "本项目同步的公开排行榜资料", 1, 0, iso(fetched_at), iso(fetched_at), "new"]
    }
    media_rows: list[list[Any]] = []
    toy_rows: list[list[Any]] = []
    rank_rows: list[list[Any]] = []
    comment_rows: list[list[Any]] = []
    comment_media_rows: list[list[Any]] = []
    state_rows: dict[tuple[str, str], list[Any]] = {}
    distribution_rows: list[list[Any]] = []
    downloaded_media_ids: set[str] = set()

    def add_user(source_user_id: Any, level: Any, created_at: datetime) -> str:
        user_id = imported_user_id(source_user_id)
        if user_id not in users:
            nickname = display_name(source_user_id)
            users[user_id] = [user_id, nickname, "active", iso(created_at), iso(created_at)]
            profiles[user_id] = [
                user_id, nickname, "", "社区导入的匿名展示账号", max(1, int(level or 1)), 0,
                iso(created_at), iso(created_at), "new",
            ]
        return user_id

    def add_media(media_id: str, owner_id: str, image_name: str, object_key: str, created_at: datetime) -> None:
        if media_id in downloaded_media_ids:
            return
        size, mime_type, checksum = download_image(image_name, args.media_dir, object_key)
        media_rows.append([
            media_id, owner_id, object_key, Path(object_key).name, mime_type,
            0, 0, size, checksum, "ready", iso(created_at), iso(created_at), iso(created_at),
        ])
        downloaded_media_ids.add(media_id)

    def add_reply_tree(
        replies: list[Any], *, toy_id: str, root_id: str, parent_id: str, parent_author_id: str,
        root_time: datetime, depth: int,
    ) -> None:
        for offset, raw_reply in enumerate(replies):
            if not isinstance(raw_reply, dict):
                continue
            source_id = safe_id(raw_reply.get("id"))
            comment_id = f"ranking-import-comment-{toy_id}-reply-{source_id}"
            source_user = raw_reply.get("userId")
            author_id = add_user(source_user, raw_reply.get("level"), root_time)
            reply_time = source_time(raw_reply.get("createdAt"), root_time + timedelta(seconds=depth * 100 + offset))
            explicit_parent = raw_reply.get("parentId")
            actual_parent = (
                f"ranking-import-comment-{toy_id}-reply-{safe_id(explicit_parent)}"
                if explicit_parent not in (None, "", 0)
                else parent_id
            )
            comment_rows.append([
                comment_id, toy_id, author_id, root_id, actual_parent, parent_author_id,
                clean_content(raw_reply.get("content")), int(raw_reply.get("likeCount") or 0),
                SOURCE_PROVIDER, f"reply-{source_id}", iso(reply_time), iso(reply_time), depth,
            ])
            nested = raw_reply.get("replies")
            if isinstance(nested, list):
                add_reply_tree(
                    nested, toy_id=toy_id, root_id=root_id, parent_id=comment_id,
                    parent_author_id=author_id, root_time=reply_time, depth=depth + 1,
                )

    for canonical_index, source_id in enumerate(sorted(raw_toys, key=lambda value: int(value) if value.isdigit() else value), start=1):
        snapshot_item = raw_toys[source_id]
        detail_response = post_json(SOURCE_TOY_API, {"toyId": int(source_id) if source_id.isdigit() else source_id, "userId": 0})
        detail = detail_response.get("data") if isinstance(detail_response.get("data"), dict) else snapshot_item
        db_id = toy_db_id(snapshot_item)
        updated_at = source_time(detail.get("updatedAt"), fetched_at)
        category = str(detail.get("category") or snapshot_item.get("category") or "")
        stimulation = str(detail.get("stimulation") or snapshot_item.get("stimulation") or "")
        tags = [tag.strip() for tag in str(detail.get("tags") or "").split(",") if tag.strip()]
        cover_media_id = ""
        hero_media_id = ""
        cover = first_image(detail, "coverUrl") or first_image(snapshot_item, "coverUrl")
        hero = first_image(detail, "weeklyTopImg") or first_image(snapshot_item, "weeklyTopImg")
        if cover:
            cover_media_id = f"media-ranking-toy-{source_id}-cover"
            add_media(
                cover_media_id, SYSTEM_USER_ID, cover,
                f"ranking/toys/{source_id}/cover{image_extension(cover)}", updated_at,
            )
        if hero:
            hero_media_id = f"media-ranking-toy-{source_id}-hero"
            add_media(
                hero_media_id, SYSTEM_USER_ID, hero,
                f"ranking/toys/{source_id}/hero{image_extension(hero)}", updated_at,
            )
        rating = float(detail.get("rating") or snapshot_item.get("rating") or 0)
        review_count = int(detail.get("totalReviews") or detail.get("reviewCount") or snapshot_item.get("reviewCount") or 0)
        source_total_centi = round(rating * review_count * 10)
        toy_rows.append([
            db_id, 1_000_000 + canonical_index, str(detail.get("name") or snapshot_item.get("name") or "未命名商品"),
            str(detail.get("merchant") or snapshot_item.get("merchant") or ""),
            int(detail.get("releaseYear") or snapshot_item.get("releaseYear") or 0),
            str(detail.get("description") or snapshot_item.get("description") or ""),
            json.dumps(tags, ensure_ascii=False), "", int(detail.get("wantCount") or snapshot_item.get("wantCount") or 0),
            source_total_centi, review_count, category, json.dumps([stimulation] if stimulation else [], ensure_ascii=False),
            SOURCE_PROVIDER, source_id, iso(updated_at), cover_media_id, hero_media_id,
            f"https://beiyoujiang.com/bang/{source_id}",
        ])
        star_counts = detail.get("starCounts") if isinstance(detail.get("starCounts"), dict) else {}
        for star in range(1, 6):
            distribution_rows.append([db_id, star * 2, int(star_counts.get(str(star)) or 0)])

        review_response = post_json(SOURCE_REVIEWS_API, {"toyId": int(source_id) if source_id.isdigit() else source_id, "userId": 0})
        reviews = review_response.get("data") if isinstance(review_response.get("data"), list) else []
        for review in reviews:
            if not isinstance(review, dict):
                continue
            source_review_id = safe_id(review.get("id"))
            root_id = f"ranking-import-comment-{db_id}-review-{source_review_id}"
            created_at = source_time(review.get("createdAt"), updated_at)
            author = review.get("user") if isinstance(review.get("user"), dict) else {}
            author_id = add_user(author.get("id") or review.get("userId"), author.get("level") or review.get("level"), created_at)
            score = float(review.get("score") or 0)
            state_rows[(db_id, author_id)] = [db_id, author_id, max(1, min(10, round(score * 2))), iso(created_at)]
            comment_rows.append([
                root_id, db_id, author_id, root_id, "", "", clean_content(review.get("content")),
                int(review.get("likeCount") or 0), SOURCE_PROVIDER, f"review-{source_review_id}",
                iso(created_at), iso(created_at), 0,
            ])
            for index, image_name in enumerate(json_list(review.get("images") or review.get("imageUrls"))):
                media_id = f"media-ranking-review-{source_id}-{source_review_id}-{index}"
                object_key = f"ranking/reviews/{source_id}/{source_review_id}/{index}{image_extension(image_name)}"
                add_media(media_id, author_id, image_name, object_key, created_at)
                comment_media_rows.append([root_id, media_id, index, iso(created_at)])
            replies = review.get("replies")
            if isinstance(replies, list):
                add_reply_tree(
                    replies, toy_id=db_id, root_id=root_id, parent_id=root_id,
                    parent_author_id=author_id, root_time=created_at, depth=1,
                )
        time.sleep(max(0.0, args.review_delay))

    for rank in source_ranks:
        rank_rows.append([
            SOURCE_PROVIDER, rank["view_key"], rank["tab_key"], rank["category_key"],
            toy_db_id(raw_toys[rank["toy_source_id"]]), rank["rank"], str(rank["is_weekly_top"]).lower(), iso(fetched_at),
        ])

    write_csv(args.output_dir / "users.csv", ["id", "username", "status", "created_at", "updated_at"], list(users.values()))
    write_csv(args.output_dir / "profiles.csv", ["user_id", "nickname", "avatar_media_id", "bio", "level", "experience", "created_at", "updated_at", "trust_level"], list(profiles.values()))
    write_csv(args.output_dir / "media.csv", ["id", "owner_id", "object_key", "original_name", "mime_type", "width", "height", "size", "sha256", "status", "created_at", "updated_at", "completed_at"], media_rows)
    write_csv(args.output_dir / "toys.csv", ["id", "rank", "name", "merchant", "release_year", "description", "tags", "asset_key", "source_want_count", "source_rating_total_centi", "source_rating_count", "category", "segments", "source_provider", "source_toy_id", "source_updated_at", "cover_media_id", "hero_media_id", "source_url"], toy_rows)
    write_csv(args.output_dir / "ranks.csv", ["source_provider", "view_key", "tab_key", "category_key", "toy_id", "rank", "is_weekly_top", "snapshot_fetched_at"], rank_rows)
    write_csv(args.output_dir / "comments.csv", ["id", "toy_id", "author_id", "root_id", "parent_id", "reply_to_user_id", "content", "like_count", "source_provider", "source_comment_id", "created_at", "updated_at", "depth"], comment_rows)
    write_csv(args.output_dir / "comment_media.csv", ["comment_id", "media_id", "sort_order", "created_at"], comment_media_rows)
    write_csv(args.output_dir / "states.csv", ["toy_id", "user_id", "rating", "updated_at"], list(state_rows.values()))
    write_csv(args.output_dir / "distribution.csv", ["toy_id", "score", "source_rating_count"], distribution_rows)
    manifest = {
        "source": "https://beiyoujiang.com/rankingList", "fetched_at": iso(fetched_at),
        "toys": len(toy_rows), "views": len(rank_rows), "users": len(users), "media": len(media_rows),
        "reviews_and_replies": len(comment_rows), "review_media": len(comment_media_rows),
    }
    (args.output_dir / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    return {key: int(value) for key, value in manifest.items() if isinstance(value, int)}


def psql_path(path: Path) -> str:
    return path.resolve().as_posix().replace("'", "''")


def psql_import(bundle: Path, db_url: str) -> None:
    if not db_url:
        raise RuntimeError("未提供 DATABASE_URL，拒绝执行数据库写入")
    sql = f"""
BEGIN;
CREATE TEMP TABLE import_users (id text, username text, status text, created_at timestamptz, updated_at timestamptz) ON COMMIT DROP;
\\copy import_users FROM '{psql_path(bundle / "users.csv")}' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
INSERT INTO users (id, username, status, created_at, updated_at)
SELECT id, username, status, created_at, updated_at FROM import_users
ON CONFLICT (id) DO UPDATE SET username = EXCLUDED.username, status = EXCLUDED.status, deleted_at = NULL, updated_at = EXCLUDED.updated_at;

CREATE TEMP TABLE import_profiles (user_id text, nickname text, avatar_media_id text, bio text, level integer, experience integer, created_at timestamptz, updated_at timestamptz, trust_level text) ON COMMIT DROP;
\\copy import_profiles FROM '{psql_path(bundle / "profiles.csv")}' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
INSERT INTO user_profiles (user_id, nickname, avatar_media_id, bio, level, experience, created_at, updated_at, trust_level)
SELECT user_id, nickname, NULLIF(avatar_media_id, ''), bio, level, experience, created_at, updated_at, trust_level FROM import_profiles
ON CONFLICT (user_id) DO UPDATE SET nickname = EXCLUDED.nickname, bio = EXCLUDED.bio, level = EXCLUDED.level, updated_at = EXCLUDED.updated_at;

CREATE TEMP TABLE import_media (id text, owner_id text, object_key text, original_name text, mime_type text, width integer, height integer, size bigint, sha256 text, status text, created_at timestamptz, updated_at timestamptz, completed_at timestamptz) ON COMMIT DROP;
\\copy import_media FROM '{psql_path(bundle / "media.csv")}' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
INSERT INTO media_assets (id, owner_id, object_key, original_name, mime_type, width, height, size, sha256, status, created_at, updated_at, completed_at, deleted_at)
SELECT id, owner_id, object_key, original_name, mime_type, width, height, size, sha256, status, created_at, updated_at, completed_at, NULL FROM import_media
ON CONFLICT (id) DO UPDATE SET owner_id = EXCLUDED.owner_id, object_key = EXCLUDED.object_key, original_name = EXCLUDED.original_name, mime_type = EXCLUDED.mime_type, width = EXCLUDED.width, height = EXCLUDED.height, size = EXCLUDED.size, sha256 = EXCLUDED.sha256, status = EXCLUDED.status, updated_at = EXCLUDED.updated_at, completed_at = EXCLUDED.completed_at, deleted_at = NULL;

CREATE TEMP TABLE import_toys (id text, rank integer, name text, merchant text, release_year integer, description text, tags jsonb, asset_key text, source_want_count bigint, source_rating_total_centi bigint, source_rating_count bigint, category text, segments jsonb, source_provider text, source_toy_id text, source_updated_at timestamptz, cover_media_id text, hero_media_id text, source_url text) ON COMMIT DROP;
\\copy import_toys FROM '{psql_path(bundle / "toys.csv")}' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
INSERT INTO ranking_toys (id, rank, name, merchant, release_year, description, tags, asset_key, want_count, rating_total_centi, rating_count, active, category, segments, source_provider, source_toy_id, source_updated_at, source_want_count, source_rating_total_centi, source_rating_count, cover_media_id, hero_media_id, source_url)
SELECT id, rank, name, merchant, release_year, description, ARRAY(SELECT jsonb_array_elements_text(tags)), asset_key, source_want_count, source_rating_total_centi, source_rating_count, true, category, ARRAY(SELECT jsonb_array_elements_text(segments)), source_provider, source_toy_id, source_updated_at, source_want_count, source_rating_total_centi, source_rating_count, NULLIF(cover_media_id, ''), NULLIF(hero_media_id, ''), source_url FROM import_toys
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name, merchant = EXCLUDED.merchant, release_year = EXCLUDED.release_year, description = EXCLUDED.description, tags = EXCLUDED.tags, asset_key = EXCLUDED.asset_key, active = true, category = EXCLUDED.category, segments = EXCLUDED.segments,
  source_provider = EXCLUDED.source_provider, source_toy_id = EXCLUDED.source_toy_id, source_updated_at = EXCLUDED.source_updated_at,
  want_count = EXCLUDED.source_want_count + GREATEST(ranking_toys.want_count - ranking_toys.source_want_count, 0),
  rating_total_centi = EXCLUDED.source_rating_total_centi + GREATEST(ranking_toys.rating_total_centi - ranking_toys.source_rating_total_centi, 0),
  rating_count = EXCLUDED.source_rating_count + GREATEST(ranking_toys.rating_count - ranking_toys.source_rating_count, 0),
  source_want_count = EXCLUDED.source_want_count, source_rating_total_centi = EXCLUDED.source_rating_total_centi, source_rating_count = EXCLUDED.source_rating_count,
  cover_media_id = EXCLUDED.cover_media_id, hero_media_id = EXCLUDED.hero_media_id, source_url = EXCLUDED.source_url, updated_at = now();

CREATE TEMP TABLE import_ranks (source_provider text, view_key text, tab_key text, category_key text, toy_id text, rank integer, is_weekly_top boolean, snapshot_fetched_at timestamptz) ON COMMIT DROP;
\\copy import_ranks FROM '{psql_path(bundle / "ranks.csv")}' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
DELETE FROM ranking_toy_rankings WHERE source_provider = '{SOURCE_PROVIDER}';
INSERT INTO ranking_toy_rankings (source_provider, view_key, tab_key, category_key, toy_id, rank, is_weekly_top, snapshot_fetched_at)
SELECT source_provider, view_key, tab_key, category_key, toy_id, rank, is_weekly_top, snapshot_fetched_at FROM import_ranks;

CREATE TEMP TABLE import_distribution (toy_id text, score integer, source_rating_count bigint) ON COMMIT DROP;
\\copy import_distribution FROM '{psql_path(bundle / "distribution.csv")}' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
UPDATE ranking_toy_rating_distribution distribution SET rating_count = GREATEST(distribution.rating_count - distribution.source_rating_count, 0), source_rating_count = 0
WHERE toy_id IN (SELECT id FROM import_toys);
INSERT INTO ranking_toy_rating_distribution (toy_id, score, rating_count, source_rating_count)
SELECT toy_id, score, source_rating_count, source_rating_count FROM import_distribution
ON CONFLICT (toy_id, score) DO UPDATE SET rating_count = ranking_toy_rating_distribution.rating_count + EXCLUDED.source_rating_count, source_rating_count = EXCLUDED.source_rating_count;

DELETE FROM ranking_toy_user_states WHERE toy_id IN (SELECT id FROM import_toys) AND user_id LIKE '{SOURCE_USER_PREFIX}%';
DELETE FROM ranking_toy_comments WHERE toy_id IN (SELECT id FROM import_toys) AND source_provider = '{SOURCE_PROVIDER}';
CREATE TEMP TABLE import_states (toy_id text, user_id text, rating integer, updated_at timestamptz) ON COMMIT DROP;
\\copy import_states FROM '{psql_path(bundle / "states.csv")}' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
INSERT INTO ranking_toy_user_states (toy_id, user_id, rating, created_at, updated_at)
SELECT toy_id, user_id, rating, updated_at, updated_at FROM import_states;

CREATE TEMP TABLE import_comments (id text, toy_id text, author_id text, root_id text, parent_id text, reply_to_user_id text, content text, like_count bigint, source_provider text, source_comment_id text, created_at timestamptz, updated_at timestamptz, depth integer) ON COMMIT DROP;
\\copy import_comments FROM '{psql_path(bundle / "comments.csv")}' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
DO $$
DECLARE current_depth integer := 0; max_depth integer := 0;
BEGIN
  SELECT COALESCE(MAX(depth), 0) INTO max_depth FROM import_comments;
  WHILE current_depth <= max_depth LOOP
    INSERT INTO ranking_toy_comments (id, toy_id, author_id, content, root_id, parent_id, reply_to_user_id, like_count, source_provider, source_comment_id, created_at, updated_at)
    SELECT id, toy_id, author_id, content, root_id, NULLIF(parent_id, ''), NULLIF(reply_to_user_id, ''), like_count, source_provider, source_comment_id, created_at, updated_at
    FROM import_comments WHERE depth = current_depth;
    current_depth := current_depth + 1;
  END LOOP;
END $$;
UPDATE ranking_toy_comments parent SET reply_count = (SELECT count(*) FROM ranking_toy_comments child WHERE child.parent_id = parent.id AND child.deleted_at IS NULL), updated_at = now()
WHERE parent.id IN (SELECT id FROM import_comments WHERE depth = 0);

CREATE TEMP TABLE import_comment_media (comment_id text, media_id text, sort_order integer, created_at timestamptz) ON COMMIT DROP;
\\copy import_comment_media FROM '{psql_path(bundle / "comment_media.csv")}' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
INSERT INTO ranking_toy_comment_media (comment_id, media_id, sort_order, created_at)
SELECT comment_id, media_id, sort_order, created_at FROM import_comment_media;
COMMIT;
"""
    subprocess.run(["psql", "-v", "ON_ERROR_STOP=1", "-P", "pager=off", db_url], input=sql, text=True, check=True)


def main() -> int:
    args = parse_args()
    if args.toy_limit < 0:
        raise SystemExit("--toy-limit 不能小于 0")
    stats = build_bundle(args)
    if not args.skip_db:
        psql_import(args.output_dir, args.db_url)
    print(json.dumps(stats, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:  # noqa: BLE001 - CLI 需要输出可读失败原因。
        print(f"榜单导入失败: {error}", file=sys.stderr)
        raise SystemExit(1)
