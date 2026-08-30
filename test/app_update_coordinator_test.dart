import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:luntan/controllers/app_update_coordinator.dart';
import 'package:luntan/data/api/app_update_cache.dart';
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
    int minimumSupportedVersionCode = 1,
    Uint8List? packageBytes,
    String? packageSha,
  }) => jsonEncode({
    'platform': 'android',
    'channel': 'stable',
    'latest_version_name': latestVersionName,
    'latest_version_code': latestVersionCode,
    'minimum_supported_version_code': minimumSupportedVersionCode,
    'title': '新版本发布',
    'changelog': '独立更新服务支持',
    'file_name': 'app-release.apk',
    'file_size': available ? (packageBytes ?? apkBytes).length : 0,
    'sha256': available ? (packageSha ?? apkSha) : '',
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

    test('production 更新服务拒绝 HTTP 地址和不完整地址', () {
      expect(
        () => resolveUpdateBaseUrl(
          overrideBaseUrl: 'http://updates.example.com',
          appEnv: 'production',
          releaseBuild: false,
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        () => resolveUpdateBaseUrl(
          overrideBaseUrl: 'updates.example.com',
          appEnv: 'production',
          releaseBuild: false,
        ),
        throwsA(isA<StateError>()),
      );
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

    test('force 不会把可选更新变成强制更新', () async {
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

      await coordinator.checkUpdate(force: true);

      expect(coordinator.status, AppUpdateStatus.optionalUpdateAvailable);
      expect(coordinator.isRequired, isFalse);
      coordinator.dispose();
    });

    test('授权返回后可恢复待安装流程并唤起系统安装器', () async {
      final root = await Directory.systemTemp.createTemp(
        'coordinator_permission_resume_test',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      var permissionAllowed = false;
      var installCalls = 0;
      final coordinator = AppUpdateCoordinator(
        cache: MemoryAppUpdateCache(),
        installerSupported: true,
        canInstallPackagesResolver: () async => permissionAllowed,
        installApkHandler: (_) async => installCalls++,
        service: AppUpdateService(
          baseUri: Uri.parse('http://server.test'),
          client: MockClient((request) async {
            if (request.url.path == '/api/v1/app/update') {
              return http.Response.bytes(utf8.encode(updatePayload()), 200);
            }
            return http.Response.bytes(apkBytes, 200);
          }),
          downloadDirResolver: () async => root,
        ),
        packageInfoResolver: () async => mockPackageInfo(),
      );

      await coordinator.checkUpdate();
      await coordinator.startDownload();

      expect(coordinator.status, AppUpdateStatus.permissionRequired);
      expect(installCalls, 0);

      permissionAllowed = true;
      expect(await coordinator.resumePendingInstall(), isTrue);
      expect(coordinator.status, AppUpdateStatus.installerOpened);
      expect(installCalls, 1);
      coordinator.dispose();
    });

    test('required 策略在协调器重建且断网后仍保持版本门禁', () async {
      final cache = MemoryAppUpdateCache();
      final firstCoordinator = AppUpdateCoordinator(
        cache: cache,
        service: AppUpdateService(
          baseUri: Uri.parse('http://server.test'),
          client: MockClient((request) async {
            return http.Response.bytes(
              utf8.encode(
                updatePayload(
                  updateType: 'required',
                  minimumSupportedVersionCode: 2,
                ),
              ),
              200,
            );
          }),
        ),
        packageInfoResolver: () async => mockPackageInfo(),
      );

      await firstCoordinator.checkUpdate();
      expect(firstCoordinator.isRequired, isTrue);
      firstCoordinator.dispose();

      final restartedCoordinator = AppUpdateCoordinator(
        cache: cache,
        service: AppUpdateService(
          baseUri: Uri.parse('http://server.test'),
          client: MockClient((request) async {
            throw const SocketException('offline');
          }),
        ),
        packageInfoResolver: () async => mockPackageInfo(),
      );

      final result = await restartedCoordinator.checkUpdate();

      expect(result, isNull);
      expect(
        restartedCoordinator.status,
        AppUpdateStatus.requiredUpdateAvailable,
      );
      expect(restartedCoordinator.isRequired, isTrue);
      expect(restartedCoordinator.info?.latestVersionCode, 2);
      restartedCoordinator.dispose();
    });

    test('并发 checkUpdate 共享同一个请求，旧结果不会覆盖新状态', () async {
      final responseCompleter = Completer<http.Response>();
      var requestCount = 0;
      final coordinator = AppUpdateCoordinator(
        cache: MemoryAppUpdateCache(),
        service: AppUpdateService(
          baseUri: Uri.parse('http://server.test'),
          client: MockClient((request) async {
            requestCount++;
            return responseCompleter.future;
          }),
        ),
        packageInfoResolver: () async => mockPackageInfo(),
      );

      final first = coordinator.checkUpdate();
      final second = coordinator.checkUpdate(manual: true);
      await Future<void>.delayed(Duration.zero);
      expect(requestCount, 1);

      responseCompleter.complete(
        http.Response.bytes(
          utf8.encode(updatePayload(latestVersionCode: 3)),
          200,
        ),
      );
      final results = await Future.wait([first, second]);

      expect(results[0]?.latestVersionCode, 3);
      expect(results[1]?.latestVersionCode, 3);
      expect(coordinator.info?.latestVersionCode, 3);
      expect(coordinator.status, AppUpdateStatus.optionalUpdateAvailable);
      coordinator.dispose();
    });

    test('发布新版本后不会复用旧版本已下载的 APK', () async {
      final v2Bytes = Uint8List.fromList(List.generate(64, (i) => i));
      final v3Bytes = Uint8List.fromList(List.generate(64, (i) => 255 - i));
      final v2Sha = crypto.sha256.convert(v2Bytes).toString();
      final v3Sha = crypto.sha256.convert(v3Bytes).toString();
      var checkCount = 0;
      final downloadedCodes = <String>[];
      final root = await Directory.systemTemp.createTemp(
        'coordinator_update_test',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      final coordinator = AppUpdateCoordinator(
        cache: MemoryAppUpdateCache(),
        service: AppUpdateService(
          baseUri: Uri.parse('http://server.test'),
          client: MockClient((request) async {
            if (request.url.path == '/api/v1/app/update') {
              checkCount++;
              final isV3 = checkCount > 1;
              final code = isV3 ? 3 : 2;
              final bytes = isV3 ? v3Bytes : v2Bytes;
              final sha = isV3 ? v3Sha : v2Sha;
              return http.Response.bytes(
                utf8.encode(
                  updatePayload(
                    latestVersionName: isV3 ? '1.3.0' : '1.2.0',
                    latestVersionCode: code,
                    packageBytes: bytes,
                    packageSha: sha,
                  ),
                ),
                200,
              );
            }
            downloadedCodes.add(request.url.pathSegments[4]);
            final bytes = request.url.path.contains('/2/') ? v2Bytes : v3Bytes;
            return http.Response.bytes(bytes, 200);
          }),
          downloadDirResolver: () async => root,
        ),
        packageInfoResolver: () async => mockPackageInfo(),
      );

      await coordinator.checkUpdate();
      await coordinator.startDownload();
      await coordinator.checkUpdate(manual: true);
      await coordinator.startDownload();

      expect(downloadedCodes, ['2', '3']);
      expect(await coordinator.downloadedFile!.readAsBytes(), v3Bytes);
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
