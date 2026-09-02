import { NextRequest, NextResponse } from "next/server";

type RouteContext = { params: Promise<{ path: string[] }> };

const targetOrigin = (process.env.API_PROXY_TARGET?.trim() || "https://shengbeijiang.com")
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

  const response = await fetch(target, {
    method: request.method,
    headers,
    body,
    redirect: "manual",
    cache: "no-store",
  });

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
}

export const GET = proxy;
export const POST = proxy;
export const PUT = proxy;
export const PATCH = proxy;
export const DELETE = proxy;
