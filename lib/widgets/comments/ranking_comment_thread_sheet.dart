import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/api/api_client.dart'
    show ApiException, userFacingApiMessage;
import '../../data/api/ranking_repository.dart';
import '../../domain/models.dart' show relativeTimeLabel;
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import '../app_network_image.dart';
import '../link_text.dart';
import 'comment_action_menu.dart';
import 'comment_common_widgets.dart';
import 'comment_image_viewer.dart';
import 'comment_more_button.dart';
import 'comment_skeleton.dart';

enum _ReplyLoadState { loading, loadedEmpty, loaded, error }

/// 未登录（401）时引导登录，而不是按创建时的登录快照拦截写操作。
bool _isUnauthorizedReply(Object error) =>
    error is ApiException && error.statusCode == 401;

/// 榜单评论楼中楼。
///
/// 服务端按 root_id 返回整座楼的扁平回复，UI 不再递归嵌套，因而可以稳定
/// 展示回复二级评论、三级评论以及分页返回的后续回复。
class RankingCommentThreadSheet extends StatefulWidget {
  const RankingCommentThreadSheet({
    super.key,
    required this.rootComment,
    required this.repository,
    required this.onReply,
    this.onToggleLike,
    this.isAuthenticated = true,
    this.canComment = true,
    this.canLike = true,
    this.canManageRanking = false,
    this.onRequireAuth,
    this.blockedMessage = '当前身份暂不能评论，请登录邮箱账号后重试',
    this.focusReplyId,
    this.onAuthorTap,
    this.onChanged,
    this.isBottomSheet = true,
  });

  final RankingToyComment rootComment;
  final RankingRepository repository;
  final String? focusReplyId;
  final Future<RankingToyComment> Function(
    RankingToyComment target,
    String content,
  )
  onReply;
  final Future<int> Function(RankingToyComment comment, bool active)?
  onToggleLike;
  final bool isAuthenticated;
  final bool canComment;
  final bool canLike;
  final bool canManageRanking;
  final VoidCallback? onRequireAuth;
  final String blockedMessage;
  final ValueChanged<String>? onAuthorTap;
  // 写操作成功后立即通知父页面；弹层可通过任意系统路径关闭。
  final VoidCallback? onChanged;
  final bool isBottomSheet;

  @override
  State<RankingCommentThreadSheet> createState() =>
      _RankingCommentThreadSheetState();
}

class _RankingCommentThreadSheetState extends State<RankingCommentThreadSheet> {
  final replies = <RankingToyComment>[];
  final scrollController = ScrollController();
  final inputController = TextEditingController();
  late int _replyCount = widget.rootComment.replyCount;
  RankingToyComment? replyTarget;
  String? nextCursor;
  String? errorMessage;
  String? loadMoreError;
  bool loading = false;
  bool loadingMore = false;
  bool sending = false;
  bool hasMore = true;
  _ReplyLoadState loadState = _ReplyLoadState.loading;
  bool _hasFocusedTarget = false;
  String? highlightedReplyId;
  Timer? _highlightTimer;

  @override
  void initState() {
    super.initState();
    // 榜单详情已返回的回复预览先行展示，完整回复列表后台合并。
    replies.addAll(widget.rootComment.replyPreview);
    scrollController.addListener(_onScroll);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    scrollController
      ..removeListener(_onScroll)
      ..dispose();
    inputController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (scrollController.hasClients &&
        scrollController.position.extentAfter < 200) {
      _loadMore();
    }
  }

  Future<void> _loadFirstPage() async {
    if (loading) return;
    final preview = List<RankingToyComment>.from(replies);
    setState(() {
      loading = true;
      loadState = preview.isEmpty
          ? _ReplyLoadState.loading
          : _ReplyLoadState.loaded;
      errorMessage = null;
      loadMoreError = null;
      replies
        ..clear()
        ..addAll(preview);
      nextCursor = null;
      hasMore = true;
    });
    try {
      final page = await widget.repository.listReplies(
        commentId: widget.rootComment.id,
      );
      if (!mounted) return;
      setState(() {
        final ids = replies.map((item) => item.id).toSet();
        for (final item in page.items) {
          if (ids.add(item.id)) replies.add(item);
        }
        nextCursor = page.nextCursor;
        hasMore = page.hasMore && page.nextCursor != null;
        loading = false;
        loadState = replies.isEmpty
            ? _ReplyLoadState.loadedEmpty
            : _ReplyLoadState.loaded;
      });
      _checkAndFocusTarget();
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          'Ranking replies request failed: '
          'GET /api/v1/ranking/toy-comments/${widget.rootComment.id}/replies; $error',
        );
      }
      if (!mounted) return;
      setState(() {
        errorMessage = '回复加载失败，请重试';
        loading = false;
        loadState = _ReplyLoadState.error;
      });
    }
  }

  Future<void> _loadMore() async {
    if (loading || loadingMore || !hasMore || nextCursor == null) return;
    final cursor = nextCursor!;
    setState(() => loadingMore = true);
    try {
      final page = await widget.repository.listReplies(
        commentId: widget.rootComment.id,
        cursor: cursor,
      );
      if (!mounted) return;
      setState(() {
        final ids = replies.map((item) => item.id).toSet();
        for (final item in page.items) {
          if (ids.add(item.id)) replies.add(item);
        }
        nextCursor = page.nextCursor;
        hasMore = page.hasMore && page.nextCursor != cursor;
        loadingMore = false;
        loadMoreError = null;
      });
      _checkAndFocusTarget();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loadingMore = false;
        loadMoreError = '加载更多失败，点击重试';
      });
    }
  }

  final _replyKeys = <String, GlobalKey>{};
  GlobalKey _getKey(String id) => _replyKeys.putIfAbsent(id, () => GlobalKey());

  void _checkAndFocusTarget() {
    if (_hasFocusedTarget || widget.focusReplyId == null) return;
    final index = replies.indexWhere((r) => r.id == widget.focusReplyId);
    if (index == -1) return;

    _hasFocusedTarget = true;
    setState(() => highlightedReplyId = widget.focusReplyId);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _getKey(widget.focusReplyId!).currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: AppMotion.normal,
          curve: AppMotion.standard,
          alignment: 0.3,
        );
      }
      _highlightTimer?.cancel();
      _highlightTimer = Timer(AppMotion.highlightFade, () {
        if (mounted) setState(() => highlightedReplyId = null);
      });
    });
  }

  Future<void> _sendReply() async {
    final content = inputController.text.trim();
    if (content.isEmpty || sending) return;
    // 登录态可能在弹层创建后才建立，直接尝试服务器，401 时再引导登录。
    final target = replyTarget ?? widget.rootComment;
    setState(() => sending = true);
    try {
      final comment = await widget.onReply(target, content);
      if (!mounted) return;
      setState(() {
        inputController.clear();
        replyTarget = null;
        if (!replies.any((item) => item.id == comment.id)) {
          replies.add(comment);
          _replyCount++;
        }
        widget.onChanged?.call();
        loadState = _ReplyLoadState.loaded;
        sending = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scrollController.hasClients) {
          scrollController.animateTo(
            scrollController.position.maxScrollExtent + 90,
            duration: AppMotion.normal,
            curve: AppMotion.standard,
          );
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => sending = false);
      if (_isUnauthorizedReply(error)) {
        widget.onRequireAuth?.call();
        return;
      }
      _showMessage('回复失败，请重试');
    }
  }

  void _showRootMenu() {
    showRankingCommentActionMenu(
      context,
      comment: widget.rootComment,
      canManageRanking: widget.canManageRanking,
      isReply: false,
      onCopy: () {
        Clipboard.setData(ClipboardData(text: widget.rootComment.content));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
      },
      onDelete: _deleteRootComment,
    );
  }

  Future<void> _deleteRootComment() async {
    try {
      await widget.repository.deleteComment(widget.rootComment.id);
      if (!mounted) return;
      widget.onChanged?.call();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('评价已删除')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userFacingApiMessage(error, fallback: '删除评价失败，请重试'),
            ),
          ),
        );
      }
    }
  }

  void _showReplyMenu(RankingToyComment reply) {
    showRankingCommentActionMenu(
      context,
      comment: reply,
      canManageRanking: widget.canManageRanking,
      isReply: true,
      onCopy: () {
        Clipboard.setData(ClipboardData(text: reply.content));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
      },
      onDelete: () => _deleteReply(reply),
    );
  }

  Future<void> _deleteReply(RankingToyComment reply) async {
    try {
      await widget.repository.deleteComment(reply.id);
      if (!mounted) return;
      setState(() {
        replies.removeWhere((item) => item.id == reply.id);
        _replyCount = (_replyCount - 1).clamp(0, 1 << 30);
        if (replies.isEmpty) {
          loadState = _ReplyLoadState.loadedEmpty;
        }
      });
      widget.onChanged?.call();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('回复已删除')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userFacingApiMessage(error, fallback: '删除回复失败，请重试'),
            ),
          ),
        );
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _name(RankingToyComment comment) =>
      comment.nickname.isEmpty ? comment.username : comment.nickname;

  String? _replyToName(RankingToyComment comment) {
    final targetId = comment.replyToUserId;
    if (targetId == null) return null;
    if (targetId == widget.rootComment.authorId) {
      return _name(widget.rootComment);
    }
    for (final item in replies) {
      if (item.authorId == targetId) return _name(item);
    }
    return comment.replyToUserNickname ?? '用户';
  }

  @override
  Widget build(BuildContext context) {
    final rootName = _name(widget.rootComment);

    final scaffold = Scaffold(
      backgroundColor: Colors.white,
      appBar: widget.isBottomSheet
          ? null
          : AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              scrolledUnderElevation: 0.5,
              leading: IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 18,
                  color: AppTheme.textPrimary,
                ),
                tooltip: '返回',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              title: Text(
                _replyTitle(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              centerTitle: true,
              actions: [
                IconButton(
                  icon: const Icon(
                    Icons.more_horiz_rounded,
                    size: 20,
                    color: Color(0xFF64748B),
                  ),
                  tooltip: '更多',
                  onPressed: _showRootMenu,
                ),
              ],
              bottom: const PreferredSize(
                preferredSize: Size.fromHeight(1),
                child: Divider(height: 1, color: Color(0xFFEDF2F7)),
              ),
            ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (widget.isBottomSheet) ...[
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(top: 8, bottom: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD0D7DE),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              SizedBox(
                height: 44,
                child: Stack(
                  children: [
                    Center(
                      child: Text(
                        _replyTitle(),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 4,
                      top: 0,
                      bottom: 0,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.more_horiz_rounded,
                              size: 20,
                              color: Color(0xFF64748B),
                            ),
                            tooltip: '更多',
                            onPressed: _showRootMenu,
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              size: 22,
                              color: Color(0xFF64748B),
                            ),
                            tooltip: '关闭',
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFEDF2F7)),
            ],
              Expanded(
                child: CustomScrollView(
                  controller: scrollController,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                        child: CommentThreadRootCard(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CommentAvatar(
                                name: rootName,
                                avatarUrl: widget.rootComment.avatarUrl,
                                size: 34,
                                onTap: () {
                                  if (widget.rootComment.authorId.isNotEmpty &&
                                      !widget.rootComment.authorId.startsWith('guest')) {
                                    widget.onAuthorTap?.call(widget.rootComment.authorId);
                                  }
                                },
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        InkWell(
                                          onTap: () {
                                            if (widget.rootComment.authorId.isNotEmpty &&
                                                !widget.rootComment.authorId.startsWith('guest')) {
                                              widget.onAuthorTap?.call(widget.rootComment.authorId);
                                            }
                                          },
                                          borderRadius: BorderRadius.circular(4),
                                          child: Text(
                                            rootName,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: AppTheme.textPrimary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        UserLevelBadge(
                                          level: widget.rootComment.level,
                                          fontSize: 8.5,
                                        ),
                                         const Spacer(),
                                         RatingBadge(widget.rootComment.authorRating),
                                         const SizedBox(width: 4),
                                         CommentMoreButton(
                                           onPressed: _showRootMenu,
                                         ),
                                       ],
                                     ),
                                    const SizedBox(height: 2),
                                    Text(
                                      relativeTimeLabel(widget.rootComment.createdAt),
                                      style: const TextStyle(
                                        fontSize: 9.5,
                                        color: Color(0xFF9AA9B8),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    LinkText(
                                      widget.rootComment.content,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        color: Color(0xFF243647),
                                        height: 1.5,
                                      ),
                                    ),
                                    _buildMedia(widget.rootComment.media),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Row(
                          children: [
                            Text(
                              '全部回复',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    _buildReplySlivers(),
                  ],
                ),
              ),
              _buildReplyBar(),
            ],
          ),
        ),
      );
    if (!widget.isBottomSheet) return scaffold;
    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.82,
        child: scaffold,
      ),
    );
  }

  Widget _buildReplySlivers() {
    if (loadState == _ReplyLoadState.loading && replies.isEmpty) {
      return const SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        sliver: SliverToBoxAdapter(child: CommentSkeleton(itemCount: 3)),
      );
    }
    if (loadState == _ReplyLoadState.error && replies.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: TextButton(
              onPressed: _loadFirstPage,
              child: Text(errorMessage!),
            ),
          ),
        ),
      );
    }
    if (replies.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: Text(
              '暂无二级回复，来发第一条吧',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
          ),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      sliver: SliverList.builder(
        itemCount: replies.length + 1,
        itemBuilder: (context, index) {
          if (index == replies.length) {
            if (loadingMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            if (loadMoreError != null) {
              return TextButton(
                onPressed: _loadMore,
                child: Text(loadMoreError!),
              );
            }
            return const SizedBox(height: 16);
          }
          final isLast = index == replies.length - 1;
          return _buildReplyItem(replies[index], isLast: isLast);
        },
      ),
    );
  }

  String _replyTitle() => switch (loadState) {
    _ReplyLoadState.loading || _ReplyLoadState.error => '回复',
    _ReplyLoadState.loadedEmpty => '0 条回复',
    _ReplyLoadState.loaded => '$_replyCount 条回复',
  };

  Widget _buildReplyItem(RankingToyComment reply, {bool isLast = false}) {
    final name = _name(reply);
    final replyTo = _replyToName(reply);
    final isLiked = reply.isLiked;
    final isHighlighted = highlightedReplyId == reply.id;

    return AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.standard,
      key: _getKey(reply.id),
      decoration: BoxDecoration(
        color: isHighlighted ? const Color(0xFFEDF6FF) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              CommentAvatar(
                name: name,
                avatarUrl: reply.avatarUrl,
                size: 32,
                onTap: () {
                  if (reply.authorId.isNotEmpty &&
                      !reply.authorId.startsWith('guest')) {
                    widget.onAuthorTap?.call(reply.authorId);
                  }
                },
              ),
              if (!isLast)
                Container(
                  width: 1.0,
                  height: 24,
                  margin: const EdgeInsets.only(top: 4),
                  color: const Color(0xFFE4EBF2),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    InkWell(
                      onTap: () {
                        if (reply.authorId.isNotEmpty &&
                            !reply.authorId.startsWith('guest')) {
                          widget.onAuthorTap?.call(reply.authorId);
                        }
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    UserLevelBadge(level: reply.level, fontSize: 8.5),
                    const Spacer(),
                    Text(
                      relativeTimeLabel(reply.createdAt),
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: Color(0xFF9AA9B8),
                      ),
                    ),
                  ],
                ),
                if (replyTo != null) ...[
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF7990A5),
                      ),
                      children: [
                        const TextSpan(text: '回复 '),
                        TextSpan(
                          text: '@$replyTo',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                LinkText(
                  reply.content,
                  selectable: true,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textPrimary,
                    height: 1.55,
                  ),
                ),
                _buildMedia(reply.media),
                const SizedBox(height: 6),
                Row(
                  children: [
                    CommentActionButton(
                      icon: Icons.reply_rounded,
                      label: '回复',
                      onTap: () => setState(() => replyTarget = reply),
                    ),
                    const SizedBox(width: 8),
                    CommentActionButton(
                      icon: isLiked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      label: '${reply.likeCount}',
                      onTap: () => _toggleLike(reply),
                      isActive: isLiked,
                      activeColor: AppTheme.pink,
                    ),
                    const Spacer(),
                    CommentMoreButton(
                      onPressed: () => _showReplyMenu(reply),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (!isLast)
                  const Divider(
                    height: 1,
                    thickness: 0.6,
                    color: Color(0xFFEDF2F7),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedia(List<RankingToyCommentMedia> media) {
    final imageUrls = media
        .map((item) => item.url.trim())
        .where((url) => url.isNotEmpty)
        .toList();
    if (imageUrls.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var index = 0; index < imageUrls.length; index++)
            GestureDetector(
              onTap: () => CommentImageViewer.open(
                context,
                imageUrls: imageUrls,
                initialIndex: index,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFFDCE7F2),
                      width: 0.8,
                    ),
                  ),
                  child: AppNetworkImage(
                    url: imageUrls[index],
                    width: 88,
                    height: 88,
                    fit: BoxFit.cover,
                    errorBuilder: (_) => const SizedBox(
                      width: 88,
                      height: 88,
                      child: Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _toggleLike(RankingToyComment reply) async {
    if (widget.onToggleLike == null) return;
    try {
      final active = !reply.isLiked;
      final count = await widget.onToggleLike!(reply, active);
      if (!mounted) return;
      final index = replies.indexWhere((item) => item.id == reply.id);
      if (index >= 0) {
        setState(() {
          replies[index] = reply.copyWith(likeCount: count, isLiked: active);
        });
      }
    } catch (error) {
      if (!mounted) return;
      if (_isUnauthorizedReply(error)) {
        widget.onRequireAuth?.call();
        return;
      }
      _showMessage('点赞失败，请重试');
    }
  }

  Widget _buildReplyBar() {
    final targetName = replyTarget == null ? null : _name(replyTarget!);
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      padding: EdgeInsets.fromLTRB(
        14,
        8,
        14,
        8 + (MediaQuery.of(context).viewInsets.bottom > 0
            ? MediaQuery.of(context).viewInsets.bottom
            : MediaQuery.viewPaddingOf(context).bottom),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: inputController,
              enabled: !sending,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendReply(),
              decoration: InputDecoration(
                hintText: targetName == null ? '友善地回复一句…' : '回复 @$targetName…',
                filled: true,
                fillColor: const Color(0xFFF5F8FB),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 42,
            child: FilledButton(
              onPressed: sending ? null : _sendReply,
              child: sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('发送'),
            ),
          ),
        ],
      ),
    );
  }
}
