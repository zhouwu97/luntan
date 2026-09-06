import { test, expect } from "@playwright/test";
import { mockApiFallbacks } from "./mock-api";

test("通知分页跨分类完成不能混入当前列表或卡住下一页", async ({ page }) => {
  await mockApiFallbacks(page);
  let releaseOld: () => void = () => {};
  const oldResponse = new Promise<void>((resolve) => { releaseOld = resolve; });
  let oldStarted = false;
  const item = (id: string) => ({ id, type: "like", actor: { id: "b", nickname: id }, target_type: "post", target_id: "post", is_read: false, created_at: new Date().toISOString() });
  await page.route("**/api/v1/notifications?*", async (route) => {
    const query = new URL(route.request().url()).searchParams;
    const category = query.get("category") || "all";
    if (query.has("cursor") && category === "all") {
      oldStarted = true;
      await oldResponse;
      await route.fulfill({ json: { items: [item("旧分类第二页")], has_more: false } });
      return;
    }
    await route.fulfill({ json: {
      items: [item(category === "all" ? "全部首页" : query.has("cursor") ? "互动第二页" : "互动首页")],
      has_more: !query.has("cursor"), next_cursor: query.has("cursor") ? null : "next",
    } });
  });
  await page.goto("/notifications");
  await expect(page.getByText("全部首页 赞了你的内容")).toBeVisible();
  await page.getByRole("button", { name: "加载更多", exact: true }).click();
  await expect.poll(() => oldStarted).toBe(true);
  await page.getByRole("tab", { name: "互动", exact: true }).click();
  await expect(page.getByText("互动首页 赞了你的内容")).toBeVisible();
  releaseOld();
  await page.getByRole("button", { name: "加载更多", exact: true }).click();
  await expect(page.getByText("互动第二页 赞了你的内容")).toBeVisible();
  await expect(page.getByText("旧分类第二页 赞了你的内容")).toHaveCount(0);
});
