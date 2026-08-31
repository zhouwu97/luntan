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

  test('production 更新服务拒绝 HTTP Base URL', () {
    expect(
      () => AppUpdateService(
        baseUri: Uri.parse('http://updates.example.com'),
        productionBuild: true,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('production 检查拒绝 HTTP absolute download_url', () async {
    final payload = jsonDecode(updatePayload()) as Map<String, dynamic>
      ..['download_url'] = 'http://cdn.example.com/app-release.apk';
    final service = AppUpdateService(
      baseUri: Uri.parse('https://updates.example.com'),
      productionBuild: true,
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
    service.close();
  });

  test('production 拒绝未编入 allowlist 的 CDN absolute download_url', () async {
    final service = AppUpdateService(
      baseUri: Uri.parse('https://updates.example.com'),
      productionBuild: true,
      client: MockClient((request) async {
        fail('非 allowlist 主机不应发起网络请求');
      }),
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
      downloadUrl: 'https://cdn.example.com/releases/app.apk?sig=stable',
    );

    await expectLater(
      service.downloadApk(info: info),
      throwsA(
        isA<AppUpdateException>()
            .having((error) => error.kind, 'kind', AppUpdateErrorKind.protocol)
            .having(
              (error) => error.message,
              'message',
              contains('不在允许列表中'),
            ),
      ),
    );
    service.close();
  });

  test('production 允许同 host 的 HTTPS absolute download_url', () async {
    final root = await Directory.systemTemp.createTemp('update_test');
    addTearDown(() => root.deleteSync(recursive: true));
    String? requestedUrl;
    final client = MockClient.streaming((request, bodyStream) async {
      requestedUrl = request.url.toString();
      return http.StreamedResponse(
        Stream<List<int>>.fromIterable([apkBytes]),
        200,
        contentLength: apkBytes.length,
      );
    });
    final service = AppUpdateService(
      baseUri: Uri.parse('https://updates.example.com'),
      productionBuild: true,
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
      downloadUrl: 'https://updates.example.com/releases/app.apk?sig=stable',
    );

    await service.downloadApk(info: info);

    expect(
      requestedUrl,
      'https://updates.example.com/releases/app.apk?sig=stable',
    );
    service.close();
  });

  test('下载重定向到非 allowlist 主机被拒绝', () async {
    final root = await Directory.systemTemp.createTemp('update_test');
    addTearDown(() => root.deleteSync(recursive: true));
    final client = MockClient.streaming((request, bodyStream) async {
      return http.StreamedResponse(
        Stream<List<int>>.empty(),
        302,
        headers: {'location': 'https://evil.example.com/app.apk'},
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

    await expectLater(
      service.downloadApk(info: info),
      throwsA(
        isA<AppUpdateException>()
            .having((error) => error.kind, 'kind', AppUpdateErrorKind.protocol)
            .having(
              (error) => error.message,
              'message',
              contains('不在允许列表中'),
            ),
      ),
    );
    service.close();
  });

  test('下载重定向到 allowlist 主机的相对 Location 正常跟随', () async {
    final root = await Directory.systemTemp.createTemp('update_test');
    addTearDown(() => root.deleteSync(recursive: true));
    final requestedUrls = <String>[];
    final client = MockClient.streaming((request, bodyStream) async {
      requestedUrls.add(request.url.toString());
      if (request.url.path == '/api/v1/app/releases/3/download') {
        return http.StreamedResponse(
          Stream<List<int>>.empty(),
          302,
          headers: {'location': '/files/app-release.apk'},
        );
      }
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

    expect(requestedUrls, [
      'http://server.test/api/v1/app/releases/3/download',
      'http://server.test/files/app-release.apk',
    ]);
    expect(await file.length(), apkBytes.length);
    service.close();
  });

  test('downloadApk 拒绝下载地址路径穿越和协议相对地址', () async {
    final service = AppUpdateService(
      baseUri: Uri.parse('http://server.test'),
      client: MockClient((request) async {
        fail('非法下载地址不应发起网络请求');
      }),
    );
    AppUpdateInfo info(String url) => AppUpdateInfo(
      updateAvailable: true,
      updateType: 'optional',
      latestVersionName: '1.2.0',
      latestVersionCode: 3,
      minimumSupportedVersionCode: 1,
      title: 't',
      changelog: 'c',
      fileSize: apkBytes.length,
      sha256: apkSha,
      downloadUrl: url,
    );

    for (final value in ['/../outside.apk', '//evil.example.com/app.apk']) {
      await expectLater(
        service.downloadApk(info: info(value)),
        throwsA(
          isA<AppUpdateException>().having(
            (error) => error.kind,
            'kind',
            AppUpdateErrorKind.protocol,
          ),
        ),
      );
    }
    service.close();
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

  test('大安装包使用四路 Range 下载并合并校验', () async {
    final largeBytes = Uint8List.fromList(
      List<int>.generate(16 * 1024 * 1024, (index) => index % 251),
    );
    final largeSha = crypto.sha256.convert(largeBytes).toString();
    final root = await Directory.systemTemp.createTemp('update_test');
    addTearDown(() => root.deleteSync(recursive: true));
    final ranges = <String>[];
    final client = MockClient.streaming((request, bodyStream) async {
      final range = request.headers['Range'];
      expect(range, isNotNull);
      ranges.add(range!);
      final match = RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(range);
      expect(match, isNotNull);
      final start = int.parse(match!.group(1)!);
      final end = int.parse(match.group(2)!);
      expect(start, lessThanOrEqualTo(end));
      final bytes = largeBytes.sublist(start, end + 1);
      return http.StreamedResponse(
        Stream<List<int>>.value(bytes),
        206,
        contentLength: bytes.length,
        headers: {
          'content-range': 'bytes $start-$end/${largeBytes.length}',
          'etag': '"$largeSha"',
        },
      );
    });
    final service = AppUpdateService(
      baseUri: Uri.parse('http://server.test'),
      client: client,
      downloadDirResolver: () => tempDirResolver(root),
    );
    addTearDown(service.close);
    final progress = <int>[];
    final info = AppUpdateInfo(
      updateAvailable: true,
      updateType: 'optional',
      latestVersionName: '1.2.0',
      latestVersionCode: 4,
      minimumSupportedVersionCode: 1,
      title: 't',
      changelog: 'c',
      fileSize: largeBytes.length,
      sha256: largeSha,
      downloadUrl: '/download',
    );

    final file = await service.downloadApk(
      info: info,
      onProgress: (received, total) {
        expect(total, largeBytes.length);
        progress.add(received);
      },
    );

    expect(ranges, contains('bytes=0-0'));
    expect(ranges.where((range) => range != 'bytes=0-0'), hasLength(4));
    expect(await file.readAsBytes(), largeBytes);
    expect(progress.last, largeBytes.length);
    expect(
      Directory(
        '${file.parent.path}${Platform.pathSeparator}update-4-$largeSha.parts',
      ).existsSync(),
      isFalse,
    );
  });

  test('大安装包按分片断点续传已存在的分片', () async {
    final largeBytes = Uint8List.fromList(
      List<int>.generate(16 * 1024 * 1024, (index) => index % 251),
    );
    final largeSha = crypto.sha256.convert(largeBytes).toString();
    final root = await Directory.systemTemp.createTemp('update_test');
    addTearDown(() => root.deleteSync(recursive: true));
    final downloadDir = await tempDirResolver(root);
    final appUpdatesDirectory = Directory(
      '${downloadDir.path}${Platform.pathSeparator}app_updates',
    )..createSync(recursive: true);
    final partsDirectory = Directory(
      '${appUpdatesDirectory.path}${Platform.pathSeparator}update-6-$largeSha.parts',
    )..createSync(recursive: true);
    await File(
      '${partsDirectory.path}${Platform.pathSeparator}metadata.json',
    ).writeAsString(
      jsonEncode({
        'total_bytes': largeBytes.length,
        'part_count': 4,
        'etag': '"$largeSha"',
      }),
    );
    await File(
      '${partsDirectory.path}${Platform.pathSeparator}part-0.part',
    ).writeAsBytes(largeBytes.sublist(0, 10));

    final ranges = <String>[];
    final client = MockClient.streaming((request, bodyStream) async {
      final range = request.headers['Range'];
      expect(range, isNotNull);
      ranges.add(range!);
      final match = RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(range);
      expect(match, isNotNull);
      final start = int.parse(match!.group(1)!);
      final end = int.parse(match.group(2)!);
      final bytes = largeBytes.sublist(start, end + 1);
      return http.StreamedResponse(
        Stream<List<int>>.value(bytes),
        206,
        contentLength: bytes.length,
        headers: {
          'content-range': 'bytes $start-$end/${largeBytes.length}',
          'etag': '"$largeSha"',
        },
      );
    });
    final service = AppUpdateService(
      baseUri: Uri.parse('http://server.test'),
      client: client,
      downloadDirResolver: () => tempDirResolver(root),
    );
    addTearDown(service.close);
    final info = AppUpdateInfo(
      updateAvailable: true,
      updateType: 'optional',
      latestVersionName: '1.2.0',
      latestVersionCode: 6,
      minimumSupportedVersionCode: 1,
      title: 't',
      changelog: 'c',
      fileSize: largeBytes.length,
      sha256: largeSha,
      downloadUrl: '/download',
    );

    final file = await service.downloadApk(info: info);

    expect(ranges, contains('bytes=0-0'));
    expect(ranges, contains('bytes=10-4194303'));
    expect(ranges, hasLength(5));
    expect(await file.readAsBytes(), largeBytes);
  });

  test('服务器不支持 Range 时回退到单连接下载', () async {
    final largeBytes = Uint8List.fromList(
      List<int>.generate(16 * 1024 * 1024, (index) => index % 251),
    );
    final largeSha = crypto.sha256.convert(largeBytes).toString();
    final root = await Directory.systemTemp.createTemp('update_test');
    addTearDown(() => root.deleteSync(recursive: true));
    final ranges = <String?>[];
    final client = MockClient.streaming((request, bodyStream) async {
      ranges.add(request.headers['Range']);
      return http.StreamedResponse(
        Stream<List<int>>.value(largeBytes),
        200,
        contentLength: largeBytes.length,
      );
    });
    final service = AppUpdateService(
      baseUri: Uri.parse('http://server.test'),
      client: client,
      downloadDirResolver: () => tempDirResolver(root),
    );
    addTearDown(service.close);
    final info = AppUpdateInfo(
      updateAvailable: true,
      updateType: 'optional',
      latestVersionName: '1.2.0',
      latestVersionCode: 5,
      minimumSupportedVersionCode: 1,
      title: 't',
      changelog: 'c',
      fileSize: largeBytes.length,
      sha256: largeSha,
      downloadUrl: '/download',
    );

    final file = await service.downloadApk(info: info);

    expect(ranges, ['bytes=0-0', null]);
    expect(await file.readAsBytes(), largeBytes);
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
      '${appUpdatesDir.path}${Platform.pathSeparator}update-3-$apkSha.apk.part',
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

  test('downloadApk 收到 416 后清理分片并从头下载', () async {
    final root = await Directory.systemTemp.createTemp('update_test');
    addTearDown(() => root.deleteSync(recursive: true));
    final downloadDir = await tempDirResolver(root);
    final appUpdatesDir = Directory(
      '${downloadDir.path}${Platform.pathSeparator}app_updates',
    )..createSync(recursive: true);
    final partFile = File(
      '${appUpdatesDir.path}${Platform.pathSeparator}update-3-$apkSha.apk.part',
    );
    await partFile.writeAsBytes(apkBytes.sublist(0, 20));

    var requests = 0;
    final client = MockClient.streaming((request, bodyStream) async {
      requests++;
      if (requests == 1) {
        expect(request.headers['Range'], 'bytes=20-');
        return http.StreamedResponse(Stream<List<int>>.empty(), 416);
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
      '${appUpdatesDir.path}${Platform.pathSeparator}update-3-$apkSha.apk.part',
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
