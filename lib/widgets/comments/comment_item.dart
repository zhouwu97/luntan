import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import '../app_network_image.dart';
import '../link_text.dart';
import 'comment_common_widgets.dart';
import 'comment_more_button.dart';
import 'comment_reply_preview.dart';
import 'emoji/sticker_catalog.dart';

/// 单条一级评论展示项。
///
/// 视觉设计：
/// - 顶部单据行：头像、昵称、等级标签、楼主专属徽章、相对时间与楼层序号。
/// - 内容区：正文（支持网址点击）、多图网格 / 单图等比缩放、贴纸表情。
/// - 操作栏：点赞、踩、回复、更多按钮，具备舒适的触控热区（>= 36dp）。
/// - 嵌套：展开/折叠式二级回复内嵌预览（`CommentReplyPreview`）。
class CommentItem extends StatefulWidget {
  const CommentItem({
    super.key,
    required this.comment,
    required this.floor,
    this.replies = const [],
    this.isHighlighted = false,
    this.isPostAuthor = false,
    this.onReply,
    this.onLike,
    this.onDislike,
    this.onMore,
    this.onAuthorTap,
    this.onReplyTo,
    this.onReplyTap,
    this.onViewAllReplies,
    this.onReplyMore,
    this.onLongPress,
  });

  final Comment comment;
  final int floor;
  final List<Comment> replies;
  final bool isHighlighted;
  final bool isPostAuthor;
  final VoidCallback? onReply;
  final VoidCallback? onLike;
  final VoidCallback? onDislike;
  final VoidCallback? onMore;
  final ValueChanged<String>? onAuthorTap;
  final ValueChanged<Comment>? onReplyTo;
  final ValueChanged<Comment>? onReplyTap;
  final VoidCallback? onViewAllReplies;
  final ValueChanged<Comment>? onReplyMore;
  final VoidCallback? onLongPress;

  @override
  State<CommentItem> createState() => _CommentItemState();
}

class _CommentItemState extends State<CommentItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _highlightController;
  late final Animation<Color?> _highlightAnimation;

  @override
  void initState() {
    super.initState();
    _highlightController = AnimationController(
      vsync: this,
      duration: AppMotion.highlightFade,
    );
    _highlightAnimation = ColorTween(
      begin: const Color(0xFFEDF6FF),
      end: Colors.white,
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
  void didUpdateWidget(covariant CommentItem oldWidget) {
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

  @override
  Widget build(BuildContext context) {
    final comment = widget.comment;
    final deleted =
        comment.publicationStatus == CommentPublicationStatus.deleted;
    final author =
        comment.author?.nickname ??
        (comment.authorId.startsWith('guest') ? '游客' : '匿名用户');
    final level =
        comment.author?.level ??
        (comment.authorId.startsWith('guest') || comment.authorId.isEmpty
            ? 0
            : 1);
    final avatar = comment.author?.avatar?.trim();

    return AnimatedBuilder(
      animation: _highlightAnimation,
      builder: (context, child) {
        final cardColor = widget.isHighlighted
            ? (_highlightAnimation.value ?? Colors.white)
            : Colors.white;

        return GestureDetector(
          onLongPress: widget.onLongPress,
          child: Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFFE3EAF2),
                width: 1.0,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: child,
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部：头像 + 昵称（统一点击热区，支持跳转个人主页）
          if (!deleted)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CommentAvatar(
                  name: author,
                  avatarUrl: avatar,
                  size: 36,
                  onTap: widget.onAuthorTap != null ? _handleAuthorTap : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: InkWell(
                              onTap: widget.onAuthorTap != null
                                  ? _handleAuthorTap
                                  : null,
                              borderRadius: BorderRadius.circular(4),
                              child: Text(
                                author,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          UserLevelBadge(level: level, fontSize: 8.5),
                          if (widget.isPostAuthor) ...[
                            const SizedBox(width: 5),
                            const PostAuthorBadge(fontSize: 8.5),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            relativeTimeLabel(comment.createdAt),
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Color(0xFF9AA9B8),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4.5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '#${comment.floor ?? widget.floor}',
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF7E8E9E),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

          // 正文区域（与头部对齐，左边距 46）
          if (!deleted)
            Padding(
              padding: const EdgeInsets.only(left: 46, top: 6, right: 4),
              child: LinkText(
                comment.content,
                selectable: true,
                style: const TextStyle(
                  fontSize: 14.5,
                  color: AppTheme.textPrimary,
                  height: 1.58,
                ),
              ),
            ),

          // 多媒体图片预览
          if (!deleted && comment.media.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 46, top: 8),
              child: _buildMediaGrid(context, comment.media),
            ),

          // 贴纸表情预览
          if (!deleted &&
              comment.stickerId != null &&
              comment.stickerId!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 46, top: 8),
              child: _buildStickerView(comment.stickerId!),
            ),

          // 操作栏（回复、点赞、踩、更多，触控热区 >= 36dp）
          if (!deleted)
            Padding(
              padding: const EdgeInsets.only(left: 46, top: 4),
              child: Row(
                children: [
                  CommentActionButton(
                    icon: Icons.reply_rounded,
                    label: '回复',
                    onTap: widget.onReply,
                  ),
                  const SizedBox(width: 8),
                  CommentActionButton(
                    icon: comment.isDisliked
                        ? Icons.thumb_down_rounded
                        : Icons.thumb_down_off_alt_rounded,
                    label: comment.dislikeCount > 0
                        ? '${comment.dislikeCount}'
                        : null,
                    onTap: widget.onDislike,
                    isActive: comment.isDisliked,
                    activeColor: const Color(0xFF5A7B9C),
                  ),
                  const SizedBox(width: 8),
                  CommentActionButton(
                    icon: comment.isLiked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    label: '${comment.likeCount}',
                    onTap: widget.onLike,
                    isActive: comment.isLiked,
                    activeColor: AppTheme.pink,
                  ),
                  const Spacer(),
                  if (widget.onMore != null)
                    CommentMoreButton(onPressed: widget.onMore!),
                ],
              ),
            ),

          // 墓碑占位：正文已由服务端清空，回复仍可见
          if (deleted)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 2),
              child: Row(
                children: [
                  const Icon(
                    Icons.delete_outline_rounded,
                    size: 14,
                    color: Color(0xFFA0AFBD),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    '该评论已删除',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${comment.floor ?? widget.floor} 楼',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFFA0AFBD),
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
              onReplyTap: widget.onReplyTap,
              onAuthorTap: widget.onAuthorTap,
              onMore: widget.onReplyMore,
            ),
        ],
      ),
    );
  }

  Widget _buildMediaGrid(BuildContext context, List<MediaAsset> mediaList) {
    if (mediaList.isEmpty) return const SizedBox.shrink();

    if (mediaList.length == 1) {
      final media = mediaList.first;
      final imageUrl = media.previewUrl ?? '';
      if (imageUrl.isEmpty) return const SizedBox.shrink();
      return GestureDetector(
        onTap: () => _openImagePreview(context, media.originalUrl ?? imageUrl),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 210, maxHeight: 210),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF0F6),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2EAF2), width: 0.8),
            ),
            child: AppNetworkImage(
              url: imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_) => const Padding(
                padding: EdgeInsets.all(16),
                child: Icon(Icons.broken_image_outlined, color: Colors.grey),
              ),
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: mediaList.map((media) {
        final imageUrl = media.previewUrl ?? '';
        if (imageUrl.isEmpty) return const SizedBox.shrink();

        return GestureDetector(
          onTap: () => _openImagePreview(
            context,
            media.originalUrl ?? imageUrl,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF0F6),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2EAF2), width: 0.8),
              ),
              child: AppNetworkImage(
                url: imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_) => const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.grey,
                  size: 24,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStickerView(String stickerId) {
    final sticker = appStickerById(stickerId);
    if (sticker != null) {
      return Image.asset(
        sticker.thumbnailAsset,
        width: 96,
        height: 96,
        fit: BoxFit.contain,
      );
    }
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4F8),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.sticky_note_2_outlined,
        color: Colors.grey,
        size: 32,
      ),
    );
  }
}
