import 'package:flutter/material.dart';

import '../data/mock_forum_data.dart';
import '../theme/app_theme.dart';
import 'forum_author_row.dart';
import 'motion_tap_icon.dart';
import 'post_media_preview.dart';

class ForumPostCard extends StatelessWidget {
  const ForumPostCard({
    super.key,
    required this.post,
    required this.onOpen,
    this.onOpenComments,
    required this.onLike,
    required this.onBookmark,
    this.onMenu,
    this.onAuthorTap,
    this.contextMeta,
    this.interactionListenable,
  });

  final Post post;
  final VoidCallback onOpen;
  final VoidCallback? onOpenComments;
  final VoidCallback onLike;
  final VoidCallback onBookmark;
  final VoidCallback? onMenu;
  final void Function(String userId)? onAuthorTap;
  final String? contextMeta;
  final Listenable? interactionListenable;

  @override
  Widget build(BuildContext context) {
    final card = _buildContent(context);
    final listenable = interactionListenable;
    if (listenable == null) return card;
    return AnimatedBuilder(
      animation: listenable,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    // 0 评论依然允许点击进入详情并开始第一条评论
    final openComments = onOpenComments ?? onOpen;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEDF2F7), width: 0.8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ForumAuthorRow(
                  post: post,
                  onMenu: onMenu,
                  onAuthorTap: onAuthorTap,
                ),
                const SizedBox(height: 9),
                if (post.isPinned ||
                    post.isFeatured ||
                    post.extraTag == '精华') ...[
                  _Tag(
                    text: post.isPinned ? '置顶' : '精华',
                    color: post.isPinned ? AppTheme.pink : AppTheme.orange,
                  ),
                  const SizedBox(height: 6),
                ],
                if (contextMeta != null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.background,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      contextMeta!,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
                Text(
                  post.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16.5,
                    height: 1.36,
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
                if (post.body.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    post.body,
                    maxLines: post.images.isEmpty ? 5 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.58,
                      color: Color(0xFF334B60),
                    ),
                  ),
                ],
                if (post.images.isNotEmpty) ...[
                  PostMediaPreview(
                    images: post.images,
                    onTap: onOpen,
                    onImageTap: (_) => onOpen(),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    _ActionStat(
                      icon: Icons.chat_bubble_outline_rounded,
                      text: '${post.comments}',
                      onTap: openComments,
                    ),
                    const SizedBox(width: 14),
                    _ActionStat(
                      icon: Icons.favorite_border_rounded,
                      activeIcon: Icons.favorite_rounded,
                      text: '${post.likeCount}',
                      onTap: onLike,
                      active: post.isLiked,
                    ),
                    const SizedBox(width: 14),
                    _Stat(icon: Icons.visibility_outlined, text: post.views),
                    const Spacer(),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: onBookmark,
                      icon: MotionTapIcon(
                        active: post.isBookmarked,
                        activeIcon: Icons.bookmark_rounded,
                        inactiveIcon: Icons.bookmark_border_rounded,
                        activeColor: AppTheme.primary,
                        inactiveColor: AppTheme.textSecondary,
                      ),
                      tooltip: '收藏帖子',
                    ),
                  ],
                ),
              ],
            ),
          ),
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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          height: 1.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppTheme.textSecondary),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}

class _ActionStat extends StatelessWidget {
  const _ActionStat({
    required this.icon,
    required this.text,
    required this.onTap,
    this.active = false,
    this.activeIcon,
  });

  final IconData icon;
  final IconData? activeIcon;
  final String text;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: AppTheme.minTapTarget,
        minWidth: AppTheme.minTapTarget,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MotionTapIcon(
              active: active,
              activeIcon: activeIcon ?? icon,
              inactiveIcon: icon,
              activeColor: AppTheme.pink,
              inactiveColor: AppTheme.textSecondary,
              size: 15,
            ),
            const SizedBox(width: 4),
            Text(
              text,
              style: TextStyle(
                color: active ? AppTheme.pink : AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: active ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

