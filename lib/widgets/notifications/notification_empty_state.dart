import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class NotificationEmptyState extends StatelessWidget {
  const NotificationEmptyState({
    super.key,
    this.categoryName = '全部',
    this.onResetCategory,
  });

  final String categoryName;
  final VoidCallback? onResetCategory;

  @override
  Widget build(BuildContext context) {
    final title = categoryName == '全部' ? '暂时没有新通知' : '该分类暂无通知';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.surfaceBlue,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.notifications_none_rounded,
                color: Color(0xFF6C91B7),
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              '回复、点赞和社区通知\n都会出现在这里',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
            if (onResetCategory != null && categoryName != '全部') ...[
              const SizedBox(height: 14),
              TextButton(
                onPressed: onResetCategory,
                child: const Text('查看全部通知'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
