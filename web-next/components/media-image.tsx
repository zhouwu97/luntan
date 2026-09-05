"use client";

import { useEffect, useState } from "react";
import { Icon } from "./icons";
import { mediaCandidates, resolveMediaUrl } from "../lib/media-url";
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
  const [detailReady, setDetailReady] = useState(false);
  const [detailFailed, setDetailFailed] = useState(false);
  const source = candidates[index];
  const detailSource = asset && (preferred === "thumb" || preferred === "feed")
    ? resolveMediaUrl(asset.detailUrl, "detail")
    : undefined;
  const showProgressiveDetail = Boolean(detailSource && source && index === 0 && detailSource !== source && !detailFailed);
  const srcSet = asset && index === 0
    ? [
        [asset.thumbUrl, "640w", "thumb"],
        [asset.feedUrl, "960w", "feed"],
        [asset.detailUrl, "1440w", "detail"],
      ].map(([value, widthHint, variant]) => {
        const resolved = resolveMediaUrl(value || undefined, variant as "thumb" | "feed" | "detail");
        return resolved ? `${resolved} ${widthHint}` : "";
      }).filter(Boolean).join(", ") || undefined
    : undefined;

  useEffect(() => {
    setIndex(0);
    setDetailReady(false);
    setDetailFailed(false);
  }, [asset?.id, asset?.url, preferred]);

  if (!source) {
    return <span className={`media-image-placeholder${className ? ` ${className}` : ""}`} role="img" aria-label={`${alt}加载失败`}><Icon name="image" size={24} /></span>;
  }

  if (showProgressiveDetail) {
    return (
      <span className={`media-image-progressive${className ? ` ${className}` : ""}`}>
        <img
          className="media-image-progressive-layer"
          src={source}
          srcSet={srcSet}
          alt={alt}
          loading={loading}
          fetchPriority={fetchPriority}
          decoding="async"
          sizes={sizes}
          width={width}
          height={height}
          onError={() => setIndex((current) => current + 1)}
        />
        <img
          className={`media-image-progressive-layer media-image-progressive-detail${detailReady ? " is-ready" : ""}`}
          src={detailSource}
          alt=""
          aria-hidden="true"
          loading={loading}
          fetchPriority={loading === "eager" ? "high" : "auto"}
          decoding="async"
          sizes={sizes}
          width={width}
          height={height}
          onLoad={() => setDetailReady(true)}
          onError={() => setDetailFailed(true)}
        />
      </span>
    );
  }

  return <img className={className} src={source} srcSet={srcSet} alt={alt} loading={loading} fetchPriority={fetchPriority} decoding="async" sizes={sizes} width={width} height={height} onError={() => setIndex((current) => current + 1)} />;
}
