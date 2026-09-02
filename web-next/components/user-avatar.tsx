"use client";

import { useEffect, useMemo, useState } from "react";
import { initials } from "../lib/format";

const avatarCache = new Map<string, string>();
const avatarTones = ["blue", "lilac", "mint", "peach"] as const;

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
  const [failedUrl, setFailedUrl] = useState<string>();

  useEffect(() => {
    if (url && cacheKey) avatarCache.set(cacheKey, url);
    setFailedUrl(undefined);
  }, [cacheKey, url]);

  const imageUrl = useMemo(() => {
    const nextUrl = url || cachedUrl;
    return nextUrl && nextUrl !== failedUrl ? nextUrl : undefined;
  }, [cachedUrl, failedUrl, url]);
  const tone = avatarTones[(Array.from(cacheKey).reduce((sum, char) => sum + char.charCodeAt(0), 0) || 0) % avatarTones.length];

  return (
    <span className={`avatar avatar-${size} avatar-${tone}${className ? ` ${className}` : ""}`}>
      {imageUrl ? (
        <img src={imageUrl} alt="" onError={() => { setFailedUrl(imageUrl); if (cacheKey) avatarCache.delete(cacheKey); }} />
      ) : initials(name)}
    </span>
  );
}

