import { test, expect, Page, Route } from "@playwright/test";
import { mockApiFallbacks } from "./mock-api";

test.describe("多标签页身份同步与会话过渡防竞态", () => {
  test("Tab 2 登录账号 B 后，Tab 1 跨标签页自动同步为账号 B", async ({ context }) => {
    let currentAccount = "user-a";
    let currentNickname = "用户甲";

    const setupAuthRoutes = async (page: Page) => {
      await mockApiFallbacks(page);
      await page.route("**/api/v1/auth/refresh", async (route: Route) => {
        await route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify({
            access_token: `token-${currentAccount}`,
            expires_in: 3600,
          }),
        });
      });
      await page.route("**/api/v1/me", async (route: Route) => {

        await route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify({
            id: currentAccount,
            username: currentAccount,
            nickname: currentNickname,
            account_type: "email",
            level: 2,
          }),
        });
      });
      await page.route("**/api/v1/feed/latest*", async (route: Route) => {
        await route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify({ items: [], has_more: false }),
        });
      });
      await page.route("**/api/v1/ranking/toys*", async (route: Route) => {
        await route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify({ items: [] }),
        });
      });
      await page.route("**/api/v1/communities*", async (route: Route) => {
        await route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify({ items: [] }),
        });
      });

    };

    // 1. Tab 1 打开页面，此时为账号 A
    const page1 = await context.newPage();
    await setupAuthRoutes(page1);
    await page1.goto("/");
    // 验证 Tab 1 显示账号 A 的昵称
    await expect(page1.getByText("用户甲")).toBeVisible({ timeout: 10000 });

    // 2. Tab 2 打开，并触发切换为账号 B
    currentAccount = "user-b";
    currentNickname = "用户乙";
    const page2 = await context.newPage();
    await setupAuthRoutes(page2);
    await page2.goto("/");
    await expect(page2.getByText("用户乙")).toBeVisible({ timeout: 10000 });

    // 3. Tab 2 通过 broadcastSessionChanged 广播会话变动（模拟 Tab 2 登录动作）
    await page2.evaluate(() => {
      const channel = new BroadcastChannel("luntan-auth");
      channel.postMessage({ type: "session-changed", timestamp: Date.now() });
      window.localStorage.setItem("luntan:session-epoch", Date.now().toString());
    });

    // 4. Tab 1 应当在不需要手动刷新的情况下，自动接收广播并更新展示用户乙
    await expect(page1.getByText("用户乙")).toBeVisible({ timeout: 10000 });
  });

  test("退出登录后新登录不会被迟到的旧游客响应或清理覆盖", async ({ page }) => {
    let allowGuestResolve: () => void = () => {};
    const guestHold = new Promise<void>((resolve) => {
      allowGuestResolve = resolve;
    });

    let currentAccount = "user-a";
    let currentNickname = "用户甲";
    let interceptDelayedGuest = false;

    await mockApiFallbacks(page);

    await page.route("**/api/v1/auth/refresh", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          access_token: `token-${currentAccount}`,
          expires_in: 3600,
        }),
      });
    });

    await page.route("**/api/v1/me", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          id: currentAccount,
          username: currentAccount,
          nickname: currentNickname,
          account_type: "email",
          level: 2,
        }),
      });
    });

    await page.route("**/api/v1/auth/logout", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ success: true }),
      });
    });

    await page.route("**/api/v1/auth/guest", async (route) => {
      if (interceptDelayedGuest) {
        await guestHold;
        await route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify({
            token: "guest-token-delayed",
            user: {
              id: "guest-delayed-id",
              username: "guest_delayed",
              nickname: "游客迟到",
              account_type: "guest",
              role: "user",
            },
          }),
        });
      } else {
        await route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify({
            token: "guest-token",
            user: {
              id: "guest-id",
              username: "guest",
              nickname: "游客初始",
              account_type: "guest",
              role: "user",
            },
          }),
        });
      }
    });

    await page.route("**/api/v1/feed/latest*", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ items: [], has_more: false }),
      });
    });
    await page.route("**/api/v1/ranking/toys*", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ items: [] }),
      });
    });
    await page.route("**/api/v1/communities*", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ items: [] }),
      });
    });

    // 1. 打开设置页，确认当前登录为“用户甲”
    await page.goto("/settings");
    await expect(page.getByText("用户甲")).toBeVisible({ timeout: 10000 });

    // 2. 开启延迟拦截，接下来退出登录触发的 /auth/guest 将被挂起
    interceptDelayedGuest = true;

    // 准备登录接口的 mock：登录为“用户乙”
    await page.route("**/api/v1/auth/login/password", async (route) => {
      currentAccount = "user-b";
      currentNickname = "用户乙";
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          access_token: "token-user-beta",
          expires_in: 3600,
          user: {
            id: "user-b",
            username: "user_b",
            nickname: "用户乙",
            account_type: "email",
            role: "user",
          },
        }),
      });
    });


    // 3. 点击“退出登录”
    await page.getByRole("button", { name: /退出登录/i }).click();

    // 退出后，页面渲染游客模式，并出现“登录 / 注册”链接
    const loginLink = page.getByRole("link", { name: "登录 / 注册" });
    await expect(loginLink).toBeVisible({ timeout: 10000 });

    // 4. 用户点击登录链接前往登录页，登录为“用户乙”
    await loginLink.click();
    await page.getByPlaceholder(/邮箱/i).fill("beta@example.com");
    await page.getByPlaceholder(/密码/i).fill("password123");
    await page.locator('button[type="submit"]').click();



    // 5. 此时应成功登录并跳转，展示“用户乙”
    await expect(page.getByText("用户乙")).toBeVisible({ timeout: 10000 });

    // 6. 此时释放先前挂起的旧 /auth/guest 请求
    allowGuestResolve();

    // 7. 等待 1 秒，确保迟到的游客响应到达或其 catch 执行后，用户乙依然保持在界面上，未被重置为 null 或游客
    await page.waitForTimeout(1000);
    await expect(page.getByText("用户乙")).toBeVisible();
    await expect(page.getByText("游客迟到")).toHaveCount(0);
  });
});


