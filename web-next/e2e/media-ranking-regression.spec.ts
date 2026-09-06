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

test("普通用户不显示榜单管理入口及规则说明，直达添加页面也不能操作", async ({ page }) => {
  await page.goto("/ranking");
  await expect(page.getByRole("heading", { name: "本周好物榜" })).toBeVisible();
  await expect(page.getByText("榜单规则", { exact: true })).toHaveCount(0);
  await expect(page.getByRole("link", { name: "调整物品顺序" })).toHaveCount(0);
  await expect(page.getByRole("link", { name: "添加物品" })).toHaveCount(0);
  await page.goto("/ranking/submit");
  await expect(page.getByText("仅超级管理员可添加榜单物品。")).toBeVisible();
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
