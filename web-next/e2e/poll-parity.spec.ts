import { expect, test, type Page } from "@playwright/test";
import { mockApiFallbacks } from "./mock-api";

const registered = {
  id: "poll-user",
  username: "poll-user",
  nickname: "投票测试用户",
  account_type: "registered",
  capabilities: { can_publish: true, can_comment: true, can_vote: true, can_create_poll: true },
};

const guest = {
  id: "poll-guest",
  username: "poll-guest",
  nickname: "投票游客",
  account_type: "guest",
  capabilities: { can_comment: true, can_vote: false, can_create_poll: false },
};

async function mockSession(page: Page, user: typeof registered | typeof guest) {
  await page.route("**/api/v1/auth/refresh", (route) => route.fulfill({ json: { access_token: "poll-fixture-token" } }));
  await page.route("**/api/v1/me", (route) => route.fulfill({ json: user }));
}

function pollPost(id: string) {
  return {
    id,
    type: "poll",
    title: "本周选题投票",
    content: "请投出你最想看的内容。",
    author: { id: "poll-author", nickname: "发起人" },
    community: { id: "community-poll", name: "投票板块" },
    created_at: new Date().toISOString(),
    viewer_state: { has_liked: false, has_bookmarked: false },
  };
}

test.describe("投票 Web/App 协议一致性", () => {
  test("正式账号可创建多选投票，并立即以服务端结果更新详情", async ({ page }) => {
    await mockApiFallbacks(page);
    await mockSession(page, registered);
    await page.route("**/api/v1/communities*", (route) => route.fulfill({ json: {
      items: [{ id: "community-poll", name: "投票板块", can_publish: true, can_create_poll: true, can_upload_media: true }],
    } }));

    let createPayload: Record<string, unknown> | null = null;
    let voted = false;
    let voteRequests = 0;
    await page.route("**/api/v1/posts", async (route) => {
      if (route.request().method() !== "POST") return route.fallback();
      createPayload = route.request().postDataJSON() as Record<string, unknown>;
      await route.fulfill({ status: 201, json: { id: "post-poll" } });
    });
    await page.route("**/api/v1/posts/post-poll*", (route) => route.fulfill({ json: pollPost("post-poll") }));
    await page.route("**/api/v1/posts/post-poll/comments?*", (route) => route.fulfill({ json: { items: [], total: 0, has_more: false } }));
    await page.route("**/api/v1/posts/post-poll/poll", (route) => route.fulfill({ json: {
      id: "poll-1",
      post_id: "post-poll",
      question: "下周优先做什么？",
      allow_multiple: true,
      options: [
        { id: "option-a", label: "开箱", sort_order: 0, vote_count: voted ? 1 : 0 },
        { id: "option-b", label: "测评", sort_order: 1, vote_count: voted ? 1 : 0 },
      ],
      viewer_state: { has_voted: voted, option_ids: voted ? ["option-a", "option-b"] : [], can_vote: !voted, authentication_required: false },
    } }));
    await page.route("**/api/v1/polls/poll-1/vote", async (route) => {
      voteRequests += 1;
      expect(route.request().postDataJSON()).toEqual({ option_ids: ["option-a", "option-b"] });
      voted = true;
      await route.fulfill({ json: { poll_id: "poll-1", option_ids: ["option-a", "option-b"] } });
    });

    await page.goto("/publish");
    await page.getByLabel("帖子类型").selectOption("poll");
    await page.getByPlaceholder("给这次分享起个标题").fill("本周选题投票");
    await page.getByPlaceholder("说说你的真实体验、问题或发现…").fill("邀请大家投票。 ");
    await page.getByLabel("投票问题").fill("下周优先做什么？");
    await page.getByLabel("投票选项 1").fill("开箱");
    await page.getByLabel("投票选项 2").fill("测评");
    await page.getByText("允许多选", { exact: true }).click();
    await page.getByRole("button", { name: "发布投票" }).click();

    await expect(page).toHaveURL(/\/post\/post-poll/);
    expect(createPayload).toMatchObject({
      type: "poll",
      poll: { question: "下周优先做什么？", options: ["开箱", "测评"], allow_multiple: true },
    });
    await page.getByLabel("开箱").check();
    await page.getByLabel("测评").check();
    await page.getByRole("button", { name: "提交投票" }).click();
    await expect(page.getByText("你已参与投票 · 共 2 票")).toBeVisible();
    expect(voteRequests).toBe(1);
  });

  test("正式账号单选投票只提交一个选项", async ({ page }) => {
    await mockApiFallbacks(page);
    await mockSession(page, registered);
    let votePayload: unknown = null;
    await page.route("**/api/v1/posts/post-poll-single*", (route) => route.fulfill({ json: pollPost("post-poll-single") }));
    await page.route("**/api/v1/posts/post-poll-single/comments?*", (route) => route.fulfill({ json: { items: [], total: 0, has_more: false } }));
    await page.route("**/api/v1/posts/post-poll-single/poll", (route) => route.fulfill({ json: {
      id: "poll-single",
      post_id: "post-poll-single",
      question: "单选测试",
      allow_multiple: false,
      options: [{ id: "single-a", label: "A", sort_order: 0, vote_count: 0 }, { id: "single-b", label: "B", sort_order: 1, vote_count: 0 }],
      viewer_state: { has_voted: false, option_ids: [], can_vote: true, authentication_required: false },
    } }));
    await page.route("**/api/v1/polls/poll-single/vote", async (route) => {
      votePayload = route.request().postDataJSON();
      await route.fulfill({ json: { poll_id: "poll-single", option_ids: ["single-b"] } });
    });

    await page.goto("/post/post-poll-single");
    await page.getByLabel("B").check();
    await page.getByRole("button", { name: "提交投票" }).click();
    await expect.poll(() => votePayload).toEqual({ option_ids: ["single-b"] });
  });

  test("截止后的投票禁用选项和提交，不发送投票请求", async ({ page }) => {
    await mockApiFallbacks(page);
    await mockSession(page, registered);
    let voteRequests = 0;
    await page.route("**/api/v1/posts/post-poll-ended*", (route) => route.fulfill({ json: pollPost("post-poll-ended") }));
    await page.route("**/api/v1/posts/post-poll-ended/comments?*", (route) => route.fulfill({ json: { items: [], total: 0, has_more: false } }));
    await page.route("**/api/v1/posts/post-poll-ended/poll", (route) => route.fulfill({ json: {
      id: "poll-ended",
      post_id: "post-poll-ended",
      question: "截止测试",
      allow_multiple: false,
      ends_at: "2020-01-01T00:00:00Z",
      options: [{ id: "ended-a", label: "已截止选项", sort_order: 0, vote_count: 3 }, { id: "ended-b", label: "另一选项", sort_order: 1, vote_count: 2 }],
      viewer_state: { has_voted: false, option_ids: [], can_vote: true, authentication_required: false },
    } }));
    await page.route("**/api/v1/polls/poll-ended/vote", (route) => {
      voteRequests += 1;
      return route.fulfill({ status: 403, json: { code: "POLL_ENDED" } });
    });

    await page.goto("/post/post-poll-ended");
    await expect(page.getByLabel("已截止选项")).toBeDisabled();
    await expect(page.getByRole("button", { name: "投票已结束" })).toBeDisabled();
    expect(voteRequests).toBe(0);
  });

  test("游客点击投票在请求前引导注册", async ({ page }) => {
    await mockApiFallbacks(page);
    await mockSession(page, guest);
    let voteRequests = 0;
    await page.route("**/api/v1/posts/post-poll-guest*", (route) => route.fulfill({ json: pollPost("post-poll-guest") }));
    await page.route("**/api/v1/posts/post-poll-guest/comments?*", (route) => route.fulfill({ json: { items: [], total: 0, has_more: false } }));
    await page.route("**/api/v1/posts/post-poll-guest/poll", (route) => route.fulfill({ json: {
      id: "poll-guest-1",
      post_id: "post-poll-guest",
      question: "游客权限测试",
      allow_multiple: false,
      options: [{ id: "guest-option", label: "参与", sort_order: 0, vote_count: 0 }, { id: "guest-option-2", label: "围观", sort_order: 1, vote_count: 0 }],
      viewer_state: { has_voted: false, option_ids: [], can_vote: false, authentication_required: false },
    } }));
    await page.route("**/api/v1/polls/poll-guest-1/vote", (route) => {
      voteRequests += 1;
      return route.fulfill({ status: 403, json: { code: "FORBIDDEN" } });
    });

    await page.goto("/post/post-poll-guest");
    await page.getByLabel("参与").check();
    await page.getByRole("button", { name: "注册后参与投票" }).click();
    await expect(page).toHaveURL(/\/login\?mode=register/);
    expect(voteRequests).toBe(0);
  });
});
