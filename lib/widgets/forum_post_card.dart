import 'package:flutter/material.dart';

import '../data/mock_forum_data.dart';
import '../theme/app_theme.dart';
import 'forum_author_row.dart';
import 'post_media_preview.dart';

class ForumPostCard extends StatelessWidget {
  const ForumPostCard({
    super.key,
    required this.post,
    required this.onOpen,
    this.onOpenComments,
    required this.onLike,
    required this.onBookmark,
    required this.onMenu,
    this.contextMeta,
    this.interactionListenable,
  });

  final Post post;
  final VoidCallback onOpen;
  final VoidCallback? onOpenComments;
  final VoidCallback onLike;
  final VoidCallback onBookmark;
  final VoidCallback onMenu;
  final String? contextMeta;
  final Listenable? interactionListenable;

  @override
  Widget build(BuildContext context) {
    final card = _buildCard(context);
    final listenable = interactionListenable;
    if (listenable == null) return card;
    return AnimatedBuilder(
      animation: listenable,
      builder: (context, _) => _buildCard(context),
    );
  }

  Widget _buildCard(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        side: const BorderSide(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ForumAuthorRow(post: post, onMenu: onMenu),
              const SizedBox(height: 10),
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
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.background,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    contextMeta!,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 10.5,
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
                  fontSize: 16,
                  height: 1.35,
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (post.body.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  post.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
              // 图片区域交给整卡 InkWell 处理，避免在卡片内部再嵌套一套手势竞争。
              PostMediaPreview(images: post.images),
              const SizedBox(height: 7),
              Row(
                children: [
                  _ActionStat(
                    icon: Icons.chat_bubble_outline_rounded,
                    text: '${post.comments}',
                    onTap: onOpenComments ?? onOpen,
                  ),
                  const SizedBox(width: 14),
                  _ActionStat(
                    icon: Icons.favorite_border_rounded,
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
                    icon: Icon(
                      post.isBookmarked
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      size: 20,
                      color: post.isBookmarked
                          ? AppTheme.primary
                          : AppTheme.textSecondary,
                    ),
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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(6),
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
        Icon(icon, size: 16, color: AppTheme.textSecondary),
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
  });

  final IconData icon;
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
            Icon(
              icon,
              size: 16,
              color: active ? AppTheme.pink : AppTheme.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              text,
              style: TextStyle(
                color: active ? AppTheme.pink : AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
