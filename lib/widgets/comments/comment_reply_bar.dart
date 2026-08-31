import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../domain/models.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import '../motion_tap_icon.dart';
import 'comment_attachment_preview.dart';
import 'comment_composer_controller.dart';
import 'emoji/comment_emoji_panel.dart';

class CommentReplyBar extends StatefulWidget {
  const CommentReplyBar({
    super.key,
    this.controller,
    this.composerController,
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

  final TextEditingController? controller;
  final CommentComposerController? composerController;
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

class _CommentReplyBarState extends State<CommentReplyBar> with WidgetsBindingObserver {
  CommentComposerController? _internalComposer;
  final ImagePicker _picker = ImagePicker();
  bool _isEditing = false;

  CommentComposerController get _composer =>
      widget.composerController ?? (_internalComposer ??= CommentComposerController());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.composerController == null) {
      _internalComposer = CommentComposerController();
    }
    _syncControllerText();
    _composer.addListener(_handleComposerChange);
    if (widget.target != null || widget.isSheetMode) {
      _isEditing = true;
    }
  }

  void _syncControllerText() {
    if (widget.controller != null &&
        widget.controller!.text != _composer.textController.text) {
      _composer.textController.text = widget.controller!.text;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateMetricsFromView();
    });
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _updateMetricsFromView();
  }

  void _updateMetricsFromView() {
    if (!mounted) return;
    final view = View.maybeOf(context);
    if (view == null) return;
    final pixelRatio = view.devicePixelRatio;
    if (pixelRatio <= 0) return;
    final bottomInset = view.viewInsets.bottom / pixelRatio;
    _composer.updateKeyboardMetrics(bottomInset);
  }

  @override
  void didUpdateWidget(CommentReplyBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.target != null && oldWidget.target == null) {
      _isEditing = true;
      _composer.open();
    }
    _syncControllerText();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _composer.removeListener(_handleComposerChange);
    _internalComposer?.dispose();
    super.dispose();
  }

  void _handleComposerChange() {
    if (widget.controller != null &&
        widget.controller!.text != _composer.textController.text) {
      widget.controller!.text = _composer.textController.text;
    }
    if (mounted) setState(() {});
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
    _composer.open();
  }

  Future<void> _handlePickImage() async {
    if (!widget.isAuthenticated) {
      widget.onRequireAuth?.call();
      return;
    }
    if (!widget.canComment) {
      widget.onFeedback(widget.blockedMessage);
      return;
    }
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() => _isEditing = true);
        _composer.setLocalImage(image);
      }
    } catch (e) {
      widget.onFeedback('选择图片失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final targetUser = widget.target?.author?.nickname ??
        (widget.target?.authorId.isNotEmpty == true ? '用户' : null);

    final showDetailActions = !widget.isSheetMode &&
        widget.commentCount != null &&
        widget.likeCount != null;

    final isExpanded = _isEditing ||
        widget.target != null ||
        widget.isSheetMode ||
        _composer.isOpen ||
        _composer.showEmojiPanel ||
        !_composer.draft.isEmpty;

    final showEmoji = _composer.showEmojiPanel || _composer.inputHandoffActive;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: SafeArea(
        top: false,
        bottom: !showEmoji,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 附件预览栏（图片或贴纸）
            CommentAttachmentPreview(
              localImage: _composer.localImage,
              sticker: _composer.sticker,
              onRemoveImage: _composer.clearLocalImage,
              onRemoveSticker: _composer.clearSticker,
            ),

            // 回复目标动态提示
            AnimatedSize(
              duration: AppMotion.fast,
              curve: AppMotion.standard,
              child: widget.target != null
                  ? Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 2, left: 16, right: 16),
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
                              if (_composer.draft.isEmpty && !widget.isSheetMode) {
                                _composer.close();
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

            Padding(
              padding: EdgeInsets.fromLTRB(
                14,
                6,
                14,
                showEmoji ? 6 : 6,
              ),
              child: (!isExpanded && showDetailActions)
                  ? _buildDefaultBar(targetUser)
                  : _buildActiveInputBar(targetUser),
            ),

            // 表情/贴纸面板容器
            if (showEmoji)
              SizedBox(
                height: _composer.stableKeyboardHeight,
                child: CommentEmojiPanel(
                  enabled: !widget.sending,
                  onEmojiSelected: (emoji) => _composer.insertEmoji(emoji),
                  onBackspace: () => _composer.deleteBackward(),
                  onStickerSelected: (sticker) {
                    _composer.setSticker(sticker);
                  },
                ),
              ),
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
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFF2F3F5),
                borderRadius: BorderRadius.circular(21),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
    final canSubmit = !_composer.draft.isEmpty && !widget.sending;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 图片附件按钮
        IconButton(
          icon: Icon(
            Icons.image_outlined,
            color: _composer.localImage != null
                ? AppTheme.primary
                : const Color(0xFF6C8093),
            size: 22,
          ),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 42),
          tooltip: '添加图片',
          onPressed: widget.sending ? null : _handlePickImage,
        ),

        // 表情/贴纸面板切换按钮
        IconButton(
          icon: Icon(
            _composer.showEmojiPanel
                ? Icons.keyboard_alt_outlined
                : Icons.sentiment_satisfied_alt_rounded,
            color: _composer.showEmojiPanel || _composer.sticker != null
                ? AppTheme.primary
                : const Color(0xFF6C8093),
            size: 22,
          ),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 42),
          tooltip: '表情与贴纸',
          onPressed: widget.sending ? null : () => _composer.toggleEmoji(),
        ),
        const SizedBox(width: 4),

        // 输入框
        Expanded(
          child: SizedBox(
            height: 42,
            child: TextField(
              focusNode: _composer.focusNode,
              controller: _composer.textController,
              enabled: !widget.sending,
              minLines: 1,
              maxLines: 1,
              textAlignVertical: TextAlignVertical.center,
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
                filled: true,
                fillColor: const Color(0xFFF2F3F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(21),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(21),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(21),
                  borderSide: BorderSide.none,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 0,
                ),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) {
                if (canSubmit) widget.onSubmit();
              },
            ),
          ),
        ),
        const SizedBox(width: 8),

        // 发送按钮
        SizedBox(
          height: 42,
          child: FilledButton(
            onPressed: canSubmit
                ? () {
                    if (!widget.isAuthenticated) {
                      widget.onRequireAuth?.call();
                      return;
                    }
                    if (!widget.canComment) {
                      widget.onFeedback(widget.blockedMessage);
                      return;
                    }
                    widget.onSubmit();
                  }
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFDDE7F0),
              disabledForegroundColor: const Color(0xFF9CB1C4),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(21),
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
