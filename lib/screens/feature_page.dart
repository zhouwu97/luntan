import 'package:flutter/material.dart';

import '../controllers/interaction_controller.dart';
import '../domain/models.dart';
import '../domain/repositories.dart';
import '../data/mock_forum_data.dart';
import '../data/api/platform_repository.dart';
import '../data/api/store_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/forum_post_card.dart';

enum FeatureType { ranking, hot, outfit, activity, gameShare, myReplies }

extension FeatureTypePresentation on FeatureType {
  String get label => switch (this) {
    FeatureType.ranking => '商品榜',
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
    this.storeRepository,
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
  final StoreRepository? storeRepository;

  @override
  State<FeaturePage> createState() => _FeaturePageState();
}

class _ApiRankingProduct extends StatelessWidget {
  const _ApiRankingProduct({required this.rank, required this.product});

  final int rank;
  final ApiStoreProduct product;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppTheme.border),
    ),
    child: Row(
      children: [
        Text(
          rank <= 3 ? ['🥇', '🥈', '🥉'][rank - 1] : '$rank',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        const SizedBox(width: 12),
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Color(product.color),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(product.emoji, style: const TextStyle(fontSize: 27)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${product.points} 积分 · 已有 ${product.redeemedCount} 人兑换',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              if (product.description.isNotEmpty)
                Text(
                  product.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MockRankingProduct extends StatelessWidget {
  const _MockRankingProduct({required this.rank, required this.product});

  final int rank;
  final StoreProduct product;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppTheme.border),
    ),
    child: Row(
      children: [
        Text(rank <= 3 ? ['🥇', '🥈', '🥉'][rank - 1] : '$rank'),
        const SizedBox(width: 12),
        Text(product.emoji, style: const TextStyle(fontSize: 27)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '${product.name}\n${product.points} 积分 · 热门兑换',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _FeaturePageState extends State<FeaturePage> {
  Future<List<Post>>? remoteFuture;
  Future<List<ApiStoreProduct>>? productsFuture;

  FeatureType get type => widget.type;
  ForumStore get store => widget.store;
  ValueChanged<Post> get onOpenPost => widget.onOpenPost;
  ValueChanged<Post>? get onLike => widget.onLike;
  ValueChanged<Post>? get onBookmark => widget.onBookmark;
  FeedRepository? get feedRepository => widget.feedRepository;
  PlatformRepository? get platformRepository => widget.platformRepository;
  PostRepository? get postRepository => widget.postRepository;
  StoreRepository? get storeRepository => widget.storeRepository;

  @override
  void initState() {
    super.initState();
    if (type == FeatureType.ranking && storeRepository != null) {
      productsFuture = storeRepository!.products();
    } else if (feedRepository != null) {
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

  List<Post> _posts() {
    if (type == FeatureType.ranking) {
      final list = [...store.posts]
        ..sort((a, b) => b.comments.compareTo(a.comments));
      return list.take(6).toList();
    }
    if (type == FeatureType.hot) {
      final list = [...store.posts]
        ..sort((a, b) => _views(b.views).compareTo(_views(a.views)));
      return list.take(6).toList();
    }
    if (type == FeatureType.gameShare) {
      return store.posts.where((post) => post.tag == '玩法分享').toList();
    }
    if (type == FeatureType.outfit) {
      return store.posts
          .where((post) => post.tag == '穿搭分享' || post.images.isNotEmpty)
          .take(6)
          .toList();
    }
    if (type == FeatureType.activity) {
      return store.posts
          .where((post) => post.type == PostType.activity)
          .toList();
    }
    return const <Post>[];
  }

  int _views(String value) =>
      int.tryParse(value.replaceAll('k', '000').replaceAll('.', '')) ?? 0;

  @override
  Widget build(BuildContext context) {
    if (type == FeatureType.ranking && storeRepository != null) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: FutureBuilder<List<ApiStoreProduct>>(
          future: productsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('商品榜加载失败'),
                    TextButton(
                      onPressed: () => setState(
                        () => productsFuture = storeRepository!.products(),
                      ),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              );
            }
            return _productBody(snapshot.data ?? const []);
          },
        ),
      );
    }
    if (feedRepository == null && type == FeatureType.ranking) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: _mockProductBody(),
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

  Future<List<Post>> _remotePosts() async {
    final repository = feedRepository!;
    final page = repository is QueryableFeedRepository
        ? await (repository as QueryableFeedRepository).getFeed(
            sort: type == FeatureType.ranking
                ? 'featured'
                : type == FeatureType.hot
                ? 'hot'
                : 'recommended',
            limit: 50,
            postType: switch (type) {
              FeatureType.activity => 'activity',
              FeatureType.gameShare => 'game_share',
              _ => null,
            },
            hasMedia: type == FeatureType.outfit ? true : null,
          )
        : await repository.getLatestFeed(limit: 50);
    final items = page.items;
    if (type == FeatureType.ranking || type == FeatureType.hot) {
      return items.take(20).toList();
    }
    if (type == FeatureType.activity ||
        type == FeatureType.gameShare ||
        type == FeatureType.outfit) {
      return items;
    }
    return const <Post>[];
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
    onMenu: () {},
    interactionListenable: widget.interactionController,
  );

  Widget _productBody(List<ApiStoreProduct> products) => CustomScrollView(
    slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
        sliver: SliverToBoxAdapter(
          child: _featureIntro('本周热门兑换\n用社区积分兑换喜欢的校园好物。'),
        ),
      ),
      if (products.isEmpty)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: Text('暂时还没有商品')),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) =>
                  _ApiRankingProduct(rank: index + 1, product: products[index]),
              childCount: products.length,
            ),
          ),
        ),
      const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
    ],
  );

  Widget _mockProductBody() => CustomScrollView(
    slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
        sliver: SliverToBoxAdapter(
          child: _featureIntro('本周热门兑换\n用社区积分兑换喜欢的校园好物。'),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _MockRankingProduct(
              rank: index + 1,
              product: storeProducts[index],
            ),
            childCount: storeProducts.length,
          ),
        ),
      ),
      const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
    ],
  );

  Widget _featureIntro(String text) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: AppTheme.primaryGradient,
      borderRadius: BorderRadius.circular(22),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        height: 1.5,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  String _description(FeatureType type) => switch (type) {
    FeatureType.ranking => '本周热门兑换，用社区积分兑换喜欢的校园好物。',
    FeatureType.hot => '社区里正在被大家讨论的内容，今天也来逛逛吧。',
    FeatureType.outfit => '桌搭、宿舍布置和校园生活灵感，都可以在这里找到。',
    FeatureType.activity => '校园活动内容集中展示，打开帖子查看时间、地点和参与方式。',
    FeatureType.gameShare => '分享游戏、桌游、社团活动和校园玩法，找到一起玩的同学。',
    FeatureType.myReplies => '这里会展示你参与过的回复，先去帖子里聊两句吧。',
  };
}
