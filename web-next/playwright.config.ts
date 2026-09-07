import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./e2e",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: "list",
  use: {
    baseURL: process.env.PLAYWRIGHT_TEST_BASE_URL || "http://127.0.0.1:3000",
    trace: "on-first-retry",
  },
  webServer: process.env.PLAYWRIGHT_TEST_BASE_URL
    ? undefined
    : {
        command: "npm run start",
        url: "http://127.0.0.1:3000",
        env: {
          ...process.env,
          // UI 契约测试由浏览器路由提供 fixture，SSR 不得穿透生产 API。
          API_PROXY_TARGET: "http://127.0.0.1:65534",
        },
        reuseExistingServer: !process.env.CI,
        timeout: 120000,
      },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
    {
      name: "webkit-smoke",
      testMatch: /(?:webkit-smoke|gif-media-regression|poll-parity)\.spec\.ts/,
      use: { ...devices["iPhone 15"] },
    },
  ],
});
