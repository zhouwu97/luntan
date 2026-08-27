import 'package:flutter/material.dart';

import '../controllers/interaction_controller.dart';
import '../domain/models.dart';
import '../domain/repositories.dart';
import '../data/mock_forum_data.dart';
import '../data/api/platform_repository.dart';
import '../data/api/ranking_repository.dart';
import '../data/api/store_repository.dart';
import '../theme/app_theme.dart';
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
    this.isAuthenticated = false,
    this.canComment = false,
    this.canLike = false,
    this.canVote = false,
    this.onRequireAuth,
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
  final bool isAuthenticated;
  final bool canComment;
  final bool canLike;
  final bool canVote;
  final VoidCallback? onRequireAuth;

  @override
  State<FeaturePage> createState() => _FeaturePageState();
}

class _FeaturePageState extends State<FeaturePage> {
  Future<List<Post>>? remoteFuture;

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
  }

  void _retry() {
    setState(() {
      remoteFuture = _remotePosts();
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
        isAuthenticated: isAuthenticated,
        canComment: canComment,
        canLike: canLike,
        canVote: canVote,
        onRequireAuth: onRequireAuth,
      );
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

  Widget _body(List<Post> posts) => CustomScrollView(
    slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
        sliver: SliverToBoxAdapter(child: _postIntro()),
      ),
      if (posts.isEmpty)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text(
              '这里还没有内容',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _postCard(posts[index]),
              childCount: posts.length,
            ),
          ),
        ),
      const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
    ],
  );

  Widget _postIntro() => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: AppTheme.primaryGradient,
      borderRadius: BorderRadius.circular(22),
    ),
    child: Row(
      children: [
        const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 30),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _description(type),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              height: 1.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _postCard(Post post) => ForumPostCard(
    post: post,
    onOpen: () => _openPost(post),
    onLike: () => onLike?.call(post),
    onBookmark: () => onBookmark?.call(post),
    // 专题页暂不提供帖子菜单，不渲染一个没有行为的省略号入口。
    onMenu: null,
    interactionListenable: widget.interactionController,
  );

  String _description(FeatureType type) => switch (type) {
    FeatureType.ranking => '社区用户真实评分的玩具榜单，按综合口碑和体验反馈展示。',
    FeatureType.hot => '社区里正在被大家讨论的内容，今天也来逛逛吧。',
    FeatureType.outfit => '开箱图、结构展示和穿搭分享，都可以在这里找到。',
    FeatureType.activity => '社区活动和公告集中展示，打开帖子查看参与方式。',
    FeatureType.gameShare => '分享慢玩、清洗、收纳和配菜玩法，找到一起交流的同好。',
    FeatureType.myReplies => '这里会展示你参与过的回复，先去帖子里聊两句吧。',
  };
}
