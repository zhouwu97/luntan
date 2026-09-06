import { test, expect, type Page } from "@playwright/test";
import { mockApiFallbacks } from "./mock-api";

test.beforeEach(async ({ page }) => { await mockApiFallbacks(page); });

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
    await expect(page.getByText("审核中", { exact: true })).toBeVisible();
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


test("取消订单：弱网重试复用幂等键，刷新余额、库存和状态", async ({ page }) => {
  await mockUserSession(page);
  const order = { id: "cancel-order", product_id: "badge", product_name: "取消测试徽章", points: 60, status: "approved", fulfillment_status: "ready_to_ship", created_at: new Date().toISOString() };
  let attempts = 0;
  const keys: string[] = [];
  await page.route("**/api/v1/me/store-orders?*", (route) => route.fulfill({ json: { items: [order] } }));
  await page.route("**/api/v1/me/points", (route) => route.fulfill({ json: { balance: order.status === "cancelled" ? 100 : 40, transactions: [] } }));
  await page.route("**/api/v1/store/products", (route) => route.fulfill({ json: { items: [] } }));
  await page.route("**/api/v1/me/store-orders/cancel-order/aftercare", (route) => route.fulfill({ json: { status: order.status, fulfillment_status: order.fulfillment_status, refunded_points: order.status === "cancelled" ? 60 : 0 } }));
  await page.route("**/api/v1/me/store-orders/cancel-order/reverse", (route) => {
    keys.push(route.request().headers()["idempotency-key"]);
    expect(route.request().postDataJSON()).toEqual({ action: "cancel", reason: "地址有误，取消重下" });
    if (++attempts === 1) return route.fulfill({ status: 500, json: { message: "请重试" } });
    order.status = "cancelled"; order.fulfillment_status = "cancelled";
    return route.fulfill({ json: order });
  });
  await page.goto("/points?tab=orders");
  await page.getByRole("button", { name: "取消与售后" }).click();
  const dialog = page.getByRole("dialog", { name: "取消与售后" });
  await dialog.getByLabel("操作说明（必填）").fill("地址有误，取消重下");
  await dialog.getByRole("button", { name: "取消订单并返还已扣积分" }).click();
  await expect(dialog.getByRole("alert")).toContainText("请重试");
  await dialog.getByRole("button", { name: "取消订单并返还已扣积分" }).click();
  await expect(dialog).toBeHidden();
  await expect(page.locator("#order-cancel-order .badge")).toHaveText("已取消");
  expect(keys).toHaveLength(2);
  expect(keys[0]).toBeTruthy();
  expect(keys[1]).toBe(keys[0]);
});

test("商城通知能加载第一页之外的旧订单", async ({ page }) => {
  await mockUserSession(page);
  await page.route("**/api/v1/me/store-orders?*", (route) => route.fulfill({ json: { items: [], has_more: false } }));
  await page.route("**/api/v1/me/store-orders/old-order", (route) => route.fulfill({ json: { id: "old-order", product_id: "badge", product_name: "旧兑换订单", points: 60, status: "approved", fulfillment_status: "shipped", created_at: "2026-01-01T00:00:00Z", shipping: { carrier: "顺丰", tracking_no: "OLD123" } } }));
  await page.goto("/points?tab=orders&order=old-order");
  await expect(page.locator("#order-old-order")).toHaveClass(/highlighted/);
  await expect(page.locator("#order-old-order")).toContainText("OLD123");
});
