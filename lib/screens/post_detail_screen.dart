import 'package:flutter/material.dart';

import '../controllers/post_detail_controller.dart';
import '../data/mock_forum_data.dart';
import '../theme/app_theme.dart';
import '../widgets/forum_author_row.dart';
import '../widgets/post_media_preview.dart';

class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({
    super.key,
    required this.store,
    required this.controller,
  });

  final ForumStore store;
  final PostDetailController controller;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final replyController = TextEditingController();
  final replies = <String>['这个整理很有用，先收藏了！', '想问下你用的是什么轴体，声音听起来很舒服。'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.load();
    });
  }

  @override
  void dispose() {
    replyController.dispose();
    super.dispose();
  }

  void submitReply() {
    final value = replyController.text.trim();
    if (value.isEmpty) return;
    setState(() {
      replies.insert(0, value);
      replyController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.store, widget.controller]),
      builder: (context, _) {
        final state = widget.controller.state;
        if (state.status == PostDetailStatus.loading ||
            state.status == PostDetailStatus.initial) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (state.status != PostDetailStatus.success || state.detail == null) {
          final message = state.status == PostDetailStatus.notFound
              ? '帖子不存在或已被删除'
              : '帖子加载失败';
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Text(
                message,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          );
        }
        final post = state.detail!.post;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              post.section.label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            actions: [
              IconButton(
                onPressed: () => widget.store.toggleBookmark(post),
                icon: Icon(
                  post.isBookmarked
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  color: AppTheme.primary,
                ),
              ),
              IconButton(
                onPressed: () => ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('分享链接已复制'))),
                icon: const Icon(Icons.share_outlined),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                  children: [
                    ForumAuthorRow(post: post, onMenu: () {}),
                    const SizedBox(height: 22),
                    Wrap(
                      spacing: 7,
                      children: [
                        _Tag(text: post.tag, color: AppTheme.primary),
                        if (post.extraTag != null)
                          _Tag(text: post.extraTag!, color: AppTheme.orange),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      post.title,
                      style: const TextStyle(
                        fontSize: 24,
                        height: 1.3,
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      post.body,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        height: 1.75,
                      ),
                    ),
                    if (post.images.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      PostMediaPreview(images: post.images, onTap: null),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Icon(
                          Icons.visibility_outlined,
                          color: AppTheme.textSecondary,
                          size: 18,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${post.views} 浏览',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 18),
                        const Icon(
                          Icons.chat_bubble_outline_rounded,
                          color: AppTheme.textSecondary,
                          size: 18,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${post.comments} 回复',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 38, color: AppTheme.border),
                    const Text(
                      '全部回复',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...replies.asMap().entries.map(
                      (entry) =>
                          _ReplyItem(index: entry.key, text: entry.value),
                    ),
                  ],
                ),
              ),
              _ReplyBar(controller: replyController, onSubmit: submitReply),
            ],
          ),
        );
      },
    );
  }
}

class _ReplyBar extends StatelessWidget {
  const _ReplyBar({required this.controller, required this.onSubmit});

  final TextEditingController controller;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppTheme.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSubmit(),
                decoration: const InputDecoration(
                  hintText: '友善地回复一句…',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onSubmit,
              style: IconButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.send_rounded, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplyItem extends StatelessWidget {
  const _ReplyItem({required this.index, required this.text});

  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: index.isEven
                ? AppTheme.surfaceBlue
                : const Color(0xFFFFEFF4),
            child: Text(
              index.isEven ? '同' : '友',
              style: TextStyle(
                color: index.isEven ? AppTheme.primary : AppTheme.pink,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      index.isEven ? '路过同学' : '校园友友',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 7),
                    const Text(
                      'Lv.4',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  text,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    height: 1.5,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );
}
