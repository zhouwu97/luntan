import { NextRequest, NextResponse } from "next/server";

type RouteContext = { params: Promise<{ path: string[] }> };

const targetOrigin = (process.env.API_PROXY_TARGET?.trim() || "https://shengbeijiang.com")
  .replace(/\/+$/, "")
  .replace(/\/api\/v1$/, "");

const passthroughHeaders = [
  "content-type",
  "cache-control",
  "etag",
  "last-modified",
  "content-range",
  "accept-ranges",
  "content-disposition",
];

async function proxy(request: NextRequest, context: RouteContext) {
  const { path } = await context.params;
  const encodedPath = path.map((part) => encodeURIComponent(part)).join("/");
  const target = new URL(`/imported-media/${encodedPath}${request.nextUrl.search}`, targetOrigin);
  const headers = new Headers(request.headers);
  headers.delete("host");
  headers.delete("content-length");
  headers.set("origin", process.env.API_PROXY_ORIGIN?.trim() || "https://shengbeijiang.com");

  try {
    let response: Response;
    try {
      response = await fetch(target, {
        method: request.method,
        headers,
        body: request.method === "GET" || request.method === "HEAD" ? undefined : await request.arrayBuffer(),
        redirect: "manual",
        cache: "no-store",
        signal: AbortSignal.timeout(8000),
      });
    } catch (primaryError: unknown) {
      const errorStr = String((primaryError as { cause?: unknown })?.cause || primaryError);
      const isConnRefused =
        errorStr.includes("ECONNREFUSED") ||
        (primaryError as { code?: string })?.code === "ECONNREFUSED" ||
        (primaryError as { cause?: { code?: string } })?.cause?.code === "ECONNREFUSED";

      if (isConnRefused && targetOrigin !== "https://shengbeijiang.com") {
        const fallbackTarget = new URL(`/imported-media/${encodedPath}${request.nextUrl.search}`, "https://shengbeijiang.com");
        const fallbackHeaders = new Headers(headers);
        fallbackHeaders.set("origin", "https://shengbeijiang.com");
        response = await fetch(fallbackTarget, {
          method: request.method,
          headers: fallbackHeaders,
          body: request.method === "GET" || request.method === "HEAD" ? undefined : await request.arrayBuffer(),
          redirect: "manual",
          cache: "no-store",
          signal: AbortSignal.timeout(8000),
        });
      } else {
        throw primaryError;
      }
    }

    const responseHeaders = new Headers();
    for (const name of passthroughHeaders) {
      const value = response.headers.get(name);
      if (value) responseHeaders.set(name, value);
    }
    return new NextResponse(response.body, { status: response.status, headers: responseHeaders });
  } catch (error) {
    console.error("[imported-media-proxy]", { path: request.nextUrl.pathname, error });
    return NextResponse.json({ error: { code: "UPSTREAM_UNAVAILABLE", message: "媒体服务不可用" } }, { status: 502 });
  }
}

export const GET = proxy;
export const HEAD = proxy;

