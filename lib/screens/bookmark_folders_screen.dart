import 'package:flutter/material.dart';

import '../data/api/api_client.dart';
import '../data/api/bookmark_repository.dart';
import '../theme/app_theme.dart';

class BookmarkFoldersScreen extends StatefulWidget {
  const BookmarkFoldersScreen({
    super.key,
    required this.repository,
    required this.onOpenPostId,
  });

  final BookmarkRepository repository;
  final ValueChanged<String> onOpenPostId;

  @override
  State<BookmarkFoldersScreen> createState() => _BookmarkFoldersScreenState();
}

class _BookmarkFoldersScreenState extends State<BookmarkFoldersScreen> {
  late Future<BookmarkFolderPage> _future;
  BookmarkFolderPage _page = const BookmarkFolderPage(items: []);
  bool _loadingMore = false;
  Object? _loadMoreError;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _future = _loadPage();
  }

  Future<BookmarkFolderPage> _loadPage({String? cursor}) async {
    final page = await widget.repository.listFolders(cursor: cursor);
    _page = page;
    return page;
  }

  Future<void> _reload() async {
    if (!mounted) return;
    late final Future<BookmarkFolderPage> future;
    setState(() {
      _loadingMore = false;
      _loadMoreError = null;
      future = _future = _loadPage();
    });
    try {
      await future;
    } catch (_) {
      // FutureBuilder 展示错误态；RefreshIndicator 不再把异常抛给手势层。
    }
  }

  void _loadMoreFolders() {
    if (_loadingMore || !_page.hasMore || _page.nextCursor == null) return;
    final cursor = _page.nextCursor;
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
      _future = _appendFolders(cursor!);
    });
  }

  Future<BookmarkFolderPage> _appendFolders(String cursor) async {
    try {
      final page = await widget.repository.listFolders(cursor: cursor);
      final seen = _page.items.map((item) => item.id).toSet();
      final merged = BookmarkFolderPage(
        items: [
          ..._page.items,
          ...page.items.where((item) => seen.add(item.id)),
        ],
        nextCursor: page.nextCursor,
        hasMore: page.hasMore && page.nextCursor != cursor,
      );
      _page = merged;
      _loadMoreError = null;
      return merged;
    } catch (error) {
      if (mounted) setState(() => _loadMoreError = error);
      rethrow;
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的收藏'),
        actions: [
          IconButton(
            onPressed: _creating ? null : _createFolder,
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: '新建收藏夹',
          ),
        ],
      ),
      body: FutureBuilder<BookmarkFolderPage>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done &&
              _page.items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError && _page.items.isEmpty) {
            return _MessageState(
              message: '收藏夹加载失败',
              action: TextButton(onPressed: _reload, child: const Text('重试')),
            );
          }
          final folders = snapshot.data?.items ?? _page.items;
          if (folders.isEmpty) {
            return _MessageState(
              message: '还没有收藏夹',
              action: FilledButton.icon(
                onPressed: _createFolder,
                icon: const Icon(Icons.add),
                label: const Text('新建收藏夹'),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.metrics.extentAfter < 240) {
                  _loadMoreFolders();
                }
                return false;
              },
              child: ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                itemCount:
                    folders.length +
                    (_loadingMore || _loadMoreError != null ? 1 : 0),
                // 3.41.8 无 onReorderItem，待 SDK 统一后迁移
                // ignore: deprecated_member_use
                onReorder: (oldIndex, newIndex) =>
                    _reorderFolders(folders, oldIndex, newIndex),
                itemBuilder: (context, index) {
                  if (index >= folders.length) {
                    return _loadingMore
                        ? const Center(
                            key: ValueKey<String>('bookmark-folders-loading'),
                            child: CircularProgressIndicator(),
                          )
                        : Center(
                            key: const ValueKey<String>(
                              'bookmark-folders-load-more-error',
                            ),
                            child: TextButton(
                              onPressed: _loadMoreFolders,
                              child: const Text('加载失败 · 点击重试'),
                            ),
                          );
                  }
                  return _FolderCard(
                    key: ValueKey(folders[index].id),
                    folder: folders[index],
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => BookmarkFolderScreen(
                            repository: widget.repository,
                            folder: folders[index],
                            onOpenPostId: widget.onOpenPostId,
                          ),
                        ),
                      );
                      if (mounted) _reload();
                    },
                    onRename: folders[index].isDefault
                        ? null
                        : () => _renameFolder(folders[index]),
                    onDelete: folders[index].isDefault
                        ? null
                        : () => _deleteFolder(folders[index]),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _createFolder() async {
    final name = await _askName('新建收藏夹');
    if (!mounted || name == null || name.trim().isEmpty) return;
    setState(() => _creating = true);
    try {
      await widget.repository.createFolder(
        name,
        idempotencyKey:
            'bookmark-folder:${DateTime.now().microsecondsSinceEpoch}',
      );
      if (mounted) _reload();
    } catch (error) {
      if (mounted) _showError(error, '新建收藏夹失败');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _renameFolder(BookmarkFolder folder) async {
    final name = await _askName('重命名收藏夹', initial: folder.name);
    if (!mounted || name == null || name.trim().isEmpty) return;
    try {
      await widget.repository.renameFolder(folder.id, name);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) _showError(error, '重命名失败');
    }
  }

  Future<void> _deleteFolder(BookmarkFolder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除「${folder.name}」？'),
        content: const Text('帖子不会被取消收藏，没有其他归属的内容会回到默认收藏夹。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.deleteFolder(folder.id);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) _showError(error, '删除收藏夹失败');
    }
  }

  Future<void> _reorderFolders(
    List<BookmarkFolder> folders,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex == 0 || oldIndex >= folders.length || oldIndex == newIndex) {
      return;
    }
    if (newIndex > oldIndex) newIndex -= 1;
    final ordered = [...folders];
    final moved = ordered.removeAt(oldIndex);
    ordered.insert(newIndex, moved);
    final rollback = BookmarkFolderPage(
      items: [...folders],
      nextCursor: _page.nextCursor,
      hasMore: _page.hasMore,
    );
    final optimistic = BookmarkFolderPage(
      items: ordered,
      nextCursor: _page.nextCursor,
      hasMore: _page.hasMore,
    );
    setState(() {
      _page = optimistic;
      _future = Future.value(optimistic);
    });
    try {
      // 排序接口按 sort_order 逐项落库，串行提交可避免并发写入互相覆盖。
      for (var index = 0; index < ordered.length; index++) {
        if (ordered[index].isDefault) continue;
        await widget.repository.reorderFolder(ordered[index].id, index);
      }
      if (mounted) await _reload();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _page = rollback;
        _future = Future.value(rollback);
      });
      _showError(error, '收藏夹排序失败，已恢复原顺序');
    }
  }

  Future<String?> _askName(String title, {String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(hintText: '输入收藏夹名称'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  void _showError(Object error, String fallback) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(userFacingApiMessage(error, fallback: fallback))),
    );
  }
}

class BookmarkFolderScreen extends StatefulWidget {
  const BookmarkFolderScreen({
    super.key,
    required this.repository,
    required this.folder,
    required this.onOpenPostId,
  });

  final BookmarkRepository repository;
  final BookmarkFolder folder;
  final ValueChanged<String> onOpenPostId;

  @override
  State<BookmarkFolderScreen> createState() => _BookmarkFolderScreenState();
}

class _BookmarkFolderScreenState extends State<BookmarkFolderScreen> {
  late Future<BookmarkPostPage> _future;
  BookmarkPostPage _page = const BookmarkPostPage(items: []);
  bool _loadingMore = false;
  Object? _loadMoreError;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _future = _loadPage();
  }

  Future<BookmarkPostPage> _loadPage({String? cursor}) async {
    final page = await widget.repository.listFolderPosts(
      widget.folder.id,
      cursor: cursor,
    );
    _page = page;
    return page;
  }

  void _reload() => setState(() {
    _generation += 1;
    _loadingMore = false;
    _loadMoreError = null;
    _future = _loadPage();
  });

  void _loadMorePosts() {
    if (_loadingMore || !_page.hasMore || _page.nextCursor == null) return;
    final cursor = _page.nextCursor!;
    final generation = _generation;
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
      _future = _appendPage(cursor, generation);
    });
  }

  Future<BookmarkPostPage> _appendPage(String cursor, int generation) async {
    try {
      final page = await widget.repository.listFolderPosts(
        widget.folder.id,
        cursor: cursor,
      );
      if (generation != _generation) return _page;
      final seen = _page.items.map((item) => item.id).toSet();
      final merged = BookmarkPostPage(
        items: [
          ..._page.items,
          ...page.items.where((item) => seen.add(item.id)),
        ],
        nextCursor: page.nextCursor,
        hasMore: page.hasMore && page.nextCursor != cursor,
      );
      _page = merged;
      _loadMoreError = null;
      return merged;
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _loadMoreError = error);
      }
      rethrow;
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loadingMore = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.folder.name)),
      body: FutureBuilder<BookmarkPostPage>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done &&
              _page.items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError && _page.items.isEmpty) {
            return _MessageState(
              message: '收藏内容加载失败',
              action: TextButton(onPressed: _reload, child: const Text('重试')),
            );
          }
          final items = snapshot.data?.items ?? _page.items;
          if (items.isEmpty) {
            return const _MessageState(message: '这个收藏夹还没有内容');
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.metrics.extentAfter < 240) {
                  _loadMorePosts();
                }
                return false;
              },
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                itemCount:
                    items.length +
                    (_loadingMore || _loadMoreError != null ? 1 : 0),
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  if (index >= items.length) {
                    return _loadingMore
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : Center(
                            child: TextButton(
                              onPressed: _loadMorePosts,
                              child: const Text('加载失败 · 点击重试'),
                            ),
                          );
                  }
                  final item = items[index];
                  return Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: const CircleAvatar(
                        backgroundColor: AppTheme.surfaceBlue,
                        child: Icon(
                          Icons.article_outlined,
                          color: AppTheme.primary,
                        ),
                      ),
                      title: Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${item.communityName} · ${item.commentCount} 回复',
                      ),
                      onTap: () => widget.onOpenPostId(item.id),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FolderCard extends StatelessWidget {
  const _FolderCard({
    super.key,
    required this.folder,
    required this.onTap,
    this.onRename,
    this.onDelete,
  });

  final BookmarkFolder folder;
  final VoidCallback onTap;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        leading: Icon(
          folder.isDefault
              ? Icons.folder_special_rounded
              : Icons.folder_rounded,
          color: folder.isDefault ? AppTheme.primary : AppTheme.orange,
          size: 30,
        ),
        title: Row(
          children: [
            Flexible(child: Text(folder.name, overflow: TextOverflow.ellipsis)),
            if (folder.isDefault) ...[
              const SizedBox(width: 8),
              const Chip(
                label: Text('默认'),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ],
        ),
        subtitle: Text('${folder.itemCount} 篇内容'),
        trailing: onRename == null && onDelete == null
            ? null
            : PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'rename') onRename?.call();
                  if (value == 'delete') onDelete?.call();
                },
                itemBuilder: (_) => [
                  if (onRename != null)
                    const PopupMenuItem(value: 'rename', child: Text('重命名')),
                  if (onDelete != null)
                    const PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.message, this.action});

  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, style: const TextStyle(color: AppTheme.textSecondary)),
        if (action != null) ...[const SizedBox(height: 12), action!],
      ],
    ),
  );
}
