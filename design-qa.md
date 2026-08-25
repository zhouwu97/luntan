# rankingList 页面视觉 QA

## 结论

final result: passed

本轮以用户明确指定的 `https://beiyoujiang.com/rankingList` 为基础视觉真值，并按用户最新要求移除了网页底部导航。附件截图只用于确认需要去掉的底部区域。Flutter 页面已切换为无网页底部导航的移动端排行榜结构，并在 Android 模拟器上完成首屏和标签切换回归。

## 对照证据

- source visual truth: `https://beiyoujiang.com/rankingList`
- source capture: `E:/AI/bb/.qa/ranking_website_source.png`
- implementation initial list: `E:/AI/bb/.qa/ranking_without_bottom_nav.png`
- implementation slow-play tab: `E:/AI/bb/.qa/ranking_without_bottom_nav_slow.png`
- state: 首页“玩具排行榜”入口 → 综合热榜；无网页底部导航；随后点击“慢玩入门”切换列表
- source capture: 浏览器中按移动端容器渲染，保留网页滚动条和固定底部导航
- implementation capture: 1080 × 2424 physical px，Android 模拟器纵向屏幕；系统状态栏和手势区保留为宿主环境

## 检查项

- 信息结构：搜索框、加号按钮、五个榜单标签、五个分类入口、NO.1 主榜卡片和排行卡片顺序一致；用户要求的底部导航已移除。
- 布局节奏：网页的 16px 内容边距、10px 卡片间距和 90px 列表卡片高度已落到 Flutter 页面，列表可以延伸到系统手势区上方。
- 视觉 token：网页背景 `#F2F1F6`、白色卡片、`#F3F4F6` 边框、粉色强调色和 12px 圆角层级一致。
- 内容：默认综合榜的主榜与第 2—20 名、评分/想冲人数/标签文案，以及慢玩入门前 6 名均来自目标页采集结果。
- 素材：主图、排行缩略图、分类图片和底部导航图片已下载到 `assets/ranking/` 并通过 Flutter asset bundle 加载。
- 交互：从首页点击“玩具排行榜”打开目标页面；“慢玩入门”切换到对应榜单；Android 返回键仍可回到首页；网页底部导航不再参与交互。

## 比较历史

1. 采集目标网址默认综合榜的 DOM 尺寸、文案、滚动高度和固定底部导航。
2. 将原有“积分兑换”排行榜替换为网站排行榜页面，并把网页素材内置到 Flutter 项目。
3. 根据用户反馈移除底部导航，重新检查默认首屏和慢玩入门切换；无 P0/P1/P2 问题。

## 验证命令

- `flutter analyze` — passed
- `flutter test` — passed（77 tests）
- `flutter build apk --debug --no-pub` — passed
- Android emulator manual path — passed
