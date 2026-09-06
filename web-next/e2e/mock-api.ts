import type { Page } from "@playwright/test";

// 契约测试只使用显式 fixture，未覆盖的请求也不得穿透到真实后端。
export async function mockApiFallbacks(page: Page) {
  await page.route("**/api/v1/**", async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path.endsWith("/auth/refresh")) {
      await route.fulfill({ status: 401, json: { code: "UNAUTHORIZED" } });
    } else if (path.endsWith("/auth/guest")) {
      await route.fulfill({ json: { access_token: "fixture-guest", user: { id: "fixture-guest", username: "guest", nickname: "游客", account_type: "guest" } } });
    } else {
      await route.fulfill({ json: { items: [], has_more: false, unread_count: 0 } });
    }
  });
}
