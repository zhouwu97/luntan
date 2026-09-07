import { test, expect } from "@playwright/test";
import path from "node:path";
import { mockApiFallbacks } from "./mock-api";

const postFixture = {
  id: "post-rc-touch-1",
  title: "RC 性能回归测试帖子",
  content: "用于验证移动端触摸不会提前请求帖子详情。",
  comment_count: 0,
  like_count: 0,
  bookmark_count: 0,
  share_count: 0,
  view_count: 1,
  created_at: new Date().toISOString(),
  author: { id: "author-rc-1", nickname: "测试作者", level: 2 },
  community: { id: "community-campus", name: "校园板块" },
  media: [],
  viewer_state: { has_liked: false, has_bookmarked: false },
};

async function mockRegisteredSession(page: Parameters<typeof mockApiFallbacks>[0], userId = "user-rc-1") {
  await page.route("**/api/v1/auth/refresh", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ access_token: "rc-token", expires_in: 3600 }),
    });
  });
  await page.route("**/api/v1/me", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({
        id: userId,
        username: userId,
        nickname: "RC 测试用户",
        account_type: "email",
        level: 2,
        capabilities: { can_upload_media: true },
      }),
    });
  });
}

test.describe("网页版 RC 回归链路", () => {
  test("移动端触摸帖子不预取详情，桌面断点才加载发现右栏", async ({ page }) => {
    await mockApiFallbacks(page);
    await page.setViewportSize({ width: 390, height: 844 });

    let detailRequests = 0;
    let hotFeedRequests = 0;
    let rankingRequests = 0;
    await page.route("**/api/v1/feed/latest*", async (route) => {
      const url = new URL(route.request().url());
      if (url.searchParams.get("sort") === "hot") hotFeedRequests += 1;
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ items: url.searchParams.get("sort") === "hot" ? [] : [postFixture], has_more: false }),
      });
    });
    await page.route("**/api/v1/posts/post-rc-touch-1*", async (route) => {
      detailRequests += 1;
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(postFixture) });
    });
    await page.route("**/api/v1/ranking/toys*", async (route) => {
      rankingRequests += 1;
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ items: [] }) });
    });
    await page.route("**/api/v1/communities*", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ items: [{ id: "community-campus", name: "校园板块", status: "active" }] }),
      });
    });

    await page.goto("/");
    const card = page.locator("article.post-card").first();
    await expect(card).toContainText(postFixture.title);
    await card.dispatchEvent("touchstart");
    await card.dispatchEvent("pointerenter", { pointerType: "touch" });
    await page.waitForTimeout(250);

    expect(detailRequests).toBe(0);
    expect(hotFeedRequests).toBe(0);
    expect(rankingRequests).toBe(0);

    await page.setViewportSize({ width: 1440, height: 900 });
    await expect.poll(() => rankingRequests).toBeGreaterThan(0);
    await expect.poll(() => hotFeedRequests).toBeGreaterThan(0);
  });

  test("草稿按账号隔离，不读取其他账号或旧版共享 key", async ({ page }) => {
    await mockApiFallbacks(page);
    await page.addInitScript(() => {
      window.localStorage.setItem(
        "shengbeijiang_post_draft:user-a",
        JSON.stringify({ title: "账号 A 的私密草稿", content: "不应被账号 B 看到" }),
      );
      window.localStorage.setItem(
        "shengbeijiang_post_draft",
        JSON.stringify({ title: "旧版共享草稿", content: "不应被任何账号读取" }),
      );
    });
    await mockRegisteredSession(page, "user-b");
    await page.route("**/api/v1/communities*", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ items: [{ id: "community-campus", name: "校园板块", can_publish: true, can_upload_media: true }] }),
      });
    });

    await page.goto("/publish");
    await expect(page.getByPlaceholder("给这次分享起个标题")).toHaveValue("");
    await expect(page.getByPlaceholder("说说你的真实体验、问题或发现…")).toHaveValue("");
    await expect(page.getByText("已自动恢复上次草稿")).toHaveCount(0);
  });

  test("积分接口失败时不显示假 0，积分中心仍可进入且可单独重试", async ({ page }) => {
    await mockApiFallbacks(page);
    await mockRegisteredSession(page, "user-points-rc");
    await page.route("**/api/v1/users/user-points-rc", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ id: "user-points-rc", nickname: "积分测试", post_count: 1, comment_count: 2, bookmark_count: 3 }),
      });
    });
    await page.route("**/api/v1/me/posts*", async (route) => {
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ items: [] }) });
    });
    // 第二次请求由路由回调中的计数控制，避免依赖真实网络重试头。
    let pointsRequests = 0;
    await page.route("**/api/v1/me/points", async (route) => {
      pointsRequests += 1;
      if (pointsRequests === 1) {
        await route.fulfill({ status: 503, contentType: "application/json", body: JSON.stringify({ message: "积分服务暂时不可用" }) });
      } else {
        await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ balance: 7 }) });
      }
    });

    await page.goto("/me");
    const pointsCard = page.locator(".workbench-stat-points");
    await expect(pointsCard).toContainText("暂时无法获取");
    await expect(pointsCard.getByRole("button", { name: "重新加载积分" })).toBeVisible();
    await pointsCard.getByRole("button", { name: "重新加载积分" }).click();
    await expect(pointsCard).toContainText("7");
    expect(pointsRequests).toBe(2);
    await pointsCard.locator(".workbench-points-link").click();
    await expect(page).toHaveURL(/\/points/);
    // 积分中心会独立读取积分，不应影响工作台的失败恢复逻辑。
    await expect.poll(() => pointsRequests).toBe(3);
  });

  test("发帖创建失败时回收本次已上传媒体", async ({ page }) => {
    await mockApiFallbacks(page);
    await mockRegisteredSession(page, "user-publish-rc");
    await page.route("**/api/v1/communities*", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ items: [{ id: "community-campus", name: "校园板块", can_publish: true, can_upload_media: true }] }),
      });
    });
    await page.route("**/api/v1/media/upload-token", async (route) => {
      await route.fulfill({
        status: 201,
        contentType: "application/json",
        body: JSON.stringify({ media_id: "media-post-rc", upload_url: "/upload/media-post-rc", upload_method: "PUT" }),
      });
    });
    await page.route("**/upload/media-post-rc", async (route) => {
      await route.fulfill({ status: 200 });
    });
    await page.route("**/api/v1/media/media-post-rc/complete", async (route) => {
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ status: "ready" }) });
    });
    await page.route("**/api/v1/posts", async (route) => {
      if (route.request().method() === "POST") {
        await route.fulfill({ status: 400, contentType: "application/json", body: JSON.stringify({ message: "创建帖子失败" }) });
      } else {
        await route.fallback();
      }
    });
    let cleanupRequests = 0;
    await page.route("**/api/v1/media/media-post-rc", async (route) => {
      if (route.request().method() === "DELETE") cleanupRequests += 1;
      await route.fulfill({ status: 204 });
    });

    await page.goto("/publish");
    await page.getByPlaceholder("给这次分享起个标题").fill("失败后应清理媒体");
    await page.getByPlaceholder("说说你的真实体验、问题或发现…").fill("验证发帖失败回滚");
    await page.locator('input[type="file"]').setInputFiles(path.resolve("../assets/images/store/badge.jpg"));
    await page.locator(".publish-submit").click();

    await expect(page.locator(".form-error")).toContainText("创建帖子失败");
    await expect.poll(() => cleanupRequests).toBe(1);
  });
});
