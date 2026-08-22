import 'package:flutter/material.dart';

import '../data/mock_forum_data.dart';
import '../theme/app_theme.dart';
import 'exchange_store_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.store, required this.onOpenPost, required this.onOpenHome, required this.onOpenComposer, required this.onOpenMessages, required this.onFeedback});

  final ForumStore store;
  final ValueChanged<Post> onOpenPost;
  final VoidCallback onOpenHome;
  final VoidCallback onOpenComposer;
  final VoidCallback onOpenMessages;
  final ValueChanged<String> onFeedback;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => Scaffold(
        body: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            children: [
              _ProfileTopbar(onMessages: onOpenMessages, onSettings: () => _showSettings(context)),
              const SizedBox(height: 18),
              _ProfileHero(),
              const SizedBox(height: 18),
              _StatsStrip(store: store, onTap: (label) => _showList(context, label)),
              const SizedBox(height: 24),
              const Text('常用功能', style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Row(children: [_ProfileTool(icon: Icons.star_rounded, label: '我的收藏', color: AppTheme.orange, onTap: () => _showList(context, '我的收藏')), _ProfileTool(icon: Icons.thumb_up_rounded, label: '我的点赞', color: AppTheme.pink, onTap: () => _showList(context, '我的点赞')), _ProfileTool(icon: Icons.history_rounded, label: '浏览历史', color: AppTheme.primary, onTap: () => _showHistory(context)), _ProfileTool(icon: Icons.mode_comment_outlined, label: '我的评论', color: AppTheme.mint, onTap: () => _showList(context, '我的评论'))]),
              const SizedBox(height: 24),
              _ExchangePreview(store: store, onOpenStore: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ExchangeStoreScreen(store: store))), onRedeem: (product) => _redeem(context, product)),
              const SizedBox(height: 16),
              const Text('最近发布', style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              _RecentPosts(store: store, onOpenPost: onOpenPost),
              const SizedBox(height: 24),
              Text('浅蓝论坛 · 把真实的校园生活留在这里', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: .7), fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (_) => SafeArea(child: Wrap(children: [const ListTile(leading: Icon(Icons.palette_outlined), title: Text('浅蓝主题'), trailing: Icon(Icons.check_rounded, color: AppTheme.primary)), ListTile(leading: const Icon(Icons.shield_outlined), title: const Text('隐私与安全'), onTap: () { Navigator.pop(context); onFeedback('隐私设置已打开'); }), ListTile(leading: const Icon(Icons.info_outline_rounded), title: const Text('关于浅蓝论坛'), onTap: () { Navigator.pop(context); onFeedback('当前版本 v1.0.0'); })])));
  }

  void _showList(BuildContext context, String label) {
    final posts = switch (label) {
      '我的收藏' => store.bookmarkedPosts,
      '我的点赞' => store.likedPosts,
      _ => <Post>[],
    };
    final comments = label == '我的评论' ? store.commentsByAuthor('user-1') : <Comment>[];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: SizedBox(
          height: 460,
          child: Column(
            children: [
              Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
              const SizedBox(height: 12),
              Expanded(
                child: posts.isEmpty && comments.isEmpty
                    ? Center(child: Text('$label暂时为空，去首页逛逛吧', style: const TextStyle(color: AppTheme.textSecondary)))
                    : ListView(
                        children: [
                          ...posts.map((post) => ListTile(leading: const Icon(Icons.article_outlined, color: AppTheme.primary), title: Text(post.title, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text('${post.community?.name ?? post.section.label} · ${post.comments} 回复'), onTap: () { Navigator.pop(context); onOpenPost(post); })),
                          ...comments.map((comment) { final post = store.posts.firstWhere((item) => item.id == comment.postId, orElse: () => store.posts.first); return ListTile(leading: const Icon(Icons.mode_comment_outlined, color: AppTheme.mint), title: Text(comment.content, maxLines: 2, overflow: TextOverflow.ellipsis), subtitle: Text('来自 ${post.title}', maxLines: 1, overflow: TextOverflow.ellipsis), onTap: () { Navigator.pop(context); onOpenPost(post); }); }),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showHistory(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: SizedBox(
          height: 360,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text('浏览历史', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textPrimary))),
              const SizedBox(height: 12),
              Expanded(
                child: store.history.isEmpty
                    ? const Center(child: Text('还没有浏览记录', style: TextStyle(color: AppTheme.textSecondary)))
                    : ListView.builder(
                        itemCount: store.history.length,
                        itemBuilder: (_, index) => ListTile(
                          title: Text(store.history[index].title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(store.history[index].section.label),
                          onTap: () {
                            Navigator.pop(context);
                            onOpenPost(store.history[index]);
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _redeem(BuildContext context, StoreProduct product) {
    final success = store.redeem(product);
    onFeedback(success ? '已兑换${product.name}，请留意领取通知' : '积分不足，再攒一攒就可以兑换啦');
  }
}

class _RecentPosts extends StatelessWidget {
  const _RecentPosts({required this.store, required this.onOpenPost});

  final ForumStore store;
  final ValueChanged<Post> onOpenPost;

  @override
  Widget build(BuildContext context) {
    final posts = store.posts.where((post) => post.authorId == 'user-1').take(3).toList();
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
      child: posts.isEmpty ? const Padding(padding: EdgeInsets.all(18), child: Text('还没有发布内容', style: TextStyle(color: AppTheme.textSecondary))) : Column(children: posts.map((post) => ListTile(title: Text(post.title, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text('${post.community?.name ?? post.section.label} · ${post.comments} 回复 · ${post.views} 浏览'), trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary), onTap: () => onOpenPost(post))).toList()),
    );
  }
}

class _ProfileTopbar extends StatelessWidget {
  const _ProfileTopbar({required this.onMessages, required this.onSettings});

  final VoidCallback onMessages;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => Row(children: [const Expanded(child: Text('我的', style: TextStyle(color: AppTheme.textPrimary, fontSize: 26, fontWeight: FontWeight.w900))), IconButton(onPressed: onMessages, icon: const Icon(Icons.notifications_none_rounded)), IconButton(onPressed: onSettings, icon: const Icon(Icons.settings_outlined))]);
}

class _ProfileHero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(children: [const CircleAvatar(radius: 31, backgroundColor: AppTheme.surfaceBlue, child: Text('理', style: TextStyle(color: AppTheme.primary, fontSize: 23, fontWeight: FontWeight.w900))), const SizedBox(width: 13), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [const Text('小理不理', style: TextStyle(color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.w900)), const SizedBox(width: 6), Container(width: 18, height: 18, decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle), child: const Icon(Icons.check_rounded, color: Colors.white, size: 13))]), const SizedBox(height: 7), const Text('关注 15   粉丝 59   等级 Lv.8', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13))])]);
  }
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.store, required this.onTap});

  final ForumStore store;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final stats = [(store.publishedCount, '我的发帖'), (store.replyCount, '我的回帖'), (store.followedBoards, '关注的吧')];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppTheme.border)),
      child: Row(
        children: stats
            .map(
              (stat) => Expanded(
                child: GestureDetector(
                  onTap: () => onTap(stat.$2),
                  child: Column(
                    children: [
                      Text('${stat.$1}', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 23, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 5),
                      Text(stat.$2, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _ProfileTool extends StatelessWidget {
  const _ProfileTool({required this.icon, required this.label, required this.color, required this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16), child: Column(children: [Container(width: 48, height: 48, decoration: BoxDecoration(color: color.withValues(alpha: .12), shape: BoxShape.circle), child: Icon(icon, color: color)), const SizedBox(height: 8), Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600))])));
}

class _ExchangePreview extends StatelessWidget {
  const _ExchangePreview({required this.store, required this.onOpenStore, required this.onRedeem});

  final ForumStore store;
  final VoidCallback onOpenStore;
  final ValueChanged<StoreProduct> onRedeem;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFE9F5FF), Color(0xFFF8FBFF)]), borderRadius: BorderRadius.circular(22), border: Border.all(color: AppTheme.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('兑换商店', style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)), SizedBox(height: 4), Text('用积分换论坛和校园周边', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12))])), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.stars_rounded, color: AppTheme.orange, size: 18), const SizedBox(width: 4), Text('${store.points}', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w800))]))]), const SizedBox(height: 14), Row(children: storeProducts.take(2).map((product) => Expanded(child: Padding(padding: const EdgeInsets.only(right: 8), child: _ProductMini(product: product, onTap: () => onRedeem(product))))).toList()), const SizedBox(height: 12), SizedBox(width: double.infinity, child: OutlinedButton(onPressed: onOpenStore, child: const Text('查看全部周边')))]),
    );
  }
}

class _ProductMini extends StatelessWidget {
  const _ProductMini({required this.product, required this.onTap});

  final StoreProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(15), child: Ink(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)), child: Row(children: [Container(width: 34, height: 34, alignment: Alignment.center, decoration: BoxDecoration(color: Color(product.color), borderRadius: BorderRadius.circular(10)), child: Text(product.emoji, style: const TextStyle(fontSize: 19))), const SizedBox(width: 8), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 11, fontWeight: FontWeight.w700)), const SizedBox(height: 3), Text('${product.points} 积分', style: const TextStyle(color: AppTheme.orange, fontSize: 10, fontWeight: FontWeight.w700))]))])));
}
