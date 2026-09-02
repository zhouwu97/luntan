import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../theme/app_theme.dart';
import '../link_text.dart';
import 'comment_more_button.dart';

class CommentReplyPreview extends StatelessWidget {
  const CommentReplyPreview({
    super.key,
    required this.replies,
    required this.totalReplyCount,
    required this.onOpenThread,
    this.onReplyTo,
    this.onAuthorTap,
    this.onMore,
  });

  final List<Comment> replies;
  final int totalReplyCount;
  final VoidCallback onOpenThread;
  final ValueChanged<Comment>? onReplyTo;
  final ValueChanged<String>? onAuthorTap;
  final ValueChanged<Comment>? onMore;

  @override
  Widget build(BuildContext context) {
    if (replies.isEmpty && totalReplyCount <= 0) {
      return const SizedBox.shrink();
    }

    final previewItems = replies.take(3).toList();

    return Padding(
      padding: const EdgeInsets.only(left: 46, top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (previewItems.isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F9FD),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE5EEF6), width: 0.8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: previewItems
                    .map(
                      (reply) => _ReplyPreviewLine(
                        key: ValueKey('reply-preview:${reply.id}'),
                        reply: reply,
                        onOpenThread: onOpenThread,
                        onReplyTo: onReplyTo,
                        onAuthorTap: onAuthorTap,
                        onMore: onMore,
                      ),
                    )
                    .toList(),
              ),
            ),
          if (totalReplyCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: InkWell(
                onTap: onOpenThread,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '展开 $totalReplyCount 条回复 ›',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 单条回复预览：作者 + 回复对象 + 正文（正文中的网址可点击跳转）。
class _ReplyPreviewLine extends StatefulWidget {
  const _ReplyPreviewLine({
    super.key,
    required this.reply,
    required this.onOpenThread,
    this.onReplyTo,
    this.onAuthorTap,
    this.onMore,
  });

  final Comment reply;
  final VoidCallback onOpenThread;
  final ValueChanged<Comment>? onReplyTo;
  final ValueChanged<String>? onAuthorTap;
  final ValueChanged<Comment>? onMore;

  @override
  State<_ReplyPreviewLine> createState() => _ReplyPreviewLineState();
}

class _ReplyPreviewLineState extends State<_ReplyPreviewLine> {
  final _recognizers = <TapGestureRecognizer>[];
  late List<TextSpan> _spans;

  @override
  void initState() {
    super.initState();
    _rebuildSpans();
  }

  @override
  void didUpdateWidget(covariant _ReplyPreviewLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reply.content != widget.reply.content) {
      _disposeRecognizers();
      _rebuildSpans();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  void _openLink(Uri uri) async {
    final opened = await openExternalLink(context, uri);
    if (!mounted || opened) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(const SnackBar(content: Text('无法打开该网址')));
  }

  void _rebuildSpans() {
    final text = widget.reply.content;
    final links = extractContentLinks(text);
    final linkStyle = const TextStyle(color: AppTheme.primary);
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final link in links) {
      if (link.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, link.start)));
      }
      final recognizer = TapGestureRecognizer()
        ..onTap = () => _openLink(link.uri);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(text: link.text, style: linkStyle, recognizer: recognizer),
      );
      cursor = link.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    if (spans.isEmpty) spans.add(TextSpan(text: text));
    _spans = spans;
  }

  @override
  Widget build(BuildContext context) {
    final reply = widget.reply;
    final author = reply.author?.nickname ?? '用户';
    final replyTo = reply.replyToUserId == null
        ? null
        : (reply.replyToUser?.nickname ?? reply.replyToUser?.username ?? '用户');

    final canTapAuthor =
        widget.onAuthorTap != null &&
        reply.authorId.isNotEmpty &&
        !reply.authorId.startsWith('guest');

    final canTapReplyTo =
        widget.onAuthorTap != null &&
        reply.replyToUserId != null &&
        reply.replyToUserId!.isNotEmpty &&
        !reply.replyToUserId!.startsWith('guest');

    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () {
              if (widget.onReplyTo != null) {
                widget.onReplyTo!(reply);
              } else {
                widget.onOpenThread();
              }
            },
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.5),
              child: Text.rich(
                TextSpan(
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF5F7488),
                    height: 1.5,
                  ),
                  children: [
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: GestureDetector(
                        onTap: canTapAuthor
                            ? () => widget.onAuthorTap!(reply.authorId)
                            : null,
                        child: Text(
                          author,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF385A79),
                          ),
                        ),
                      ),
                    ),
                    if (replyTo != null) ...[
                      const TextSpan(text: ' 回复 '),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: GestureDetector(
                          onTap: canTapReplyTo
                              ? () => widget.onAuthorTap!(reply.replyToUserId!)
                              : null,
                          child: Text(
                            '@$replyTo',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const TextSpan(
                      text: '：',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF385A79),
                      ),
                    ),
                    ..._spans,
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        if (widget.onMore != null)
          CommentMoreButton(onPressed: () => widget.onMore!(reply)),
      ],
    );
  }
}
