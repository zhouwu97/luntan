"use client";

import { useEffect, useState } from "react";
import { initials } from "../lib/format";

const avatarCache = new Map<string, string>();
const avatarTones = ["blue", "lilac", "mint", "peach"] as const;
const DEFAULT_AVATAR_URL = "/avatars/byj_avatar102.webp";
const avatarPixels = { small: 30, default: 40, large: 46, header: 38, profile: 76 } as const;

function normalizeAvatarUrl(value?: string): string | undefined {
  const clean = value?.trim();
  if (!clean) return undefined;
  const path = clean.replace(/^https?:\/\/[^/]+/i, "").split("?", 1)[0];
  // 旧默认头像文件体积过大且内容重复，统一指向唯一的小尺寸资源。
  if (path === "/default-avatar.webp" || /^\/avatars\/byj_avatar\d+\.webp$/i.test(path)) {
    return DEFAULT_AVATAR_URL;
  }
  return clean;
}

export function UserAvatar({
  userId,
  name,
  url,
  size = "default",
  className = "",
  loading = "lazy",
}: {
  userId?: string;
  name: string;
  url?: string;
  size?: "small" | "default" | "large" | "header" | "profile";
  className?: string;
  loading?: "eager" | "lazy";
}) {
  const cacheKey = userId || name;
  const cachedUrl = cacheKey ? avatarCache.get(cacheKey) : undefined;
  const normalizedUrl = normalizeAvatarUrl(url);
  const [imgFailed, setImgFailed] = useState(false);

  useEffect(() => {
    if (normalizedUrl && cacheKey) avatarCache.set(cacheKey, normalizedUrl);
    setImgFailed(false);
  }, [cacheKey, normalizedUrl]);

  const fallbackAvatar = DEFAULT_AVATAR_URL;
  const activeUrl = normalizedUrl || cachedUrl || fallbackAvatar;
  const tone = avatarTones[(Array.from(cacheKey).reduce((sum, char) => sum + char.charCodeAt(0), 0) || 0) % avatarTones.length];

  return (
    <span className={`avatar avatar-${size} avatar-${tone}${className ? ` ${className}` : ""}`}>
      {!imgFailed && activeUrl ? (
        <img
          src={activeUrl}
          alt={name}
          width={avatarPixels[size]}
          height={avatarPixels[size]}
          loading={loading}
          onError={() => setImgFailed(true)}
        />
      ) : (
        initials(name)
      )}
    </span>
  );
}
