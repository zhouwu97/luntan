import 'package:flutter/material.dart';

import '../data/mock_forum_data.dart';
import '../theme/app_theme.dart';
import 'app_network_image.dart';

class ForumAuthorRow extends StatelessWidget {
  const ForumAuthorRow({
    super.key,
    required this.post,
    this.onMenu,
    this.onAuthorTap,
    this.avatarRadius = 19.0,
    this.showCommunity = true,
  });

  final Post post;
  final VoidCallback? onMenu;
  final void Function(String userId)? onAuthorTap;
  final double avatarRadius;
  final bool showCommunity;

  Color get levelColor {
    if (post.level >= 8) return AppTheme.purple;
    if (post.level >= 6) return AppTheme.primary;
    if (post.level >= 4) return AppTheme.mint;
    return AppTheme.textSecondary;
  }

  String get communityLabel {
    final name = post.community?.name.trim();
    return name == null || name.isEmpty ? post.section.label : name;
  }

  @override
  Widget build(BuildContext context) {
    var avatarUrl = post.author?.avatar?.trim();
    if (avatarUrl == null || avatarUrl.isEmpty) {
      avatarUrl = UserAvatarCache.get(post.authorId);
    } else {
      UserAvatarCache.set(post.authorId, avatarUrl);
    }
    final nickname = post.author?.nickname.trim();
    final initialChar = (nickname != null && nickname.isNotEmpty)
        ? nickname.characters.first
        : (post.authorId.startsWith('guest') ? '游' : '匿');
    final displayName = (nickname != null && nickname.isNotEmpty)
        ? nickname
        : (post.authorId.startsWith('guest') ? '游客' : '匿名用户');

    final metaText = showCommunity
        ? '$communityLabel · ${post.time}'
        : post.time;

    final authorTapHandler = onAuthorTap == null
        ? null
        : () {
            if (post.authorId.isNotEmpty && !post.authorId.startsWith('guest')) {
              onAuthorTap!(post.authorId);
            }
          };

    return Row(
      children: [
        GestureDetector(
          onTap: authorTapHandler,
          child: _buildAvatar(context, avatarUrl, initialChar),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: authorTapHandler,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        displayName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _LevelBadge(level: post.level, color: levelColor),
                  ],
                ),
                const SizedBox(height: 2.5),
                Text(
                  metaText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (onMenu != null)
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: onMenu,
            icon: const Icon(
              Icons.more_horiz_rounded,
              color: AppTheme.textSecondary,
              size: 20,
            ),
          ),
      ],
    );
  }

  Widget _buildAvatar(
    BuildContext context,
    String? avatarUrl,
    String initialChar,
  ) {
    final diameter = avatarRadius * 2;
    final placeholder = Container(
      width: diameter,
      height: diameter,
      decoration: const BoxDecoration(
        color: AppTheme.surfaceBlue,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initialChar,
        style: TextStyle(
          color: AppTheme.primary,
          fontSize: avatarRadius * 0.72,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    if (avatarUrl == null || avatarUrl.isEmpty) {
      return placeholder;
    }

    return ClipOval(
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: AppNetworkImage(
          url: avatarUrl,
          fit: BoxFit.cover,
          width: diameter,
          height: diameter,
          placeholder: (_) => placeholder,
          errorBuilder: (_) => placeholder,
        ),
      ),
    );
  }
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level, required this.color});

  final int level;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        'Lv.$level',
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          height: 1.15,
        ),
      ),
    );
  }
}

