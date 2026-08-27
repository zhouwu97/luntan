import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import '../motion_tap_icon.dart';

class CommentReplyBar extends StatefulWidget {
  const CommentReplyBar({
    super.key,
    required this.controller,
    this.target,
    this.sending = false,
    this.isAuthenticated = true,
    this.canComment = true,
    this.onRequireAuth,
    required this.blockedMessage,
    required this.onFeedback,
    required this.onCancelTarget,
    required this.onSubmit,
    this.commentCount,
    this.likeCount,
    this.isLiked = false,
    this.isBookmarked = false,
    this.onToggleLike,
    this.onToggleBookmark,
    this.onScrollToComments,
    this.isSheetMode = false,
    this.focusNode,
  });

  final TextEditingController controller;
  final Comment? target;
  final bool sending;
  final bool isAuthenticated;
  final bool canComment;
  final VoidCallback? onRequireAuth;
  final String blockedMessage;
  final ValueChanged<String> onFeedback;
  final VoidCallback onCancelTarget;
  final VoidCallback onSubmit;

  // 详情页快捷互动字段
  final int? commentCount;
  final int? likeCount;
  final bool isLiked;
  final bool isBookmarked;
  final VoidCallback? onToggleLike;
  final VoidCallback? onToggleBookmark;
  final VoidCallback? onScrollToComments;
  final bool isSheetMode;
  final FocusNode? focusNode;

  @override
  State<CommentReplyBar> createState() => _CommentReplyBarState();
}

class _CommentReplyBarState extends State<CommentReplyBar> {
  late final FocusNode _internalFocusNode;
  bool _isEditing = false;

  FocusNode get _effectiveFocusNode => widget.focusNode ?? _internalFocusNode;

  @override
  void initState() {
    super.initState();
    _internalFocusNode = FocusNode();
    _effectiveFocusNode.addListener(_handleFocusChange);
    widget.controller.addListener(_handleTextChange);
    if (widget.target != null || widget.isSheetMode) {
      _isEditing = true;
    }
  }

  @override
  void didUpdateWidget(CommentReplyBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.target != null && oldWidget.target == null) {
      _isEditing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_effectiveFocusNode.hasFocus) {
          _effectiveFocusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _effectiveFocusNode.removeListener(_handleFocusChange);
    widget.controller.removeListener(_handleTextChange);
    if (widget.focusNode == null) {
      _internalFocusNode.dispose();
    }
    super.dispose();
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {
        if (_effectiveFocusNode.hasFocus) {
          _isEditing = true;
        } else if (widget.target == null &&
            widget.controller.text.isEmpty &&
            !widget.isSheetMode) {
          _isEditing = false;
        }
      });
    }
  }

  void _handleTextChange() {
    if (widget.controller.text.isNotEmpty && !_isEditing && mounted) {
      setState(() => _isEditing = true);
    }
  }

  void _activateEditing() {
    if (!widget.isAuthenticated) {
      widget.onRequireAuth?.call();
      return;
    }
    if (!widget.canComment) {
      widget.onFeedback(widget.blockedMessage);
      return;
    }
    setState(() => _isEditing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _effectiveFocusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final targetUser = widget.target?.author?.nickname ??
        (widget.target?.authorId.isNotEmpty == true ? '用户' : null);

    final showDetailActions = !widget.isSheetMode &&
        widget.commentCount != null &&
        widget.likeCount != null;

    final isExpanded = _isEditing || widget.target != null || widget.isSheetMode;

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
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 回复目标动态栏
            AnimatedSize(
              duration: AppMotion.fast,
              curve: AppMotion.standard,
              child: widget.target != null
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 6, left: 4),
                      child: Row(
                        children: [
                          Text(
                            '回复 @${targetUser ?? "用户"}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () {
                              widget.onCancelTarget();
                              if (widget.controller.text.isEmpty &&
                                  !widget.isSheetMode) {
                                _effectiveFocusNode.unfocus();
                                setState(() => _isEditing = false);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Color(0xFFEAF2F9),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                size: 13,
                                color: Color(0xFF6C8093),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),

            if (!isExpanded && showDetailActions)
              _buildDefaultBar(targetUser)
            else
              _buildActiveInputBar(targetUser),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultBar(String? targetUser) {
    return Row(
      children: [
        // 伪输入框入口
        Expanded(
          child: GestureDetector(
            onTap: _activateEditing,
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF4F7FA),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFDDE6F0)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  const Icon(
                    Icons.edit_note_rounded,
                    size: 18,
                    color: Color(0xFF8B9DB0),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    targetUser != null
                        ? '回复 @$targetUser…'
                        : '友善地回复一句…',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF8B9DB0),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),

        // 评论数快捷入口
        InkWell(
          onTap: widget.onScrollToComments ?? _activateEditing,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 18,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  '${widget.commentCount ?? 0}',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),

        // 点赞按钮
        InkWell(
          onTap: widget.onToggleLike,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                MotionTapIcon(
                  active: widget.isLiked,
                  activeIcon: Icons.favorite_rounded,
                  inactiveIcon: Icons.favorite_border_rounded,
                  activeColor: AppTheme.pink,
                  inactiveColor: AppTheme.textSecondary,
                  size: 18,
                ),
                const SizedBox(width: 4),
                Text(
                  '${widget.likeCount ?? 0}',
                  style: TextStyle(
                    color: widget.isLiked ? AppTheme.pink : AppTheme.textSecondary,
                    fontSize: 12.5,
                    fontWeight: widget.isLiked ? FontWeight.w700 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),

        // 收藏按钮
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: widget.onToggleBookmark,
          icon: MotionTapIcon(
            active: widget.isBookmarked,
            activeIcon: Icons.bookmark_rounded,
            inactiveIcon: Icons.bookmark_border_rounded,
            activeColor: AppTheme.primary,
            inactiveColor: AppTheme.textSecondary,
            size: 20,
          ),
          tooltip: '收藏帖子',
        ),
      ],
    );
  }

  Widget _buildActiveInputBar(String? targetUser) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F8FB),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFDDE7F0)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              child: TextField(
                focusNode: _effectiveFocusNode,
                controller: widget.controller,
                enabled: !widget.sending,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppTheme.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: widget.target != null
                      ? '回复 @${targetUser ?? "用户"}…'
                      : '友善地回复一句…',
                  hintStyle: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF899AAC),
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  filled: false,
                  isDense: true,
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) {
                  if (!widget.sending) widget.onSubmit();
                },
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 42,
          child: FilledButton(
            onPressed: widget.sending
                ? null
                : () {
                    if (!widget.isAuthenticated) {
                      widget.onRequireAuth?.call();
                      return;
                    }
                    if (!widget.canComment) {
                      widget.onFeedback(widget.blockedMessage);
                      return;
                    }
                    widget.onSubmit();
                  },
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
              elevation: 0,
            ),
            child: widget.sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    '发送',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

