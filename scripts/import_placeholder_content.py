#!/usr/bin/env python3
"""从杯友酱公开列表构建本站帖子、评论和配图导入包，并写入论坛 PostgreSQL。

脚本只保存随机化的本地展示用户名，不保存源站作者昵称或头像。
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
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SOURCE_API = "https://beiyoujiang.com/api/post/getAllPost"
SOURCE_COMMENTS_API = "https://beiyoujiang.com/api/comment/getPostComment"
SOURCE_IMAGE_BASE = "https://beiyoujiang.com/PostImg/"
# 当前部署通过正式 HTTPS 域名暴露媒体目录；可用 --public-media-base 覆盖。
PUBLIC_MEDIA_BASE = "https://shengbeijiang.com/imported-media"

# 用稳定哈希生成脱敏后的本地社区昵称。哈希只用于保持重复导入时
# 的用户名稳定，不会把源站昵称、头像或用户 ID 写入展示数据。
DISPLAY_NAME_PREFIXES = (
    "慢玩",
    "软萌",
    "夜猫",
    "温水",
    "清洗",
    "收纳",
    "开箱",
    "杯友",
    "橘子",
    "白桃",
)
DISPLAY_NAME_SUFFIXES = (
    "观察员",
    "研究员",
    "试用员",
    "记录本",
    "小分队",
    "后勤组",
    "玩家",
    "测评君",
    "汽水",
    "拿铁",
)

COMMUNITIES = {
    1: {
        "category_id": "category-digital",
        "category_name": "数码玩具",
        "category_slug": "digital",
        "community_id": "community-unboxing",
        "community_slug": "unboxing",
        "community_name": "大型拆箱",
        "description": "玩具开箱、结构拆解和真实使用体验。",
        "sort_order": 10,
    },
    2: {
        "category_id": "category-campus",
        "category_name": "交流讨论",
        "category_slug": "campus",
        "community_id": "community-campus",
        "community_slug": "campus",
        "community_name": "酱紫社区",
        "description": "真实测评、避坑求助和同好交流。",
        "sort_order": 11,
    },
    3: {
        "category_id": "category-life",
        "category_name": "日常分享",
        "category_slug": "life",
        "community_id": "community-daily",
        "community_slug": "daily",
        "community_name": "杂鱼日常",
        "description": "润滑、保养和日常使用记录。",
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


def post_json(api_url: str, body: dict[str, Any]) -> Any:
    payload = json.dumps(body).encode("utf-8")
    for attempt in range(6):
        request = urllib.request.Request(
            api_url,
            data=payload,
            headers={"Content-Type": "application/json", "User-Agent": "luntan-placeholder-import/1.0"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                value: Any = json.loads(response.read().decode("utf-8"))
            break
        except urllib.error.HTTPError as error:
            if error.code != 429 or attempt == 5:
                raise
            retry_after = error.headers.get("Retry-After")
            try:
                delay = max(2.0, float(retry_after or 0))
            except ValueError:
                delay = 5.0
            print(f"源站接口限流，{delay:g} 秒后重试（第 {attempt + 1} 次）", file=sys.stderr)
            time.sleep(delay)
    # 该接口在部分环境会把 JSON 再包成字符串。
    if isinstance(value, str):
        value = json.loads(value)
    return value


def fetch_posts(api_url: str, page_size: int) -> list[dict[str, Any]]:
    value = post_json(
        api_url,
        {"plate": None, "most": None, "userId": None, "page": 1, "pageSize": page_size},
    )
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
    # 用源作者 ID 做种子，只为保证重复导入稳定；用户名本身不包含源站用户名，
    # 也不再使用“占位用户”前缀，避免首页看起来像测试数据。
    digest = hashlib.sha256(f"placeholder-user:{author_id}".encode("utf-8")).hexdigest()
    prefix = DISPLAY_NAME_PREFIXES[int(digest[:2], 16) % len(DISPLAY_NAME_PREFIXES)]
    suffix = DISPLAY_NAME_SUFFIXES[int(digest[2:4], 16) % len(DISPLAY_NAME_SUFFIXES)]
    serial = int(digest[4:10], 16) % 10000
    return f"{prefix}{suffix}_{serial:04d}"


def fetch_post_comments(source_post_id: Any) -> list[dict[str, Any]]:
    """读取帖子评论树，只提取公开评论字段，不落源站账号资料。"""
    value = post_json(
        SOURCE_COMMENTS_API,
        {
            "postId": int(source_post_id) if str(source_post_id).isdigit() else source_post_id,
            "userId": None,
            "reply": False,
            "order": None,
            "orderType": "time",
        },
    )
    items = value.get("data", []) if isinstance(value, dict) else []
    if not isinstance(items, list):
        raise RuntimeError(f"源站评论接口返回格式异常: post={source_post_id}")
    return [item for item in items if isinstance(item, dict)]


def flatten_comment_tree(
    source_post_id: Any,
    raw: dict[str, Any],
    *,
    parent_source_id: str | None = None,
    root_source_id: str | None = None,
    parent_author_id: str | None = None,
    depth: int = 0,
    seen: set[str] | None = None,
) -> list[dict[str, Any]]:
    """把源站的 replies 数组摊平成数据库需要的 parent/root 关系。"""
    seen = seen if seen is not None else set()
    source_id = safe_source_id(raw.get("id"))
    if source_id in seen:
        return []
    seen.add(source_id)
    author = raw.get("author") if isinstance(raw.get("author"), dict) else {}
    source_author_id = safe_source_id(raw.get("authorId") or author.get("id"))
    explicit_parent = raw.get("parentId")
    parent_id = safe_source_id(explicit_parent) if explicit_parent else parent_source_id
    explicit_root = raw.get("rootId")
    root_id = safe_source_id(explicit_root) if explicit_root else root_source_id or source_id
    reply_to = raw.get("replyToUserId")
    if not reply_to and isinstance(raw.get("parentComment"), dict):
        parent_author = raw["parentComment"].get("author")
        if isinstance(parent_author, dict):
            reply_to = parent_author.get("id")
    if not reply_to:
        reply_to = parent_author_id
    current = {
        "source_id": source_id,
        "source_author_id": source_author_id,
        "parent_source_id": parent_id,
        "root_source_id": root_id,
        "reply_to_source_author_id": safe_source_id(reply_to) if reply_to else None,
        "content": clean_content(raw.get("content")),
        "like_count": int(raw.get("likeCount") or raw.get("likeNumber") or 0),
        "created_at": iso_time(raw.get("createdAt")),
        "depth": depth,
    }
    rows = [current]
    replies = raw.get("replies")
    if isinstance(replies, list):
        for child in replies:
            if isinstance(child, dict):
                rows.extend(
                    flatten_comment_tree(
                        source_post_id,
                        child,
                        parent_source_id=source_id,
                        root_source_id=root_id,
                        parent_author_id=source_author_id,
                        depth=depth + 1,
                        seen=seen,
                    )
                )
    return rows


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
    comment_rows: list[list[Any]] = []
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
                "社区随机展示账号",
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
        comment_items = fetch_post_comments(item.get("id"))
        # 源站评论接口有访问频控，导入时留出间隔，避免半批失败。
        time.sleep(0.75)
        seen_comments: set[str] = set()
        for raw_comment in comment_items:
            for comment in flatten_comment_tree(item.get("id"), raw_comment, seen=seen_comments):
                comment_author_id = safe_source_id(comment["source_author_id"])
                comment_user_id = f"user-import-{comment_author_id}"
                comment_time = comment["created_at"]
                if comment_user_id not in users:
                    users[comment_user_id] = [
                        comment_user_id,
                        placeholder_username(comment_author_id),
                        "active",
                        comment_time,
                        comment_time,
                    ]
                    profiles[comment_user_id] = [
                        comment_user_id,
                        placeholder_username(comment_author_id),
                        "",
                        "社区随机展示账号",
                        1,
                        0,
                        comment_time,
                        comment_time,
                        "new",
                    ]
                comment_id = f"comment-import-{source_post_id}-{comment['source_id']}"
                parent_id = comment.get("parent_source_id")
                root_id = comment.get("root_source_id") or comment["source_id"]
                parent_import_id = (
                    f"comment-import-{source_post_id}-{parent_id}" if parent_id else ""
                )
                root_import_id = f"comment-import-{source_post_id}-{root_id}"
                reply_to_author_id = comment.get("reply_to_source_author_id")
                reply_to_user_id = (
                    f"user-import-{reply_to_author_id}" if reply_to_author_id else ""
                )
                comment_rows.append(
                    [
                        comment_id,
                        post_id,
                        comment_user_id,
                        root_import_id,
                        parent_import_id,
                        reply_to_user_id,
                        comment["content"],
                        comment["like_count"],
                        0,
                        "published",
                        "normal",
                        comment_time,
                        comment_time,
                        comment_time,
                        comment["depth"],
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
    write_csv(
        args.output_dir / "comments.csv",
        [
            "id", "post_id", "author_id", "root_id", "parent_id", "reply_to_user_id",
            "content", "like_count", "reply_count", "publication_status", "moderation_status",
            "created_at", "updated_at", "published_at", "depth",
        ],
        comment_rows,
    )
    (args.output_dir / "manifest.json").write_text(
        json.dumps(
            {
                "source": args.api_url,
                "posts": len(post_rows),
                "users": len(users),
                "media": downloaded,
                "comments": len(comment_rows),
                "replies": sum(1 for row in comment_rows if row[4]),
                "generated_at": datetime.now(timezone.utc).isoformat(),
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    return args.output_dir, {
        "posts": len(post_rows),
        "users": len(users),
        "media": downloaded,
        "comments": len(comment_rows),
        "replies": sum(1 for row in comment_rows if row[4]),
    }


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

CREATE TEMP TABLE import_comments (id text, post_id text, author_id text, root_id text, parent_id text, reply_to_user_id text, content text, like_count bigint, reply_count bigint, publication_status text, moderation_status text, created_at timestamptz, updated_at timestamptz, published_at timestamptz, depth integer) ON COMMIT DROP;
\\copy import_comments FROM '{(bundle_dir / 'comments.csv').as_posix()}' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
-- 重导入同一批帖子时先清理旧评论及互动，避免源站评论减少后留下脏数据。
DELETE FROM comment_reactions WHERE comment_id IN (SELECT c.id FROM comments c JOIN import_posts p ON p.id = c.post_id);
DELETE FROM comment_idempotency_keys WHERE comment_id IN (SELECT c.id FROM comments c JOIN import_posts p ON p.id = c.post_id);
DELETE FROM comments WHERE post_id IN (SELECT id FROM import_posts) AND parent_id IS NOT NULL;
DELETE FROM comments WHERE post_id IN (SELECT id FROM import_posts);
-- 先写入一级评论，再按深度写入楼中楼，满足自引用外键约束。
DO $$
DECLARE
    current_depth integer := 0;
    max_depth integer := 0;
BEGIN
    SELECT COALESCE(MAX(depth), 0) INTO max_depth FROM import_comments;
    WHILE current_depth <= max_depth LOOP
        INSERT INTO comments (id, post_id, author_id, root_id, parent_id, reply_to_user_id, content, like_count, reply_count, publication_status, moderation_status, created_at, updated_at, published_at)
        SELECT id, post_id, author_id, root_id, NULLIF(parent_id, ''), NULLIF(reply_to_user_id, ''), content, like_count, reply_count, publication_status, moderation_status, created_at, updated_at, published_at
        FROM import_comments
        WHERE depth = current_depth;
        current_depth := current_depth + 1;
    END LOOP;
END $$;
UPDATE comments c
SET reply_count = (
    SELECT count(*) FROM comments child
    WHERE child.parent_id = c.id AND child.deleted_at IS NULL
), updated_at = now()
WHERE c.post_id IN (SELECT id FROM import_posts);
-- 含淘宝链接等关键词的导入内容会被 000026 的防灌水触发器置为待审核；
-- 种子数据视作已审核内容，这里恢复可见并关闭对应的 auto_rule 审核案例。
CREATE TEMP TABLE import_pending_cases (case_id text) ON COMMIT DROP;
INSERT INTO import_pending_cases (case_id)
SELECT moderation_case_id FROM posts
WHERE id IN (SELECT id FROM import_posts) AND moderation_case_id IS NOT NULL
UNION
SELECT moderation_case_id FROM comments
WHERE post_id IN (SELECT id FROM import_posts) AND moderation_case_id IS NOT NULL;
UPDATE posts
SET post_status = 'published', moderation_status = 'normal',
    moderation_case_id = NULL, visibility_reason = '', updated_at = now()
WHERE id IN (SELECT id FROM import_posts) AND moderation_status = 'pending';
UPDATE comments
SET moderation_status = 'normal', moderation_case_id = NULL,
    visibility_reason = '', updated_at = now()
WHERE post_id IN (SELECT id FROM import_posts) AND moderation_status = 'pending';
UPDATE moderation_cases
SET status = 'resolved', resolved_at = now()
WHERE status = 'open' AND id IN (SELECT case_id FROM import_pending_cases);
UPDATE posts p
SET comment_count = (
    SELECT count(*) FROM comments c
    WHERE c.post_id = p.id AND c.deleted_at IS NULL
      AND c.publication_status = 'published' AND c.moderation_status = 'normal'
), updated_at = now()
WHERE p.id IN (SELECT id FROM import_posts);

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
