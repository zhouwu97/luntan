import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";

export async function proxy(request: NextRequest) {
  const postId = request.nextUrl.pathname.slice("/post/".length);
  if (!postId) return NextResponse.next();

  try {
    // 预检直连运行时上游，避免用外部域名回环时经过 CDN 并读到旧版本响应。
    const apiOrigin = (process.env.API_PROXY_TARGET?.trim() || "http://127.0.0.1:8080").replace(/\/+$/, "");
    const apiUrl = new URL(`/api/v1/posts/${encodeURIComponent(decodeURIComponent(postId))}?include_details=1`, apiOrigin);
    const response = await fetch(apiUrl, { headers: { Accept: "application/json" }, cache: "no-store" });
    if (response.status === 404 || response.status === 410) {
      // Next 的 rewrite 会把目标页面重新标记为 200；透传页面内容并显式保留 404，
      // 错误页也从本机端口读取，不能沿生产域名再次经过公网代理。
      const localOrigin = `http://127.0.0.1:${process.env.PORT?.trim() || "3000"}`;
      const notFoundHeaders = new Headers(request.headers);
      notFoundHeaders.delete("host");
      const notFoundPage = await fetch(new URL("/post-not-found", localOrigin), {
        headers: notFoundHeaders,
        cache: "no-store",
      });
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
