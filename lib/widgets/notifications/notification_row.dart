import 'package:flutter/material.dart';

import '../../data/api/platform_repository.dart';
import '../../domain/models.dart';
import '../../theme/app_theme.dart';

class NotificationRow extends StatelessWidget {
  const NotificationRow({super.key, required this.item, required this.onTap});

  final ForumNotification item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, iconBg, iconColor) = _iconConfig(item);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 分类图标
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),

            // 通知文本主体
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                      height: 1.35,
                    ),
                  ),
                  if (item.content.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      item.content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    relativeTimeLabel(item.createdAt),
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFF9AAABD),
                    ),
                  ),
                ],
              ),
            ),

            // 仅保留精致的 6px 未读小圆点
            if (!item.isRead) ...[
              const SizedBox(width: 8),
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: AppTheme.pink,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  (IconData, Color, Color) _iconConfig(ForumNotification notification) {
    switch (notification.category) {
      case NotificationCategory.interaction:
      case NotificationCategory.reply:
      case NotificationCategory.like:
        if (notification.type.contains('like')) {
          return (
            Icons.favorite_rounded,
            const Color(0xFFFFF0F5),
            AppTheme.pink,
          );
        }
        return (
          Icons.chat_bubble_rounded,
          const Color(0xFFEEF6FF),
          AppTheme.primary,
        );
      case NotificationCategory.community:
        return (
          Icons.notifications_rounded,
          const Color(0xFFEBF8F5),
          AppTheme.mint,
        );
      case NotificationCategory.moderation:
        return (Icons.info_rounded, const Color(0xFFFFF3EA), AppTheme.orange);
      case NotificationCategory.all:
      case NotificationCategory.system:
        return (
          Icons.mail_outline_rounded,
          const Color(0xFFEEF6FF),
          AppTheme.primary,
        );
    }
  }
}
