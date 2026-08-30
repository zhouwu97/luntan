import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:package_info_plus/package_info_plus.dart';

import '../data/api/app_update_service.dart';
import '../data/repository_provider.dart';
import '../platform/app_installer.dart';
import '../theme/app_theme.dart';

/// 检查更新流程的底部弹层。
///
/// 状态机：checking → upToDate / available / error；available 内部再分
/// idle / downloading / readyToInstall / installPermissionRequired。
///
/// [force] 用于启动强制更新门禁：禁用点遮罩、下拉和返回键关闭，并隐藏
/// 关闭按钮，用户只能更新或重试。
Future<void> showAppUpdateSheet(
  BuildContext context, {
  bool force = false,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    isDismissible: !force,
    enableDrag: !force,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => AppUpdateSheet(force: force),
  );
}

class AppUpdateSheet extends StatefulWidget {
  const AppUpdateSheet({super.key, this.force = false});

  final bool force;

  @override
  State<AppUpdateSheet> createState() => _AppUpdateSheetState();
}

enum _UpdatePhase { checking, upToDate, available, error }

enum _DownloadPhase {
  idle,
  downloading,
  readyToInstall,
  installing,
  installerOpened,
}

class _AppUpdateSheetState extends State<AppUpdateSheet> {
  _UpdatePhase _phase = _UpdatePhase.checking;
  _DownloadPhase _downloadPhase = _DownloadPhase.idle;
  String? _errorMessage;
  AppUpdateInfo? _info;
  int _received = 0;
  int _total = 0;
  DateTime _lastTick = DateTime.now();
  int _lastBytes = 0;
  double _speedBytesPerSecond = 0;

  AppUpdateService? _service;
  ValueCancelToken? _cancelToken;
  File? _downloadedFile;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _service?.close();
    super.dispose();
  }

  AppUpdateService? _resolveService() {
    try {
      final baseUrl = apiBaseUrlFromEnvironment();
      if (baseUrl.trim().isEmpty) return null;
      return AppUpdateService(baseUri: Uri.parse(baseUrl));
    } catch (_) {
      return null;
    }
  }

  Future<void> _check() async {
    final service = _resolveService();
    if (service == null) {
      setState(() {
        _phase = _UpdatePhase.error;
        _errorMessage = '当前为离线演示模式，无法检查更新';
      });
      return;
    }
    _service?.close();
    _service = service;
    setState(() {
      _phase = _UpdatePhase.checking;
      _errorMessage = null;
    });
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final info = await service.checkUpdate(
        versionName: packageInfo.version,
        versionCode: int.tryParse(packageInfo.buildNumber) ?? 0,
      );
      if (!mounted) return;
      setState(() {
        if (info.updateAvailable) {
          _info = info;
          _phase = _UpdatePhase.available;
        } else {
          _phase = _UpdatePhase.upToDate;
        }
      });
    } on AppUpdateException catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.error;
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.error;
        _errorMessage = '检查更新失败，请稍后重试';
      });
    }
  }

  Future<void> _startDownload() async {
    final info = _info;
    final service = _service;
    if (info == null || service == null) return;
    final cancelToken = ValueCancelToken();
    _cancelToken = cancelToken;
    setState(() {
      _downloadPhase = _DownloadPhase.downloading;
      _received = 0;
      _total = info.fileSize;
      _speedBytesPerSecond = 0;
      _lastTick = DateTime.now();
      _lastBytes = 0;
    });
    try {
      final file =
          _downloadedFile ??
          await service.downloadApk(
            info: info,
            cancelToken: cancelToken,
            onProgress: (received, total) {
              if (!mounted) return;
              final now = DateTime.now();
              final elapsed = now.difference(_lastTick).inMilliseconds;
              if (elapsed >= 400) {
                final speed =
                    (received - _lastBytes) *
                    1000 /
                    (elapsed == 0 ? 1 : elapsed);
                _lastTick = now;
                _lastBytes = received;
                _speedBytesPerSecond = speed;
              }
              setState(() {
                _received = received;
                _total = total;
              });
            },
          );
      if (!mounted) return;
      _downloadedFile = file;
      if (!AppInstaller.isSupported) {
        setState(() => _downloadPhase = _DownloadPhase.readyToInstall);
        return;
      }
      if (!await AppInstaller.canInstallPackages()) {
        setState(() {
          _downloadPhase = _DownloadPhase.readyToInstall;
          _errorMessage = '需要先允许“安装未知应用”';
        });
        return;
      }
      setState(() => _downloadPhase = _DownloadPhase.installing);
      try {
        await AppInstaller.installApk(file);
        if (!mounted) return;
        setState(() {
          _downloadPhase = _DownloadPhase.installerOpened;
          _errorMessage = null;
        });
      } on PlatformException catch (error) {
        if (!mounted) return;
        setState(() {
          _downloadPhase = _DownloadPhase.readyToInstall;
          if (error.code == 'UNKNOWN_SOURCE_NOT_ALLOWED') {
            _errorMessage = '需要先允许“安装未知应用”';
          } else {
            _errorMessage = error.message ?? '唤起安装器失败';
          }
        });
      }
    } on AppUpdateCancelled {
      if (!mounted) return;
      setState(() {
        _downloadPhase = _DownloadPhase.idle;
        _errorMessage = null;
      });
    } on AppUpdateException catch (error) {
      if (!mounted) return;
      setState(() {
        _downloadPhase = _DownloadPhase.idle;
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _downloadPhase = _DownloadPhase.idle;
        _errorMessage = '下载失败，请稍后重试';
      });
    } finally {
      if (identical(_cancelToken, cancelToken)) _cancelToken = null;
    }
  }

  Future<void> _openPermissionSettings() async {
    await AppInstaller.openInstallPermissionSettings();
    if (!mounted) return;
    setState(() {
      _errorMessage = '授权后点击“安装”重新唤起安装器';
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.force,
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.86,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceBlue,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.system_update_alt_rounded,
                        color: AppTheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '检查更新',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _statusSubtitle(),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!widget.force)
                      IconButton(
                        tooltip: '关闭',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                ...switch (_phase) {
                  _UpdatePhase.checking => [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ],
                  _UpdatePhase.upToDate => [_UpToDateCard(onRetry: _check)],
                  _UpdatePhase.error => [
                    _ErrorCard(
                      message: _errorMessage ?? '检查更新失败',
                      onRetry: _check,
                    ),
                  ],
                  _UpdatePhase.available => _buildAvailableBody(),
                },
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _statusSubtitle() {
    return switch (_phase) {
      _UpdatePhase.checking => '正在连接服务器…',
      _UpdatePhase.upToDate => '当前已是最新版本',
      _UpdatePhase.available => '发现新版本 v${_info?.latestVersionName ?? ''}',
      _UpdatePhase.error => '检查更新失败',
    };
  }

  List<Widget> _buildAvailableBody() {
    final info = _info;
    if (info == null) return const [];
    return [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'v${info.latestVersionName}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                if (info.isRequired)
                  const _UpdateBadge(label: '必须更新', color: AppTheme.pink)
                else
                  const _UpdateBadge(label: '推荐更新', color: AppTheme.mint),
                const Spacer(),
                Text(
                  _formatBytes(info.fileSize),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              info.title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            if (info.changelog.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                info.changelog,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ],
        ),
      ),
      if (_downloadPhase == _DownloadPhase.downloading) ...[
        const SizedBox(height: 14),
        Semantics(
          label: '安装包下载进度',
          value: _percentText(),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceBlue,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Text(
                      '正在下载安装包',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _percentText(),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: _total > 0
                        ? (_received / _total).clamp(0.0, 1.0)
                        : 0,
                    minHeight: 8,
                    backgroundColor: Colors.white,
                    valueColor: const AlwaysStoppedAnimation(AppTheme.primary),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _progressText(),
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _cancelToken?.cancel(),
                      child: const Text('取消'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
      if (_errorMessage != null && _downloadPhase != _DownloadPhase.downloading)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            _errorMessage!,
            style: const TextStyle(fontSize: 12, color: AppTheme.pink),
          ),
        ),
      const SizedBox(height: 14),
      _primaryButton(info),
      if (AppInstaller.isSupported &&
          _downloadPhase == _DownloadPhase.readyToInstall &&
          _errorMessage?.contains('未知') == true)
        TextButton(
          onPressed: _openPermissionSettings,
          child: const Text('前往开启安装权限'),
        ),
      if (!AppInstaller.isSupported)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            kIsWeb
                ? '浏览器环境不支持应用内安装，请使用 Android 手机下载'
                : '当前平台不支持应用内安装（仅支持 Android）',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
        ),
    ];
  }

  Widget _primaryButton(AppUpdateInfo info) {
    final downloading = _downloadPhase == _DownloadPhase.downloading;
    final installing = _downloadPhase == _DownloadPhase.installing;
    final installerOpened = _downloadPhase == _DownloadPhase.installerOpened;
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      onPressed:
          downloading ||
              installing ||
              installerOpened ||
              !AppInstaller.isSupported
          ? null
          : _startDownload,
      child: Text(switch (_downloadPhase) {
        _DownloadPhase.downloading => '正在下载 ${_percentText()}',
        _DownloadPhase.installing => '正在打开系统安装器…',
        _DownloadPhase.installerOpened => '已打开系统安装器',
        _DownloadPhase.readyToInstall => '安装',
        _DownloadPhase.idle => info.isRequired ? '立即更新' : '下载并安装',
      }, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
    );
  }

  String _progressText() {
    final speed = _speedBytesPerSecond > 0
        ? ' · ${_formatBytes(_speedBytesPerSecond.round())}/s'
        : '';
    final remainingBytes = (_total - _received).clamp(0, _total);
    final seconds = _speedBytesPerSecond > 0
        ? (remainingBytes / _speedBytesPerSecond).ceil()
        : 0;
    final eta = seconds > 0
        ? seconds < 60
              ? ' · 约 $seconds 秒'
              : ' · 约 ${(seconds / 60).ceil()} 分钟'
        : '';
    return '${_formatBytes(_received)} / ${_formatBytes(_total)}$speed$eta';
  }

  String _percentText() {
    if (_total <= 0) return '0%';
    return '${((_received / _total) * 100).clamp(0, 100).toStringAsFixed(0)}%';
  }
}

class _UpToDateCard extends StatelessWidget {
  const _UpToDateCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_rounded, color: AppTheme.mint),
                SizedBox(width: 8),
                Text(
                  '已是最新版本',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: const BorderSide(color: AppTheme.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('重新检查'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: onRetry,
              child: const Text('重试'),
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdateBadge extends StatelessWidget {
  const _UpdateBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}
