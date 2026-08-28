import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../theme/app_theme.dart';

class CommentReplyPreview extends StatelessWidget {
  const CommentReplyPreview({
    super.key,
    required this.replies,
    required this.totalReplyCount,
    required this.onOpenThread,
    this.onReplyTo,
    this.onAuthorTap,
  });

  final List<Comment> replies;
  final int totalReplyCount;
  final VoidCallback onOpenThread;
  final ValueChanged<Comment>? onReplyTo;
  final ValueChanged<String>? onAuthorTap;

  @override
  Widget build(BuildContext context) {
    if (replies.isEmpty && totalReplyCount <= 0) {
      return const SizedBox.shrink();
    }

    final previewItems = replies.take(3).toList();

    return Padding(
      padding: const EdgeInsets.only(left: 44, top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (previewItems.isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: Color(0xFFD7E4F0), width: 2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: previewItems.map((reply) {
                  final author = reply.author?.nickname ?? '用户';
                  final replyTo = reply.replyToUserId == null
                      ? null
                      : (reply.replyToUser?.nickname ??
                            reply.replyToUser?.username ??
                            '用户');

                  final authorTapRecognizer = (onAuthorTap != null &&
                          reply.authorId.isNotEmpty &&
                          !reply.authorId.startsWith('guest'))
                      ? (TapGestureRecognizer()..onTap = () => onAuthorTap!(reply.authorId))
                      : null;

                  final replyToTapRecognizer = (onAuthorTap != null &&
                          reply.replyToUserId != null &&
                          reply.replyToUserId!.isNotEmpty &&
                          !reply.replyToUserId!.startsWith('guest'))
                      ? (TapGestureRecognizer()..onTap = () => onAuthorTap!(reply.replyToUserId!))
                      : null;

                  return InkWell(
                    onTap: () {
                      if (onReplyTo != null) {
                        onReplyTo!(reply);
                      } else {
                        onOpenThread();
                      }
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.5),
                      child: RichText(
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        text: TextSpan(
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF5F7488),
                            height: 1.5,
                          ),
                          children: [
                            TextSpan(
                              text: author,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF385A79),
                              ),
                              recognizer: authorTapRecognizer,
                            ),
                            if (replyTo != null) ...[
                              const TextSpan(text: ' 回复 '),
                              TextSpan(
                                text: '@$replyTo',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primary,
                                ),
                                recognizer: replyToTapRecognizer,
                              ),
                            ],
                            const TextSpan(
                              text: '：',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF385A79),
                              ),
                            ),
                            TextSpan(text: reply.content),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          if (totalReplyCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 10),
              child: GestureDetector(
                onTap: onOpenThread,
                child: Text(
                  '展开 $totalReplyCount 条回复 ›',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
