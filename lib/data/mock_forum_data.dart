import 'package:flutter/foundation.dart';

import '../domain/models.dart';

export '../domain/models.dart' show Comment, Community, CommunityCategory, FeedPage, MediaAsset, Post, PostDetail, Reaction, User, ViewerPostState;

typedef PostMedia = MediaAsset;

/// 兼容当前 UI 的板块选择值。
///
/// 真实业务关系已经由 Post.communityId -> Community.id 表达；这个枚举只在
/// Mock/过渡层把现有三个板块映射成动态 Community，后续接 API 时可移除。
enum ForumSection { unboxing, community, daily }

enum FeedSort { recommended, latest, featured }

extension ForumSectionLabel on ForumSection {
  String get label => switch (this) {
        ForumSection.unboxing => '大型拆箱',
        ForumSection.community => '酱紫社区',
        ForumSection.daily => '杂鱼日常',
      };

  String get communityId => switch (this) {
        ForumSection.unboxing => 'community-unboxing',
        ForumSection.community => 'community-campus',
        ForumSection.daily => 'community-daily',
      };
}

extension PostForumPresentation on Post {
  ForumSection get section => switch (communityId) {
        'community-campus' => ForumSection.community,
        'community-daily' => ForumSection.daily,
        _ => ForumSection.unboxing,
      };
}

extension FeedSortLabel on FeedSort {
  String get label => switch (this) {
        FeedSort.recommended => '推荐',
        FeedSort.latest => '最新',
        FeedSort.featured => '精华',
      };
}

class PostDraft {
  const PostDraft({required this.title, required this.body, required this.section, this.isMarket = false});

  final String title;
  final String body;
  final ForumSection section;
  final bool isMarket;
}

class StoreProduct {
  const StoreProduct({required this.name, required this.description, required this.emoji, required this.points, required this.color});

  final String name;
  final String description;
  final String emoji;
  final int points;
  final int color;
}

class ForumStore extends ChangeNotifier {
  ForumStore._(this.posts, this.communities);

  factory ForumStore.seeded() => ForumStore._(_seedPosts(), _seedCommunities());

  final List<Post> posts;
  final List<Community> communities;
  final List<Post> history = [];
  ForumSection selectedSection = ForumSection.unboxing;
  FeedSort selectedSort = FeedSort.recommended;
  bool isRefreshing = false;
  int unreadMessages = 8;
  int points = 3980;
  int publishedCount = 119;
  int replyCount = 2584;
  int followedBoards = 20;

  Community get selectedCommunity => communities.firstWhere((item) => item.id == selectedSection.communityId);

  List<Post> get visiblePosts {
    final result = posts.where((post) => post.communityId == selectedSection.communityId).where((post) {
      if (selectedSort == FeedSort.featured) return post.isFeatured;
      return true;
    }).toList();
    if (selectedSort == FeedSort.latest) {
      result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } else if (selectedSort == FeedSort.featured) {
      result.sort((a, b) => b.commentCount.compareTo(a.commentCount));
    }
    return result;
  }

  List<Post> search(String query) {
    final keyword = query.trim().toLowerCase();
    if (keyword.isEmpty) return posts;
    return posts.where((post) => '${post.title} ${post.content} ${post.author?.nickname ?? ''} ${post.tags.join(' ')}'.toLowerCase().contains(keyword)).toList();
  }

  void selectSection(ForumSection section) {
    selectedSection = section;
    notifyListeners();
  }

  void selectSort(FeedSort sort) {
    selectedSort = sort;
    notifyListeners();
  }

  Future<int> refresh() async {
    if (isRefreshing) return 0;
    isRefreshing = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 520));
    isRefreshing = false;
    notifyListeners();
    return visiblePosts.length;
  }

  void toggleLike(Post post) {
    post.isLiked = !post.isLiked;
    post.likeCount += post.isLiked ? 1 : -1;
    notifyListeners();
  }

  void toggleBookmark(Post post) {
    post.isBookmarked = !post.isBookmarked;
    post.bookmarkCount += post.isBookmarked ? 1 : -1;
    notifyListeners();
  }

  void recordHistory(Post post) {
    history.removeWhere((item) => item.id == post.id);
    history.insert(0, post);
    if (history.length > 20) history.removeLast();
    notifyListeners();
  }

  void markMessagesRead() {
    unreadMessages = 0;
    notifyListeners();
  }

  void addPost(PostDraft draft) {
    final now = DateTime.now();
    final post = Post(
      id: 'user-${now.microsecondsSinceEpoch}',
      authorId: _currentUser.id,
      author: _currentUser,
      communityId: draft.section.communityId,
      community: communities.firstWhere((item) => item.id == draft.section.communityId),
      type: draft.isMarket ? PostType.market : PostType.normal,
      title: draft.isMarket ? '【二手】${draft.title}' : draft.title,
      content: draft.body,
      createdAt: now,
      updatedAt: now,
      publishedAt: now,
      viewCount: 1,
      tags: [draft.isMarket ? '二手集市' : draft.section.label],
      extraTag: '新发布',
    );
    posts.insert(0, post);
    selectedSection = draft.section;
    selectedSort = FeedSort.latest;
    publishedCount++;
    notifyListeners();
  }

  bool redeem(StoreProduct product) {
    if (points < product.points) return false;
    points -= product.points;
    notifyListeners();
    return true;
  }
}

final _now = DateTime.now();
final _currentUser = User(id: 'user-1', username: 'xiaoli', nickname: '小理不理', level: 8, createdAt: _now.subtract(const Duration(days: 300)), updatedAt: _now);
final _users = <String, User>{
  _currentUser.id: _currentUser,
  'user-2': User(id: 'user-2', username: 'zhuodong', nickname: '桌搭同学', level: 6, createdAt: _now, updatedAt: _now),
  'user-3': User(id: 'user-3', username: 'anjing', nickname: '安静一点', level: 4, createdAt: _now, updatedAt: _now),
  'user-4': User(id: 'user-4', username: 'pixel', nickname: '像素观察员', level: 5, createdAt: _now, updatedAt: _now),
  'user-5': User(id: 'user-5', username: 'chichi', nickname: '吃吃吃同学', level: 7, createdAt: _now, updatedAt: _now),
  'user-6': User(id: 'user-6', username: 'jiulian', nickname: '纠结新人', level: 3, createdAt: _now, updatedAt: _now),
  'user-7': User(id: 'user-7', username: 'baike', nickname: '校园百科', level: 9, createdAt: _now, updatedAt: _now),
  'user-8': User(id: 'user-8', username: 'xuexi', nickname: '沉迷学习', level: 6, createdAt: _now, updatedAt: _now),
  'user-9': User(id: 'user-9', username: 'wanfeng', nickname: '晚风路人', level: 2, createdAt: _now, updatedAt: _now),
  'user-10': User(id: 'user-10', username: 'zhuanzhuan', nickname: '转转达人', level: 5, createdAt: _now, updatedAt: _now),
  'user-11': User(id: 'user-11', username: 'yangtai', nickname: '阳台观察员', level: 4, createdAt: _now, updatedAt: _now),
};

List<Community> _seedCommunities() => const [
      Community(id: 'community-unboxing', slug: 'unboxing', name: '大型拆箱', description: '分享设备、桌搭和真实使用体验', categoryId: 'category-digital', sortOrder: 1),
      Community(id: 'community-campus', slug: 'campus', name: '酱紫社区', description: '校园讨论、问答和同学交流', categoryId: 'category-campus', sortOrder: 2),
      Community(id: 'community-daily', slug: 'daily', name: '杂鱼日常', description: '记录校园生活与身边的小事', categoryId: 'category-life', sortOrder: 3),
    ];

const _keyboard = [MediaAsset(id: 'media-keyboard', type: MediaType.image, emoji: '⌨️', label: '机械键盘', colors: [0xFFB7D9FF, 0xFF6D9CDE])];
const _campus = [MediaAsset(id: 'media-campus', type: MediaType.image, emoji: '📚', label: '校园桌面', colors: [0xFFCEE9FF, 0xFF7FB6E5])];
const _daily = [MediaAsset(id: 'media-daily', type: MediaType.image, emoji: '🌙', label: '晚霞随拍', colors: [0xFFFFD2B2, 0xFFEA8FB1])];
const _market = [MediaAsset(id: 'media-market', type: MediaType.image, emoji: '📦', label: '闲置好物', colors: [0xFFFFE5BC, 0xFFE5A55B])];

Post _post({
  required String id,
  required String authorId,
  required String title,
  required String body,
  required ForumSection section,
  required String tag,
  required int hoursAgo,
  required int comments,
  required int views,
  String? extraTag,
  bool isFeatured = false,
  List<MediaAsset> images = const [],
}) {
  final createdAt = _now.subtract(Duration(hours: hoursAgo));
  final community = _seedCommunities().firstWhere((item) => item.id == section.communityId);
  return Post(id: id, authorId: authorId, author: _users[authorId], communityId: community.id, community: community, title: title, content: body, commentCount: comments, likeCount: comments ~/ 3, viewCount: views, createdAt: createdAt, updatedAt: createdAt, publishedAt: createdAt, tags: [tag], extraTag: extraTag, isFeatured: isFeatured, media: images);
}

List<Post> _seedPosts() => [
      _post(id: 'u1', authorId: 'user-1', title: '新人手的机械键盘开箱！手感绝了', body: '等了好久终于到手，颜值在线，打字声音也很好听，顺手分享一下轴体、手感和桌搭。', section: ForumSection.unboxing, tag: '大型拆箱', hoursAgo: 2, comments: 128, views: 3200, extraTag: '推荐好帖', isFeatured: true, images: _keyboard),
      _post(id: 'u2', authorId: 'user-2', title: '图书馆桌面新搭配：平板支架 + 台灯 + 便携键盘', body: '不是纯晒图，顺便把实际使用感受、价格和避坑点也写了一下。', section: ForumSection.unboxing, tag: '穿搭分享', hoursAgo: 5, comments: 64, views: 1400, images: _campus),
      _post(id: 'u3', authorId: 'user-3', title: '宿舍降噪耳机实测：晚自习和午休都能用吗？', body: '对比了佩戴感、主动降噪、漏音和睡觉时的压耳问题，尽量讲细一点。', section: ForumSection.unboxing, tag: '大型拆箱', hoursAgo: 26, comments: 53, views: 980, images: [..._daily, ..._campus]),
      _post(id: 'u4', authorId: 'user-4', title: '刚拿到手的 2K 显示器，先发个开箱首图', body: '先放外观和接口，后面再补色彩和护眼体验。', section: ForumSection.unboxing, tag: '大型拆箱', hoursAgo: 0, comments: 8, views: 136, images: [..._campus, ..._keyboard]),
      _post(id: 'u5', authorId: 'user-1', title: '从零搭一个舒服的宿舍桌面：完整清单', body: '把我这半年试过的桌搭方案重新整理了一遍，预算、使用感和优先级都写上。', section: ForumSection.unboxing, tag: '大型拆箱', hoursAgo: 72, comments: 236, views: 7800, extraTag: '精华', isFeatured: true, images: [..._keyboard, ..._campus, ..._daily, ..._market, ..._keyboard]),
      _post(id: 'c1', authorId: 'user-5', title: '理工食堂哪家强？来投票 🍜', body: '把常去的窗口都放上来了，欢迎顺便留言说说你最常点的菜和踩雷经历。', section: ForumSection.community, tag: '酱紫社区', hoursAgo: 4, comments: 96, views: 1800, extraTag: '热门讨论', isFeatured: true, images: _campus),
      _post(id: 'c2', authorId: 'user-6', title: '新学期社团招新，有没有值得冲的推荐？', body: '偏想找氛围好、不会太水的那种，有经验的学长学姐可以聊聊。', section: ForumSection.community, tag: '酱紫社区', hoursAgo: 6, comments: 81, views: 1200, images: _daily),
      _post(id: 'c3', authorId: 'user-7', title: '新生校园生活问答合集：宿舍 / 食堂 / 图书馆', body: '把高频问题都整理在一起，后续还能持续补充，适合固定沉淀。', section: ForumSection.community, tag: '酱紫社区', hoursAgo: 336, comments: 329, views: 9400, extraTag: '精华', isFeatured: true, images: [..._campus, ..._daily, ..._market]),
      _post(id: 'd1', authorId: 'user-8', title: '图书馆自习位置分享（持续更新）', body: '按楼层把我坐过的位置都写了，顺便标一下插座、空调和是否容易抢到。', section: ForumSection.daily, tag: '杂鱼日常', hoursAgo: 6, comments: 64, views: 1200, extraTag: '持续更新', isFeatured: true, images: _daily),
      _post(id: 'd2', authorId: 'user-9', title: '今晚的云真的很好看，顺手发几张校园随拍', body: '不是专业拍照，就觉得晚霞和路灯那会儿特别有氛围。', section: ForumSection.daily, tag: '杂鱼日常', hoursAgo: 8, comments: 37, views: 682, images: [..._daily, ..._campus, ..._keyboard]),
      _post(id: 'd3', authorId: 'user-10', title: '【二手】出九成新 Kindle Paperwhite 5', body: '平时用得少，机身成色不错，盒子和线都还在，校内可面交。', section: ForumSection.daily, tag: '二手集市', hoursAgo: 24, comments: 35, views: 890, images: _market),
      _post(id: 'd4', authorId: 'user-11', title: '宿舍养的绿植终于活下来了', body: '上个月差点以为救不回来了，今天看见新叶心情很好。', section: ForumSection.daily, tag: '杂鱼日常', hoursAgo: 0, comments: 2, views: 32),
    ];

const storeProducts = [
  StoreProduct(name: '论坛纪念徽章', description: '论坛限定周边', emoji: '🏅', points: 600, color: 0xFFFFD77A),
  StoreProduct(name: '校园钥匙扣', description: '限量周边', emoji: '🔑', points: 900, color: 0xFFA9D8FF),
  StoreProduct(name: '主题贴纸包', description: '社区纪念', emoji: '✨', points: 350, color: 0xFFFFB9D0),
  StoreProduct(name: '校园帆布袋', description: '生活周边', emoji: '👜', points: 1800, color: 0xFFB8E8D5),
];
