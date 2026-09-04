import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

export async function GET() {
  const webSha = process.env.NEXT_PUBLIC_GIT_SHA || "dev";
  const buildTime = process.env.NEXT_PUBLIC_BUILD_TIME || new Date().toISOString();

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
    web: {
      version: "0.1.0",
      commit: webSha,
      build_time: buildTime,
    },
    api: apiVersion,
  });
}
