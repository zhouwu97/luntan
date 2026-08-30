import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:package_info_plus/package_info_plus.dart';

import '../data/api/app_update_cache.dart';
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
    AppUpdateCache? cache,
    Future<PackageInfo> Function()? packageInfoResolver,
    bool? installerSupported,
    Future<bool> Function()? canInstallPackagesResolver,
    Future<void> Function(File apkFile)? installApkHandler,
  }) : _service = service ?? AppUpdateService(),
       _cache = cache ?? SharedPreferencesAppUpdateCache(),
       _packageInfoResolver = packageInfoResolver ?? PackageInfo.fromPlatform,
       _installerSupported = installerSupported ?? AppInstaller.isSupported,
       _canInstallPackages =
           canInstallPackagesResolver ?? AppInstaller.canInstallPackages,
       _installApk = installApkHandler ?? AppInstaller.installApk;

  final AppUpdateService _service;
  final AppUpdateCache _cache;
  final Future<PackageInfo> Function() _packageInfoResolver;
  final bool _installerSupported;
  final Future<bool> Function() _canInstallPackages;
  final Future<void> Function(File apkFile) _installApk;

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
  int? _downloadedVersionCode;
  String? _downloadedSha256;
  bool _isRequiredLocked = false;
  int? _requiredMinimumSupportedVersionCode;
  DateTime? _lastCheckedAt;
  String _currentVersionName = '';
  int _currentVersionCode = 0;
  AppUpdateCacheEntry? _cachedEntry;
  Future<void>? _cacheLoadFuture;
  Future<AppUpdateInfo?>? _checkFuture;
  Future<bool>? _resumeInstallFuture;

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
  /// [force] 仅为兼容旧调用方保留；强制更新策略只能由服务端响应决定。
  Future<AppUpdateInfo?> checkUpdate({
    bool manual = false,
    bool force = false,
  }) {
    // manual/force 保留给现有 UI 调用方；服务端策略不能被 UI 参数改写。
    final ongoing = _checkFuture;
    if (ongoing != null) return ongoing;

    final future = _doCheck(manual: manual, force: force);
    _checkFuture = future;
    future.then<void>(
      (_) => _clearCheckFuture(future),
      onError: (Object error, StackTrace stackTrace) {
        _clearCheckFuture(future);
      },
    );
    return future;
  }

  Future<AppUpdateInfo?> _doCheck({
    required bool manual,
    required bool force,
  }) async {
    _status = AppUpdateStatus.checking;
    _errorMessage = null;
    _errorKind = null;
    notifyListeners();

    try {
      await _ensureCacheLoaded();
      final packageInfo = await _packageInfoResolver();
      _currentVersionName = packageInfo.version;
      _currentVersionCode = int.tryParse(packageInfo.buildNumber) ?? 0;
      if (await _restoreCachedPolicy()) {
        notifyListeners();
      }

      final updateInfo = await _service.checkUpdate(
        versionName: _currentVersionName,
        versionCode: _currentVersionCode,
      );

      _lastCheckedAt = DateTime.now();
      _applyNetworkUpdate(updateInfo);
      await _persistPolicy(updateInfo);
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

  void _clearCheckFuture(Future<AppUpdateInfo?> future) {
    if (identical(_checkFuture, future)) {
      _checkFuture = null;
    }
  }

  Future<void> _ensureCacheLoaded() {
    return _cacheLoadFuture ??= _readCache();
  }

  Future<void> _readCache() async {
    try {
      _cachedEntry = await _cache.read();
    } catch (_) {
      // 缓存损坏或平台存储暂不可用时，继续走联网检查，不阻断应用启动。
      _cachedEntry = null;
    }
  }

  /// 在联网前恢复上次已确认的最低版本门禁。
  Future<bool> _restoreCachedPolicy() async {
    final cached = _cachedEntry;
    if (cached == null) return false;
    if (_isRequiredLocked && cached.isRequired) {
      // 当前进程已经确认过 required，不能因为下一次重检开始前的缓存清理
      // 把仍在生效的内存门禁提前降级。
      return false;
    }
    final minimum = cached.info.minimumSupportedVersionCode;
    if (cached.isRequired && _currentVersionCode < minimum) {
      _isRequiredLocked = true;
      _requiredMinimumSupportedVersionCode = minimum;
      _info = cached.info;
      _status = AppUpdateStatus.requiredUpdateAvailable;
      return true;
    }

    _cachedEntry = null;
    _isRequiredLocked = false;
    _requiredMinimumSupportedVersionCode = null;
    try {
      await _cache.clear();
    } catch (_) {
      // 清理失败不影响当前联网检查结果。
    }
    return false;
  }

  void _applyNetworkUpdate(AppUpdateInfo updateInfo) {
    final previousInfo = _info;
    final hadRequiredLock = _isRequiredLocked;
    final requiredMinimum = _requiredMinimumSupportedVersionCode;

    if (updateInfo.updateAvailable) {
      _info = updateInfo;
      _invalidateDownloadedFile(updateInfo);
      if (updateInfo.isRequired) {
        _isRequiredLocked = true;
        if (requiredMinimum == null ||
            updateInfo.minimumSupportedVersionCode > requiredMinimum) {
          _requiredMinimumSupportedVersionCode =
              updateInfo.minimumSupportedVersionCode;
        }
        _status = AppUpdateStatus.requiredUpdateAvailable;
      } else if (hadRequiredLock &&
          requiredMinimum != null &&
          _currentVersionCode < requiredMinimum) {
        // 已确认的最低版本门禁不能被一次较宽松的临时响应解除。
        _isRequiredLocked = true;
        _status = AppUpdateStatus.requiredUpdateAvailable;
      } else {
        _isRequiredLocked = false;
        _requiredMinimumSupportedVersionCode = null;
        _status = AppUpdateStatus.optionalUpdateAvailable;
      }
      return;
    }

    if (hadRequiredLock &&
        requiredMinimum != null &&
        _currentVersionCode < requiredMinimum) {
      // none 响应可能来自短暂的发布切换，保留可安装的缓存元数据。
      _info = _cachedEntry?.info ?? previousInfo;
      _isRequiredLocked = true;
      _status = AppUpdateStatus.requiredUpdateAvailable;
      return;
    }

    _info = updateInfo;
    _invalidateDownloadedFile(updateInfo);
    _isRequiredLocked = false;
    _requiredMinimumSupportedVersionCode = null;
    _status = AppUpdateStatus.upToDate;
  }

  Future<void> _persistPolicy(AppUpdateInfo updateInfo) async {
    if (updateInfo.updateAvailable || _isRequiredLocked) {
      final infoToPersist = _info ?? updateInfo;
      final entry = AppUpdateCacheEntry(
        info: infoToPersist,
        checkedAt: _lastCheckedAt ?? DateTime.now(),
        requiredPolicy: _isRequiredLocked,
      );
      _cachedEntry = entry;
      try {
        await _cache.write(entry);
      } catch (_) {
        // 本地缓存失败不应让线上更新检查失败。
      }
      return;
    }

    _cachedEntry = null;
    try {
      await _cache.clear();
    } catch (_) {
      // 本地缓存失败不影响当前无更新结论。
    }
  }

  void _invalidateDownloadedFile(AppUpdateInfo? updateInfo) {
    final downloaded = _downloadedFile;
    if (downloaded == null) return;
    if (updateInfo == null ||
        !updateInfo.updateAvailable ||
        _downloadedVersionCode != updateInfo.latestVersionCode ||
        _downloadedSha256 != updateInfo.sha256.toLowerCase()) {
      _downloadedFile = null;
      _downloadedVersionCode = null;
      _downloadedSha256 = null;
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
    var lastProgressNotification = DateTime.now();
    _errorMessage = null;
    notifyListeners();

    try {
      final normalizedSha = currentInfo.sha256.toLowerCase();
      final downloaded = _downloadedFile;
      final canReuseDownloadedFile =
          downloaded != null &&
          _downloadedVersionCode == currentInfo.latestVersionCode &&
          _downloadedSha256 == normalizedSha &&
          await downloaded.exists();
      final file = canReuseDownloadedFile
          ? downloaded
          : await _service.downloadApk(
              info: currentInfo,
              cancelToken: cancelToken,
              onProgress: (received, total) {
                final now = DateTime.now();
                final elapsed = now.difference(_lastTick).inMilliseconds;
                final notificationElapsed = now
                    .difference(lastProgressNotification)
                    .inMilliseconds;
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
                // 分片下载会产生更多进度回调；限制 UI 重建频率，避免渲染
                // 反过来占用下载 isolate 的事件循环。
                if (notificationElapsed >= 350 || received >= total) {
                  lastProgressNotification = now;
                  notifyListeners();
                }
              },
            );

      _downloadedFile = file;
      _downloadedVersionCode = currentInfo.latestVersionCode;
      _downloadedSha256 = normalizedSha;
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

    if (!_installerSupported) {
      _status = AppUpdateStatus.readyToInstall;
      _errorMessage = '当前平台不支持应用内直接安装';
      notifyListeners();
      return;
    }

    final hasPermission = await _canInstallPackages();
    if (!hasPermission) {
      _status = AppUpdateStatus.permissionRequired;
      _errorMessage = '需要先允许“安装未知应用”权限';
      notifyListeners();
      return;
    }

    _status = AppUpdateStatus.installing;
    notifyListeners();

    try {
      await _installApk(file);
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

  /// 从“安装未知应用”设置页返回后恢复安装流程。
  ///
  /// Android 设置页返回会触发应用 resumed，但更新检查本身有节流窗口；
  /// 权限恢复必须先于普通版本检查执行，否则用户会停留在旧的
  /// [AppUpdateStatus.permissionRequired] 状态。该方法只处理已有安装包的
  /// 待安装状态，授权成功后自动再次唤起系统安装器。
  Future<bool> resumePendingInstall() {
    final ongoing = _resumeInstallFuture;
    if (ongoing != null) return ongoing;

    final future = _resumePendingInstall();
    _resumeInstallFuture = future;
    future.then<void>(
      (_) => _clearResumeInstallFuture(future),
      onError: (Object error, StackTrace stackTrace) {
        _clearResumeInstallFuture(future);
      },
    );
    return future;
  }

  Future<bool> _resumePendingInstall() async {
    if (_status != AppUpdateStatus.permissionRequired) return false;
    await installApk();
    return _status == AppUpdateStatus.installerOpened;
  }

  void _clearResumeInstallFuture(Future<bool> future) {
    if (identical(_resumeInstallFuture, future)) {
      _resumeInstallFuture = null;
    }
  }

  /// App 回到前台时的防抖/节流检查。
  Future<void> onAppForeground({
    Duration minInterval = const Duration(minutes: 30),
  }) async {
    if (kIsWeb || !Platform.isAndroid) return;
    if (await resumePendingInstall()) return;
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
