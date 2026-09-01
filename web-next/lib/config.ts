const trimSlash = (value: string) => value.replace(/\/+$/, "");

export const appBasePath = trimSlash(process.env.NEXT_PUBLIC_APP_BASE_PATH?.trim() || "");

const configuredApiBase = process.env.NEXT_PUBLIC_API_BASE_URL?.trim();

export const apiRoot = configuredApiBase
  ? `${trimSlash(configuredApiBase).replace(/\/api\/v1$/, "")}/api/v1`
  : `${appBasePath}/api/v1`;

export function resolveAssetUrl(value?: string): string | undefined {
  if (!value) return undefined;
  if (/^https?:\/\//i.test(value)) return value;
  if (apiRoot.startsWith("http")) {
    return `${apiRoot.replace(/\/api\/v1$/, "")}${value.startsWith("/") ? value : `/${value}`}`;
  }
  if (value.startsWith("/")) {
    return `${appBasePath}${value}`;
  }
  return `${appBasePath}/${value}`;
}
