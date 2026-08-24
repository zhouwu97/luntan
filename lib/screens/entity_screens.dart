import 'package:flutter/material.dart';

import '../data/api/api_client.dart';
import '../data/api/user_repository.dart';
import '../domain/models.dart';
import '../domain/repositories.dart';
import '../theme/app_theme.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({
    super.key,
    required this.repository,
    required this.userId,
    required this.isAuthenticated,
    required this.onRequireAuth,
    required this.onFeedback,
    required this.onOpenPostId,
  });

  final UserRepository repository;
  final String userId;
  final bool isAuthenticated;
  final VoidCallback onRequireAuth;
  final ValueChanged<String> onFeedback;
  final ValueChanged<String> onOpenPostId;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  late Future<UserProfile?> _future;
  late Future<UserPostPage> _postsFuture;
  UserProfile? _profile;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _postsFuture = widget.repository.listPosts(widget.userId);
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
                        'Lv.${profile.level}',
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
                    child: Text(profile.isFollowing ? '已关注' : '关注'),
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
                _Stat(label: '关注者', value: profile.followerCount),
                _Stat(label: '关注', value: profile.followingCount),
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
                if (postsSnapshot.hasError ||
                    postsSnapshot.data!.items.isEmpty) {
                  return const Text(
                    '暂时没有公开帖子',
                    style: TextStyle(color: AppTheme.textSecondary),
                  );
                }
                return Column(
                  children: postsSnapshot.data!.items
                      .map(
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
                      )
                      .toList(),
                );
              },
            ),
          ],
        );
      },
    ),
  );
}

class CommunityDetailScreen extends StatefulWidget {
  const CommunityDetailScreen({
    super.key,
    required this.repository,
    required this.communityId,
    required this.isAuthenticated,
    required this.onRequireAuth,
    required this.onFeedback,
  });

  final CommunityRepository repository;
  final String communityId;
  final bool isAuthenticated;
  final VoidCallback onRequireAuth;
  final ValueChanged<String> onFeedback;

  @override
  State<CommunityDetailScreen> createState() => _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends State<CommunityDetailScreen> {
  late Future<Community?> _future;
  Community? _community;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
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
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            const CircleAvatar(
              radius: 34,
              backgroundColor: AppTheme.surfaceBlue,
              child: Icon(
                Icons.forum_outlined,
                color: AppTheme.primary,
                size: 34,
              ),
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
                    child: Text(community.isFollowing ? '已关注' : '关注板块'),
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
          ],
        );
      },
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
