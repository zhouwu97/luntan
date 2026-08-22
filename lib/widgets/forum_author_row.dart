import 'package:flutter/material.dart';

import '../data/mock_forum_data.dart';
import '../theme/app_theme.dart';

class ForumAuthorRow extends StatelessWidget {
  const ForumAuthorRow({super.key, required this.post, required this.onMenu});

  final Post post;
  final VoidCallback onMenu;

  Color get levelColor {
    if (post.level >= 8) return AppTheme.purple;
    if (post.level >= 6) return AppTheme.primary;
    if (post.level >= 4) return AppTheme.mint;
    return AppTheme.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: AppTheme.surfaceBlue,
          child: Text(post.author.characters.first, style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [Flexible(child: Text(post.author, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w800))), const SizedBox(width: 6), _LevelBadge(level: post.level, color: levelColor)]),
              const SizedBox(height: 3),
              Text('${post.section.label} · ${post.time}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            ],
          ),
        ),
        IconButton(onPressed: onMenu, icon: const Icon(Icons.more_horiz_rounded, color: AppTheme.textSecondary)),
      ],
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(6)),
      child: Text('Lv.$level', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
    );
  }
}
