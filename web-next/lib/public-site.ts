const trimSlash = (value: string) => value.replace(/\/+$/, "");

export const publicSiteOrigin = trimSlash(
  process.env.NEXT_PUBLIC_SITE_URL?.trim() || "https://shengbeijiang.com",
);

export function publicSiteUrl(path = "/"): string {
  return new URL(path, `${publicSiteOrigin}/`).toString();
}
