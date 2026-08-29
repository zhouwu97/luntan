import 'package:flutter/material.dart';

import 'app_motion.dart';

class AppTheme {
  static const primary = Color(0xFF5A9EFF);
  static const sky = Color(0xFF71CFFF);
  static const surfaceBlue = Color(0xFFEDF6FF);
  static const background = Color(0xFFF4F8FC);
  static const textPrimary = Color(0xFF182A3D);
  static const textSecondary = Color(0xFF71869B);
  static const border = Color(0xFFDFE8F2);
  static const mint = Color(0xFF46C7B1);
  static const orange = Color(0xFFFF9C62);
  static const pink = Color(0xFFFF86A7);
  static const purple = Color(0xFF9A88E8);

  static const surface = Colors.white;

  // 论坛 UI 的统一量尺，页面和基础组件只从这里取值，避免局部漂移。
  static const pagePadding = 14.0;
  static const contentHorizontal = 16.0;
  static const sectionGap = 24.0;
  static const listGap = 16.0;
  static const spacing4 = 4.0;
  static const spacing8 = 8.0;
  static const spacing12 = 12.0;
  static const spacing16 = 16.0;
  static const spacing20 = 20.0;
  static const spacing24 = 24.0;

  static const avatarTiny = 28.0;
  static const avatarSmall = 34.0;
  static const avatarMedium = 40.0;
  static const avatarLarge = 48.0;
  static const minTapTarget = 44.0;

  static const radiusSmall = 8.0;
  static const radiusMedium = 14.0;
  static const radiusLarge = 20.0;

  static const compactRadius = 9.0;
  static const searchRadius = 14.0;
  static const cardRadius = 16.0;
  static const iconContainerRadius = 14.0;
  static const publishRadius = 17.0;

  // 高亮与等级样式
  static const highlight = Color(0xFF2B6DBA);
  static const highlightBg = Color(0xFFEDF6FF);
  static const levelBg = Color(0xFFE7F7F2);
  static const levelText = Color(0xFF36AA92);

  // 兼容旧页面的别名；新代码统一从 AppMotion 取动效 token。
  static const fastMotion = AppMotion.fast;
  static const tabMotion = AppMotion.normal;
  static const sheetMotion = AppMotion.page;
  static const Curve contentCurve = AppMotion.standard;
  static const Curve stateCurve = AppMotion.emphasized;

  static const primaryGradient = LinearGradient(
    colors: [primary, sky],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Web 端 CanvasKit 读不到系统字体，必须在 pubspec 打包 LuntanCJK
  //（Noto Sans SC）并全局指定；fontFamilyFallback 里的系统字体名仅在
  // 原生平台兜底，web 上不生效。
  static const fontFamily = 'LuntanCJK';

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily,
    scaffoldBackgroundColor: background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      surface: Colors.white,
    ),
    fontFamilyFallback: const [
      'Microsoft YaHei',
      'Noto Sans CJK SC',
      'PingFang SC',
      'sans-serif',
    ],
    textTheme: const TextTheme(
      headlineSmall: TextStyle(color: textPrimary, fontWeight: FontWeight.w800),
      titleLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w800),
      titleMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
      bodyLarge: TextStyle(color: textPrimary, height: 1.5),
      bodyMedium: TextStyle(color: textSecondary, height: 1.45),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: background,
      foregroundColor: textPrimary,
      elevation: 0,
      centerTitle: false,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(cardRadius),
      ),
      backgroundColor: textPrimary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceBlue,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );
}
