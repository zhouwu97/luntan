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
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.listFolders();
  }

  void _reload() => setState(() => _future = widget.repository.listFolders());

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
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return _MessageState(
              message: '收藏夹加载失败',
              action: TextButton(onPressed: _reload, child: const Text('重试')),
            );
          }
          final folders = snapshot.data!.items;
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
            onRefresh: () async => _reload(),
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              itemCount: folders.length,
              onReorder: (oldIndex, newIndex) =>
                  _reorderFolders(folders, oldIndex, newIndex),
              itemBuilder: (context, index) => _FolderCard(
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
    if (oldIndex == 0 || oldIndex == newIndex) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final ordered = [...folders];
    final moved = ordered.removeAt(oldIndex);
    ordered.insert(newIndex, moved);
    try {
      await Future.wait([
        for (var index = 0; index < ordered.length; index++)
          if (!ordered[index].isDefault)
            widget.repository.reorderFolder(ordered[index].id, index),
      ]);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) _showError(error, '收藏夹排序失败');
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

  @override
  void initState() {
    super.initState();
    _future = widget.repository.listFolderPosts(widget.folder.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.folder.name)),
      body: FutureBuilder<BookmarkPostPage>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return _MessageState(
              message: '收藏内容加载失败',
              action: TextButton(
                onPressed: () => setState(
                  () => _future = widget.repository.listFolderPosts(
                    widget.folder.id,
                  ),
                ),
                child: const Text('重试'),
              ),
            );
          }
          final items = snapshot.data!.items;
          if (items.isEmpty) {
            return const _MessageState(message: '这个收藏夹还没有内容');
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
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
