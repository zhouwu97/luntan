import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/api/api_client.dart' show ApiException;
import '../../data/api/ranking_repository.dart';
import '../../domain/models.dart' show relativeTimeLabel;
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import '../app_network_image.dart';
import 'comment_skeleton.dart';
import 'comment_image_viewer.dart';
import '../link_text.dart';

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
    this.onRequireAuth,
    this.blockedMessage = '当前身份暂不能评论，请登录邮箱账号后重试',
    this.onAuthorTap,
  });

  final RankingToyComment rootComment;
  final RankingRepository repository;
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
  final VoidCallback? onRequireAuth;
  final String blockedMessage;
  final ValueChanged<String>? onAuthorTap;

  @override
  State<RankingCommentThreadSheet> createState() =>
      _RankingCommentThreadSheetState();
}

class _RankingCommentThreadSheetState extends State<RankingCommentThreadSheet> {
  final replies = <RankingToyComment>[];
  final scrollController = ScrollController();
  final inputController = TextEditingController();
  RankingToyComment? replyTarget;
  String? nextCursor;
  String? errorMessage;
  String? loadMoreError;
  bool loading = false;
  bool loadingMore = false;
  bool sending = false;
  bool changed = false;
  bool hasMore = true;
  _ReplyLoadState loadState = _ReplyLoadState.loading;

  @override
  void initState() {
    super.initState();
    scrollController.addListener(_onScroll);
    _loadFirstPage();
  }

  @override
  void dispose() {
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
      if (!mounted) return;
      setState(() {
        replies.addAll(page.items);
        nextCursor = page.nextCursor;
        hasMore = page.hasMore && page.nextCursor != null;
        loading = false;
        loadState = replies.isEmpty
            ? _ReplyLoadState.loadedEmpty
            : _ReplyLoadState.loaded;
      });
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
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loadingMore = false;
        loadMoreError = '加载更多失败，点击重试';
      });
    }
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
        }
        widget.rootComment.replyCount += 1;
        changed = true;
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

  Widget _rating(int? rating) {
    if (rating == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(
          5,
          (index) => Icon(
            index < ((rating + 1) ~/ 2)
                ? Icons.favorite
                : Icons.favorite_border_rounded,
            size: 11,
            color: AppTheme.pink,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          '$rating分',
          style: const TextStyle(
            color: AppTheme.pink,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final rootName = _name(widget.rootComment);
    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.82,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD6E0E9),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                          onPressed: () => Navigator.of(context).pop(changed),
                          icon: const Icon(Icons.close_rounded, size: 20),
                        ),
                      ],
                    ),
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
                            onTap: () {
                              if (widget.rootComment.authorId.isNotEmpty &&
                                  !widget.rootComment.authorId.startsWith(
                                    'guest',
                                  )) {
                                widget.onAuthorTap?.call(
                                  widget.rootComment.authorId,
                                );
                              }
                            },
                            borderRadius: BorderRadius.circular(15),
                            child: CircleAvatar(
                              radius: 15,
                              backgroundColor: AppTheme.surfaceBlue,
                              child: Text(
                                rootName.isEmpty
                                    ? '友'
                                    : rootName.characters.first,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.primary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    InkWell(
                                      onTap: () {
                                        if (widget
                                                .rootComment
                                                .authorId
                                                .isNotEmpty &&
                                            !widget.rootComment.authorId
                                                .startsWith('guest')) {
                                          widget.onAuthorTap?.call(
                                            widget.rootComment.authorId,
                                          );
                                        }
                                      },
                                      borderRadius: BorderRadius.circular(4),
                                      child: Text(
                                        rootName,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'LV${widget.rootComment.level}',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: AppTheme.levelText,
                                      ),
                                    ),
                                    const Spacer(),
                                    _rating(widget.rootComment.authorRating),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                LinkText(
                                  widget.rootComment.content,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF62788D),
                                    height: 1.45,
                                  ),
                                ),
                                _buildMedia(widget.rootComment.media),
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
              Expanded(child: _buildReplyList()),
              _buildReplyBar(),
            ],
          ),
        ),
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
        child: TextButton(
          onPressed: _loadFirstPage,
          child: Text(errorMessage!),
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
      separatorBuilder: (_, _) =>
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
            return TextButton(
              onPressed: _loadMore,
              child: Text(loadMoreError!),
            );
          }
          return const SizedBox(height: 16);
        }
        return _buildReplyItem(replies[index]);
      },
    );
  }

  String _replyTitle() => switch (loadState) {
    _ReplyLoadState.loading || _ReplyLoadState.error => '回复',
    _ReplyLoadState.loadedEmpty => '0 条回复',
    _ReplyLoadState.loaded => '${widget.rootComment.replyCount} 条回复',
  };

  Widget _buildReplyItem(RankingToyComment reply) {
    final name = _name(reply);
    final replyTo = _replyToName(reply);
    final isLiked = reply.isLiked;
    return Container(
      key: GlobalObjectKey('ranking-reply:${reply.id}'),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              if (reply.authorId.isNotEmpty &&
                  !reply.authorId.startsWith('guest')) {
                widget.onAuthorTap?.call(reply.authorId);
              }
            },
            borderRadius: BorderRadius.circular(15),
            child: CircleAvatar(
              radius: 15,
              backgroundColor: AppTheme.surfaceBlue,
              child: Text(
                name.isEmpty ? '友' : name.characters.first,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primary,
                ),
              ),
            ),
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
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'LV${reply.level}',
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: AppTheme.levelText,
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
                    GestureDetector(
                      onTap: () => setState(() => replyTarget = reply),
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
                      onTap: () => _toggleLike(reply),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isLiked
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            size: 13,
                            color: isLiked
                                ? AppTheme.pink
                                : AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${reply.likeCount}',
                            style: TextStyle(
                              fontSize: 11,
                              color: isLiked
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
                child: AppNetworkImage(
                  url: imageUrls[index],
                  width: 96,
                  height: 96,
                  fit: BoxFit.cover,
                  errorBuilder: (_) => const SizedBox(
                    width: 96,
                    height: 96,
                    child: Icon(Icons.broken_image_outlined),
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
        8 + MediaQuery.of(context).viewInsets.bottom,
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
