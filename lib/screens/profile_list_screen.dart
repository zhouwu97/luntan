import 'package:flutter/material.dart';

import '../data/api/api_client.dart';
import '../data/api/profile_repository.dart';
import '../theme/app_theme.dart';

typedef OpenPostById = void Function(String postId, {String? focusCommentId});

class ProfileListScreen extends StatefulWidget {
  const ProfileListScreen({
    super.key,
    required this.label,
    required this.kind,
    required this.repository,
    required this.onOpenPostId,
  });

  final String label;
  final String kind;
  final ProfileRepository repository;
  final OpenPostById onOpenPostId;

  @override
  State<ProfileListScreen> createState() => _ProfileListScreenState();
}

class _ProfileListScreenState extends State<ProfileListScreen> {
  var _loading = true;
  var _loadingMore = false;
  var _items = <ProfilePostItem>[];
  String? _cursor;
  var _hasMore = false;
  String? _error;
  String? _loadMoreError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.repository.list(
        widget.kind,
        limit: 20,
        includeDetails: false,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _items = page.items;
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载失败，请重试';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _cursor == null) return;
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    try {
      final page = await widget.repository.list(
        widget.kind,
        cursor: _cursor,
        limit: 20,
        includeDetails: false,
      );
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _items = [..._items, ...page.items];
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _loadMoreError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _loadMoreError = '加载失败';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.label),
        backgroundColor: AppTheme.surface,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      backgroundColor: AppTheme.background,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error!,
                        style: const TextStyle(color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _load,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : _items.isEmpty
                  ? Center(
                      child: Text(
                        '${widget.label}为空',
                        style: const TextStyle(color: AppTheme.textSecondary),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification.metrics.extentAfter < 240) {
                            _loadMore();
                          }
                          return false;
                        },
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          itemCount: _items.length +
                              (_loadingMore || _loadMoreError != null ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index >= _items.length) {
                              return _loadingMore
                                  ? const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(16),
                                        child: CircularProgressIndicator(),
                                      ),
                                    )
                                  : Center(
                                      child: TextButton(
                                        onPressed: _loadMore,
                                        child: const Text('加载失败 · 点击重试'),
                                      ),
                                    );
                            }
                            final item = _items[index];
                            return ListTile(
                              leading: const Icon(
                                Icons.article_outlined,
                                color: AppTheme.primary,
                              ),
                              title: Text(
                                item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  [
                                    item.communityName,
                                    '${item.commentCount} 回复',
                                    _formatTime(item.publishedAt),
                                  ].join(' · '),
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              onTap: () => widget.onOpenPostId(
                                item.id,
                                focusCommentId: item.commentId,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays > 7) {
      return '${dt.month}月${dt.day}日';
    }
    if (diff.inDays > 0) return '${diff.inDays}天前';
    if (diff.inHours > 0) return '${diff.inHours}小时前';
    if (diff.inMinutes > 0) return '${diff.inMinutes}分钟前';
    return '刚刚';
  }
}
