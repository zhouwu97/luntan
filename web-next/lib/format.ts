export function compactCount(value: number): string {
  if (value >= 10000) return `${(value / 10000).toFixed(value >= 100000 ? 0 : 1)}万`;
  if (value >= 1000) return `${(value / 1000).toFixed(value >= 10000 ? 0 : 1)}k`;
  return String(value);
}

export function relativeTime(value?: string): string {
  if (!value) return "刚刚";
  const timestamp = new Date(value).getTime();
  if (!Number.isFinite(timestamp)) return "刚刚";
  const minutes = Math.max(0, Math.floor((Date.now() - timestamp) / 60000));
  if (minutes < 1) return "刚刚";
  if (minutes < 60) return `${minutes} 分钟前`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours} 小时前`;
  const days = Math.floor(hours / 24);
  if (days < 30) return `${days} 天前`;
  return new Intl.DateTimeFormat("zh-CN", { month: "numeric", day: "numeric" }).format(
    new Date(timestamp),
  );
}

export function initials(value: string): string {
  const chars = Array.from(value.trim());
  return chars[0] || "友";
}

export function formatError(error: unknown, fallback = "操作失败，请稍后重试"): string {
  if (error instanceof ApiError) {
    switch (error.code) {
      case "MEDIA_UNSUPPORTED_TYPE":
        return "仅支持 JPG、PNG、WebP 图片";
      case "MEDIA_TOO_LARGE":
        return "图片文件过大，请压缩后再上传";
      case "MEDIA_TOO_MANY_PIXELS":
        return "图片像素过大，请压缩后再上传";
      case "MEDIA_CHECKSUM_MISMATCH":
      case "MEDIA_UPLOAD_MISMATCH":
        return "图片校验失败，请重新选择后上传";
      case "MEDIA_NOT_READY":
        return "图片还没有上传完成，请稍后重试";
      case "MEDIA_NOT_OWNED":
        return "只能使用自己上传的图片";
      case "MEDIA_NOT_FOUND":
        return "图片已失效，请重新选择";
      case "STORAGE_UNAVAILABLE":
        return "媒体存储暂时不可用，请稍后再试";
      default:
        break;
    }
  }
  return error instanceof Error && error.message ? error.message : fallback;
}
import { ApiError } from "./api/client";
