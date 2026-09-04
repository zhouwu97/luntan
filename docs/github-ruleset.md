# GitHub 分支保护与 CI 自动化门禁配置指引

为确保 `main` 分支代码质量受自动化 CI 严格保护，防止任何未经测试或测试失败的代码直接合并/推送，推荐在 GitHub 仓库中配置 Branch Ruleset。

---

## 1. 进入配置界面

1. 打开 GitHub 仓库页面：`https://github.com/zhouwu97/luntan`
2. 点击顶部导航栏 **Settings**。
3. 在左侧菜单中展开 **Rules** -> 点击 **Rulesets**。
4. 点击右上角 **New ruleset** -> 选择 **New branch ruleset**。

---

## 2. 规则集基本信息 (General)

- **Ruleset Name**: `protect-main`
- **Enforcement status**: `Active`
- **Bypass list** (可选，若个人开发允许紧急修复直推):
  - 添加 `Repository Admin` (Role) -> 勾选 `Always allow` (仅限应急，日常依然推荐走 PR)。

---

## 3. 目标分支 (Target branches)

- 点击 **Add target** -> 选择 **Include default branch**（或 Include by pattern -> `main`）。

---

## 4. 保护规则 (Branch rules)

勾选以下关键门禁规则：

### A. 限制直推与删除
- 勾选 **Restrict deletions**（防止误删 main 分支）
- 勾选 **Block force pushes**（禁止强制推送 `git push -f`，保护提交历史线性完整）

### B. 要求 Pull Request 合并
- 勾选 **Require a pull request before merging**
  - **Required approvals**: 设为 `0`（单人维护项目）或 `1`（多人协作）
  - 勾选 **Dismiss stale pull request approvals when new commits are pushed**

### C. 必须通过状态检查 (Status checks) —— 核心门禁
- 勾选 **Require status checks to pass**
- 勾选 **Require branches to be up to date before merging**
- 在 **Status checks that are required** 搜索框中，依次添加当前 `.github/workflows/ci.yml` 声明的 4 个顶级 Job：
  1. `flutter`（运行 Flutter analyze、全部单元测试、Web 与 APK Release 构建）
  2. `go`（运行 Go 单元测试、vet、构建及 govulncheck）
  3. `web`（运行 Next.js typecheck、Next.js 生产构建及 Playwright Chromium E2E 自动化测试）
  4. `security`（独立运行 Gitleaks 敏感信息扫描，不受测试状态阻塞）

---

## 5. 保存并生效

点击底部 **Save changes**。

配置生效后：
- 任何推向 `main` 分支的 PR 都必须等待 `flutter`、`go`、`web`、`security` 四个 Job 全部显示绿色勾（Success）方可合并。
- 敏感信息泄露扫描在独立的 `security` Job 中与单元测试并行执行，即时拦截任何误入代码库的密钥或凭据。
