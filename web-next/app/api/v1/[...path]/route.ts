import { NextRequest, NextResponse } from "next/server";

type RouteContext = { params: Promise<{ path: string[] }> };

const defaultTarget = process.env.NODE_ENV === "development" ? "http://127.0.0.1:8080" : "https://shengbeijiang.com";
const targetOrigin = (process.env.API_PROXY_TARGET?.trim() || defaultTarget)
  .replace(/\/+$/, "")
  .replace(/\/api\/v1$/, "");

function browserAuthCookiePath(request: NextRequest): string {
  const marker = "/api/v1/";
  const index = request.nextUrl.pathname.indexOf(marker);
  const prefix = index >= 0 ? request.nextUrl.pathname.slice(0, index) : "";
  return `${prefix}/api/v1/auth`.replace(/\/+/g, "/");
}

function rewriteAuthCookiePath(cookie: string, request: NextRequest): string {
  const path = browserAuthCookiePath(request);
  if (/;\s*Path=\/api\/v1\/auth(?=;|$)/i.test(cookie)) {
    return cookie.replace(/;\s*Path=\/api\/v1\/auth(?=;|$)/i, `; Path=${path}`);
  }
  return cookie;
}

async function proxy(request: NextRequest, context: RouteContext) {
  const { path } = await context.params;
  const encodedPath = path.map((part) => encodeURIComponent(part)).join("/");
  const target = new URL(`/api/v1/${encodedPath}${request.nextUrl.search}`, targetOrigin);
  const headers = new Headers(request.headers);
  headers.delete("host");
  headers.set("origin", process.env.API_PROXY_ORIGIN?.trim() || "https://shengbeijiang.com");

  const body = request.method === "GET" || request.method === "HEAD"
    ? undefined
    : await request.arrayBuffer();

  try {
    let response: Response;
    try {
      response = await fetch(target, {
        method: request.method,
        headers,
        body,
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
        const fallbackTarget = new URL(`/api/v1/${encodedPath}${request.nextUrl.search}`, "https://shengbeijiang.com");
        const fallbackHeaders = new Headers(headers);
        fallbackHeaders.set("origin", "https://shengbeijiang.com");
        response = await fetch(fallbackTarget, {
          method: request.method,
          headers: fallbackHeaders,
          body,
          redirect: "manual",
          cache: "no-store",
          signal: AbortSignal.timeout(8000),
        });
      } else {
        throw primaryError;
      }
    }

    const responseHeaders = new Headers();
    response.headers.forEach((value, key) => {
      if (!["content-encoding", "content-length", "transfer-encoding", "connection"].includes(key)) {
        responseHeaders.set(key, value);
      }
    });

    const setCookie = response.headers.getSetCookie?.();
    if (setCookie?.length) responseHeaders.delete("set-cookie");

    const output = new NextResponse(response.body, {
      status: response.status,
      headers: responseHeaders,
    });

    if (setCookie?.length) {
      setCookie.forEach((cookie) => {
        output.headers.append("set-cookie", rewriteAuthCookiePath(cookie, request));
      });
    }

    return output;
  } catch (error) {
    console.error("[api-proxy]", {
      path: request.nextUrl.pathname,
      error,
    });

    return NextResponse.json(
      {
        error: {
          code: "UPSTREAM_UNAVAILABLE",
          message: "后端服务暂时不可用",
        },
      },
      { status: 502 },
    );
  }
}

export const GET = proxy;
export const POST = proxy;
export const PUT = proxy;
export const PATCH = proxy;
export const DELETE = proxy;
