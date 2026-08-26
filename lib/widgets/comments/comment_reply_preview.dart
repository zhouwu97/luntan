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
  });

  final List<Comment> replies;
  final int totalReplyCount;
  final VoidCallback onOpenThread;
  final ValueChanged<Comment>? onReplyTo;

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
                  final replyTo =
                      reply.replyToUserId != null ? '用户' : null;

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
                            ),
                            if (replyTo != null) ...[
                              const TextSpan(text: ' 回复 '),
                              TextSpan(
                                text: '@$replyTo',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primary,
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
                            TextSpan(text: reply.content),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          if (totalReplyCount > previewItems.length || totalReplyCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 10),
              child: GestureDetector(
                onTap: onOpenThread,
                child: Text(
                  '展开 $totalReplyCount 条回复 ›',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
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
