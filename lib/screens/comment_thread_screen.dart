import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/api/api_client.dart';
import '../data/api/comment_repository.dart';
import '../domain/models.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import '../widgets/app_network_image.dart';
import '../widgets/comments/comment_common_widgets.dart';
import '../widgets/comments/comment_composer_controller.dart';
import '../widgets/comments/comment_more_button.dart';
import '../widgets/comments/comment_reply_bar.dart';
import '../widgets/comments/comment_skeleton.dart';
import '../widgets/comments/emoji/sticker_catalog.dart';
import '../widgets/link_text.dart';

enum _ReplyLoadState { loading, loadedEmpty, loaded, error }

/// 楼中楼底部弹层：根评论摘要 + 回复列表（cursor 分页）+ 底部回复栏，
/// 从帖子详情页底部弹出，样式对齐榜单的回复弹窗。
class CommentThreadScreen extends StatefulWidget {
  const CommentThreadScreen({
    super.key,
    required this.rootComment,
    required this.repository,
    this.postAuthorId,
    this.focusReplyId,
    this.isAuthenticated = true,
    this.onRequireAuth,
    this.canComment = true,
    required this.blockedMessage,
    required this.onReply,
    this.onReplyDraft,
    this.onToggleLike,
    this.onToggleDislike,
    this.onAuthorTap,
    this.onMore,
  });

  final Comment rootComment;
  final CommentRepository repository;
  final String? postAuthorId;
  final String? focusReplyId;
  final bool isAuthenticated;
  final VoidCallback? onRequireAuth;
  final bool canComment;
  final String blockedMessage;
  final Future<Comment> Function(Comment target, String content) onReply;
  final Future<Comment> Function(Comment target, CommentDraft draft)?
  onReplyDraft;
  final Future<void> Function(Comment comment)? onToggleLike;
  final Future<void> Function(Comment comment)? onToggleDislike;
  final ValueChanged<String>? onAuthorTap;
  final ValueChanged<Comment>? onMore;

  @override
  State<CommentThreadScreen> createState() => _CommentThreadScreenState();
}

class _CommentThreadScreenState extends State<CommentThreadScreen> {
  final List<Comment> replies = [];
  final ScrollController scrollController = ScrollController();
  final CommentComposerController _composer = CommentComposerController();
  Comment? currentReplyTarget;
  String? nextCursor;
  bool hasMore = true;
  bool loading = false;
  bool loadingMore = false;
  bool sending = false;
  String? errorMessage;
  String? loadMoreError;
  _ReplyLoadState loadState = _ReplyLoadState.loading;
  int _generation = 0;
  bool _hasFocusedTarget = false;
  String? highlightedReplyId;
  Timer? _highlightTimer;

  @override
  void initState() {
    super.initState();
    scrollController.addListener(_onScroll);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _composer.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (scrollController.hasClients &&
        scrollController.position.extentAfter < 200) {
      _loadMore();
    }
  }

  Future<void> _loadFirstPage() async {
    final generation = ++_generation;
    setState(() {
      loading = true;
      loadState = _ReplyLoadState.loading;
      errorMessage = null;
      loadMoreError = null;
      replies.clear();
      nextCursor = null;
      hasMore = true;
    });

    try {
      final page = await widget.repository.listReplies(
        commentId: widget.rootComment.id,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        replies
          ..clear()
          ..addAll(page.items);
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
          'Comment replies request failed: '
          'GET /api/v1/comments/${widget.rootComment.id}/replies; $error',
        );
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        loading = false;
        loadState = _ReplyLoadState.error;
        errorMessage = userFacingApiMessage(error, fallback: '回复加载失败，请重试');
      });
    }
  }

  Future<void> _loadMore() async {
    if (loadingMore || !hasMore || nextCursor == null) return;
    setState(() {
      loadingMore = true;
      loadMoreError = null;
    });

    try {
      final page = await widget.repository.listReplies(
        commentId: widget.rootComment.id,
        cursor: nextCursor,
      );
      if (!mounted) return;
      setState(() {
        for (final item in page.items) {
          if (!replies.any((r) => r.id == item.id)) {
            replies.add(item);
          }
        }
        nextCursor = page.nextCursor;
        hasMore = page.hasMore && page.nextCursor != null;
        loadingMore = false;
      });
      _checkAndFocusTarget();
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          'Comment replies paginate failed: '
          'GET /api/v1/comments/${widget.rootComment.id}/replies?cursor=$nextCursor; $error',
        );
      }
      if (!mounted) return;
      setState(() {
        loadingMore = false;
        loadMoreError = '加载更多失败，点击重试';
      });
    }
  }

  void _checkAndFocusTarget() {
    if (_hasFocusedTarget || widget.focusReplyId == null) return;
    final index = replies.indexWhere((r) => r.id == widget.focusReplyId);
    if (index == -1) return;

    _hasFocusedTarget = true;
    setState(() => highlightedReplyId = widget.focusReplyId);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = GlobalObjectKey(
        'reply:${widget.focusReplyId}',
      ).currentContext;
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
    final draft = _composer.draft;
    if (draft.isEmpty || sending) return;

    final target = currentReplyTarget ?? widget.rootComment;
    setState(() => sending = true);

    try {
      final newComment = widget.onReplyDraft != null
          ? await widget.onReplyDraft!(target, draft)
          : await widget.onReply(target, draft.text);
      if (!mounted) return;
      setState(() {
        _composer.reset();
        currentReplyTarget = null;
        if (!replies.any((r) => r.id == newComment.id)) {
          replies.add(newComment);
        }
        loadState = _ReplyLoadState.loaded;
        sending = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scrollController.hasClients) {
          scrollController.animateTo(
            scrollController.position.maxScrollExtent + 80,
            duration: AppMotion.normal,
            curve: AppMotion.standard,
          );
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() => sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userFacingApiMessage(error, fallback: '回复失败，请重试')),
          ),
        );
      }
    }
  }

  void _handleAuthorTap(String? authorId) {
    if (authorId != null &&
        authorId.isNotEmpty &&
        !authorId.startsWith('guest')) {
      widget.onAuthorTap?.call(authorId);
    }
  }

  bool _isPostAuthor(Comment comment) =>
      widget.postAuthorId != null &&
      widget.postAuthorId!.isNotEmpty &&
      comment.authorId == widget.postAuthorId;

  void _openImagePreview(BuildContext context, String imageUrl) {
    if (imageUrl.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          body: Center(
            child: InteractiveViewer(
              child: AppNetworkImage(
                url: imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (_) => const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white54,
                  size: 64,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _replyTitle() => switch (loadState) {
    _ReplyLoadState.loading || _ReplyLoadState.error => '回复',
    _ReplyLoadState.loadedEmpty => '0 条回复',
    _ReplyLoadState.loaded =>
      '${widget.rootComment.replyCount ?? replies.length} 条回复',
  };

  @override
  Widget build(BuildContext context) {
    final root = widget.rootComment;
    final rootAuthor =
        root.author?.nickname ??
        (root.authorId.startsWith('guest') ? '游客' : '匿名用户');
    final rootLevel =
        root.author?.level ??
        (root.authorId.startsWith('guest') || root.authorId.isEmpty ? 0 : 1);

    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.84,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD6E0E9),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                child: Row(
                  children: [
                    Text(
                      _replyTitle(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: '关闭',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFEDF2F7)),
              Expanded(
                child: Container(
                  color: Colors.white,
                  child: CustomScrollView(
                    controller: scrollController,
                    slivers: [
                      // 根评论精简摘要
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF6FAFD),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFE2EDF7),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CommentAvatar(
                                  name: rootAuthor,
                                  avatarUrl: root.author?.avatar?.trim(),
                                  size: 34,
                                  onTap: () => _handleAuthorTap(root.authorId),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      InkWell(
                                        onTap: () =>
                                            _handleAuthorTap(root.authorId),
                                        borderRadius: BorderRadius.circular(4),
                                        child: Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                rootAuthor,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppTheme.textPrimary,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 5),
                                            UserLevelBadge(
                                              level: rootLevel,
                                              fontSize: 8.5,
                                            ),
                                            if (_isPostAuthor(root)) ...[
                                              const SizedBox(width: 5),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 5,
                                                      vertical: 1,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color:
                                                      const Color(0xFFEBF3FE),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  border: Border.all(
                                                    color:
                                                        const Color(0xFFCFE2FA),
                                                    width: 0.6,
                                                  ),
                                                ),
                                                child: const Text(
                                                  '楼主',
                                                  style: TextStyle(
                                                    fontSize: 8.5,
                                                    fontWeight: FontWeight.w800,
                                                    color: Color(0xFF2672D6),
                                                  ),
                                                ),
                                              ),
                                            ],
                                            const Spacer(),
                                            if (root.floor != null)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 5,
                                                      vertical: 1,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFFE9F0F8,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  '${root.floor} 楼',
                                                  style: const TextStyle(
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFF7E93A7),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (root.content.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        LinkText(
                                          root.content,
                                          selectable: true,
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            color: Color(0xFF243647),
                                            height: 1.55,
                                          ),
                                        ),
                                      ],
                                      if (root.media.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 6,
                                          ),
                                          child: Wrap(
                                            spacing: 6,
                                            runSpacing: 6,
                                            children: root.media.map((m) {
                                              final url = m.previewUrl ?? '';
                                              if (url.isEmpty) {
                                                return const SizedBox.shrink();
                                              }
                                              return GestureDetector(
                                                onTap: () => _openImagePreview(
                                                  context,
                                                  m.originalUrl ?? url,
                                                ),
                                                child: ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                      border: Border.all(
                                                        color: const Color(
                                                          0xFFDCE7F2,
                                                        ),
                                                        width: 0.8,
                                                      ),
                                                    ),
                                                    child: AppNetworkImage(
                                                      url: url,
                                                      width: 80,
                                                      height: 80,
                                                      fit: BoxFit.cover,
                                                    ),
                                                  ),
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                      if (root.stickerId != null &&
                                          root.stickerId!.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 6,
                                          ),
                                          child: _buildStickerThumbnail(
                                            root.stickerId!,
                                            size: 60,
                                          ),
                                        ),
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
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
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
                      ..._buildReplySlivers(),
                    ],
                  ),
                ),
              ),

              // 底部回复栏（保留表情/贴纸/图片能力）
              CommentReplyBar(
                composerController: _composer,
                target: currentReplyTarget,
                sending: sending,
                isAuthenticated: widget.isAuthenticated,
                canComment: widget.canComment,
                onRequireAuth: widget.onRequireAuth,
                blockedMessage: widget.blockedMessage,
                isSheetMode: true,
                onFeedback: (msg) => ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(msg))),
                onCancelTarget: () => setState(() => currentReplyTarget = null),
                onSubmit: _sendReply,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildReplySlivers() {
    if (loadState == _ReplyLoadState.loading && replies.isEmpty) {
      return [
        const SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          sliver: SliverToBoxAdapter(child: CommentSkeleton(itemCount: 3)),
        ),
      ];
    }
    if (loadState == _ReplyLoadState.error && replies.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    errorMessage!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _loadFirstPage,
                    child: const Text('点击重试'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ];
    }
    if (replies.isEmpty) {
      return [
        const SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                '暂无二级回复，来发第一条吧',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        sliver: SliverList.separated(
          itemCount: replies.length + 1,
          separatorBuilder: (context, index) =>
              const Divider(height: 16, thickness: 1, color: Color(0xFFEFF3F6)),
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
                return Center(
                  child: TextButton(
                    onPressed: _loadMore,
                    child: Text(
                      loadMoreError!,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                );
              }
              return const SizedBox(height: 16);
            }

            final reply = replies[index];
            final isHighlighted = highlightedReplyId == reply.id;
            final author =
                reply.author?.nickname ??
                (reply.authorId.startsWith('guest') ? '游客' : '匿名用户');
            final replyLevel =
                reply.author?.level ??
                (reply.authorId.startsWith('guest') || reply.authorId.isEmpty
                    ? 0
                    : 1);
            final replyTo = reply.replyToUserId == null
                ? null
                : (reply.replyToUser?.nickname ??
                      reply.replyToUser?.username ??
                      '用户');

            return Container(
              key: GlobalObjectKey('reply:${reply.id}'),
              decoration: BoxDecoration(
                color: isHighlighted
                    ? const Color(0xFFEDF6FF)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CommentAvatar(
                    name: author,
                    avatarUrl: reply.author?.avatar?.trim(),
                    size: 32,
                    onTap: () => _handleAuthorTap(reply.authorId),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: () => _handleAuthorTap(reply.authorId),
                          borderRadius: BorderRadius.circular(4),
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  author,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 5),
                              UserLevelBadge(level: replyLevel, fontSize: 8.5),
                              if (_isPostAuthor(reply)) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEBF3FE),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: const Color(0xFFCFE2FA),
                                      width: 0.6,
                                    ),
                                  ),
                                  child: const Text(
                                    '楼主',
                                    style: TextStyle(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF2672D6),
                                    ),
                                  ),
                                ),
                              ],
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
                        ),
                        if (replyTo != null) ...[
                          const SizedBox(height: 2),
                          InkWell(
                            onTap: () => _handleAuthorTap(reply.replyToUserId),
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 1),
                              child: Text.rich(
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
                            ),
                          ),
                        ],
                        if (reply.content.isNotEmpty) ...[
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
                        ],
                        if (reply.media.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: reply.media.map((m) {
                                final url = m.previewUrl ?? '';
                                if (url.isEmpty) return const SizedBox.shrink();
                                return GestureDetector(
                                  onTap: () => _openImagePreview(
                                    context,
                                    m.originalUrl ?? url,
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: const Color(0xFFDCE7F2),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: AppNetworkImage(
                                        url: url,
                                        width: 80,
                                        height: 80,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        if (reply.stickerId != null &&
                            reply.stickerId!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: _buildStickerThumbnail(
                              reply.stickerId!,
                              size: 60,
                            ),
                          ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            CommentActionButton(
                              icon: Icons.reply_rounded,
                              label: '回复',
                              onTap: () {
                                setState(() => currentReplyTarget = reply);
                                _composer.openReply(
                                  parentCommentId: reply.id,
                                  replyToUserId: reply.authorId,
                                  replyToName: author,
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            CommentActionButton(
                              icon: reply.isLiked
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              label: '${reply.likeCount}',
                              onTap: widget.onToggleLike != null
                                  ? () => widget.onToggleLike!(reply)
                                  : null,
                              isActive: reply.isLiked,
                              activeColor: AppTheme.pink,
                            ),
                            if (widget.onToggleDislike != null) ...[
                              const SizedBox(width: 8),
                              CommentActionButton(
                                icon: reply.isDisliked
                                    ? Icons.thumb_down_rounded
                                    : Icons.thumb_down_off_alt_rounded,
                                label: reply.dislikeCount > 0
                                    ? '${reply.dislikeCount}'
                                    : null,
                                onTap: () => widget.onToggleDislike!(reply),
                                isActive: reply.isDisliked,
                                activeColor: const Color(0xFF5A7B9C),
                              ),
                            ],
                            const Spacer(),
                            if (widget.onMore != null)
                              CommentMoreButton(
                                onPressed: () => widget.onMore!(reply),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ];
  }

  Widget _buildStickerThumbnail(String stickerId, {required double size}) {
    final sticker = appStickerById(stickerId);
    if (sticker != null) {
      return Image.asset(
        sticker.thumbnailAsset,
        width: size,
        height: size,
        fit: BoxFit.contain,
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4F8),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.sticky_note_2_outlined,
        color: Colors.grey,
        size: 24,
      ),
    );
  }
}
