import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:luntan/controllers/app_update_coordinator.dart';
import 'package:luntan/data/api/app_update_service.dart';
import 'package:luntan/data/api/update_config.dart';

void main() {
  final apkBytes = Uint8List.fromList(List.generate(64, (i) => i));
  final apkSha = crypto.sha256.convert(apkBytes).toString();

  PackageInfo mockPackageInfo({
    String version = '1.0.0',
    String buildNumber = '1',
  }) {
    return PackageInfo(
      appName: 'luntan',
      packageName: 'com.shengbeijiang.luntan',
      version: version,
      buildNumber: buildNumber,
      buildSignature: '',
    );
  }

  String updatePayload({
    bool available = true,
    String updateType = 'optional',
    String latestVersionName = '1.2.0',
    int latestVersionCode = 2,
  }) => jsonEncode({
    'platform': 'android',
    'channel': 'stable',
    'latest_version_name': latestVersionName,
    'latest_version_code': latestVersionCode,
    'minimum_supported_version_code': 1,
    'title': '新版本发布',
    'changelog': '独立更新服务支持',
    'file_name': 'app-release.apk',
    'file_size': available ? apkBytes.length : 0,
    'sha256': available ? apkSha : '',
    'download_url': '/api/v1/app/releases/$latestVersionCode/download',
    'published_at': '2026-08-30T00:00:00Z',
    'check_after_seconds': 21600,
    'update_available': available,
    'update_type': available ? updateType : 'none',
  });

  group('UpdateConfig', () {
    test('resolveUpdateBaseUrl 默认回退到官方正式域名 https://shengbeijiang.com', () {
      final url = resolveUpdateBaseUrl();
      expect(url, 'https://shengbeijiang.com');
    });

    test('resolveUpdateBaseUrl 支持显式 overrideBaseUrl', () {
      final url = resolveUpdateBaseUrl(
        overrideBaseUrl: 'http://custom-update.internal:8080///',
      );
      expect(url, 'http://custom-update.internal:8080');
    });
  });

  group('AppUpdateCoordinator', () {
    test('初始状态为 idle', () {
      final coordinator = AppUpdateCoordinator();
      expect(coordinator.status, AppUpdateStatus.idle);
      expect(coordinator.info, isNull);
      expect(coordinator.isRequired, isFalse);
      coordinator.dispose();
    });

    test('checkUpdate 检测到无更新时变为 upToDate', () async {
      final client = MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(updatePayload(available: false)),
          200,
        );
      });
      final service = AppUpdateService(
        baseUri: Uri.parse('http://server.test'),
        client: client,
      );
      final coordinator = AppUpdateCoordinator(
        service: service,
        packageInfoResolver: () async => mockPackageInfo(),
      );

      final result = await coordinator.checkUpdate();
      expect(result, isNotNull);
      expect(result!.updateAvailable, isFalse);
      expect(coordinator.status, AppUpdateStatus.upToDate);
      expect(coordinator.currentVersionName, '1.0.0');
      coordinator.dispose();
    });

    test('checkUpdate 检测到可选更新时变为 optionalUpdateAvailable', () async {
      final client = MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(updatePayload(available: true, updateType: 'optional')),
          200,
        );
      });
      final service = AppUpdateService(
        baseUri: Uri.parse('http://server.test'),
        client: client,
      );
      final coordinator = AppUpdateCoordinator(
        service: service,
        packageInfoResolver: () async => mockPackageInfo(),
      );

      final result = await coordinator.checkUpdate();
      expect(result, isNotNull);
      expect(result!.updateAvailable, isTrue);
      expect(coordinator.status, AppUpdateStatus.optionalUpdateAvailable);
      expect(coordinator.isRequired, isFalse);
      coordinator.dispose();
    });

    test('checkUpdate 检测到强制更新时锁存 requiredUpdateAvailable', () async {
      final client = MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(updatePayload(available: true, updateType: 'required')),
          200,
        );
      });
      final service = AppUpdateService(
        baseUri: Uri.parse('http://server.test'),
        client: client,
      );
      final coordinator = AppUpdateCoordinator(
        service: service,
        packageInfoResolver: () async => mockPackageInfo(),
      );

      final result = await coordinator.checkUpdate();
      expect(result, isNotNull);
      expect(coordinator.status, AppUpdateStatus.requiredUpdateAvailable);
      expect(coordinator.isRequired, isTrue);
      expect(coordinator.isRequiredLocked, isTrue);
      coordinator.dispose();
    });

    test('强制更新锁存后，后续网络失败不解除强制门禁', () async {
      var callCount = 0;
      final client = MockClient((request) async {
        callCount++;
        if (callCount == 1) {
          return http.Response.bytes(
            utf8.encode(updatePayload(available: true, updateType: 'required')),
            200,
          );
        }
        throw http.ClientException('connection dropped');
      });
      final service = AppUpdateService(
        baseUri: Uri.parse('http://server.test'),
        client: client,
      );
      final coordinator = AppUpdateCoordinator(
        service: service,
        packageInfoResolver: () async => mockPackageInfo(),
      );

      await coordinator.checkUpdate();
      expect(coordinator.status, AppUpdateStatus.requiredUpdateAvailable);

      // 第二次网络异常
      await coordinator.checkUpdate();
      expect(coordinator.status, AppUpdateStatus.requiredUpdateAvailable);
      expect(coordinator.isRequired, isTrue);
      coordinator.dispose();
    });

    test('网络异常时进入 error 状态并记录明确错误分类', () async {
      final client = MockClient((request) async {
        throw const SocketException('Connection refused');
      });
      final service = AppUpdateService(
        baseUri: Uri.parse('http://server.test'),
        client: client,
      );
      final coordinator = AppUpdateCoordinator(
        service: service,
        packageInfoResolver: () async => mockPackageInfo(),
      );

      final result = await coordinator.checkUpdate();
      expect(result, isNull);
      expect(coordinator.status, AppUpdateStatus.error);
      expect(coordinator.errorKind, AppUpdateErrorKind.network);
      expect(coordinator.errorMessage, contains('无法连接更新服务器'));
      coordinator.dispose();
    });
  });
}
