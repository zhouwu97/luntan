import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../theme/app_theme.dart';

/// 所有社区评论共用的操作菜单；调用方负责注入各页面实际的读写行为。
Future<void> showCommentActionMenu(
  BuildContext context, {
  required Comment comment,
  required String? currentUserId,
  required bool canModerate,
  required VoidCallback onCopy,
  VoidCallback? onReport,
  VoidCallback? onEdit,
  VoidCallback? onDelete,
}) {
  final isAuthor = currentUserId != null && comment.authorId == currentUserId;
  final canEdit = isAuthor && onEdit != null;
  final canDelete = (isAuthor || canModerate) && onDelete != null;

  return _showCommentActionSheet(
    context,
    (sheetContext) => [
          ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: const Text('复制内容'),
            onTap: () {
              Navigator.pop(sheetContext);
              onCopy();
            },
          ),
          if (onReport != null)
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: AppTheme.orange),
              title: const Text('举报评论'),
              onTap: () {
                Navigator.pop(sheetContext);
                onReport();
              },
            ),
          if (canEdit)
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑评论'),
              onTap: () {
                Navigator.pop(sheetContext);
                onEdit();
              },
            ),
          if (canDelete)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除评论'),
              onTap: () {
                Navigator.pop(sheetContext);
                onDelete();
              },
            ),
    ],
  );
}

/// 榜单评价目前只有复制操作，但必须和普通评论共用同一套安全区处理。
Future<void> showCommentCopyMenu(
  BuildContext context, {
  required VoidCallback onCopied,
}) {
  return _showCommentActionSheet(
    context,
    (sheetContext) => [
      ListTile(
        leading: const Icon(Icons.copy_outlined),
        title: const Text('复制内容'),
        onTap: () {
          Navigator.pop(sheetContext);
          onCopied();
        },
      ),
    ],
  );
}

Future<void> _showCommentActionSheet(
  BuildContext context,
  List<Widget> Function(BuildContext sheetContext) builder,
) {
  final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.white,
    useSafeArea: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(bottom: bottomInset + 8),
      child: Wrap(children: builder(sheetContext)),
    ),
  );
}
