import 'package:flutter/material.dart';

import '../../data/api/ranking_repository.dart';
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
  final canReport = !isAuthor && onReport != null;

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
      if (canReport)
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
          leading: const Icon(Icons.delete_outline, color: AppTheme.danger),
          title: const Text(
            '删除评论',
            style: TextStyle(color: AppTheme.danger),
          ),
          onTap: () async {
            Navigator.pop(sheetContext);
            final confirmed = await _confirmDelete(
              context,
              title: '删除评论',
              content: '确定要删除这条评论吗？此操作无法撤销。',
            );
            if (confirmed) {
              onDelete();
            }
          },
        ),
    ],
  );
}

/// 榜单评价/回复操作菜单：普通用户仅展示复制等常规操作；管理用户展示置底危险删除。
Future<void> showRankingCommentActionMenu(
  BuildContext context, {
  required RankingToyComment comment,
  required bool canManageRanking,
  required VoidCallback onCopy,
  VoidCallback? onDelete,
  bool isReply = false,
}) {
  final canDelete = canManageRanking && onDelete != null;
  final actionLabel = isReply ? '删除回复' : '删除评价';
  final confirmPrompt = isReply
      ? '确定要删除这条回复吗？此操作无法撤销。'
      : '确定要删除这条评价吗？此操作无法撤销。';

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
      if (canDelete)
        ListTile(
          leading: const Icon(Icons.delete_outline, color: AppTheme.danger),
          title: Text(
            actionLabel,
            style: const TextStyle(color: AppTheme.danger),
          ),
          onTap: () async {
            Navigator.pop(sheetContext);
            final confirmed = await _confirmDelete(
              context,
              title: actionLabel,
              content: confirmPrompt,
            );
            if (confirmed) {
              onDelete();
            }
          },
        ),
    ],
  );
}

/// 榜单评价历史兼容方法，统一走通用底栏安全区逻辑。
@Deprecated('Use showRankingCommentActionMenu instead')
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

Future<bool> _confirmDelete(
  BuildContext context, {
  required String title,
  required String content,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.danger,
          ),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

Future<void> _showCommentActionSheet(
  BuildContext context,
  List<Widget> Function(BuildContext sheetContext) builder,
) {
  // 必须从系统底层 View 获取真实系统避让区，避免嵌套 BottomSheet 路由处理丢失 padding
  final view = View.maybeOf(context);
  final bottomInset = view != null
      ? MediaQueryData.fromView(view).viewPadding.bottom
      : MediaQuery.viewPaddingOf(context).bottom;

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.white,
    useSafeArea: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(bottom: bottomInset + 10),
      child: Wrap(children: builder(sheetContext)),
    ),
  );
}
