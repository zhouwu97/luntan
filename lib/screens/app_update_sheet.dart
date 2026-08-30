import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../controllers/app_update_coordinator.dart';
import '../data/api/app_update_service.dart';
import '../platform/app_installer.dart';
import '../theme/app_theme.dart';

/// 检查更新流程的底部弹层。
///
/// 状态机：checking → upToDate / available / error；available 内部包含
/// idle / downloading / verifying / readyToInstall / permissionRequired / installing / installerOpened。
///
/// [force] 用于启动强制更新门禁：禁用点遮罩、下拉和返回键关闭，并隐藏
/// 关闭按钮，用户只能更新或重试。
Future<void> showAppUpdateSheet(
  BuildContext context, {
  bool force = false,
  AppUpdateCoordinator? coordinator,
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
    builder: (_) => AppUpdateSheet(force: force, coordinator: coordinator),
  );
}

class AppUpdateSheet extends StatefulWidget {
  const AppUpdateSheet({super.key, this.force = false, this.coordinator});

  final bool force;
  final AppUpdateCoordinator? coordinator;

  @override
  State<AppUpdateSheet> createState() => _AppUpdateSheetState();
}

class _AppUpdateSheetState extends State<AppUpdateSheet> {
  late final AppUpdateCoordinator _coordinator;
  late final bool _ownsCoordinator;

  @override
  void initState() {
    super.initState();
    if (widget.coordinator != null) {
      _coordinator = widget.coordinator!;
      _ownsCoordinator = false;
    } else {
      _coordinator = AppUpdateCoordinator();
      _ownsCoordinator = true;
    }
    _coordinator.addListener(_onCoordinatorChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_coordinator.status == AppUpdateStatus.idle ||
          _coordinator.status == AppUpdateStatus.error) {
        _coordinator.checkUpdate(manual: true, force: widget.force);
      }
    });
  }

  @override
  void dispose() {
    _coordinator.removeListener(_onCoordinatorChanged);
    if (_ownsCoordinator) {
      _coordinator.dispose();
    }
    super.dispose();
  }

  void _onCoordinatorChanged() {
    if (mounted) setState(() {});
  }

  bool get _isForce => widget.force || _coordinator.isRequired;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isForce,
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.88,
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
                    if (!_isForce)
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
                ..._buildContent(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _statusSubtitle() {
    switch (_coordinator.status) {
      case AppUpdateStatus.checking:
        return '正在连接更新服务器…';
      case AppUpdateStatus.upToDate:
        return _coordinator.currentVersionName.isNotEmpty
            ? '当前版本 v${_coordinator.currentVersionName} 已是最新'
            : '当前已是最新版本';
      case AppUpdateStatus.optionalUpdateAvailable:
      case AppUpdateStatus.requiredUpdateAvailable:
      case AppUpdateStatus.downloading:
      case AppUpdateStatus.verifying:
      case AppUpdateStatus.readyToInstall:
      case AppUpdateStatus.installing:
      case AppUpdateStatus.installerOpened:
      case AppUpdateStatus.permissionRequired:
        final ver = _coordinator.info?.latestVersionName;
        return ver != null && ver.isNotEmpty
            ? '发现新版本 v$ver'
            : '发现新版本';
      case AppUpdateStatus.error:
        return '检查更新失败';
      case AppUpdateStatus.idle:
        return '准备检查更新…';
    }
  }

  List<Widget> _buildContent() {
    switch (_coordinator.status) {
      case AppUpdateStatus.idle:
      case AppUpdateStatus.checking:
        return [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 36),
            child: Column(
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                SizedBox(height: 14),
                Text(
                  '正在检查新版本…',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ];

      case AppUpdateStatus.upToDate:
        return [
          _UpToDateCard(
            versionName: _coordinator.currentVersionName,
            onRetry: () => _coordinator.checkUpdate(manual: true),
          ),
        ];

      case AppUpdateStatus.error:
        return [
          _ErrorCard(
            message: _resolveDisplayErrorMessage(),
            onRetry: () => _coordinator.checkUpdate(manual: true, force: widget.force),
          ),
        ];

      case AppUpdateStatus.optionalUpdateAvailable:
      case AppUpdateStatus.requiredUpdateAvailable:
      case AppUpdateStatus.downloading:
      case AppUpdateStatus.verifying:
      case AppUpdateStatus.readyToInstall:
      case AppUpdateStatus.installing:
      case AppUpdateStatus.installerOpened:
      case AppUpdateStatus.permissionRequired:
        return _buildUpdateAvailableBody();
    }
  }

  String _resolveDisplayErrorMessage() {
    final msg = _coordinator.errorMessage;
    if (msg != null && msg.isNotEmpty) return msg;

    switch (_coordinator.errorKind) {
      case AppUpdateErrorKind.network:
        return '无法连接更新服务器，请检查网络后重试';
      case AppUpdateErrorKind.server:
        return '更新服务暂不可用，请稍后重试';
      case AppUpdateErrorKind.protocol:
        return '更新信息异常，请稍后重试';
      case null:
        return '检查更新失败，请稍后重试';
    }
  }

  List<Widget> _buildUpdateAvailableBody() {
    final info = _coordinator.info;
    if (info == null) return const [];

    final isDownloading = _coordinator.status == AppUpdateStatus.downloading;
    final isVerifying = _coordinator.status == AppUpdateStatus.verifying;
    final isPermissionRequired =
        _coordinator.status == AppUpdateStatus.permissionRequired;
    final isReadyToInstall =
        _coordinator.status == AppUpdateStatus.readyToInstall;
    final isInstalling = _coordinator.status == AppUpdateStatus.installing;
    final isInstallerOpened =
        _coordinator.status == AppUpdateStatus.installerOpened;

    return [
      // 版本详情卡片
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
                if (_isForce)
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

      // 下载中进度卡片
      if (isDownloading) ...[
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
                    value: _coordinator.downloadProgress,
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
                      onPressed: _coordinator.cancelDownload,
                      child: const Text('取消'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],

      // 正在校验状态
      if (isVerifying) ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.surfaceBlue,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          ),
          child: const Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
              SizedBox(width: 10),
              Text(
                '正在校验安装包完整性 (SHA-256)…',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
        ),
      ],

      // 权限提示或错误提示
      if (_coordinator.errorMessage != null && !isDownloading && !isVerifying)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.pink.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 16, color: AppTheme.pink),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _coordinator.errorMessage!,
                    style: const TextStyle(fontSize: 12, color: AppTheme.pink),
                  ),
                ),
              ],
            ),
          ),
        ),

      const SizedBox(height: 16),

      // 操作按钮组
      if (isPermissionRequired) ...[
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: _coordinator.openPermissionSettings,
          icon: const Icon(Icons.security_rounded, size: 18),
          label: const Text(
            '前往开启“安装未知应用”权限',
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.textPrimary,
            minimumSize: const Size.fromHeight(44),
            side: const BorderSide(color: AppTheme.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: _coordinator.installApk,
          child: const Text('已授权，继续安装'),
        ),
      ] else if (isInstallerOpened) ...[
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: _coordinator.installApk,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text(
            '重新唤起系统安装器',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
      ] else ...[
        Row(
          children: [
            if (!_isForce && !isDownloading && !isInstalling && !isVerifying) ...[
              Expanded(
                flex: 1,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textSecondary,
                    minimumSize: const Size.fromHeight(48),
                    side: const BorderSide(color: AppTheme.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    '稍后更新',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              flex: 2,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: (isDownloading || isInstalling || isVerifying || !AppInstaller.isSupported)
                    ? null
                    : (isReadyToInstall
                        ? _coordinator.installApk
                        : _coordinator.startDownload),
                child: Text(
                  _actionButtonText(
                    isDownloading: isDownloading,
                    isVerifying: isVerifying,
                    isInstalling: isInstalling,
                    isReadyToInstall: isReadyToInstall,
                    isRequired: _isForce,
                  ),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ],

      if (!AppInstaller.isSupported)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            kIsWeb
                ? '浏览器环境不支持应用内安装，请使用 Android 手机客户端'
                : '当前平台不支持应用内安装（仅支持 Android）',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
        ),
    ];
  }

  String _actionButtonText({
    required bool isDownloading,
    required bool isVerifying,
    required bool isInstalling,
    required bool isReadyToInstall,
    required bool isRequired,
  }) {
    if (isDownloading) return '正在下载 ${_percentText()}';
    if (isVerifying) return '正在校验…';
    if (isInstalling) return '正在打开系统安装器…';
    if (isReadyToInstall) return '立即安装';
    return isRequired ? '立即更新' : '立即更新';
  }

  String _progressText() {
    final speed = _coordinator.speedBytesPerSecond > 0
        ? ' · ${_formatBytes(_coordinator.speedBytesPerSecond.round())}/s'
        : '';
    final total = _coordinator.totalBytes;
    final received = _coordinator.receivedBytes;
    final remainingBytes = (total - received).clamp(0, total);
    final seconds = _coordinator.speedBytesPerSecond > 0
        ? (remainingBytes / _coordinator.speedBytesPerSecond).ceil()
        : 0;
    final eta = seconds > 0
        ? seconds < 60
            ? ' · 约 $seconds 秒'
            : ' · 约 ${(seconds / 60).ceil()} 分钟'
        : '';
    return '${_formatBytes(received)} / ${_formatBytes(total)}$speed$eta';
  }

  String _percentText() {
    final total = _coordinator.totalBytes;
    if (total <= 0) return '0%';
    final received = _coordinator.receivedBytes;
    return '${((received / total) * 100).clamp(0, 100).toStringAsFixed(0)}%';
  }
}

class _UpToDateCard extends StatelessWidget {
  const _UpToDateCard({required this.versionName, required this.onRetry});

  final String versionName;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppTheme.mint.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: AppTheme.mint,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '已是最新版本',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (versionName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '当前版本：v$versionName',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
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
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.pink.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.cloud_off_rounded,
                    color: AppTheme.pink,
                    size: 26,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppTheme.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
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
