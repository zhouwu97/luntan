import 'package:flutter/material.dart';

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

  static const primaryGradient = LinearGradient(colors: [primary, sky], begin: Alignment.topLeft, end: Alignment.bottomRight);

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.fromSeed(seedColor: primary, brightness: Brightness.light, surface: Colors.white),
        fontFamily: 'Microsoft YaHei',
        textTheme: const TextTheme(
          headlineSmall: TextStyle(color: textPrimary, fontWeight: FontWeight.w800),
          titleLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w800),
          titleMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
          bodyLarge: TextStyle(color: textPrimary, height: 1.5),
          bodyMedium: TextStyle(color: textSecondary, height: 1.45),
        ),
        appBarTheme: const AppBarTheme(backgroundColor: background, foregroundColor: textPrimary, elevation: 0, centerTitle: false),
        snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), backgroundColor: textPrimary),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surfaceBlue,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: primary, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      );
}
