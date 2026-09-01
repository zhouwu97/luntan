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

  test('Android 应用必须使用独立的自适应自定义图标资源', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final adaptiveIcon = File(
      'android/app/src/main/res/mipmap-anydpi-v26/luntan_launcher.xml',
    );
    final foreground = File(
      'android/app/src/main/res/drawable-nodpi/luntan_launcher_foreground.png',
    );

    expect(manifest, contains('android:icon="@mipmap/luntan_launcher"'));
    expect(
      manifest,
      contains('android:roundIcon="@mipmap/luntan_launcher"'),
    );
    expect(manifest, isNot(contains('@mipmap/ic_launcher')));
    expect(adaptiveIcon.existsSync(), isTrue);
    expect(foreground.existsSync(), isTrue);
    expect(
      adaptiveIcon.readAsStringSync(),
      contains('android:drawable="@drawable/luntan_launcher_foreground"'),
    );
    for (final density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      expect(
        File(
          'android/app/src/main/res/mipmap-$density/luntan_launcher.png',
        ).existsSync(),
        isTrue,
        reason: '$density 必须保留旧系统的自定义图标回退资源',
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
          'android:windowSplashScreenAnimatedIcon">@drawable/luntan_launcher_foreground',
        ),
        reason: '$path 必须覆盖 Android 12+ 的系统启动图标',
      );
    }
  });
}
