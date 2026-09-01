import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android release 构建脚本必须注入正式运行时配置', () {
    final script = File('scripts/build_android_release.ps1').readAsStringSync();

    expect(script, contains(r'[string]$AppEnvironment = '));
    expect(script, contains(r'[string]$ApiBaseUrl = '));
    expect(script, contains(r'[string]$WebBaseUrl = '));
    expect(
      script,
      contains(r'--dart-define=APP_ENV=$normalizedAppEnvironment'),
    );
    expect(script, contains(r'--dart-define=API_BASE_URL=$($ApiBaseUrl.Trim())'));
    expect(script, contains(r'--dart-define=WEB_BASE_URL=$($WebBaseUrl.Trim())'));
    expect(script, contains('https://shengbeijiang.com'));
  });

  test('Android 应用必须使用 flutter_launcher_icons 生成的统一图标', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final adaptiveIcon = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    );
    final colorsXml = File(
      'android/app/src/main/res/values/colors.xml',
    );

    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    expect(manifest, contains('android:roundIcon="@mipmap/ic_launcher"'));
    expect(adaptiveIcon.existsSync(), isTrue);
    expect(colorsXml.existsSync(), isTrue);

    final adaptiveContent = adaptiveIcon.readAsStringSync();
    expect(
      adaptiveContent,
      contains('android:drawable="@drawable/ic_launcher_foreground"'),
    );
    expect(
      adaptiveContent,
      contains('android:drawable="@color/ic_launcher_background"'),
    );

    for (final density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      expect(
        File(
          'android/app/src/main/res/mipmap-$density/ic_launcher.png',
        ).existsSync(),
        isTrue,
        reason: '$density 必须有 ic_launcher 回退资源',
      );
      expect(
        File(
          'android/app/src/main/res/drawable-$density/ic_launcher_foreground.png',
        ).existsSync(),
        isTrue,
        reason: '$density 必须有前景层资源',
      );
    }

    for (final path in [
      'android/app/src/main/res/values-v31/styles.xml',
      'android/app/src/main/res/values-night-v31/styles.xml',
    ]) {
      final styles = File(path).readAsStringSync();
      expect(
        styles,
        contains(
          'android:windowSplashScreenAnimatedIcon">@drawable/splash_transparent',
        ),
        reason: '$path 必须使用透明占位，品牌插画由 Flutter 层展示',
      );
    }

    expect(
      File('android/app/src/main/res/drawable/splash_transparent.xml').existsSync(),
      isTrue,
      reason: '必须有 Android 12+ 启动图透明占位资源',
    );
  });
}
