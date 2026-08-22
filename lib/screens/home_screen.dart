import 'package:flutter/material.dart';

import '../data/mock_forum_data.dart';
import '../theme/app_theme.dart';
import '../widgets/forum_post_card.dart';
import 'feature_page.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store, required this.onOpenPost, required this.onOpenProfile, required this.onOpenComposer, required this.onOpenMessages, required this.onFeedback});

  final ForumStore store;
  final ValueChanged<Post> onOpenPost;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenComposer;
  final VoidCallback onOpenMessages;
  final ValueChanged<String> onFeedback;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ScrollController scrollController;

  @override
  void initState() {
    super.initState();
    scrollController = ScrollController();
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    final count = await widget.store.refresh();
    if (mounted && count > 0) widget.onFeedback('已更新 $count 条内容');
  }

  void openSearch() {
    showSearch<void>(context: context, delegate: _ForumSearchDelegate(store: widget.store, onOpenPost: widget.onOpenPost));
  }

  void openFeature(String title) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FeaturePage(title: title, store: widget.store, onOpenPost: widget.onOpenPost)));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final posts = widget.store.visiblePosts;
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: AppTheme.primary,
              onRefresh: refresh,
              child: CustomScrollView(
                controller: scrollController,
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                slivers: [
                  SliverToBoxAdapter(child: _Header(onProfile: widget.onOpenProfile, onSearch: openSearch, onMessages: widget.onOpenMessages, unread: widget.store.unreadMessages)),
                  SliverToBoxAdapter(child: _SectionTabs(store: widget.store)),
                  SliverToBoxAdapter(child: _FeatureEntries(onTap: openFeature)),
                  SliverToBoxAdapter(
                    child: _FeedToolbar(
                      store: widget.store,
                      onReply: () => widget.onFeedback('回复入口已打开，进入帖子后即可参与讨论'),
                      onPublish: widget.onOpenComposer,
                      onRefresh: refresh,
                    ),
                  ),
                  if (widget.store.isRefreshing)
                    const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2, color: AppTheme.primary, backgroundColor: AppTheme.surfaceBlue))
                  else
                    const SliverToBoxAdapter(child: SizedBox(height: 2)),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 26),
                    sliver: posts.isEmpty
                        ? SliverToBoxAdapter(child: _EmptyFeed(sort: widget.store.selectedSort))
                        : SliverList.builder(
                            itemCount: posts.length,
                            itemBuilder: (context, index) {
                              final post = posts[index];
                              return ForumPostCard(
                                post: post,
                                onOpen: () => widget.onOpenPost(post),
                                onLike: () => widget.store.toggleLike(post),
                                onBookmark: () => widget.store.toggleBookmark(post),
                                onMenu: () => _showPostMenu(post),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showPostMenu(Post post) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(leading: Icon(post.isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: AppTheme.primary), title: Text(post.isBookmarked ? '取消收藏' : '收藏帖子'), onTap: () { widget.store.toggleBookmark(post); Navigator.pop(sheetContext); }),
            ListTile(leading: const Icon(Icons.share_outlined), title: const Text('分享帖子'), onTap: () { Navigator.pop(sheetContext); widget.onFeedback('分享链接已复制'); }),
            ListTile(leading: const Icon(Icons.flag_outlined, color: AppTheme.orange), title: const Text('举报或屏蔽'), onTap: () { Navigator.pop(sheetContext); widget.onFeedback('感谢反馈，我们会尽快处理'); }),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onProfile, required this.onSearch, required this.onMessages, required this.unread});

  final VoidCallback onProfile;
  final VoidCallback onSearch;
  final VoidCallback onMessages;
  final int unread;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Row(
        children: [
          InkResponse(
            onTap: onProfile,
            radius: 26,
            child: const CircleAvatar(radius: 21, backgroundColor: AppTheme.surfaceBlue, child: Text('理', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w800))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: onSearch,
              borderRadius: BorderRadius.circular(18),
              child: Ink(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppTheme.border)),
                child: const Row(children: [Icon(Icons.search_rounded, color: AppTheme.textSecondary, size: 20), SizedBox(width: 8), Text('搜索帖子 / 用户 / 板块', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13))]),
              ),
            ),
          ),
          const SizedBox(width: 7),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(onPressed: onMessages, icon: const Icon(Icons.notifications_none_rounded, color: AppTheme.textPrimary, size: 25), tooltip: '消息'),
              if (unread > 0)
                Positioned(right: 4, top: 4, child: Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: AppTheme.pink, borderRadius: BorderRadius.circular(8)), child: Text(unread > 99 ? '99+' : '$unread', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)))),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTabs extends StatelessWidget {
  const _SectionTabs({required this.store});

  final ForumStore store;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: ForumSection.values.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (_, index) {
          final section = ForumSection.values[index];
          final active = store.selectedSection == section;
          return GestureDetector(
            onTap: () => store.selectSection(section),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: active ? AppTheme.textPrimary : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: active ? AppTheme.textPrimary : AppTheme.border)),
              child: Text(section.label, style: TextStyle(color: active ? Colors.white : AppTheme.textSecondary, fontSize: 14, fontWeight: FontWeight.w800)),
            ),
          );
        },
      ),
    );
  }
}

class _FeatureEntries extends StatelessWidget {
  const _FeatureEntries({required this.onTap});

  final ValueChanged<String> onTap;

  static const entries = [
    ('榜', '排行榜', AppTheme.primary),
    ('热', '热门帖子', AppTheme.orange),
    ('搭', '穿搭分享', AppTheme.pink),
    ('活', '活动', AppTheme.mint),
    ('市', '二手集市', AppTheme.purple),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        scrollDirection: Axis.horizontal,
        itemCount: entries.length,
        separatorBuilder: (context, index) => const SizedBox(width: 20),
        itemBuilder: (_, index) {
          final entry = entries[index];
          return GestureDetector(
            onTap: () => onTap(entry.$2),
            child: SizedBox(
              width: 54,
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: entry.$3.withValues(alpha: .12), shape: BoxShape.circle),
                    child: Center(child: Text(entry.$1, style: TextStyle(color: entry.$3, fontWeight: FontWeight.w900, fontSize: 16))),
                  ),
                  const SizedBox(height: 7),
                  Text(entry.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FeedToolbar extends StatelessWidget {
  const _FeedToolbar({required this.store, required this.onReply, required this.onPublish, required this.onRefresh});

  final ForumStore store;
  final VoidCallback onReply;
  final VoidCallback onPublish;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          ...FeedSort.values.map((sort) => Padding(padding: const EdgeInsets.only(right: 18), child: GestureDetector(onTap: () => store.selectSort(sort), child: _SortItem(label: sort.label, active: store.selectedSort == sort)))),
          const Spacer(),
          _ToolbarButton(label: '回复', icon: Icons.chat_bubble_outline_rounded, onTap: onReply),
          const SizedBox(width: 4),
          _ToolbarButton(label: '发布', icon: Icons.edit_outlined, onTap: onPublish),
          const SizedBox(width: 2),
          IconButton(onPressed: store.isRefreshing ? null : onRefresh, tooltip: '刷新', icon: AnimatedRotation(turns: store.isRefreshing ? .8 : 0, duration: const Duration(milliseconds: 450), child: const Icon(Icons.refresh_rounded, color: AppTheme.primary, size: 22))),
        ],
      ),
    );
  }
}

class _SortItem extends StatelessWidget {
  const _SortItem({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Column(children: [Text(label, style: TextStyle(color: active ? AppTheme.textPrimary : AppTheme.textSecondary, fontSize: 14, fontWeight: active ? FontWeight.w800 : FontWeight.w600)), const SizedBox(height: 5), AnimatedContainer(duration: const Duration(milliseconds: 200), width: active ? 20 : 0, height: 3, decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(3)))]);
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(onPressed: onTap, icon: Icon(icon, size: 15, color: AppTheme.primary), label: Text(label, style: const TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w700)), style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 3)));
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({required this.sort});

  final FeedSort sort;

  @override
  Widget build(BuildContext context) {
    return Container(padding: const EdgeInsets.symmetric(vertical: 70), alignment: Alignment.center, child: Column(children: [const Icon(Icons.auto_awesome_mosaic_outlined, color: AppTheme.primary, size: 44), const SizedBox(height: 12), Text('${sort.label}暂无内容', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700)), const SizedBox(height: 4), const Text('换一个筛选条件看看吧', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13))]));
  }
}

class _ForumSearchDelegate extends SearchDelegate<void> {
  _ForumSearchDelegate({required this.store, required this.onOpenPost});

  final ForumStore store;
  final ValueChanged<Post> onOpenPost;

  @override
  List<Widget>? buildActions(BuildContext context) => [if (query.isNotEmpty) IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear_rounded))];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(onPressed: () => close(context, null), icon: const Icon(Icons.arrow_back_rounded));

  @override
  Widget buildResults(BuildContext context) => _results();

  @override
  Widget buildSuggestions(BuildContext context) => _results();

  Widget _results() {
    final results = store.search(query);
    if (results.isEmpty) return const Center(child: Text('没有找到相关内容', style: TextStyle(color: AppTheme.textSecondary)));
    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: results.length,
      itemBuilder: (context, index) => ForumPostCard(post: results[index], onOpen: () { close(context, null); onOpenPost(results[index]); }, onLike: () => store.toggleLike(results[index]), onBookmark: () => store.toggleBookmark(results[index]), onMenu: () {}),
    );
  }
}
