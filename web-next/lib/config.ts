const trimSlash = (value: string) => value.replace(/\/+$/, "");

export const appBasePath = trimSlash(process.env.NEXT_PUBLIC_APP_BASE_PATH?.trim() || "");

const configuredApiBase = process.env.NEXT_PUBLIC_API_BASE_URL?.trim();

export const apiRoot = configuredApiBase
  ? `${trimSlash(configuredApiBase).replace(/\/api\/v1$/, "")}/api/v1`
  : `${appBasePath}/api/v1`;

export const apiOrigin = apiRoot.startsWith("http")
  ? apiRoot.replace(/\/api\/v1$/, "")
  : "";

function normalizeHttpUrl(value: string): string {
  if (/^http:\/\/shengbeijiang\.com\//i.test(value)) {
    return value.replace(/^http:/i, "https:");
  }
  return value;
}

export function resolveAssetUrl(value?: string): string | undefined {
  if (!value) return undefined;
  const clean = value.trim();
  if (!clean) return undefined;
  if (/^https?:\/\//i.test(clean)) return normalizeHttpUrl(clean);
  if (appBasePath && (clean === appBasePath || clean.startsWith(`${appBasePath}/`))) return clean;
  if (clean.startsWith("/api/v1/") && apiOrigin) {
    return `${apiOrigin}${clean}`;
  }
  if (clean.startsWith("/")) return `${appBasePath}${clean}`;
  return `${appBasePath}/${clean}`;
}
