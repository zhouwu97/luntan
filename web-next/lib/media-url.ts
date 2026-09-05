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
export function resolveMediaUrl(value?: string, variant: "thumb" | "feed" | "detail" | "original" = "detail"): string | undefined {
  if (!value) return undefined;
  const clean = value.trim();
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
  const order = preferred === "thumb"
    ? [[asset.thumbUrl, "thumb"], [asset.feedUrl, "feed"], [asset.detailUrl, "detail"]]
    : preferred === "feed"
      ? [[asset.feedUrl, "feed"], [asset.detailUrl, "detail"], [asset.thumbUrl, "thumb"]]
    : preferred === "original"
      ? [[asset.originalUrl, "original"], [asset.detailUrl, "detail"], [asset.feedUrl, "feed"], [asset.url, "original"], [asset.thumbUrl, "thumb"]]
      : [[asset.detailUrl, "detail"], [asset.originalUrl, "original"], [asset.feedUrl, "feed"], [asset.thumbUrl, "thumb"], [asset.url, "original"]];

  const values = order
    .map(([value, variant]) => resolveMediaUrl(value, variant as "thumb" | "feed" | "detail" | "original"))
    .filter((value): value is string => Boolean(value));
  return [...new Set(values)];
}
