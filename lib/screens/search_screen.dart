import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/interaction_controller.dart';
import '../data/api/platform_repository.dart';
import '../data/mock_forum_data.dart';
import '../theme/app_theme.dart';
import '../widgets/forum_post_card.dart';

enum SearchKind { all, posts, users, communities }

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.store, this.platform, required this.onOpenPost, required this.onOpenPostId, required this.interactionController});
  final ForumStore store;
  final PlatformRepository? platform;
  final ValueChanged<Post> onOpenPost;
  final ValueChanged<String> onOpenPostId;
  final InteractionController interactionController;
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final queryController = TextEditingController();
  SearchKind kind = SearchKind.all;
  Timer? debounce;
  Future<Map<String, dynamic>?>? future;

  @override
  void dispose() {
    debounce?.cancel();
    queryController.dispose();
    super.dispose();
  }

  void search([String? value]) {
    if (value != null) queryController.text = value;
    debounce?.cancel();
    final query = queryController.text.trim();
    if (query.isEmpty || widget.platform == null) {
      setState(() => future = null);
      return;
    }
    debounce = Timer(const Duration(milliseconds: 260), () {
      if (mounted) setState(() => future = widget.platform!.search(query, type: kind.name));
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = queryController.text.trim();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(controller: queryController, autofocus: true, textInputAction: TextInputAction.search, onChanged: (_) => search(), onSubmitted: (_) => search(), decoration: const InputDecoration(hintText: '搜索帖子 / 用户 / 板块', prefixIcon: Icon(Icons.search_rounded), filled: true, border: InputBorder.none)),
        actions: [if (query.isNotEmpty) IconButton(onPressed: () { queryController.clear(); search(); }, icon: const Icon(Icons.clear_rounded))],
      ),
      body: Column(children: [
        _KindTabs(selected: kind, onChanged: (value) { setState(() => kind = value); search(); }),
        Expanded(child: _body(query)),
      ]),
    );
  }

  Widget _body(String query) {
    if (query.isEmpty) return ListView(padding: const EdgeInsets.all(AppTheme.pagePadding), children: [const _GroupTitle(title: '最近搜索'), Wrap(spacing: 8, runSpacing: 8, children: ['新生攻略', '二手电脑', '食堂', '社团', '考研'].map((item) => ActionChip(label: Text(item), onPressed: () => search(item))).toList()), const SizedBox(height: 24), const _GroupTitle(title: '推荐板块'), ...widget.store.communities.map((community) => ListTile(contentPadding: EdgeInsets.zero, leading: const CircleAvatar(backgroundColor: AppTheme.surfaceBlue, child: Icon(Icons.forum_outlined, color: AppTheme.primary)), title: Text(community.name), subtitle: Text(community.description)))]);
    if (widget.platform == null) return _mockBody(query);
    return FutureBuilder<Map<String, dynamic>?>(future: future, builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('搜索失败', style: TextStyle(color: AppTheme.textSecondary)), TextButton(onPressed: search, child: const Text('重试'))]));
      final data = snapshot.data ?? const <String, dynamic>{};
      final posts = data['posts'] is List ? data['posts'] as List : const [];
      final users = data['users'] is List ? data['users'] as List : const [];
      final communities = data['communities'] is List ? data['communities'] as List : const [];
      if (posts.isEmpty && users.isEmpty && communities.isEmpty) return const Center(child: Text('没有找到相关内容', style: TextStyle(color: AppTheme.textSecondary)));
      return ListView(padding: const EdgeInsets.all(AppTheme.pagePadding), children: [if (posts.isNotEmpty) ...[_GroupTitle(title: '帖子'), ...posts.map((raw) => _ApiPostTile(value: Map<String, dynamic>.from(raw as Map), onTap: widget.onOpenPostId))], if (users.isNotEmpty) ...[_GroupTitle(title: '用户'), ...users.map((raw) => _ApiUserTile(value: Map<String, dynamic>.from(raw as Map)))], if (communities.isNotEmpty) ...[_GroupTitle(title: '板块'), ...communities.map((raw) => _ApiCommunityTile(value: Map<String, dynamic>.from(raw as Map)))] ]);
    });
  }

  Widget _mockBody(String query) {
    final posts = kind == SearchKind.users || kind == SearchKind.communities ? const <Post>[] : widget.store.search(query);
    final users = kind == SearchKind.posts || kind == SearchKind.communities ? const <User>[] : widget.store.searchUsers(query);
    final communities = kind == SearchKind.posts || kind == SearchKind.users ? const <Community>[] : widget.store.searchCommunities(query);
    if (posts.isEmpty && users.isEmpty && communities.isEmpty) return const Center(child: Text('没有找到相关内容', style: TextStyle(color: AppTheme.textSecondary)));
    return ListView(padding: const EdgeInsets.all(AppTheme.pagePadding), children: [if (posts.isNotEmpty) ...[_GroupTitle(title: '帖子'), ...posts.map((post) => ForumPostCard(post: post, onOpen: () => widget.onOpenPost(post), onOpenComments: () => widget.onOpenPost(post), onLike: () => widget.interactionController.togglePostLike(post), onBookmark: () => widget.interactionController.toggleBookmark(post), onMenu: () {}))], if (users.isNotEmpty) ...[_GroupTitle(title: '用户'), ...users.map((user) => ListTile(leading: const CircleAvatar(backgroundColor: AppTheme.surfaceBlue, child: Icon(Icons.person, color: AppTheme.primary)), title: Text(user.nickname), subtitle: Text('Lv.${user.level} · ${user.signature ?? '活跃用户'}')))], if (communities.isNotEmpty) ...[_GroupTitle(title: '板块'), ...communities.map((community) => ListTile(leading: const CircleAvatar(backgroundColor: AppTheme.surfaceBlue, child: Icon(Icons.forum_outlined, color: AppTheme.primary)), title: Text(community.name), subtitle: Text(community.description)))] ]);
  }
}

class _KindTabs extends StatelessWidget {
  const _KindTabs({required this.selected, required this.onChanged});
  final SearchKind selected;
  final ValueChanged<SearchKind> onChanged;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 6, 12, 0), child: Row(children: SearchKind.values.map((value) => Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(switch (value) { SearchKind.all => '综合', SearchKind.posts => '帖子', SearchKind.users => '用户', SearchKind.communities => '板块' }), selected: value == selected, onSelected: (_) => onChanged(value)))).toList()));
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(top: 14, bottom: 8), child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)));
}

class _ApiPostTile extends StatelessWidget {
  const _ApiPostTile({required this.value, required this.onTap});
  final Map<String, dynamic> value;
  final ValueChanged<String> onTap;
  @override
  Widget build(BuildContext context) => ListTile(contentPadding: EdgeInsets.zero, title: Text('${value['title'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text('${value['content_preview'] ?? ''}\n${value['community_name'] ?? ''} · ${value['comment_count'] ?? 0} 回复', maxLines: 2, overflow: TextOverflow.ellipsis), onTap: () => onTap('${value['id'] ?? ''}'));
}

class _ApiUserTile extends StatelessWidget {
  const _ApiUserTile({required this.value});
  final Map<String, dynamic> value;
  @override
  Widget build(BuildContext context) => ListTile(contentPadding: EdgeInsets.zero, leading: const CircleAvatar(backgroundColor: AppTheme.surfaceBlue, child: Icon(Icons.person, color: AppTheme.primary)), title: Text('${value['nickname'] ?? value['username'] ?? ''}'), subtitle: Text('@${value['username'] ?? ''}'));
}

class _ApiCommunityTile extends StatelessWidget {
  const _ApiCommunityTile({required this.value});
  final Map<String, dynamic> value;
  @override
  Widget build(BuildContext context) => ListTile(contentPadding: EdgeInsets.zero, leading: const CircleAvatar(backgroundColor: AppTheme.surfaceBlue, child: Icon(Icons.forum_outlined, color: AppTheme.primary)), title: Text('${value['name'] ?? ''}'), subtitle: Text('${value['description'] ?? ''} · ${value['follower_count'] ?? 0} 关注'));
}
