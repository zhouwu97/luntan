import 'package:flutter/material.dart';

import 'controllers/feed_controller.dart';
import 'controllers/post_detail_controller.dart';
import 'data/mock_forum_data.dart';
import 'data/repository_provider.dart';
import 'screens/home_screen.dart';
import 'screens/post_detail_screen.dart';
import 'screens/profile_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/composer_sheet.dart';
import 'widgets/messages_sheet.dart';

class LuntanApp extends StatefulWidget {
  const LuntanApp({super.key});

  @override
  State<LuntanApp> createState() => _LuntanAppState();
}

class _LuntanAppState extends State<LuntanApp> {
  late final ForumStore store;
  late final ForumRepositories repositories;
  late final FeedController feedController;
  int currentTab = 0;

  @override
  void initState() {
    super.initState();
    store = ForumStore.seeded();
    repositories = ForumRepositories.fromEnvironment(store: store);
    feedController = FeedController(repository: repositories.feed);
  }

  @override
  void dispose() {
    store.dispose();
    feedController.dispose();
    repositories.close();
    super.dispose();
  }

  void showComposer() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => ComposerSheet(
        onCreatePost: () {
          Navigator.of(sheetContext).pop();
          _showPostEditor();
        },
        onCreatePoll: () {
          Navigator.of(sheetContext).pop();
          _showPostEditor(isPoll: true);
        },
        onCreateGameShare: () {
          Navigator.of(sheetContext).pop();
          _showPostEditor(isGameShare: true);
        },
      ),
    );
  }

  Future<void> _showPostEditor({
    bool isGameShare = false,
    bool isPoll = false,
  }) async {
    final result = await showDialog<PostDraft>(
      context: context,
      builder: (_) =>
          PostEditorDialog(isGameShare: isGameShare, isPoll: isPoll),
    );
    if (!mounted || result == null) return;
    store.addPost(result);
    setState(() => currentTab = 0);
    _showQuickFeedback('帖子已发布，已加入当前板块');
  }

  void openPost(Post post, {bool focusComments = false}) {
    store.recordHistory(post);
    final detailController = PostDetailController(
      repository: repositories.post,
      postId: post.id,
    );
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => PostDetailScreen(
              store: store,
              controller: detailController,
              focusComments: focusComments,
            ),
          ),
        )
        .then((_) => detailController.dispose());
  }

  void _showQuickFeedback(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void showMessages() {
    store.markMessagesRead();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const MessagesSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '浅蓝论坛',
      theme: AppTheme.light,
      home: Scaffold(
        body: IndexedStack(
          index: currentTab == 1 ? 0 : currentTab,
          children: [
            HomeScreen(
              store: store,
              feedController: feedController,
              onOpenPost: openPost,
              onOpenComments: (post) => openPost(post, focusComments: true),
              onOpenProfile: () => setState(() => currentTab = 2),
              onOpenComposer: showComposer,
              onOpenMessages: showMessages,
              onFeedback: _showQuickFeedback,
            ),
            const SizedBox.shrink(),
            ProfileScreen(
              store: store,
              onOpenPost: openPost,
              onOpenHome: () => setState(() => currentTab = 0),
              onOpenComposer: showComposer,
              onOpenMessages: showMessages,
              onFeedback: _showQuickFeedback,
            ),
          ],
        ),
        bottomNavigationBar: _BottomBar(
          currentTab: currentTab,
          onHome: () => setState(() => currentTab = 0),
          onProfile: () => setState(() => currentTab = 2),
          onCreate: showComposer,
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.currentTab,
    required this.onHome,
    required this.onProfile,
    required this.onCreate,
  });

  final int currentTab;
  final VoidCallback onHome;
  final VoidCallback onProfile;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              Expanded(
                child: _BottomItem(
                  icon: Icons.home_rounded,
                  label: '首页',
                  active: currentTab == 0,
                  onTap: onHome,
                ),
              ),
              Expanded(
                child: Center(
                  child: Semantics(
                    button: true,
                    label: '发布',
                    child: InkResponse(
                      onTap: onCreate,
                      radius: 38,
                      child: Ink(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          borderRadius: BorderRadius.all(
                            Radius.circular(AppTheme.publishRadius),
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x355A9EFF),
                              blurRadius: 16,
                              offset: Offset(0, 7),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.add_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _BottomItem(
                  icon: Icons.person_rounded,
                  label: '我的',
                  active: currentTab == 2,
                  onTap: onProfile,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomItem extends StatelessWidget {
  const _BottomItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppTheme.primary : AppTheme.textSecondary;
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
