import 'package:flutter/material.dart';

import '../data/api/platform_repository.dart';
import '../domain/models.dart';
import '../theme/app_theme.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.repository, required this.onOpenPostId});
  final PlatformRepository repository;
  final ValueChanged<String> onOpenPostId;
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<NotificationPage> future;
  final List<ForumNotification> items = [];

  @override
  void initState() {
    super.initState();
    future = widget.repository.listNotifications();
    widget.repository.markAllNotificationsRead();
  }

  void retry() => setState(() => future = widget.repository.listNotifications());

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('消息', style: TextStyle(fontWeight: FontWeight.w800))),
    body: FutureBuilder<NotificationPage>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('消息加载失败', style: TextStyle(color: AppTheme.textSecondary)), TextButton(onPressed: retry, child: const Text('重试'))]));
        final values = snapshot.data?.items ?? const <ForumNotification>[];
        if (values.isEmpty) return const Center(child: Text('暂时没有新消息', style: TextStyle(color: AppTheme.textSecondary)));
        return ListView.separated(padding: const EdgeInsets.all(AppTheme.pagePadding), itemCount: values.length, separatorBuilder: (_, _) => const Divider(height: 1), itemBuilder: (context, index) {
          final item = values[index];
          return ListTile(contentPadding: const EdgeInsets.symmetric(vertical: 5), leading: CircleAvatar(backgroundColor: AppTheme.surfaceBlue, child: Icon(_icon(item.type), color: AppTheme.primary, size: 20)), title: Text(_title(item), style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(relativeTimeLabel(item.createdAt), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)), trailing: item.isRead ? null : const CircleAvatar(radius: 4, backgroundColor: AppTheme.pink), onTap: () { widget.repository.markNotificationRead(item.id); if (item.targetType == 'post') widget.onOpenPostId(item.targetId); });
        });
      },
    ),
  );

  IconData _icon(String type) => type.contains('like') ? Icons.favorite_rounded : type.contains('follow') ? Icons.person_add_alt_1_rounded : type.contains('comment') || type.contains('reply') ? Icons.chat_bubble_rounded : Icons.campaign_rounded;
  String _title(ForumNotification item) => switch (item.type) { 'post.liked' => '${item.actorName} 赞了你的帖子', 'comment.created' || 'comment.replied' => '${item.actorName} 回复了你', 'user.followed' => '${item.actorName} 关注了你', _ => '你有一条新通知' };
}
