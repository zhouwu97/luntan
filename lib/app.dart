import 'package:flutter/material.dart';

import 'data/mock_forum_data.dart';
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
  int currentTab = 0;

  @override
  void initState() {
    super.initState();
    store = ForumStore.seeded();
  }

  @override
  void dispose() {
    store.dispose();
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
          _showQuickFeedback('投票发布入口已打开，选择项功能已准备好');
        },
        onCreateMarket: () {
          Navigator.of(sheetContext).pop();
          _showPostEditor(isMarket: true);
        },
      ),
    );
  }

  Future<void> _showPostEditor({bool isMarket = false}) async {
    final result = await showDialog<PostDraft>(
      context: context,
      builder: (_) => PostEditorDialog(isMarket: isMarket),
    );
    if (!mounted || result == null) return;
    store.addPost(result);
    setState(() => currentTab = 0);
    _showQuickFeedback('帖子已发布，已加入当前板块');
  }

  void openPost(Post post) {
    store.recordHistory(post);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PostDetailScreen(store: store, post: post),
      ),
    );
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
              onOpenPost: openPost,
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
  const _BottomBar({required this.currentTab, required this.onHome, required this.onProfile, required this.onCreate});

  final int currentTab;
  final VoidCallback onHome;
  final VoidCallback onProfile;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 12,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              Expanded(child: _BottomItem(icon: Icons.home_rounded, label: '首页', active: currentTab == 0, onTap: onHome)),
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
                        decoration: const BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Color(0x355A9EFF), blurRadius: 16, offset: Offset(0, 7))],
                        ),
                        child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(child: _BottomItem(icon: Icons.person_rounded, label: '我的', active: currentTab == 2, onTap: onProfile)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomItem extends StatelessWidget {
  const _BottomItem({required this.icon, required this.label, required this.active, required this.onTap});

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
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
        ],
      ),
    );
  }
}
