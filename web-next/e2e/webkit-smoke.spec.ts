import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";
import { mockApiFallbacks } from "./mock-api";

test.beforeEach(async ({ page }) => {
  await mockApiFallbacks(page);
});

test("移动 Safari 可打开首页和固定底部导航", async ({ page }) => {
  await page.goto("/");
  await expect(page.locator("body")).toBeVisible();
  await expect(page.getByRole("navigation").last()).toBeVisible();
});

test("移动 Safari 注册页遵循服务端验证码策略", async ({ page }) => {
  await page.route("**/api/v1/bootstrap", (route) => route.fulfill({
    json: { auth: { guest_enabled: true, registration_enabled: true, email_code_required: true } },
  }));
  await page.goto("/login?mode=register");
  await expect(page.getByLabel("邮箱验证码", { exact: true })).toHaveAttribute("required", "");
});

test("登录页无严重或关键级无障碍问题", async ({ page }) => {
  await page.goto("/login");
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
    .analyze();
  const blocking = results.violations.filter((item) => item.impact === "critical" || item.impact === "serious");
  expect(blocking).toEqual([]);
});
