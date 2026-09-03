"use client";

import { useEffect, useMemo, useState } from "react";
import { initials } from "../lib/format";

const avatarCache = new Map<string, string>();
const avatarTones = ["blue", "lilac", "mint", "peach"] as const;

const defaultAvatars = [
  "/default-avatar.webp",
  "/avatars/byj_avatar100219.webp",
  "/avatars/byj_avatar100692.webp",
  "/avatars/byj_avatar101249.webp",
  "/avatars/byj_avatar101253.webp",
  "/avatars/byj_avatar101586.webp",
  "/avatars/byj_avatar101735.webp",
  "/avatars/byj_avatar101927.webp",
  "/avatars/byj_avatar101936.webp",
  "/avatars/byj_avatar102.webp",
  "/avatars/byj_avatar102036.webp",
  "/avatars/byj_avatar102138.webp",
  "/avatars/byj_avatar102185.webp",
];

function getDeterministicAvatar(key: string): string {
  const hash = Array.from(key).reduce((sum, char) => sum + char.charCodeAt(0), 0);
  return defaultAvatars[hash % defaultAvatars.length];
}

export function UserAvatar({
  userId,
  name,
  url,
  size = "default",
  className = "",
}: {
  userId?: string;
  name: string;
  url?: string;
  size?: "small" | "default" | "large" | "header" | "profile";
  className?: string;
}) {
  const cacheKey = userId || name;
  const cachedUrl = cacheKey ? avatarCache.get(cacheKey) : undefined;
  const [imgFailed, setImgFailed] = useState(false);

  useEffect(() => {
    if (url && cacheKey) avatarCache.set(cacheKey, url);
    setImgFailed(false);
  }, [cacheKey, url]);

  const fallbackAvatar = useMemo(() => getDeterministicAvatar(cacheKey || "user"), [cacheKey]);
  const activeUrl = url || cachedUrl || fallbackAvatar;
  const tone = avatarTones[(Array.from(cacheKey).reduce((sum, char) => sum + char.charCodeAt(0), 0) || 0) % avatarTones.length];

  return (
    <span className={`avatar avatar-${size} avatar-${tone}${className ? ` ${className}` : ""}`}>
      {!imgFailed && activeUrl ? (
        <img
          src={activeUrl}
          alt={name}
          onError={() => setImgFailed(true)}
        />
      ) : (
        initials(name)
      )}
    </span>
  );
}

