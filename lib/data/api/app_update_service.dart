import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart' as path_provider;

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

/// 应用更新服务：检查 `/api/v1/app/update` 并流式下载 APK。
///
/// 下载复用服务端 ETag/Range 能力：`.part` 文件按已收字节续传，服务端忽略
/// Range 返回 200 时截断重写；SHA-256 校验通过后原子改名成 `.apk`。
class AppUpdateService {
  AppUpdateService({
    required Uri baseUri,
    http.Client? client,
    Future<Directory> Function()? downloadDirResolver,
  }) : _baseUri = baseUri,
       _client = client ?? http.Client(),
       _downloadDirResolver = downloadDirResolver;

  final Uri _baseUri;
  final http.Client _client;

  /// 下载目录解析器。默认走 path_provider 的临时目录；测试注入临时目录。
  final Future<Directory> Function()? _downloadDirResolver;

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
    } on http.ClientException {
      throw const AppUpdateException(AppUpdateErrorKind.network, '网络连接失败');
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
      return AppUpdateInfo.fromJson(payload);
    } on FormatException {
      throw const AppUpdateException(
        AppUpdateErrorKind.protocol,
        '版本检查响应字段不完整',
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

    final downloadDir = await _resolveDownloadDir();
    final partFile = File(
      p.join(downloadDir.path, 'update-$expectedSha.apk.part'),
    );
    final finalFile = File(p.join(downloadDir.path, 'update-$expectedSha.apk'));

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
      final uri = _baseUri.resolve(info.downloadUrl);
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
        final response = await _client
            .send(request)
            .timeout(const Duration(seconds: 30));
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
    } on AppUpdateException {
      rethrow;
    } on TimeoutException {
      throw const AppUpdateException(
        AppUpdateErrorKind.network,
        '下载超时，请检查网络后重试',
      );
    } on http.ClientException {
      throw const AppUpdateException(
        AppUpdateErrorKind.network,
        '网络连接中断，可重试续传',
      );
    } on FileSystemException {
      throw const AppUpdateException(AppUpdateErrorKind.protocol, '存储读写失败');
    } finally {
      try {
        await sink?.close();
      } catch (_) {
        // 忽略 sink 关闭错误，保留原始异常。
      }
    }
  }

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

  Future<String> _sha256Of(File file) async {
    final digest = await crypto.sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  bool _validContentRange(String? value, int startByte, int totalBytes) {
    if (value == null || value.isEmpty) return true;
    final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(value.trim());
    if (match == null) return false;
    final start = int.tryParse(match.group(1)!);
    final end = int.tryParse(match.group(2)!);
    final total = int.tryParse(match.group(3)!);
    return start == startByte &&
        end != null &&
        end >= startByte &&
        total == totalBytes;
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
