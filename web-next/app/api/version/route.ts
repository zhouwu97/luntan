import { NextResponse } from "next/server";
import { webBuildInfo } from "../../../lib/build-info";

export const dynamic = "force-dynamic";

export async function GET() {
  const web = webBuildInfo();

  let apiVersion: Record<string, unknown> | null = null;
  const targetOrigin = (process.env.API_PROXY_TARGET?.trim() || "https://shengbeijiang.com")
    .replace(/\/+$/, "")
    .replace(/\/api\/v1$/, "");

  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 2000);
    const res = await fetch(`${targetOrigin}/version`, { signal: controller.signal, cache: "no-store" });
    clearTimeout(timer);
    if (res.ok) {
      apiVersion = (await res.json()) as Record<string, unknown>;
    }
  } catch {
    // API backend might be unreachable from node in local dev, ignore
  }

  return NextResponse.json({
    status: "ok",
    web,
    api: apiVersion,
  });
}
