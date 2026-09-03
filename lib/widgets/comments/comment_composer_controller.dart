import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'emoji/sticker_catalog.dart';

enum CommentBottomPanel { none, keyboard, emoji }

/// Emoji → Keyboard 切换时的平滑过渡交接状态。
enum CommentInputHandoff { none, emojiToKeyboard }

class CommentDraft {
  const CommentDraft({
    required this.text,
    this.parentCommentId,
    this.replyToUserId,
    this.replyToName,
    this.sticker,
    this.localImages = const [],
    XFile? localImage,
  }) : _legacyLocalImage = localImage;

  final String text;
  final String? parentCommentId;
  final String? replyToUserId;
  final String? replyToName;
  final AppSticker? sticker;
  final List<XFile> localImages;
  final XFile? _legacyLocalImage;

  XFile? get localImage =>
      _legacyLocalImage ?? (localImages.isNotEmpty ? localImages.first : null);

  bool get isEmpty =>
      text.trim().isEmpty &&
      sticker == null &&
      localImages.isEmpty &&
      _legacyLocalImage == null;
}

class CommentComposerController extends ChangeNotifier {
  CommentComposerController() {
    // TextEditingController 的值变化不会自动冒泡到本控制器；同步转发后，
    // 发送按钮、字数和附件布局可以随用户输入立即重建。
    textController.addListener(_handleTextChanged);
  }

  final TextEditingController textController = TextEditingController();
  final FocusNode focusNode = FocusNode();

  bool _isOpen = false;
  CommentBottomPanel _bottomPanel = CommentBottomPanel.none;
  double _stableKeyboardHeight = 280;
  double _keyboardInset = 0;
  double _lastKeyboardInset = 0;
  bool _hasObservedKeyboardHeight = false;
  CommentInputHandoff _handoff = CommentInputHandoff.none;
  Timer? _handoffTimer;
  bool _disposing = false;

  String? _parentCommentId;
  String? _replyToUserId;
  String? _replyToName;
  AppSticker? _sticker;
  final List<XFile> _localImages = [];

  bool get isOpen => _isOpen;
  CommentBottomPanel get bottomPanel => _bottomPanel;
  bool get showEmojiPanel => _bottomPanel == CommentBottomPanel.emoji;
  double get stableKeyboardHeight => _stableKeyboardHeight;
  double get keyboardInset => _keyboardInset;
  bool get inputHandoffActive => _handoff != CommentInputHandoff.none;

  String? get parentCommentId => _parentCommentId;
  String? get replyToUserId => _replyToUserId;
  String? get replyToName => _replyToName;
  AppSticker? get sticker => _sticker;
  List<XFile> get localImages => List.unmodifiable(_localImages);
  XFile? get localImage => _localImages.isNotEmpty ? _localImages.first : null;

  CommentDraft get draft => CommentDraft(
    text: textController.text.trim(),
    parentCommentId: _parentCommentId,
    replyToUserId: _replyToUserId,
    replyToName: _replyToName,
    sticker: _sticker,
    localImages: List.unmodifiable(_localImages),
  );

  void updateKeyboardMetrics(double inset) {
    final normalizedInset = inset < 0 ? 0.0 : inset;
    final insetChanged = (_keyboardInset - normalizedInset).abs() > 0.1;
    final wasCollapsing = normalizedInset < _lastKeyboardInset;
    _lastKeyboardInset = normalizedInset;
    _keyboardInset = normalizedInset;

    if (_handoff == CommentInputHandoff.emojiToKeyboard) {
      if (normalizedInset > 0) {
        final target = _stableKeyboardHeight;
        if (normalizedInset >= target * 0.85 ||
            (target - normalizedInset).abs() <= 16) {
          _completeEmojiToKeyboardHandoff();
        } else if (insetChanged) {
          notifyListeners();
        }
      } else {
        _cancelHandoff();
      }
      return;
    }

    if (normalizedInset > 0) {
      if (!wasCollapsing &&
          (normalizedInset > _stableKeyboardHeight ||
              !_hasObservedKeyboardHeight)) {
        if (normalizedInset >= 180 || !_hasObservedKeyboardHeight) {
          _stableKeyboardHeight = normalizedInset;
          _hasObservedKeyboardHeight = true;
        }
      }
      final canShowKeyboardPanel =
          _isOpen ||
          focusNode.hasFocus ||
          _bottomPanel == CommentBottomPanel.keyboard;
      if (_bottomPanel != CommentBottomPanel.emoji && canShowKeyboardPanel) {
        _bottomPanel = CommentBottomPanel.keyboard;
      }
      if (insetChanged) {
        notifyListeners();
      }
    } else {
      if (_bottomPanel == CommentBottomPanel.keyboard) {
        _bottomPanel = CommentBottomPanel.none;
        notifyListeners();
      } else if (insetChanged) {
        notifyListeners();
      }
    }
  }

  void open() {
    _cancelHandoff();
    _isOpen = true;
    _bottomPanel = CommentBottomPanel.keyboard;
    notifyListeners();
    _focusAfterLayout();
  }

  void openRoot() {
    clearReplyTarget();
    open();
  }

  void setReplyTarget({
    required String parentCommentId,
    String? replyToUserId,
    String? replyToName,
  }) {
    _parentCommentId = parentCommentId;
    _replyToUserId = replyToUserId;
    _replyToName = replyToName?.trim();
    notifyListeners();
  }

  void openReply({
    required String parentCommentId,
    String? replyToUserId,
    String? replyToName,
  }) {
    _parentCommentId = parentCommentId;
    _replyToUserId = replyToUserId;
    _replyToName = replyToName?.trim();
    open();
  }

  void clearReplyTarget() {
    if (_parentCommentId == null &&
        _replyToName == null &&
        _replyToUserId == null) {
      return;
    }
    _parentCommentId = null;
    _replyToName = null;
    _replyToUserId = null;
    notifyListeners();
  }

  void setSticker(AppSticker? sticker) {
    if (_sticker?.id == sticker?.id) return;
    _sticker = sticker;
    if (sticker != null) {
      _localImages.clear(); // 贴纸与图片互斥单选附件
    }
    notifyListeners();
  }

  void clearSticker() {
    if (_sticker == null) return;
    _sticker = null;
    notifyListeners();
  }

  void addLocalImages(List<XFile> images) {
    for (final image in images) {
      if (_localImages.length >= 9) break;

      if (!_localImages.any((item) => item.path == image.path)) {
        _localImages.add(image);
      }
    }

    if (_localImages.isNotEmpty) {
      _sticker = null; // 贴纸与图片互斥
    }

    notifyListeners();
  }

  void removeLocalImageAt(int index) {
    if (index >= 0 && index < _localImages.length) {
      _localImages.removeAt(index);
      notifyListeners();
    }
  }

  void clearLocalImages() {
    if (_localImages.isEmpty) return;
    _localImages.clear();
    notifyListeners();
  }

  void setLocalImage(XFile? image) {
    _localImages.clear();
    if (image != null) {
      _localImages.add(image);
      _sticker = null; // 贴纸与图片互斥单选附件
    }
    notifyListeners();
  }

  void clearLocalImage() {
    clearLocalImages();
  }

  void insertEmoji(String emoji) {
    final text = textController.text;
    final selection = textController.selection;
    if (!selection.isValid || selection.isCollapsed) {
      final offset = selection.isValid ? selection.baseOffset : text.length;
      final newText = text.replaceRange(offset, offset, emoji);
      textController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: offset + emoji.length),
      );
    } else {
      final newText = text.replaceRange(selection.start, selection.end, emoji);
      textController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: selection.start + emoji.length,
        ),
      );
    }
  }

  void deleteBackward() {
    final text = textController.text;
    final selection = textController.selection;
    if (text.isEmpty) return;
    if (!selection.isValid || selection.isCollapsed) {
      final offset = selection.isValid ? selection.baseOffset : text.length;
      if (offset <= 0) return;
      final charRange = _previousCharacterRange(text, offset);
      final newText = text.replaceRange(charRange.start, charRange.end, '');
      textController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: charRange.start),
      );
    } else {
      final newText = text.replaceRange(selection.start, selection.end, '');
      textController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start),
      );
    }
  }

  void _handleTextChanged() {
    if (!_disposing) notifyListeners();
  }

  TextRange _previousCharacterRange(String text, int offset) {
    final runes = text.runes.toList();
    var currentOffset = 0;
    var prevStart = 0;
    for (var i = 0; i < runes.length; i++) {
      final runeLen = String.fromCharCode(runes[i]).length;
      if (currentOffset + runeLen >= offset) {
        return TextRange(start: currentOffset, end: offset);
      }
      prevStart = currentOffset;
      currentOffset += runeLen;
    }
    return TextRange(start: prevStart, end: offset);
  }

  void toggleEmoji() {
    _cancelHandoff();
    _isOpen = true;
    if (_bottomPanel == CommentBottomPanel.emoji) {
      _startEmojiToKeyboardHandoff();
    } else {
      _bottomPanel = CommentBottomPanel.emoji;
      if (focusNode.hasFocus) {
        focusNode.unfocus();
      }
      notifyListeners();
    }
  }

  void switchToKeyboard() {
    _cancelHandoff();
    _isOpen = true;
    if (_bottomPanel == CommentBottomPanel.emoji) {
      _startEmojiToKeyboardHandoff();
    } else {
      _bottomPanel = CommentBottomPanel.keyboard;
      notifyListeners();
      _focusAfterLayout();
    }
  }

  void close() {
    _cancelHandoff();
    _isOpen = false;
    _bottomPanel = CommentBottomPanel.none;
    if (focusNode.hasFocus) {
      focusNode.unfocus();
    }
    notifyListeners();
  }

  void reset() {
    _cancelHandoff();
    textController.clear();
    _sticker = null;
    _localImages.clear();
    _parentCommentId = null;
    _replyToUserId = null;
    _replyToName = null;
    _isOpen = false;
    _bottomPanel = CommentBottomPanel.none;
    if (focusNode.hasFocus) {
      focusNode.unfocus();
    }
    notifyListeners();
  }

  void _startEmojiToKeyboardHandoff() {
    _handoff = CommentInputHandoff.emojiToKeyboard;
    _bottomPanel = CommentBottomPanel.keyboard;
    notifyListeners();
    _focusAfterLayout();

    _handoffTimer?.cancel();
    _handoffTimer = Timer(const Duration(milliseconds: 320), () {
      if (!_disposing && _handoff == CommentInputHandoff.emojiToKeyboard) {
        _completeEmojiToKeyboardHandoff();
      }
    });
  }

  void _completeEmojiToKeyboardHandoff() {
    _handoffTimer?.cancel();
    _handoffTimer = null;
    _handoff = CommentInputHandoff.none;
    _bottomPanel = CommentBottomPanel.keyboard;
    notifyListeners();
  }

  void _cancelHandoff() {
    _handoffTimer?.cancel();
    _handoffTimer = null;
    _handoff = CommentInputHandoff.none;
  }

  void _focusAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposing && _isOpen && !focusNode.hasFocus) {
        focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _disposing = true;
    _cancelHandoff();
    textController.removeListener(_handleTextChanged);
    textController.dispose();
    focusNode.dispose();
    super.dispose();
  }
}
