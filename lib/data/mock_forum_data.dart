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
    this.communityId,
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
  final String? communityId;
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
  // Mock 仅用于离线测试；真实运行时由 HomeScreen 显式请求最新流。
  FeedSort selectedSort = FeedSort.recommended;
  bool isRefreshing = false;
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
          if (selectedSort == FeedSort.recommended) return post.isRecommended;
          return true;
        })
        .toList();
    if (selectedSort == FeedSort.latest) {
      result.sort(_comparePostsByPublishTime);
    } else if (selectedSort == FeedSort.featured) {
      result.sort((a, b) => b.commentCount.compareTo(a.commentCount));
    } else if (selectedSort == FeedSort.hot) {
      result.sort((a, b) => b.commentCount.compareTo(a.commentCount));
    } else if (selectedSort == FeedSort.recommended) {
      result.sort((a, b) {
        final posA = a.recommendationPosition ?? 999999;
        final posB = b.recommendationPosition ?? 999999;
        final byPos = posA.compareTo(posB);
        return byPos != 0
            ? byPos
            : (b.publishedAt ?? b.createdAt).compareTo(
                a.publishedAt ?? a.createdAt,
              );
      });
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
  username: 'byj_demo',
  nickname: '杯友小理',
  level: 8,
  createdAt: _now.subtract(const Duration(days: 300)),
  updatedAt: _now,
);
final _users = <String, User>{
  _currentUser.id: _currentUser,
  'user-2': User(
    id: 'user-2',
    username: 'soft_lab',
    nickname: '软萌研究员',
    level: 6,
    createdAt: _now,
    updatedAt: _now,
  ),
  'user-3': User(
    id: 'user-3',
    username: 'slow_player',
    nickname: '慢玩观察员',
    level: 4,
    createdAt: _now,
    updatedAt: _now,
  ),
  'user-4': User(
    id: 'user-4',
    username: 'new_cup_friend',
    nickname: '北优新手',
    level: 5,
    createdAt: _now,
    updatedAt: _now,
  ),
  'user-5': User(
    id: 'user-5',
    username: 'care_notes',
    nickname: '胶体养护员',
    level: 7,
    createdAt: _now,
    updatedAt: _now,
  ),
  'user-6': User(
    id: 'user-6',
    username: 'pillow_keeper',
    nickname: '抱枕收藏家',
    level: 3,
    createdAt: _now,
    updatedAt: _now,
  ),
  'user-7': User(
    id: 'user-7',
    username: 'warm_water',
    nickname: '温水派',
    level: 9,
    createdAt: _now,
    updatedAt: _now,
  ),
  'user-8': User(
    id: 'user-8',
    username: 'night_review',
    nickname: '夜猫试用员',
    level: 6,
    createdAt: _now,
    updatedAt: _now,
  ),
  'user-9': User(
    id: 'user-9',
    username: 'cat_support',
    nickname: '猫猫后勤',
    level: 2,
    createdAt: _now,
    updatedAt: _now,
  ),
  'user-10': User(
    id: 'user-10',
    username: 'orange_soda',
    nickname: '橘子汽水',
    level: 5,
    createdAt: _now,
    updatedAt: _now,
  ),
  'user-11': User(
    id: 'user-11',
    username: 'cup_review',
    nickname: '小杯测评',
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
    description: '玩具开箱、结构拆解和真实使用体验',
    categoryId: 'category-digital',
    sortOrder: 1,
  ),
  Community(
    id: 'community-campus',
    slug: 'campus',
    name: '酱紫社区',
    description: '真实测评、避坑求助和同好交流',
    categoryId: 'category-campus',
    sortOrder: 2,
  ),
  Community(
    id: 'community-daily',
    slug: 'daily',
    name: '杂鱼日常',
    description: '润滑、保养和日常使用记录',
    categoryId: 'category-life',
    sortOrder: 3,
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
  bool isRecommended = false,
  int? recommendationPosition,
  int? lastCommentMinutesAgo,
  List<MediaAsset> images = const [],
}) {
  final createdAt = _now.subtract(Duration(hours: hoursAgo));
  final community = _seedCommunities().firstWhere(
    (item) => item.id == section.communityId,
  );
  final activityAt = lastCommentMinutesAgo != null
      ? _now.subtract(Duration(minutes: lastCommentMinutesAgo))
      : (comments > 0
            ? _now.subtract(Duration(minutes: hoursAgo * 20 + 5))
            : createdAt);
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
    activityAt: activityAt,
    lastCommentAt: comments > 0 ? activityAt : null,
    isRecommended: isRecommended,
    recommendationPosition: recommendationPosition,
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
    title: '为啥很少朋友推荐星野爱丽丝2代？',
    body: '我个人比较颜控，挑选大臀时想找客服要实物照片，目前只看中了星野爱丽丝2代，但站里好像没什么讨论。',
    section: ForumSection.unboxing,
    tag: '大型拆箱',
    hoursAgo: 2,
    comments: 24,
    views: 133,
    extraTag: '求真实体验',
    isFeatured: true,
    isRecommended: true,
    recommendationPosition: 1,
    lastCommentMinutesAgo: 23,
  ),
  _post(
    id: 'u2',
    authorId: 'user-2',
    title: '新手小屯用黄油小姐二代吗？',
    body: '看榜单上面它排第一，有没有吧友发个真实使用感受？如果适合新手我就直接拿下了。',
    section: ForumSection.unboxing,
    tag: '大型拆箱',
    hoursAgo: 5,
    comments: 18,
    views: 98,
    isRecommended: true,
    recommendationPosition: 2,
    lastCommentMinutesAgo: 45,
  ),
  _post(
    id: 'u3',
    authorId: 'user-3',
    title: '润滑怎么选？妹汁和牛奶润滑差别明显吗',
    body: '体验了妹汁后确实更容易感觉到纹路，牛奶润滑更黏一些；换了妹汁后清洗也更快了。',
    section: ForumSection.unboxing,
    tag: '大型拆箱',
    hoursAgo: 26,
    comments: 12,
    views: 76,
  ),
  _post(
    id: 'u4',
    authorId: 'user-4',
    title: '开箱记录：第一次买大尺寸倒模',
    body: '先记录一下包装、重量和到手状态，后面再补充清洗、收纳和实际体验。',
    section: ForumSection.unboxing,
    tag: '大型拆箱',
    hoursAgo: 0,
    comments: 8,
    views: 136,
  ),
  _post(
    id: 'u5',
    authorId: 'user-1',
    title: '新手入门：预算 300-400 怎么选屯磨？',
    body: '整理一份偏慢玩、容易清洗、收纳压力不大的入门选择，欢迎老玩家补充避坑经验。',
    section: ForumSection.unboxing,
    tag: '大型拆箱',
    hoursAgo: 72,
    comments: 46,
    views: 860,
    extraTag: '精华',
    isFeatured: true,
    isRecommended: true,
    recommendationPosition: 3,
  ),
  _post(
    id: 'c1',
    authorId: 'user-5',
    title: '我不行了：客服让我屏蔽真实评价',
    body: '正常评价说有点胶臭味和起皮，客服联系我让我屏蔽评价并返了一半价格。大家遇到过类似情况吗？',
    section: ForumSection.community,
    tag: '酱紫社区',
    hoursAgo: 4,
    comments: 31,
    views: 420,
    extraTag: '热门讨论',
    isFeatured: true,
  ),
  _post(
    id: 'c2',
    authorId: 'user-6',
    title: '二选一，独居的话这两个怎么选？',
    body: '之前玩过几个杯子，这两个看起来都是好价，想听听大家对软硬度和清洗难度的意见。',
    section: ForumSection.community,
    tag: '酱紫社区',
    hoursAgo: 6,
    comments: 22,
    views: 310,
  ),
  _post(
    id: 'c3',
    authorId: 'user-7',
    title: '人在这一生中会做很多后悔的事情',
    body: '最后悔的就是把一个用了几次的杯子丢掉，丢掉以后一直后悔到现在。大家有类似经历吗？',
    section: ForumSection.community,
    tag: '酱紫社区',
    hoursAgo: 336,
    comments: 38,
    views: 1220,
    extraTag: '精华',
    isFeatured: true,
  ),
  _post(
    id: 'd1',
    authorId: 'user-8',
    title: '教学：爽身粉还是保护粉？多久一次？',
    body: '这里的粉主要是名器保养粉、婴儿爽身粉这类产品。我的经验是手感发粘时再处理，长期不用前收纳一次即可。',
    section: ForumSection.daily,
    tag: '杂鱼日常',
    hoursAgo: 6,
    comments: 15,
    views: 260,
    extraTag: '持续更新',
    isFeatured: true,
  ),
  _post(
    id: 'd2',
    authorId: 'user-9',
    title: '今天补保养粉，发现起皮和皱纹是怎么回事？',
    body: '平常套着原装内衣再套一个抱枕套，买回来刚好一周。想请教一下大家平时怎么保养和收纳。',
    section: ForumSection.daily,
    tag: '杂鱼日常',
    hoursAgo: 8,
    comments: 9,
    views: 190,
  ),
  _post(
    id: 'd3',
    authorId: 'user-10',
    title: '慢玩分享：怎么把清洗和收纳做得更省事？',
    body: '从润滑用量、冲洗顺序到晾干收纳整理一套流程，核心是别急着塞回袋子里，给材料留足干燥时间。',
    section: ForumSection.daily,
    tag: '玩法分享',
    hoursAgo: 24,
    comments: 27,
    views: 520,
  ),
  _post(
    id: 'd4',
    authorId: 'user-11',
    title: '感觉牛牛吃软不吃硬，有没有同样情况？',
    body: '来回用了几次，大部分时候快撸慢撸都没什么感觉，换成偏软的结构反而更容易找到节奏。',
    section: ForumSection.daily,
    tag: '杂鱼日常',
    hoursAgo: 0,
    comments: 11,
    views: 146,
  ),
];

Map<String, List<Comment>> _seedComments() => {
  'u1': [
    Comment(
      id: 'comment-u1-1',
      postId: 'u1',
      authorId: 'user-2',
      content: '这个整理很有用，尤其是清洗和收纳那段。想问下你更推荐软一点还是支撑感强一点的？',
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
      content: '这类帖子就该多写实际感受，榜单分数只能当参考。',
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
      content: '清洗和收纳的建议很实用，先收藏了。',
      likeCount: 8,
      createdAt: _now.subtract(const Duration(hours: 2)),
      updatedAt: _now.subtract(const Duration(hours: 2)),
    ),
  ],
  // 与 u4 帖子头部展示的 8 条回复保持一致，便于未传 API_BASE_URL 的
  // 本地模拟器也能完整验证评论、楼中楼展开和回复入口。
  'u4': [
    Comment(
      id: 'comment-u4-1',
      postId: 'u4',
      authorId: 'user-2',
      content: '包装比我想象中扎实，重量也确实有点分量。第一次买大尺寸的话，建议先把收纳位置准备好。',
      likeCount: 9,
      replyCount: 2,
      createdAt: _now.subtract(const Duration(hours: 2)),
      updatedAt: _now.subtract(const Duration(hours: 2)),
    ),
    Comment(
      id: 'comment-u4-1-1',
      postId: 'u4',
      authorId: 'user-4',
      rootId: 'comment-u4-1',
      parentId: 'comment-u4-1',
      replyToUserId: 'user-2',
      content: '同感，我也是先清点配件再开始清洗，第一次不要急着直接上手。',
      createdAt: _now.subtract(const Duration(hours: 1, minutes: 45)),
      updatedAt: _now.subtract(const Duration(hours: 1, minutes: 45)),
    ),
    Comment(
      id: 'comment-u4-1-2',
      postId: 'u4',
      authorId: 'user-5',
      rootId: 'comment-u4-1',
      parentId: 'comment-u4-1',
      replyToUserId: 'user-4',
      content: '收纳袋最好留一点通风空间，完全密封反而容易有味道。',
      createdAt: _now.subtract(const Duration(hours: 1, minutes: 30)),
      updatedAt: _now.subtract(const Duration(hours: 1, minutes: 30)),
    ),
    Comment(
      id: 'comment-u4-2',
      postId: 'u4',
      authorId: 'user-3',
      content: '大尺寸第一次用建议多加一点润滑，适应之后再慢慢调整用量。',
      likeCount: 5,
      createdAt: _now.subtract(const Duration(hours: 1, minutes: 15)),
      updatedAt: _now.subtract(const Duration(hours: 1, minutes: 15)),
    ),
    Comment(
      id: 'comment-u4-3',
      postId: 'u4',
      authorId: 'user-6',
      content: '看起来内壁结构挺丰富的，清洗时记得用软水流慢慢冲，不然容易漏洗。',
      likeCount: 4,
      createdAt: _now.subtract(const Duration(minutes: 55)),
      updatedAt: _now.subtract(const Duration(minutes: 55)),
    ),
    Comment(
      id: 'comment-u4-4',
      postId: 'u4',
      authorId: 'user-7',
      content: '我比较关心晾干时间，建议楼主后面补一张完全干燥后的收纳图。',
      likeCount: 3,
      createdAt: _now.subtract(const Duration(minutes: 42)),
      updatedAt: _now.subtract(const Duration(minutes: 42)),
    ),
    Comment(
      id: 'comment-u4-5',
      postId: 'u4',
      authorId: 'user-8',
      content: '这类开箱记录很适合新手参考，尤其是重量和尺寸最好都写清楚。',
      likeCount: 6,
      replyCount: 1,
      createdAt: _now.subtract(const Duration(minutes: 26)),
      updatedAt: _now.subtract(const Duration(minutes: 26)),
    ),
    Comment(
      id: 'comment-u4-5-1',
      postId: 'u4',
      authorId: 'user-1',
      rootId: 'comment-u4-5',
      parentId: 'comment-u4-5',
      replyToUserId: 'user-8',
      content: '收到，等实际体验几次后我再补充压力和清洗感受。',
      createdAt: _now.subtract(const Duration(minutes: 12)),
      updatedAt: _now.subtract(const Duration(minutes: 12)),
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
    name: '杯友钥匙扣',
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
    name: '杯友帆布袋',
    description: '生活周边',
    emoji: '👜',
    points: 1800,
    color: 0xFFB8E8D5,
  ),
];
