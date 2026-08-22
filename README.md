# 浅蓝论坛（Flutter）

基于「贴吧的信息结构 + 社区高效入口 + 浅蓝年轻化视觉」实现的移动端论坛 Demo。参考仓库 `https://github.com/zhouwu97/luntan` 当前为空仓库，因此本工程以产品说明和目录中的 HTML 视觉基准为实现依据。

## 已实现

- 首页顶部头像、搜索、消息未读数
- 大型拆箱 / 酱紫社区 / 杂鱼日常三大板块切换
- 推荐 / 最新 / 精华筛选，其中精华只展示 `isFeatured` 内容
- 排行榜、热门帖子、穿搭分享、活动、二手集市入口
- 帖子卡片：作者等级、标签、摘要、点赞、收藏、浏览/回复数
- 0 / 1 / 2 / 3 / 4+ 张图片布局，4+ 张显示剩余数量
- 帖子详情、完整图片画廊、回复输入
- 搜索帖子 / 用户 / 板块
- 下拉刷新和筛选行刷新状态
- 首页 / 发布 / 我的三段底部导航
- 普通帖子、投票、二手闲置发布入口；普通帖和闲置可真实加入本地信息流
- 我的页面：用户信息、统计数据、收藏/点赞/浏览历史入口
- 积分兑换商店：徽章、钥匙扣、贴纸、帆布袋，积分扣减逻辑已接通

当前数据层是本地 `ChangeNotifier` mock store，方便先验证 UI 和交互；后续可以把 `ForumStore` 的读取和写入替换为 REST、Supabase 或现有后端 API。

## 运行

```bash
flutter pub get
flutter run
```

Web：

```bash
flutter run -d chrome
```

验证：

```bash
flutter analyze
flutter test
flutter build web --release
```

## 目录

```text
lib/
  app.dart
  data/mock_forum_data.dart
  screens/
    home_screen.dart
    feature_page.dart
    post_detail_screen.dart
    profile_screen.dart
    exchange_store_screen.dart
  widgets/
    forum_post_card.dart
    forum_author_row.dart
    post_media_preview.dart
    composer_sheet.dart
    messages_sheet.dart
  theme/app_theme.dart
```
