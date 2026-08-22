// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter/material.dart';

import '../data/mock_forum_data.dart';
import '../theme/app_theme.dart';
import 'post_media_preview.dart';

class ComposerSheet extends StatelessWidget {
  const ComposerSheet({super.key, required this.onCreatePost, required this.onCreatePoll, required this.onCreateGameShare});

  final VoidCallback onCreatePost;
  final VoidCallback onCreatePoll;
  final VoidCallback onCreateGameShare;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(4)))),
        const SizedBox(height: 18),
        const Text('发布到论坛', style: TextStyle(color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 5),
        const Text('选择一种发布方式，进入完整编辑页', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: _PublishOption(icon: Icons.article_rounded, label: '普通帖子', color: AppTheme.primary, onTap: onCreatePost)),
          const SizedBox(width: 10),
          Expanded(child: _PublishOption(icon: Icons.poll_rounded, label: '发起投票', color: AppTheme.mint, onTap: onCreatePoll)),
          const SizedBox(width: 10),
          Expanded(child: _PublishOption(icon: Icons.sports_esports_outlined, label: '玩法分享', color: AppTheme.orange, onTap: onCreateGameShare)),
        ]),
      ]),
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
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: onTap,
    child: Ink(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(16)),
      child: Column(children: [Icon(icon, color: color, size: 30), const SizedBox(height: 8), Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700))]),
    ),
  );
}

class PostEditorDialog extends StatefulWidget {
  const PostEditorDialog({super.key, required this.isGameShare, this.isPoll = false});

  final bool isGameShare;
  final bool isPoll;

  @override
  State<PostEditorDialog> createState() => _PostEditorDialogState();
}

class _PostEditorDialogState extends State<PostEditorDialog> {
  final titleController = TextEditingController();
  final bodyController = TextEditingController();
  ForumSection section = ForumSection.unboxing;
  List<MediaAsset> selectedMedia = const [];
  String? errorText;
  bool submitting = false;

  List<MediaAsset> get sampleMedia => ForumStore.seeded().posts.expand((post) => post.images).take(9).toList();

  @override
  void dispose() {
    titleController.dispose();
    bodyController.dispose();
    super.dispose();
  }

  void submit() {
    if (submitting) return;
    final title = titleController.text.trim();
    final body = bodyController.text.trim();
    if (title.isEmpty) return setState(() => errorText = '请输入标题');
    if (body.isEmpty) return setState(() => errorText = '正文不能为空');
    setState(() => submitting = true);
    Navigator.of(context).pop(PostDraft(title: title, body: body, section: section, isGameShare: widget.isGameShare, isPoll: widget.isPoll, media: selectedMedia));
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isGameShare ? '发布玩法分享' : widget.isPoll ? '发起投票' : '发布普通帖子';
    return Dialog.fullscreen(
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          leading: TextButton(onPressed: submitting ? null : () => Navigator.of(context).pop(), child: const Text('取消')),
          actions: [Padding(padding: const EdgeInsets.only(right: 10), child: FilledButton(onPressed: submitting ? null : submit, style: FilledButton.styleFrom(backgroundColor: AppTheme.primary), child: Text(submitting ? '发布中…' : '发布')))],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(15, 14, 15, 30),
            children: [
              DropdownButtonFormField<ForumSection>(initialValue: section, decoration: const InputDecoration(labelText: '发布板块'), items: ForumSection.values.map((item) => DropdownMenuItem(value: item, child: Text(item.label))).toList(), onChanged: submitting ? null : (value) => setState(() => section = value ?? section)),
              const SizedBox(height: 12),
              TextField(controller: titleController, enabled: !submitting, maxLength: 40, decoration: const InputDecoration(labelText: '标题', hintText: '给帖子起一个清楚的标题')),
              const SizedBox(height: 12),
              TextField(controller: bodyController, enabled: !submitting, maxLength: 2000, minLines: 8, maxLines: 12, decoration: const InputDecoration(labelText: '正文', hintText: '分享你的真实体验、问题或发现…')),
              const SizedBox(height: 12),
              const Text('图片', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Row(children: [
                OutlinedButton.icon(onPressed: submitting ? null : () => setState(() => selectedMedia = [...selectedMedia, ...sampleMedia.take(1)]), icon: const Icon(Icons.add_photo_alternate_outlined), label: const Text('添加示例图')),
                const SizedBox(width: 8),
                Text('${selectedMedia.length} / 9', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              ]),
              if (selectedMedia.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(height: 86, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: selectedMedia.length, separatorBuilder: (_, _) => const SizedBox(width: 8), itemBuilder: (_, index) => Stack(children: [
                  SizedBox(width: 86, height: 86, child: PostMediaPreview(images: [selectedMedia[index]])),
                  Positioned(right: 0, top: 0, child: IconButton(onPressed: submitting ? null : () => setState(() { final copy = [...selectedMedia]..removeAt(index); selectedMedia = copy; }), icon: const Icon(Icons.cancel, color: Colors.white, size: 20))),
                ]))),
              ],
              if (errorText != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(errorText!, style: const TextStyle(color: AppTheme.pink, fontSize: 12))),
            ],
          ),
        ),
      ),
    );
  }
}
