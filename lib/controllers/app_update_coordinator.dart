import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:package_info_plus/package_info_plus.dart';

import '../data/api/app_update_service.dart';
import '../platform/app_installer.dart';

enum AppUpdateStatus {
  idle,
  checking,
  upToDate,
  optionalUpdateAvailable,
  requiredUpdateAvailable,
  downloading,
  verifying,
  readyToInstall,
  installing,
  installerOpened,
  permissionRequired,
  error,
}

/// 全局应用更新协调器。
///
/// 独立管理更新检查、状态机流转、断点续传、包体校验与系统安装器唤起。
/// 解耦于具体 UI 弹层与业务登录/Mock 状态。
class AppUpdateCoordinator extends ChangeNotifier {
  AppUpdateCoordinator({
    AppUpdateService? service,
    Future<PackageInfo> Function()? packageInfoResolver,
  }) : _service = service ?? AppUpdateService(),
       _packageInfoResolver =
           packageInfoResolver ?? PackageInfo.fromPlatform;

  final AppUpdateService _service;
  final Future<PackageInfo> Function() _packageInfoResolver;

  AppUpdateStatus _status = AppUpdateStatus.idle;
  AppUpdateInfo? _info;
  String? _errorMessage;
  AppUpdateErrorKind? _errorKind;

  int _receivedBytes = 0;
  int _totalBytes = 0;
  double _speedBytesPerSecond = 0;
  DateTime _lastTick = DateTime.now();
  int _lastBytes = 0;

  ValueCancelToken? _cancelToken;
  File? _downloadedFile;
  bool _isRequiredLocked = false;
  DateTime? _lastCheckedAt;
  String _currentVersionName = '';
  int _currentVersionCode = 0;

  AppUpdateStatus get status => _status;
  AppUpdateInfo? get info => _info;
  String? get errorMessage => _errorMessage;
  AppUpdateErrorKind? get errorKind => _errorKind;
  int get receivedBytes => _receivedBytes;
  int get totalBytes => _totalBytes;
  double get speedBytesPerSecond => _speedBytesPerSecond;
  File? get downloadedFile => _downloadedFile;
  bool get isRequiredLocked => _isRequiredLocked;
  DateTime? get lastCheckedAt => _lastCheckedAt;
  String get currentVersionName => _currentVersionName;
  int get currentVersionCode => _currentVersionCode;

  double get downloadProgress {
    if (_totalBytes <= 0) return 0.0;
    final progress = _receivedBytes / _totalBytes;
    return progress.clamp(0.0, 1.0);
  }

  bool get isChecking => _status == AppUpdateStatus.checking;
  bool get isDownloading => _status == AppUpdateStatus.downloading;
  bool get isVerifying => _status == AppUpdateStatus.verifying;
  bool get isRequired =>
      _isRequiredLocked ||
      _status == AppUpdateStatus.requiredUpdateAvailable ||
      (_info?.isRequired ?? false);

  /// 检查更新。
  ///
  /// [manual] 表示是否为用户在设置中主动触发。
  /// [force] 表示是否显式启用强制更新门禁模式。
  Future<AppUpdateInfo?> checkUpdate({
    bool manual = false,
    bool force = false,
  }) async {
    _status = AppUpdateStatus.checking;
    _errorMessage = null;
    _errorKind = null;
    notifyListeners();

    try {
      final packageInfo = await _packageInfoResolver();
      _currentVersionName = packageInfo.version;
      _currentVersionCode = int.tryParse(packageInfo.buildNumber) ?? 0;

      final updateInfo = await _service.checkUpdate(
        versionName: _currentVersionName,
        versionCode: _currentVersionCode,
      );

      _lastCheckedAt = DateTime.now();
      _info = updateInfo;

      if (updateInfo.updateAvailable) {
        if (updateInfo.isRequired || force) {
          _isRequiredLocked = true;
          _status = AppUpdateStatus.requiredUpdateAvailable;
        } else {
          _status = AppUpdateStatus.optionalUpdateAvailable;
        }
      } else {
        _isRequiredLocked = false;
        _status = AppUpdateStatus.upToDate;
      }
      notifyListeners();
      return updateInfo;
    } on AppUpdateException catch (error) {
      _lastCheckedAt = DateTime.now();
      _errorKind = error.kind;
      _errorMessage = error.message;

      // 如果已锁存强制更新，即使临时断网也不降级解除门禁。
      if (_isRequiredLocked) {
        _status = AppUpdateStatus.requiredUpdateAvailable;
      } else {
        _status = AppUpdateStatus.error;
      }
      notifyListeners();
      return null;
    } catch (_) {
      _lastCheckedAt = DateTime.now();
      _errorKind = AppUpdateErrorKind.protocol;
      _errorMessage = '检查更新失败，请稍后重试';

      if (_isRequiredLocked) {
        _status = AppUpdateStatus.requiredUpdateAvailable;
      } else {
        _status = AppUpdateStatus.error;
      }
      notifyListeners();
      return null;
    }
  }

  /// 启动 APK 应用内下载。
  Future<void> startDownload() async {
    final currentInfo = _info;
    if (currentInfo == null || !currentInfo.updateAvailable) return;

    final cancelToken = ValueCancelToken();
    _cancelToken = cancelToken;

    _status = AppUpdateStatus.downloading;
    _receivedBytes = 0;
    _totalBytes = currentInfo.fileSize;
    _speedBytesPerSecond = 0;
    _lastTick = DateTime.now();
    _lastBytes = 0;
    _errorMessage = null;
    notifyListeners();

    try {
      final file =
          _downloadedFile ??
          await _service.downloadApk(
            info: currentInfo,
            cancelToken: cancelToken,
            onProgress: (received, total) {
              final now = DateTime.now();
              final elapsed = now.difference(_lastTick).inMilliseconds;
              if (elapsed >= 350) {
                final speed =
                    (received - _lastBytes) *
                    1000 /
                    (elapsed == 0 ? 1 : elapsed);
                _lastTick = now;
                _lastBytes = received;
                _speedBytesPerSecond = speed;
              }
              _receivedBytes = received;
              _totalBytes = total;
              if (received >= total && total > 0) {
                _status = AppUpdateStatus.verifying;
              }
              notifyListeners();
            },
          );

      _downloadedFile = file;
      _status = AppUpdateStatus.readyToInstall;
      notifyListeners();

      // 下载完成并校验后，自动尝试进入安装流程
      await installApk();
    } on AppUpdateCancelled {
      _status = _isRequiredLocked
          ? AppUpdateStatus.requiredUpdateAvailable
          : AppUpdateStatus.optionalUpdateAvailable;
      _errorMessage = null;
      notifyListeners();
    } on AppUpdateException catch (error) {
      _status = _isRequiredLocked
          ? AppUpdateStatus.requiredUpdateAvailable
          : AppUpdateStatus.error;
      _errorKind = error.kind;
      _errorMessage = error.message;
      notifyListeners();
    } catch (_) {
      _status = _isRequiredLocked
          ? AppUpdateStatus.requiredUpdateAvailable
          : AppUpdateStatus.error;
      _errorKind = AppUpdateErrorKind.protocol;
      _errorMessage = '下载失败，请稍后重试';
      notifyListeners();
    } finally {
      if (identical(_cancelToken, cancelToken)) {
        _cancelToken = null;
      }
    }
  }

  /// 取消当前下载。
  void cancelDownload() {
    _cancelToken?.cancel();
    _cancelToken = null;
  }

  /// 唤起 Android 系统安装器。
  Future<void> installApk() async {
    final file = _downloadedFile;
    if (file == null || !await file.exists()) {
      _status = AppUpdateStatus.error;
      _errorMessage = '未找到已下载的安装包，请重新下载';
      notifyListeners();
      return;
    }

    if (!AppInstaller.isSupported) {
      _status = AppUpdateStatus.readyToInstall;
      _errorMessage = '当前平台不支持应用内直接安装';
      notifyListeners();
      return;
    }

    final hasPermission = await AppInstaller.canInstallPackages();
    if (!hasPermission) {
      _status = AppUpdateStatus.permissionRequired;
      _errorMessage = '需要先允许“安装未知应用”权限';
      notifyListeners();
      return;
    }

    _status = AppUpdateStatus.installing;
    notifyListeners();

    try {
      await AppInstaller.installApk(file);
      _status = AppUpdateStatus.installerOpened;
      _errorMessage = null;
      notifyListeners();
    } on PlatformException catch (error) {
      if (error.code == 'UNKNOWN_SOURCE_NOT_ALLOWED') {
        _status = AppUpdateStatus.permissionRequired;
        _errorMessage = '需要先允许“安装未知应用”权限';
      } else {
        _status = AppUpdateStatus.readyToInstall;
        _errorMessage = error.message ?? '唤起系统安装器失败';
      }
      notifyListeners();
    } catch (_) {
      _status = AppUpdateStatus.readyToInstall;
      _errorMessage = '唤起系统安装器失败';
      notifyListeners();
    }
  }

  /// 打开系统权限设置页面。
  Future<void> openPermissionSettings() async {
    await AppInstaller.openInstallPermissionSettings();
  }

  /// 启动延迟检查（静默模式）。
  Future<void> checkStartup({
    Duration delay = const Duration(seconds: 3),
  }) async {
    if (kIsWeb || !Platform.isAndroid) return;
    await Future<void>.delayed(delay);
    await checkUpdate(manual: false);
  }

  /// App 回到前台时的防抖/节流检查。
  Future<void> onAppForeground({
    Duration minInterval = const Duration(minutes: 30),
  }) async {
    if (kIsWeb || !Platform.isAndroid) return;
    final last = _lastCheckedAt;
    if (last != null && DateTime.now().difference(last) < minInterval) {
      return;
    }
    await checkUpdate(manual: false);
  }

  /// 关闭或释放资源。
  @override
  void dispose() {
    _cancelToken?.cancel();
    _service.close();
    super.dispose();
  }
}
