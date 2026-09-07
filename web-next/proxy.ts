import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";

export async function proxy(request: NextRequest) {
  const postId = request.nextUrl.pathname.slice("/post/".length);
  if (!postId) return NextResponse.next();

  try {
    // 统一经过本站 API 入口，确保 Edge 预检与 Node SSR 使用同一运行时上游配置。
    const apiUrl = request.nextUrl.clone();
    apiUrl.pathname = `/api/v1/posts/${encodeURIComponent(decodeURIComponent(postId))}`;
    apiUrl.search = "?include_details=1";
    const response = await fetch(apiUrl, { headers: { Accept: "application/json" }, cache: "no-store" });
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
