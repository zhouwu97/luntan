import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import 'comment_reply_preview.dart';
import 'emoji/sticker_catalog.dart';

class CommentItem extends StatefulWidget {
  const CommentItem({
    super.key,
    required this.comment,
    required this.floor,
    this.replies = const [],
    this.isHighlighted = false,
    this.onReply,
    this.onReplyTo,
    this.onLike,
    this.onMore,
    this.onViewAllReplies,
    this.onAuthorTap,
  });

  final Comment comment;
  final int floor;
  final List<Comment> replies;
  final bool isHighlighted;
  final VoidCallback? onReply;
  final ValueChanged<Comment>? onReplyTo;
  final VoidCallback? onLike;
  final VoidCallback? onMore;
  final VoidCallback? onViewAllReplies;
  final ValueChanged<String>? onAuthorTap;

  @override
  State<CommentItem> createState() => _CommentItemState();
}

class _CommentItemState extends State<CommentItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _highlightController;
  late Animation<Color?> _highlightAnimation;

  @override
  void initState() {
    super.initState();
    _highlightController = AnimationController(
      vsync: this,
      duration: AppMotion.highlightFade,
    );
    _highlightAnimation =
        ColorTween(
          begin: const Color(0xFFEDF6FF),
          end: Colors.transparent,
        ).animate(
          CurvedAnimation(
            parent: _highlightController,
            curve: Curves.easeOutCubic,
          ),
        );

    if (widget.isHighlighted) {
      _highlightController.forward();
    }
  }

  @override
  void didUpdateWidget(CommentItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isHighlighted && !oldWidget.isHighlighted) {
      _highlightController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _highlightController.dispose();
    super.dispose();
  }

  void _handleAuthorTap() {
    final authorId = widget.comment.authorId;
    if (authorId.isNotEmpty && !authorId.startsWith('guest')) {
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
    final comment = widget.comment;
    final author = comment.author?.nickname ??
        (comment.authorId.startsWith('guest') ? '游客' : '匿名用户');
    final level = comment.author?.level ??
        (comment.authorId.startsWith('guest') || comment.authorId.isEmpty ? 0 : 1);
    final avatar = comment.author?.avatar?.trim();

    return AnimatedBuilder(
      animation: _highlightAnimation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            color: _highlightAnimation.value ?? Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: child,
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部：头像 + 昵称（统一点击热区，支持跳转个人主页）
          InkWell(
            onTap: widget.onAuthorTap != null ? _handleAuthorTap : null,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCommentAvatar(context, avatar, author),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                author,
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
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.levelBg,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Lv.$level',
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.levelText,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${widget.floor} 楼',
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: Color(0xFFA0AFBD),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          relativeTimeLabel(comment.createdAt),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF99A8B7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 评论正文
          if (comment.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 44, top: 4, right: 4),
              child: Text(
                comment.content,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textPrimary,
                  height: 1.6,
                ),
              ),
            ),

          // 评论图片展示
          if (comment.media.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 44, top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: comment.media.map((media) {
                  final imageUrl = media.url ?? media.detail?.url ?? media.thumb?.url ?? '';
                  if (imageUrl.isEmpty) return const SizedBox.shrink();

                  return GestureDetector(
                    onTap: () => _openImagePreview(context, imageUrl),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        constraints: const BoxConstraints(
                          maxWidth: 200,
                          maxHeight: 200,
                        ),
                        color: const Color(0xFFEAF0F6),
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Padding(
                            padding: EdgeInsets.all(16),
                            child: Icon(Icons.broken_image_outlined, color: Colors.grey),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

          // 评论贴纸展示
          if (comment.stickerId != null && comment.stickerId!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 44, top: 8),
              child: _buildStickerView(comment.stickerId!),
            ),

          // 操作栏（回复、点赞、更多）
          Padding(
            padding: const EdgeInsets.only(left: 44, top: 8),
            child: Row(
              children: [
                GestureDetector(
                  onTap: widget.onReply,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.reply_rounded,
                        size: 14,
                        color: AppTheme.textSecondary,
                      ),
                      SizedBox(width: 3),
                      Text(
                        '回复',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                GestureDetector(
                  onTap: widget.onLike,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        comment.isLiked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 14,
                        color: comment.isLiked
                            ? AppTheme.pink
                            : AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${comment.likeCount}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: comment.isLiked
                              ? AppTheme.pink
                              : AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (widget.onMore != null)
                  GestureDetector(
                    onTap: widget.onMore,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Icon(
                        Icons.more_horiz_rounded,
                        size: 16,
                        color: Color(0xFF9AAABD),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // 二级评论预览
          if (widget.replies.isNotEmpty || comment.replyCount > 0)
            CommentReplyPreview(
              replies: widget.replies,
              totalReplyCount: comment.replyCount,
              onOpenThread: widget.onViewAllReplies ?? () {},
              onReplyTo: widget.onReplyTo,
              onAuthorTap: widget.onAuthorTap,
            ),
        ],
      ),
    );
  }

  Widget _buildStickerView(String stickerId) {
    final sticker = appStickerById(stickerId);
    if (sticker != null) {
      return Image.asset(
        sticker.thumbnailAsset,
        width: 100,
        height: 100,
        fit: BoxFit.contain,
      );
    }
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4F8),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.sticky_note_2_outlined, color: Colors.grey, size: 36),
    );
  }

  Widget _buildCommentAvatar(
    BuildContext context,
    String? avatarUrl,
    String author,
  ) {
    const diameter = 34.0;
    final initial = author.isNotEmpty ? author.characters.first : '友';
    final placeholder = Container(
      width: diameter,
      height: diameter,
      decoration: const BoxDecoration(
        color: AppTheme.surfaceBlue,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 12,
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
        width: diameter,
        height: diameter,
        child: Image.network(
          avatarUrl,
          fit: BoxFit.cover,
          width: diameter,
          height: diameter,
          cacheWidth: (diameter * MediaQuery.devicePixelRatioOf(context)).round(),
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
