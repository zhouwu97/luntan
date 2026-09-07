import { expect, test, type Page } from "@playwright/test";
import { mockApiFallbacks } from "./mock-api";

const guest = {
  id: "guest-1",
  username: "guest",
  nickname: "游客",
  account_type: "guest",
  capabilities: {
    can_comment: true,
    can_like: true,
    can_upload_media: false,
    can_manage_bookmarks: false,
    can_vote: false,
  },
};

const registered = {
  id: "user-1",
  username: "member",
  nickname: "正式用户",
  account_type: "registered",
  capabilities: {
    can_comment: true,
    can_like: true,
    can_upload_media: true,
    can_manage_bookmarks: true,
    can_vote: true,
  },
};

async function restoreAs(page: Page, user: typeof guest | typeof registered) {
  await page.route("**/api/v1/auth/refresh", (route) => route.fulfill({ json: { access_token: "fixture-token" } }));
  await page.route("**/api/v1/me", (route) => route.fulfill({ json: user }));
}

async function mockHome(page: Page) {
  await page.route("**/api/v1/communities*", (route) => route.fulfill({ json: { items: [{ id: "community-campus", name: "校园板块", status: "active" }] } }));
  await page.route("**/api/v1/posts*", (route) => route.fulfill({ json: { items: [], has_more: false } }));
}

async function mockPost(page: Page) {
  const post = {
    id: "post-capability",
    title: "权限测试帖子",
    content: "游客仍然可以发表纯文字评论",
    author: { id: "author-1", nickname: "作者" },
    community: { id: "community-campus", name: "校园板块" },
    created_at: new Date().toISOString(),
    viewer_state: { has_liked: false, has_bookmarked: false },
  };
  await page.route("**/api/v1/posts/post-capability?*", (route) => route.fulfill({ json: post }));
  await page.route("**/api/v1/posts/post-capability/comments*", (route) => route.fulfill({ json: { items: [], total: 0 } }));
}

async function mockRanking(page: Page) {
  const toy = {
    id: "toy-1",
    rank: 1,
    name: "权限测试玩具",
    merchant: "TEST",
    description: "权限测试",
    score: 8.8,
    want_count: 3,
    rating_count: 2,
    tags: ["测试"],
    rating_distribution: {},
    comments: [],
    viewer_state: { wanted: false, owned: false },
  };
  await page.route("**/api/v1/ranking/toys/toy-1*", (route) => route.fulfill({ json: toy }));
  await page.route("**/api/v1/ranking/view*", (route) => route.fulfill({ json: { items: [toy] } }));
}

test.beforeEach(async ({ page }) => {
  await mockApiFallbacks(page);
});

test("社区首页明确进入全站，PC 游客不伪装成正式用户", async ({ page }) => {
  await restoreAs(page, guest);
  await mockHome(page);
  await page.goto("/?community=community-campus");

  await expect(page.getByText("杂鱼萌新 (未登录)")).toBeVisible();
  await expect(page.getByRole("link", { name: "查看个人主页" })).toHaveCount(0);
  await page.getByRole("button", { name: /社区首页/ }).click();
  await expect(page).toHaveURL(/community=all/);
});

test("游客收藏在请求前引导注册，评论只保留文字入口", async ({ page }) => {
  await restoreAs(page, guest);
  await mockPost(page);
  let bookmarkRequests = 0;
  await page.route("**/api/v1/posts/post-capability/bookmark", (route) => {
    bookmarkRequests += 1;
    return route.fulfill({ status: 403, json: { code: "FORBIDDEN" } });
  });

  await page.goto("/post/post-capability");
  await expect(page.getByPlaceholder("写下你的评价、拆箱感受或回复…")).toBeVisible();
  await expect(page.locator('input[type="file"]')).toHaveCount(0);
  await page.getByRole("button", { name: "收藏" }).first().click();
  await expect(page).toHaveURL(/\/login\?mode=register/);
  expect(bookmarkRequests).toBe(0);
});

test("手机游客点击图片入口时明确引导注册", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await restoreAs(page, guest);
  await mockPost(page);

  await page.goto("/post/post-capability");
  await page.getByPlaceholder("说点什么，参与热烈讨论...").click();
  await page.getByRole("button", { name: "添加图片（注册后可用）" }).click();

  await expect(page).toHaveURL(/\/login\?mode=register/);
});

test("手机正式用户可以上传图片并随评论发送", async ({ page }) => {
  const pngBytes = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=", "base64");
  await page.setViewportSize({ width: 390, height: 844 });
  await restoreAs(page, registered);
  await mockPost(page);
  let commentPayload: Record<string, unknown> | null = null;

  await page.route("**/api/v1/media/upload-token", (route) => route.fulfill({
    status: 201,
    json: { media_id: "mobile-comment-image", upload_url: "/upload/mobile-comment-image", upload_method: "PUT" },
  }));
  await page.route("**/upload/mobile-comment-image", (route) => route.fulfill({ status: 200 }));
  await page.route("**/api/v1/media/mobile-comment-image/complete", (route) => route.fulfill({ json: { status: "ready" } }));
  await page.route("**/api/v1/posts/post-capability/comments", async (route) => {
    if (route.request().method() !== "POST") return route.fallback();
    commentPayload = route.request().postDataJSON() as Record<string, unknown>;
    await route.fulfill({ status: 201, json: {
      id: "mobile-image-comment",
      post_id: "post-capability",
      content: "手机图片评论",
      author: registered,
      created_at: new Date().toISOString(),
      viewer_state: {},
      media: [],
    } });
  });

  await page.goto("/post/post-capability");
  await page.getByPlaceholder("说点什么，参与热烈讨论...").click();
  await page.getByPlaceholder("友善地写下你的评价或想法…").fill("手机图片评论");
  await page.locator('.composer-sheet input[type="file"]').setInputFiles({ name: "mobile.png", mimeType: "image/png", buffer: pngBytes });
  await expect(page.locator(".composer-sheet img")).toBeVisible();
  await page.getByRole("button", { name: "发送", exact: true }).click();

  await expect.poll(() => commentPayload).toMatchObject({ content: "手机图片评论", media_ids: ["mobile-comment-image"] });
});

test("普通正式用户可进入榜单投稿，管理员入口仍保持独立", async ({ page }) => {
  await restoreAs(page, registered);
  await mockRanking(page);
  await page.goto("/ranking");

  await expect(page.getByRole("link", { name: "添加物品" })).toBeVisible();
  await expect(page.getByRole("link", { name: "调整物品顺序" })).toHaveCount(0);
  await page.goto("/ranking/submit");
  await expect(page.getByRole("heading", { name: "投稿新玩具" })).toBeVisible();
  await expect(page.getByText("仅超级管理员可添加榜单物品。")).toHaveCount(0);
});

test("游客的想冲、买过和评分统一按 can_vote 引导注册", async ({ page }) => {
  await restoreAs(page, guest);
  await mockRanking(page);

  for (const control of ["想冲", "买过", "点击评分，当前 8.8 分"]) {
    await page.goto("/ranking/toy-1");
    await page.getByRole(control.startsWith("点击") ? "button" : "button", { name: new RegExp(control) }).first().click();
    await expect(page).toHaveURL(/\/login\?mode=register/);
  }
});

test("帖子工具栏恢复图片筛选入口", async ({ page }) => {
  await restoreAs(page, registered);
  await mockHome(page);
  await page.goto("/");

  await page.getByRole("button", { name: "筛选" }).click();
  await expect(page.getByRole("checkbox", { name: "只看图片" })).toBeVisible();
});

test("我的收藏卡片显示收藏数，切换 Tab 只请求一次", async ({ page }) => {
  await restoreAs(page, registered);
  await page.route("**/api/v1/users/user-1", (route) => route.fulfill({ json: {
    ...registered,
    post_count: 5,
    comment_count: 6,
    follower_count: 99,
    bookmark_count: 7,
  } }));
  await page.route("**/api/v1/me/points", (route) => route.fulfill({ json: { balance: 10 } }));
  await page.route("**/api/v1/me/posts*", (route) => route.fulfill({ json: { items: [], has_more: false } }));
  let commentRequests = 0;
  await page.route("**/api/v1/me/comments*", (route) => {
    commentRequests += 1;
    return route.fulfill({ json: { items: [], has_more: false } });
  });

  await page.goto("/me");
  const bookmarkCard = page.getByRole("button", { name: /我的收藏/ }).first();
  await expect(bookmarkCard).toContainText("7");
  await page.getByRole("button", { name: "我的回复", exact: true }).first().click();
  await expect.poll(() => commentRequests).toBe(1);
});

test("会话恢复时 /me 临时失败会重试，而不是静默匿名", async ({ page }) => {
  await page.route("**/api/v1/auth/refresh", (route) => route.fulfill({ json: { access_token: "fixture-token" } }));
  let attempts = 0;
  await page.route("**/api/v1/me", (route) => {
    attempts += 1;
    return attempts === 1
      ? route.fulfill({ status: 503, json: { code: "TEMPORARY_UNAVAILABLE" } })
      : route.fulfill({ json: registered });
  });
  await mockHome(page);

  await page.goto("/");
  await expect(page.getByText("正式用户")).toBeVisible();
  expect(attempts).toBeGreaterThanOrEqual(2);
});

test("用户主页把 commentCount 准确标为评论", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await restoreAs(page, registered);
  await page.route("**/api/v1/users/user-1", (route) => route.fulfill({ json: { ...registered, comment_count: 6 } }));
  await page.route("**/api/v1/users/user-1/posts*", (route) => route.fulfill({ json: { items: [] } }));
  await page.goto("/user/user-1");

  await expect(page.getByText("评论与收藏")).toHaveCount(0);
  await expect(page.locator(".stat-label", { hasText: "评论" })).toBeVisible();
});
