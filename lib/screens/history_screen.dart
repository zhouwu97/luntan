import 'package:flutter/material.dart';

import '../data/api/api_client.dart';
import '../data/api/profile_repository.dart';
import '../data/mock_forum_data.dart';
import '../theme/app_theme.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    this.repository,
    this.store,
    this.onOpenPost,
    this.onOpenPostById,
    this.onOpenHome,
  });

  final ProfileRepository? repository;
  final ForumStore? store;
  final ValueChanged<Post>? onOpenPost;
  final void Function(String postId, {String? focusCommentId})? onOpenPostById;
  final VoidCallback? onOpenHome;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final ScrollController _scrollController = ScrollController();
  final List<ProfilePostItem> _items = [];
  String? _nextCursor;
  bool _hasMore = false;
  bool _loading = false;
  bool _loadingMore = false;
  bool _clearing = false;
  String? _errorMessage;
  String? _loadMoreError;

  bool get _isApiMode => widget.repository != null;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    if (_isApiMode) {
      _loadInitial();
    } else if (widget.store != null) {
      widget.store!.addListener(_onStoreChanged);
      _syncFromStore();
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    if (!_isApiMode && widget.store != null) {
      widget.store!.removeListener(_onStoreChanged);
    }
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(_syncFromStore);
  }

  void _syncFromStore() {
    final history = widget.store?.history ?? [];
    _items
      ..clear()
      ..addAll(
        history.map(
          (post) => ProfilePostItem(
            id: post.id,
            communityName: post.community?.name ?? post.section.label,
            title: post.title,
            contentPreview: post.content,
            postContentPreview: post.content,
            communityId: post.communityId.isNotEmpty
                ? post.communityId
                : post.section.communityId,
            commentCount: post.commentCount,
            likeCount: post.likeCount,
            bookmarkCount: post.bookmarkCount,
            publishedAt: post.publishedAt ?? post.createdAt,
            activityAt: post.activityAt ?? post.createdAt,
            authorId: post.author?.id ?? post.authorId,
            authorNickname: post.author?.nickname ?? post.author?.username ?? '',
          ),
        ),
      );
    _hasMore = false;
    _loading = false;
  }

  void _onScroll() {
    if (!_isApiMode) return;
    if (_scrollController.position.extentAfter < 240) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    if (!mounted || widget.repository == null) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final page = await widget.repository!.list('history', limit: 20);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (_) {
      if (mounted) setState(() => _errorMessage = '加载失败，请重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (!_isApiMode ||
        _loading ||
        _loadingMore ||
        !_hasMore ||
        _nextCursor == null) {
      return;
    }
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    try {
      final page = await widget.repository!.list(
        'history',
        cursor: _nextCursor,
        limit: 20,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadMoreError = e.message);
    } catch (_) {
      if (mounted) setState(() => _loadMoreError = '加载失败 · 点击重试');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _clearHistory() async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('清空浏览历史？'),
            content: const Text('清空后将无法恢复。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('清空'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) return;

    setState(() => _clearing = true);
    try {
      if (_isApiMode) {
        await widget.repository!.clearHistory();
        if (!mounted) return;
        setState(() {
          _items.clear();
          _nextCursor = null;
          _hasMore = false;
        });
      } else {
        widget.store?.clearHistory();
        if (!mounted) return;
        setState(() => _items.clear());
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('浏览历史已清空'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('清空失败，请稍后重试'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  void _navigateToPost(ProfilePostItem item) {
    if (widget.onOpenPostById != null) {
      widget.onOpenPostById!(item.id, focusCommentId: item.commentId);
      return;
    }
    if (widget.onOpenPost != null) {
      final post = Post(
        id: item.id,
        authorId: item.authorId,
        communityId: item.communityId,
        title: item.title,
        content: item.contentPreview,
        commentCount: item.commentCount,
        likeCount: item.likeCount,
        bookmarkCount: item.bookmarkCount,
        createdAt: item.publishedAt,
        updatedAt: item.publishedAt,
        publishedAt: item.publishedAt,
      );
      widget.onOpenPost!(post);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('浏览历史'),
        centerTitle: false,
        backgroundColor: AppTheme.surface,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        actions: [
          if (_items.isNotEmpty)
            TextButton(
              onPressed: _clearing ? null : _clearHistory,
              child: _clearing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      '清空',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: AppTheme.textSecondary.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _loadInitial,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceBlue,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.history_toggle_off_rounded,
                  size: 36,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '暂无浏览记录',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '去首页逛逛，发现更多精彩内容吧',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
              if (widget.onOpenHome != null) ...[
                const SizedBox(height: 20),
                FilledButton.tonal(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onOpenHome?.call();
                  },
                  child: const Text('去首页逛逛'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final listView = ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _items.length + (_loadingMore || _loadMoreError != null ? 1 : 0),
      separatorBuilder: (_, _) => const Divider(
        height: 1,
        color: AppTheme.border,
        indent: 52,
      ),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          if (_loadingMore) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          if (_loadMoreError != null) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: TextButton(
                  onPressed: _loadMore,
                  child: Text(
                    _loadMoreError!,
                    style: const TextStyle(fontSize: 13, color: AppTheme.primary),
                  ),
                ),
              ),
            );
          }
          return const SizedBox.shrink();
        }

        final item = _items[index];
        final timeLabel = item.activityAt != null
            ? relativeTimeLabel(item.activityAt!)
            : relativeTimeLabel(item.publishedAt);

        final metaParts = <String>[
          if (item.communityName.isNotEmpty) item.communityName,
          '${item.commentCount} 回复',
          '发布于$timeLabel',
        ];

        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _navigateToPost(item),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF4FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.history_rounded,
                    color: AppTheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        metaParts.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: Color(0xFFB5C4D3),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (_isApiMode) {
      return RefreshIndicator(
        onRefresh: _loadInitial,
        child: listView,
      );
    }

    return listView;
  }
}
