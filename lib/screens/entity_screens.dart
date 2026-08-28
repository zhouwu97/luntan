import 'package:flutter/material.dart';

import '../controllers/feed_controller.dart';
import '../controllers/interaction_controller.dart';
import '../data/api/api_client.dart';
import '../data/api/profile_repository.dart';
import '../data/api/publish_repository.dart';
import '../data/api/store_repository.dart';
import '../data/api/user_repository.dart';
import '../domain/models.dart';
import '../domain/repositories.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import '../widgets/forum_post_card.dart';
import 'profile_screen.dart';

bool _hasUsableAvatar(String? value) {
  final url = value?.trim().toLowerCase();
  return url != null && (url.startsWith('https://') || url.startsWith('http://'));
}

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
    this.onOpenPostById,
    this.onOpenRelations,
    this.profileRepository,
    this.publishRepository,
    this.storeRepository,
    this.isSelf = false,
    this.profileSummary,
  });

  final UserRepository repository;
  final String userId;
  final bool isAuthenticated;
  final bool canFollow;
  final VoidCallback onRequireAuth;
  final ValueChanged<String> onFeedback;
  final ValueChanged<String> onOpenPostId;
  final OpenPostById? onOpenPostById;
  final void Function(String userId, bool followers)? onOpenRelations;
  final ProfileRepository? profileRepository;
  final PublishRepository? publishRepository;
  final StoreRepository? storeRepository;
  final bool isSelf;
  final ProfileSummary? profileSummary;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  late Future<UserProfile?> _future;
  late Future<UserPostPage> _postsFuture;
  late Future<ProfileListPage?> _commentsFuture;
  UserProfile? _profile;
  ProfileSummary? _selfSummary;
  int? _pointsBalance;
  bool _busy = false;
  int _currentTab = 0; // 0: 帖子, 1: 评论
  final ScrollController _postsScrollController = ScrollController();
  final ScrollController _commentsScrollController = ScrollController();
  final List<UserPost> _posts = <UserPost>[];
  final List<ProfilePostItem> _comments = <ProfilePostItem>[];
  String? _nextPostsCursor;
  bool _hasMorePosts = true;
  bool _loadingMorePosts = false;
  String? _nextCommentsCursor;
  bool _hasMoreComments = true;
  bool _loadingMoreComments = false;

  @override
  void initState() {
    super.initState();
    _selfSummary = widget.profileSummary;
    _future = _load();
    _postsFuture = _loadInitialPosts();
    _commentsFuture = _loadInitialComments();
    _loadPoints();
    _postsScrollController.addListener(_loadMorePostsWhenNeeded);
    _commentsScrollController.addListener(_loadMoreCommentsWhenNeeded);
  }

  @override
  void dispose() {
    _postsScrollController
      ..removeListener(_loadMorePostsWhenNeeded)
      ..dispose();
    _commentsScrollController
      ..removeListener(_loadMoreCommentsWhenNeeded)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadPoints() async {
    if (widget.storeRepository == null) return;
    try {
      final overview = await widget.storeRepository!.overview();
      if (mounted) setState(() => _pointsBalance = overview.balance);
    } catch (_) {}
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

  Future<ProfileListPage?> _loadInitialComments() async {
    if (widget.profileRepository == null) return null;
    try {
      final page = await widget.profileRepository!.list('comments');
      if (!mounted) return page;
      setState(() {
        _comments
          ..clear()
          ..addAll(page.items);
        _nextCommentsCursor = page.nextCursor;
        _hasMoreComments = page.hasMore;
      });
      return page;
    } catch (_) {
      return null;
    }
  }

  void _loadMorePostsWhenNeeded() {
    if (_postsScrollController.position.extentAfter < 260) {
      _loadMorePosts();
    }
  }

  void _loadMoreCommentsWhenNeeded() {
    if (_commentsScrollController.position.extentAfter < 260) {
      _loadMoreComments();
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

  Future<void> _loadMoreComments() async {
    if (_loadingMoreComments || !_hasMoreComments || _nextCommentsCursor == null || widget.profileRepository == null) {
      return;
    }
    setState(() => _loadingMoreComments = true);
    try {
      final page = await widget.profileRepository!.list(
        'comments',
        cursor: _nextCommentsCursor,
      );
      if (!mounted) return;
      setState(() {
        final ids = _comments.map((c) => c.id).toSet();
        _comments.addAll(page.items.where((c) => ids.add(c.id)));
        final nextCursor = page.nextCursor;
        _hasMoreComments = page.hasMore && nextCursor != _nextCommentsCursor;
        _nextCommentsCursor = nextCursor;
      });
    } catch (error) {
      if (mounted) {
        widget.onFeedback(userFacingApiMessage(error, fallback: '更多评论加载失败'));
      }
    } finally {
      if (mounted) setState(() => _loadingMoreComments = false);
    }
  }

  Future<UserProfile?> _load() async {
    if (widget.isSelf && widget.profileRepository != null) {
      try {
        final summary = await widget.profileRepository!.getProfile();
        if (mounted) {
          setState(() {
            _selfSummary = summary;
          });
        }
      } catch (_) {}
    }
    final profile = await widget.repository.getProfile(widget.userId);
    if (mounted) setState(() => _profile = profile);
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

  Future<void> _openEditProfile() async {
    if (widget.profileRepository == null) return;
    final summary = _selfSummary ?? (_profile != null
        ? ProfileSummary(
            id: _profile!.id,
            username: _profile!.username,
            nickname: _profile!.nickname,
            avatarMediaId: _profile!.avatarMediaId,
            level: _profile!.level,
            experience: _profile!.experience,
            growth: _profile!.growth,
            trustLevel: _profile!.trustLevel,
            signature: _profile!.bio,
            postCount: _profile!.postCount,
            commentCount: 0,
            likeReceivedCount: 0,
            followerCount: _profile!.followerCount,
            followingCount: _profile!.followingCount,
          )
        : null);
    if (summary == null) return;

    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => EditProfileScreen(
          profile: summary,
          repository: widget.profileRepository!,
          publishRepository: widget.publishRepository,
        ),
      ),
    );
    if (updated == true && mounted) {
      widget.onFeedback('个人资料已更新');
      _future = _load();
      _postsFuture = _loadInitialPosts();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: FutureBuilder<UserProfile?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done && _profile == null && _selfSummary == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError && _profile == null && _selfSummary == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('用户不存在或加载失败', style: TextStyle(color: AppTheme.textSecondary)),
                  const SizedBox(height: 8),
                  TextButton(onPressed: () => setState(() => _future = _load()), child: const Text('重试')),
                ],
              ),
            ),
          );
        }

        final profile = snapshot.data ?? _profile;
        if (profile != null) _profile = profile;

        final nickname = _selfSummary?.nickname.isNotEmpty == true
            ? _selfSummary!.nickname
            : (profile?.nickname.isNotEmpty == true ? profile!.nickname : '游客');
        final username = _selfSummary?.username.isNotEmpty == true
            ? _selfSummary!.username
            : (profile?.username.isNotEmpty == true ? profile!.username : 'guest');
        final level = _selfSummary?.level ?? profile?.level ?? 1;
        final trustLevel = _selfSummary?.trustLevel.isNotEmpty == true
            ? _selfSummary!.trustLevel
            : (profile?.trustLevel.isNotEmpty == true ? profile!.trustLevel : 'new');
        final signature = _selfSummary?.signature.isNotEmpty == true
            ? _selfSummary!.signature
            : (profile?.bio.isNotEmpty == true ? profile!.bio : '');
        final postCount = _selfSummary?.postCount ?? profile?.postCount ?? _posts.length;
        final commentCount = _selfSummary?.commentCount ?? _comments.length;
        final followerCount = _selfSummary?.followerCount ?? profile?.followerCount ?? 0;
        final followingCount = _selfSummary?.followingCount ?? profile?.followingCount ?? 0;
        final likeReceivedCount = _selfSummary?.likeReceivedCount ?? 0;
        final avatarUrl = _selfSummary?.avatarUrl;
        final growth = _selfSummary?.growth ?? profile?.growth;
        final experience = _selfSummary?.experience ?? profile?.experience ?? 0;
        final expInLevel = growth?.experienceInLevel ?? 0;
        final expReq = growth?.experienceRequiredInLevel ?? 1000;
        final isLocked = growth?.levelLocked == true;

        return Stack(
          children: [
            // 1. Hero 梦幻渐变头图背景
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 445,
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(0.4, -1),
                        end: Alignment(-0.4, 1),
                        colors: [
                          Color(0xFF8FBEFA),
                          Color(0xFFAFD9F7),
                          Color(0xFFFFD2DB),
                          Color(0xFFF4C79E),
                        ],
                        stops: [0.0, 0.30, 0.69, 1.0],
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x050B1422),
                            Color(0x140A1422),
                            Color(0xCC070D18),
                          ],
                          stops: [0.0, 0.34, 1.0],
                        ),
                      ),
                    ),
                  ),
                  // Hero 顶部快捷操作栏
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: const BoxDecoration(
                                color: Color(0x560F1822),
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                                onPressed: () => Navigator.of(context).pop(),
                                tooltip: '返回',
                              ),
                            ),
                            if (widget.isSelf)
                              Container(
                                width: 38,
                                height: 38,
                                decoration: const BoxDecoration(
                                  color: Color(0x560F1822),
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  icon: const Icon(Icons.settings_outlined, color: Colors.white, size: 20),
                                  onPressed: _openEditProfile,
                                  tooltip: '主页设置',
                                ),
                              )
                            else if (profile != null)
                              Container(
                                width: 38,
                                height: 38,
                                decoration: const BoxDecoration(
                                  color: Color(0x560F1822),
                                  shape: BoxShape.circle,
                                ),
                                child: PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_horiz_rounded, color: Colors.white, size: 20),
                                  onSelected: (value) {
                                    if (value == 'block') _toggleBlock();
                                  },
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      value: 'block',
                                      child: Text(profile.isBlocked ? '取消拉黑' : '拉黑用户'),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Hero 个人信息内容区
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 48,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 头像 + 编辑/关注按钮
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 78,
                              height: 78,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 3),
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFF4F9FF), Color(0xFFD8EDFF)],
                                ),
                                boxShadow: const [
                                  BoxShadow(color: Color(0x2E000000), blurRadius: 18, offset: Offset(0, 6)),
                                ],
                              ),
                              child: ClipOval(
                                child: _hasUsableAvatar(avatarUrl)
                                    ? Image.network(avatarUrl!, fit: BoxFit.cover)
                                    : Center(
                                        child: Text(
                                          nickname.isEmpty ? '游' : nickname.characters.first,
                                          style: const TextStyle(
                                            color: Color(0xFF417CC0),
                                            fontSize: 29,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                            const Spacer(),
                            if (widget.isSelf)
                              InkWell(
                                onTap: _openEditProfile,
                                borderRadius: BorderRadius.circular(13),
                                child: Container(
                                  height: 35,
                                  padding: const EdgeInsets.symmetric(horizontal: 14),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
                                    color: Colors.white.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                  alignment: Alignment.center,
                                  child: const Text(
                                    '编辑资料',
                                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                                  ),
                                ),
                              )
                            else if (profile != null && profile.canFollow)
                              FilledButton.tonal(
                                onPressed: _busy ? null : _toggleFollow,
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                                ),
                                child: Text(profile.isFollowing ? '已关注' : '关注'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // 昵称 + 等级胶囊
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                nickname,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.4,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4B97C6),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                isLocked ? 'Lv.0' : 'Lv.$level',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        // ID 与信任标签
                        Text(
                          '@$username · 信任 $trustLevel',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 12),
                        ),
                        if (signature.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            signature,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12),
                          ),
                        ],
                        const SizedBox(height: 12),
                        // 统计指标行 (获赞、关注、粉丝)
                        Row(
                          children: [
                            _HeroStatItem(
                              value: likeReceivedCount,
                              label: '获赞',
                              onTap: () => widget.onFeedback('共收到 $likeReceivedCount 个点赞'),
                            ),
                            const SizedBox(width: 24),
                            _HeroStatItem(
                              value: followingCount,
                              label: '关注',
                              onTap: widget.onOpenRelations == null
                                  ? null
                                  : () => widget.onOpenRelations!(profile?.id ?? widget.userId, false),
                            ),
                            const SizedBox(width: 24),
                            _HeroStatItem(
                              value: followerCount,
                              label: '粉丝',
                              onTap: widget.onOpenRelations == null
                                  ? null
                                  : () => widget.onOpenRelations!(profile?.id ?? widget.userId, true),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // 经验与积分长胶囊
                        Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 13),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                            color: const Color(0x3E1E2630),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              if (isLocked) ...[
                                const Text(
                                  'Lv.0',
                                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    '累计经验 $experience EXP · 🔒 注册后解锁等级',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.9),
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ] else ...[
                                Text(
                                  'Lv.$level',
                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(99),
                                    child: Container(
                                      height: 7,
                                      color: Colors.white.withValues(alpha: 0.32),
                                      alignment: Alignment.centerLeft,
                                      child: FractionallySizedBox(
                                        widthFactor: expReq > 0 ? (expInLevel / expReq).clamp(0.05, 1.0) : 0.5,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF64B6DF),
                                            borderRadius: BorderRadius.circular(99),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 9),
                                Text(
                                  '$expInLevel / $expReq EXP',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: 11),
                                ),
                              ],
                              if (_pointsBalance != null) ...[
                                const SizedBox(width: 10),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.monetization_on_rounded, color: AppTheme.orange, size: 15),
                                    const SizedBox(width: 3),
                                    Text(
                                      '$_pointsBalance',
                                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // 2. 底部悬浮圆角面板与 Feed 流
            Positioned(
              top: 407,
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(color: Color(0x140E1D2C), blurRadius: 20, offset: Offset(0, -8)),
                  ],
                ),
                child: Column(
                  children: [
                    // Tab 切换条
                    Container(
                      height: 52,
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: Color(0xFFEEF1F4), width: 1)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _HomeTabButton(
                              label: '帖子 ${postCount > 0 ? postCount : _posts.length}',
                              active: _currentTab == 0,
                              onTap: () => setState(() => _currentTab = 0),
                            ),
                          ),
                          Expanded(
                            child: _HomeTabButton(
                              label: '评论 ${commentCount > 0 ? commentCount : _comments.length}',
                              active: _currentTab == 1,
                              onTap: () => setState(() => _currentTab = 1),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Feed 流列表
                    Expanded(
                      child: _currentTab == 0
                          ? _buildPostsFeed(nickname, isLocked, level)
                          : _buildCommentsFeed(nickname, isLocked, level),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _buildPostsFeed(String authorName, bool isLocked, int level) => FutureBuilder<UserPostPage>(
    future: _postsFuture,
    builder: (context, postsSnapshot) {
      if (postsSnapshot.connectionState != ConnectionState.done && _posts.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      final posts = _posts.isEmpty ? postsSnapshot.data?.items ?? const <UserPost>[] : _posts;
      if (posts.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceBlue,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.article_outlined, color: AppTheme.primary, size: 24),
              ),
              const SizedBox(height: 10),
              const Text('还没有发布过帖子', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            ],
          ),
        );
      }
      return ListView.separated(
        controller: _postsScrollController,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
        itemCount: posts.length + (_loadingMorePosts ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFFF0F2F5)),
        itemBuilder: (context, index) {
          if (index == posts.length) {
            return const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          final post = posts[index];
          return _PrototypePostCard(
            post: post,
            authorNickname: authorName,
            authorLevel: isLocked ? 0 : level,
            onTap: () => widget.onOpenPostId(post.id),
          );
        },
      );
    },
  );

  Widget _buildCommentsFeed(String authorName, bool isLocked, int level) => FutureBuilder<ProfileListPage?>(
    future: _commentsFuture,
    builder: (context, commentsSnapshot) {
      if (commentsSnapshot.connectionState != ConnectionState.done && _comments.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      final comments = _comments.isEmpty ? commentsSnapshot.data?.items ?? const <ProfilePostItem>[] : _comments;
      if (comments.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceBlue,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.chat_bubble_outline_rounded, color: AppTheme.primary, size: 24),
              ),
              const SizedBox(height: 10),
              const Text('还没有发表过评论', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            ],
          ),
        );
      }
      return ListView.separated(
        controller: _commentsScrollController,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
        itemCount: comments.length + (_loadingMoreComments ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFFF0F2F5)),
        itemBuilder: (context, index) {
          if (index == comments.length) {
            return const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          final comment = comments[index];
          return _PrototypeCommentCard(
            item: comment,
            authorNickname: authorName,
            authorLevel: isLocked ? 0 : level,
            onTap: () => widget.onOpenPostId(comment.id),
          );
        },
      );
    },
  );
}

class _HeroStatItem extends StatelessWidget {
  const _HeroStatItem({
    required this.value,
    required this.label,
    this.onTap,
  });

  final int value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            '$value',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12,
            ),
          ),
        ],
      ),
    ),
  );
}

class _HomeTabButton extends StatelessWidget {
  const _HomeTabButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Center(
          child: Text(
            label,
            style: TextStyle(
              color: active ? const Color(0xFF3E68A0) : const Color(0xFF74818D),
              fontSize: 15,
              fontWeight: active ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
        if (active)
          Positioned(
            left: 38,
            right: 38,
            bottom: 0,
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                color: const Color(0xFF6A86CF),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
      ],
    ),
  );
}

class _PrototypePostCard extends StatelessWidget {
  const _PrototypePostCard({
    required this.post,
    required this.authorNickname,
    required this.authorLevel,
    required this.onTap,
  });

  final UserPost post;
  final String authorNickname;
  final int authorLevel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 作者信息栏 + 信任盾牌标签
          Row(
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: AppTheme.surfaceBlue,
                child: Text(
                  authorNickname.isEmpty ? '杯' : authorNickname.characters.first,
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            authorNickname,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F3F7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Lv.$authorLevel',
                            style: const TextStyle(color: Color(0xFF5F8DA7), fontSize: 9, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      relativeTimeLabel(post.createdAt),
                      style: const TextStyle(fontSize: 10, color: Color(0xFF9AA5AE)),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE9F8EE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield_outlined, color: Color(0xFF4CB87A), size: 12),
                    SizedBox(width: 3),
                    Text(
                      '100%',
                      style: TextStyle(color: Color(0xFF4CB87A), fontSize: 10, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 帖子标题
          Text(
            post.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
              height: 1.35,
            ),
          ),
          if (post.contentPreview.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              post.contentPreview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: Color(0xFF45505A), height: 1.55),
            ),
          ],
          const SizedBox(height: 10),
          // 浏览、点赞、评论度量行
          Row(
            children: [
              _MetricItem(icon: Icons.visibility_outlined, label: '${post.commentCount * 12 + 18}'),
              const SizedBox(width: 17),
              _MetricItem(icon: Icons.favorite_border_rounded, label: '${post.commentCount > 0 ? post.commentCount : 1}'),
              const SizedBox(width: 17),
              _MetricItem(icon: Icons.chat_bubble_outline_rounded, label: '${post.commentCount}'),
            ],
          ),
        ],
      ),
    ),
  );
}

class _PrototypeCommentCard extends StatelessWidget {
  const _PrototypeCommentCard({
    required this.item,
    required this.authorNickname,
    required this.authorLevel,
    required this.onTap,
  });

  final ProfilePostItem item;
  final String authorNickname;
  final int authorLevel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: AppTheme.surfaceBlue,
                child: Text(
                  authorNickname.isEmpty ? '杯' : authorNickname.characters.first,
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        authorNickname,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F3F7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Lv.$authorLevel',
                          style: const TextStyle(color: Color(0xFF5F8DA7), fontSize: 9, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    relativeTimeLabel(item.activityAt ?? item.publishedAt),
                    style: const TextStyle(fontSize: 10, color: Color(0xFF9AA5AE)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.contentPreview.isNotEmpty ? item.contentPreview : '发表了评论',
            style: const TextStyle(fontSize: 13, color: Color(0xFF394856), height: 1.55),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F8FB),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '回复帖子：${item.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Color(0xFF708294)),
            ),
          ),
        ],
      ),
    ),
  );
}

class _MetricItem extends StatelessWidget {
  const _MetricItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: const Color(0xFFA3ADB6)),
      const SizedBox(width: 4),
      Text(
        label,
        style: const TextStyle(fontSize: 10, color: Color(0xFFA3ADB6)),
      ),
    ],
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
  const _Stat({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Column(
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
  );
}

