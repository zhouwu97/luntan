import 'package:flutter/material.dart';

import '../controllers/interaction_controller.dart';
import '../domain/models.dart';
import '../domain/repositories.dart';
import '../data/mock_forum_data.dart';
import '../data/api/platform_repository.dart';
import '../data/api/publish_repository.dart';
import '../data/api/ranking_repository.dart';
import '../data/api/store_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/app_network_image.dart';
import '../widgets/forum_post_card.dart';
import 'ranking_page.dart';

enum FeatureType { ranking, hot, outfit, activity, gameShare, myReplies }

extension FeatureTypePresentation on FeatureType {
  String get label => switch (this) {
    FeatureType.ranking => '玩具排行榜',
    FeatureType.hot => '热门帖子',
    FeatureType.outfit => '穿搭分享',
    FeatureType.activity => '活动',
    FeatureType.gameShare => '玩法分享',
    FeatureType.myReplies => '我的回复',
  };
}

class FeaturePage extends StatefulWidget {
  const FeaturePage({
    super.key,
    required this.type,
    required this.store,
    required this.onOpenPost,
    required this.interactionController,
    this.onOpenPostId,
    this.onLike,
    this.onBookmark,
    this.feedRepository,
    this.platformRepository,
    this.postRepository,
    this.rankingRepository,
    this.storeRepository,
    this.publishRepository,
    this.isAuthenticated = false,
    this.canComment = false,
    this.canLike = false,
    this.canVote = false,
    this.canManageRanking = false,
    this.onRequireAuth,
    this.onOpenUserId,
  });

  final FeatureType type;
  final ForumStore store;
  final ValueChanged<Post> onOpenPost;
  final InteractionController interactionController;
  final ValueChanged<String>? onOpenPostId;
  final ValueChanged<Post>? onLike;
  final ValueChanged<Post>? onBookmark;
  final FeedRepository? feedRepository;
  final PlatformRepository? platformRepository;
  final PostRepository? postRepository;
  final RankingRepository? rankingRepository;
  final StoreRepository? storeRepository;
  final PublishRepository? publishRepository;
  final bool isAuthenticated;
  final bool canComment;
  final bool canLike;
  final bool canVote;
  final bool canManageRanking;
  final VoidCallback? onRequireAuth;
  final ValueChanged<String>? onOpenUserId;

  @override
  State<FeaturePage> createState() => _FeaturePageState();
}

class _FeaturePageState extends State<FeaturePage> {
  Future<List<Post>>? remoteFuture;
  Future<List<ActivityItem>>? activityFuture;

  FeatureType get type => widget.type;
  ForumStore get store => widget.store;
  ValueChanged<Post> get onOpenPost => widget.onOpenPost;
  ValueChanged<Post>? get onLike => widget.onLike;
  ValueChanged<Post>? get onBookmark => widget.onBookmark;
  FeedRepository? get feedRepository => widget.feedRepository;
  PlatformRepository? get platformRepository => widget.platformRepository;
  PostRepository? get postRepository => widget.postRepository;
  RankingRepository? get rankingRepository => widget.rankingRepository;
  StoreRepository? get storeRepository => widget.storeRepository;
  bool get isAuthenticated => widget.isAuthenticated;
  bool get canComment => widget.canComment;
  bool get canLike => widget.canLike;
  bool get canVote => widget.canVote;
  VoidCallback? get onRequireAuth => widget.onRequireAuth;

  @override
  void initState() {
    super.initState();
    if (type != FeatureType.ranking && feedRepository != null) {
      remoteFuture = _remotePosts();
    }
    if (type == FeatureType.activity && platformRepository != null) {
      activityFuture = platformRepository!.listPublicActivities();
    }
  }

  void _retry() {
    setState(() {
      if (type != FeatureType.ranking && feedRepository != null) {
        remoteFuture = _remotePosts();
      }
      if (type == FeatureType.activity && platformRepository != null) {
        activityFuture = platformRepository!.listPublicActivities();
      }
    });
  }

  String get title => type.label;

  void _openPost(Post post) {
    final onOpenPostId = widget.onOpenPostId;
    if (onOpenPostId != null) {
      onOpenPostId(post.id);
    } else {
      onOpenPost(post);
    }
  }

  Future<List<Post>> _remotePosts() async {
    final repository = feedRepository!;
    final page = repository is QueryableFeedRepository
        ? await (repository as QueryableFeedRepository).getFeed(
            sort: type == FeatureType.hot ? 'hot' : 'recommended',
            limit: 50,
            postType: switch (type) {
              FeatureType.activity => 'activity',
              FeatureType.gameShare => 'game_share',
              _ => null,
            },
            topic: type == FeatureType.outfit ? 'outfit' : null,
          )
        : await repository.getLatestFeed(limit: 50);
    final items = page.items;
    if (type == FeatureType.hot) {
      return items.take(20).toList();
    }
    return items;
  }

  List<Post> _posts() {
    if (type == FeatureType.hot) {
      final list = [...store.posts]
        ..sort((a, b) => b.commentCount.compareTo(a.commentCount));
      return list.take(6).toList();
    }
    if (type == FeatureType.gameShare) {
      return store.posts.where((post) => post.tag == '玩法分享').toList();
    }
    if (type == FeatureType.outfit) {
      return store.posts.where((post) => post.tag == '穿搭分享').take(6).toList();
    }
    if (type == FeatureType.activity) {
      return store.posts
          .where((post) => post.type == PostType.activity)
          .toList();
    }
    return const <Post>[];
  }

  @override
  Widget build(BuildContext context) {
    if (type == FeatureType.ranking) {
      return RankingPage(
        repository: rankingRepository,
        platformRepository: platformRepository,
        publishRepository: widget.publishRepository,
        isAuthenticated: isAuthenticated,
        canComment: canComment,
        canLike: canLike,
        canVote: canVote,
        canManageRanking: widget.canManageRanking,
        onRequireAuth: onRequireAuth,
      );
    }
    if (type == FeatureType.activity) {
      if (feedRepository != null || platformRepository != null) {
        return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: FutureBuilder<List<Post>>(
            future: remoteFuture ?? Future.value(_posts()),
            builder: (context, postSnapshot) {
              if (postSnapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (postSnapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '活动内容加载失败',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                      TextButton(onPressed: _retry, child: const Text('返回重试')),
                    ],
                  ),
                );
              }
              final posts = postSnapshot.data ?? const <Post>[];
              if (posts.isNotEmpty) {
                return _body(posts);
              }
              if (activityFuture != null) {
                return FutureBuilder<List<ActivityItem>>(
                  future: activityFuture,
                  builder: (context, actSnapshot) {
                    if (actSnapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final activities = actSnapshot.data ?? const <ActivityItem>[];
                    if (activities.isNotEmpty) {
                      return _activitiesBody(activities);
                    }
                    return _body(_posts());
                  },
                );
              }
              return _body(_posts());
            },
          ),
        );
      }
    }
    if (feedRepository != null) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: FutureBuilder<List<Post>>(
          future: remoteFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '内容加载失败',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                    TextButton(onPressed: _retry, child: const Text('返回重试')),
                  ],
                ),
              );
            }
            return _body(snapshot.data ?? const <Post>[]);
          },
        ),
      );
    }
    final posts = _posts();
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _body(posts),
    );
  }

  Widget _activitiesBody(List<ActivityItem> activities) => CustomScrollView(
    slivers: [
      const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 8, 14, 6),
          child: Text(
            '近期活动',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _activityItemCard(activities[index]),
          childCount: activities.length,
        ),
      ),
      const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
    ],
  );

  Widget _activityItemCard(ActivityItem item) {
    final statusColor = switch (item.status) {
      'active' => AppTheme.primary,
      'upcoming' => AppTheme.orange,
      'ended' => const Color(0xFF8A98A6),
      _ => AppTheme.textSecondary,
    };

    final startAt = item.startAt;
    final dayStr = startAt != null ? startAt.day.toString().padLeft(2, '0') : '--';
    final monthStr = startAt != null ? '${startAt.month} 月' : '';
    final timeStr = startAt != null
        ? '${startAt.hour.toString().padLeft(2, '0')}:${startAt.minute.toString().padLeft(2, '0')}'
        : '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEDF2F7), width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 44,
              child: Column(
                children: [
                  Text(
                    dayStr,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                      height: 1.1,
                    ),
                  ),
                  if (monthStr.isNotEmpty)
                    Text(
                      monthStr,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF5B6E80),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        item.statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  if (item.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.description,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF63788B),
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (timeStr.isNotEmpty || item.location.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        if (timeStr.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.access_time_outlined,
                                size: 13,
                                color: Color(0xFF7D90A2),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                timeStr,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF7D90A2),
                                ),
                              ),
                            ],
                          ),
                        if (item.location.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                size: 13,
                                color: Color(0xFF7D90A2),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                item.location,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF7D90A2),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (item.coverUrl != null && item.coverUrl!.isNotEmpty) ...[
              const SizedBox(width: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 78,
                  height: 62,
                  child: AppNetworkImage(
                    url: item.coverUrl!,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _activityEmptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 60),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFFAFCFE),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFDDE6EF)),
            ),
            child: const Icon(
              Icons.calendar_today_outlined,
              size: 20,
              color: Color(0xFF8497AA),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '暂无活动',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '管理员发布活动后，会直接显示在这里。',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF8A9BAD),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );

  Widget _hotMetaHeader() => const Padding(
    padding: EdgeInsets.fromLTRB(14, 8, 14, 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '按热度排序',
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.textSecondary,
          ),
        ),
        Text(
          '最多展示 20 条',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF536B81),
          ),
        ),
      ],
    ),
  );

  Widget _body(List<Post> posts) {
    if (posts.isEmpty) {
      if (type == FeatureType.activity) {
        return _activityEmptyState();
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 60),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFCFE),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFDDE6EF)),
                ),
                child: const Icon(
                  Icons.inbox_outlined,
                  size: 20,
                  color: Color(0xFF8497AA),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '这里还没有内容',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        if (type == FeatureType.hot)
          SliverToBoxAdapter(child: _hotMetaHeader()),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _postCard(posts[index]),
            childCount: posts.length,
          ),
        ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
      ],
    );
  }

  Widget _postCard(Post post) => ForumPostCard(
    post: post,
    onOpen: () => _openPost(post),
    onLike: () => onLike?.call(post),
    onBookmark: () => onBookmark?.call(post),
    // 专题页暂不提供帖子菜单，不渲染一个没有行为的省略号入口。
    onMenu: null,
    onAuthorTap: widget.onOpenUserId,
    interactionListenable:
        widget.interactionController.interactionsFor(post.id),
  );
}
