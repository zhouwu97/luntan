import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../app_network_image.dart';

/// 统一用户等级色彩与标签徽章。
class UserLevelBadge extends StatelessWidget {
  const UserLevelBadge({
    super.key,
    required this.level,
    this.fontSize = 8.5,
    this.padding = const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1.5),
  });

  final int level;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  /// 统一的等级主题色彩：Lv.8+ 紫色、Lv.6-7 论坛主色、Lv.4-5 薄荷绿、Lv.1-3 青绿。
  static Color levelColor(int lvl) {
    if (lvl >= 8) return AppTheme.purple;
    if (lvl >= 6) return AppTheme.primary;
    if (lvl >= 4) return AppTheme.mint;
    return const Color(0xFF38AD8B);
  }

  @override
  Widget build(BuildContext context) {
    final color = levelColor(level);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'LV$level',
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
    );
  }
}

/// 统一评论用户头像，优先展示真实网络头像，失败或为空时回退首字。
class CommentAvatar extends StatelessWidget {
  const CommentAvatar({
    super.key,
    required this.name,
    this.avatarUrl,
    this.size = 36,
    this.onTap,
    this.borderColor = const Color(0xFFE2EBF5),
    this.borderWidth = 1.0,
    this.backgroundColor = const Color(0xFFE3EEFF),
    this.fallbackTextColor = AppTheme.primary,
  });

  final String name;
  final String? avatarUrl;
  final double size;
  final VoidCallback? onTap;
  final Color borderColor;
  final double borderWidth;
  final Color backgroundColor;
  final Color fallbackTextColor;

  @override
  Widget build(BuildContext context) {
    final hasUrl = avatarUrl != null && avatarUrl!.trim().isNotEmpty;
    final fallbackChar = name.trim().isNotEmpty ? name.trim().characters.first : '友';

    Widget avatarWidget = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasUrl
          ? AppNetworkImage(
              url: avatarUrl!.trim(),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_) => _buildFallback(fallbackChar),
            )
          : _buildFallback(fallbackChar),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(size / 2),
        child: avatarWidget,
      );
    }
    return avatarWidget;
  }

  Widget _buildFallback(String char) => Center(
    child: Text(
      char,
      style: TextStyle(
        fontSize: size * 0.36,
        fontWeight: FontWeight.w800,
        color: fallbackTextColor,
      ),
    ),
  );
}

/// 统一紧凑型评分胶囊（例如 `♥ 9.0` 或 `♥ 9分`）。
class RatingBadge extends StatelessWidget {
  const RatingBadge(
    this.rating, {
    super.key,
    this.showUnit = true,
  });

  final int? rating;
  final bool showUnit;

  @override
  Widget build(BuildContext context) {
    if (rating == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F4),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.favorite_rounded,
            size: 11,
            color: Color(0xFFF76591),
          ),
          const SizedBox(width: 3),
          Text(
            showUnit ? '$rating分' : '$rating',
            style: const TextStyle(
              color: Color(0xFFF76591),
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// 统一“楼主”专属徽章。
class PostAuthorBadge extends StatelessWidget {
  const PostAuthorBadge({
    super.key,
    this.fontSize = 8.5,
    this.padding = const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1.5),
  });

  final double fontSize;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFFEBF3FE),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: const Color(0xFFCFE2FA),
          width: 0.6,
        ),
      ),
      child: Text(
        '楼主',
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF2672D6),
          height: 1.1,
        ),
      ),
    );
  }
}

/// 统一的内嵌二级回复卡片底板（浅蓝灰背景 #F6F9FC、细边框与柔和圆角 10）。
class ReplyPreviewSurface extends StatelessWidget {
  const ReplyPreviewSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(10, 8, 10, 8),
    this.borderRadius = 10,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final container = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFFF6FAFF),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: const Color(0xFFE4EEF9), width: 0.8),
      ),
      child: child,
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: container,
      );
    }
    return container;
  }
}

/// 统一的楼中楼根评论摘要卡片底板（浅蓝底板 + 柔和细边框 + 12px 圆角）。
class CommentThreadRootCard extends StatelessWidget {
  const CommentThreadRootCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.borderRadius = 12,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF7FBFF), Color(0xFFF3F8FF)],
        ),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: const Color(0xFFDCEAFB),
          width: 1.0,
        ),
      ),
      child: child,
    );
  }
}

/// 统一的评论操作按钮，确保触摸区域至少接近 36~40dp，同时保持精致视觉尺寸。
class CommentActionButton extends StatelessWidget {
  const CommentActionButton({
    super.key,
    required this.icon,
    this.label,
    required this.onTap,
    this.isActive = false,
    this.activeColor = const Color(0xFFF76591),
    this.color = AppTheme.textSecondary,
    this.iconSize = 14,
    this.fontSize = 11.5,
    this.minTouchWidth = 36,
    this.minTouchHeight = 36,
  });

  final IconData icon;
  final String? label;
  final VoidCallback? onTap;
  final bool isActive;
  final Color activeColor;
  final Color color;
  final double iconSize;
  final double fontSize;
  final double minTouchWidth;
  final double minTouchHeight;

  @override
  Widget build(BuildContext context) {
    final currentColor = isActive ? activeColor : color;
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: minTouchWidth,
        minHeight: minTouchHeight,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: iconSize, color: currentColor),
              if (label != null && label!.isNotEmpty) ...[
                const SizedBox(width: 3),
                Text(
                  label!,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: currentColor,
                    height: 1.1,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

