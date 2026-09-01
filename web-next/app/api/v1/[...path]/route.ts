import { NextRequest, NextResponse } from "next/server";

type RouteContext = { params: Promise<{ path: string[] }> };

const targetOrigin = (process.env.API_PROXY_TARGET?.trim() || "https://shengbeijiang.com").replace(/\/+$/, "").replace(/\/api\/v1$/, "");

async function proxy(request: NextRequest, context: RouteContext) {
  const { path } = await context.params;
  const target = new URL(`/api/v1/${path.map((part) => encodeURIComponent(part)).join("/")}${request.nextUrl.search}`, targetOrigin);
  const headers = new Headers(request.headers);
  headers.delete("host");
  headers.set("origin", process.env.API_PROXY_ORIGIN?.trim() || "https://shengbeijiang.com");
  const body = request.method === "GET" || request.method === "HEAD" ? undefined : await request.arrayBuffer();
  const response = await fetch(target, { method: request.method, headers, body, redirect: "manual", cache: "no-store" });
  const responseHeaders = new Headers();
  response.headers.forEach((value, key) => {
    if (!["content-encoding", "content-length", "transfer-encoding", "connection"].includes(key)) responseHeaders.set(key, value);
  });
  const setCookie = response.headers.getSetCookie?.();
  if (setCookie?.length) responseHeaders.delete("set-cookie");
  const output = new NextResponse(response.body, { status: response.status, headers: responseHeaders });
  if (setCookie?.length) setCookie.forEach((cookie) => output.headers.append("set-cookie", cookie));
  return output;
}

export const GET = proxy;
export const POST = proxy;
export const PUT = proxy;
export const PATCH = proxy;
export const DELETE = proxy;
