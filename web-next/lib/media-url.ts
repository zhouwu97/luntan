import { apiOrigin, appBasePath, resolveAssetUrl } from "./config";
import type { MediaAsset } from "../types/forum";

function normalizeHttpUrl(value: string): string {
  if (/^http:\/\/shengbeijiang\.com\//i.test(value)) {
    return value.replace(/^http:/i, "https:");
  }
  return value;
}

function resolveApiPath(path: string): string {
  return apiOrigin ? `${apiOrigin}${path}` : `${appBasePath}${path}`;
}

/**
 * 统一解析后端媒体地址。
 * 本地开发时 imported-media 与 /api/v1/media-file 都走 Next 同源代理，
 * 生产环境若配置了 API 地址则使用后端源站，避免把 objectKey 当成静态文件。
 */
export function resolveMediaUrl(value?: string, variant: "source" | "thumb" | "feed" | "detail" | "original" = "detail"): string | undefined {
  if (!value) return undefined;
  let clean = value.trim();
  // 兼容异步处理完成前返回的旧源地址，只映射自有媒体 ID，不开放源文件访问。
  const legacy = clean.match(/^\/api\/v1\/media-file\/media\/[^/]+\/(media_[a-f0-9]+)$/i);
  if (legacy) clean = `/api/v1/media-file/${legacy[1]}/${variant}`;
  if (!clean) return undefined;
  if (/^data:/i.test(clean) || /^blob:/i.test(clean)) return clean;
  if (/^https?:\/\//i.test(clean)) return normalizeHttpUrl(clean);
  if (appBasePath && (clean === appBasePath || clean.startsWith(`${appBasePath}/`))) return clean;
  if (clean.startsWith("/imported-media/")) return `${appBasePath}${clean}`;
  if (clean.startsWith("/api/v1/")) return resolveApiPath(clean);
  if (/^media(?:[-_]|$)/i.test(clean)) {
    return resolveApiPath(`/api/v1/media-file/${encodeURIComponent(clean)}/${variant}`);
  }
  return resolveAssetUrl(clean);
}

export function mediaCandidates(asset: MediaAsset, preferred: "thumb" | "feed" | "detail" | "original" = "thumb"): string[] {
  if (asset.mimeType?.toLowerCase() === "image/gif") {
    // GIF 只有 source 变体保留完整动画帧，不能降级到不存在的静态变体。
    const fallbackSource = /^media(?:[-_]|$)/i.test(asset.id)
      ? resolveMediaUrl(asset.id, "source")
      : undefined;
    const sourceCandidates = [asset.sourceUrl, asset.url, asset.detailUrl, asset.feedUrl, asset.thumbUrl, asset.originalUrl, fallbackSource]
      .filter((value): value is string => Boolean(value && (value.includes("/source") || !value.includes("/api/v1/media-file/"))));
    return [...new Set(sourceCandidates)];
  }
  const order = preferred === "thumb"
    ? [[asset.thumbUrl, "thumb"], [asset.feedUrl, "feed"], [asset.detailUrl, "detail"], [asset.originalUrl, "original"], [asset.url, "detail"]]
    : preferred === "feed"
      ? [[asset.feedUrl, "feed"], [asset.detailUrl, "detail"], [asset.thumbUrl, "thumb"], [asset.originalUrl, "original"], [asset.url, "detail"]]
    : preferred === "original"
      ? [[asset.originalUrl, "original"], [asset.detailUrl, "detail"], [asset.feedUrl, "feed"], [asset.url, "original"], [asset.thumbUrl, "thumb"]]
      : [[asset.detailUrl, "detail"], [asset.originalUrl, "original"], [asset.feedUrl, "feed"], [asset.thumbUrl, "thumb"], [asset.url, "original"]];

  // 预览只在压缩版本之间降级，原图由用户主动加载；兼容旧数据多个字段共用同一地址。
  const hasPreview = Boolean(asset.thumbUrl || asset.feedUrl || asset.detailUrl);
  const values = order
    .filter(([value, variant]) => preferred === "original" || !hasPreview || (variant !== "original" && (value !== asset.originalUrl || value === asset.thumbUrl || value === asset.feedUrl || value === asset.detailUrl)))
    .map(([value, variant]) => resolveMediaUrl(value, variant as "thumb" | "feed" | "detail" | "original"))
    .filter((value): value is string => Boolean(value));
  return [...new Set(values)];
}
