import 'package:flutter/foundation.dart';

enum ForumSection { unboxing, community, daily }

enum FeedSort { recommended, latest, featured }

extension ForumSectionLabel on ForumSection {
  String get label => switch (this) {
        ForumSection.unboxing => '大型拆箱',
        ForumSection.community => '酱紫社区',
        ForumSection.daily => '杂鱼日常',
      };
}

extension FeedSortLabel on FeedSort {
  String get label => switch (this) {
        FeedSort.recommended => '推荐',
        FeedSort.latest => '最新',
        FeedSort.featured => '精华',
      };
}

class PostMedia {
  const PostMedia({required this.emoji, required this.label, required this.colors});

  final String emoji;
  final String label;
  final List<int> colors;
}

class Post {
  Post({
    required this.id,
    required this.title,
    required this.body,
    required this.author,
    required this.level,
    required this.time,
    required this.comments,
    required this.views,
    required this.section,
    required this.tag,
    this.extraTag,
    this.isFeatured = false,
    this.isPinned = false,
    this.images = const [],
    this.isLiked = false,
    this.isBookmarked = false,
  });

  final String id;
  final String title;
  final String body;
  final String author;
  final int level;
  final String time;
  int comments;
  final String views;
  final ForumSection section;
  final String tag;
  final String? extraTag;
  final bool isFeatured;
  final bool isPinned;
  final List<PostMedia> images;
  bool isLiked;
  bool isBookmarked;
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
  ForumStore._(this.posts);

  factory ForumStore.seeded() => ForumStore._(_seedPosts());

  final List<Post> posts;
  final List<Post> history = [];
  ForumSection selectedSection = ForumSection.unboxing;
  FeedSort selectedSort = FeedSort.recommended;
  bool isRefreshing = false;
  int unreadMessages = 8;
  int points = 3980;
  int publishedCount = 119;
  int replyCount = 2584;
  int followedBoards = 20;

  List<Post> get visiblePosts {
    final result = posts.where((post) => post.section == selectedSection).where((post) {
      if (selectedSort == FeedSort.featured) return post.isFeatured;
      return true;
    }).toList();
    if (selectedSort == FeedSort.latest) {
      result.sort((a, b) => _relativeTimeScore(a.time).compareTo(_relativeTimeScore(b.time)));
    } else if (selectedSort == FeedSort.featured) {
      result.sort((a, b) => b.comments.compareTo(a.comments));
    }
    return result;
  }

  List<Post> search(String query) {
    final keyword = query.trim().toLowerCase();
    if (keyword.isEmpty) return posts;
    return posts.where((post) => '${post.title} ${post.body} ${post.author} ${post.tag}'.toLowerCase().contains(keyword)).toList();
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
    post.comments += post.isLiked ? 1 : -1;
    notifyListeners();
  }

  void toggleBookmark(Post post) {
    post.isBookmarked = !post.isBookmarked;
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
    final post = Post(
      id: 'user-${DateTime.now().microsecondsSinceEpoch}',
      title: draft.isMarket ? '【二手】${draft.title}' : draft.title,
      body: draft.body,
      author: '小理不理',
      level: 8,
      time: '刚刚',
      comments: 0,
      views: '1',
      section: draft.section,
      tag: draft.isMarket ? '二手集市' : draft.section.label,
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

  static int _relativeTimeScore(String value) {
    if (value == '刚刚') return 0;
    if (value.contains('分钟前')) return 1;
    if (value.contains('小时前')) return 2;
    if (value == '昨天') return 3;
    return 4;
  }
}

const _keyboard = [PostMedia(emoji: '⌨️', label: '机械键盘', colors: [0xFFB7D9FF, 0xFF6D9CDE])];
const _campus = [PostMedia(emoji: '📚', label: '校园桌面', colors: [0xFFCEE9FF, 0xFF7FB6E5])];
const _daily = [PostMedia(emoji: '🌙', label: '晚霞随拍', colors: [0xFFFFD2B2, 0xFFEA8FB1])];
const _market = [PostMedia(emoji: '📦', label: '闲置好物', colors: [0xFFFFE5BC, 0xFFE5A55B])];

List<Post> _seedPosts() => [
      Post(id: 'u1', title: '新人手的机械键盘开箱！手感绝了', body: '等了好久终于到手，颜值在线，打字声音也很好听，顺手分享一下轴体、手感和桌搭。', author: '小理不理', level: 8, time: '2小时前', comments: 128, views: '3.2k', section: ForumSection.unboxing, tag: '大型拆箱', extraTag: '推荐好帖', isFeatured: true, images: _keyboard),
      Post(id: 'u2', title: '图书馆桌面新搭配：平板支架 + 台灯 + 便携键盘', body: '不是纯晒图，顺便把实际使用感受、价格和避坑点也写了一下。', author: '桌搭同学', level: 6, time: '5小时前', comments: 64, views: '1.4k', section: ForumSection.unboxing, tag: '穿搭分享', images: _campus),
      Post(id: 'u3', title: '宿舍降噪耳机实测：晚自习和午休都能用吗？', body: '对比了佩戴感、主动降噪、漏音和睡觉时的压耳问题，尽量讲细一点。', author: '安静一点', level: 4, time: '昨天', comments: 53, views: '980', section: ForumSection.unboxing, tag: '大型拆箱', images: [..._daily, ..._campus]),
      Post(id: 'u4', title: '刚拿到手的 2K 显示器，先发个开箱首图', body: '先放外观和接口，后面再补色彩和护眼体验。', author: '像素观察员', level: 5, time: '刚刚', comments: 8, views: '136', section: ForumSection.unboxing, tag: '大型拆箱', images: [..._campus, ..._keyboard]),
      Post(id: 'u5', title: '从零搭一个舒服的宿舍桌面：完整清单', body: '把我这半年试过的桌搭方案重新整理了一遍，预算、使用感和优先级都写上。', author: '小理不理', level: 8, time: '3天前', comments: 236, views: '7.8k', section: ForumSection.unboxing, tag: '大型拆箱', extraTag: '精华', isFeatured: true, images: [..._keyboard, ..._campus, ..._daily, ..._market, ..._keyboard]),
      Post(id: 'c1', title: '理工食堂哪家强？来投票 🍜', body: '把常去的窗口都放上来了，欢迎顺便留言说说你最常点的菜和踩雷经历。', author: '吃吃吃同学', level: 7, time: '4小时前', comments: 96, views: '1.8k', section: ForumSection.community, tag: '酱紫社区', extraTag: '热门讨论', isFeatured: true, images: _campus),
      Post(id: 'c2', title: '新学期社团招新，有没有值得冲的推荐？', body: '偏想找氛围好、不会太水的那种，有经验的学长学姐可以聊聊。', author: '纠结新人', level: 3, time: '6小时前', comments: 81, views: '1.2k', section: ForumSection.community, tag: '酱紫社区', images: _daily),
      Post(id: 'c3', title: '新生校园生活问答合集：宿舍 / 食堂 / 图书馆', body: '把高频问题都整理在一起，后续还能持续补充，适合固定沉淀。', author: '校园百科', level: 9, time: '2周前', comments: 329, views: '9.4k', section: ForumSection.community, tag: '酱紫社区', extraTag: '精华', isFeatured: true, images: [..._campus, ..._daily, ..._market]),
      Post(id: 'd1', title: '图书馆自习位置分享（持续更新）', body: '按楼层把我坐过的位置都写了，顺便标一下插座、空调和是否容易抢到。', author: '沉迷学习', level: 6, time: '6小时前', comments: 64, views: '1.2k', section: ForumSection.daily, tag: '杂鱼日常', extraTag: '持续更新', isFeatured: true, images: _daily),
      Post(id: 'd2', title: '今晚的云真的很好看，顺手发几张校园随拍', body: '不是专业拍照，就觉得晚霞和路灯那会儿特别有氛围。', author: '晚风路人', level: 2, time: '8小时前', comments: 37, views: '682', section: ForumSection.daily, tag: '杂鱼日常', images: [..._daily, ..._campus, ..._keyboard]),
      Post(id: 'd3', title: '【二手】出九成新 Kindle Paperwhite 5', body: '平时用得少，机身成色不错，盒子和线都还在，校内可面交。', author: '转转达人', level: 5, time: '1天前', comments: 35, views: '890', section: ForumSection.daily, tag: '二手集市', images: _market),
      Post(id: 'd4', title: '宿舍养的绿植终于活下来了', body: '上个月差点以为救不回来了，今天看见新叶心情很好。', author: '阳台观察员', level: 4, time: '刚刚', comments: 2, views: '32', section: ForumSection.daily, tag: '杂鱼日常'),
    ];

const storeProducts = [
  StoreProduct(name: '论坛纪念徽章', description: '论坛限定周边', emoji: '🏅', points: 600, color: 0xFFFFD77A),
  StoreProduct(name: '校园钥匙扣', description: '限量周边', emoji: '🔑', points: 900, color: 0xFFA9D8FF),
  StoreProduct(name: '主题贴纸包', description: '社区纪念', emoji: '✨', points: 350, color: 0xFFFFB9D0),
  StoreProduct(name: '校园帆布袋', description: '生活周边', emoji: '👜', points: 1800, color: 0xFFB8E8D5),
];
