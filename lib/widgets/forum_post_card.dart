import 'package:flutter/material.dart';

import '../data/mock_forum_data.dart';
import '../theme/app_theme.dart';
import 'forum_author_row.dart';
import 'post_media_preview.dart';

class ForumPostCard extends StatelessWidget {
  const ForumPostCard({super.key, required this.post, required this.onOpen, required this.onLike, required this.onBookmark, required this.onMenu});

  final Post post;
  final VoidCallback onOpen;
  final VoidCallback onLike;
  final VoidCallback onBookmark;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: AppTheme.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ForumAuthorRow(post: post, onMenu: onMenu),
              const SizedBox(height: 12),
              Wrap(
                spacing: 7,
                runSpacing: 6,
                children: [
                  _Tag(text: post.tag, color: _sectionColor(post.section)),
                  if (post.extraTag != null) _Tag(text: post.extraTag!, color: post.extraTag == '精华' ? AppTheme.orange : AppTheme.primary),
                  if (post.isPinned) const _Tag(text: '置顶', color: AppTheme.pink),
                ],
              ),
              const SizedBox(height: 9),
              Text(post.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, height: 1.32, color: AppTheme.textPrimary, fontWeight: FontWeight.w800)),
              if (post.body.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(post.body, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, height: 1.55, color: AppTheme.textSecondary)),
              ],
              PostMediaPreview(images: post.images, onTap: onOpen),
              const SizedBox(height: 11),
              Row(
                children: [
                  _Stat(icon: Icons.chat_bubble_outline_rounded, text: '${post.comments}'),
                  const SizedBox(width: 16),
                  _Stat(icon: Icons.visibility_outlined, text: post.views),
                  const Spacer(),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: onLike,
                    icon: Icon(post.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 20, color: post.isLiked ? AppTheme.pink : AppTheme.textSecondary),
                    tooltip: '点赞',
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: onBookmark,
                    icon: Icon(post.isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, size: 20, color: post.isBookmarked ? AppTheme.primary : AppTheme.textSecondary),
                    tooltip: '收藏',
                  ),
                  const SizedBox(width: 4),
                  const Text('进入帖子', style: TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w700)),
                  const Icon(Icons.chevron_right_rounded, size: 18, color: AppTheme.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _sectionColor(ForumSection section) => switch (section) {
        ForumSection.unboxing => AppTheme.primary,
        ForumSection.community => AppTheme.mint,
        ForumSection.daily => AppTheme.purple,
      };
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(7)),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 16, color: AppTheme.textSecondary), const SizedBox(width: 4), Text(text, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12))]);
  }
}
