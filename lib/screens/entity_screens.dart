import 'package:flutter/material.dart';

import '../controllers/feed_controller.dart';
import '../controllers/interaction_controller.dart';
import '../data/api/api_client.dart';
import '../data/api/user_repository.dart';
import '../domain/models.dart';
import '../domain/repositories.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import '../widgets/forum_post_card.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({
    super.key,
    required this.repository,
    required this.userId,
    required this.isAuthenticated,
    this.canFollow = true,
    required this.onRequireAuth,
    required this.onFeedback,
    required this.onOpenPostId,
    this.onOpenRelations,
  });

  final UserRepository repository;
  final String userId;
  final bool isAuthenticated;
  final bool canFollow;
  final VoidCallback onRequireAuth;
  final ValueChanged<String> onFeedback;
  final ValueChanged<String> onOpenPostId;
  final void Function(String userId, bool followers)? onOpenRelations;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  late Future<UserProfile?> _future;
  late Future<UserPostPage> _postsFuture;
  UserProfile? _profile;
  bool _busy = false;
  final ScrollController _postsScrollController = ScrollController();
  final List<UserPost> _posts = <UserPost>[];
  String? _nextPostsCursor;
  bool _hasMorePosts = true;
  bool _loadingMorePosts = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _postsFuture = _loadInitialPosts();
    _postsScrollController.addListener(_loadMoreWhenNeeded);
  }

  @override
  void dispose() {
    _postsScrollController
      ..removeListener(_loadMoreWhenNeeded)
      ..dispose();
    super.dispose();
  }

  Future<UserPostPage> _loadInitialPosts() async {
    final page = await widget.repository.listPosts(widget.userId);
    if (!mounted) return page;
    setState(() {
      _posts
        ..clear()
        ..addAll(page.items);
      _nextPostsCursor = page.nextCursor;
      _hasMorePosts = page.hasMore;
    });
    return page;
  }

  void _loadMoreWhenNeeded() {
    if (_postsScrollController.position.extentAfter < 260) {
      _loadMorePosts();
    }
  }

  Future<void> _loadMorePosts() async {
    if (_loadingMorePosts || !_hasMorePosts || _nextPostsCursor == null) {
      return;
    }
    setState(() => _loadingMorePosts = true);
    try {
      final page = await widget.repository.listPosts(
        widget.userId,
        cursor: _nextPostsCursor,
      );
      if (!mounted) return;
      setState(() {
        final ids = _posts.map((post) => post.id).toSet();
        _posts.addAll(page.items.where((post) => ids.add(post.id)));
        final nextCursor = page.nextCursor;
        _hasMorePosts = page.hasMore && nextCursor != _nextPostsCursor;
        _nextPostsCursor = nextCursor;
      });
    } catch (error) {
      if (mounted) {
        widget.onFeedback(userFacingApiMessage(error, fallback: '更多帖子加载失败'));
      }
    } finally {
      if (mounted) setState(() => _loadingMorePosts = false);
    }
  }

  Future<UserProfile?> _load() async {
    final profile = await widget.repository.getProfile(widget.userId);
    if (mounted) _profile = profile;
    return profile;
  }

  Future<void> _toggleFollow() async {
    if (!widget.isAuthenticated) {
      widget.onRequireAuth();
      return;
    }
    if (!widget.canFollow) {
      widget.onFeedback('当前身份暂不能关注，请登录邮箱账号后重试');
      return;
    }
    final profile = _profile;
    if (profile == null || !profile.canFollow || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.repository.setFollow(
        userId: profile.id,
        active: !profile.isFollowing,
      );
      if (mounted) setState(() => _future = _load());
    } catch (error) {
      if (mounted) {
        widget.onFeedback(userFacingApiMessage(error, fallback: '关注操作失败'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleBlock() async {
    if (!widget.isAuthenticated) {
      widget.onRequireAuth();
      return;
    }
    final profile = _profile;
    if (profile == null || _busy) return;
    final active = !profile.isBlocked;
    setState(() => _busy = true);
    try {
      await widget.repository.setBlock(userId: profile.id, active: active);
      if (mounted) {
        widget.onFeedback(active ? '已拉黑该用户' : '已取消拉黑');
        setState(() => _future = _load());
      }
    } catch (error) {
      if (mounted) {
        widget.onFeedback(userFacingApiMessage(error, fallback: '拉黑操作失败'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('用户主页'),
      actions: [
        if (_profile != null)
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'block') {
                _toggleBlock();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'block',
                child: Text(_profile!.isBlocked ? '取消拉黑' : '拉黑用户'),
              ),
            ],
          ),
      ],
    ),
    body: FutureBuilder<UserProfile?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data == null) {
          return const Center(child: Text('用户不存在或加载失败'));
        }
        final profile = snapshot.data!;
        _profile = profile;
        return ListView(
          controller: _postsScrollController,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 34,
                  backgroundColor: AppTheme.surfaceBlue,
                  child: Icon(Icons.person, color: AppTheme.primary, size: 34),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.nickname,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '@${profile.username}',
                        style: const TextStyle(color: AppTheme.textSecondary),
                      ),
                      Text(
                        profile.growth?.levelLocked == true
                            ? 'Lv.0 · 累计经验 ${profile.experience} · 注册后解锁等级'
                            : (profile.growth?.nextLevelExperience == null
                                ? 'Lv.${profile.level} (最高级) · 经验 ${profile.experience}'
                                : 'Lv.${profile.level} · 经验 ${profile.growth?.experienceInLevel ?? 0}/${profile.growth?.experienceRequiredInLevel ?? 100}'),
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (profile.canFollow)
                  FilledButton.tonal(
                    onPressed: _busy ? null : _toggleFollow,
                    child: AnimatedSwitcher(
                      duration: AppMotion.duration(context, AppMotion.fast),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(scale: animation, child: child),
                      ),
                      child: Text(
                        profile.isFollowing ? '已关注' : '关注',
                        key: ValueKey(profile.isFollowing),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            if (profile.bio.isNotEmpty) Text(profile.bio),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _Stat(label: '帖子', value: profile.postCount),
                _Stat(
                  label: '关注者',
                  value: profile.followerCount,
                  onTap: widget.onOpenRelations == null
                      ? null
                      : () => widget.onOpenRelations!(profile.id, true),
                ),
                _Stat(
                  label: '关注',
                  value: profile.followingCount,
                  onTap: widget.onOpenRelations == null
                      ? null
                      : () => widget.onOpenRelations!(profile.id, false),
                ),
              ],
            ),
            const Divider(height: 36),
            const Text(
              '公开内容',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            FutureBuilder<UserPostPage>(
              future: _postsFuture,
              builder: (context, postsSnapshot) {
                if (postsSnapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final posts = _posts.isEmpty
                    ? postsSnapshot.data?.items ?? const <UserPost>[]
                    : _posts;
                if (postsSnapshot.hasError && posts.isEmpty) {
                  return const Text(
                    '暂时没有公开帖子',
                    style: TextStyle(color: AppTheme.textSecondary),
                  );
                }
                return Column(
                  children: [
                    ...posts.map(
                      (post) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          post.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${post.communityName} · ${post.commentCount} 回复',
                        ),
                        onTap: () => widget.onOpenPostId(post.id),
                      ),
                    ),
                    if (_loadingMorePosts)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (!_hasMorePosts && posts.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          '没有更多帖子了',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        );
      },
    ),
  );
}

class UserRelationsScreen extends StatefulWidget {
  const UserRelationsScreen({
    super.key,
    required this.repository,
    required this.userId,
    required this.followers,
    required this.isAuthenticated,
    this.canFollow = true,
    required this.onRequireAuth,
    required this.onOpenUserId,
    required this.onFeedback,
  });

  final UserRepository repository;
  final String userId;
  final bool followers;
  final bool isAuthenticated;
  final bool canFollow;
  final VoidCallback onRequireAuth;
  final ValueChanged<String> onOpenUserId;
  final ValueChanged<String> onFeedback;

  @override
  State<UserRelationsScreen> createState() => _UserRelationsScreenState();
}

class _UserRelationsScreenState extends State<UserRelationsScreen> {
  final ScrollController _scrollController = ScrollController();
  final List<UserRelation> _items = <UserRelation>[];
  String? _nextCursor;
  bool _hasMore = true;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;

  String get _title => widget.followers ? '关注者' : '关注列表';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadMoreWhenNeeded);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_loadMoreWhenNeeded)
      ..dispose();
    super.dispose();
  }

  void _loadMoreWhenNeeded() {
    if (_scrollController.position.extentAfter < 240) _loadMore();
  }

  Future<UserRelationPage> _request({String? cursor}) => widget.followers
      ? widget.repository.listFollowers(widget.userId, cursor: cursor)
      : widget.repository.listFollowing(widget.userId, cursor: cursor);

  Future<void> _loadInitial() async {
    try {
      final page = await _request();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _nextCursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final cursor = _nextCursor;
      final page = await _request(cursor: cursor);
      if (!mounted) return;
      setState(() {
        final knownIds = _items.map((item) => item.id).toSet();
        _items.addAll(page.items.where((item) => knownIds.add(item.id)));
        final nextCursor = page.nextCursor;
        _hasMore = page.hasMore && nextCursor != cursor;
        _nextCursor = nextCursor;
      });
    } catch (error) {
      if (mounted) {
        widget.onFeedback(userFacingApiMessage(error, fallback: '更多用户加载失败'));
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _toggleFollow(int index) async {
    final relation = _items[index];
    if (!widget.isAuthenticated) {
      widget.onRequireAuth();
      return;
    }
    if (!widget.canFollow) {
      widget.onFeedback('当前身份暂不能关注，请登录邮箱账号后重试');
      return;
    }
    if (!relation.canFollow && !relation.isFollowing) return;
    try {
      final active = !relation.isFollowing;
      await widget.repository.setFollow(userId: relation.id, active: active);
      if (!mounted) return;
      _replace(
        index,
        UserRelation(
          id: relation.id,
          username: relation.username,
          nickname: relation.nickname,
          avatarMediaId: relation.avatarMediaId,
          isFollowing: active,
          isBlocked: relation.isBlocked,
          canFollow: relation.canFollow,
        ),
      );
    } catch (error) {
      if (mounted) {
        widget.onFeedback(userFacingApiMessage(error, fallback: '关注操作失败'));
      }
    }
  }

  Future<void> _toggleBlock(int index) async {
    final relation = _items[index];
    if (!widget.isAuthenticated) {
      widget.onRequireAuth();
      return;
    }
    try {
      final active = !relation.isBlocked;
      await widget.repository.setBlock(userId: relation.id, active: active);
      if (!mounted) return;
      _replace(
        index,
        UserRelation(
          id: relation.id,
          username: relation.username,
          nickname: relation.nickname,
          avatarMediaId: relation.avatarMediaId,
          isFollowing: active ? false : relation.isFollowing,
          isBlocked: active,
          canFollow: active ? false : relation.canFollow,
        ),
      );
    } catch (error) {
      if (mounted) {
        widget.onFeedback(userFacingApiMessage(error, fallback: '屏蔽操作失败'));
      }
    }
  }

  void _replace(int index, UserRelation value) {
    setState(() => _items[index] = value);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_title)),
    body: _body(),
  );

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '列表加载失败',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            TextButton(onPressed: _loadInitial, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          '暂时没有${widget.followers ? '关注者' : '关注用户'}',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      itemCount: _items.length + 1,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == _items.length) {
          return _loadingMore
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : const SizedBox(height: 12);
        }
        final relation = _items[index];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const CircleAvatar(
            backgroundColor: AppTheme.surfaceBlue,
            child: Icon(Icons.person_outline, color: AppTheme.primary),
          ),
          title: Text(relation.nickname),
          subtitle: Text('@${relation.username}'),
          onTap: () => widget.onOpenUserId(relation.id),
          trailing: widget.isAuthenticated
              ? PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'follow') _toggleFollow(index);
                    if (value == 'block') _toggleBlock(index);
                  },
                  itemBuilder: (_) => [
                    if (relation.canFollow || relation.isFollowing)
                      PopupMenuItem(
                        value: 'follow',
                        child: Text(relation.isFollowing ? '取消关注' : '关注'),
                      ),
                    PopupMenuItem(
                      value: 'block',
                      child: Text(relation.isBlocked ? '取消屏蔽' : '屏蔽用户'),
                    ),
                  ],
                )
              : null,
        );
      },
    );
  }
}

class CommunityDetailScreen extends StatefulWidget {
  const CommunityDetailScreen({
    super.key,
    required this.repository,
    required this.feedRepository,
    required this.communityId,
    required this.isAuthenticated,
    this.canFollow = true,
    required this.onRequireAuth,
    required this.onFeedback,
    required this.onOpenPost,
    required this.onOpenComments,
    required this.onToggleLike,
    required this.onToggleBookmark,
    required this.interactionController,
  });

  final CommunityRepository repository;
  final FeedRepository feedRepository;
  final String communityId;
  final bool isAuthenticated;
  final bool canFollow;
  final VoidCallback onRequireAuth;
  final ValueChanged<String> onFeedback;
  final ValueChanged<Post> onOpenPost;
  final ValueChanged<Post> onOpenComments;
  final ValueChanged<Post> onToggleLike;
  final ValueChanged<Post> onToggleBookmark;
  final InteractionController interactionController;

  @override
  State<CommunityDetailScreen> createState() => _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends State<CommunityDetailScreen> {
  late Future<Community?> _future;
  late final FeedController _feedController;
  Community? _community;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _feedController = FeedController(repository: widget.feedRepository);
    _future = _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _feedController.setQuery(communityId: widget.communityId);
    });
  }

  @override
  void dispose() {
    _feedController.dispose();
    super.dispose();
  }

  Future<Community?> _load() async {
    final community = await widget.repository.getCommunity(widget.communityId);
    if (mounted) _community = community;
    return community;
  }

  Future<void> _mutate({required bool membership}) async {
    if (!widget.isAuthenticated) {
      widget.onRequireAuth();
      return;
    }
    if (!widget.canFollow) {
      widget.onFeedback('游客模式只能浏览、评论和举报，登录邮箱账号后才能关注或加入板块');
      return;
    }
    final community = _community;
    final mutation = widget.repository is CommunityMutationRepository
        ? widget.repository as CommunityMutationRepository
        : null;
    if (community == null || mutation == null || _busy) return;
    setState(() => _busy = true);
    try {
      final active = membership ? !community.isMember : !community.isFollowing;
      if (membership) {
        await mutation.setMembership(communityId: community.id, active: active);
      } else {
        await mutation.setFollow(communityId: community.id, active: active);
      }
      if (mounted) setState(() => _future = _load());
    } catch (error) {
      if (mounted) {
        widget.onFeedback(userFacingApiMessage(error, fallback: '操作失败'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('板块详情')),
    body: FutureBuilder<Community?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data == null) {
          return const Center(child: Text('板块不存在或加载失败'));
        }
        final community = snapshot.data!;
        _community = community;
        return RefreshIndicator(
          onRefresh: _feedController.refresh,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.extentAfter < 360) {
                _feedController.loadMore();
              }
              return false;
            },
            child: AnimatedBuilder(
              animation: _feedController,
              builder: (context, _) {
                final feed = _feedController.state;
                return CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                      sliver: SliverToBoxAdapter(
                        child: _communityHeader(community),
                      ),
                    ),
                    ..._feedSlivers(feed),
                    const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
                  ],
                );
              },
            ),
          ),
        );
      },
    ),
  );

  Widget _communityHeader(Community community) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const CircleAvatar(
        radius: 34,
        backgroundColor: AppTheme.surfaceBlue,
        child: Icon(Icons.forum_outlined, color: AppTheme.primary, size: 34),
      ),
      const SizedBox(height: 14),
      Text(
        community.name,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
      ),
      Text(
        '@${community.slug}',
        style: const TextStyle(color: AppTheme.textSecondary),
      ),
      const SizedBox(height: 12),
      Text(community.description),
      const SizedBox(height: 20),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Stat(label: '帖子', value: community.postCount),
          _Stat(label: '成员', value: community.memberCount),
          _Stat(label: '关注', value: community.followerCount),
        ],
      ),
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _busy ? null : () => _mutate(membership: false),
              child: AnimatedSwitcher(
                duration: AppMotion.duration(context, AppMotion.fast),
                child: Text(
                  community.isFollowing ? '已关注' : '关注板块',
                  key: ValueKey(community.isFollowing),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: _busy ? null : () => _mutate(membership: true),
              child: Text(community.isMember ? '已加入' : '加入板块'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 28),
      const Text(
        '板块帖子',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 10),
    ],
  );

  List<Widget> _feedSlivers(FeedState feed) {
    if (feed.status == FeedStatus.error && feed.items.isEmpty) {
      return const [
        SliverToBoxAdapter(child: _CommunityFeedMessage(text: '帖子加载失败，向下拉可重试')),
      ];
    }
    if ((feed.status == FeedStatus.initial ||
            (feed.status == FeedStatus.loading && feed.items.isEmpty)) &&
        feed.items.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ];
    }
    if (feed.items.isEmpty) {
      return const [
        SliverToBoxAdapter(child: _CommunityFeedMessage(text: '这个板块还没有帖子')),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final post = feed.items[index];
            return ForumPostCard(
              post: post,
              onOpen: () => widget.onOpenPost(post),
              onOpenComments: () => widget.onOpenComments(post),
              onLike: () => widget.onToggleLike(post),
              onBookmark: () => widget.onToggleBookmark(post),
              onMenu: () => widget.onFeedback('更多操作请在帖子详情中进行'),
              interactionListenable: widget.interactionController,
            );
          }, childCount: feed.items.length),
        ),
      ),
      if (feed.status == FeedStatus.loadingMore)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          ),
        )
      else if (!feed.hasMore)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: 4),
            child: Center(
              child: Text(
                '没有更多帖子了',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          ),
        ),
    ];
  }
}

class _CommunityFeedMessage extends StatelessWidget {
  const _CommunityFeedMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Center(
      child: Text(text, style: const TextStyle(color: AppTheme.textSecondary)),
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.onTap});
  final String label;
  final int value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(
      children: [
        Text(
          '$value',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        Text(
          label,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
      ],
    ),
  );
}
