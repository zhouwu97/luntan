import { expect, test, type Page } from "@playwright/test";
import { mockApiFallbacks } from "./mock-api";

const pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";

async function mockPost(page: Page) {
  await page.route("**/api/v1/auth/refresh", (route) => route.fulfill({ json: { access_token: "composer-token" } }));
  await page.route("**/api/v1/me", (route) => route.fulfill({ json: {
    id: "composer-user",
    username: "composer-user",
    nickname: "输入测试用户",
    account_type: "email",
    capabilities: { can_comment: true, can_upload_media: true },
  } }));
  await page.route("**/api/v1/posts/post-composer?*", (route) => route.fulfill({ json: {
    id: "post-composer",
    title: "评论输入测试",
    content: "验证拖放与粘贴共用图片草稿。",
    author: { id: "author", nickname: "作者" },
    community: { id: "community", name: "测试社区" },
    comment_count: 1,
    created_at: new Date().toISOString(),
    viewer_state: {},
  } }));
  await page.route("**/api/v1/posts/post-composer/comments?*", (route) => route.fulfill({ json: { items: [{
    id: "root-comment",
    post_id: "post-composer",
    root_id: "root-comment",
    author: { id: "author", nickname: "作者" },
    content: "打开回复框",
    reply_count: 1,
    reply_preview: [{ id: "reply-preview", post_id: "post-composer", root_id: "root-comment", parent_id: "root-comment", author: { id: "author", nickname: "作者" }, content: "已有回复", created_at: new Date().toISOString() }],
    created_at: new Date().toISOString(),
    viewer_state: {},
  }], total: 1, has_more: false } }));
  await page.route("**/api/v1/comments/root-comment/replies*", (route) => route.fulfill({ json: { items: [], total: 0, has_more: false } }));
}

async function dispatchImage(page: Page, selector: string, eventName: "drop" | "paste", fileName: string) {
  return page.locator(selector).evaluate((element, input) => {
    const bytes = Uint8Array.from(atob(input.base64), (char) => char.charCodeAt(0));
    const transfer = new DataTransfer();
    transfer.items.add(new File([bytes], input.fileName, { type: "image/png" }));
    const event = input.eventName === "drop"
      ? new DragEvent("drop", { bubbles: true, cancelable: true, dataTransfer: transfer })
      : new ClipboardEvent("paste", { bubbles: true, cancelable: true, clipboardData: transfer });
    element.dispatchEvent(event);
    return event.defaultPrevented;
  }, { base64: pngBase64, fileName, eventName });
}

test.beforeEach(async ({ page }) => {
  await mockApiFallbacks(page);
  await mockPost(page);
});

test("桌面一级评论拖入图片后预览并携带 media_ids 发送", async ({ page }) => {
  let payload: Record<string, unknown> | null = null;
  await page.route("**/api/v1/media/upload-token", (route) => route.fulfill({ status: 201, json: { media_id: "drop-media", upload_url: "/upload/drop-media", upload_method: "PUT" } }));
  await page.route("**/upload/drop-media", (route) => route.fulfill({ status: 200 }));
  await page.route("**/api/v1/media/drop-media/complete", (route) => route.fulfill({ json: { status: "ready" } }));
  await page.route("**/api/v1/posts/post-composer/comments", async (route) => {
    if (route.request().method() !== "POST") return route.fallback();
    payload = route.request().postDataJSON() as Record<string, unknown>;
    await route.fulfill({ status: 201, json: { id: "new-comment", post_id: "post-composer", content: "拖图评论", author: { id: "composer-user", nickname: "输入测试用户" }, created_at: new Date().toISOString(), viewer_state: {}, media: [] } });
  });

  await page.goto("/post/post-composer");
  await dispatchImage(page, ".comment-composer", "drop", "drop.png");
  await expect(page.locator(".comment-composer img[src^='blob:']")).toHaveCount(1);
  await page.getByPlaceholder("写下你的评价、拆箱感受或回复…").fill("拖图评论");
  await page.getByRole("button", { name: "发布回复" }).click();
  await expect.poll(() => payload).toMatchObject({ content: "拖图评论", media_ids: ["drop-media"] });
});

test("粘贴图片沿用预览与九张上限", async ({ page }) => {
  await page.goto("/post/post-composer");
  const textarea = ".comment-composer textarea";
  for (let index = 0; index < 10; index += 1) {
    await dispatchImage(page, textarea, "paste", `paste-${index}.png`);
  }
  await expect(page.locator(".comment-composer img[src^='blob:']")).toHaveCount(9);
  await expect(page.getByText("最多上传 9 张图片")).toBeVisible();
});

test("上传失败后保留文字和图片草稿", async ({ page }) => {
  await page.route("**/api/v1/media/upload-token", (route) => route.fulfill({ status: 503, json: { message: "暂时不可用" } }));
  await page.goto("/post/post-composer");
  const textarea = page.getByPlaceholder("写下你的评价、拆箱感受或回复…");
  await textarea.fill("不要丢失的草稿");
  await dispatchImage(page, ".comment-composer", "drop", "keep.png");
  await page.getByRole("button", { name: "发布回复" }).click();

  await expect(textarea).toHaveValue("不要丢失的草稿");
  await expect(page.locator(".comment-composer img[src^='blob:']")).toHaveCount(1);
  await expect(page.getByText(/评论发送失败|暂时不可用/)).toBeVisible();
});

test("楼中楼回复支持拖入图片且草稿与一级评论隔离", async ({ page }) => {
  await page.goto("/post/post-composer");
  await dispatchImage(page, ".comment-composer", "drop", "root-draft.png");
  await page.locator("#comment-root-comment .nested").click();
  await dispatchImage(page, ".comment-reply-composer", "drop", "reply-draft.png");

  await expect(page.locator(".comment-composer img[src^='blob:']")).toHaveCount(1);
  await expect(page.locator(".comment-reply-modal img[src^='blob:']")).toHaveCount(1);
});

test("楼中楼 Emoji 网格不会被发送按钮样式撑出面板", async ({ page }) => {
  await page.goto("/post/post-composer");
  await page.locator("#comment-root-comment .nested").click();
  const modal = page.locator(".comment-reply-modal");
  await modal.getByRole("button", { name: "添加表情" }).click();
  const panel = modal.locator(".expression-panel");
  await expect(panel).toBeVisible();
  await expect.poll(() => panel.evaluate((element) => element.scrollWidth <= element.clientWidth)).toBe(true);
  const panelBounds = await panel.boundingBox();
  const lastEmojiBounds = await modal.getByRole("button", { name: "插入 💯" }).boundingBox();
  expect(panelBounds && lastEmojiBounds).toBeTruthy();
  expect(lastEmojiBounds!.x + lastEmojiBounds!.width).toBeLessThanOrEqual(panelBounds!.x + panelBounds!.width);

  await panel.getByRole("button", { name: "表情包", exact: true }).click();
  const modalBounds = await modal.boundingBox();
  const stickerPanelBounds = await panel.boundingBox();
  const stickerTabBounds = await panel.getByRole("button", { name: "表情包", exact: true }).boundingBox();
  const groupBounds = await panel.getByRole("button", { name: "明风·日常", exact: true }).boundingBox();
  expect(modalBounds && stickerPanelBounds && stickerTabBounds && groupBounds).toBeTruthy();
  expect(stickerPanelBounds!.y).toBeGreaterThanOrEqual(modalBounds!.y);
  expect(stickerPanelBounds!.height).toBeLessThanOrEqual(210);
  expect(Math.abs((stickerTabBounds!.y + stickerTabBounds!.height / 2) - (groupBounds!.y + groupBounds!.height / 2))).toBeLessThan(3);

  await modal.locator("header h2").click();
  await expect(panel).toBeHidden();
  await modal.getByRole("button", { name: "添加表情" }).click();
  await page.keyboard.press("Escape");
  await expect(panel).toBeHidden();
  await expect(modal.getByRole("button", { name: "添加表情" })).toBeFocused();
});

test("Emoji 插入当前光标而不是固定追加到末尾", async ({ page }) => {
  await page.goto("/post/post-composer");
  const textarea = page.getByPlaceholder("写下你的评价、拆箱感受或回复…");
  await textarea.fill("你好");
  await textarea.evaluate((element) => (element as HTMLTextAreaElement).setSelectionRange(1, 1));
  await page.locator(".comment-composer").getByRole("button", { name: "添加表情" }).click();
  await page.getByRole("button", { name: "插入 😂" }).click();
  await expect(textarea).toHaveValue("你😂好");
});

test("表情包发送 sticker_id 并在新评论中正确渲染", async ({ page }) => {
  let payload: Record<string, unknown> | null = null;
  await page.route("**/api/v1/posts/post-composer/comments", async (route) => {
    if (route.request().method() !== "POST") return route.fallback();
    payload = route.request().postDataJSON() as Record<string, unknown>;
    await route.fulfill({ status: 201, json: {
      id: "sticker-comment",
      post_id: "post-composer",
      content: "",
      attachments: [{ id: "aad70d8d064f9eb79286c1393490716c", type: "sticker", sticker_id: "aad70d8d064f9eb79286c1393490716c" }],
      author: { id: "composer-user", nickname: "输入测试用户" },
      created_at: new Date().toISOString(),
      viewer_state: {},
    } });
  });

  await page.goto("/post/post-composer");
  const composer = page.locator(".comment-composer");
  await composer.getByRole("button", { name: "添加表情" }).click();
  await composer.getByRole("button", { name: "表情包" }).click();
  await composer.getByRole("button", { name: "选择表情包：亲亲" }).click();
  await composer.getByRole("button", { name: "发布回复" }).click();

  await expect.poll(() => payload).toMatchObject({ content: "", sticker_id: "aad70d8d064f9eb79286c1393490716c" });
  await expect(page.locator("#comment-sticker-comment .comment-sticker")).toHaveAttribute("src", "/stickers/aad70d8d064f9eb79286c1393490716c.png");
});

test("楼中楼表情包发送 sticker_id 并在回复列表中渲染", async ({ page }) => {
  let payload: Record<string, unknown> | null = null;
  await page.route("**/api/v1/comments/root-comment/replies*", async (route) => {
    if (route.request().method() !== "POST") return route.fallback();
    payload = route.request().postDataJSON() as Record<string, unknown>;
    await route.fulfill({ status: 201, json: {
      id: "reply-sticker",
      post_id: "post-composer",
      root_id: "root-comment",
      parent_id: "root-comment",
      content: "",
      attachments: [{ id: "aad70d8d064f9eb79286c1393490716c", type: "sticker", sticker_id: "aad70d8d064f9eb79286c1393490716c" }],
      author: { id: "composer-user", nickname: "输入测试用户" },
      created_at: new Date().toISOString(),
      viewer_state: {},
    } });
  });

  await page.goto("/post/post-composer");
  await page.locator("#comment-root-comment .nested").click();
  const modal = page.locator(".comment-reply-modal");
  await modal.getByRole("button", { name: "添加表情" }).click();
  await modal.getByRole("button", { name: "表情包", exact: true }).click();
  await modal.getByRole("button", { name: "选择表情包：亲亲" }).click();
  await modal.getByRole("button", { name: "发送" }).click();

  await expect.poll(() => payload).toMatchObject({ content: "", sticker_id: "aad70d8d064f9eb79286c1393490716c" });
  await expect(page.locator("#comment-reply-sticker .comment-sticker")).toHaveAttribute("src", "/stickers/aad70d8d064f9eb79286c1393490716c.png");
});

test("移动端常驻 Composer 支持表情包发送", async ({ page }) => {
  let payload: Record<string, unknown> | null = null;
  await page.route("**/api/v1/posts/post-composer/comments", async (route) => {
    if (route.request().method() !== "POST") return route.fallback();
    payload = route.request().postDataJSON() as Record<string, unknown>;
    await route.fulfill({ status: 201, json: {
      id: "mobile-sticker-comment",
      post_id: "post-composer",
      content: "",
      attachments: [{ id: "aad70d8d064f9eb79286c1393490716c", type: "sticker", sticker_id: "aad70d8d064f9eb79286c1393490716c" }],
      author: { id: "composer-user", nickname: "输入测试用户" },
      created_at: new Date().toISOString(),
      viewer_state: {},
    } });
  });

  await page.setViewportSize({ width: 435, height: 850 });
  await page.goto("/post/post-composer");
  const composer = page.locator(".mobile-comment-composer");
  await composer.getByRole("button", { name: "添加表情" }).click();
  await composer.getByRole("button", { name: "表情包", exact: true }).click();
  await composer.getByRole("button", { name: "选择表情包：亲亲" }).click();
  await composer.getByRole("button", { name: "发送" }).click();

  await expect.poll(() => payload).toMatchObject({ content: "", sticker_id: "aad70d8d064f9eb79286c1393490716c" });
  await expect(page.locator("#comment-mobile-sticker-comment .comment-sticker")).toHaveAttribute("src", "/stickers/aad70d8d064f9eb79286c1393490716c.png");
});

test("已选表情包时拖图会阻止导航并提示互斥", async ({ page }) => {
  await page.goto("/post/post-composer");
  const composer = page.locator(".comment-composer");
  await composer.getByRole("button", { name: "添加表情" }).click();
  await composer.getByRole("button", { name: "表情包", exact: true }).click();
  await composer.getByRole("button", { name: "选择表情包：亲亲" }).click();

  await dispatchImage(page, ".comment-composer", "drop", "disabled-drop.png");
  await expect(page).toHaveURL(/\/post\/post-composer$/);
  await expect(page.getByText("图片与表情包不能同时发送")).toBeVisible();
  await expect(composer.locator("img[src^='blob:']")).toHaveCount(0);
});

test("已选表情包时粘贴图片不吞掉现有文字", async ({ page }) => {
  await page.goto("/post/post-composer");
  const composer = page.locator(".comment-composer");
  const textarea = composer.locator("textarea");
  await textarea.fill("保留这段文字");
  await composer.getByRole("button", { name: "添加表情" }).click();
  await composer.getByRole("button", { name: "表情包", exact: true }).click();
  await composer.getByRole("button", { name: "选择表情包：亲亲" }).click();

  const prevented = await dispatchImage(page, ".comment-composer textarea", "paste", "disabled-paste.png");
  await expect(textarea).toHaveValue("保留这段文字");
  await expect(composer.locator("img[src^='blob:']")).toHaveCount(0);
  expect(prevented).toBe(false);
});

test("435px 手机表情面板不发生横向溢出", async ({ page }) => {
  await page.setViewportSize({ width: 435, height: 850 });
  await page.goto("/post/post-composer");
  const toolbar = page.locator(".mobile-reply-toolbar");
  const imageBounds = await toolbar.getByLabel("添加图片").boundingBox();
  const inputBounds = await toolbar.getByPlaceholder("友善地回复一句…").boundingBox();
  const sendBounds = await toolbar.getByRole("button", { name: "发送" }).boundingBox();
  expect(imageBounds && inputBounds && sendBounds).toBeTruthy();
  expect(Math.abs((imageBounds!.y + imageBounds!.height / 2) - (inputBounds!.y + inputBounds!.height / 2))).toBeLessThan(3);
  expect(Math.abs((sendBounds!.y + sendBounds!.height / 2) - (inputBounds!.y + inputBounds!.height / 2))).toBeLessThan(3);
  await page.locator(".mobile-comment-composer").getByRole("button", { name: "添加表情" }).click();
  const panel = page.locator(".expression-panel");
  await expect(panel).toBeVisible();
  const bounds = await panel.boundingBox();
  expect(bounds).toBeTruthy();
  expect(bounds!.x).toBeGreaterThanOrEqual(0);
  expect(bounds!.x + bounds!.width).toBeLessThanOrEqual(435);
});

test("移动端动态 Composer 高度为图片预览留出底部空间", async ({ page }) => {
  await page.setViewportSize({ width: 435, height: 850 });
  await page.goto("/post/post-composer");
  const composer = page.locator(".mobile-comment-composer");
  const before = await composer.boundingBox();
  await composer.locator("input[type=file]").setInputFiles(
    Array.from({ length: 9 }, (_, index) => ({
      name: `mobile-${index}.png`,
      mimeType: "image/png",
      buffer: Buffer.from(pngBase64, "base64"),
    })),
  );
  await expect(composer.locator("img[src^='blob:']")).toHaveCount(9);
  const after = await composer.boundingBox();
  const content = await page.locator(".post-detail-mobile-content").evaluate((element) => ({
    paddingBottom: getComputedStyle(element).paddingBottom,
    composerHeight: getComputedStyle(element).getPropertyValue("--mobile-comment-composer-height"),
  }));

  expect(before && after).toBeTruthy();
  expect(after!.height).toBeGreaterThan(before!.height);
  expect(parseFloat(content.composerHeight)).toBeGreaterThan(before!.height);
  expect(parseFloat(content.paddingBottom)).toBeGreaterThan(after!.height - 1);
});

test("低高度移动端表情面板保持在视口内且表情包可滚动", async ({ page }) => {
  for (const viewport of [{ width: 390, height: 400 }, { width: 435, height: 420 }]) {
    await page.setViewportSize(viewport);
    await page.goto("/post/post-composer");
    const composer = page.locator(".mobile-comment-composer");
    await composer.getByRole("button", { name: "添加表情" }).click();
    const panel = composer.locator(".expression-panel");
    await expect(panel).toBeVisible();
    const bounds = await panel.boundingBox();
    expect(bounds).toBeTruthy();
    expect(bounds!.x).toBeGreaterThanOrEqual(0);
    expect(bounds!.y).toBeGreaterThanOrEqual(0);
    expect(bounds!.x + bounds!.width).toBeLessThanOrEqual(viewport.width);

    await panel.getByRole("button", { name: "表情包", exact: true }).click();
    await expect.poll(() => panel.locator(".sticker-grid").evaluate((element) => element.scrollHeight >= element.clientHeight)).toBe(true);
  }
});
