import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';

class CommentReplyBar extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final targetUser = target?.author?.nickname ??
        (target?.authorId.isNotEmpty == true ? '用户' : null);

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
              child: target != null
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
                            onTap: onCancelTarget,
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

            // 输入与发送行
            Row(
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
                        controller: controller,
                        enabled: !sending,
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: AppTheme.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: target != null
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
                          if (!sending) onSubmit();
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 42,
                  child: FilledButton(
                    onPressed: sending
                        ? null
                        : () {
                            if (!isAuthenticated) {
                              onRequireAuth?.call();
                              return;
                            }
                            if (!canComment) {
                              onFeedback(blockedMessage);
                              return;
                            }
                            onSubmit();
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
                    child: sending
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
            ),
          ],
        ),
      ),
    );
  }
}
