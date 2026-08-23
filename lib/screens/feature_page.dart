import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../domain/repositories.dart';
import '../data/mock_forum_data.dart';
import '../theme/app_theme.dart';
import '../widgets/forum_post_card.dart';

enum FeatureType { ranking, hot, outfit, activity, gameShare, myReplies }

extension FeatureTypePresentation on FeatureType {
  String get label => switch (this) {
    FeatureType.ranking => '排行榜',
    FeatureType.hot => '热门帖子',
    FeatureType.outfit => '穿搭分享',
    FeatureType.activity => '活动',
    FeatureType.gameShare => '玩法分享',
    FeatureType.myReplies => '我的回复',
  };
}

class FeaturePage extends StatelessWidget {
  const FeaturePage({
    super.key,
    required this.type,
    required this.store,
    required this.onOpenPost,
    this.onLike,
    this.onBookmark,
    this.feedRepository,
  });

  final FeatureType type;
  final ForumStore store;
  final ValueChanged<Post> onOpenPost;
  final ValueChanged<Post>? onLike;
  final ValueChanged<Post>? onBookmark;
  final FeedRepository? feedRepository;

  String get title => type.label;

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
    if (feedRepository != null) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: FutureBuilder<List<Post>>(
          future: _remotePosts(),
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
                    TextButton(onPressed: () {}, child: const Text('返回重试')),
                  ],
                ),
              );
            }
            return _body(context, snapshot.data ?? const <Post>[]);
          },
        ),
      );
    }
    final posts = _posts();
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 30,
                ),
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
          ),
          const SizedBox(height: 16),
          if (posts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 80),
              child: Center(
                child: Text(
                  '这里还没有内容',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            )
          else
            ...posts.map(
              (post) => ForumPostCard(
                post: post,
                onOpen: () => onOpenPost(post),
                onLike: () => onLike?.call(post),
                onBookmark: () => onBookmark?.call(post),
                onMenu: () {},
              ),
            ),
        ],
      ),
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
          )
        : await repository.getLatestFeed(limit: 50);
    final items = page.items;
    if (type == FeatureType.ranking || type == FeatureType.hot) {
      return items.take(20).toList();
    }
    if (type == FeatureType.activity) {
      return items.where((post) => post.type == PostType.activity).toList();
    }
    if (type == FeatureType.gameShare) {
      return items
          .where(
            (post) =>
                post.type == PostType.gameShare || post.tags.contains('玩法分享'),
          )
          .toList();
    }
    if (type == FeatureType.outfit) {
      return items
          .where((post) => post.media.isNotEmpty || post.tags.contains('穿搭分享'))
          .toList();
    }
    return const <Post>[];
  }

  Widget _body(BuildContext context, List<Post> posts) => ListView(
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
    children: [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: AppTheme.primaryGradient,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 30,
            ),
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
      ),
      const SizedBox(height: 16),
      if (posts.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 80),
          child: Center(
            child: Text(
              '这里还没有内容',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
        )
      else
        ...posts.map(
          (post) => ForumPostCard(
            post: post,
            onOpen: () => onOpenPost(post),
            onLike: () => onLike?.call(post),
            onBookmark: () => onBookmark?.call(post),
            onMenu: () {},
          ),
        ),
    ],
  );

  String _description(FeatureType type) => switch (type) {
    FeatureType.ranking => '看看最近最受欢迎的帖子，给认真分享的人一点掌声。',
    FeatureType.hot => '社区里正在被大家讨论的内容，今天也来逛逛吧。',
    FeatureType.outfit => '桌搭、宿舍布置和校园生活灵感，都可以在这里找到。',
    FeatureType.activity => '活动模型和报名能力正在建设中，暂时没有可展示的活动。',
    FeatureType.gameShare => '分享游戏、桌游、社团活动和校园玩法，找到一起玩的同学。',
    FeatureType.myReplies => '这里会展示你参与过的回复，先去帖子里聊两句吧。',
  };
}
