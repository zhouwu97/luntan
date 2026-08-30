import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_update_service.dart';

/// 更新检查结果的持久化边界。
///
/// 缓存只用于恢复已确认的版本策略，不能替代联网复核，也不保存任何凭证。
abstract interface class AppUpdateCache {
  Future<AppUpdateCacheEntry?> read();

  Future<void> write(AppUpdateCacheEntry entry);

  Future<void> clear();
}

class AppUpdateCacheEntry {
  const AppUpdateCacheEntry({
    required this.info,
    required this.checkedAt,
    required this.requiredPolicy,
  });

  final AppUpdateInfo info;
  final DateTime checkedAt;

  /// 服务端已经确认过的最低版本门禁。该字段与当前响应的 update_type
  /// 分开保存，避免一次临时的 optional/none 响应错误解除历史门禁。
  final bool requiredPolicy;

  bool get isRequired => requiredPolicy || info.isRequired;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      ...info.toJson(),
      'checked_at': checkedAt.toUtc().toIso8601String(),
      'required_policy': requiredPolicy,
    };
  }

  static AppUpdateCacheEntry fromJson(Map<String, dynamic> json) {
    final checkedAtValue = json['checked_at'];
    if (checkedAtValue is! String) {
      throw const FormatException('更新缓存缺少 checked_at');
    }
    final checkedAt = DateTime.tryParse(checkedAtValue);
    if (checkedAt == null) {
      throw const FormatException('更新缓存 checked_at 非法');
    }
    final info = AppUpdateInfo.fromJson(json);
    final requiredPolicyValue = json['required_policy'];
    if (requiredPolicyValue != null && requiredPolicyValue is! bool) {
      throw const FormatException('更新缓存 required_policy 非法');
    }
    return AppUpdateCacheEntry(
      info: info,
      checkedAt: checkedAt.toUtc(),
      // 兼容早期只持久化 update_type 的缓存格式。
      requiredPolicy: requiredPolicyValue ?? info.isRequired,
    );
  }
}

/// 基于 SharedPreferences 的生产缓存实现。
class SharedPreferencesAppUpdateCache implements AppUpdateCache {
  static const storageKey = 'app_update_policy_v1';

  Future<SharedPreferences>? _preferencesFuture;

  Future<SharedPreferences> get _preferences =>
      _preferencesFuture ??= SharedPreferences.getInstance();

  @override
  Future<AppUpdateCacheEntry?> read() async {
    final raw = (await _preferences).getString(storageKey);
    if (raw == null || raw.trim().isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('更新缓存根节点必须是对象');
    }
    return AppUpdateCacheEntry.fromJson(decoded);
  }

  @override
  Future<void> write(AppUpdateCacheEntry entry) async {
    await (await _preferences).setString(
      storageKey,
      jsonEncode(entry.toJson()),
    );
  }

  @override
  Future<void> clear() async {
    await (await _preferences).remove(storageKey);
  }
}

/// 测试及嵌入式调用使用的内存实现，不依赖 Flutter 平台插件。
class MemoryAppUpdateCache implements AppUpdateCache {
  AppUpdateCacheEntry? entry;

  @override
  Future<AppUpdateCacheEntry?> read() async => entry;

  @override
  Future<void> write(AppUpdateCacheEntry value) async {
    entry = value;
  }

  @override
  Future<void> clear() async {
    entry = null;
  }
}
