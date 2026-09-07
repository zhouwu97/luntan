import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";

function apiOrigin(): string {
  const configured =
    process.env.API_PROXY_TARGET?.trim() ||
    process.env.NEXT_PUBLIC_API_BASE_URL?.trim() ||
    (process.env.NODE_ENV === "development" ? "http://127.0.0.1:8080" : "https://shengbeijiang.com");
  return configured.replace(/\/+$/, "").replace(/\/api\/v1$/, "");
}

export async function proxy(request: NextRequest) {
  const postId = request.nextUrl.pathname.slice("/post/".length);
  if (!postId) return NextResponse.next();

  try {
    const response = await fetch(
      `${apiOrigin()}/api/v1/posts/${encodeURIComponent(decodeURIComponent(postId))}?include_details=1`,
      { headers: { Accept: "application/json" }, cache: "no-store" },
    );
    if (response.status === 404 || response.status === 410) {
      const notFoundUrl = request.nextUrl.clone();
      notFoundUrl.pathname = "/post-not-found";
      return NextResponse.rewrite(notFoundUrl, { status: 404 });
    }
  } catch {
    // 上游暂时不可用时继续进入页面壳，由客户端重试，不能误判内容已删除。
  }
  return NextResponse.next();
}

export const config = {
  matcher: "/post/:id",
};
