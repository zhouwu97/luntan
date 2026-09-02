"use client";

import { useState } from "react";
import { Icon } from "./icons";
import { mediaCandidates } from "../lib/media-url";
import type { MediaAsset } from "../types/forum";

export function MediaImage({
  asset,
  sources,
  alt,
  loading = "lazy",
  className = "",
}: {
  asset?: MediaAsset;
  sources?: Array<string | undefined>;
  alt: string;
  loading?: "eager" | "lazy";
  className?: string;
}) {
  const candidates = asset
    ? mediaCandidates(asset)
    : [...new Set((sources || []).filter((source): source is string => Boolean(source)))];
  const [index, setIndex] = useState(0);
  const source = candidates[index];

  if (!source) {
    return <span className={`media-image-placeholder${className ? ` ${className}` : ""}`} role="img" aria-label={`${alt}加载失败`}><Icon name="image" size={24} /></span>;
  }

  return <img className={className} src={source} alt={alt} loading={loading} onError={() => setIndex((current) => current + 1)} />;
}

