#!/usr/bin/env python3
"""从杯友酱公开列表生成占位展示数据，并写入论坛 PostgreSQL。

脚本只保存随机化的占位用户名，不保存源站作者昵称或头像。
脚本依赖 Python 标准库和 psql，便于直接在远端 Debian 环境执行。
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
import shutil
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SOURCE_API = "https://beiyoujiang.com/api/post/getAllPost"
SOURCE_IMAGE_BASE = "https://beiyoujiang.com/PostImg/"
# 当前部署通过服务器 IP 暴露媒体目录；可用 --public-media-base 覆盖。
PUBLIC_MEDIA_BASE = "http://101.42.27.44/imported-media"

COMMUNITIES = {
    1: {
        "category_id": "category-import-digital",
        "category_name": "数码玩具",
        "category_slug": "import-digital",
        "community_id": "community-import-unboxing",
        "community_slug": "import-unboxing",
        "community_name": "大型拆箱",
        "description": "源站帖子占位展示：玩具、设备和真实使用体验。",
        "sort_order": 10,
    },
    2: {
        "category_id": "category-import-forum",
        "category_name": "交流讨论",
        "category_slug": "import-forum",
        "community_id": "community-import-forum",
        "community_slug": "import-forum",
        "community_name": "酱紫社区",
        "description": "源站帖子占位展示：经验交流、求助和讨论。",
        "sort_order": 11,
    },
    3: {
        "category_id": "category-import-daily",
        "category_name": "日常分享",
        "category_slug": "import-daily",
        "community_id": "community-import-daily",
        "community_slug": "import-daily",
        "community_name": "杂鱼日常",
        "description": "源站帖子占位展示：日常记录和轻松分享。",
        "sort_order": 12,
    },
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--media-dir", type=Path, required=True)
    parser.add_argument("--page-size", type=int, default=100)
    parser.add_argument("--api-url", default=SOURCE_API)
    parser.add_argument("--image-base", default=SOURCE_IMAGE_BASE)
    parser.add_argument("--public-media-base", default=PUBLIC_MEDIA_BASE)
    parser.add_argument("--db-url", default=os.environ.get("DATABASE_URL", ""))
    parser.add_argument("--skip-db", action="store_true")
    parser.add_argument("--keep-workdir", action="store_true")
    return parser.parse_args()


def fetch_posts(api_url: str, page_size: int) -> list[dict[str, Any]]:
    payload = json.dumps(
        {"plate": None, "most": None, "userId": None, "page": 1, "pageSize": page_size}
    ).encode("utf-8")
    request = urllib.request.Request(
        api_url,
        data=payload,
        headers={"Content-Type": "application/json", "User-Agent": "luntan-placeholder-import/1.0"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        value: Any = json.loads(response.read().decode("utf-8"))
    # 该接口在部分环境会把 JSON 再包成字符串。
    if isinstance(value, str):
        value = json.loads(value)
    items = value.get("data", []) if isinstance(value, dict) else []
    if not isinstance(items, list):
        raise RuntimeError("源站帖子接口返回格式异常")
    return [item for item in items if isinstance(item, dict)][:page_size]


def clean_content(value: Any) -> str:
    text = str(value or "")
    # 源站内容包含少量表情 img 和 HTML 排版标签，清理后更适合原生客户端文本渲染。
    text = re.sub(r"<img\b[^>]*>", "", text, flags=re.IGNORECASE)
    text = re.sub(r"<\s*(br|/p|/div|/li)\s*/?>", "\n", text, flags=re.IGNORECASE)
    text = re.sub(r"<[^>]+>", "", text)
    text = html.unescape(text).replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"[ \t]+\n", "\n", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip() or "（此帖子未提供文字内容）"


def iso_time(value: Any) -> str:
    if not isinstance(value, str) or not value.strip():
        return datetime.now(timezone.utc).isoformat()
    parsed = value.replace("Z", "+00:00")
    try:
        moment = datetime.fromisoformat(parsed)
    except ValueError:
        return datetime.now(timezone.utc).isoformat()
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    return moment.astimezone(timezone.utc).isoformat()


def placeholder_username(author_id: Any) -> str:
    # 用源作者 ID 做种子，只为保证重复导入稳定；用户名本身不包含源站用户名。
    digest = hashlib.sha256(f"placeholder-user:{author_id}".encode("utf-8")).hexdigest()
    return f"占位用户_{digest[:8]}"


def safe_source_id(value: Any) -> str:
    text = str(value or "")
    return re.sub(r"[^A-Za-z0-9_-]", "_", text) or "unknown"


def webp_dimensions(data: bytes) -> tuple[int, int]:
    """读取常见 WebP 头部尺寸，无法识别时使用稳定兜底值。"""
    if len(data) >= 30 and data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        chunk = data[12:16]
        if chunk == b"VP8X":
            width = 1 + data[24] + (data[25] << 8) + (data[26] << 16)
            height = 1 + data[27] + (data[28] << 8) + (data[29] << 16)
            return width, height
        if chunk == b"VP8L" and len(data) >= 25 and data[20] == 0x2F:
            width = 1 + data[21] + ((data[22] & 0x3F) << 8)
            height = 1 + (data[22] >> 6) + (data[23] << 2) + ((data[24] & 0x0F) << 10)
            return width, height
        if chunk == b"VP8 " and len(data) >= 30 and data[23:26] == b"\x9d\x01\x2a":
            width = data[26] | ((data[27] & 0x3F) << 8)
            height = data[28] | ((data[29] & 0x3F) << 8)
            return width, height
    return 4, 3


def download_image(image_base: str, source_name: Any, destination: Path) -> tuple[int, int, int, str]:
    name = Path(str(source_name or "")).name
    if not name or name in {".", ".."} or name != str(source_name):
        raise ValueError(f"不安全的源站图片文件名: {source_name!r}")
    url = image_base.rstrip("/") + "/" + urllib.parse.quote(name)
    request = urllib.request.Request(url, headers={"User-Agent": "luntan-placeholder-import/1.0"})
    with urllib.request.urlopen(request, timeout=60) as response:
        data = response.read()
    if not data:
        raise RuntimeError(f"源站图片为空: {name}")
    destination.write_bytes(data)
    mime_type = response.headers.get_content_type() or mimetypes.guess_type(name)[0] or "image/webp"
    if mime_type not in {"image/jpeg", "image/png", "image/webp"}:
        raise RuntimeError(f"不支持的图片类型: {mime_type}")
    width, height = webp_dimensions(data) if mime_type == "image/webp" else (4, 3)
    return len(data), width, height, hashlib.sha256(data).hexdigest()


def write_csv(path: Path, headers: list[str], rows: list[list[Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(headers)
        writer.writerows(rows)


def build_bundle(args: argparse.Namespace) -> tuple[Path, dict[str, int]]:
    args.output_dir.mkdir(parents=True, exist_ok=True)
    args.media_dir.mkdir(parents=True, exist_ok=True)
    posts = fetch_posts(args.api_url, args.page_size)
    if len(posts) < args.page_size:
        print(f"提示：源站本次返回 {len(posts)} 条，目标为 {args.page_size} 条。", file=sys.stderr)

    users: dict[str, list[Any]] = {}
    profiles: dict[str, list[Any]] = {}
    post_rows: list[list[Any]] = []
    revision_rows: list[list[Any]] = []
    media_rows: list[list[Any]] = []
    post_media_rows: list[list[Any]] = []
    downloaded = 0

    for item in posts:
        source_post_id = safe_source_id(item.get("id"))
        source_author_id = safe_source_id(item.get("authorId"))
        user_id = f"user-import-{source_author_id}"
        username = placeholder_username(source_author_id)
        timestamp = iso_time(item.get("createdAt"))
        updated_at = iso_time(item.get("updatedAt") or item.get("createdAt"))
        if user_id not in users:
            users[user_id] = [user_id, username, "active", timestamp, updated_at]
            profiles[user_id] = [
                user_id,
                username,
                "",
                "源站帖子占位用户",
                1,
                0,
                timestamp,
                updated_at,
                "new",
            ]

        community = COMMUNITIES.get(int(item.get("plate") or 2), COMMUNITIES[2])
        post_id = f"post-import-{source_post_id}"
        title = str(item.get("title") or "未命名帖子").strip() or "未命名帖子"
        content = clean_content(item.get("content"))
        image_names = item.get("imageUrls") if isinstance(item.get("imageUrls"), list) else []
        post_type = "image" if image_names else "normal"
        post_rows.append(
            [
                post_id,
                user_id,
                community["community_id"],
                post_type,
                "published",
                "normal",
                title,
                content,
                int(item.get("CommentCount") or item.get("commentCount") or 0),
                int(item.get("likeCount") or 0),
                0,
                0,
                int(item.get("readingQuantity") or 0),
                timestamp,
                updated_at,
                timestamp,
            ]
        )
        revision_rows.append(
            [
                f"revision-import-{source_post_id}",
                post_id,
                user_id,
                community["community_id"],
                post_type,
                title,
                content,
                updated_at,
            ]
        )

        for index, source_name in enumerate(image_names):
            media_id = f"media-import-{source_post_id}-{index}"
            file_name = f"{post_id}-{index}.webp"
            destination = args.media_dir / file_name
            size, width, height, checksum = download_image(args.image_base, source_name, destination)
            media_rows.append(
                [
                    media_id,
                    user_id,
                    f"{args.public_media_base.rstrip('/')}/{file_name}",
                    file_name,
                    "image/webp",
                    width,
                    height,
                    size,
                    checksum,
                    "ready",
                    updated_at,
                    updated_at,
                    updated_at,
                ]
            )
            post_media_rows.append([post_id, media_id, index, updated_at])
            downloaded += 1

    write_csv(args.output_dir / "users.csv", ["id", "username", "status", "created_at", "updated_at"], list(users.values()))
    write_csv(
        args.output_dir / "profiles.csv",
        ["user_id", "nickname", "avatar_media_id", "bio", "level", "experience", "created_at", "updated_at", "trust_level"],
        list(profiles.values()),
    )
    category_rows = []
    community_rows = []
    for item in COMMUNITIES.values():
        category_rows.append([item["category_id"], "", item["category_name"], item["category_slug"], item["sort_order"], "active"])
        community_rows.append(
            [
                item["community_id"],
                item["category_id"],
                item["community_slug"],
                item["community_name"],
                item["description"],
                item["sort_order"],
                "public",
                "open",
                "active",
            ]
        )
    write_csv(args.output_dir / "categories.csv", ["id", "parent_id", "name", "slug", "sort_order", "status"], category_rows)
    write_csv(
        args.output_dir / "communities.csv",
        ["id", "category_id", "slug", "name", "description", "sort_order", "visibility", "join_policy", "status"],
        community_rows,
    )
    write_csv(
        args.output_dir / "posts.csv",
        [
            "id", "author_id", "community_id", "type", "publication_status", "moderation_status",
            "title", "content", "comment_count", "like_count", "bookmark_count", "share_count",
            "view_count", "created_at", "updated_at", "published_at",
        ],
        post_rows,
    )
    write_csv(
        args.output_dir / "revisions.csv",
        ["id", "post_id", "editor_id", "community_id", "type", "title", "content", "created_at"],
        revision_rows,
    )
    write_csv(
        args.output_dir / "media_assets.csv",
        [
            "id", "owner_id", "object_key", "original_name", "mime_type", "width", "height", "size",
            "sha256", "status", "created_at", "updated_at", "completed_at",
        ],
        media_rows,
    )
    write_csv(args.output_dir / "post_media.csv", ["post_id", "media_id", "sort_order", "created_at"], post_media_rows)
    (args.output_dir / "manifest.json").write_text(
        json.dumps(
            {
                "source": args.api_url,
                "posts": len(post_rows),
                "users": len(users),
                "media": downloaded,
                "generated_at": datetime.now(timezone.utc).isoformat(),
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    return args.output_dir, {"posts": len(post_rows), "users": len(users), "media": downloaded}


def psql_import(bundle_dir: Path, db_url: str) -> None:
    if not db_url:
        raise RuntimeError("未提供 DATABASE_URL，拒绝执行数据库写入")
    sql = f"""
BEGIN;
CREATE TEMP TABLE import_categories (id text, parent_id text, name text, slug text, sort_order integer, status text) ON COMMIT DROP;
\\copy import_categories FROM '{(bundle_dir / 'categories.csv').as_posix()}' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
INSERT INTO community_categories (id, parent_id, name, slug, sort_order, status)
SELECT id, NULLIF(parent_id, ''), name, slug, sort_order, status FROM import_categories
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, slug = EXCLUDED.slug, sort_order = EXCLUDED.sort_order, status = EXCLUDED.status, updated_at = now();

CREATE TEMP TABLE import_communities (id text, category_id text, slug text, name text, description text, sort_order integer, visibility text, join_policy text, status text) ON COMMIT DROP;
\\copy import_communities FROM '{(bundle_dir / 'communities.csv').as_posix()}' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
INSERT INTO communities (id, category_id, slug, name, description, sort_order, visibility, join_policy, status)
SELECT id, category_id, slug, name, description, sort_order, visibility, join_policy, status FROM import_communities
ON CONFLICT (id) DO UPDATE SET category_id = EXCLUDED.category_id, name = EXCLUDED.name, description = EXCLUDED.description, sort_order = EXCLUDED.sort_order, visibility = EXCLUDED.visibility, join_policy = EXCLUDED.join_policy, status = EXCLUDED.status, deleted_at = NULL, updated_at = now();

CREATE TEMP TABLE import_users (id text, username text, status text, created_at timestamptz, updated_at timestamptz) ON COMMIT DROP;
\\copy import_users FROM '{(bundle_dir / 'users.csv').as_posix()}' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
INSERT INTO users (id, username, status, created_at, updated_at)
SELECT id, username, status, created_at, updated_at FROM import_users
ON CONFLICT (id) DO UPDATE SET username = EXCLUDED.username, status = EXCLUDED.status, deleted_at = NULL, updated_at = EXCLUDED.updated_at;

CREATE TEMP TABLE import_profiles (user_id text, nickname text, avatar_media_id text, bio text, level integer, experience integer, created_at timestamptz, updated_at timestamptz, trust_level text) ON COMMIT DROP;
\\copy import_profiles FROM '{(bundle_dir / 'profiles.csv').as_posix()}' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
INSERT INTO user_profiles (user_id, nickname, avatar_media_id, bio, level, experience, created_at, updated_at, trust_level)
SELECT user_id, nickname, NULLIF(avatar_media_id, ''), bio, level, experience, created_at, updated_at, trust_level FROM import_profiles
ON CONFLICT (user_id) DO UPDATE SET nickname = EXCLUDED.nickname, bio = EXCLUDED.bio, level = EXCLUDED.level, experience = EXCLUDED.experience, trust_level = EXCLUDED.trust_level, updated_at = EXCLUDED.updated_at;

CREATE TEMP TABLE import_posts (id text, author_id text, community_id text, type text, publication_status text, moderation_status text, title text, content text, comment_count bigint, like_count bigint, bookmark_count bigint, share_count bigint, view_count bigint, created_at timestamptz, updated_at timestamptz, published_at timestamptz) ON COMMIT DROP;
\\copy import_posts FROM '{(bundle_dir / 'posts.csv').as_posix()}' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
INSERT INTO posts (id, author_id, community_id, type, publication_status, moderation_status, title, content, comment_count, like_count, bookmark_count, share_count, view_count, created_at, updated_at, published_at)
SELECT id, author_id, community_id, type, publication_status, moderation_status, title, content, comment_count, like_count, bookmark_count, share_count, view_count, created_at, updated_at, published_at FROM import_posts
ON CONFLICT (id) DO UPDATE SET author_id = EXCLUDED.author_id, community_id = EXCLUDED.community_id, type = EXCLUDED.type, publication_status = EXCLUDED.publication_status, moderation_status = EXCLUDED.moderation_status, title = EXCLUDED.title, content = EXCLUDED.content, comment_count = EXCLUDED.comment_count, like_count = EXCLUDED.like_count, view_count = EXCLUDED.view_count, updated_at = EXCLUDED.updated_at, published_at = EXCLUDED.published_at, deleted_at = NULL;

CREATE TEMP TABLE import_revisions (id text, post_id text, editor_id text, community_id text, type text, title text, content text, created_at timestamptz) ON COMMIT DROP;
\\copy import_revisions FROM '{(bundle_dir / 'revisions.csv').as_posix()}' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
INSERT INTO post_revisions (id, post_id, editor_id, community_id, type, title, content, created_at)
SELECT id, post_id, editor_id, community_id, type, title, content, created_at FROM import_revisions
ON CONFLICT (id) DO UPDATE SET community_id = EXCLUDED.community_id, type = EXCLUDED.type, title = EXCLUDED.title, content = EXCLUDED.content, created_at = EXCLUDED.created_at;

CREATE TEMP TABLE import_media (id text, owner_id text, object_key text, original_name text, mime_type text, width integer, height integer, size bigint, sha256 text, status text, created_at timestamptz, updated_at timestamptz, completed_at timestamptz) ON COMMIT DROP;
\\copy import_media FROM '{(bundle_dir / 'media_assets.csv').as_posix()}' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
INSERT INTO media_assets (id, owner_id, object_key, original_name, mime_type, width, height, size, sha256, status, created_at, updated_at, completed_at, deleted_at)
SELECT id, owner_id, object_key, original_name, mime_type, width, height, size, sha256, status, created_at, updated_at, completed_at, NULL FROM import_media
ON CONFLICT (id) DO UPDATE SET owner_id = EXCLUDED.owner_id, object_key = EXCLUDED.object_key, original_name = EXCLUDED.original_name, mime_type = EXCLUDED.mime_type, width = EXCLUDED.width, height = EXCLUDED.height, size = EXCLUDED.size, sha256 = EXCLUDED.sha256, status = EXCLUDED.status, updated_at = EXCLUDED.updated_at, completed_at = EXCLUDED.completed_at, deleted_at = NULL;

CREATE TEMP TABLE import_post_media (post_id text, media_id text, sort_order integer, created_at timestamptz) ON COMMIT DROP;
\\copy import_post_media FROM '{(bundle_dir / 'post_media.csv').as_posix()}' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
DELETE FROM post_media WHERE post_id IN (SELECT id FROM import_posts);
INSERT INTO post_media (post_id, media_id, sort_order, created_at)
SELECT post_id, media_id, sort_order, created_at FROM import_post_media;

UPDATE communities c SET post_count = (SELECT count(*) FROM posts p WHERE p.community_id = c.id AND p.deleted_at IS NULL), updated_at = now()
WHERE c.id IN (SELECT id FROM import_communities);
COMMIT;
"""
    command = ["psql", "-v", "ON_ERROR_STOP=1", "-P", "pager=off", db_url]
    subprocess.run(command, input=sql, text=True, check=True)


def main() -> int:
    args = parse_args()
    if args.page_size < 1 or args.page_size > 100:
        raise SystemExit("--page-size 必须在 1 到 100 之间")
    work_dir = args.output_dir
    try:
        _, stats = build_bundle(args)
        if not args.skip_db:
            psql_import(work_dir, args.db_url)
        print(json.dumps(stats, ensure_ascii=False))
        return 0
    finally:
        if not args.keep_workdir and args.skip_db is False:
            # 数据库导入完成后保留 bundle 和媒体文件，便于核验与回滚，不自动删除远端文件。
            pass


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:  # noqa: BLE001 - CLI 需要给出可读错误并返回失败码
        print(f"导入失败: {error}", file=sys.stderr)
        raise SystemExit(1)
