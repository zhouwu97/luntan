import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/api/api_client.dart';
import '../../data/api/comment_repository.dart';
import '../../domain/models.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import 'comment_reply_bar.dart';
import 'comment_skeleton.dart';

enum _ReplyLoadState { loading, loadedEmpty, loaded, error }

class CommentThreadSheet extends StatefulWidget {
  const CommentThreadSheet({
    super.key,
    required this.rootComment,
    required this.repository,
    this.focusReplyId,
    this.isAuthenticated = true,
    this.onRequireAuth,
    this.canComment = true,
    required this.blockedMessage,
    required this.onReply,
    this.onToggleLike,
  });

  final Comment rootComment;
  final CommentRepository repository;
  final String? focusReplyId;
  final bool isAuthenticated;
  final VoidCallback? onRequireAuth;
  final bool canComment;
  final String blockedMessage;
  final Future<Comment> Function(Comment target, String content) onReply;
  final Future<void> Function(Comment comment)? onToggleLike;

  @override
  State<CommentThreadSheet> createState() => _CommentThreadSheetState();
}

class _CommentThreadSheetState extends State<CommentThreadSheet> {
  final List<Comment> replies = [];
  final ScrollController scrollController = ScrollController();
  final TextEditingController inputController = TextEditingController();
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
    inputController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (scrollController.position.extentAfter < 200) {
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
      if (mounted && generation == _generation) {
        setState(() {
          errorMessage = '回复加载失败，请重试';
          loading = false;
          loadState = _ReplyLoadState.error;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (loading || loadingMore || !hasMore || nextCursor == null) return;
    final generation = _generation;
    final cursor = nextCursor!;
    setState(() => loadingMore = true);

    try {
      final page = await widget.repository.listReplies(
        commentId: widget.rootComment.id,
        cursor: cursor,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        final existingIds = replies.map((r) => r.id).toSet();
        for (final item in page.items) {
          if (existingIds.add(item.id)) {
            replies.add(item);
          }
        }
        nextCursor = page.nextCursor;
        hasMore = page.hasMore && page.nextCursor != cursor;
        loadingMore = false;
        loadMoreError = null;
      });
      _checkAndFocusTarget();
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          loadMoreError = '加载更多失败，点击重试';
          loadingMore = false;
        });
      }
    }
  }

  void _checkAndFocusTarget() {
    final targetId = widget.focusReplyId;
    if (targetId == null || _hasFocusedTarget) return;

    final found = replies.any((r) => r.id == targetId);
    if (!found) {
      if (hasMore && !loading && !loadingMore) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadMore();
        });
      }
      return;
    }

    _hasFocusedTarget = true;
    setState(() => highlightedReplyId = targetId);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = GlobalObjectKey('reply:$targetId').currentContext;
      if (context != null && mounted) {
        Scrollable.ensureVisible(
          context,
          duration: AppMotion.normal,
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
    final text = inputController.text.trim();
    if (text.isEmpty || sending) return;

    final target = currentReplyTarget ?? widget.rootComment;
    setState(() => sending = true);

    try {
      final newComment = await widget.onReply(target, text);
      if (!mounted) return;
      setState(() {
        inputController.clear();
        currentReplyTarget = null;
        // 如果未存在则插入末尾
        if (!replies.any((r) => r.id == newComment.id)) {
          replies.add(newComment);
        }
        widget.rootComment.replyCount += 1;
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

  @override
  Widget build(BuildContext context) {
    final root = widget.rootComment;
    final rootAuthor = root.author?.nickname ?? '用户';
    final rootLevel = root.author?.level ?? 1;

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        children: [
          // 拖拽把手
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD6E0E9),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),

          // 头部标题与根评论摘要
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _replyTitle(root),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: AppTheme.textSecondary,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 4),

                // 根评论精简摘要
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7FAFD),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 13,
                        backgroundColor: AppTheme.surfaceBlue,
                        backgroundImage: root.author?.avatar != null
                            ? NetworkImage(root.author!.avatar!)
                            : null,
                        child: root.author?.avatar == null
                            ? Text(
                                rootAuthor.isNotEmpty
                                    ? rootAuthor.characters.first
                                    : '友',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.primary,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  rootAuthor,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 0.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.levelBg,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Lv.$rootLevel',
                                    style: const TextStyle(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.levelText,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              root.content,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF62788D),
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: AppTheme.border),

          // 回复列表
          Expanded(child: _buildReplyList()),

          // 底部回复栏
          CommentReplyBar(
            controller: inputController,
            target: currentReplyTarget,
            sending: sending,
            isAuthenticated: widget.isAuthenticated,
            canComment: widget.canComment,
            onRequireAuth: widget.onRequireAuth,
            blockedMessage: widget.blockedMessage,
            onFeedback: (msg) => ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(msg))),
            onCancelTarget: () => setState(() => currentReplyTarget = null),
            onSubmit: _sendReply,
          ),
        ],
      ),
    );
  }

  Widget _buildReplyList() {
    if (loadState == _ReplyLoadState.loading && replies.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: CommentSkeleton(itemCount: 3),
      );
    }
    if (loadState == _ReplyLoadState.error && replies.isEmpty) {
      return Center(
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
            TextButton(onPressed: _loadFirstPage, child: const Text('点击重试')),
          ],
        ),
      );
    }
    if (replies.isEmpty) {
      return const Center(
        child: Text(
          '暂无二级回复，来发第一条吧',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
      );
    }

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
        final author = reply.author?.nickname ?? '用户';
        final replyTo = reply.replyToUserId == null
            ? null
            : (reply.replyToUser?.nickname ??
                  reply.replyToUser?.username ??
                  '用户');

        return Container(
          key: GlobalObjectKey('reply:${reply.id}'),
          decoration: BoxDecoration(
            color: isHighlighted ? const Color(0xFFEDF6FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: AppTheme.surfaceBlue,
                backgroundImage: reply.author?.avatar != null
                    ? NetworkImage(reply.author!.avatar!)
                    : null,
                child: reply.author?.avatar == null
                    ? Text(
                        author.isNotEmpty ? author.characters.first : '友',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primary,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          author,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
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
                      Text(
                        '回复 @$replyTo',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF7990A5),
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      reply.content,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textPrimary,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () =>
                              setState(() => currentReplyTarget = reply),
                          child: const Text(
                            '回复',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: widget.onToggleLike != null
                              ? () => widget.onToggleLike!(reply)
                              : null,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                reply.isLiked
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                size: 13,
                                color: reply.isLiked
                                    ? AppTheme.pink
                                    : AppTheme.textSecondary,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '${reply.likeCount}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: reply.isLiked
                                      ? AppTheme.pink
                                      : AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
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
    );
  }

  String _replyTitle(Comment root) => switch (loadState) {
    _ReplyLoadState.loading || _ReplyLoadState.error => '回复',
    _ReplyLoadState.loadedEmpty => '0 条回复',
    _ReplyLoadState.loaded => '${root.replyCount} 条回复',
  };
}
