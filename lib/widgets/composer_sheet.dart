import 'package:flutter/material.dart';

import '../data/mock_forum_data.dart';
import '../theme/app_theme.dart';

class ComposerSheet extends StatelessWidget {
  const ComposerSheet({super.key, required this.onCreatePost, required this.onCreatePoll, required this.onCreateMarket});

  final VoidCallback onCreatePost;
  final VoidCallback onCreatePoll;
  final VoidCallback onCreateMarket;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(4)))),
          const SizedBox(height: 18),
          const Text('发布到论坛', style: TextStyle(color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          const Text('选择一种发布方式，和同学们分享当下想法', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: _PublishOption(icon: Icons.article_rounded, label: '普通帖子', color: AppTheme.primary, onTap: onCreatePost)),
              const SizedBox(width: 10),
              Expanded(child: _PublishOption(icon: Icons.poll_rounded, label: '发起投票', color: AppTheme.mint, onTap: onCreatePoll)),
              const SizedBox(width: 10),
              Expanded(child: _PublishOption(icon: Icons.storefront_rounded, label: '二手闲置', color: AppTheme.orange, onTap: onCreateMarket)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PublishOption extends StatelessWidget {
  const _PublishOption({required this.icon, required this.label, required this.color, required this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 6),
        decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(18)),
        child: Column(children: [Icon(icon, color: color, size: 30), const SizedBox(height: 9), Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700))]),
      ),
    );
  }
}

class PostEditorDialog extends StatefulWidget {
  const PostEditorDialog({super.key, required this.isMarket});

  final bool isMarket;

  @override
  State<PostEditorDialog> createState() => _PostEditorDialogState();
}

class _PostEditorDialogState extends State<PostEditorDialog> {
  final titleController = TextEditingController();
  final bodyController = TextEditingController();
  ForumSection section = ForumSection.unboxing;

  @override
  void dispose() {
    titleController.dispose();
    bodyController.dispose();
    super.dispose();
  }

  void submit() {
    if (titleController.text.trim().isEmpty || bodyController.text.trim().isEmpty) return;
    Navigator.of(context).pop(PostDraft(title: titleController.text.trim(), body: bodyController.text.trim(), section: section, isMarket: widget.isMarket));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isMarket ? '发布二手闲置' : '发布普通帖子'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleController, maxLength: 50, decoration: const InputDecoration(labelText: '标题', hintText: '说说你想分享什么')),
            const SizedBox(height: 12),
            TextField(controller: bodyController, maxLines: 5, maxLength: 500, decoration: const InputDecoration(labelText: '正文', hintText: '写下具体内容、体验或问题')),
            const SizedBox(height: 6),
            DropdownButtonFormField<ForumSection>(
              initialValue: section,
              decoration: const InputDecoration(labelText: '发布板块'),
              items: ForumSection.values.map((item) => DropdownMenuItem(value: item, child: Text(item.label))).toList(),
              onChanged: (value) => setState(() => section = value ?? section),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(onPressed: submit, child: const Text('发布')),
      ],
    );
  }
}
