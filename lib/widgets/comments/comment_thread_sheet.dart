import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/api/api_client.dart';
import '../../data/api/comment_repository.dart';
import '../../domain/models.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import 'comment_composer_controller.dart';
import 'comment_reply_bar.dart';
import 'comment_skeleton.dart';
import 'emoji/sticker_catalog.dart';

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
    this.onReplyDraft,
    this.onToggleLike,
    this.onAuthorTap,
  });

  final Comment rootComment;
  final CommentRepository repository;
  final String? focusReplyId;
  final bool isAuthenticated;
  final VoidCallback? onRequireAuth;
  final bool canComment;
  final String blockedMessage;
  final Future<Comment> Function(Comment target, String content) onReply;
  final Future<Comment> Function(Comment target, CommentDraft draft)? onReplyDraft;
  final Future<void> Function(Comment comment)? onToggleLike;
  final ValueChanged<String>? onAuthorTap;

  @override
  State<CommentThreadSheet> createState() => _CommentThreadSheetState();
}

class _CommentThreadSheetState extends State<CommentThreadSheet> {
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
      final context = GlobalObjectKey('reply:${widget.focusReplyId}').currentContext;
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

  void _handleAuthorTap(String? authorId) {
    if (authorId != null && authorId.isNotEmpty && !authorId.startsWith('guest')) {
      widget.onAuthorTap?.call(authorId);
    }
  }

  void _openImagePreview(BuildContext context, String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
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

  @override
  Widget build(BuildContext context) {
    final root = widget.rootComment;
    final rootAuthor = root.author?.nickname ??
        (root.authorId.startsWith('guest') ? '游客' : '匿名用户');
    final rootLevel = root.author?.level ??
        (root.authorId.startsWith('guest') || root.authorId.isEmpty ? 0 : 1);

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
                      InkWell(
                        onTap: () => _handleAuthorTap(root.authorId),
                        borderRadius: BorderRadius.circular(13),
                        child: _buildSmallAvatar(root.author?.avatar?.trim(), rootAuthor, size: 26),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InkWell(
                              onTap: () => _handleAuthorTap(root.authorId),
                              borderRadius: BorderRadius.circular(4),
                              child: Row(
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
                            ),
                            if (root.content.isNotEmpty) ...[
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
                            if (root.media.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Wrap(
                                  spacing: 4,
                                  children: root.media.map((m) {
                                    final url = m.url ?? m.thumb?.url ?? '';
                                    if (url.isEmpty) return const SizedBox.shrink();
                                    return GestureDetector(
                                      onTap: () => _openImagePreview(context, url),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: Image.network(
                                          url,
                                          width: 48,
                                          height: 48,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            if (root.stickerId != null && root.stickerId!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: _buildStickerThumbnail(root.stickerId!, size: 40),
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
        final author = reply.author?.nickname ??
            (reply.authorId.startsWith('guest') ? '游客' : '匿名用户');
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
              InkWell(
                onTap: () => _handleAuthorTap(reply.authorId),
                borderRadius: BorderRadius.circular(15),
                child: _buildSmallAvatar(reply.author?.avatar?.trim(), author, size: 30),
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
                    ),
                    if (replyTo != null) ...[
                      const SizedBox(height: 2),
                      InkWell(
                        onTap: () => _handleAuthorTap(reply.replyToUserId),
                        borderRadius: BorderRadius.circular(4),
                        child: Text(
                          '回复 @$replyTo',
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: Color(0xFF7990A5),
                          ),
                        ),
                      ),
                    ],
                    if (reply.content.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        reply.content,
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
                            final url = m.url ?? m.thumb?.url ?? '';
                            if (url.isEmpty) return const SizedBox.shrink();
                            return GestureDetector(
                              onTap: () => _openImagePreview(context, url),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.network(
                                  url,
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    if (reply.stickerId != null && reply.stickerId!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: _buildStickerThumbnail(reply.stickerId!, size: 60),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            setState(() => currentReplyTarget = reply);
                            _composer.openReply(
                              parentCommentId: reply.id,
                              replyToUserId: reply.authorId,
                              replyToName: author,
                            );
                          },
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
      child: const Icon(Icons.sticky_note_2_outlined, color: Colors.grey, size: 24),
    );
  }

  String _replyTitle(Comment root) => switch (loadState) {
    _ReplyLoadState.loading || _ReplyLoadState.error => '回复',
    _ReplyLoadState.loadedEmpty => '0 条回复',
    _ReplyLoadState.loaded => '${root.replyCount} 条回复',
  };

  Widget _buildSmallAvatar(String? avatarUrl, String author, {required double size}) {
    final initial = author.isNotEmpty ? author.characters.first : '友';
    final placeholder = Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: AppTheme.surfaceBlue,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w800,
          color: AppTheme.primary,
        ),
      ),
    );

    if (avatarUrl == null || avatarUrl.isEmpty) {
      return placeholder;
    }

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
          avatarUrl,
          fit: BoxFit.cover,
          width: size,
          height: size,
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) {
              return child;
            }
            return placeholder;
          },
          errorBuilder: (context, error, stackTrace) => placeholder,
        ),
      ),
    );
  }
}
