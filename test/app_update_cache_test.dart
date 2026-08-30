import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/data/api/app_update_cache.dart';
import 'package:luntan/data/api/app_update_service.dart';

void main() {
  final info = AppUpdateInfo(
    updateAvailable: true,
    updateType: 'required',
    latestVersionName: '1.2.0',
    latestVersionCode: 12,
    minimumSupportedVersionCode: 10,
    title: '更新',
    changelog: '修复',
    fileSize: 64,
    sha256: 'a' * 64,
    downloadUrl: '/api/v1/app/releases/12/download',
  );

  test('required 策略缓存可序列化并恢复', () {
    final entry = AppUpdateCacheEntry(
      info: info,
      checkedAt: DateTime.utc(2026, 8, 30, 12),
      requiredPolicy: true,
    );

    final restored = AppUpdateCacheEntry.fromJson(entry.toJson());

    expect(restored.info.latestVersionCode, 12);
    expect(restored.info.minimumSupportedVersionCode, 10);
    expect(restored.info.sha256, 'a' * 64);
    expect(restored.checkedAt, DateTime.utc(2026, 8, 30, 12));
    expect(restored.requiredPolicy, isTrue);
    expect(restored.isRequired, isTrue);
  });

  test('兼容只保存 update_type 的旧缓存格式', () {
    final legacy = <String, dynamic>{
      ...info.toJson(),
      'checked_at': '2026-08-30T12:00:00Z',
    };

    final restored = AppUpdateCacheEntry.fromJson(legacy);

    expect(restored.requiredPolicy, isTrue);
    expect(restored.isRequired, isTrue);
  });
}
