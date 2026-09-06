import { test, expect, type Page } from "@playwright/test";

async function mockGuestSession(page: Page) {
  await page.route("**/api/v1/auth/refresh", async (route) => {
    await route.fulfill({ status: 401, body: JSON.stringify({ code: "UNAUTHORIZED" }) });
  });
  await page.route("**/api/v1/auth/guest", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({
        access_token: "mock-guest-token",
        user: {
          id: "guest-1",
          username: "guest_visitor",
          nickname: "游客",
          role: "guest",
          account_type: "guest",
          experience: 0,
          public_id: "G1000",
        },
      }),
    });
  });
  await page.route("**/api/v1/notifications/unread-count", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ count: 0 }),
    });
  });
}

async function mockUserSession(page: Page) {
  await page.route("**/api/v1/auth/refresh", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ access_token: "mock-token", expires_in: 3600 }),
    });
  });
  await page.route("**/api/v1/me", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({
        id: "user-1",
        username: "points_fan",
        nickname: "积分达人",
        role: "user",
        account_type: "registered",
        experience: 100,
        public_id: "U1001",
      }),
    });
  });
  await page.route("**/api/v1/notifications/unread-count", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ count: 0 }),
    });
  });
}

test.describe("积分商城履约链路 E2E 验收套件", () => {
  test("1. 游客访问商城 → 引导注册", async ({ page }) => {
    await mockGuestSession(page);

    await page.route("**/api/v1/store/products", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          items: [
            {
              id: "prod-badge",
              name: "社区纪念徽章",
              description: "金属烤漆徽章",
              emoji: "🎖️",
              points: 60,
              color: 0,
              redeemed_count: 5,
              stock: 10,
            },
          ],
        }),
      });
    });

    await page.goto("/points");
    await expect(page.getByText("社区纪念徽章")).toBeVisible();
    const guestBtn = page.getByRole("button", { name: "注册后兑换" });
    await expect(guestBtn).toBeVisible();

    await guestBtn.click();
    await expect(page).toHaveURL(/.*login.*mode=register/);
  });

  test("2. 正式用户兑换申请：3 值积分模型校验，申请不扣真实余额", async ({ page }) => {
    await mockUserSession(page);

    await page.route("**/api/v1/me/points", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          balance: 100,
          reserved_points: 0,
          available_points: 100,
          transactions: [],
        }),
      });
    });

    await page.route("**/api/v1/store/products", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          items: [
            {
              id: "prod-badge",
              name: "社区纪念徽章",
              description: "金属烤漆徽章",
              emoji: "🎖️",
              points: 60,
              color: 0,
              redeemed_count: 5,
              stock: 10,
            },
          ],
        }),
      });
    });

    await page.route("**/api/v1/me/store-orders", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          items: [],
          has_more: false,
        }),
      });
    });

    await page.route("**/api/v1/store/orders", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          id: "order-test-1",
          product_id: "prod-badge",
          product_name: "社区纪念徽章",
          points: 60,
          status: "pending_review",
          fulfillment_status: "none",
          created_at: new Date().toISOString(),
        }),
      });
    });

    await page.goto("/points");

    // 初始积分卡校验：100 PTS，当前可兑换 100，审核中占用 0
    await expect(page.locator(".points-hero-number")).toHaveText("100");
    await expect(page.getByText("当前可兑换")).toBeVisible();
    await expect(page.getByText("审核中占用")).toBeVisible();

    // 点击申请兑换
    const applyBtn = page.getByRole("button", { name: "申请兑换" });
    await expect(applyBtn).toBeVisible();
    await applyBtn.click();

    // 弹窗校验
    await expect(page.getByText("提交后将进入人工审核")).toBeVisible();
    const submitBtn = page.getByRole("button", { name: "提交申请" });
    await submitBtn.click();

    // 提交后校验：余额保持 100，审核中占用 60，当前可兑换 40
    await expect(page.locator(".points-hero-number")).toHaveText("100");
    await expect(page.getByText("40", { exact: true })).toBeVisible();
    await expect(page.getByText("60", { exact: true })).toBeVisible();
    // 自动切到订单页，显示审核中
    await expect(page.getByText("审核中")).toBeVisible();
  });

  test("3. 通知深链与待填地址自动弹窗", async ({ page }) => {
    await mockUserSession(page);

    await page.route("**/api/v1/me/points", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          balance: 40,
          reserved_points: 0,
          available_points: 40,
          transactions: [],
        }),
      });
    });

    await page.route("**/api/v1/store/products", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ items: [] }),
      });
    });

    await page.route("**/api/v1/me/store-orders*", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          items: [
            {
              id: "order-deep-1",
              product_id: "prod-badge",
              product_name: "社区纪念徽章",
              points: 60,
              status: "approved",
              fulfillment_status: "awaiting_address",
              created_at: new Date().toISOString(),
            },
          ],
          has_more: false,
        }),
      });
    });

    // 直接以深链进入商城
    await page.goto("/points?tab=orders&order=order-deep-1");

    // 校验：自动打开填写收货地址弹窗
    const dialog = page.getByRole("dialog");
    await expect(dialog).toBeVisible();
    await expect(dialog.getByRole("heading", { name: "填写收货地址" })).toBeVisible();
    await expect(page.getByPlaceholder("如：张三")).toBeVisible();
    await expect(page.getByPlaceholder("如：13800000000")).toBeVisible();
  });

  test("4. 用户确认收货链路完成", async ({ page }) => {
    await mockUserSession(page);

    await page.route("**/api/v1/me/points", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          balance: 40,
          reserved_points: 0,
          available_points: 40,
          transactions: [],
        }),
      });
    });

    await page.route("**/api/v1/store/products", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ items: [] }),
      });
    });

    await page.route("**/api/v1/me/store-orders*", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          items: [
            {
              id: "order-shipped-1",
              product_id: "prod-badge",
              product_name: "社区纪念徽章",
              points: 60,
              status: "approved",
              fulfillment_status: "shipped",
              created_at: new Date().toISOString(),
              shipping: {
                recipient_name: "张三",
                phone: "13800000000",
                province: "北京市",
                city: "北京市",
                address_detail: "朝阳区科技园",
                carrier: "顺丰速运",
                tracking_no: "SF1234567890",
              },
            },
          ],
          has_more: false,
        }),
      });
    });

    await page.route("**/api/v1/me/store-orders/order-shipped-1/complete", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          id: "order-shipped-1",
          product_id: "prod-badge",
          product_name: "社区纪念徽章",
          points: 60,
          status: "approved",
          fulfillment_status: "completed",
          created_at: new Date().toISOString(),
          completed_at: new Date().toISOString(),
        }),
      });
    });

    await page.goto("/points?tab=orders");

    await expect(page.getByText("已发货")).toBeVisible();
    await expect(page.getByText("SF1234567890")).toBeVisible();

    const completeBtn = page.getByRole("button", { name: "确认已收到" });
    await expect(completeBtn).toBeVisible();
    await completeBtn.click();

    // 弹窗二次确认
    await expect(page.getByText("确认已经收到兑换商品")).toBeVisible();
    const modalConfirmBtn = page.getByRole("dialog").getByRole("button", { name: "确认已收到" });
    await modalConfirmBtn.click();

    // 状态更新为已完成
    await expect(page.getByText("已完成")).toBeVisible();
  });
});
