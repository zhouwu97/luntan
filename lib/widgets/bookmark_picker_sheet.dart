import 'package:flutter/material.dart';

import '../data/api/api_client.dart';
import '../data/api/bookmark_repository.dart';
import '../domain/models.dart';
import '../theme/app_theme.dart';

/// 帖子收藏归属选择器。一个帖子可以勾选多个收藏夹，但最终收藏事实仍由
/// 服务端 bookmarks 表统一维护。
class BookmarkPickerSheet extends StatefulWidget {
  const BookmarkPickerSheet({
    super.key,
    required this.post,
    required this.repository,
  });

  final Post post;
  final BookmarkRepository repository;

  @override
  State<BookmarkPickerSheet> createState() => _BookmarkPickerSheetState();
}

class _BookmarkPickerSheetState extends State<BookmarkPickerSheet> {
  late Future<BookmarkSelection> _selectionFuture;
  final Set<String> _selected = <String>{};
  List<BookmarkFolder> _folders = const <BookmarkFolder>[];
  bool _loaded = false;
  bool _saving = false;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _selectionFuture = widget.repository.getPostFolders(widget.post.id);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: FutureBuilder<BookmarkSelection>(
          future: _selectionFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 280,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return SizedBox(
                height: 240,
                child: Center(
                  child: Text(
                    '收藏夹加载失败，请稍后重试',
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
              );
            }
            if (!_loaded) {
              _folders = snapshot.data!.folders;
              _selected
                ..clear()
                ..addAll(snapshot.data!.selectedFolderIds);
              _loaded = true;
            }
            return _content();
          },
        ),
      ),
    );
  }

  Widget _content() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '收藏到收藏夹',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              '${_selected.length} 个收藏夹',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_folders.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Center(child: Text('还没有收藏夹')),
          )
        else
          ..._folders.map(
            (folder) => CheckboxListTile(
              value: _selected.contains(folder.id),
              onChanged: _saving
                  ? null
                  : (value) => setState(() {
                      if (value == true) {
                        _selected.add(folder.id);
                      } else {
                        _selected.remove(folder.id);
                      }
                    }),
              contentPadding: EdgeInsets.zero,
              secondary: Icon(
                folder.isDefault
                    ? Icons.folder_special_rounded
                    : Icons.folder_outlined,
                color: folder.isDefault ? AppTheme.primary : AppTheme.orange,
              ),
              title: Text(folder.name),
              subtitle: Text(
                '${folder.itemCount} 篇内容${folder.isDefault ? ' · 默认' : ''}',
              ),
              controlAffinity: ListTileControlAffinity.trailing,
            ),
          ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: _creating || _saving ? null : _createFolder,
          icon: _creating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_rounded),
          label: const Text('新建收藏夹'),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : '完成'),
          ),
        ),
      ],
    );
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建收藏夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(hintText: '例如：开学攻略'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || name == null || name.trim().isEmpty) return;
    setState(() => _creating = true);
    try {
      final folder = await widget.repository.createFolder(
        name,
        idempotencyKey:
            'bookmark-folder:${DateTime.now().microsecondsSinceEpoch}',
      );
      if (!mounted) return;
      setState(() {
        _folders = [..._folders, folder];
        _selected.add(folder.id);
        _creating = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userFacingApiMessage(error, fallback: '新建收藏夹失败')),
        ),
      );
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final result = await widget.repository.setPostFolders(
        widget.post.id,
        _selected.toList(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(result.selectedFolderIds.isNotEmpty);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userFacingApiMessage(error, fallback: '收藏保存失败')),
        ),
      );
    }
  }
}
