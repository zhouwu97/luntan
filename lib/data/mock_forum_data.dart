import 'package:flutter/foundation.dart';

import '../domain/models.dart';

export '../domain/models.dart'
    show
        Comment,
        Community,
        CommunityCategory,
        FeedPage,
        MediaAsset,
        Post,
        PostDetail,
        Reaction,
        User,
        ViewerPostState,
        relativeTimeLabel;

typedef PostMedia = MediaAsset;

/// 兼容当前 UI 的板块选择值。
///
/// 真实业务关系已经由 Post.communityId -> Community.id 表达；这个枚举只在
/// Mock/过渡层把现有三个板块映射成动态 Community，后续接 API 时可移除。
enum ForumSection { unboxing, community, daily }

enum FeedSort { recommended, latest, featured, hot }

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
    FeedSort.hot => '热门',
  };
}

int _comparePostsByPublishTime(Post a, Post b) {
  final byTime = (b.publishedAt ?? b.createdAt).compareTo(
    a.publishedAt ?? a.createdAt,
  );
  return byTime == 0 ? b.id.compareTo(a.id) : byTime;
}

int _compareCommentsByTime(Comment a, Comment b) {
  final byTime = a.createdAt.compareTo(b.createdAt);
  return byTime == 0 ? a.id.compareTo(b.id) : byTime;
}

class PostDraft {
  const PostDraft({
    required this.title,
    required this.body,
    required this.section,
    this.isGameShare = false,
    this.isPoll = false,
    this.media = const [],
    this.mediaIds = const [],
    this.pollOptions = const [],
    this.allowMultiple = false,
    this.pollEndsAt,
  });

  final String title;
  final String body;
  final ForumSection section;
  final bool isGameShare;
  final bool isPoll;
  final List<MediaAsset> media;
  final List<String> mediaIds;
  final List<String> pollOptions;
  final bool allowMultiple;
  final DateTime? pollEndsAt;
}

class StoreProduct {
  const StoreProduct({
    required this.name,
    required this.description,
    required this.emoji,
    required this.points,
    required this.color,
  });

  final String name;
  final String description;
  final String emoji;
  final int points;
  final int color;
}

class ForumStore extends ChangeNotifier {
  ForumStore._(
    this.posts,
    this.communities, {
    Map<String, List<Comment>>? comments,
  }) : commentsByPost = comments ?? _seedComments();

  factory ForumStore.seeded() => ForumStore._(_seedPosts(), _seedCommunities());

  /// API 模式只需要板块和本地 UI 筛选状态，不应预加载一套会与服务端
  /// 冲突的演示帖子、评论或用户资料。
  factory ForumStore.uiOnly() => ForumStore._(
    <Post>[],
    _seedCommunities(),
    comments: <String, List<Comment>>{},
  );

  final List<Post> posts;
  final List<Community> communities;
  final Map<String, List<Comment>> commentsByPost;
  final Set<String> likedCommentIds = <String>{};
  final List<Post> history = [];
  ForumSection selectedSection = ForumSection.unboxing;
  // 首页默认按发布时间倒序，推荐/精华/热门仍可通过筛选主动切换。
  FeedSort selectedSort = FeedSort.latest;
  bool isRefreshing = false;
  int unreadMessages = 8;
  int points = 3980;
  int publishedCount = 119;
  int replyCount = 2584;
  int followedBoards = 20;

  Community get selectedCommunity =>
      communities.firstWhere((item) => item.id == selectedSection.communityId);

  List<Post> get visiblePosts {
    final result = posts
        .where((post) => post.communityId == selectedSection.communityId)
        .where((post) {
          if (selectedSort == FeedSort.featured) return post.isFeatured;
          return true;
        })
        .toList();
    if (selectedSort == FeedSort.latest) {
      result.sort(_comparePostsByPublishTime);
    } else if (selectedSort == FeedSort.featured) {
      result.sort((a, b) => b.commentCount.compareTo(a.commentCount));
    }
    return result;
  }

  List<Post> search(String query) {
    final keyword = query.trim().toLowerCase();
    if (keyword.isEmpty) return posts;
    return posts
        .where(
          (post) =>
              '${post.title} ${post.content} ${post.author?.nickname ?? ''} ${post.tags.join(' ')}'
                  .toLowerCase()
                  .contains(keyword),
        )
        .toList();
  }

  List<User> searchUsers(String query) {
    final keyword = query.trim().toLowerCase();
    if (keyword.isEmpty) return _users.values.toList();
    return _users.values
        .where(
          (user) => '${user.nickname} ${user.username} ${user.signature ?? ''}'
              .toLowerCase()
              .contains(keyword),
        )
        .toList();
  }

  List<Community> searchCommunities(String query) {
    final keyword = query.trim().toLowerCase();
    if (keyword.isEmpty) return communities;
    return communities
        .where(
          (community) => '${community.name} ${community.description}'
              .toLowerCase()
              .contains(keyword),
        )
        .toList();
  }

  List<Comment> commentsFor(Post post) {
    final result = [...(commentsByPost[post.id] ?? const <Comment>[])]
      ..sort(_compareCommentsByTime);
    return List.unmodifiable(result);
  }

  List<Post> get bookmarkedPosts =>
      posts.where((post) => post.isBookmarked).toList();

  List<Post> get likedPosts => posts.where((post) => post.isLiked).toList();

  User? userById(String id) => _users[id];

  bool isCommentLiked(Comment comment) => likedCommentIds.contains(comment.id);

  void toggleCommentLike(Comment comment) {
    if (!likedCommentIds.add(comment.id)) likedCommentIds.remove(comment.id);
    notifyListeners();
  }

  void selectSection(ForumSection section) {
    selectedSection = section;
    notifyListeners();
  }

  void touch() => notifyListeners();

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
    // Mock repository没有远端增量游标，暂无新增时必须返回 0，不能拿当前列表长度冒充新增数。
    return 0;
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
      community: communities.firstWhere(
        (item) => item.id == draft.section.communityId,
      ),
      type: draft.isGameShare
          ? PostType.gameShare
          : draft.isPoll
          ? PostType.poll
          : PostType.normal,
      title: draft.isGameShare ? '【玩法分享】${draft.title}' : draft.title,
      content: draft.body,
      createdAt: now,
      updatedAt: now,
      publishedAt: now,
      viewCount: 1,
      tags: [draft.isGameShare ? '玩法分享' : draft.section.label],
      extraTag: '新发布',
      media: draft.media,
    );
    posts.insert(0, post);
    selectedSection = draft.section;
    selectedSort = FeedSort.latest;
    publishedCount++;
    notifyListeners();
  }

  Comment addComment(
    Post post,
    String content, {
    String? parentId,
    String? replyToUserId,
  }) {
    final now = DateTime.now();
    final comments = commentsByPost.putIfAbsent(post.id, () => <Comment>[]);
    final comment = Comment(
      id: 'comment-${now.microsecondsSinceEpoch}',
      postId: post.id,
      authorId: _currentUser.id,
      rootId: parentId == null ? null : _rootIdForReply(comments, parentId),
      parentId: parentId,
      replyToUserId: replyToUserId,
      content: content,
      createdAt: now,
      updatedAt: now,
    );
    comments.add(comment);
    post.commentCount += 1;
    replyCount += 1;
    notifyListeners();
    return comment;
  }

  void deleteComment(Post post, Comment comment) {
    final comments = commentsByPost[post.id];
    if (comments == null) return;
    comments.removeWhere((item) => item.id == comment.id);
    post.commentCount = post.commentCount > 0 ? post.commentCount - 1 : 0;
    replyCount = replyCount > 0 ? replyCount - 1 : 0;
    notifyListeners();
  }

  String _rootIdForReply(List<Comment> comments, String parentId) {
    for (final comment in comments) {
      if (comment.id == parentId) return comment.rootId ?? comment.id;
    }
    return parentId;
  }

  bool redeem(StoreProduct product) {
    if (points < product.points) return false;
    points -= product.points;
    notifyListeners();
    return true;
  }
}

final _now = DateTime.now();
final _currentUser = User(
  id: 'user-1',
  username: 'xiaoli',
  nickname: '小理不理',
  level: 8,
  createdAt: _now.subtract(const Duration(days: 300)),
  updatedAt: _now,
);
final _users = <String, User>{
  _currentUser.id: _currentUser,
  'user-2': User(
    id: 'user-2',
    username: 'zhuodong',
    nickname: '桌搭同学',
    level: 6,
    createdAt: _now,
    updatedAt: _now,
  ),
  'user-3': User(
    id: 'user-3',
    username: 'anjing',
    nickname: '安静一点',
    level: 4,
    createdAt: _now,
    updatedAt: _now,
  ),
  'user-4': User(
    id: 'user-4',
    username: 'pixel',
    nickname: '像素观察员',
    level: 5,
    createdAt: _now,
    updatedAt: _now,
  ),
  'user-5': User(
    id: 'user-5',
    username: 'chichi',
    nickname: '吃吃吃同学',
    level: 7,
    createdAt: _now,
    updatedAt: _now,
  ),
  'user-6': User(
    id: 'user-6',
    username: 'jiulian',
    nickname: '纠结新人',
    level: 3,
    createdAt: _now,
    updatedAt: _now,
  ),
  'user-7': User(
    id: 'user-7',
    username: 'baike',
    nickname: '校园百科',
    level: 9,
    createdAt: _now,
    updatedAt: _now,
  ),
  'user-8': User(
    id: 'user-8',
    username: 'xuexi',
    nickname: '沉迷学习',
    level: 6,
    createdAt: _now,
    updatedAt: _now,
  ),
  'user-9': User(
    id: 'user-9',
    username: 'wanfeng',
    nickname: '晚风路人',
    level: 2,
    createdAt: _now,
    updatedAt: _now,
  ),
  'user-10': User(
    id: 'user-10',
    username: 'zhuanzhuan',
    nickname: '转转达人',
    level: 5,
    createdAt: _now,
    updatedAt: _now,
  ),
  'user-11': User(
    id: 'user-11',
    username: 'yangtai',
    nickname: '阳台观察员',
    level: 4,
    createdAt: _now,
    updatedAt: _now,
  ),
};

List<Community> _seedCommunities() => const [
  Community(
    id: 'community-unboxing',
    slug: 'unboxing',
    name: '大型拆箱',
    description: '分享设备、桌搭和真实使用体验',
    categoryId: 'category-digital',
    sortOrder: 1,
  ),
  Community(
    id: 'community-campus',
    slug: 'campus',
    name: '酱紫社区',
    description: '校园讨论、问答和同学交流',
    categoryId: 'category-campus',
    sortOrder: 2,
  ),
  Community(
    id: 'community-daily',
    slug: 'daily',
    name: '杂鱼日常',
    description: '记录校园生活与身边的小事',
    categoryId: 'category-life',
    sortOrder: 3,
  ),
];

const _keyboard = [
  MediaAsset(
    id: 'media-keyboard',
    type: MediaType.image,
    url:
        'https://images.unsplash.com/photo-1688525425714-12851414c3e7?auto=format&fit=crop&w=900&q=82',
    width: 1200,
    height: 900,
    emoji: '⌨️',
    label: '机械键盘',
    colors: [0xFFB7D9FF, 0xFF6D9CDE],
  ),
];
const _campus = [
  MediaAsset(
    id: 'media-campus',
    type: MediaType.image,
    url:
        'https://images.unsplash.com/photo-1743268139156-b9d8c1d4e98e?auto=format&fit=crop&w=700&q=80',
    width: 1200,
    height: 800,
    emoji: '📚',
    label: '校园桌面',
    colors: [0xFFCEE9FF, 0xFF7FB6E5],
  ),
];
const _daily = [
  MediaAsset(
    id: 'media-daily',
    type: MediaType.image,
    url:
        'https://static.wixstatic.com/media/94d226_1f3cac2a4f5b450d98d0bc6355cc30ac~mv2.jpg/v1/fill/w_1000,h_900,al_c,q_85/94d226_1f3cac2a4f5b450d98d0bc6355cc30ac~mv2.jpg',
    width: 1000,
    height: 900,
    emoji: '🌙',
    label: '晚霞随拍',
    colors: [0xFFFFD2B2, 0xFFEA8FB1],
  ),
];
const _gameShare = [
  MediaAsset(
    id: 'media-game-share',
    type: MediaType.image,
    url:
        'https://images.squarespace-cdn.com/content/v1/62fbfbed423b4f1bb8caed31/dce67434-bb6b-4a71-87f8-e98dd70cab47/v2-e242x-15y2g.jpg',
    width: 1000,
    height: 700,
    emoji: '🎮',
    label: '玩法示例',
    colors: [0xFFFFE5BC, 0xFFE5A55B],
  ),
];

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
  final community = _seedCommunities().firstWhere(
    (item) => item.id == section.communityId,
  );
  return Post(
    id: id,
    authorId: authorId,
    author: _users[authorId],
    communityId: community.id,
    community: community,
    title: title,
    content: body,
    commentCount: comments,
    likeCount: comments ~/ 3,
    viewCount: views,
    createdAt: createdAt,
    updatedAt: createdAt,
    publishedAt: createdAt,
    tags: [tag],
    extraTag: extraTag,
    isFeatured: isFeatured,
    media: images,
  );
}

List<Post> _seedPosts() => [
  _post(
    id: 'u1',
    authorId: 'user-1',
    title: '新人手的机械键盘开箱！手感绝了',
    body: '等了好久终于到手，颜值在线，打字声音也很好听，顺手分享一下轴体、手感和桌搭。',
    section: ForumSection.unboxing,
    tag: '大型拆箱',
    hoursAgo: 2,
    comments: 128,
    views: 3200,
    extraTag: '推荐好帖',
    isFeatured: true,
    images: _keyboard,
  ),
  _post(
    id: 'u2',
    authorId: 'user-2',
    title: '图书馆桌面新搭配：平板支架 + 台灯 + 便携键盘',
    body: '不是纯晒图，顺便把实际使用感受和避坑点也写了一下。',
    section: ForumSection.unboxing,
    tag: '穿搭分享',
    hoursAgo: 5,
    comments: 64,
    views: 1400,
    images: _campus,
  ),
  _post(
    id: 'u3',
    authorId: 'user-3',
    title: '宿舍降噪耳机实测：晚自习和午休都能用吗？',
    body: '对比了佩戴感、主动降噪、漏音和睡觉时的压耳问题，尽量讲细一点。',
    section: ForumSection.unboxing,
    tag: '大型拆箱',
    hoursAgo: 26,
    comments: 53,
    views: 980,
    images: [..._daily, ..._campus],
  ),
  _post(
    id: 'u4',
    authorId: 'user-4',
    title: '刚拿到手的 2K 显示器，先发个开箱首图',
    body: '先放外观和接口，后面再补色彩和护眼体验。',
    section: ForumSection.unboxing,
    tag: '大型拆箱',
    hoursAgo: 0,
    comments: 8,
    views: 136,
    images: [..._campus, ..._keyboard],
  ),
  _post(
    id: 'u5',
    authorId: 'user-1',
    title: '从零搭一个舒服的宿舍桌面：完整清单',
    body: '把我这半年试过的桌搭方案重新整理了一遍，预算、使用感和优先级都写上。',
    section: ForumSection.unboxing,
    tag: '大型拆箱',
    hoursAgo: 72,
    comments: 236,
    views: 7800,
    extraTag: '精华',
    isFeatured: true,
    images: [..._keyboard, ..._campus, ..._daily, ..._gameShare, ..._keyboard],
  ),
  _post(
    id: 'c1',
    authorId: 'user-5',
    title: '理工食堂哪家强？来投票 🍜',
    body: '把常去的窗口都放上来了，欢迎顺便留言说说你最常点的菜和踩雷经历。',
    section: ForumSection.community,
    tag: '酱紫社区',
    hoursAgo: 4,
    comments: 96,
    views: 1800,
    extraTag: '热门讨论',
    isFeatured: true,
    images: _campus,
  ),
  _post(
    id: 'c2',
    authorId: 'user-6',
    title: '新学期社团招新，有没有值得冲的推荐？',
    body: '偏想找氛围好、不会太水的那种，有经验的学长学姐可以聊聊。',
    section: ForumSection.community,
    tag: '酱紫社区',
    hoursAgo: 6,
    comments: 81,
    views: 1200,
    images: _daily,
  ),
  _post(
    id: 'c3',
    authorId: 'user-7',
    title: '新生校园生活问答合集：宿舍 / 食堂 / 图书馆',
    body: '把高频问题都整理在一起，后续还能持续补充，适合固定沉淀。',
    section: ForumSection.community,
    tag: '酱紫社区',
    hoursAgo: 336,
    comments: 329,
    views: 9400,
    extraTag: '精华',
    isFeatured: true,
    images: [..._campus, ..._daily, ..._gameShare],
  ),
  _post(
    id: 'd1',
    authorId: 'user-8',
    title: '图书馆自习位置分享（持续更新）',
    body: '按楼层把我坐过的位置都写了，顺便标一下插座、空调和是否容易抢到。',
    section: ForumSection.daily,
    tag: '杂鱼日常',
    hoursAgo: 6,
    comments: 64,
    views: 1200,
    extraTag: '持续更新',
    isFeatured: true,
    images: _daily,
  ),
  _post(
    id: 'd2',
    authorId: 'user-9',
    title: '今晚的云真的很好看，顺手发几张校园随拍',
    body: '不是专业拍照，就觉得晚霞和路灯那会儿特别有氛围。',
    section: ForumSection.daily,
    tag: '杂鱼日常',
    hoursAgo: 8,
    comments: 37,
    views: 682,
    images: [..._daily, ..._campus, ..._keyboard],
  ),
  _post(
    id: 'd3',
    authorId: 'user-10',
    title: '玩法分享：宿舍多人桌游局怎么组？',
    body: '整理一套四到六人都能快速上手的桌游流程，包含分组、计分和新手友好规则，欢迎大家补充自己的玩法。',
    section: ForumSection.daily,
    tag: '玩法分享',
    hoursAgo: 24,
    comments: 35,
    views: 890,
    images: _gameShare,
  ),
  _post(
    id: 'd4',
    authorId: 'user-11',
    title: '宿舍养的绿植终于活下来了',
    body: '上个月差点以为救不回来了，今天看见新叶心情很好。',
    section: ForumSection.daily,
    tag: '杂鱼日常',
    hoursAgo: 0,
    comments: 2,
    views: 32,
  ),
];

Map<String, List<Comment>> _seedComments() => {
  'u1': [
    Comment(
      id: 'comment-u1-1',
      postId: 'u1',
      authorId: 'user-2',
      content: '这个整理很有用，尤其是宿舍噪音那段。想问下你用的是什么轴？',
      likeCount: 12,
      replyCount: 1,
      createdAt: _now.subtract(const Duration(hours: 1)),
      updatedAt: _now.subtract(const Duration(hours: 1)),
    ),
    Comment(
      id: 'comment-u1-1-1',
      postId: 'u1',
      authorId: 'user-1',
      rootId: 'comment-u1-1',
      parentId: 'comment-u1-1',
      replyToUserId: 'user-2',
      content: '我这把是偏轻的线性轴，之后可以单独补一楼声音和压力克数。',
      createdAt: _now.subtract(const Duration(minutes: 45)),
      updatedAt: _now.subtract(const Duration(minutes: 45)),
    ),
    Comment(
      id: 'comment-u1-2',
      postId: 'u1',
      authorId: 'user-3',
      content: '图片比例现在看着舒服多了，一张图没有占满整个屏幕。',
      likeCount: 7,
      createdAt: _now.subtract(const Duration(minutes: 48)),
      updatedAt: _now.subtract(const Duration(minutes: 48)),
    ),
    Comment(
      id: 'comment-u1-3',
      postId: 'u1',
      authorId: 'user-4',
      content: '建议再加一个“只看楼主”，这种长讨论会比较方便。',
      likeCount: 4,
      createdAt: _now.subtract(const Duration(minutes: 23)),
      updatedAt: _now.subtract(const Duration(minutes: 23)),
    ),
  ],
  'c1': [
    Comment(
      id: 'comment-c1-1',
      postId: 'c1',
      authorId: 'user-1',
      content: '二食堂的砂锅晚上去比较不排队，先收藏了。',
      likeCount: 8,
      createdAt: _now.subtract(const Duration(hours: 2)),
      updatedAt: _now.subtract(const Duration(hours: 2)),
    ),
  ],
};

const storeProducts = [
  StoreProduct(
    name: '论坛纪念徽章',
    description: '论坛限定周边',
    emoji: '🏅',
    points: 600,
    color: 0xFFFFD77A,
  ),
  StoreProduct(
    name: '校园钥匙扣',
    description: '限量周边',
    emoji: '🔑',
    points: 900,
    color: 0xFFA9D8FF,
  ),
  StoreProduct(
    name: '主题贴纸包',
    description: '社区纪念',
    emoji: '✨',
    points: 350,
    color: 0xFFFFB9D0,
  ),
  StoreProduct(
    name: '校园帆布袋',
    description: '生活周边',
    emoji: '👜',
    points: 1800,
    color: 0xFFB8E8D5,
  ),
];
