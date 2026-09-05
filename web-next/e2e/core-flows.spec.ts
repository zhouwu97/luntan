import { test, expect } from "@playwright/test";

test.describe("Web-Next 核心业务链路验收套件", () => {
  test("1. PC 登录：密码登录与验证码登录切换正常", async ({ page }) => {
    await page.goto("/login");

    // 默认展示密码登录与邮箱、密码输入框
    const emailInput = page.getByPlaceholder("请输入邮箱地址");
    await expect(emailInput).toBeVisible();
    const passwordInput = page.getByPlaceholder("请输入密码");
    await expect(passwordInput).toBeVisible();

    // 切换到“验证码登录”
    const codeLoginTab = page.getByRole("button", { name: "验证码登录", exact: true });
    await codeLoginTab.click();

    // 此时应显示验证码输入框与获取验证码按钮
    const sendCodeBtn = page.getByRole("button", { name: "获取验证码" });
    await expect(sendCodeBtn).toBeVisible();

    // 再次切换回“密码登录”
    const pwdLoginTab = page.getByRole("button", { name: "密码登录", exact: true });
    await pwdLoginTab.click();
    await expect(passwordInput).toBeVisible();
  });

  test("2. 免验证码注册：支持免验证码直接注册表单契约", async ({ page }) => {
    await page.goto("/login");

    // 切换至“注册”
    const registerTab = page.getByRole("button", { name: "注册" });
    await registerTab.click();

    // 验证注册表单字段：邮箱、密码、确认密码、昵称（可选）
    const emailInput = page.getByPlaceholder("请输入邮箱地址");
    const passwordInput = page.getByPlaceholder("至少 8 位密码");
    const confirmPasswordInput = page.getByPlaceholder("再次输入密码");
    await expect(emailInput).toBeVisible();
    await expect(passwordInput).toBeVisible();
    await expect(confirmPasswordInput).toBeVisible();

    // 填入基础信息，验证码不强制填写，客户端不会提示“请输入验证码”
    await emailInput.fill("test_new_user@example.com");
    await passwordInput.fill("Password123!");
    await confirmPasswordInput.fill("Password123!");

    // 模拟注册 API 返回合法的 access_token 与用户信息，验证免密注册成功并建立会话
    let submittedPayload: Record<string, unknown> | null = null;
    await page.route("**/api/v1/auth/register", async (route) => {
      submittedPayload = JSON.parse(route.request().postData() || "{}");
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          access_token: "mock-token-reg-123",
          token_type: "Bearer",
          expires_in: 3600,
          user: {
            id: "user-new-1",
            username: "testuser",
            nickname: "测试萌新",
            level: 1,
          },
        }),
      });
    });

    const submitBtn = page.getByRole("button", { name: "注册并进入社区" });
    await submitBtn.click();

    // 确认已向后端发起注册请求，且没有客户端强制阻断
    await expect(async () => {
      expect(submittedPayload).not.toBeNull();
      expect(submittedPayload?.email).toBe("test_new_user@example.com");
    }).toPass();

    // 验证注册成功后真实建立登录态并跳转回首页，无报错
    await expect(page).toHaveURL("/");
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

    // 拦截刷新以注入有效登录凭据
    await page.route("**/api/v1/auth/refresh", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ access_token: "mock-valid-token", expires_in: 3600 }),
      });
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

  test("4. 帖子与评论：30+评论真分页与全屏图片画廊查看器（正文多图与评论图片强校验）", async ({ page }) => {
    const svgImg1 = "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='600' height='400'%3E%3Crect fill='%233b82f6' width='100%25' height='100%25'/%3E%3Ctext x='50%25' y='50%25' fill='%23ffffff' font-size='20' text-anchor='middle'%3EImage 1%3C/text%3E%3C/svg%3E";
    const svgImg2 = "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='600' height='400'%3E%3Crect fill='%2310b981' width='100%25' height='100%25'/%3E%3Ctext x='50%25' y='50%25' fill='%23ffffff' font-size='20' text-anchor='middle'%3EImage 2%3C/text%3E%3C/svg%3E";
    const svgImg3 = "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='600' height='400'%3E%3Crect fill='%23f59e0b' width='100%25' height='100%25'/%3E%3Ctext x='50%25' y='50%25' fill='%23ffffff' font-size='20' text-anchor='middle'%3EImage 3%3C/text%3E%3C/svg%3E";
    const svgCommImg = "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='200' height='200'%3E%3Crect fill='%238b5cf6' width='100%25' height='100%25'/%3E%3Ctext x='50%25' y='50%25' fill='%23ffffff' font-size='16' text-anchor='middle'%3ECommPic%3C/text%3E%3C/svg%3E";

    // Mock 帖子与 30 条初始评论
    const mockPost = {
      id: "post-101",
      title: "长篇热门测评与大图分享",
      content: "本期评测玩具包含多张细节实拍图片",
      comment_count: 45,
      like_count: 88,
      bookmark_count: 12,
      view_count: 500,
      created_at: new Date().toISOString(),
      author: { id: "u2", nickname: "测评专家", level: 5 },
      community: { id: "c1", name: "机甲区" },
      media: [
        { id: "m1", url: svgImg1, detail_url: svgImg1, original_url: svgImg1, alt_text: "测评图1" },
        { id: "m2", url: svgImg2, detail_url: svgImg2, original_url: svgImg2, alt_text: "测评图2" },
        { id: "m3", url: svgImg3, detail_url: svgImg3, original_url: svgImg3, alt_text: "测评图3" },
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
        media: i === 0 ? [{ id: "cm1", url: svgCommImg, detail_url: svgCommImg, original_url: svgCommImg, alt_text: "评论配图1" }] : [],
        viewer_state: { has_liked: false, has_disliked: false },
      })),
      total: 45,
      has_more: true,
    };

    await page.route("**/api/v1/posts/post-101*", async (route) => {
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

    // 强制强校验：正文必须出现 3 张图片
    const postImages = page.locator(".detail-gallery img");
    await expect(postImages).toHaveCount(3);

    // 点击第 1 张图片，画廊弹窗必须出现，且计数为 1 / 3
    await postImages.first().click();
    const galleryModal = page.getByRole("dialog", { name: "图片查看器" });
    await expect(galleryModal).toBeVisible();
    await expect(galleryModal.getByText("1 / 3")).toBeVisible();

    // 切换至下一张 -> 2 / 3
    await galleryModal.getByRole("button", { name: "下一张" }).click();
    await expect(galleryModal.getByText("2 / 3")).toBeVisible();

    // 切换回上一张 -> 1 / 3
    await galleryModal.getByRole("button", { name: "上一张" }).click();
    await expect(galleryModal.getByText("1 / 3")).toBeVisible();

    // 点击关闭按钮退出画廊
    await galleryModal.getByRole("button", { name: "关闭查看器" }).click();
    await expect(galleryModal).toBeHidden();

    // 强制强校验：评论区第 1 条评论必须有配图，且点击能打开全屏画廊
    const commentImage = page.locator("#comment-comment-1 .comment-media-grid img, .comment-media-grid img").first();
    await expect(commentImage).toBeVisible();
    await commentImage.click();
    await expect(galleryModal).toBeVisible();
    await expect(galleryModal.getByText("1 / 1")).toBeVisible();

    // 按 ESC 键关闭画廊
    await page.keyboard.press("Escape");
    await expect(galleryModal).toBeHidden();
  });

  test("5. 真实举报功能：弹窗选择违规原因并成功提交 POST /api/v1/reports", async ({ page }) => {
    await page.route("**/api/v1/auth/refresh", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ access_token: "mock-valid-token", expires_in: 3600 }),
      });
    });

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

    await page.route("**/api/v1/posts/post-bad-1*", async (route) => {
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
    // 拦截刷新以注入有效登录凭据
    await page.route("**/api/v1/auth/refresh", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ access_token: "mock-valid-token", expires_in: 3600 }),
      });
    });

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

    // 拦截详情页帖子数据
    await page.route("**/api/v1/posts/post-multi-1*", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          id: "post-multi-1",
          title: "同一个帖子的第一条回复",
          content: "这是帖子的主要讨论正文内容",
          comment_count: 50,
          like_count: 10,
          view_count: 100,
          created_at: new Date().toISOString(),
          author: { id: "u-author", nickname: "发帖作者", level: 2 },
          community: { id: "c1", name: "开箱专区" },
          viewer_state: { has_liked: false, has_bookmarked: false },
        }),
      });
    });

    // 模拟首屏评论列表中并不包含 c-first-1（模拟非首屏评论）
    await page.route("**/api/v1/posts/post-multi-1/comments*", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          items: [
            {
              id: "c-other-0",
              post_id: "post-multi-1",
              author: { id: "u-other", nickname: "其他楼层用户", level: 1 },
              content: "这是首屏其他普通楼层评论",
              floor: 1,
              created_at: new Date().toISOString(),
              viewer_state: {},
            },
          ],
          total: 50,
          has_more: true,
        }),
      });
    });

    let contextRequested = false;
    await page.route("**/api/v1/comments/c-first-1/context", async (route) => {
      contextRequested = true;
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          post_id: "post-multi-1",
          comment_id: "c-first-1",
          root_id: "c-first-1",
          is_root: true,
          root_comment: {
            id: "c-first-1",
            post_id: "post-multi-1",
            author: { id: "u-owner", nickname: "工作台主人", level: 4 },
            content: "我先说两句",
            floor: 35,
            like_count: 3,
            reply_count: 0,
            created_at: new Date().toISOString(),
            viewer_state: {},
          },
        }),
      });
    });

    // 真实点击“我的回复”链接
    await firstLink.click();

    // 验证跳转到详情页且携带目标 hash
    await expect(page).toHaveURL("/post/post-multi-1#comment-c-first-1");

    // 验证 Context 接口被调用以获取非首屏评论
    await expect(async () => {
      expect(contextRequested).toBe(true);
    }).toPass();

    // 验证目标评论节点被成功挂载至 DOM，并添加了 comment-highlight 过渡高亮样式
    const targetCommentEl = page.locator("#comment-c-first-1");
    await expect(targetCommentEl).toBeVisible();
    await expect(targetCommentEl).toContainText("我先说两句");
    await expect(targetCommentEl).toHaveClass(/comment-highlight/);
  });

  test("7. 评论锚点：楼中楼深层回复通过 Context 自动展开回复抽屉并精准定位高亮", async ({ page }) => {
    // 拦截帖子数据
    await page.route("**/api/v1/posts/post-nested-10*", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          id: "post-nested-10",
          title: "嵌套回复测试帖子",
          content: "测试楼中楼锚点唤起与定位",
          comment_count: 10,
          like_count: 5,
          view_count: 60,
          created_at: new Date().toISOString(),
          author: { id: "u-author", nickname: "楼主", level: 2 },
          community: { id: "c1", name: "机甲区" },
          viewer_state: {},
        }),
      });
    });

    // 首屏只包含根评论 c-root-10
    const mockRootComment = {
      id: "c-root-10",
      post_id: "post-nested-10",
      author: { id: "u-root", nickname: "根评论作者", level: 3 },
      content: "这是根评论主楼层",
      floor: 2,
      reply_count: 5,
      created_at: new Date().toISOString(),
      viewer_state: {},
    };

    await page.route("**/api/v1/posts/post-nested-10/comments*", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          items: [mockRootComment],
          total: 1,
          has_more: false,
        }),
      });
    });

    // 模拟子回复的 Context 查询
    const mockChildReply = {
      id: "c-child-99",
      post_id: "post-nested-10",
      author: { id: "u-child", nickname: "楼中楼辩友", level: 1 },
      content: "这是深层楼中楼精准回复内容",
      root_id: "c-root-10",
      parent_id: "c-root-10",
      created_at: new Date().toISOString(),
      viewer_state: {},
    };

    await page.route("**/api/v1/comments/c-child-99/context", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          post_id: "post-nested-10",
          comment_id: "c-child-99",
          root_id: "c-root-10",
          parent_id: "c-root-10",
          is_root: false,
          root_comment: mockRootComment,
          target_comment: mockChildReply,
        }),
      });
    });

    // 模拟回复抽屉请求根评论的 replies
    await page.route("**/api/v1/comments/c-root-10/replies*", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          items: [mockChildReply],
          has_more: false,
        }),
      });
    });

    // 直接通过 URL 携带楼中楼回复 hash 进入帖子
    await page.goto("/post/post-nested-10#comment-c-child-99");

    // 验证楼中楼弹窗被自动打开，且目标子回复成功呈现并获得高亮
    const childReplyEl = page.locator(".comment-reply-modal #comment-c-child-99");
    await expect(childReplyEl).toBeVisible();
    await expect(childReplyEl).toContainText("这是深层楼中楼精准回复内容");
    await expect(childReplyEl).toHaveClass(/comment-highlight/);
  });

  test("8. 移动端画廊与整卡点击：移动端图片查看与首页整卡点击跳转详情", async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 667 });

    const svgImg = "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='600' height='400'%3E%3Crect fill='%233b82f6' width='100%25' height='100%25'/%3E%3C/svg%3E";
    const mockPost = {
      id: "post-mobile-1",
      title: "移动端专用测评贴",
      content: "测试移动端全屏查看图片与整卡点击体验",
      comment_count: 1,
      like_count: 5,
      bookmark_count: 2,
      view_count: 88,
      created_at: new Date().toISOString(),
      author: { id: "u-m", nickname: "掌上评测员", level: 3 },
      community: { id: "c1", name: "机甲区" },
      media: [{ id: "m1", url: svgImg, detail_url: svgImg, original_url: svgImg, alt_text: "移动端配图" }],
      viewer_state: { has_liked: false, has_bookmarked: false },
    };

    await page.route("**/api/v1/posts/post-mobile-1*", async (route) => {
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(mockPost) });
    });
    await page.route("**/api/v1/posts/post-mobile-1/comments*", async (route) => {
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ items: [], total: 0, has_more: false }) });
    });
    await page.route("**/api/v1/posts?sort=hot*", async (route) => {
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ items: [] }) });
    });

    // 1. 移动端视口下正文图片点击画廊
    await page.goto("/post/post-mobile-1");
    const mobilePostImg = page.locator(".detail-gallery img").first();
    await expect(mobilePostImg).toBeVisible();
    await mobilePostImg.click();
    const modal = page.getByRole("dialog", { name: "图片查看器" });
    await expect(modal).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(modal).toBeHidden();

    // 2. 首页整卡点击跳转验证
    await page.route(/\/api\/v1\/feed/, async (route) => {
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ items: [mockPost], has_more: false }) });
    });
    await page.route(/\/api\/v1\/communities/, async (route) => {
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ items: [{ id: "c1", name: "机甲区", member_count: 100 }] }) });
    });

    await page.evaluate(() => {
      try {
        localStorage.clear();
      } catch {}
    });

    await page.goto("/");
    const card = page.locator(".post-card[data-post-id='post-mobile-1']");
    await expect(card).toBeVisible();
    // 点击卡片上的空白区域（例如靠近边缘）触发整卡路由跳转
    await card.click({ position: { x: 8, y: 8 } });
    await page.waitForURL("**/post/post-mobile-1*");
    expect(page.url()).toContain("/post/post-mobile-1");
  });

  test("9. 版本元数据：/api/version 正确暴露 Web 构建 SHA 与状态契约", async ({ request }) => {
    const res = await request.get("/api/version");
    expect(res.status()).toBe(200);
    const body = await res.json();
    expect(body.status).toBe("ok");
    expect(body.web).toBeDefined();
    expect(body.web.commit).toBeDefined();
    expect(body.web.build_time).toBeDefined();
  });

  test("10. 真实媒体网关与 Fallback 容灾：detail 返回 404 时正文画廊与评论图自动回退至 original 并正常渲染", async ({ page }) => {
    const validSvgOriginal = "<svg xmlns='http://www.w3.org/2000/svg' width='800' height='600'><rect fill='#3b82f6' width='100%' height='100%'/><text x='50%' y='50%' fill='#ffffff' font-size='24' text-anchor='middle'>Original Fallback Success</text></svg>";
    const validSvgCommOriginal = "<svg xmlns='http://www.w3.org/2000/svg' width='400' height='400'><rect fill='#10b981' width='100%' height='100%'/><text x='50%' y='50%' fill='#ffffff' font-size='20' text-anchor='middle'>Comm Original Fallback Success</text></svg>";

    // 1. 正文媒体：detail 返回 404 异常，original 返回 200
    await page.route("**/api/v1/media-file/media_test_fallback/detail", async (route) => {
      await route.fulfill({ status: 404, contentType: "application/json", body: JSON.stringify({ message: "Variant not found" }) });
    });
    await page.route("**/api/v1/media-file/media_test_fallback/original", async (route) => {
      await route.fulfill({ status: 200, contentType: "image/svg+xml", body: validSvgOriginal });
    });

    // 2. 评论媒体：thumb 404，detail 404，original 返回 200
    await page.route("**/api/v1/media-file/media_comm_fallback/thumb", async (route) => {
      await route.fulfill({ status: 404, contentType: "application/json", body: JSON.stringify({ message: "Thumb variant not found" }) });
    });
    await page.route("**/api/v1/media-file/media_comm_fallback/detail", async (route) => {
      await route.fulfill({ status: 404, contentType: "application/json", body: JSON.stringify({ message: "Detail variant not found" }) });
    });
    await page.route("**/api/v1/media-file/media_comm_fallback/original", async (route) => {
      await route.fulfill({ status: 200, contentType: "image/svg+xml", body: validSvgCommOriginal });
    });

    const mockPostWithFallback = {
      id: "post-fallback-1",
      title: "媒体网关回退测试贴",
      content: "测试详情图与评论图 404 情况下自动回退至原图渲染",
      comment_count: 1,
      like_count: 3,
      bookmark_count: 1,
      view_count: 50,
      created_at: new Date().toISOString(),
      author: { id: "u-fallback", nickname: "容灾测试员", level: 2 },
      community: { id: "c1", name: "机甲区" },
      media: [
        {
          id: "media_test_fallback",
          url: "/api/v1/media-file/media_test_fallback/detail",
          detail_url: "/api/v1/media-file/media_test_fallback/detail",
          original_url: "/api/v1/media-file/media_test_fallback/original",
          thumb_url: "/api/v1/media-file/media_test_fallback/detail",
          alt_text: "需容灾回退的大图",
        },
      ],
      viewer_state: { has_liked: false, has_bookmarked: false },
    };

    const mockCommentsWithFallback = {
      items: [
        {
          id: "comm-fb-1",
          post_id: "post-fallback-1",
          author: { id: "u-comm-fb", nickname: "回退验证员", level: 1 },
          content: "这是带容灾回退图片的评论",
          floor: 1,
          created_at: new Date().toISOString(),
          media: [
            {
              id: "media_comm_fallback",
              url: "/api/v1/media-file/media_comm_fallback/detail",
              thumb_url: "/api/v1/media-file/media_comm_fallback/thumb",
              detail_url: "/api/v1/media-file/media_comm_fallback/detail",
              original_url: "/api/v1/media-file/media_comm_fallback/original",
              alt_text: "评论需容灾图",
            },
          ],
          viewer_state: { has_liked: false, has_disliked: false },
        },
      ],
      total: 1,
      has_more: false,
    };

    await page.route("**/api/v1/posts/post-fallback-1*", async (route) => {
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(mockPostWithFallback) });
    });

    await page.route("**/api/v1/posts/post-fallback-1/comments*", async (route) => {
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(mockCommentsWithFallback) });
    });

    await page.route("**/api/v1/posts?sort=hot*", async (route) => {
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ items: [] }) });
    });

    await page.goto("/post/post-fallback-1");

    // 1. 验证正文图片画廊回退
    const postImg = page.locator(".detail-gallery img").first();
    await expect(postImg).toBeVisible();
    await postImg.click();

    const modal = page.getByRole("dialog", { name: "图片查看器" });
    await expect(modal).toBeVisible();

    const mainImg = modal.locator(".gallery-main-image");
    await expect(mainImg).toHaveAttribute("src", /media_test_fallback\/original/);
    await expect(mainImg).toBeVisible();

    await page.keyboard.press("Escape");
    await expect(modal).toBeHidden();

    // 2. 验证评论图片缩略图与画廊回退（thumb 404 / detail 404 → original 200）
    const commentImg = page.locator("#comment-comm-fb-1 .comment-media-grid img").first();
    await expect(commentImg).toBeVisible();
    await expect(commentImg).toHaveAttribute("src", /media_comm_fallback\/original/);

    // 点击评论缩略图，验证评论画廊大图同样回退到 original
    await commentImg.click();
    await expect(modal).toBeVisible();
    await expect(modal.locator(".gallery-main-image")).toHaveAttribute("src", /media_comm_fallback\/original/);
    await page.keyboard.press("Escape");
    await expect(modal).toBeHidden();
  });

  test("11. 真实异步高延迟解耦：帖子快速响应，正文先行展示就绪，绝不被高延迟评论阻断", async ({ page }) => {
    const mockPost = {
      id: "post-async-delay-1",
      title: "高延迟异步隔离测试帖",
      content: "正文必须先秒开展示，评论在 1 秒多后慢速到达",
      comment_count: 5,
      like_count: 10,
      bookmark_count: 2,
      view_count: 100,
      created_at: new Date().toISOString(),
      author: { id: "u-async", nickname: "解耦测试员", level: 3 },
      community: { id: "c1", name: "机甲区" },
      media: [],
      viewer_state: { has_liked: false, has_bookmarked: false },
    };

    // 帖子正文 80ms 快速响应
    await page.route("**/api/v1/posts/post-async-delay-1*", async (route) => {
      await new Promise((resolve) => setTimeout(resolve, 80));
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(mockPost) });
    });

    // 评论接口 2000ms 高延迟响应
    await page.route("**/api/v1/posts/post-async-delay-1/comments*", async (route) => {
      await new Promise((resolve) => setTimeout(resolve, 2000));
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          items: [{ id: "comm-slow-1", post_id: "post-async-delay-1", author: { id: "u1", nickname: "慢速评论者" }, content: "这是一条慢速到达的评论", created_at: new Date().toISOString() }],
          total: 1,
          has_more: false,
        }),
      });
    });

    // 推荐流 2500ms 极高延迟
    await page.route("**/api/v1/posts?sort=hot*", async (route) => {
      await new Promise((resolve) => setTimeout(resolve, 2500));
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ items: [] }) });
    });

    await page.goto("/post/post-async-delay-1");

    // 核心断言 1：正文在进入页面后 600ms 内优先渲染展示
    await expect(page.getByRole("heading", { name: "高延迟异步隔离测试帖" })).toBeVisible({ timeout: 600 });
    await expect(page.getByText("正文必须先秒开展示，评论在 1 秒多后慢速到达")).toBeVisible({ timeout: 600 });

    // 核心断言 2：正文已就绪时，设置了 1200ms 高延迟的评论绝对尚未呈现（证明非阻塞异步解耦）
    await expect(page.getByText("这是一条慢速到达的评论")).toBeHidden();
    await expect(page.locator("#comments")).toBeVisible();

    // 核心断言 3：最终慢速评论到达并成功呈现
    await expect(page.getByText("这是一条慢速到达的评论")).toBeVisible({ timeout: 3500 });
  });

  test("12. 评论去重与防竞态：正文返回不触发二次请求，快速切换排序单一源驱动", async ({ page }) => {
    let commentsRequestCount = 0;

    const mockPost = {
      id: "post-dedup-1",
      title: "评论防竞态防重复请求测试帖",
      content: "测试初次加载与正文返回不触发重复评论拉取",
      comment_count: 2,
      like_count: 4,
      bookmark_count: 1,
      view_count: 80,
      created_at: new Date().toISOString(),
      author: { id: "u-author-target", nickname: "发帖作者", level: 4 },
      community: { id: "c1", name: "机甲区" },
      media: [],
      viewer_state: { has_liked: false, has_bookmarked: false },
    };

    // 延迟 150ms 返回正文，保证有明显的 post 从 null -> post 的转变
    await page.route("**/api/v1/posts/post-dedup-1*", async (route) => {
      await new Promise((resolve) => setTimeout(resolve, 150));
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(mockPost) });
    });

    await page.route("**/api/v1/posts/post-dedup-1/comments*", async (route) => {
      commentsRequestCount++;
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          items: [{ id: "c1", post_id: "post-dedup-1", author: { id: "u2", nickname: "评友" }, content: "第一条评论", created_at: new Date().toISOString() }],
          total: 1,
          has_more: false,
        }),
      });
    });

    await page.route("**/api/v1/posts?sort=hot*", async (route) => {
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ items: [] }) });
    });

    await page.goto("/post/post-dedup-1");
    await expect(page.getByRole("heading", { name: "评论防竞态防重复请求测试帖" })).toBeVisible();
    await expect(page.getByText("第一条评论")).toBeVisible();

    // 等待 300ms 确保 post 完成后没有触发第 2 次评论请求
    await page.waitForTimeout(300);
    expect(commentsRequestCount).toBe(1);

    // 切换排序为最新
    const latestBtn = page.getByRole("button", { name: "最新" });
    await latestBtn.click();
    await page.waitForTimeout(200);
    // 验证切换只触发了一次新的请求（总数变为 2），没有多重请求
    expect(commentsRequestCount).toBe(2);
  });

  test("13. 点赞与收藏状态单一源：移动端正文与底部浮动栏状态双向 100% 同步", async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 667 });

    const mockPost = {
      id: "post-sync-state-1",
      title: "双向状态同步测试贴",
      content: "测试正文与移动端底部栏的点赞与收藏状态单一源同步",
      comment_count: 0,
      like_count: 10,
      bookmark_count: 5,
      view_count: 120,
      created_at: new Date().toISOString(),
      author: { id: "u-sync", nickname: "同步测试员", level: 3 },
      community: { id: "c1", name: "机甲区" },
      media: [],
      viewer_state: { has_liked: false, has_bookmarked: false },
    };

    await page.route("**/api/v1/posts/post-sync-state-1*", async (route) => {
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(mockPost) });
    });

    await page.route("**/api/v1/posts/post-sync-state-1/comments*", async (route) => {
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ items: [], total: 0, has_more: false }) });
    });

    await page.route("**/api/v1/posts?sort=hot*", async (route) => {
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ items: [] }) });
    });

    await page.route("**/api/v1/posts/post-sync-state-1/like", async (route) => {
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ status: "ok" }) });
    });

    await page.route("**/api/v1/posts/post-sync-state-1/bookmark", async (route) => {
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ status: "ok" }) });
    });

    await page.route("**/api/v1/auth/refresh", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ access_token: "mock-valid-token-13", expires_in: 3600 }),
      });
    });

    await page.route("**/api/v1/me", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ id: "u-logged-13", username: "tester13", nickname: "测试用户13", role: "user" }),
      });
    });

    await page.goto("/post/post-sync-state-1");
    await expect(page.getByRole("heading", { name: "双向状态同步测试贴" })).toBeVisible();

    // 1. 在正文区域点击点赞
    const articleLikeBtn = page.locator(".detail-stats button").filter({ hasText: "点赞" });
    const bottomLikeBtn = page.locator(".composer.mobile-only .composer-side button").nth(0);

    await expect(articleLikeBtn).not.toHaveClass(/selected/);
    await expect(bottomLikeBtn).not.toHaveClass(/selected/);
    await expect(bottomLikeBtn).toHaveAttribute("aria-label", "点赞");

    await articleLikeBtn.click();

    // 验证正文与移动端底部栏【同时】变亮，计数同步增加
    await expect(articleLikeBtn).toHaveClass(/selected/);
    await expect(bottomLikeBtn).toHaveClass(/selected/);
    await expect(bottomLikeBtn).toHaveAttribute("aria-label", "已点赞");
    await expect(articleLikeBtn).toContainText("11 点赞");
    await expect(bottomLikeBtn).toContainText("11");

    // 2. 在移动端底部栏点击收藏
    const bottomBookmarkBtn = page.locator(".composer.mobile-only .composer-side button").nth(1);
    const articleBookmarkBtn = page.locator(".detail-stats button").filter({ hasText: "收藏" });

    await expect(bottomBookmarkBtn).not.toHaveClass(/selected/);
    await expect(articleBookmarkBtn).not.toHaveClass(/selected/);
    await expect(bottomBookmarkBtn).toHaveAttribute("aria-label", "收藏");

    await bottomBookmarkBtn.click();

    // 验证底部与正文收藏【同时】变亮，计数同步增加
    await expect(bottomBookmarkBtn).toHaveClass(/selected/);
    await expect(articleBookmarkBtn).toHaveClass(/selected/);
    await expect(bottomBookmarkBtn).toHaveAttribute("aria-label", "已收藏");
    await expect(articleBookmarkBtn).toContainText("6 收藏");
    await expect(bottomBookmarkBtn).toContainText("6");
  });

  test("14. 首页默认入口与排序语义：/ 默认进入最新且 URL 保持干净，推荐严格按管理员精选无自动回退", async ({ page }) => {
    // 监听所有 feed 流请求
    const requestedSorts: string[] = [];
    await page.route("**/api/v1/feed/latest*", async (route) => {
      const url = new URL(route.request().url());
      const sort = url.searchParams.get("sort") || "none";
      requestedSorts.push(sort);

      if (sort === "latest") {
        await route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify({
            items: [
              {
                id: "post-latest-1",
                title: "最新帖子第一篇",
                content: "最新版块的测试内容",
                comment_count: 12,
                like_count: 8,
                view_count: 90,
                created_at: new Date().toISOString(),
                author: { id: "u-lat-1", nickname: "最新作者1", level: 2 },
                community: { id: "c1", name: "酱紫社区" },
                media: [],
                viewer_state: { has_liked: false, has_bookmarked: false },
              },
            ],
            total: 1,
            has_more: false,
          }),
        });
      } else if (sort === "recommended") {
        // 推荐流：管理员未配置推荐时返回 0 篇，验证绝对无自动 fallback
        await route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify({ items: [], total: 0, has_more: false }),
        });
      } else if (sort === "hot") {
        await route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify({
            items: [
              {
                id: "post-hot-1",
                title: "热门帖子不应自动补位到推荐",
                content: "热门内容",
                comment_count: 99,
                like_count: 88,
                view_count: 999,
                created_at: new Date().toISOString(),
                author: { id: "u-hot-1", nickname: "热门作者", level: 5 },
                community: { id: "c1", name: "机甲区" },
                media: [],
                viewer_state: { has_liked: false, has_bookmarked: false },
              },
            ],
            total: 1,
            has_more: false,
          }),
        });
      } else {
        await route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify({ items: [], total: 0, has_more: false }),
        });
      }
    });

    await page.route("**/api/v1/communities*", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          items: [{ id: "c1", name: "酱紫社区", slug: "jiangzi", post_count: 10 }],
        }),
      });
    });

    // 访问根路径 /
    await page.goto("/");

    // 1. 先等待最新帖子正常渲染（确保网络请求与渲染均已完成）
    await expect(page.getByRole("heading", { name: "最新帖子第一篇" })).toBeVisible();

    // 2. 验证 URL 保持纯净的 /，不强加 ?sort=latest
    expect(new URL(page.url()).pathname).toBe("/");
    expect(new URL(page.url()).search).toBe("");

    // 3. 验证“最新”Tab 默认激活高亮
    const latestTab = page.locator(".feed-tabs button.tab").filter({ hasText: "最新" });
    await expect(latestTab).toBeVisible();
    await expect(latestTab).toHaveAttribute("aria-selected", "true");
    await expect(latestTab).toHaveClass(/active/);

    // 4. 验证首次请求的 sort 参数包含 latest
    expect(requestedSorts).toContain("latest");
    expect(requestedSorts[0]).toBe("latest");

    // 5. 点击“推荐”Tab，验证切换并测试无 fallback 逻辑
    const recommendedTab = page.locator(".feed-tabs button.tab").filter({ hasText: "推荐" });
    await recommendedTab.click();

    await expect(page).toHaveURL("/?sort=recommended");
    await expect(recommendedTab).toHaveAttribute("aria-selected", "true");

    // 验证推荐列表空态：只展示真实说明，绝不把热门补位进来
    await expect(page.getByRole("heading", { name: "暂无推荐内容" })).toBeVisible();
    await expect(page.getByText("管理员推荐的精选帖子会出现在这里")).toBeVisible();
    await expect(page.getByText("热门帖子不应自动补位到推荐")).toBeHidden();

    // 6. 点击“最新”返回，URL 恢复干净 /，再次展示最新帖子
    await latestTab.click();
    await expect(page).toHaveURL("/");
    await expect(page.getByRole("heading", { name: "最新帖子第一篇" })).toBeVisible();
  });

  test("15. 首页人工推荐管理：权限隔离、搜索帖子、添加位次与重新排序保存", async ({ page }) => {
    // 1. 模拟非管理员用户访问，应被守卫拦截呈现“访问受限”
    await page.route("**/api/v1/auth/refresh", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ access_token: "mock-valid-token-user", expires_in: 3600 }),
      });
    });

    await page.route("**/api/v1/me", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ id: "u-normal", username: "user1", nickname: "普通用户", role: "user" }),
      });
    });

    await page.goto("/admin/recommendations");
    await expect(page.getByRole("heading", { name: "访问受限" })).toBeVisible();
    await expect(page.getByText("该功能仅限平台管理员使用。")).toBeVisible();

    // 2. 切换为管理员身份
    await page.unroute("**/api/v1/me");
    await page.route("**/api/v1/me", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ id: "u-admin", username: "admin", nickname: "超级管理员", role: "admin" }),
      });
    });

    let mockRecommendations = [
      {
        post_id: "p-rec-1",
        position: 1,
        recommended_at: new Date().toISOString(),
        post: {
          id: "p-rec-1",
          title: "现有精选帖子A",
          author: { nickname: "作者A" },
          community: { name: "酱紫社区" },
          created_at: new Date().toISOString(),
        },
      },
      {
        post_id: "p-rec-2",
        position: 2,
        recommended_at: new Date().toISOString(),
        post: {
          id: "p-rec-2",
          title: "现有精选帖子B",
          author: { nickname: "作者B" },
          community: { name: "大型拆箱" },
          created_at: new Date().toISOString(),
        },
      },
    ];

    await page.route("**/api/v1/admin/recommendations", async (route) => {
      if (route.request().method() === "GET") {
        await route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify({ items: mockRecommendations }),
        });
      }
    });

    let reorderPayload: unknown = null;
    await page.route("**/api/v1/admin/recommendations/reorder", async (route) => {
      reorderPayload = JSON.parse(route.request().postData() || "[]");
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ status: "ok" }) });
    });

    await page.route("**/api/v1/admin/recommendations/p-rec-new", async (route) => {
      if (route.request().method() === "PUT") {
        await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ status: "ok" }) });
      }
    });

    await page.route("**/api/v1/admin/recommendations/p-rec-1", async (route) => {
      if (route.request().method() === "DELETE") {
        await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ status: "ok" }) });
      }
    });

    await page.route("**/api/v1/search?*", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          posts: [
            {
              id: "p-rec-new",
              title: "待推荐的好物新帖",
              content: "测评内容十分详实",
              author_name: "新作者",
              author: { nickname: "新作者" },
              community: { name: "活动专区" },
            },
          ],
        }),
      });
    });

    await page.route("**/api/v1/posts/p-rec-new*", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          id: "p-rec-new",
          title: "待推荐的好物新帖",
          content: "测评内容十分详实",
          author: { nickname: "新作者" },
          community: { name: "活动专区" },
          created_at: new Date().toISOString(),
          media: [],
          comment_count: 3,
          like_count: 5,
        }),
      });
    });

    // 再次访问，成功进入
    await page.goto("/admin/recommendations");
    await expect(page.getByRole("heading", { name: /首页.*推荐管理/ })).toBeVisible();

    // 验证当前已有两条推荐
    await expect(page.getByText("现有精选帖子A")).toBeVisible();
    await expect(page.getByText("现有精选帖子B")).toBeVisible();

    // 3. 搜索帖子并加入推荐
    const searchInput = page.locator(".admin-search-panel input");
    await searchInput.fill("好物");
    await page.getByRole("button", { name: "搜索帖子" }).click();

    // 候选列表出现
    await expect(page.getByText("待推荐的好物新帖")).toBeVisible();
    await page.getByText("待推荐的好物新帖").click();

    // 提交加入推荐
    await page.getByRole("button", { name: "确认加入首页推荐" }).click();
    await expect(page.getByText("已成功加入首页推荐！")).toBeVisible();

    // 4. 测试下移与保存排序
    const firstRowDownBtn = page.locator("button[title='下移']").first();
    await firstRowDownBtn.click();

    // 保存排序按钮由 disabled 变为可用
    const saveOrderBtn = page.getByRole("button", { name: "保存排序" });
    await expect(saveOrderBtn).toBeEnabled();
    await saveOrderBtn.click();

    // 验证调用了 reorder API
    await expect(async () => {
      expect(reorderPayload).not.toBeNull();
    }).toPass();

    // 5. 测试移除推荐
    page.on("dialog", (dialog) => dialog.accept());
    const removeBtn = page.locator("button").filter({ hasText: "移除" }).first();
    await removeBtn.click();
    await expect(page.getByText("已从首页推荐中移除")).toBeVisible();
  });

  test("16. 评论系统：一级评论外露最多 4 条热评预览，点击查看全部恢复楼层时间顺序", async ({ page }) => {
    const mockPost = {
      id: "post-hot-replies-1",
      title: "四条热评外露结构测试帖",
      content: "测试一级评论外露 4 条高赞热评，点击后恢复时间正序",
      comment_count: 10,
      like_count: 20,
      bookmark_count: 5,
      view_count: 300,
      created_at: new Date().toISOString(),
      author: { id: "u-author", nickname: "楼主", level: 3 },
      community: { id: "c1", name: "酱紫社区" },
      media: [],
      viewer_state: { has_liked: false, has_bookmarked: false },
    };

    const mockComments = {
      items: [
        {
          id: "comm-root-1",
          post_id: "post-hot-replies-1",
          author: { id: "u-comm-root", nickname: "一级楼主", level: 2 },
          content: "这是具有多条二级回复的一级主评论",
          floor: 1,
          reply_count: 6,
          created_at: new Date().toISOString(),
          media: [],
          viewer_state: { has_liked: false, has_disliked: false },
          reply_preview: [
            {
              id: "rep-hot-1",
              content: "第一条热评回复，点赞最高",
              author: { id: "u-rep-1", nickname: "热评甲", level: 2 },
              like_count: 68,
              created_at: "2026-09-05T08:30:00Z",
            },
            {
              id: "rep-hot-2",
              content: "第二条热评回复",
              author: { id: "u-rep-2", nickname: "热评乙", level: 1 },
              like_count: 52,
              created_at: "2026-09-05T08:40:00Z",
            },
            {
              id: "rep-hot-3",
              content: "第三条热评回复",
              author: { id: "u-rep-3", nickname: "热评丙", level: 3 },
              like_count: 48,
              created_at: "2026-09-05T08:10:00Z",
            },
            {
              id: "rep-hot-4",
              content: "第四条热评回复",
              author: { id: "u-rep-4", nickname: "热评丁", level: 2 },
              like_count: 36,
              created_at: "2026-09-05T08:50:00Z",
            },
          ],
        },
      ],
      total: 1,
      has_more: false,
    };

    // 楼中楼完整回复列表（恢复按时间/楼层顺序 asc）
    const mockThreadReplies = [
      {
        id: "rep-hot-3",
        content: "第三条热评回复（最早发言）",
        author: { id: "u-rep-3", nickname: "热评丙", level: 3 },
        floor: 1,
        created_at: "2026-09-05T08:10:00Z",
        like_count: 48,
      },
      {
        id: "rep-hot-1",
        content: "第一条热评回复，点赞最高",
        author: { id: "u-rep-1", nickname: "热评甲", level: 2 },
        floor: 2,
        created_at: "2026-09-05T08:30:00Z",
        like_count: 68,
      },
      {
        id: "rep-hot-2",
        content: "第二条热评回复",
        author: { id: "u-rep-2", nickname: "热评乙", level: 1 },
        floor: 3,
        created_at: "2026-09-05T08:40:00Z",
        like_count: 52,
      },
      {
        id: "rep-hot-4",
        content: "第四条热评回复",
        author: { id: "u-rep-4", nickname: "热评丁", level: 2 },
        floor: 4,
        created_at: "2026-09-05T08:50:00Z",
        like_count: 36,
      },
      {
        id: "rep-asc-5",
        content: "第五条回复，点赞少但按顺序展示",
        author: { id: "u-rep-5", nickname: "新人戊", level: 1 },
        floor: 5,
        created_at: "2026-09-05T09:00:00Z",
        like_count: 2,
      },
      {
        id: "rep-asc-6",
        content: "第六条最新回复",
        author: { id: "u-rep-6", nickname: "新人己", level: 1 },
        floor: 6,
        created_at: "2026-09-05T09:10:00Z",
        like_count: 1,
      },
    ];

    await page.route("**/api/v1/posts/post-hot-replies-1/comments*", async (route) => {
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(mockComments) });
    });

    await page.route("**/api/v1/posts/post-hot-replies-1*", async (route) => {
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(mockPost) });
    });

    let repliesRequestedSort = "";
    await page.route("**/api/v1/comments/comm-root-1/replies*", async (route) => {
      const url = new URL(route.request().url());
      repliesRequestedSort = url.searchParams.get("sort") || "";
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ items: mockThreadReplies, total: 6, has_more: false }),
      });
    });

    await page.route("**/api/v1/feed/latest*", async (route) => {
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ items: [] }) });
    });

    await page.goto("/post/post-hot-replies-1");

    // 先等待帖子正文与主评论渲染就绪
    await expect(page.getByRole("heading", { name: "四条热评外露结构测试帖" })).toBeVisible();
    await expect(page.getByText("这是具有多条二级回复的一级主评论")).toBeVisible();

    // 1. 验证一级评论外露 4 条热评预览
    const hotRepliesBox = page.locator("#comment-comm-root-1 .hot-replies");
    await expect(hotRepliesBox).toBeVisible();
    await expect(hotRepliesBox.locator(".reply-row")).toHaveCount(4);

    // 验证热评第一名内容和热度数值呈现
    await expect(hotRepliesBox).toContainText("第一条热评回复，点赞最高");
    await expect(hotRepliesBox).toContainText("68");
    await expect(hotRepliesBox).toContainText("第四条热评回复");

    // 2. 点击“查看全部 6 条回复 ›”
    const viewAllBtn = hotRepliesBox.getByRole("button", { name: /查看全部 6 条回复/ });
    await expect(viewAllBtn).toBeVisible();
    await viewAllBtn.click();

    // 3. 验证楼中楼模态框弹出
    const replyModal = page.getByRole("dialog", { name: /评论回复/ });
    await expect(replyModal).toBeVisible();

    // 4. 验证接口调用指定了 sort=asc
    expect(repliesRequestedSort).toBe("asc");

    // 5. 验证在模态框中按时间第一条的“第三条热评回复（最早发言）”排在首位，且第 5、6 条按时间正常追加展示
    const threadItems = replyModal.locator(".comment-reply-item");
    await expect(threadItems).toHaveCount(6);
    await expect(threadItems.first()).toContainText("第三条热评回复（最早发言）");
    await expect(threadItems.last()).toContainText("第六条最新回复");
  });

  test("17. PC 排行榜 beiyoujiang 架构与多视口布局：display:grid、列宽、Top2/3同行、Rank4+行高及右栏智能扩展", async ({ page }) => {
    // 设为 1920x1080 PC 宽屏视口
    await page.setViewportSize({ width: 1920, height: 1080 });

    const mockRankingToys = [
      {
        id: "toy-1",
        name: "黄油小姐二代",
        merchant: "ACG",
        category: "CUP",
        score: 8.7,
        rating: 8.7,
        rating_count: 47,
        want_count: 1600,
        cover_url: "/mock-cover-1.jpg",
        tags: ["ACG", "测评"],
      },
      {
        id: "toy-2",
        name: "鱼头",
        merchant: "CUP",
        category: "高性价比",
        score: 9.1,
        rating: 9.1,
        rating_count: 90,
        want_count: 850,
        cover_url: "/mock-cover-2.jpg",
        tags: ["CUP", "高性价比"],
      },
      {
        id: "toy-3",
        name: "双穴爱莉",
        merchant: "CUP",
        category: "经典",
        score: 9.1,
        rating: 9.1,
        rating_count: 14,
        want_count: 320,
        cover_url: "/mock-cover-3.jpg",
        tags: ["CUP"],
      },
      {
        id: "toy-4",
        name: "天与苍穹",
        merchant: "CUP",
        category: "软萌",
        score: 8.9,
        rating: 8.9,
        rating_count: 26,
        want_count: 480,
        cover_url: "/mock-cover-4.jpg",
        tags: ["CUP"],
      },
      {
        id: "toy-5",
        name: "蓝海星落",
        merchant: "CUP",
        category: "新品",
        score: 8.8,
        rating: 8.8,
        rating_count: 31,
        want_count: 390,
        cover_url: "/mock-cover-5.jpg",
        tags: ["CUP"],
      },
    ];

    await page.route("**/api/v1/ranking/toys*", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ items: mockRankingToys }),
      });
    });

    await page.route("**/api/v1/communities*", async (route) => {
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ items: [] }) });
    });

    await page.goto("/ranking");

    // 1. 验证 PC 桌面端 RankingDesktopShell 及其 Grid 布局生效
    const desktopShell = page.getByTestId("ranking-desktop-shell");
    await expect(desktopShell).toBeVisible();

    const shellGrid = page.getByTestId("ranking-shell-grid");
    await expect(shellGrid).toBeVisible();

    const gridStyles = await shellGrid.evaluate((el) => {
      const computed = window.getComputedStyle(el);
      return {
        display: computed.display,
        gridTemplateColumns: computed.gridTemplateColumns,
      };
    });
    expect(gridStyles.display).toBe("grid");

    // 无独立周冠军时，自动应用 .noRightRail，不保留幽灵右栏，中间栏自动吃满 (220px 1fr)
    expect(gridStyles.gridTemplateColumns).toMatch(/220px\s+\d+(\.\d+)?px/);
    await expect(page.getByTestId("ranking-right-rail")).toBeHidden();

    // 2. 验证严格遵照服务端原序：
    // 虽然第 2、3 名评分为 9.1，高于第 1 名的 8.7，但前端绝对不重新按评分倒序，第 1 名仍然严格为“黄油小姐二代”！
    const top1Link = page.getByTestId("ranking-top1-link");
    await expect(top1Link).toBeVisible();
    await expect(top1Link).toContainText("01");
    await expect(top1Link).toContainText("黄油小姐二代");
    await expect(top1Link).toContainText("8.7");
    await expect(top1Link).toContainText("47 篇测评");

    // 3. 验证 Top 2 与 Top 3 并排在同一水平行（垂直坐标 top 误差小于 5px）
    const top23Grid = page.getByTestId("ranking-top23-grid");
    await expect(top23Grid).toBeVisible();
    const top2Card = page.getByTestId("ranking-top2-link");
    const top3Card = page.getByTestId("ranking-top3-link");
    await expect(top2Card).toBeVisible();
    await expect(top3Card).toBeVisible();
    await expect(top2Card).toContainText("02");
    await expect(top2Card).toContainText("鱼头");
    await expect(top3Card).toContainText("03");
    await expect(top3Card).toContainText("双穴爱莉");

    const top2Box = await top2Card.boundingBox();
    const top3Box = await top3Card.boundingBox();
    expect(top2Box).not.toBeNull();
    expect(top3Box).not.toBeNull();
    expect(Math.abs((top2Box?.y || 0) - (top3Box?.y || 0))).toBeLessThan(5);

    // 4. 验证第 4 名以后为紧凑横向行列表（行高在 90px~110px 之间）
    const row04 = page.getByTestId("ranking-row-04");
    const row05 = page.getByTestId("ranking-row-05");
    await expect(row04).toBeVisible();
    await expect(row04).toContainText("04");
    await expect(row04).toContainText("天与苍穹");
    await expect(row05).toBeVisible();
    await expect(row05).toContainText("05");
    await expect(row05).toContainText("蓝海星落");

    const row04Box = await row04.boundingBox();
    expect(row04Box).not.toBeNull();
    expect(row04Box!.height).toBeGreaterThanOrEqual(85);
    expect(row04Box!.height).toBeLessThanOrEqual(115);

    // 5. 验证 1366x768 视口下依然保持良好桌面网格
    await page.setViewportSize({ width: 1366, height: 768 });
    await expect(shellGrid).toBeVisible();
    const gridStyles1366 = await shellGrid.evaluate((el) => window.getComputedStyle(el).display);
    expect(gridStyles1366).toBe("grid");

    // 6. 验证 1024x768 横屏视口下居中主榜单，左栏与右栏隐藏
    await page.setViewportSize({ width: 1100, height: 750 });
    const leftRailStyles = await page.getByTestId("ranking-left-rail").evaluate((el) => window.getComputedStyle(el).display);
    expect(leftRailStyles).toBe("none");

    // 7. 验证 1080x1920 PC 竖屏视口：
    // 隐藏桌面 Shell，切换到单列移动端风格；但由于不是真实手机，绝不弹出下载 App 浮窗！
    await page.setViewportSize({ width: 1080, height: 1920 });
    await expect(desktopShell).toBeHidden();
    await expect(page.getByTestId("ranking-mobile-list")).toBeVisible();
    // 验证 PC 竖屏无 App 下载浮窗
    await expect(page.locator(".app-download-banner")).toBeHidden();
  });

  test("18. 手机与 PC 竖屏架构隔离：390x844 手机仅保留 3 个主社区板块，PC 1440x900 完整呈现桌面三栏", async ({ page }) => {
    // 1. 移动端 390x844 手机视口
    await page.setViewportSize({ width: 390, height: 844 });

    await page.route("**/api/v1/feed/latest*", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          items: [
            {
              id: "post-viewport-1",
              title: "单图规范测试帖",
              content: "测试单图自适应包含不拉伸",
              comment_count: 1,
              like_count: 2,
              view_count: 20,
              created_at: new Date().toISOString(),
              author: { id: "u-vp-1", nickname: "视口作者", level: 2 },
              community: { id: "c1", name: "酱紫社区" },
              media: [
                {
                  id: "m-single-1",
                  url: "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='300' height='400'%3E%3Crect width='300' height='400' fill='%233f8df7'/%3E%3C/svg%3E",
                  thumb_url: "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='300' height='400'%3E%3Crect width='300' height='400' fill='%233f8df7'/%3E%3C/svg%3E",
                  detail_url: "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='300' height='400'%3E%3Crect width='300' height='400' fill='%233f8df7'/%3E%3C/svg%3E",
                  original_url: "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='300' height='400'%3E%3Crect width='300' height='400' fill='%233f8df7'/%3E%3C/svg%3E",
                  alt_text: "竖屏单图",
                },
              ],
              viewer_state: { has_liked: false, has_bookmarked: false },
            },
          ],
          total: 1,
          has_more: false,
        }),
      });
    });

    await page.route("**/api/v1/communities*", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          items: [
            { id: "c-1", name: "大型拆箱", slug: "unboxing", sort_order: 1 },
            { id: "c-2", name: "酱紫社区", slug: "campus", sort_order: 2 },
            { id: "c-3", name: "杂鱼日常", slug: "daily", sort_order: 3 },
            { id: "c-extra", name: "额外板块", slug: "extra", sort_order: 4 },
          ],
        }),
      });
    });

    await page.goto("/");

    // 移动端：底部浮动导航栏与移动端头部可见
    const mobileBottomNav = page.locator("nav.bottom-nav");
    await expect(mobileBottomNav).toBeVisible();

    // 移动端：严格只有 3 个社区 Tab（大型拆箱 | 酱紫社区 | 杂鱼日常），没有冗余的“全部”
    const communityTabs = page.locator(".home-community-tabs .home-community-tab");
    await expect(communityTabs).toHaveCount(3);
    await expect(communityTabs.nth(0)).toContainText("大型拆箱");
    await expect(communityTabs.nth(1)).toContainText("酱紫社区");
    await expect(communityTabs.nth(2)).toContainText("杂鱼日常");

    // 移动端：桌面左侧与右侧侧边栏严格隐藏
    const desktopLeftRail = page.locator(".home-left-col");
    await expect(desktopLeftRail).toBeHidden();
    const desktopRightCol = page.locator(".home-right-col");
    await expect(desktopRightCol).toBeHidden();

    // 2. 桌面端 1440x900 视口
    await page.setViewportSize({ width: 1440, height: 900 });

    // 桌面端：底部移动端导航栏隐藏，桌面左右侧栏可见
    await expect(mobileBottomNav).toBeHidden();
    await expect(desktopLeftRail).toBeVisible();
    await expect(desktopRightCol).toBeVisible();

    // 3. 验证单图规范：max-height: 420px，object-fit: contain，无强制拉伸
    const singleMediaImg = page.locator(".media-single img").first();
    await expect(singleMediaImg).toBeVisible();
    const imgStyles = await singleMediaImg.evaluate((el) => {
      const computed = window.getComputedStyle(el);
      return {
        objectFit: computed.objectFit,
        maxHeight: computed.maxHeight,
      };
    });
    expect(imgStyles.objectFit).toBe("contain");
    expect(imgStyles.maxHeight).toBe("420px");
  });
});

