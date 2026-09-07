import { expect, test } from "@playwright/test";

test("旧帖子链接永久跳转到当前详情路由", async ({ request }) => {
  const response = await request.get("/posts/post-legacy-1", {
    maxRedirects: 0,
  });

  expect(response.status()).toBe(308);
  expect(response.headers().location).toBe("/post/post-legacy-1");
});
