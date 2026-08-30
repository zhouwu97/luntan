# 个人中心与兑换商店视觉 QA

## 结论

final result: passed

本轮按用户提供的六张截图逐项验收个人中心、个人主页与兑换商店。截图中的原始界面作为结构与状态参考；“游客永久 Lv.0、经验可累计、设置权限提示、签名与 ID、三项商品和固定积分规则”作为本轮明确的预期差异。

## 对照证据

- source visual truth:
  - `C:/Users/haha/AppData/Local/Temp/codex-clipboard-08883988-01e5-4e39-a40b-557dc66eadab.png`（图一，681 × 1358）
  - `C:/Users/haha/AppData/Local/Temp/codex-clipboard-a8fbdac3-fef5-4878-b7e3-b50c959ab85b.png`（图三，681 × 1358）
  - `C:/Users/haha/AppData/Local/Temp/codex-clipboard-08f524e0-77a6-49b0-8aaa-f13f19be413b.png`（图五，681 × 1358）
- implementation captures:
  - `E:/AI/bb/artifacts/design-qa/local-guest-settings.jpg`（681 × 1162）
  - `E:/AI/bb/artifacts/design-qa/local-guest-public-id.jpg`（681 × 1162）
  - `E:/AI/bb/artifacts/design-qa/comparison-profile.jpg`（1386 × 1410，图三与实现同屏比较）
  - `E:/AI/bb/artifacts/design-qa/online-guest-settings.jpg`（公网游客设置权限）
  - `E:/AI/bb/artifacts/design-qa/online-guest-profile.jpg`（公网游客主页）
  - `E:/AI/bb/artifacts/design-qa/online-registered-id.jpg`（公网正式账号 ID 10000）
- viewport/state: Codex 应用内浏览器，移动端 681px 宽；本地与公网 QA API 游客会话；个人中心 → 设置、个人主页 → 主页设置两条路径均实测，并使用正式账号资料复验数字 ID。

## 聚焦区域与结果

- 图一个人中心积分卡：吉祥物从 34px 缩至 28px，卡片上下留白、图文间距和余额字号同步收紧；游客状态改为紧凑的“游客模式 · 当前累计 N EXP”说明条，不再伪装成普通等级卡。
- 游客等级：个人中心和个人主页均显示 `Lv.0`；经验区显示“累计经验 N EXP · 注册后解锁等级”。浏览器验收发现一次无本地用户对象时误显示 `Lv.1` 的边界问题，修复后重新截图并通过。
- 设置权限：个人中心齿轮与个人主页齿轮均弹出“暂无设置权限”，明确建议绑定邮箱并说明经验、评论保留；未进入设置或编辑资料页面。
- 图三信息行：原账号/信任组合行已替换为独立的签名与数字 `ID` 展示。正式账号注册或游客绑定邮箱时从 `10000` 起顺序分配，游客显示“注册后生成”；内部 UUID 不再直接展示。
- 图五兑换商店：自动化界面测试确认只保留论坛纪念徽章 60、论坛纪念立牌 300、200 元杯子盲盒（可许愿）600；旧贴纸、钥匙扣、帆布袋均不出现；兑换后“我的兑换”立即出现记录。
- 图六积分规则：界面与服务端统一为发帖 +5、点赞 +1、评论 +1、上海自然日合计上限 20；服务端不再接受环境变量覆盖这些公开规则。

## 迭代历史

1. 首轮实现等级阈值、游客锁级、权限弹窗、签名/ID、紧凑卡片与商店规则。
2. 完成 Flutter/Go 自动化测试后进入浏览器实机验收。
3. 浏览器发现“游客无本地用户对象”路径仍显示 `Lv.1` 且 ID 为空；补充会话身份兜底与 ID fallback，并新增回归测试。
4. 重新加载同一视口、同一路径复验：`Lv.0`、累计经验提示、`ID：注册后生成`、两处权限弹窗均通过；注册账号数字 ID 由组件与接口测试覆盖。
5. 部署后在公网新会话复验：游客页面与权限提示通过；正式账号 `测试账号A` 显示 `ID：10000`、`Lv.1`、`0 / 50 EXP`。数据库 1122 个正式账号已按注册顺序回填 `10000–11121`，游客未分配。

## 控制台、交互与自动化

- 应用内浏览器：核心路径交互 passed；更新后的全新公网标签页 error/warning 均为 0。发布切换期间旧 PWA 缓存曾产生一次 CanvasKit 历史日志，清缓存式新会话复验未复现。
- `flutter analyze` — passed，0 issues。
- `flutter test` — passed，220 tests。
- `go test ./...` — passed。
- 兑换商店专项组件测试 — passed。
- 公网 `/ready` — passed，API 与 worker 进程正常；最近 200 行 API 日志未发现 ERROR、FATAL、panic。
