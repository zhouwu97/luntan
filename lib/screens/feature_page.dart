import 'package:flutter/material.dart';

import '../data/mock_forum_data.dart';
import '../theme/app_theme.dart';
import '../widgets/forum_post_card.dart';

class FeaturePage extends StatelessWidget {
  const FeaturePage({super.key, required this.title, required this.store, required this.onOpenPost});

  final String title;
  final ForumStore store;
  final ValueChanged<Post> onOpenPost;

  List<Post> _posts() {
    if (title == '排行榜') {
      final list = [...store.posts]..sort((a, b) => b.comments.compareTo(a.comments));
      return list.take(6).toList();
    }
    if (title == '热门帖子') {
      final list = [...store.posts]..sort((a, b) => _views(b.views).compareTo(_views(a.views)));
      return list.take(6).toList();
    }
    if (title == '玩法分享') return store.posts.where((post) => post.tag == '玩法分享').toList();
    if (title == '穿搭分享') return store.posts.where((post) => post.tag == '穿搭分享' || post.images.isNotEmpty).take(6).toList();
    return store.posts.where((post) => post.isFeatured).take(6).toList();
  }

  int _views(String value) => int.tryParse(value.replaceAll('k', '000').replaceAll('.', '')) ?? 0;

  @override
  Widget build(BuildContext context) {
    final posts = _posts();
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(gradient: AppTheme.primaryGradient, borderRadius: BorderRadius.circular(22)),
            child: Row(children: [const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 30), const SizedBox(width: 12), Expanded(child: Text(_description(title), style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5, fontWeight: FontWeight.w700)))]),
          ),
          const SizedBox(height: 16),
          if (posts.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 80), child: Center(child: Text('这里还没有内容', style: TextStyle(color: AppTheme.textSecondary))))
          else
            ...posts.map((post) => ForumPostCard(post: post, onOpen: () => onOpenPost(post), onLike: () => store.toggleLike(post), onBookmark: () => store.toggleBookmark(post), onMenu: () {})),
        ],
      ),
    );
  }

  String _description(String title) => switch (title) {
        '排行榜' => '看看最近最受欢迎的帖子，给认真分享的人一点掌声。',
        '热门帖子' => '社区里正在被大家讨论的内容，今天也来逛逛吧。',
        '穿搭分享' => '桌搭、宿舍布置和校园生活灵感，都可以在这里找到。',
        '活动' => '把校园里有趣的活动和新鲜事，集中整理给你。',
        '玩法分享' => '分享游戏、桌游、社团活动和校园玩法，找到一起玩的同学。',
        _ => '社区精华内容，值得慢下来认真读一读。',
      };
}
