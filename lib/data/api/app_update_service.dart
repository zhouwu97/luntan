import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart' as path_provider;

import 'update_config.dart';

/// 应用更新检查结果。字段与服务端 `/api/v1/app/update` 响应对齐。
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.updateAvailable,
    required this.updateType,
    required this.latestVersionName,
    required this.latestVersionCode,
    required this.minimumSupportedVersionCode,
    required this.title,
    required this.changelog,
    required this.fileSize,
    required this.sha256,
    required this.downloadUrl,
  });

  final bool updateAvailable;

  /// `none` / `optional` / `required`。
  final String updateType;
  final String latestVersionName;
  final int latestVersionCode;
  final int minimumSupportedVersionCode;
  final String title;
  final String changelog;
  final int fileSize;
  final String sha256;
  final String downloadUrl;

  bool get isRequired => updateType == 'required';

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'platform': 'android',
      'channel': 'stable',
      'latest_version_name': latestVersionName,
      'latest_version_code': latestVersionCode,
      'minimum_supported_version_code': minimumSupportedVersionCode,
      'title': title,
      'changelog': changelog,
      'file_size': fileSize,
      'sha256': sha256,
      'download_url': downloadUrl,
      'update_available': updateAvailable,
      'update_type': updateType,
    };
  }

  static AppUpdateInfo fromJson(Map<String, dynamic> json) {
    final updateAvailable = json['update_available'];
    if (updateAvailable is! bool) {
      throw const FormatException('update_available 必须是布尔值');
    }
    final updateType = switch (json['update_type']) {
      'required' => 'required',
      'optional' => 'optional',
      'none' => 'none',
      _ => throw const FormatException(
        'update_type 必须是 none/optional/required',
      ),
    };
    if (updateAvailable != (updateType != 'none')) {
      throw const FormatException('update_available 与 update_type 不一致');
    }
    final latestVersionName = _requiredString(json, 'latest_version_name');
    final latestVersionCode = _positiveInt(json, 'latest_version_code');
    final minimumSupportedVersionCode = _nonNegativeInt(
      json,
      'minimum_supported_version_code',
    );
    final title = _string(json, 'title');
    final changelog = _string(json, 'changelog');
    final fileSize = _nonNegativeInt(json, 'file_size');
    final sha256 = _string(json, 'sha256').toLowerCase();
    final downloadUrl = _string(json, 'download_url');
    if (updateAvailable) {
      if (title.isEmpty || changelog.isEmpty) {
        throw const FormatException('新版本标题和更新内容不能为空');
      }
      if (fileSize <= 0 || !_isSha256(sha256) || downloadUrl.isEmpty) {
        throw const FormatException('新版本安装包信息不完整');
      }
    }
    return AppUpdateInfo(
      updateAvailable: updateAvailable,
      updateType: updateType,
      latestVersionName: latestVersionName,
      latestVersionCode: latestVersionCode,
      minimumSupportedVersionCode: minimumSupportedVersionCode,
      title: title,
      changelog: changelog,
      // 无更新时服务端允许这些字段缺省。
      fileSize: fileSize,
      sha256: sha256,
      downloadUrl: downloadUrl,
    );
  }

  static String _string(Map<String, dynamic> json, String key) {
    final value = json[key];
    return value is String ? value.trim() : '';
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = _string(json, key);
    if (value.isEmpty) throw FormatException('$key 不能为空');
    return value;
  }

  static int _positiveInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is num && value > 0 && value == value.toInt()) {
      return value.toInt();
    }
    throw FormatException('$key 必须为正整数');
  }

  static int _nonNegativeInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is num && value >= 0 && value == value.toInt()) {
      return value.toInt();
    }
    throw FormatException('$key 必须为非负整数');
  }

  static bool _isSha256(String value) =>
      value.length == 64 && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
}

/// 更新检查失败。调用方按 [kind] 决定提示文案。
class AppUpdateException implements Exception {
  const AppUpdateException(this.kind, this.message);

  final AppUpdateErrorKind kind;
  final String message;

  @override
  String toString() => 'AppUpdateException($kind): $message';
}

enum AppUpdateErrorKind { network, server, protocol }

// 跨境网络上单条 TCP 连接容易出现带宽跑不满的情况；大包使用少量并发
// Range 请求，既提高吞吐，也保留每个分片的断点续传能力。
const _multiPartDownloadThresholdBytes = 16 * 1024 * 1024;
const _multiPartDownloadPartCount = 4;

class _DownloadPart {
  const _DownloadPart({
    required this.index,
    required this.start,
    required this.end,
  });

  final int index;
  final int start;
  final int end;

  int get length => end - start + 1;

  File fileIn(Directory directory) =>
      File(p.join(directory.path, 'part-$index.part'));
}

class _ContentRange {
  const _ContentRange({
    required this.start,
    required this.end,
    required this.total,
  });

  final int start;
  final int end;
  final int total;
}

class _RangeUnsupported implements Exception {
  const _RangeUnsupported();
}

/// 应用更新服务：检查 `/api/v1/app/update` 并流式下载 APK。
///
/// 下载复用服务端 ETag/Range 能力：`.part` 文件按已收字节续传，服务端忽略
/// Range 返回 200 时截断重写；SHA-256 校验通过后原子改名成 `.apk`。
class AppUpdateService {
  AppUpdateService({
    Uri? baseUri,
    http.Client? client,
    Future<Directory> Function()? downloadDirResolver,
    bool? productionBuild,
  }) : _productionBuild = productionBuild ?? isProductionUpdateBuild(),
       _baseUri = _validateBaseUri(
         baseUri ??
             Uri.parse(resolveUpdateBaseUrl(releaseBuild: productionBuild)),
         production: productionBuild ?? isProductionUpdateBuild(),
       ),
       _client = client ?? http.Client(),
       _downloadDirResolver = downloadDirResolver {
    _allowedDownloadHosts = _buildAllowedHosts(_baseUri);
  }

  final Uri _baseUri;
  final bool _productionBuild;
  final http.Client _client;

  /// 下载目录解析器。默认走 path_provider 的临时目录；测试注入临时目录。
  final Future<Directory> Function()? _downloadDirResolver;

  /// 下载 URL 允许的主机集合：官方更新域 + 编译期 `UPDATE_ALLOWED_HOSTS`。
  /// 更新元数据（hash、URL）与服务端同源时可能被一并篡改，独立 allowlist
  /// 是防止安装包被引导到任意主机的最后防线。
  late final Set<String> _allowedDownloadHosts;

  static const _maxDownloadRedirects = 5;

  static Set<String> _buildAllowedHosts(Uri baseUri) {
    final baseHost = baseUri.host.toLowerCase();
    final hosts = <String>{baseHost};
    // 官方 API 与静态下载 CDN 是两个域名，但共同属于官方发布链路。
    // 仅对官方 API 主机启用这个内置例外；自定义部署仍必须显式配置
    // UPDATE_ALLOWED_HOSTS，避免把任意更新源错误地放宽到官方 CDN。
    if (baseHost ==
        Uri.parse(defaultOfficialUpdateBaseUrl).host.toLowerCase()) {
      hosts.add(defaultOfficialUpdateDownloadHost);
    }
    const configuredHosts = String.fromEnvironment('UPDATE_ALLOWED_HOSTS');
    for (final entry in configuredHosts.split(',')) {
      final host = entry.trim().toLowerCase();
      if (host.isNotEmpty) {
        hosts.add(host);
      }
    }
    return hosts;
  }

  static Uri _validateBaseUri(
    Uri uri, {
    required bool production,
    bool allowQuery = false,
  }) {
    final scheme = uri.scheme.toLowerCase();
    if (!uri.hasScheme ||
        uri.host.isEmpty ||
        (scheme != 'http' && scheme != 'https') ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        (!allowQuery && uri.query.isNotEmpty)) {
      throw StateError('更新服务器必须是完整的 HTTP(S) URL');
    }
    if (production && scheme != 'https') {
      throw StateError('正式更新服务器必须使用 HTTPS');
    }
    return uri;
  }

  /// 查询当前客户端版本的更新策略。接口是公开的，不携带任何凭证。
  Future<AppUpdateInfo> checkUpdate({
    required String versionName,
    required int versionCode,
  }) async {
    if (versionName.isEmpty) {
      throw const AppUpdateException(
        AppUpdateErrorKind.protocol,
        'version_name 不能为空',
      );
    }
    if (versionCode <= 0) {
      throw const AppUpdateException(
        AppUpdateErrorKind.protocol,
        'version_code 必须为正',
      );
    }
    final uri = _baseUri
        .resolve('/api/v1/app/update')
        .replace(
          queryParameters: {
            'platform': 'android',
            'channel': 'stable',
            'version_name': versionName,
            'version_code': versionCode.toString(),
          },
        );
    final http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'X-App-Platform': 'android',
              'X-App-Channel': 'stable',
              'X-App-Version-Name': versionName,
              'X-App-Version-Code': versionCode.toString(),
            },
          )
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw const AppUpdateException(
        AppUpdateErrorKind.network,
        '连接超时，请检查网络后重试',
      );
    } on SocketException {
      throw const AppUpdateException(
        AppUpdateErrorKind.network,
        '无法连接更新服务器，请检查网络',
      );
    } on HttpException {
      throw const AppUpdateException(
        AppUpdateErrorKind.network,
        '无法连接更新服务器，请检查网络',
      );
    } on http.ClientException {
      throw const AppUpdateException(
        AppUpdateErrorKind.network,
        '无法连接更新服务器，请检查网络',
      );
    }
    if (response.statusCode >= 500) {
      throw AppUpdateException(
        AppUpdateErrorKind.server,
        '版本服务暂时不可用（HTTP ${response.statusCode}）',
      );
    }
    if (response.statusCode != 200) {
      throw AppUpdateException(
        AppUpdateErrorKind.protocol,
        '版本检查失败（HTTP ${response.statusCode}）',
      );
    }
    dynamic payload;
    try {
      payload = jsonDecode(response.body);
    } on FormatException {
      throw const AppUpdateException(AppUpdateErrorKind.protocol, '版本检查响应格式错误');
    }
    if (payload is! Map<String, dynamic>) {
      throw const AppUpdateException(AppUpdateErrorKind.protocol, '版本检查响应格式错误');
    }
    try {
      final info = AppUpdateInfo.fromJson(payload);
      if (info.updateAvailable) {
        // 检查阶段就拒绝不安全下载地址，避免 UI 显示一个之后必然失败的更新。
        _resolveDownloadUri(info.downloadUrl);
      }
      return info;
    } on FormatException {
      throw const AppUpdateException(
        AppUpdateErrorKind.protocol,
        '版本检查响应字段不完整',
      );
    } on AppUpdateException {
      rethrow;
    } on StateError catch (error) {
      throw AppUpdateException(
        AppUpdateErrorKind.protocol,
        error.message.toString(),
      );
    }
  }

  /// 下载 APK 并校验 SHA-256，成功返回最终文件。
  ///
  /// [onProgress] 收到 (已收字节, 总字节) 快照；[cancelToken] 置 true 即取消。
  Future<File> downloadApk({
    required AppUpdateInfo info,
    void Function(int receivedBytes, int totalBytes)? onProgress,
    ValueCancelToken? cancelToken,
  }) async {
    if (info.downloadUrl.isEmpty) {
      throw const AppUpdateException(AppUpdateErrorKind.protocol, '下载地址为空');
    }
    if (info.fileSize <= 0 || info.sha256.isEmpty) {
      throw const AppUpdateException(AppUpdateErrorKind.protocol, '安装包信息不完整');
    }
    final expectedSha = info.sha256.toLowerCase();
    if (expectedSha.length != 64 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedSha)) {
      throw const AppUpdateException(
        AppUpdateErrorKind.protocol,
        'SHA-256 格式非法',
      );
    }

    final Uri safeDownloadUri;
    try {
      safeDownloadUri = _resolveDownloadUri(info.downloadUrl);
    } on StateError catch (error) {
      throw AppUpdateException(
        AppUpdateErrorKind.protocol,
        error.message.toString(),
      );
    }
    final downloadDir = await _resolveDownloadDir();
    final partFile = File(
      p.join(
        downloadDir.path,
        'update-${info.latestVersionCode}-$expectedSha.apk.part',
      ),
    );
    final finalFile = File(
      p.join(
        downloadDir.path,
        'update-${info.latestVersionCode}-$expectedSha.apk',
      ),
    );

    // 上次下载完成且校验通过的同版本包直接复用。
    if (await finalFile.exists()) {
      final size = await finalFile.length();
      if (size == info.fileSize && await _sha256Of(finalFile) == expectedSha) {
        return finalFile;
      }
      try {
        await finalFile.delete();
      } on FileSystemException {
        // 删不掉就交给下面的完整下载流程覆盖。
      }
    }

    try {
      if (info.fileSize >= _multiPartDownloadThresholdBytes &&
          !await partFile.exists()) {
        return await _downloadMultiPart(
          info: info,
          uri: safeDownloadUri,
          legacyPartFile: partFile,
          finalFile: finalFile,
          partsDirectory: Directory(
            p.join(
              downloadDir.path,
              'update-${info.latestVersionCode}-$expectedSha.parts',
            ),
          ),
          expectedSha: expectedSha,
          onProgress: onProgress,
          cancelToken: cancelToken,
        );
      }
      return await _downloadSingle(
        info: info,
        uri: safeDownloadUri,
        partFile: partFile,
        finalFile: finalFile,
        expectedSha: expectedSha,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    } on AppUpdateException {
      rethrow;
    } on TimeoutException {
      throw const AppUpdateException(
        AppUpdateErrorKind.network,
        '下载超时，请检查网络后重试',
      );
    } on SocketException {
      throw const AppUpdateException(
        AppUpdateErrorKind.network,
        '网络连接中断，可重试续传',
      );
    } on HttpException {
      throw const AppUpdateException(
        AppUpdateErrorKind.network,
        '网络连接中断，可重试续传',
      );
    } on http.ClientException {
      throw const AppUpdateException(
        AppUpdateErrorKind.network,
        '网络连接中断，可重试续传',
      );
    } on FileSystemException {
      throw const AppUpdateException(AppUpdateErrorKind.protocol, '存储读写失败');
    }
  }

  Future<File> _downloadSingle({
    required AppUpdateInfo info,
    required Uri uri,
    required File partFile,
    required File finalFile,
    required String expectedSha,
    void Function(int receivedBytes, int totalBytes)? onProgress,
    ValueCancelToken? cancelToken,
  }) async {
    var startByte = 0;
    if (await partFile.exists()) {
      startByte = await partFile.length();
      if (startByte > info.fileSize) {
        try {
          await partFile.delete();
        } on FileSystemException {
          // ignore: 让下载阶段处理。
        }
        startByte = 0;
      }
    }

    IOSink? sink;
    try {
      var received = startByte;
      if (received == info.fileSize) {
        final actualSha = await _sha256Of(partFile);
        if (actualSha == expectedSha) {
          if (await finalFile.exists()) await finalFile.delete();
          await partFile.rename(finalFile.path);
          onProgress?.call(info.fileSize, info.fileSize);
          return finalFile;
        }
        await partFile.delete();
        received = 0;
      }
      var attempt = 0;
      while (true) {
        attempt += 1;
        if (attempt > 2) {
          throw const AppUpdateException(AppUpdateErrorKind.server, '下载重试次数耗尽');
        }
        final request = http.Request('GET', uri);
        if (received > 0) {
          request.headers['Range'] = 'bytes=$received-';
        }
        final response = await _sendDownloadRequest(request);
        if (response.statusCode == 416) {
          // Range 不合适：本地数据与服务器期望不一致，重头再来。
          received = 0;
          if (await partFile.exists()) await partFile.delete();
          continue;
        }
        if (response.statusCode >= 400) {
          throw AppUpdateException(
            AppUpdateErrorKind.server,
            '下载失败（HTTP ${response.statusCode}）',
          );
        }
        final serverHonoredRange = received > 0 && response.statusCode == 206;
        if (response.statusCode != 200 && !serverHonoredRange) {
          throw AppUpdateException(
            AppUpdateErrorKind.server,
            '下载响应异常（HTTP ${response.statusCode}）',
          );
        }
        if (serverHonoredRange &&
            !_validContentRange(
              response.headers['content-range'],
              received,
              info.fileSize,
            )) {
          // 续传偏移不一致时不能直接拼接，清理后重新请求完整文件。
          received = 0;
          if (await partFile.exists()) await partFile.delete();
          continue;
        }
        if (!serverHonoredRange) {
          // 服务端忽略 Range 返回完整文件：截断重写。
          received = 0;
        }
        final total = serverHonoredRange
            ? info.fileSize
            : (response.contentLength ?? info.fileSize);
        sink = partFile.openWrite(
          mode: serverHonoredRange ? FileMode.writeOnlyAppend : FileMode.write,
        );
        final completer = StreamIterator<List<int>>(response.stream);
        var cancelled = false;
        while (await completer.moveNext().timeout(
          const Duration(seconds: 30),
        )) {
          if (cancelToken?.isCancelled ?? false) {
            cancelled = true;
            break;
          }
          final chunk = completer.current;
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
        await sink.flush();
        await sink.close();
        sink = null;
        if (cancelled) {
          throw const AppUpdateCancelled();
        }
        break;
      }

      if (received != info.fileSize) {
        // 保留 .part 以便断点续传。
        throw AppUpdateException(
          AppUpdateErrorKind.server,
          '下载数据长度不符，预期 ${info.fileSize} 实收 $received',
        );
      }
      final actualSha = await _sha256Of(partFile);
      if (actualSha != expectedSha) {
        // 校验失败必须删 .part，避免下次续传继续追加坏数据。
        try {
          await partFile.delete();
        } on FileSystemException {
          // ignore
        }
        throw const AppUpdateException(
          AppUpdateErrorKind.protocol,
          '安装包校验失败，请重试下载',
        );
      }
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await partFile.rename(finalFile.path);
      onProgress?.call(info.fileSize, info.fileSize);
      return finalFile;
    } finally {
      try {
        await sink?.close();
      } catch (_) {
        // 忽略 sink 关闭错误，保留原始异常。
      }
    }
  }

  Future<File> _downloadMultiPart({
    required AppUpdateInfo info,
    required Uri uri,
    required File legacyPartFile,
    required File finalFile,
    required Directory partsDirectory,
    required String expectedSha,
    void Function(int receivedBytes, int totalBytes)? onProgress,
    ValueCancelToken? cancelToken,
  }) async {
    final parts = _buildDownloadParts(info.fileSize);
    final metadataFile = File(p.join(partsDirectory.path, 'metadata.json'));
    Map<String, dynamic>? metadata;

    if (await partsDirectory.exists()) {
      metadata = await _readPartsMetadata(metadataFile);
      if (!_validPartsMetadata(metadata, info.fileSize, parts.length)) {
        await _deletePartsDirectory(partsDirectory);
        metadata = null;
      }
    }
    if (!await partsDirectory.exists()) {
      await partsDirectory.create(recursive: true);
    }

    // 先用一个字节探测 Range 能力。某些代理会吞掉 Range 并返回 200，
    // 这时回退到原来的单连接下载，保证更新链路仍然兼容。
    final probeRequest = http.Request('GET', uri)
      ..headers['Range'] = 'bytes=0-0';
    final probeResponse = await _sendDownloadRequest(probeRequest);
    if (probeResponse.statusCode == 200) {
      await _discardResponse(probeResponse);
      await _deletePartsDirectory(partsDirectory);
      return _downloadSingle(
        info: info,
        uri: uri,
        partFile: legacyPartFile,
        finalFile: finalFile,
        expectedSha: expectedSha,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    }
    if (probeResponse.statusCode >= 400) {
      await _discardResponse(probeResponse);
      throw AppUpdateException(
        AppUpdateErrorKind.server,
        '下载探测失败（HTTP ${probeResponse.statusCode}）',
      );
    }
    if (probeResponse.statusCode != 206) {
      await _discardResponse(probeResponse);
      throw AppUpdateException(
        AppUpdateErrorKind.server,
        '服务器不支持分片下载（HTTP ${probeResponse.statusCode}）',
      );
    }
    final probeRange = _parseContentRange(
      probeResponse.headers['content-range'],
    );
    final currentEtag = _normalizeEtag(probeResponse.headers['etag']);
    await probeResponse.stream.drain<void>();
    if (probeRange == null ||
        probeRange.start != 0 ||
        probeRange.end != 0 ||
        probeRange.total != info.fileSize) {
      throw const AppUpdateException(
        AppUpdateErrorKind.protocol,
        '服务器分片范围响应无效',
      );
    }

    final storedEtag = _metadataEtag(metadata);
    if (storedEtag != currentEtag) {
      // 同一版本的文件内容发生变化时，旧分片不能继续拼接。
      await _deletePartsDirectory(partsDirectory);
      await partsDirectory.create(recursive: true);
      metadata = null;
    }
    await _writePartsMetadata(
      metadataFile,
      totalBytes: info.fileSize,
      partCount: parts.length,
      etag: currentEtag,
    );
    if (cancelToken?.isCancelled ?? false) {
      throw const AppUpdateCancelled();
    }

    var receivedBytes = 0;
    for (final part in parts) {
      final file = part.fileIn(partsDirectory);
      if (await file.exists()) {
        final length = await file.length();
        if (length > part.length) {
          await file.delete();
        } else {
          receivedBytes += length;
        }
      }
    }
    onProgress?.call(receivedBytes, info.fileSize);

    final internalCancelToken = ValueCancelToken();
    final partDownloads = parts
        .map(
          (part) => _downloadPart(
            part: part,
            partsDirectory: partsDirectory,
            uri: uri,
            totalBytes: info.fileSize,
            etag: currentEtag,
            externalCancelToken: cancelToken,
            internalCancelToken: internalCancelToken,
            onBytes: (delta) {
              receivedBytes += delta;
              onProgress?.call(receivedBytes, info.fileSize);
            },
          ),
        )
        .toList();
    try {
      await Future.wait<void>(partDownloads);
    } catch (error) {
      internalCancelToken.cancel();
      // Future.wait 在第一个任务失败时会立即返回；等待其它分片收尾，
      // 避免回退或重试时仍有旧请求写入分片目录。
      await Future.wait<void>(
        partDownloads.map((future) async {
          try {
            await future;
          } catch (_) {
            // 保留第一个错误作为本次下载结果。
          }
        }),
      );
      if (error is _RangeUnsupported) {
        await _deletePartsDirectory(partsDirectory);
        return _downloadSingle(
          info: info,
          uri: uri,
          partFile: legacyPartFile,
          finalFile: finalFile,
          expectedSha: expectedSha,
          onProgress: onProgress,
          cancelToken: cancelToken,
        );
      }
      rethrow;
    }

    if (cancelToken?.isCancelled ?? false) {
      throw const AppUpdateCancelled();
    }

    final assembledFile = File(
      p.join(partsDirectory.path, 'assembled.apk.part'),
    );
    if (await assembledFile.exists()) {
      await assembledFile.delete();
    }
    IOSink? sink;
    try {
      sink = assembledFile.openWrite();
      for (final part in parts) {
        if (cancelToken?.isCancelled ?? false) {
          throw const AppUpdateCancelled();
        }
        await sink.addStream(part.fileIn(partsDirectory).openRead());
      }
      await sink.flush();
      await sink.close();
      sink = null;
    } finally {
      try {
        await sink?.close();
      } catch (_) {
        // 忽略 sink 关闭错误，保留原始异常。
      }
    }

    if (await assembledFile.length() != info.fileSize) {
      throw AppUpdateException(
        AppUpdateErrorKind.server,
        '分片合并长度不符，预期 ${info.fileSize}',
      );
    }
    final actualSha = await _sha256Of(assembledFile);
    if (actualSha != expectedSha) {
      await _deletePartsDirectory(partsDirectory);
      throw const AppUpdateException(
        AppUpdateErrorKind.protocol,
        '安装包校验失败，请重试下载',
      );
    }
    if (await finalFile.exists()) {
      await finalFile.delete();
    }
    await assembledFile.rename(finalFile.path);
    await _deletePartsDirectory(partsDirectory);
    onProgress?.call(info.fileSize, info.fileSize);
    return finalFile;
  }

  Future<void> _downloadPart({
    required _DownloadPart part,
    required Directory partsDirectory,
    required Uri uri,
    required int totalBytes,
    required String? etag,
    required ValueCancelToken? externalCancelToken,
    required ValueCancelToken internalCancelToken,
    required void Function(int delta) onBytes,
  }) async {
    final partFile = part.fileIn(partsDirectory);
    var received = 0;
    if (await partFile.exists()) {
      received = await partFile.length();
      if (received > part.length) {
        await partFile.delete();
        received = 0;
      }
    }

    while (received < part.length) {
      if (_isDownloadCancelled(externalCancelToken, internalCancelToken)) {
        throw const AppUpdateCancelled();
      }
      final start = part.start + received;
      final request = http.Request('GET', uri)
        ..headers['Range'] = 'bytes=$start-${part.end}';
      if (etag != null) {
        request.headers['If-Range'] = etag;
      }
      final response = await _sendDownloadRequest(request);
      if (response.statusCode == 200) {
        await _discardResponse(response);
        throw const _RangeUnsupported();
      }
      if (response.statusCode >= 400) {
        await _discardResponse(response);
        throw AppUpdateException(
          AppUpdateErrorKind.server,
          '分片下载失败（HTTP ${response.statusCode}）',
        );
      }
      if (response.statusCode != 206) {
        await _discardResponse(response);
        throw AppUpdateException(
          AppUpdateErrorKind.server,
          '分片下载响应异常（HTTP ${response.statusCode}）',
        );
      }
      final contentRange = _parseContentRange(
        response.headers['content-range'],
      );
      final responseEtag = _normalizeEtag(response.headers['etag']);
      if (contentRange == null ||
          contentRange.start != start ||
          contentRange.end < start ||
          contentRange.end > part.end ||
          contentRange.total != totalBytes) {
        await _discardResponse(response);
        throw const AppUpdateException(
          AppUpdateErrorKind.protocol,
          '服务器分片范围响应无效',
        );
      }
      if (etag != null && responseEtag != etag) {
        await _discardResponse(response);
        throw const AppUpdateException(
          AppUpdateErrorKind.protocol,
          '安装包内容已变化，请重试下载',
        );
      }

      IOSink? sink;
      var receivedFromResponse = 0;
      var cancelled = false;
      try {
        sink = partFile.openWrite(mode: FileMode.writeOnlyAppend);
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 30),
        )) {
          if (_isDownloadCancelled(externalCancelToken, internalCancelToken)) {
            cancelled = true;
            break;
          }
          final remaining = part.length - received;
          if (chunk.length > remaining) {
            throw const AppUpdateException(
              AppUpdateErrorKind.protocol,
              '分片返回数据超出请求范围',
            );
          }
          sink.add(chunk);
          received += chunk.length;
          receivedFromResponse += chunk.length;
          onBytes(chunk.length);
        }
        await sink.flush();
        await sink.close();
        sink = null;
      } finally {
        try {
          await sink?.close();
        } catch (_) {
          // 忽略 sink 关闭错误，保留原始异常。
        }
      }
      if (cancelled) {
        throw const AppUpdateCancelled();
      }
      if (receivedFromResponse == 0) {
        throw const AppUpdateException(
          AppUpdateErrorKind.network,
          '服务器返回空分片，请重试下载',
        );
      }
    }
  }

  List<_DownloadPart> _buildDownloadParts(int totalBytes) {
    final baseLength = totalBytes ~/ _multiPartDownloadPartCount;
    final remainder = totalBytes % _multiPartDownloadPartCount;
    var start = 0;
    return List<_DownloadPart>.generate(_multiPartDownloadPartCount, (index) {
      final length = baseLength + (index < remainder ? 1 : 0);
      final part = _DownloadPart(
        index: index,
        start: start,
        end: start + length - 1,
      );
      start += length;
      return part;
    });
  }

  Future<Map<String, dynamic>?> _readPartsMetadata(File metadataFile) async {
    if (!await metadataFile.exists()) return null;
    try {
      final value = jsonDecode(await metadataFile.readAsString());
      return value is Map<String, dynamic> ? value : null;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  bool _validPartsMetadata(
    Map<String, dynamic>? metadata,
    int totalBytes,
    int partCount,
  ) {
    if (metadata == null ||
        metadata['total_bytes'] != totalBytes ||
        metadata['part_count'] != partCount) {
      return false;
    }
    final etag = metadata['etag'];
    return etag == null || etag is String;
  }

  String? _metadataEtag(Map<String, dynamic>? metadata) {
    if (metadata == null) return null;
    return _normalizeEtag(metadata['etag'] as String?);
  }

  Future<void> _writePartsMetadata(
    File metadataFile, {
    required int totalBytes,
    required int partCount,
    required String? etag,
  }) async {
    final temporaryFile = File('${metadataFile.path}.tmp');
    if (await temporaryFile.exists()) {
      await temporaryFile.delete();
    }
    await temporaryFile.writeAsString(
      jsonEncode({
        'total_bytes': totalBytes,
        'part_count': partCount,
        'etag': etag,
      }),
      flush: true,
    );
    if (await metadataFile.exists()) {
      await metadataFile.delete();
    }
    await temporaryFile.rename(metadataFile.path);
  }

  Future<void> _deletePartsDirectory(Directory directory) async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<void> _discardResponse(http.StreamedResponse response) async {
    try {
      await response.stream.listen((_) {}).cancel();
    } catch (_) {
      // 忽略响应清理错误，保留原始下载结果。
    }
  }

  bool _isDownloadCancelled(
    ValueCancelToken? external,
    ValueCancelToken internal,
  ) => (external?.isCancelled ?? false) || internal.isCancelled;

  Future<Directory> _resolveDownloadDir() async {
    try {
      final temp =
          await (_downloadDirResolver?.call() ??
              path_provider.getTemporaryDirectory());
      final dir = Directory(p.join(temp.path, 'app_updates'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    } on FileSystemException {
      throw const AppUpdateException(AppUpdateErrorKind.protocol, '无法创建下载目录');
    }
  }

  Uri _resolveDownloadUri(String rawUrl) {
    final trimmedUrl = rawUrl.trim();
    final rawPath = trimmedUrl.split(RegExp(r'[?#]')).first;
    final String decodedPath;
    try {
      decodedPath = Uri.decodeComponent(rawPath);
    } on FormatException {
      throw StateError('下载地址编码非法');
    }
    if (decodedPath.split('/').contains('..')) {
      throw StateError('下载地址路径不能穿越');
    }
    final parsed = Uri.tryParse(trimmedUrl);
    if (parsed == null || (!parsed.hasScheme && parsed.path.isEmpty)) {
      throw StateError('下载地址必须是有效 URL');
    }
    if (parsed.userInfo.isNotEmpty || parsed.fragment.isNotEmpty) {
      throw StateError('下载地址不能包含凭证或片段');
    }

    final isAbsolute = parsed.hasScheme;
    if (!isAbsolute) {
      // 只允许以根路径开头的相对地址，拒绝 //host、../ 等转向其他资源的写法。
      if (parsed.host.isNotEmpty || !parsed.path.startsWith('/')) {
        throw StateError('相对下载地址非法');
      }
    }

    final resolved = isAbsolute ? parsed : _baseUri.resolveUri(parsed);
    final validated = _validateBaseUri(
      resolved,
      production: _productionBuild,
      allowQuery: true,
    );
    if (!_allowedDownloadHosts.contains(validated.host.toLowerCase())) {
      throw StateError('下载地址主机不在允许列表中');
    }
    return validated;
  }

  /// 发送下载请求并手动处理重定向。每一跳的 Location 都必须重新通过
  /// allowlist 校验，防止更新服务器被劫持后把安装包重定向到任意主机。
  Future<http.StreamedResponse> _sendDownloadRequest(
    http.Request request,
  ) async {
    var current = request;
    var hops = 0;
    while (true) {
      current.followRedirects = false;
      final response = await _client
          .send(current)
          .timeout(const Duration(seconds: 30));
      final status = response.statusCode;
      if (status < 300 || status >= 400 || status == 304) {
        return response;
      }
      final location = response.headers['location'];
      await _discardResponse(response);
      if (hops >= _maxDownloadRedirects) {
        throw const AppUpdateException(
          AppUpdateErrorKind.protocol,
          '下载重定向次数超限',
        );
      }
      hops += 1;
      if (location == null || location.trim().isEmpty) {
        throw const AppUpdateException(
          AppUpdateErrorKind.protocol,
          '下载重定向缺少 Location',
        );
      }
      final trimmedLocation = location.trim();
      Uri nextUri;
      try {
        final parsedLocation = Uri.parse(trimmedLocation);
        // 相对 Location 按当前跳的 URL 解析，而不是 base URI。
        nextUri = parsedLocation.hasScheme
            ? parsedLocation
            : current.url.resolve(trimmedLocation);
      } on FormatException {
        throw const AppUpdateException(
          AppUpdateErrorKind.protocol,
          '下载重定向地址非法',
        );
      }
      Uri safeUri;
      try {
        safeUri = _resolveDownloadUri(nextUri.toString());
      } on StateError catch (error) {
        throw AppUpdateException(
          AppUpdateErrorKind.protocol,
          error.message.toString(),
        );
      }
      final redirected = http.Request(current.method, safeUri);
      redirected.headers.addAll(current.headers);
      current = redirected;
    }
  }

  Future<String> _sha256Of(File file) async {
    final digest = await crypto.sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  bool _validContentRange(String? value, int startByte, int totalBytes) {
    if (value == null || value.isEmpty) return true;
    final range = _parseContentRange(value);
    return range != null &&
        range.start == startByte &&
        range.end >= startByte &&
        range.total == totalBytes;
  }

  _ContentRange? _parseContentRange(String? value) {
    if (value == null || value.isEmpty) return null;
    final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(value.trim());
    if (match == null) return null;
    final start = int.tryParse(match.group(1)!);
    final end = int.tryParse(match.group(2)!);
    final total = int.tryParse(match.group(3)!);
    if (start == null || end == null || total == null) return null;
    return _ContentRange(start: start, end: end, total: total);
  }

  String? _normalizeEtag(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  void close() => _client.close();
}

class ValueCancelToken {
  bool isCancelled = false;

  void cancel() => isCancelled = true;
}

class AppUpdateCancelled implements Exception {
  const AppUpdateCancelled();
}
