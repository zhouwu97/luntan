import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class MessagesSheet extends StatelessWidget {
  const MessagesSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('消息', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
            const SizedBox(height: 14),
            _MessageRow(icon: Icons.favorite_rounded, color: AppTheme.pink, title: '有人赞了你的帖子', subtitle: '机械键盘开箱！手感绝了 · 3分钟前'),
            _MessageRow(icon: Icons.chat_bubble_rounded, color: AppTheme.primary, title: '你的帖子有了新回复', subtitle: '“校园桌面新搭配” · 18分钟前'),
            _MessageRow(icon: Icons.campaign_rounded, color: AppTheme.orange, title: '社区活动提醒', subtitle: '本周校园周边兑换活动已上线'),
          ],
        ),
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({required this.icon, required this.color, required this.title, required this.subtitle});

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(backgroundColor: color.withValues(alpha: .12), child: Icon(icon, color: color, size: 19)),
      title: Text(title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
    );
  }
}
