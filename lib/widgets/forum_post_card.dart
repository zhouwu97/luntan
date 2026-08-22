import 'package:flutter/material.dart';

import '../data/mock_forum_data.dart';
import '../theme/app_theme.dart';
import 'forum_author_row.dart';
import 'post_media_preview.dart';

class ForumPostCard extends StatelessWidget {
  const ForumPostCard({super.key, required this.post, required this.onOpen, this.onOpenComments, required this.onLike, required this.onBookmark, required this.onMenu});

  final Post post;
  final VoidCallback onOpen;
  final VoidCallback? onOpenComments;
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
              if (post.isPinned || post.isFeatured || post.extraTag == '精华') ...[
                _Tag(text: post.isPinned ? '置顶' : '精华', color: post.isPinned ? AppTheme.pink : AppTheme.orange),
                const SizedBox(height: 7),
              ],
              Text(post.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, height: 1.32, color: AppTheme.textPrimary, fontWeight: FontWeight.w800)),
              if (post.body.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(post.body, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, height: 1.55, color: AppTheme.textSecondary)),
              ],
              PostMediaPreview(images: post.images, onTap: onOpen),
              const SizedBox(height: 11),
              Row(
                children: [
                  _ActionStat(icon: Icons.chat_bubble_outline_rounded, text: '${post.comments}', onTap: onOpenComments ?? onOpen),
                  const SizedBox(width: 14),
                  _ActionStat(icon: Icons.favorite_border_rounded, text: '${post.likeCount}', onTap: onLike, active: post.isLiked),
                  const SizedBox(width: 14),
                  _Stat(icon: Icons.visibility_outlined, text: post.views),
                  const Spacer(),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: onBookmark,
                    icon: Icon(post.isBookmarked ? Icons.star_rounded : Icons.star_border_rounded, size: 20, color: post.isBookmarked ? AppTheme.orange : AppTheme.textSecondary),
                    tooltip: '收藏帖子',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

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

class _ActionStat extends StatelessWidget {
  const _ActionStat({required this.icon, required this.text, required this.onTap, this.active = false});

  final IconData icon;
  final String text;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 16, color: active ? AppTheme.pink : AppTheme.textSecondary), const SizedBox(width: 4), Text(text, style: TextStyle(color: active ? AppTheme.pink : AppTheme.textSecondary, fontSize: 12))]),
    ),
  );
}
