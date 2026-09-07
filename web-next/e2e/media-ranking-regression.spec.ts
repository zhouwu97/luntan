import { test, expect } from "@playwright/test";
import { mockApiFallbacks } from "./mock-api";
import { readFileSync } from "node:fs";
import path from "node:path";

test.beforeEach(async ({ page }) => { await mockApiFallbacks(page); });

test("新评论的旧源地址转换为网关，异步生成后自动显示并可打开大图", async ({ page }) => {
  const photo = readFileSync(path.resolve("../assets/images/store/badge.jpg"));
  const post = { id: "post-media-retry", title: "新上传图片", content: "图片处理等待测试", author: { id: "author", nickname: "作者" }, community: { id: "campus", name: "校园" }, comment_count: 1, created_at: new Date().toISOString() };
  await page.route("**/api/v1/posts/post-media-retry?*", (route) => route.fulfill({ json: post }));
  await page.route("**/api/v1/posts/post-media-retry/comments*", (route) => route.fulfill({ json: { items: [{ id: "comment-image", post_id: post.id, content: "我自己上传的图片", author: post.author, created_at: post.created_at, media: [{ id: "media_abcd", url: "/api/v1/media-file/media/author/media_abcd" }] }], total: 1 } }));
  let requests = 0;
  await page.route("**/api/v1/media-file/media_abcd/*", (route) => {
    requests++;
    return requests < 3 ? route.fulfill({ status: 404 }) : route.fulfill({ contentType: "image/jpeg", body: photo });
  });
  await page.goto(`/post/${post.id}`);
  const img = page.locator("#comment-comment-image .comment-media-grid img");
  await expect.poll(() => img.evaluateAll((images) => images.some((image) => (image as HTMLImageElement).naturalWidth > 0)), { timeout: 20000 }).toBe(true);
  await img.click();
  await expect(page.getByRole("dialog", { name: "图片查看器" })).toBeVisible();
  await expect.poll(() => page.locator(".gallery-main-image").evaluateAll((images) => images.some((image) => (image as HTMLImageElement).naturalWidth > 0))).toBe(true);
});

test("楼中楼竖图使用可辨识的完整预览而不是裁切小方块", async ({ page }) => {
  const tallImage = "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='216' height='480'%3E%3Crect fill='white' width='100%25' height='100%25'/%3E%3Crect fill='%23ef4444' x='18' y='30' width='180' height='80'/%3E%3Ctext x='108' y='210' text-anchor='middle' font-size='24'%3EORDER%3C/text%3E%3C/svg%3E";
  const createdAt = new Date().toISOString();
  const author = { id: "reply-author", nickname: "回复作者", level: 3 };
  const root = {
    id: "reply-root",
    post_id: "post-reply-media",
    root_id: "reply-root",
    author,
    content: "带竖图的回复线程",
    reply_count: 3,
    reply_preview: [{
      id: "reply-preview",
      post_id: "post-reply-media",
      root_id: "reply-root",
      parent_id: "reply-root",
      author,
      content: "",
      created_at: createdAt,
      media: [{ id: "reply-preview-image", url: tallImage, thumb_url: tallImage, detail_url: tallImage, original_url: tallImage, alt_text: "折叠回复竖图" }],
    }],
    created_at: createdAt,
  };
  const imageReply = {
    id: "reply-with-image",
    post_id: "post-reply-media",
    root_id: "reply-root",
    parent_id: "reply-root",
    author,
    content: "",
    created_at: createdAt,
    media: [{ id: "reply-image", url: tallImage, thumb_url: tallImage, detail_url: tallImage, original_url: tallImage, alt_text: "竖图预览" }],
  };

  await page.route("**/api/v1/posts/post-reply-media?*", (route) => route.fulfill({ json: {
    id: "post-reply-media", title: "回复图片预览测试", content: "正文", author, community: { id: "campus", name: "校园" }, comment_count: 1, created_at: createdAt,
  } }));
  await page.route("**/api/v1/posts/post-reply-media/comments*", (route) => route.fulfill({ json: { items: [root], total: 1, has_more: false } }));
  await page.route("**/api/v1/comments/reply-root/replies*", (route) => route.fulfill({ json: {
    items: [imageReply, { ...imageReply, id: "reply-text-2", content: "第二条", media: [] }, { ...imageReply, id: "reply-text-3", content: "第三条", media: [] }],
    total: 3,
    has_more: false,
  } }));

  await page.goto("/post/post-reply-media");
  const collapsedPreview = page.locator("#comment-reply-root .nested .comment-media-thumb");
  await expect(collapsedPreview).toBeVisible();
  await expect.poll(() => collapsedPreview.evaluate((image) => (image as HTMLImageElement).naturalWidth)).toBeGreaterThan(0);
  await page.locator("#comment-reply-root .more-nested").click();
  const preview = page.locator("#comment-reply-with-image .comment-media-preview");
  await expect(preview).toBeVisible();
  const size = await preview.boundingBox();
  expect(size?.width).toBeGreaterThanOrEqual(120);
  expect(size?.height).toBeGreaterThanOrEqual(160);
  await expect(preview).toHaveCSS("object-fit", "contain");
});

test("游客不显示榜单管理入口，直达投稿页时引导注册", async ({ page }) => {
  await page.goto("/ranking");
  await expect(page.getByRole("heading", { name: "本周好物榜" })).toBeVisible();
  await expect(page.getByText("榜单规则", { exact: true })).toHaveCount(0);
  await expect(page.getByRole("link", { name: "调整物品顺序" })).toHaveCount(0);
  await expect(page.getByRole("link", { name: "添加物品" })).toHaveCount(0);
  await page.goto("/ranking/submit");
  await expect(page.getByRole("heading", { name: "注册后才能投稿" })).toBeVisible();
});

for (const width of [1440, 390]) {
  test(`图片分级加载与原图缩放 ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 });
    const photo = readFileSync(path.resolve("../assets/images/store/badge.jpg"));
    const requests: string[] = [];
    await page.route("**/api/v1/media-file/media_zoom/*", async (route) => {
      requests.push(new URL(route.request().url()).pathname.split("/").pop()!);
      await route.fulfill({ contentType: "image/jpeg", body: photo });
    });
    await page.route("**/api/v1/posts/post-zoom?*", (route) => route.fulfill({ json: {
      id: "post-zoom", title: "分级图片测试", content: "按需查看原图", author: { id: "author", nickname: "作者" }, community: { id: "campus", name: "校园" }, created_at: new Date().toISOString(),
      media: [{ id: "media_zoom", url: "/api/v1/media-file/media_zoom/detail", thumb_url: "/api/v1/media-file/media_zoom/thumb", detail_url: "/api/v1/media-file/media_zoom/detail", original_url: "/api/v1/media-file/media_zoom/original" }],
    } }));
    await page.goto("/post/post-zoom");
    await page.locator(".detail-gallery img").first().click();
    const viewer = page.getByRole("dialog", { name: "图片查看器" });
    await expect(viewer.locator(".gallery-main-image")).toHaveAttribute("src", /\/detail$/);
    expect(requests).not.toContain("original");
    await viewer.getByRole("button", { name: "查看原图", exact: true }).click();
    await expect(viewer.locator(".gallery-main-image")).toHaveAttribute("src", /\/original$/);
    await expect.poll(() => requests.includes("original")).toBe(true);
    await viewer.getByRole("button", { name: "放大图片" }).click();
    await expect(viewer.locator(".gallery-main-image")).toHaveAttribute("style", /scale\(1.5\)/);
    await viewer.getByRole("button", { name: "重置缩放" }).click();
    await expect(viewer.locator(".gallery-main-image")).toHaveAttribute("style", /scale\(1\)/);
    await viewer.locator(".gallery-main-image").dblclick();
    await expect(viewer.locator(".gallery-main-image")).toHaveAttribute("style", /scale\(2\)/);
    const bounds = await viewer.locator(".gallery-main-image").boundingBox();
    expect(bounds).toBeTruthy();
    await page.mouse.move(bounds!.x + bounds!.width / 2, bounds!.y + bounds!.height / 2);
    await page.mouse.down();
    await page.mouse.move(bounds!.x + bounds!.width / 2 + 30, bounds!.y + bounds!.height / 2 + 20);
    await page.mouse.up();
    await expect(viewer.locator(".gallery-main-image")).toHaveAttribute("style", /translate\(30px, 20px\)/);
    const close = await viewer.getByRole("button", { name: "关闭查看器" }).boundingBox();
    expect(close!.x + close!.width).toBeLessThanOrEqual(width);
    if (process.env.LUNTAN_QA_SCREENSHOT_DIR) await page.screenshot({ path: path.join(process.env.LUNTAN_QA_SCREENSHOT_DIR, `gallery-zoom-${width}.png`) });
    await page.keyboard.press("Escape");
    await expect(viewer).toBeHidden();
  });
}
