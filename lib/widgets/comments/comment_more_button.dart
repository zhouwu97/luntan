import 'package:flutter/material.dart';

/// 评论操作栏统一使用的更多按钮，固定尺寸避免挤压回复与点赞操作。
class CommentMoreButton extends StatelessWidget {
  const CommentMoreButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 36,
    height: 32,
    child: IconButton(
      tooltip: '更多操作',
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      icon: const Icon(
        Icons.more_horiz_rounded,
        size: 18,
        color: Color(0xFF9AAABD),
      ),
      onPressed: onPressed,
    ),
  );
}
