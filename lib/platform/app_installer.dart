import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Android 系统安装器桥接。
///
/// APK 仅从应用私有 cache/app_updates 目录传给 FileProvider，原生侧会再次
/// 校验路径归属，避免把任意文件暴露给安装 Intent。非 Android 平台一律返回
/// false / 抛出 [PlatformException]，由调用方降级为“前往网页下载”。
class AppInstaller {
  AppInstaller._();

  static const MethodChannel _channel = MethodChannel('luntan/app_update');

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// 设备是否允许直接安装（Android 8+ 需要“未知来源应用”授权）。
  static Future<bool> canInstallPackages() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// 打开“允许安装未知应用”的系统设置页。
  static Future<bool> openInstallPermissionSettings() async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('openInstallPermissionSettings') ??
        false;
  }

  /// 唤起系统安装器。原生侧校验路径必须位于 cache/app_updates 下。
  static Future<void> installApk(File apkFile) async {
    if (!isSupported) {
      throw PlatformException(
        code: 'UNSUPPORTED_PLATFORM',
        message: '应用内安装仅支持 Android',
      );
    }
    await _channel.invokeMethod<void>('installApk', {'path': apkFile.path});
  }
}
