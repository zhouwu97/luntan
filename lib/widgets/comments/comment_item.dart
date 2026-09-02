import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import '../app_network_image.dart';
import '../link_text.dart';
import 'comment_reply_preview.dart';
import 'comment_more_button.dart';
import 'emoji/sticker_catalog.dart';

class CommentItem extends StatefulWidget {
  const CommentItem({
    super.key,
    required this.comment,
    required this.floor,
    this.replies = const [],
    this.isHighlighted = false,
    this.isPostAuthor = false,
    this.onReply,
    this.onReplyTo,
    this.onLike,
    this.onDislike,
    this.onMore,
    this.onReplyMore,
    this.onViewAllReplies,
    this.onAuthorTap,
    this.onLongPress,
  });

  final Comment comment;
  final int floor;
  final List<Comment> replies;
  final bool isHighlighted;
  final bool isPostAuthor;
  final VoidCallback? onReply;
  final ValueChanged<Comment>? onReplyTo;
  final VoidCallback? onLike;
  final VoidCallback? onDislike;
  final VoidCallback? onMore;
  final ValueChanged<Comment>? onReplyMore;
  final VoidCallback? onViewAllReplies;
  final ValueChanged<String>? onAuthorTap;
  final VoidCallback? onLongPress;

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

  Color _levelColor(int level) {
    if (level >= 8) return AppTheme.purple;
    if (level >= 6) return AppTheme.primary;
    if (level >= 4) return AppTheme.mint;
    return AppTheme.textSecondary;
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
    var avatar = comment.author?.avatar?.trim();
    if (avatar == null || avatar.isEmpty) {
      avatar = UserAvatarCache.get(comment.authorId);
    } else {
      UserAvatarCache.set(comment.authorId, avatar);
    }

    final lvlColor = _levelColor(level);

    return AnimatedBuilder(
      animation: _highlightAnimation,
      builder: (context, child) {
        return GestureDetector(
          onLongPress: widget.onLongPress,
          child: Container(
            decoration: BoxDecoration(
              color: _highlightAnimation.value ?? Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: child,
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部：头像 + 昵称（统一点击热区，支持跳转个人主页）
          if (!deleted)
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
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textPrimary,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: lvlColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Lv.$level',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: lvlColor,
                                    height: 1.15,
                                  ),
                                ),
                              ),
                              if (widget.isPostAuthor) ...[
                                const SizedBox(width: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1.5,
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
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF2672D6),
                                      height: 1.1,
                                    ),
                                  ),
                                ),
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
                                  color: Color(0xFF94A5B7),
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${comment.floor ?? widget.floor} 楼',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF8C9EAF),
                                    height: 1.15,
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
              ),
            ),

          // 评论正文
          if (!deleted && comment.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 46, top: 4, right: 4),
              child: LinkText(
                comment.content,
                selectable: true,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textPrimary,
                  height: 1.6,
                ),
              ),
            ),

          // 评论图片展示
          if (!deleted && comment.media.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 46, top: 8),
              child: _buildMediaGrid(context, comment.media),
            ),

          // 评论贴纸展示
          if (!deleted &&
              comment.stickerId != null &&
              comment.stickerId!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 46, top: 8),
              child: _buildStickerView(comment.stickerId!),
            ),

          // 操作栏（回复、点赞、更多）
          if (!deleted)
            Padding(
              padding: const EdgeInsets.only(left: 46, top: 8),
              child: Row(
                children: [
                  InkWell(
                    onTap: widget.onReply,
                    borderRadius: BorderRadius.circular(6),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.reply_rounded,
                            size: 14.5,
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
                  ),
                  const SizedBox(width: 14),
                  InkWell(
                    onTap: widget.onDislike,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 3,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            comment.isDisliked
                                ? Icons.thumb_down_rounded
                                : Icons.thumb_down_off_alt_rounded,
                            size: 14,
                            color: comment.isDisliked
                                ? const Color(0xFF5A7B9C)
                                : AppTheme.textSecondary,
                          ),
                          if (comment.dislikeCount > 0) ...[
                            const SizedBox(width: 3),
                            Text(
                              '${comment.dislikeCount}',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: comment.isDisliked
                                    ? const Color(0xFF5A7B9C)
                                    : AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  InkWell(
                    onTap: widget.onLike,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 3,
                      ),
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

  Widget _buildCommentAvatar(
    BuildContext context,
    String? avatarUrl,
    String author,
  ) {
    const diameter = 36.0;
    final initial = author.isNotEmpty ? author.characters.first : '友';
    final placeholder = Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlue,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE2EBF5), width: 1.0),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: AppTheme.primary,
        ),
      ),
    );

    if (avatarUrl == null || avatarUrl.isEmpty) {
      return placeholder;
    }

    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE2EBF5), width: 1.0),
      ),
      child: ClipOval(
        child: AppNetworkImage(
          url: avatarUrl,
          fit: BoxFit.cover,
          width: diameter,
          height: diameter,
          placeholder: (_) => placeholder,
          errorBuilder: (_) => placeholder,
        ),
      ),
    );
  }
}
