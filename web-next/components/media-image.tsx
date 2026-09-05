"use client";

import { useEffect, useState } from "react";
import { Icon } from "./icons";
import { mediaCandidates } from "../lib/media-url";
import type { MediaAsset } from "../types/forum";

export function MediaImage({
  asset,
  sources,
  alt,
  loading = "lazy",
  preferred = "thumb",
  fetchPriority = "auto",
  sizes,
  width,
  height,
  className = "",
}: {
  asset?: MediaAsset;
  sources?: Array<string | undefined>;
  alt: string;
  loading?: "eager" | "lazy";
  preferred?: "thumb" | "feed" | "detail" | "original";
  fetchPriority?: "high" | "low" | "auto";
  sizes?: string;
  width?: number;
  height?: number;
  className?: string;
}) {
  const candidates = asset
    ? mediaCandidates(asset, preferred)
    : [...new Set((sources || []).filter((source): source is string => Boolean(source)))];
  const [index, setIndex] = useState(0);
  const source = candidates[index];

  useEffect(() => {
    setIndex(0);
  }, [asset?.id, asset?.url, preferred]);

  if (!source) {
    return <span className={`media-image-placeholder${className ? ` ${className}` : ""}`} role="img" aria-label={`${alt}加载失败`}><Icon name="image" size={24} /></span>;
  }

  return <img className={className} src={source} alt={alt} loading={loading} fetchPriority={fetchPriority} decoding="async" sizes={sizes} width={width} height={height} onError={() => setIndex((current) => current + 1)} />;
}
