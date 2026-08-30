import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../controllers/comments_controller.dart';
import '../controllers/interaction_controller.dart';
import '../controllers/post_detail_controller.dart';
import '../data/api/api_client.dart';
import '../data/api/comment_repository.dart';
import '../data/api/platform_repository.dart';
import '../data/api/poll_repository.dart';
import '../data/api/publish_repository.dart';
import '../data/app_links.dart';
import '../domain/models.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import '../widgets/comments/comment_composer_controller.dart';
import '../widgets/comments/comment_item.dart';
import '../widgets/comments/comment_reply_bar.dart';
import '../widgets/comments/comment_skeleton.dart';
import 'comment_thread_screen.dart';
import '../widgets/forum_author_row.dart';
import '../widgets/post_media_preview.dart';

class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({
    super.key,
    required this.controller,
    required this.commentsController,
    required this.interactionController,
    this.currentUserId,
    this.isAuthenticated = true,
    this.canLike,
    this.canComment,
    this.commentRestricted = false,
    this.commentRestrictedUntil,
    this.canBookmark,
    this.canReport,
    this.canVote,
    this.onRequireAuth,
    this.focusComments = false,
    this.focusCommentId,
    required this.onToggleLike,
    required this.onToggleBookmark,
    required this.onFeedback,
    this.onDeletePost,
    this.onEditPost,
    this.onReport,
    this.pollRepository,
    this.publishRepository,
    this.platformRepository,
    this.canModerate = false,
    this.onOpenUserId,
  });

  final PostDetailController controller;
  final CommentsController commentsController;
  final InteractionController interactionController;
  final String? currentUserId;
  final bool isAuthenticated;

  /// 能力字段由 /me 下发；可空是为了兼容直接使用该页面的旧调用方。
  final bool? canLike;
  final bool? canComment;
  final bool commentRestricted;
  final DateTime? commentRestrictedUntil;
  final bool? canBookmark;
  final bool? canReport;
  final bool? canVote;
  final VoidCallback? onRequireAuth;
  final bool focusComments;
  final String? focusCommentId;
  final Future<void> Function(Post) onToggleLike;
  final Future<void> Function(Post) onToggleBookmark;
  final ValueChanged<String> onFeedback;
  final Future<void> Function(Post)? onDeletePost;
  final Future<void> Function(Post, String title, String content)? onEditPost;
  final Future<void> Function(String targetType, String targetId)? onReport;
  final PollRepository? pollRepository;
  final PublishRepository? publishRepository;
  final PlatformRepository? platformRepository;
  final bool canModerate;
  final ValueChanged<String>? onOpenUserId;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _composerController = CommentComposerController();
  final commentsKey = GlobalKey();
  final commentsScrollController = ScrollController();
  bool isSending = false;
  bool hasFocusedComments = false;
  Comment? replyTarget;
  String? highlightedCommentId;
  Timer? _highlightTimer;
  Timer? _threadOpenTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.controller.load();
      widget.commentsController.load();
    });
    commentsScrollController.addListener(_loadMoreComments);
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _threadOpenTimer?.cancel();
    _composerController.dispose();
    commentsScrollController
      ..removeListener(_loadMoreComments)
      ..dispose();
    super.dispose();
  }

  void _loadMoreComments() {
    if (commentsScrollController.position.extentAfter < 240) {
      widget.commentsController.loadMore();
    }
  }

  Future<void> _submitReply(Post post) async {
    if (!widget.isAuthenticated) {
      widget.onRequireAuth?.call();
      return;
    }
    if (widget.canComment == false) {
      widget.onFeedback(_commentBlockedMessage);
      return;
    }
    if (isSending) return;
    final draft = _composerController.draft;
    if (draft.isEmpty) return;

    final comments = widget.commentsController;
    setState(() => isSending = true);
    final target = replyTarget;
    final before = post.commentCount;

    try {
      List<String> mediaIds = const [];
      if (draft.localImage != null) {
        final file = draft.localImage!;
        final bytes = await file.readAsBytes();
        final lower = file.name.toLowerCase();
        final mimeType = lower.endsWith('.png')
            ? 'image/png'
            : (lower.endsWith('.webp') ? 'image/webp' : 'image/jpeg');
        final digest = sha256.convert(bytes).toString();
        if (widget.publishRepository != null) {
          final ticket = await widget.publishRepository!.requestMediaUpload(
            fileName: file.name,
            mimeType: mimeType,
            size: bytes.length,
            sha256: digest,
          );
          await widget.publishRepository!.uploadMedia(
            ticket: ticket,
            bytes: bytes,
            size: bytes.length,
            sha256: digest,
          );
          mediaIds = [ticket.mediaId];
        } else {
          mediaIds = [file.path];
        }
      }

      final stickerId = draft.sticker?.id;

      if (target == null) {
        await comments.addComment(
          draft.text,
          mediaIds: mediaIds,
          stickerId: stickerId,
        );
      } else {
        await comments.replyTo(
          target,
          draft.text,
          replyToUserId: target.authorId,
          mediaIds: mediaIds,
          stickerId: stickerId,
        );
      }
      if (post.commentCount == before) post.commentCount = before + 1;
      if (!mounted) return;
      setState(() {
        _composerController.reset();
        replyTarget = null;
      });
      widget.onFeedback('回复已发布');
    } catch (error) {
      if (mounted) {
        widget.onFeedback(userFacingApiMessage(error, fallback: '回复失败，请重试'));
      }
    } finally {
      if (mounted) setState(() => isSending = false);
    }
  }

  String get _commentBlockedMessage {
    if (widget.commentRestricted) {
      final until = widget.commentRestrictedUntil;
      if (until == null) return '你已被永久禁言，仍可浏览内容';
      return '你已被禁言至 ${_formatDateTime(until)}，仍可浏览内容';
    }
    return '当前身份暂不能评论，请登录邮箱账号后重试';
  }

  void _focusCommentsIfNeeded(List<Comment> allComments) {
    if ((!widget.focusComments && widget.focusCommentId == null) ||
        hasFocusedComments) {
      return;
    }
    final targetId = widget.focusCommentId;
    if (targetId != null) {
      // 楼层视图只下发根评论 + 前 3 条回复预览；先在两层内查找目标。
      Comment? target;
      Comment? rootComment;
      bool isNested = false;
      for (final comment in allComments) {
        if (comment.id == targetId) {
          target = comment;
          rootComment = comment;
          break;
        }
        for (final reply in comment.replyPreview) {
          if (reply.id == targetId) {
            target = reply;
            rootComment = comment;
            isNested = true;
            break;
          }
        }
        if (target != null) break;
      }
      if (target == null &&
          widget.commentsController.hasMore &&
          !widget.commentsController.isLoadingMore) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.commentsController.loadMore();
        });
        return;
      }
      if (target == null) {
        // 目标超出预览范围（深层回复）：退化为滚动到评论区。
        hasFocusedComments = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final context = commentsKey.currentContext;
          if (mounted && context != null) {
            Scrollable.ensureVisible(
              context,
              duration: AppMotion.normal,
              alignment: 0.08,
            );
          }
        });
        return;
      }

      hasFocusedComments = true;
      final rootCommentId = target.rootId ?? target.parentId ?? target.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = GlobalObjectKey(
          'comment:$rootCommentId',
        ).currentContext;
        if (mounted && context != null) {
          Scrollable.ensureVisible(
            context,
            duration: AppMotion.normal,
            alignment: 0.1,
          );
        }
        if (isNested) {
          _threadOpenTimer?.cancel();
          _threadOpenTimer = Timer(const Duration(milliseconds: 350), () {
            if (mounted) {
              _openReplyThread(rootComment!, focusReplyId: targetId);
            }
          });
        } else {
          setState(() => highlightedCommentId = targetId);
          _highlightTimer?.cancel();
          _highlightTimer = Timer(AppMotion.highlightFade, () {
            if (mounted) setState(() => highlightedCommentId = null);
          });
        }
      });
    } else if (widget.focusComments) {
      hasFocusedComments = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = commentsKey.currentContext;
        if (mounted && context != null) {
          Scrollable.ensureVisible(
            context,
            duration: AppMotion.normal,
            alignment: 0.08,
          );
        }
      });
    }
  }

  void _openReplyThread(Comment comment, {String? focusReplyId}) {
    final post = widget.controller.state.detail?.post;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CommentThreadScreen(
        rootComment: comment,
        repository: widget.commentsController.repository,
        postAuthorId: post?.authorId,
        focusReplyId: focusReplyId,
        isAuthenticated: widget.isAuthenticated,
        onRequireAuth: widget.onRequireAuth,
        canComment: widget.canComment ?? widget.isAuthenticated,
        blockedMessage: _commentBlockedMessage,
        onAuthorTap: widget.onOpenUserId,
        onReplyDraft: (target, draft) async {
          List<String> mediaIds = const [];
          if (draft.localImage != null) {
            final file = draft.localImage!;
            final bytes = await file.readAsBytes();
            final lower = file.name.toLowerCase();
            final mimeType = lower.endsWith('.png')
                ? 'image/png'
                : (lower.endsWith('.webp') ? 'image/webp' : 'image/jpeg');
            final digest = sha256.convert(bytes).toString();
            if (widget.publishRepository != null) {
              final ticket = await widget.publishRepository!.requestMediaUpload(
                fileName: file.name,
                mimeType: mimeType,
                size: bytes.length,
                sha256: digest,
              );
              await widget.publishRepository!.uploadMedia(
                ticket: ticket,
                bytes: bytes,
                size: bytes.length,
                sha256: digest,
              );
              mediaIds = [ticket.mediaId];
            } else {
              mediaIds = [file.path];
            }
          }
          final stickerId = draft.sticker?.id;
          return widget.commentsController.replyTo(
            target,
            draft.text,
            replyToUserId: target.authorId,
            mediaIds: mediaIds,
            stickerId: stickerId,
          );
        },
        onReply: (target, content) => widget.commentsController.replyTo(
          target,
          content,
          replyToUserId: target.authorId,
        ),
        onToggleLike: (reply) => _likeComment(reply),
        onToggleDislike: (reply) => _dislikeComment(reply),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final detailPostId = state.detail?.post.id;
    // 评论点赞仍走全局通知；本帖点赞/收藏走帖子维度的细粒度通知。
    final listenables = <Listenable>[
      widget.controller,
      widget.commentsController,
      widget.interactionController,
      if (detailPostId != null)
        widget.interactionController.interactionsFor(detailPostId),
    ];

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
        final commentsController = widget.commentsController;
        final allComments = commentsController.items;
        _focusCommentsIfNeeded(allComments);

        return Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            titleSpacing: 0,
            title: Text(
              post.community?.name ?? post.tag,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  color: AppTheme.textPrimary,
                  size: 22,
                ),
                onPressed: () => _showPostMenu(post),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: CustomScrollView(
                  controller: commentsScrollController,
                  slivers: [
                    // 帖子主体
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ForumAuthorRow(
                              post: post,
                              onAuthorTap: widget.onOpenUserId,
                            ),
                            const SizedBox(height: 12),
                            if (post.isPinned ||
                                post.isFeatured ||
                                post.extraTag == '精华') ...[
                              _Tag(
                                text: post.isPinned ? '置顶' : '精华',
                                color: post.isPinned
                                    ? AppTheme.pink
                                    : AppTheme.orange,
                              ),
                              const SizedBox(height: 8),
                            ],
                            Text(
                              post.title,
                              style: const TextStyle(
                                fontSize: 20,
                                height: 1.38,
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              post.body,
                              style: const TextStyle(
                                color: Color(0xFF243647),
                                fontSize: 15.5,
                                height: 1.72,
                                letterSpacing: 0.1,
                              ),
                            ),
                            if (post.type == PostType.poll &&
                                widget.pollRepository != null)
                              _PollPanel(
                                repository: widget.pollRepository!,
                                postId: post.id,
                                isAuthenticated: widget.isAuthenticated,
                                canVote: widget.canVote,
                                onRequireAuth: widget.onRequireAuth,
                              ),
                            if (post.images.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              PostMediaPreview(
                                images: post.images,
                                mode: PostMediaPreviewMode.detail,
                                onImageTap: (index) =>
                                    Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => MediaGalleryScreen(
                                          images: post.images,
                                          initialIndex: index,
                                        ),
                                      ),
                                    ),
                              ),
                            ],
                            const SizedBox(height: 14),

                            // 浏览与统计栏
                            Row(
                              children: [
                                const Icon(
                                  Icons.visibility_outlined,
                                  color: AppTheme.textSecondary,
                                  size: 15,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${post.views} 浏览',
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 11.5,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  color: AppTheme.textSecondary,
                                  size: 15,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${post.comments} 回复',
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 11.5,
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
                                  size: 15,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${post.likeCount} 赞',
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 32, color: AppTheme.border),
                          ],
                        ),
                      ),
                    ),

                    // 评论区标题
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              key: commentsKey,
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '评论 ${post.comments}',
                                    style: const TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      _CommentSortChip(
                                        label: '热门',
                                        selected:
                                            commentsController.sort ==
                                            CommentSort.hot,
                                        onTap: () => commentsController
                                            .setSort(CommentSort.hot),
                                      ),
                                      const SizedBox(width: 6),
                                      _CommentSortChip(
                                        label: '顺序',
                                        selected:
                                            commentsController.sort ==
                                            CommentSort.asc,
                                        onTap: () => commentsController
                                            .setSort(CommentSort.asc),
                                      ),
                                      const SizedBox(width: 6),
                                      _CommentSortChip(
                                        label: '倒序',
                                        selected:
                                            commentsController.sort ==
                                            CommentSort.desc,
                                        onTap: () => commentsController
                                            .setSort(CommentSort.desc),
                                      ),
                                      const Spacer(),
                                      if (post.authorId.isNotEmpty)
                                        _CommentSortChip(
                                          label: '只看楼主',
                                          selected:
                                              commentsController.authorFilter !=
                                              null,
                                          onTap: () => commentsController
                                              .setAuthorFilter(
                                                commentsController
                                                            .authorFilter ==
                                                        null
                                                    ? post.authorId
                                                    : null,
                                              ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (commentsController.isLoading &&
                                allComments.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: CommentSkeleton(itemCount: 3),
                              ),
                            if (commentsController.errorMessage != null &&
                                allComments.isEmpty)
                              _CommentError(onRetry: commentsController.load),
                            if (allComments.isEmpty &&
                                !commentsController.isLoading)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 40,
                                ),
                                child: Center(
                                  child: Text(
                                    commentsController.authorFilter != null
                                        ? '楼主还没有回复'
                                        : '还没有回复，来抢沙发吧',
                                    style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    // 一级评论列表
                    if (allComments.isNotEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        sliver: SliverList.separated(
                          itemCount: allComments.length,
                          separatorBuilder: (context, index) => const Divider(
                            height: 1,
                            thickness: 1,
                            color: Color(0xFFEDF2F6),
                          ),
                          itemBuilder: (context, index) {
                            final comment = allComments[index];
                            final isHighlighted =
                                highlightedCommentId == comment.id;
                            final isFirst = index == 0;
                            final isLast = index == allComments.length - 1;
                            final side = BorderSide(color: AppTheme.border);

                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border(
                                  top: isFirst ? side : BorderSide.none,
                                  left: side,
                                  right: side,
                                  bottom: isLast ? side : BorderSide.none,
                                ),
                                borderRadius: BorderRadius.vertical(
                                  top: isFirst
                                      ? const Radius.circular(
                                          AppTheme.radiusMedium,
                                        )
                                      : Radius.zero,
                                  bottom: isLast
                                      ? const Radius.circular(
                                          AppTheme.radiusMedium,
                                        )
                                      : Radius.zero,
                                ),
                              ),
                              child: CommentItem(
                                key: GlobalObjectKey('comment:${comment.id}'),
                                comment: comment,
                                floor: index + 2,
                                replies: comment.replyPreview,
                                isHighlighted: isHighlighted,
                                isPostAuthor:
                                    post.authorId == comment.authorId,
                                onAuthorTap: widget.onOpenUserId,
                                onReply: () {
                                  setState(() => replyTarget = comment);
                                  _composerController.openReply(
                                    parentCommentId: comment.id,
                                    replyToUserId: comment.authorId,
                                    replyToName: comment.author?.nickname,
                                  );
                                },
                                onReplyTo: (target) {
                                  setState(() => replyTarget = target);
                                  _composerController.openReply(
                                    parentCommentId: target.id,
                                    replyToUserId: target.authorId,
                                    replyToName: target.author?.nickname,
                                  );
                                },
                                onLike: () => _likeComment(comment),
                                onDislike: () => _dislikeComment(comment),
                                onMore: () => _showCommentMenu(comment),
                                onViewAllReplies: () =>
                                    _openReplyThread(comment),
                              ),
                            );
                          },
                        ),
                      ),

                    // 评论分页状态
                    if (commentsController.isLoadingMore)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(14),
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                      ),
                    if (commentsController.errorMessage != null &&
                        allComments.isNotEmpty &&
                        !commentsController.isLoadingMore)
                      SliverToBoxAdapter(
                        child: Center(
                          child: TextButton(
                            onPressed: commentsController.loadMore,
                            child: const Text(
                              '加载更多失败，点击重试',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (!commentsController.hasMore && allComments.isNotEmpty)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 18),
                          child: Center(
                            child: Text(
                              '已经到底啦',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // 底部评论输入栏
              CommentReplyBar(
                composerController: _composerController,
                target: replyTarget,
                sending: isSending,
                isAuthenticated: widget.isAuthenticated,
                canComment: widget.canComment ?? widget.isAuthenticated,
                onRequireAuth: widget.onRequireAuth,
                blockedMessage: _commentBlockedMessage,
                onFeedback: widget.onFeedback,
                onCancelTarget: () => setState(() => replyTarget = null),
                onSubmit: () => _submitReply(post),
                commentCount: post.comments,
                likeCount: post.likeCount,
                isLiked: post.isLiked,
                isBookmarked: post.isBookmarked,
                onToggleLike: () => _toggleLike(post),
                onToggleBookmark: () => _toggleBookmark(post),
                onScrollToComments: () {
                  final context = commentsKey.currentContext;
                  if (context != null) {
                    Scrollable.ensureVisible(
                      context,
                      duration: AppMotion.normal,
                      alignment: 0.08,
                    );
                  }
                },
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

  Future<void> _toggleLike(Post post) async {
    if (widget.canLike == false) {
      if (!widget.isAuthenticated) {
        widget.onRequireAuth?.call();
      } else {
        widget.onFeedback('当前身份暂不能点赞，请登录邮箱账号后重试');
      }
      return;
    }
    await widget.onToggleLike(post);
  }

  Future<void> _toggleBookmark(Post post) async {
    if (widget.canBookmark == false) {
      if (!widget.isAuthenticated) {
        widget.onRequireAuth?.call();
      } else {
        widget.onFeedback('游客模式只能浏览、评论和举报，登录邮箱账号后才能收藏');
      }
      return;
    }
    await widget.onToggleBookmark(post);
  }

  Future<void> _likeComment(Comment comment) async {
    if (!widget.isAuthenticated) {
      widget.onRequireAuth?.call();
      return;
    }
    if (widget.canLike == false) {
      widget.onFeedback('当前身份暂不能点赞，请登录邮箱账号后重试');
      return;
    }
    try {
      await widget.interactionController.toggleCommentLike(comment);
    } catch (error) {
      if (mounted) widget.onFeedback(userFacingApiMessage(error));
    }
  }

  Future<void> _dislikeComment(Comment comment) async {
    if (!widget.isAuthenticated) {
      widget.onRequireAuth?.call();
      return;
    }
    if (widget.canLike == false) {
      widget.onFeedback('当前身份暂不能点踩，请登录邮箱账号后重试');
      return;
    }
    try {
      await widget.interactionController.toggleCommentDislike(comment);
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
      backgroundColor: Colors.white,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(
                post.isLiked
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: post.isLiked ? AppTheme.pink : AppTheme.textSecondary,
              ),
              title: Text(post.isLiked ? '取消点赞' : '点赞帖子'),
              onTap: () {
                Navigator.pop(sheetContext);
                _runInteraction(() => _toggleLike(post));
              },
            ),
            ListTile(
              leading: Icon(
                post.isBookmarked
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                color: post.isBookmarked
                    ? AppTheme.primary
                    : AppTheme.textSecondary,
              ),
              title: Text(post.isBookmarked ? '取消收藏' : '收藏帖子'),
              onTap: () {
                Navigator.pop(sheetContext);
                _runInteraction(() => _toggleBookmark(post));
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('分享帖子'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final shareUrl = AppLinks.post(post.id);
                try {
                  await Share.share(shareUrl, subject: '分享帖子');
                } catch (_) {
                  await Clipboard.setData(ClipboardData(text: shareUrl));
                  widget.onFeedback('系统分享不可用，帖子链接已复制');
                }
              },
            ),
            if (widget.platformRepository != null && widget.canModerate)
              ListTile(
                leading: Icon(
                  post.isRecommended
                      ? Icons.remove_circle_outline
                      : Icons.push_pin_outlined,
                  color: AppTheme.primary,
                ),
                title: Text(post.isRecommended ? '移出首页推荐' : '加入首页推荐'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  try {
                    if (post.isRecommended) {
                      await widget.platformRepository!.removeHomeRecommendation(post.id);
                    } else {
                      await widget.platformRepository!.setHomeRecommendation(
                        postId: post.id,
                      );
                    }
                    if (!mounted) return;
                    widget.onFeedback(
                      post.isRecommended ? '已移出首页推荐' : '已加入首页推荐',
                    );
                    await widget.controller.load();
                  } catch (error) {
                    if (mounted) {
                      widget.onFeedback(
                        userFacingApiMessage(error, fallback: '推荐操作失败，请稍后重试'),
                      );
                    }
                  }
                },
              ),
            if (widget.onReport != null)
              ListTile(
                leading: const Icon(
                  Icons.flag_outlined,
                  color: AppTheme.orange,
                ),
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
        widget.onEditPost == null) {
      return;
    }
    try {
      await widget.onEditPost!(post, value.$1, value.$2);
      if (mounted) widget.onFeedback('帖子已更新');
    } catch (error) {
      if (mounted) {
        widget.onFeedback(userFacingApiMessage(error, fallback: '编辑失败，请重试'));
      }
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
      if (mounted) {
        widget.onFeedback(userFacingApiMessage(error, fallback: '删除失败，请重试'));
      }
    }
  }

  void _showCommentMenu(Comment comment) {
    final canEdit =
        widget.currentUserId != null &&
        comment.authorId == widget.currentUserId;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            if (widget.onReport != null)
              ListTile(
                leading: const Icon(
                  Icons.flag_outlined,
                  color: AppTheme.orange,
                ),
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
    if (!widget.isAuthenticated) {
      widget.onRequireAuth?.call();
      return;
    }
    if (widget.canReport == false) {
      widget.onFeedback('当前身份暂不能举报');
      return;
    }
    try {
      if (widget.onReport != null) {
        await widget.onReport!(targetType, targetId);
        if (mounted) widget.onFeedback('举报已提交，我们会尽快处理');
      }
    } catch (error) {
      if (mounted) {
        widget.onFeedback(userFacingApiMessage(error, fallback: '举报失败，请稍后重试'));
      }
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
    if (value == null || value.isEmpty) {
      return;
    }
    try {
      final updated = await widget.commentsController.edit(comment, value);
      if (updated == null) widget.onFeedback('当前模式暂不支持编辑评论');
    } catch (error) {
      if (mounted) {
        widget.onFeedback(userFacingApiMessage(error, fallback: '评论编辑失败，请重试'));
      }
    }
  }

  Future<void> _deleteComment(Comment comment) async {
    final state = widget.controller.state;
    final post = state.detail?.post;
    if (post == null) return;
    final before = post.commentCount;
    try {
      await widget.commentsController.delete(comment);
      if (post.commentCount == before && before > 0) {
        post.commentCount = before - 1;
      }
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        widget.onFeedback(userFacingApiMessage(error, fallback: '删除失败，请重试'));
      }
    }
  }
}

class _PollPanel extends StatefulWidget {
  const _PollPanel({
    required this.repository,
    required this.postId,
    required this.isAuthenticated,
    this.canVote,
    this.onRequireAuth,
  });

  final PollRepository repository;
  final String postId;
  final bool isAuthenticated;
  final bool? canVote;
  final VoidCallback? onRequireAuth;

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
      if (mounted) {
        setState(() {
          voted = true;
        });
      }
      if (mounted) {
        setState(() => future = widget.repository.getPoll(widget.postId));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('投票失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>?>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: LinearProgressIndicator(),
        );
      }
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
      final viewerState = value['viewer_state'] is Map
          ? Map<String, dynamic>.from(value['viewer_state'] as Map)
          : const <String, dynamic>{};
      final viewerVoted = viewerState['has_voted'] == true;
      final canVote = viewerState['can_vote'] != false;
      final authenticationRequired =
          !widget.isAuthenticated ||
          viewerState['authentication_required'] == true;
      final locked =
          voted ||
          viewerVoted ||
          !canVote ||
          authenticationRequired ||
          widget.canVote == false;
      final viewerOptionIds = viewerState['option_ids'] is List
          ? (viewerState['option_ids'] as List).whereType<String>().toSet()
          : const <String>{};

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
            if (allowMultiple)
              ...options.map((option) {
                final id = '${option['id'] ?? ''}';
                final count = option['vote_count'] is num
                    ? (option['vote_count'] as num).toInt()
                    : 0;
                return CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: (viewerVoted ? viewerOptionIds : selected).contains(
                    id,
                  ),
                  onChanged: locked
                      ? null
                      : (value) => setState(() {
                          if (value == true) {
                            selected.add(id);
                          } else {
                            selected.remove(id);
                          }
                        }),
                  title: Text('${option['label'] ?? ''}'),
                  secondary: locked ? Text('$count') : null,
                );
              })
            else
              RadioGroup<String>(
                groupValue: selected.isEmpty ? null : selected.first,
                onChanged: locked
                    ? (_) {}
                    : (value) => setState(() {
                        if (value != null) {
                          selected
                            ..clear()
                            ..add(value);
                        }
                      }),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...options.map((option) {
                      final id = '${option['id'] ?? ''}';
                      final count = option['vote_count'] is num
                          ? (option['vote_count'] as num).toInt()
                          : 0;
                      return RadioListTile<String>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: id,
                        title: Text('${option['label'] ?? ''}'),
                        secondary: locked ? Text('$count') : null,
                      );
                    }),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: submitting
                    ? null
                    : authenticationRequired
                    ? widget.onRequireAuth
                    : locked
                    ? null
                    : () => _vote(pollId, allowMultiple, options),
                child: Text(
                  authenticationRequired
                      ? '登录后参与投票'
                      : viewerVoted || voted
                      ? '已投票'
                      : !canVote
                      ? '投票已结束'
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

class _CommentSortChip extends StatelessWidget {
  const _CommentSortChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? AppTheme.primary : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: selected ? Colors.white : AppTheme.textSecondary,
        ),
      ),
    ),
  );
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

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}
