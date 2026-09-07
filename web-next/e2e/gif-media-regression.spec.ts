import { expect, test, type Page } from "@playwright/test";
import { mockApiFallbacks } from "./mock-api";

const gifBytes = Buffer.from("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7", "base64");

async function mockRegisteredSession(page: Page) {
  await page.route("**/api/v1/auth/refresh", (route) => route.fulfill({ json: { access_token: "gif-fixture-token" } }));
  await page.route("**/api/v1/me", (route) => route.fulfill({ json: {
    id: "gif-user",
    username: "gif-user",
    nickname: "GIF 测试用户",
    account_type: "registered",
    capabilities: { can_publish: true, can_comment: true, can_upload_media: true },
  } }));
}

function postFixture(id: string, mediaId?: string) {
  return {
    id,
    title: "GIF 媒体回归帖子",
    content: "验证 GIF 不进入静态图片链路。",
    type: "normal",
    author: { id: "gif-user", nickname: "GIF 测试用户" },
    community: { id: "community-gif", name: "媒体测试板块" },
    created_at: new Date().toISOString(),
    viewer_state: { has_liked: false, has_bookmarked: false },
    media: mediaId ? [{
      id: mediaId,
      type: "image",
      mime_type: "image/gif",
      url: `/api/v1/media-file/${mediaId}/source`,
      thumb: { url: `/api/v1/media-file/${mediaId}/source` },
      feed: { url: `/api/v1/media-file/${mediaId}/source` },
      detail: { url: `/api/v1/media-file/${mediaId}/source` },
      original: { url: `/api/v1/media-file/${mediaId}/source` },
      width: 1,
      height: 1,
    }] : [],
  };
}

test.describe("GIF 媒体 Web 回归", () => {
  test("GIF 发帖保留原始字节，并且详情只请求 source 变体", async ({ page }) => {
    await mockApiFallbacks(page);
    await mockRegisteredSession(page);
    await page.route("**/api/v1/communities*", (route) => route.fulfill({ json: {
      items: [{ id: "community-gif", name: "媒体测试板块", can_publish: true, can_upload_media: true }],
    } }));

    let uploadPayload: Record<string, unknown> | null = null;
    let uploadedBytes = new Uint8Array();
    let createdPayload: Record<string, unknown> | null = null;
    const mediaRequests: string[] = [];
    page.on("request", (request) => {
      if (request.url().includes("/api/v1/media-file/")) mediaRequests.push(request.url());
    });
    await page.route("**/api/v1/media/upload-token", async (route) => {
      uploadPayload = route.request().postDataJSON() as Record<string, unknown>;
      await route.fulfill({ status: 201, json: { media_id: "media-gif-post", upload_url: "/upload/media-gif-post", upload_method: "PUT" } });
    });
    await page.route("**/upload/media-gif-post", async (route) => {
      uploadedBytes = new Uint8Array(route.request().postDataBuffer() ?? new Uint8Array());
      await route.fulfill({ status: 200 });
    });
    await page.route("**/api/v1/media/media-gif-post/complete", (route) => route.fulfill({ json: { status: "ready" } }));
    await page.route("**/api/v1/posts", async (route) => {
      if (route.request().method() !== "POST") return route.fallback();
      createdPayload = route.request().postDataJSON() as Record<string, unknown>;
      await route.fulfill({ status: 201, json: { id: "post-gif" } });
    });
    await page.route("**/api/v1/posts/post-gif*", (route) => route.fulfill({ json: postFixture("post-gif", "media-gif-post") }));
    await page.route("**/api/v1/media-file/media-gif-post/source", (route) => route.fulfill({ contentType: "image/gif", body: gifBytes }));

    await page.goto("/publish");
    await page.getByPlaceholder("给这次分享起个标题").fill("GIF 发布测试");
    await page.getByPlaceholder("说说你的真实体验、问题或发现…").fill("保留动画帧的原始 GIF");
    await page.locator('input[type="file"]').setInputFiles({ name: "animated.gif", mimeType: "image/gif", buffer: gifBytes });
    await page.locator(".publish-submit").click();

    await expect(page).toHaveURL(/\/post\/post-gif/);
    await expect.poll(() => uploadPayload?.mime_type).toBe("image/gif");
    expect(Buffer.from(uploadedBytes).equals(gifBytes)).toBeTruthy();
    expect(createdPayload).toMatchObject({ type: "normal", media_ids: ["media-gif-post"] });
    await expect.poll(() => mediaRequests.some((url) => url.endsWith("/source"))).toBe(true);
    expect(mediaRequests.some((url) => /\/(detail|feed|thumb)(?:\/|$)/.test(url))).toBe(false);
  });

  test("GIF 评论沿用同一上传逻辑，并在评论区只使用 source 变体", async ({ page }) => {
    await mockApiFallbacks(page);
    await mockRegisteredSession(page);
    let commentPayload: Record<string, unknown> | null = null;
    let uploadPayload: Record<string, unknown> | null = null;
    let uploadedBytes = new Uint8Array();
    const mediaRequests: string[] = [];
    page.on("request", (request) => {
      if (request.url().includes("/api/v1/media-file/")) mediaRequests.push(request.url());
    });
    await page.route("**/api/v1/posts/post-gif-comment*", (route) => route.fulfill({ json: postFixture("post-gif-comment") }));
    await page.route("**/api/v1/posts/post-gif-comment/comments?*", (route) => route.fulfill({ json: { items: [], total: 0, has_more: false } }));
    await page.route("**/api/v1/media/upload-token", (route) => {
      uploadPayload = route.request().postDataJSON() as Record<string, unknown>;
      return route.fulfill({ status: 201, json: { media_id: "media-gif-comment", upload_url: "/upload/media-gif-comment", upload_method: "PUT" } });
    });
    await page.route("**/upload/media-gif-comment", (route) => {
      uploadedBytes = new Uint8Array(route.request().postDataBuffer() ?? new Uint8Array());
      return route.fulfill({ status: 200 });
    });
    await page.route("**/api/v1/media/media-gif-comment/complete", (route) => route.fulfill({ json: { status: "ready" } }));
    await page.route("**/api/v1/posts/post-gif-comment/comments", async (route) => {
      commentPayload = route.request().postDataJSON() as Record<string, unknown>;
      await route.fulfill({ status: 201, json: {
        id: "comment-gif",
        post_id: "post-gif-comment",
        content: "评论 GIF",
        author: { id: "gif-user", nickname: "GIF 测试用户" },
        created_at: new Date().toISOString(),
        viewer_state: {},
        media: postFixture("ignored", "media-gif-comment").media,
      } });
    });
    await page.route("**/api/v1/media-file/media-gif-comment/source", (route) => route.fulfill({ contentType: "image/gif", body: gifBytes }));

    await page.goto("/post/post-gif-comment");
    const desktopComposer = page.getByPlaceholder("写下你的评价、拆箱感受或回复…");
    const mobileComposer = page.getByPlaceholder("友善地回复一句…");
    await expect.poll(async () => (await desktopComposer.isVisible()) || (await mobileComposer.isVisible())).toBe(true);
    if (await desktopComposer.isVisible()) {
      await desktopComposer.fill("评论 GIF");
      await page.locator(".comment-composer input[type=file]").setInputFiles({ name: "reply.gif", mimeType: "image/gif", buffer: gifBytes });
      await page.getByRole("button", { name: "发布回复" }).click();
    } else {
      await mobileComposer.fill("评论 GIF");
      await page.locator(".mobile-comment-composer input[type=file]").setInputFiles({ name: "reply.gif", mimeType: "image/gif", buffer: gifBytes });
      await page.getByRole("button", { name: "发送", exact: true }).click();
    }

    await expect.poll(() => commentPayload?.media_ids).toEqual(["media-gif-comment"]);
    await expect.poll(() => uploadPayload?.mime_type).toBe("image/gif");
    expect(Buffer.from(uploadedBytes).equals(gifBytes)).toBeTruthy();
    await expect.poll(() => mediaRequests.some((url) => url.endsWith("/source"))).toBe(true);
    expect(mediaRequests.some((url) => /\/(detail|feed|thumb)(?:\/|$)/.test(url))).toBe(false);
  });
});
