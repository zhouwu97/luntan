import 'package:flutter/material.dart';

/// 论坛全局动效契约。
///
/// 基础组件只使用这里的时长和曲线，避免页面各自调整 duration 造成节奏
/// 漂移。动画必须能在状态变化时被打断，并且尊重系统的减少动态效果设置。
class AppMotion {
  static const fast = Duration(milliseconds: 120);
  static const tab = Duration(milliseconds: 200);
  static const normal = Duration(milliseconds: 200);
  static const page = Duration(milliseconds: 280);
  static const highlightFade = Duration(milliseconds: 1500);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeInOutCubic;

  static bool reduceMotion(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  static Duration duration(BuildContext context, Duration value) =>
      reduceMotion(context) ? Duration.zero : value;

  /// 页面进入/退出的统一转场，保留轻微位移来表达层级，同时使用淡入避免
  /// 大面积内容突然闪现。
  static PageRoute<T> pageRoute<T>({required WidgetBuilder builder}) =>
      PageRouteBuilder<T>(
        transitionDuration: page,
        reverseTransitionDuration: normal,
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          if (reduceMotion(context)) return child;
          final curved = CurvedAnimation(
            parent: animation,
            curve: standard,
            reverseCurve: emphasized,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.025, 0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      );
}
