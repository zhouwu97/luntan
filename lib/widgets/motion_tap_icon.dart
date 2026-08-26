import 'package:flutter/material.dart';

import '../theme/app_motion.dart';

/// 高频操作图标的短促反馈：状态切换时轻微放大后回落，不改变布局尺寸。
///
/// 图标本身通过 AnimatedSwitcher 完成形态切换，控制器只负责反馈动画；
/// 因此连续点击和接口 rollback 时不会叠加整张卡片动画。
class MotionTapIcon extends StatefulWidget {
  const MotionTapIcon({
    super.key,
    required this.active,
    required this.activeIcon,
    required this.inactiveIcon,
    required this.activeColor,
    required this.inactiveColor,
    this.size = 20,
  });

  final bool active;
  final IconData activeIcon;
  final IconData inactiveIcon;
  final Color activeColor;
  final Color inactiveColor;
  final double size;

  @override
  State<MotionTapIcon> createState() => _MotionTapIconState();
}

class _MotionTapIconState extends State<MotionTapIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  late final Animation<double> scale;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(vsync: this, duration: AppMotion.fast);
    controller.value = 1;
    scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: .96, end: 1.12), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.12, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: controller, curve: AppMotion.standard));
  }

  @override
  void didUpdateWidget(covariant MotionTapIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active == widget.active) return;
    if (AppMotion.reduceMotion(context)) {
      controller.value = 1;
      return;
    }
    controller.forward(from: 0);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: scale,
    builder: (context, child) =>
        Transform.scale(scale: scale.value, child: child),
    child: AnimatedSwitcher(
      duration: AppMotion.duration(context, AppMotion.fast),
      switchInCurve: AppMotion.standard,
      switchOutCurve: AppMotion.emphasized,
      child: Icon(
        widget.active ? widget.activeIcon : widget.inactiveIcon,
        key: ValueKey(widget.active),
        size: widget.size,
        color: widget.active ? widget.activeColor : widget.inactiveColor,
      ),
    ),
  );
}
