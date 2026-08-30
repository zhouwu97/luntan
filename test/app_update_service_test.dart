import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:luntan/data/api/app_update_service.dart';

void main() {
  // 固定的 64 字节测试安装包与其 SHA-256。
  final apkBytes = Uint8List.fromList(List.generate(64, (i) => i));
  final apkSha = crypto.sha256.convert(apkBytes).toString();

  String updatePayload({bool available = true}) => jsonEncode({
    'platform': 'android',
    'channel': 'stable',
    'latest_version_name': '1.2.0',
    'latest_version_code': 3,
    'minimum_supported_version_code': 1,
    'title': '新版本发布',
    'changelog': '修复了下载链路问题',
    'file_name': 'app-release.apk',
    'file_size': available ? apkBytes.length : 0,
    'sha256': available ? apkSha : '',
    'download_url': '/api/v1/app/releases/3/download',
    'published_at': '2026-08-30T00:00:00Z',
    'check_after_seconds': 21600,
    'update_available': available,
    'update_type': available ? 'optional' : 'none',
  });

  Future<Directory> tempDirResolver(Directory root) async {
    final dir = Directory.fromUri(root.uri.resolve('downloads'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  test('checkUpdate 正确解析有更新的响应', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/v1/app/update');
      expect(request.url.queryParameters['version_code'], '1');
      expect(request.headers['X-App-Version-Code'], '1');
      return http.Response.bytes(utf8.encode(updatePayload()), 200);
    });
    final service = AppUpdateService(
      baseUri: Uri.parse('http://server.test'),
      client: client,
    );
    final info = await service.checkUpdate(
      versionName: '1.0.0',
      versionCode: 1,
    );
    expect(info.updateAvailable, isTrue);
    expect(info.updateType, 'optional');
    expect(info.latestVersionName, '1.2.0');
    expect(info.latestVersionCode, 3);
    expect(info.sha256, apkSha);
    expect(info.downloadUrl, '/api/v1/app/releases/3/download');
  });

  test('checkUpdate 网络失败与 5xx 分类正确', () async {
    final client = MockClient((request) async {
      throw http.ClientException('boom');
    });
    final service = AppUpdateService(
      baseUri: Uri.parse('http://server.test'),
      client: client,
    );
    await expectLater(
      service.checkUpdate(versionName: '1.0.0', versionCode: 1),
      throwsA(
        isA<AppUpdateException>().having(
          (e) => e.kind,
          'kind',
          AppUpdateErrorKind.network,
        ),
      ),
    );

    final serverError = AppUpdateService(
      baseUri: Uri.parse('http://server.test'),
      client: MockClient((request) async => http.Response('down', 503)),
    );
    await expectLater(
      serverError.checkUpdate(versionName: '1.0.0', versionCode: 1),
      throwsA(
        isA<AppUpdateException>().having(
          (e) => e.kind,
          'kind',
          AppUpdateErrorKind.server,
        ),
      ),
    );
  });

  test('downloadApk 下载完成后校验并落盘', () async {
    final root = await Directory.systemTemp.createTemp('update_test');
    addTearDown(() => root.deleteSync(recursive: true));
    final client = MockClient.streaming((request, bodyStream) async {
      return http.StreamedResponse(
        Stream<List<int>>.fromIterable([apkBytes]),
        200,
        contentLength: apkBytes.length,
      );
    });
    final service = AppUpdateService(
      baseUri: Uri.parse('http://server.test'),
      client: client,
      downloadDirResolver: () => tempDirResolver(root),
    );
    final info = AppUpdateInfo(
      updateAvailable: true,
      updateType: 'optional',
      latestVersionName: '1.2.0',
      latestVersionCode: 3,
      minimumSupportedVersionCode: 1,
      title: 't',
      changelog: 'c',
      fileSize: apkBytes.length,
      sha256: apkSha,
      downloadUrl: '/api/v1/app/releases/3/download',
    );
    final file = await service.downloadApk(info: info);
    expect(await file.length(), apkBytes.length);
    expect(file.path.endsWith('.apk'), isTrue);
    expect(file.parent.path.contains('app_updates'), isTrue);
  });

  test('downloadApk SHA-256 不匹配时报错并清理 .part 文件', () async {
    final root = await Directory.systemTemp.createTemp('update_test');
    addTearDown(() => root.deleteSync(recursive: true));
    final badBytes = Uint8List.fromList([...apkBytes.take(63), 255]);
    final client = MockClient.streaming((request, bodyStream) async {
      return http.StreamedResponse(
        Stream<List<int>>.fromIterable([badBytes]),
        200,
        contentLength: badBytes.length,
      );
    });
    final service = AppUpdateService(
      baseUri: Uri.parse('http://server.test'),
      client: client,
      downloadDirResolver: () => tempDirResolver(root),
    );
    final info = AppUpdateInfo(
      updateAvailable: true,
      updateType: 'optional',
      latestVersionName: '1.2.0',
      latestVersionCode: 3,
      minimumSupportedVersionCode: 1,
      title: 't',
      changelog: 'c',
      fileSize: badBytes.length,
      sha256: apkSha,
      downloadUrl: '/download',
    );
    await expectLater(
      service.downloadApk(info: info),
      throwsA(isA<AppUpdateException>()),
    );
    final downloadDir = Directory.fromUri(root.uri.resolve('downloads'));
    expect(
      downloadDir.listSync().where((e) => e.path.endsWith('.part')),
      isEmpty,
    );
  });

  test('downloadApk 断点续传发送 Range 且拼接成功', () async {
    final root = await Directory.systemTemp.createTemp('update_test');
    addTearDown(() => root.deleteSync(recursive: true));
    final downloadDir = await tempDirResolver(root);
    final appUpdatesDir = Directory(
      '${downloadDir.path}${Platform.pathSeparator}app_updates',
    )..createSync(recursive: true);
    final partFile = File(
      '${appUpdatesDir.path}${Platform.pathSeparator}update-$apkSha.apk.part',
    );
    await partFile.writeAsBytes(apkBytes.sublist(0, 20));

    String? rangeHeader;
    final client = MockClient.streaming((request, bodyStream) async {
      rangeHeader = request.headers['Range'];
      return http.StreamedResponse(
        Stream<List<int>>.fromIterable([apkBytes.sublist(20)]),
        206,
        contentLength: apkBytes.length - 20,
        headers: {'content-range': 'bytes 20-63/64'},
      );
    });
    final service = AppUpdateService(
      baseUri: Uri.parse('http://server.test'),
      client: client,
      downloadDirResolver: () => tempDirResolver(root),
    );
    final info = AppUpdateInfo(
      updateAvailable: true,
      updateType: 'optional',
      latestVersionName: '1.2.0',
      latestVersionCode: 3,
      minimumSupportedVersionCode: 1,
      title: 't',
      changelog: 'c',
      fileSize: apkBytes.length,
      sha256: apkSha,
      downloadUrl: '/download',
    );
    final file = await service.downloadApk(info: info);
    expect(rangeHeader, 'bytes=20-');
    expect(await file.length(), apkBytes.length);
    expect(await partFile.exists(), isFalse);
  });

  test('无更新响应解析为 updateAvailable=false', () async {
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
    final info = await service.checkUpdate(
      versionName: '1.2.0',
      versionCode: 3,
    );
    expect(info.updateAvailable, isFalse);
    expect(info.updateType, 'none');
  });

  test('downloadApk 续传偏移异常时清理分片并重新完整下载', () async {
    final root = await Directory.systemTemp.createTemp('update_test');
    addTearDown(() => root.deleteSync(recursive: true));
    final downloadDir = await tempDirResolver(root);
    final appUpdatesDir = Directory(
      '${downloadDir.path}${Platform.pathSeparator}app_updates',
    )..createSync(recursive: true);
    final partFile = File(
      '${appUpdatesDir.path}${Platform.pathSeparator}update-$apkSha.apk.part',
    );
    await partFile.writeAsBytes(apkBytes.sublist(0, 20));

    var requests = 0;
    final client = MockClient.streaming((request, bodyStream) async {
      requests += 1;
      if (requests == 1) {
        expect(request.headers['Range'], 'bytes=20-');
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([apkBytes.sublist(10)]),
          206,
          contentLength: apkBytes.length - 10,
          headers: {'content-range': 'bytes 10-63/64'},
        );
      }
      expect(request.headers['Range'], isNull);
      return http.StreamedResponse(
        Stream<List<int>>.fromIterable([apkBytes]),
        200,
        contentLength: apkBytes.length,
      );
    });
    final service = AppUpdateService(
      baseUri: Uri.parse('http://server.test'),
      client: client,
      downloadDirResolver: () => tempDirResolver(root),
    );
    final info = AppUpdateInfo(
      updateAvailable: true,
      updateType: 'optional',
      latestVersionName: '1.2.0',
      latestVersionCode: 3,
      minimumSupportedVersionCode: 1,
      title: 't',
      changelog: 'c',
      fileSize: apkBytes.length,
      sha256: apkSha,
      downloadUrl: '/download',
    );

    final file = await service.downloadApk(info: info);
    expect(requests, 2);
    expect(await file.readAsBytes(), apkBytes);
  });

  test('checkUpdate 拒绝相互矛盾或不完整的更新响应', () async {
    final payload = jsonDecode(updatePayload()) as Map<String, dynamic>
      ..['update_type'] = 'none';
    final service = AppUpdateService(
      baseUri: Uri.parse('http://server.test'),
      client: MockClient(
        (_) async => http.Response.bytes(utf8.encode(jsonEncode(payload)), 200),
      ),
    );

    await expectLater(
      service.checkUpdate(versionName: '1.0.0', versionCode: 1),
      throwsA(
        isA<AppUpdateException>().having(
          (error) => error.kind,
          'kind',
          AppUpdateErrorKind.protocol,
        ),
      ),
    );
  });
}
