import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/comments_controller.dart';
import '../controllers/interaction_controller.dart';
import '../controllers/post_detail_controller.dart';
import '../data/api/api_client.dart';
import '../data/api/poll_repository.dart';
import '../data/mock_forum_data.dart';
import '../domain/models.dart';
import '../theme/app_theme.dart';
import '../widgets/forum_author_row.dart';
import '../widgets/post_media_preview.dart';

class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({
    super.key,
    required this.store,
    required this.controller,
    this.commentsController,
    this.interactionController,
    this.currentUserId,
    this.focusComments = false,
    required this.onToggleLike,
    required this.onToggleBookmark,
    required this.onFeedback,
    this.onDeletePost,
    this.onEditPost,
    this.onReport,
    this.pollRepository,
  });

  final ForumStore store;
  final PostDetailController controller;
  final CommentsController? commentsController;
  final InteractionController? interactionController;
  final String? currentUserId;
  final bool focusComments;
  final Future<void> Function(Post) onToggleLike;
  final Future<void> Function(Post) onToggleBookmark;
  final ValueChanged<String> onFeedback;
  final Future<void> Function(Post)? onDeletePost;
  final Future<void> Function(Post, String title, String content)? onEditPost;
  final Future<void> Function(String targetType, String targetId)? onReport;
  final PollRepository? pollRepository;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final replyController = TextEditingController();
  final commentsKey = GlobalKey();
  final commentsScrollController = ScrollController();
  bool isSending = false;
  bool hasFocusedComments = false;
  Comment? replyTarget;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.controller.load();
      widget.commentsController?.load();
    });
    commentsScrollController.addListener(_loadMoreComments);
  }

  @override
  void dispose() {
    replyController.dispose();
    commentsScrollController
      ..removeListener(_loadMoreComments)
      ..dispose();
    super.dispose();
  }

  void _loadMoreComments() {
    final controller = widget.commentsController;
    if (controller != null &&
        commentsScrollController.position.extentAfter < 240) {
      controller.loadMore();
    }
  }

  Future<void> _submitReply(Post post) async {
    if (isSending) return;
    final content = replyController.text.trim();
    if (content.isEmpty) return;
    final comments = widget.commentsController;
    if (comments == null) return;
    setState(() => isSending = true);
    final target = replyTarget;
    final before = post.commentCount;
    try {
      if (target == null) {
        await comments.addComment(content);
      } else {
        await comments.replyTo(target, content, replyToUserId: target.authorId);
      }
      if (post.commentCount == before) post.commentCount = before + 1;
      if (!mounted) return;
      setState(() {
        replyController.clear();
        replyTarget = null;
      });
      widget.onFeedback('回复已发布');
    } catch (error) {
      if (mounted)
        widget.onFeedback(userFacingApiMessage(error, fallback: '回复失败，请重试'));
    } finally {
      if (mounted) setState(() => isSending = false);
    }
  }

  void _focusCommentsIfNeeded() {
    if (!widget.focusComments || hasFocusedComments) return;
    hasFocusedComments = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = commentsKey.currentContext;
      if (mounted && context != null) {
        Scrollable.ensureVisible(
          context,
          duration: AppTheme.tabMotion,
          alignment: .08,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final listenables = <Listenable>[widget.controller];
    if (widget.commentsController != null)
      listenables.add(widget.commentsController!);
    if (widget.interactionController != null)
      listenables.add(widget.interactionController!);
    return AnimatedBuilder(
      animation: Listenable.merge(listenables),
      builder: (context, _) {
        final state = widget.controller.state;
        if (state.status == PostDetailStatus.initial ||
            state.status == PostDetailStatus.loading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (state.status != PostDetailStatus.success || state.detail == null) {
          final message = state.status == PostDetailStatus.notFound
              ? '内容不存在或已被删除'
              : userFacingApiMessage(
                  state.error ?? StateError('load'),
                  fallback: '帖子加载失败，请重试',
                );
          return Scaffold(
            appBar: AppBar(),
            body: _StateMessage(
              message: message,
              onRetry: widget.controller.load,
            ),
          );
        }
        final post = state.detail!.post;
        _focusCommentsIfNeeded();
        final commentsController = widget.commentsController;
        final allComments =
            commentsController?.items ?? widget.store.commentsFor(post);
        final roots = allComments
            .where((comment) => comment.parentId == null)
            .toList();
        return Scaffold(
          appBar: AppBar(
            title: Text(
              post.community?.name ?? post.tag,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            actions: [
              IconButton(
                onPressed: () =>
                    _runInteraction(() => widget.onToggleBookmark(post)),
                tooltip: '收藏帖子',
                icon: Icon(
                  post.isBookmarked
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  color: post.isBookmarked
                      ? AppTheme.primary
                      : AppTheme.textSecondary,
                ),
              ),
              IconButton(
                onPressed: () =>
                    _runInteraction(() => widget.onToggleLike(post)),
                tooltip: '点赞帖子',
                icon: Icon(
                  post.isLiked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: post.isLiked ? AppTheme.pink : AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  controller: commentsScrollController,
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.pagePadding,
                    8,
                    AppTheme.pagePadding,
                    24,
                  ),
                  children: [
                    ForumAuthorRow(
                      post: post,
                      onMenu: () => _showPostMenu(post),
                    ),
                    const SizedBox(height: 15),
                    if (post.isPinned ||
                        post.isFeatured ||
                        post.extraTag == '精华')
                      _Tag(
                        text: post.isPinned ? '置顶' : '精华',
                        color: post.isPinned ? AppTheme.pink : AppTheme.orange,
                      ),
                    if (post.isPinned ||
                        post.isFeatured ||
                        post.extraTag == '精华')
                      const SizedBox(height: 8),
                    Text(
                      post.title,
                      style: const TextStyle(
                        fontSize: 22,
                        height: 1.35,
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 11),
                    Text(
                      post.body,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        height: 1.75,
                      ),
                    ),
                    if (post.type == PostType.poll &&
                        widget.pollRepository != null)
                      _PollPanel(
                        repository: widget.pollRepository!,
                        postId: post.id,
                      ),
                    if (post.images.isNotEmpty)
                      PostMediaPreview(
                        images: post.images,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                MediaGalleryScreen(images: post.images),
                          ),
                        ),
                      ),
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        const Icon(
                          Icons.visibility_outlined,
                          color: AppTheme.textSecondary,
                          size: 17,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${post.views} 浏览',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Icon(
                          Icons.chat_bubble_outline_rounded,
                          color: AppTheme.textSecondary,
                          size: 17,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${post.comments} 回复',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Icon(
                          post.isLiked
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: post.isLiked
                              ? AppTheme.pink
                              : AppTheme.textSecondary,
                          size: 17,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${post.likeCount} 赞',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 35, color: AppTheme.border),
                    Container(
                      key: commentsKey,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '全部回复 ${post.comments}',
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Text(
                            '${roots.length} 条可见',
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 13),
                    if (commentsController?.isLoading == true &&
                        allComments.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 36),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (commentsController?.errorMessage != null &&
                        allComments.isEmpty)
                      _CommentError(onRetry: () => commentsController!.load()),
                    if (allComments.isEmpty &&
                        commentsController?.isLoading != true)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 45),
                        child: Center(
                          child: Text(
                            '还没有回复，来抢沙发吧',
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                        ),
                      ),
                    ...roots.asMap().entries.map((entry) {
                      final comment = entry.value;
                      final children = allComments
                          .where((item) => item.parentId == comment.id)
                          .toList();
                      return _CommentTile(
                        comment: comment,
                        floor: entry.key + 2,
                        children: children,
                        store: widget.store,
                        liked:
                            widget.interactionController?.likedCommentIds
                                .contains(comment.id) ??
                            widget.store.isCommentLiked(comment),
                        onReply: () => setState(() => replyTarget = comment),
                        onLike: () => _likeComment(comment),
                        onMore: () => _showCommentMenu(comment),
                      );
                    }),
                    if (commentsController?.isLoadingMore == true)
                      const Padding(
                        padding: EdgeInsets.all(14),
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    if (commentsController != null &&
                        !commentsController.hasMore &&
                        allComments.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Center(
                          child: Text(
                            '没有更多回复了',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _ReplyBar(
                controller: replyController,
                target: replyTarget,
                sending: isSending,
                onSubmit: () => _submitReply(post),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _runInteraction(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) widget.onFeedback(userFacingApiMessage(error));
    }
  }

  Future<void> _likeComment(Comment comment) async {
    final interaction = widget.interactionController;
    if (interaction == null) return;
    try {
      await interaction.toggleCommentLike(comment);
    } catch (error) {
      if (mounted) widget.onFeedback(userFacingApiMessage(error));
    }
  }

  void _showPostMenu(Post post) {
    final canEdit =
        post.viewerState.canEdit ||
        (widget.currentUserId != null && post.authorId == widget.currentUserId);
    final canDelete = post.viewerState.canDelete || canEdit;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(
                post.isBookmarked
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                color: AppTheme.primary,
              ),
              title: Text(post.isBookmarked ? '取消收藏' : '收藏帖子'),
              onTap: () {
                Navigator.pop(sheetContext);
                _runInteraction(() => widget.onToggleBookmark(post));
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('分享帖子'),
              onTap: () {
                Navigator.pop(sheetContext);
                Clipboard.setData(ClipboardData(text: '/posts/${post.id}'));
                widget.onFeedback('帖子链接已复制');
              },
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: AppTheme.orange),
              title: const Text('举报帖子'),
              onTap: () {
                Navigator.pop(sheetContext);
                _report('post', post.id);
              },
            ),
            if (canEdit)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('编辑帖子'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _editPost(post);
                },
              ),
            if (canDelete)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppTheme.pink),
                title: const Text('删除帖子'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _deletePost(post);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editPost(Post post) async {
    final titleController = TextEditingController(text: post.title);
    final contentController = TextEditingController(text: post.content);
    final value = await showDialog<(String, String)>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('编辑帖子'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              maxLength: 200,
              decoration: const InputDecoration(labelText: '标题'),
            ),
            TextField(
              controller: contentController,
              maxLines: 5,
              decoration: const InputDecoration(labelText: '正文'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, (
              titleController.text.trim(),
              contentController.text.trim(),
            )),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    titleController.dispose();
    contentController.dispose();
    if (value == null ||
        value.$1.isEmpty ||
        value.$2.isEmpty ||
        widget.onEditPost == null)
      return;
    try {
      await widget.onEditPost!(post, value.$1, value.$2);
      if (mounted) widget.onFeedback('帖子已更新');
    } catch (error) {
      if (mounted)
        widget.onFeedback(userFacingApiMessage(error, fallback: '编辑失败，请重试'));
    }
  }

  Future<void> _deletePost(Post post) async {
    if (widget.onDeletePost == null) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('删除帖子？'),
            content: const Text('删除后帖子将不再公开显示。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      await widget.onDeletePost!(post);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted)
        widget.onFeedback(userFacingApiMessage(error, fallback: '删除失败，请重试'));
    }
  }

  void _showCommentMenu(Comment comment) {
    final canEdit =
        widget.currentUserId != null &&
        comment.authorId == widget.currentUserId;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: AppTheme.orange),
              title: const Text('举报评论'),
              onTap: () {
                Navigator.pop(sheetContext);
                _report('comment', comment.id);
              },
            ),
            if (canEdit)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('编辑评论'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _editComment(comment);
                },
              ),
            if (canEdit)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('删除评论'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _deleteComment(comment);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _report(String targetType, String targetId) async {
    try {
      if (widget.onReport != null) {
        await widget.onReport!(targetType, targetId);
        if (mounted) widget.onFeedback('举报已提交，我们会尽快处理');
      } else if (mounted) {
        widget.onFeedback('感谢反馈，我们会尽快处理');
      }
    } catch (error) {
      if (mounted)
        widget.onFeedback(userFacingApiMessage(error, fallback: '举报失败，请稍后重试'));
    }
  }

  Future<void> _editComment(Comment comment) async {
    final controller = TextEditingController(text: comment.content);
    final value = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('编辑评论'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty || widget.commentsController == null)
      return;
    try {
      final updated = await widget.commentsController!.edit(comment, value);
      if (updated == null) widget.onFeedback('当前模式暂不支持编辑评论');
    } catch (error) {
      if (mounted)
        widget.onFeedback(userFacingApiMessage(error, fallback: '评论编辑失败，请重试'));
    }
  }

  Future<void> _deleteComment(Comment comment) async {
    final controller = widget.commentsController;
    if (controller == null) return;
    final state = widget.controller.state;
    final post = state.detail?.post;
    if (post == null) return;
    final before = post.commentCount;
    try {
      await controller.delete(comment);
      if (post.commentCount == before && before > 0)
        post.commentCount = before - 1;
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted)
        widget.onFeedback(userFacingApiMessage(error, fallback: '删除失败，请重试'));
    }
  }
}

class _PollPanel extends StatefulWidget {
  const _PollPanel({required this.repository, required this.postId});
  final PollRepository repository;
  final String postId;
  @override
  State<_PollPanel> createState() => _PollPanelState();
}

class _PollPanelState extends State<_PollPanel> {
  late Future<Map<String, dynamic>?> future;
  final Set<String> selected = <String>{};
  bool submitting = false;
  bool voted = false;

  @override
  void initState() {
    super.initState();
    future = widget.repository.getPoll(widget.postId);
  }

  Future<void> _vote(
    String pollId,
    bool allowMultiple,
    List<Map<String, dynamic>> options,
  ) async {
    if (selected.isEmpty || submitting || voted) return;
    setState(() => submitting = true);
    try {
      await widget.repository.vote(
        pollId: pollId,
        optionIds: selected.toList(),
      );
      if (mounted)
        setState(() {
          voted = true;
        });
      // 服务器重新计算票数，刷新后再展示权威结果。
      if (mounted)
        setState(() => future = widget.repository.getPoll(widget.postId));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('投票失败，请重试')));
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>?>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done)
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: LinearProgressIndicator(),
        );
      final value = snapshot.data;
      if (value == null) return const SizedBox.shrink();
      final raw = value['options'];
      final options = raw is List
          ? raw
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
          : <Map<String, dynamic>>[];
      final pollId = '${value['id'] ?? ''}';
      final allowMultiple = value['allow_multiple'] == true;
      return Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceBlue,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${value['question'] ?? '投票'}',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            ...options.map((option) {
              final id = '${option['id'] ?? ''}';
              final count = option['vote_count'] is num
                  ? (option['vote_count'] as num).toInt()
                  : 0;
              // ignore: deprecated_member_use
              if (allowMultiple) {
                return CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: selected.contains(id),
                  onChanged: voted
                      ? null
                      : (value) => setState(() {
                          if (value == true) {
                            selected.add(id);
                          } else {
                            selected.remove(id);
                          }
                        }),
                  title: Text('${option['label'] ?? ''}'),
                  secondary: voted ? Text('$count') : null,
                );
              }
              return RadioListTile<String>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: id,
                groupValue: selected.isEmpty ? null : selected.first,
                onChanged: voted
                    ? null
                    : (value) => setState(() {
                        selected
                          ..clear()
                          ..add(value!);
                      }),
                title: Text('${option['label'] ?? ''}'),
                secondary: voted ? Text('$count') : null,
              );
            }),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: submitting || voted
                    ? null
                    : () => _vote(pollId, allowMultiple, options),
                child: Text(
                  voted
                      ? '已投票'
                      : submitting
                      ? '提交中…'
                      : '投票',
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, style: const TextStyle(color: AppTheme.textSecondary)),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetry, child: const Text('重试')),
      ],
    ),
  );
}

class _CommentError extends StatelessWidget {
  const _CommentError({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 30),
    child: Column(
      children: [
        const Text('评论加载失败', style: TextStyle(color: AppTheme.textSecondary)),
        TextButton(onPressed: onRetry, child: const Text('重试')),
      ],
    ),
  );
}

class _ReplyBar extends StatelessWidget {
  const _ReplyBar({
    required this.controller,
    required this.target,
    required this.sending,
    required this.onSubmit,
  });
  final TextEditingController controller;
  final Comment? target;
  final bool sending;
  final VoidCallback onSubmit;
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 8, 11, 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppTheme.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSubmit(),
                decoration: InputDecoration(
                  hintText: target == null ? '友善地回复一句…' : '回复这位同学…',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 7),
            FilledButton(
              onPressed: sending ? null : onSubmit,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              child: Text(sending ? '…' : '发送'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.floor,
    required this.children,
    required this.store,
    required this.liked,
    required this.onReply,
    required this.onLike,
    required this.onMore,
  });
  final Comment comment;
  final int floor;
  final List<Comment> children;
  final ForumStore store;
  final bool liked;
  final VoidCallback onReply;
  final VoidCallback onLike;
  final VoidCallback onMore;
  @override
  Widget build(BuildContext context) {
    final author = comment.author ?? store.userById(comment.authorId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: AppTheme.surfaceBlue,
                child: Text(
                  (author?.nickname ?? '匿').characters.first,
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w800,
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
                        Flexible(
                          child: Text(
                            author?.nickname ?? '匿名用户',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Lv.${author?.level ?? 1}',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '$floor楼',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      relativeTimeLabel(comment.createdAt),
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      comment.content,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        TextButton(
                          onPressed: onReply,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(38, 28),
                          ),
                          child: const Text('回复'),
                        ),
                        TextButton(
                          onPressed: onLike,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(48, 28),
                          ),
                          child: Text(
                            '${liked ? '♥' : '♡'} ${comment.likeCount + (liked ? 1 : 0)}',
                          ),
                        ),
                        IconButton(
                          onPressed: onMore,
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            Icons.more_horiz_rounded,
                            size: 17,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (children.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(left: 43, top: 2),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children.take(3).map((child) {
                  final childAuthor =
                      child.author ?? store.userById(child.authorId);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${childAuthor?.nickname ?? '匿名用户'}：${child.content}',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          if (children.length > 3)
            const Padding(
              padding: EdgeInsets.only(left: 43, top: 5),
              child: Text(
                '查看全部回复 ›',
                style: TextStyle(
                  color: AppTheme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );
}
