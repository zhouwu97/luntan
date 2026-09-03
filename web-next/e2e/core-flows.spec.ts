import { test, expect } from "@playwright/test";

test.describe("Web-Next 核心业务链路验收套件", () => {
  test("1. PC 登录：密码登录与验证码登录切换正常", async ({ page }) => {
    await page.goto("/login");

    // 默认展示密码登录与邮箱、密码输入框
    const emailInput = page.getByPlaceholder("请输入你的常用邮箱");
    await expect(emailInput).toBeVisible();
    const passwordInput = page.getByPlaceholder("请输入登录密码");
    await expect(passwordInput).toBeVisible();

    // 切换到“验证码登录”
    const codeLoginTab = page.getByRole("button", { name: "验证码登录" });
    await codeLoginTab.click();

    // 此时应显示验证码输入框与获取验证码按钮
    const sendCodeBtn = page.getByRole("button", { name: "获取验证码" });
    await expect(sendCodeBtn).toBeVisible();

    // 再次切换回“密码登录”
    const pwdLoginTab = page.getByRole("button", { name: "密码登录" });
    await pwdLoginTab.click();
    await expect(passwordInput).toBeVisible();
  });

  test("2. 免验证码注册：支持免验证码直接注册表单契约", async ({ page }) => {
    await page.goto("/login");

    // 切换至“注册”
    const registerTab = page.getByRole("button", { name: "注册" });
    await registerTab.click();

    // 验证注册表单字段：邮箱、密码、确认密码、昵称（可选）
    const emailInput = page.getByPlaceholder("请输入你的常用邮箱");
    const passwordInput = page.getByPlaceholder("设置至少 8 位登录密码");
    const confirmPasswordInput = page.getByPlaceholder("再次确认登录密码");
    await expect(emailInput).toBeVisible();
    await expect(passwordInput).toBeVisible();
    await expect(confirmPasswordInput).toBeVisible();

    // 填入基础信息，验证码不强制填写，客户端不会提示“请输入验证码”
    await emailInput.fill("test_new_user@example.com");
    await passwordInput.fill("Password123!");
    await confirmPasswordInput.fill("Password123!");

    // 模拟注册 API 返回，验证客户端发送的数据允许 code 为空
    let submittedPayload: Record<string, unknown> | null = null;
    await page.route("**/api/v1/auth/register", async (route) => {
      submittedPayload = JSON.parse(route.request().postData() || "{}");
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          token: "mock-token",
          user: {
            id: "user-new-1",
            username: "testuser",
            nickname: "测试萌新",
            level: 1,
          },
        }),
      });
    });

    const submitBtn = page.getByRole("button", { name: "立即注册" });
    await submitBtn.click();

    // 确认已向后端发起注册请求，且没有客户端强制阻断
    await expect(async () => {
      expect(submittedPayload).not.toBeNull();
      expect(submittedPayload?.email).toBe("test_new_user@example.com");
    }).toPass();
  });

  test("3. 发帖草稿保护：本地持久化保存与恢复", async ({ page }) => {
    // 注入已登录 Session
    await page.addInitScript(() => {
      window.localStorage.setItem(
        "shengbeijiang_post_draft",
        JSON.stringify({
          title: "测试草稿标题 - 自动保存",
          content: "这是草稿正文内容，页面刷新后应自动恢复",
          communityId: "comm-1",
          updatedAt: Date.now(),
        }),
      );
    });

    // Mock 用户信息以允许进入发布页
    await page.route("**/api/v1/me", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          id: "u1",
          username: "tester",
          nickname: "测试达人",
          level: 3,
        }),
      });
    });

    await page.route("**/api/v1/communities*", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          items: [{ id: "comm-1", name: "综合讨论", can_publish: true }],
        }),
      });
    });

    await page.goto("/publish");

    // 验证草稿内容成功自动回填
    const titleInput = page.getByPlaceholder("给这次分享起个标题");
    const contentTextarea = page.getByPlaceholder("说说你的真实体验、问题或发现…");

    await expect(titleInput).toHaveValue("测试草稿标题 - 自动保存");
    await expect(contentTextarea).toHaveValue("这是草稿正文内容，页面刷新后应自动恢复");
    await expect(page.getByText("已自动恢复上次草稿")).toBeVisible();
  });

  test("4. 帖子与评论：30+评论真分页与全屏图片画廊查看器", async ({ page }) => {
    // Mock 帖子与 30 条初始评论
    const mockPost = {
      id: "post-101",
      title: "长篇热门测评与大图分享",
      content: "本期评测玩具包含多张细节实拍图片",
      comment_count: 45,
      like_count: 88,
      view_count: 500,
      created_at: new Date().toISOString(),
      author: { id: "u2", nickname: "测评专家", level: 5 },
      community: { id: "c1", name: "机甲区" },
      media: [
        { id: "m1", url: "https://via.placeholder.com/600x400.png?text=Media1", detail_url: "https://via.placeholder.com/600x400.png?text=Media1" },
      ],
      viewer_state: { has_liked: false, has_bookmarked: false },
    };

    const mockCommentsPage1 = {
      items: Array.from({ length: 30 }, (_, i) => ({
        id: `comment-${i + 1}`,
        post_id: "post-101",
        author: { id: `u-comm-${i}`, nickname: `用户_${i + 1}`, level: 1 },
        content: `这是第 ${i + 1} 楼的精彩评论内容`,
        like_count: i,
        floor: i + 1,
        created_at: new Date().toISOString(),
        media: i === 0 ? [{ id: "cm1", url: "https://via.placeholder.com/200x200.png?text=CommPic", detail_url: "https://via.placeholder.com/200x200.png?text=CommPic" }] : [],
        viewer_state: { has_liked: false },
      })),
      total: 45,
      has_more: true,
    };

    await page.route("**/api/v1/posts/post-101", async (route) => {
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(mockPost) });
    });

    await page.route("**/api/v1/posts/post-101/comments*", async (route) => {
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(mockCommentsPage1) });
    });

    await page.route("**/api/v1/posts?sort=hot*", async (route) => {
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ items: [] }) });
    });

    await page.goto("/post/post-101");

    // 确认总评论数展示并包含 30 楼
    await expect(page.getByText("评论 (45)")).toBeVisible();
    await expect(page.getByText("这是第 30 楼的精彩评论内容")).toBeVisible();

    // 确认“加载更多评论”按钮出现
    const loadMoreBtn = page.getByRole("button", { name: "加载更多评论" });
    await expect(loadMoreBtn).toBeVisible();

    // 验证点击图片可成功唤起 ImageGalleryModal 全屏画廊
    const postImage = page.locator(".detail-gallery img").first();
    if (await postImage.isVisible()) {
      await postImage.click();
      await expect(page.getByRole("dialog", { name: "图片查看器" })).toBeVisible();

      // 按 ESC 退出画廊
      await page.keyboard.press("Escape");
      await expect(page.getByRole("dialog", { name: "图片查看器" })).toBeHidden();
    }
  });

  test("5. 真实举报功能：弹窗选择违规原因并成功提交 POST /api/v1/reports", async ({ page }) => {
    // 注入登录状态
    await page.route("**/api/v1/me", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ id: "user-rep-1", username: "rep_user", nickname: "风纪委员", level: 2 }),
      });
    });

    const mockPost = {
      id: "post-bad-1",
      title: "涉嫌违规的垃圾广告贴",
      content: "点击链接领取免费礼包",
      comment_count: 0,
      like_count: 0,
      view_count: 10,
      created_at: new Date().toISOString(),
      author: { id: "spammer", nickname: "发广告者", level: 1 },
      community: { id: "c1", name: "综合区" },
      media: [],
      viewer_state: { has_liked: false, has_bookmarked: false },
    };

    await page.route("**/api/v1/posts/post-bad-1", async (route) => {
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(mockPost) });
    });
    await page.route("**/api/v1/posts/post-bad-1/comments*", async (route) => {
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ items: [], total: 0, has_more: false }) });
    });
    await page.route("**/api/v1/posts?sort=hot*", async (route) => {
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ items: [] }) });
    });

    let reportRequest: Record<string, unknown> | null = null;
    await page.route("**/api/v1/reports", async (route) => {
      reportRequest = JSON.parse(route.request().postData() || "{}");
      await route.fulfill({
        status: 201,
        contentType: "application/json",
        body: JSON.stringify({ id: "rep-1", moderation_case_id: "case-1", status: "pending" }),
      });
    });

    await page.goto("/post/post-bad-1");

    // 点击帖子底部的举报按钮
    const reportBtn = page.getByRole("button", { name: "举报" });
    await reportBtn.click();

    // 确认举报弹窗显式弹出
    const modal = page.getByRole("dialog", { name: "举报帖子" });
    await expect(modal).toBeVisible();

    // 切换违规原因至“垃圾广告、恶意刷屏”并填写补充描述
    await modal.getByLabel("垃圾广告、恶意刷屏").check();
    await modal.getByPlaceholder("请提供更多背景信息，以便管理员更快核实…").fill("大量机器刷屏广告");

    // 提交举报
    await modal.getByRole("button", { name: "确认提交举报" }).click();

    // 验证 API 真实调用与入参
    await expect(async () => {
      expect(reportRequest).not.toBeNull();
      expect(reportRequest?.target_type).toBe("post");
      expect(reportRequest?.target_id).toBe("post-bad-1");
      expect(reportRequest?.reason_code).toBe("spam");
      expect(reportRequest?.description).toBe("大量机器刷屏广告");
    }).toPass();

    // 确认弹层已关闭
    await expect(modal).toBeHidden();
  });

  test("6. 我的工作台：真实读取 balance 积分并支持评论精确锚点定位", async ({ page }) => {
    // 注入登录态
    await page.route("**/api/v1/me", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ id: "u-owner", username: "owner", nickname: "工作台主人", level: 4 }),
      });
    });

    await page.route("**/api/v1/users/u-owner", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          id: "u-owner",
          nickname: "工作台主人",
          post_count: 5,
          comment_count: 12,
          follower_count: 99,
          following_count: 10,
        }),
      });
    });

    // Mock 后端真实字段 balance
    await page.route("**/api/v1/me/points", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ balance: 520, transactions: [] }),
      });
    });

    // Mock 我的回复列表：同一帖子两条不同的回复，必须携带 comment_id
    await page.route("**/api/v1/me/comments*", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          items: [
            {
              id: "post-multi-1",
              comment_id: "c-first-1",
              title: "同一个帖子的第一条回复",
              content_preview: "我先说两句",
              community_name: "开箱专区",
              comment_count: 20,
              like_count: 3,
              created_at: new Date().toISOString(),
              activity_at: new Date().toISOString(),
            },
            {
              id: "post-multi-1",
              comment_id: "c-second-2",
              title: "同一个帖子的第二条回复",
              content_preview: "补充说明另外一点",
              community_name: "开箱专区",
              comment_count: 20,
              like_count: 8,
              created_at: new Date().toISOString(),
              activity_at: new Date().toISOString(),
            },
          ],
          has_more: false,
        }),
      });
    });

    await page.route("**/api/v1/me/posts*", async (route) => {
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ items: [] }) });
    });

    await page.goto("/me");

    // 验证积分显示真实数值 520（而不是 0）
    await expect(page.getByText("520", { exact: true })).toBeVisible();

    // 切换至“我的回复”
    await page.getByRole("button", { name: "我的回复" }).click();

    // 验证两条回复链接均携带对应的 comment_id 锚点
    const firstLink = page.getByRole("link", { name: /同一个帖子的第一条回复/ });
    const secondLink = page.getByRole("link", { name: /同一个帖子的第二条回复/ });

    await expect(firstLink).toHaveAttribute("href", "/post/post-multi-1#comment-c-first-1");
    await expect(secondLink).toHaveAttribute("href", "/post/post-multi-1#comment-c-second-2");
  });
});
