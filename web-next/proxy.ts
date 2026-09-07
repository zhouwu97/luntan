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
      // Next 的 rewrite 会把目标页面重新标记为 200；透传页面内容并显式保留 404，
      // 让浏览器、搜索引擎和外部链接检查都得到一致的真实状态码。
      const notFoundPage = await fetch(notFoundUrl, { headers: request.headers, cache: "no-store" });
      const headers = new Headers(notFoundPage.headers);
      headers.delete("content-length");
      return new NextResponse(notFoundPage.body, { status: 404, headers });
    }
  } catch {
    // 上游暂时不可用时继续进入页面壳，由客户端重试，不能误判内容已删除。
  }
  return NextResponse.next();
}

export const config = {
  matcher: "/post/:id",
};
