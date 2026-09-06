import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../data/api/publish_repository.dart';

/// 原生端所有业务图片上传共用的预处理与上传入口。
/// 服务端只接受 jpeg/png/webp，因此 HEIC 会优先借助平台解码器转成 PNG。
class MediaUploadService {
  const MediaUploadService(this._repository);

  static const int defaultMaxBytes = 10 * 1024 * 1024;
  static const int maxPixels = 40 * 1000 * 1000;
  static const int maxLongEdge = 4096;

  final PublishRepository _repository;

  static Future<PreparedUploadImage> prepareImage(
    XFile file, {
    int maxBytes = defaultMaxBytes,
  }) async {
    final sourceBytes = Uint8List.fromList(await file.readAsBytes());
    if (sourceBytes.isEmpty) {
      throw const PublishException('图片内容为空，请重新选择图片');
    }
    if (sourceBytes.length > maxBytes && !_isHeic(sourceBytes, file.name)) {
      throw const PublishException('单张图片不能超过 10 MB');
    }

    var bytes = sourceBytes;
    var mimeType = _detectMime(bytes, file.name);
    if (mimeType == 'image/heic') {
      bytes = await _platformDecodeToPng(bytes);
      mimeType = 'image/png';
    }

    var decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const PublishException('无法读取图片，请选择 JPG、PNG 或 WebP 图片');
    }
    final hadOrientation = decoded.exif.imageIfd.orientation != null &&
        decoded.exif.imageIfd.orientation != 1;
    decoded = img.bakeOrientation(decoded);
    final width = decoded.width;
    final height = decoded.height;
    if (width <= 0 || height <= 0) {
      throw const PublishException('图片尺寸无效，请重新选择图片');
    }
    if (width * height > maxPixels) {
      throw const PublishException('图片像素过大，请选择较小的图片');
    }

    final needsResize = _max(width, height) > maxLongEdge;
    if (!hadOrientation && !needsResize && bytes.length <= maxBytes) {
      return _prepared(
        file: file,
        bytes: bytes,
        mimeType: mimeType,
        width: width,
        height: height,
      );
    }

    var target = decoded;
    if (needsResize) {
      final scale = maxLongEdge / _max(width, height);
      target = img.copyResize(
        decoded,
        width: (width * scale).round(),
        height: (height * scale).round(),
      );
    }

    final keepPng = mimeType == 'image/png' &&
        !needsResize &&
        !hadOrientation &&
        bytes.length <= maxBytes;
    final output = keepPng
        ? Uint8List.fromList(img.encodePng(target))
        : _encodeJpegWithinLimit(target, maxBytes);
    if (output.length > maxBytes) {
      throw const PublishException('图片压缩后仍超过 10 MB');
    }
    return _prepared(
      file: file,
      bytes: output,
      mimeType: keepPng ? 'image/png' : 'image/jpeg',
      width: target.width,
      height: target.height,
    );
  }

  Future<String> uploadImage(XFile file) async {
    final prepared = await prepareImage(file);
    return uploadPreparedImage(prepared);
  }

  Future<List<String>> uploadImages(List<XFile> files) async {
    if (files.isEmpty) return const [];
    final uploaded = <String>[];
    try {
      for (final file in files) {
        uploaded.add(await uploadImage(file));
      }
      return uploaded;
    } catch (_) {
      for (final mediaId in uploaded) {
        try {
          await _repository.deleteMedia(mediaId);
        } catch (_) {
          // 回滚失败由服务端未引用媒体回收任务兜底。
        }
      }
      rethrow;
    }
  }

  Future<String> uploadPreparedImage(PreparedUploadImage image) async {
    final ticket = await _repository.requestMediaUpload(
      fileName: image.fileName,
      mimeType: image.mimeType,
      size: image.bytes.length,
      sha256: image.sha256,
      width: image.width,
      height: image.height,
    );
    await _repository.uploadMedia(
      ticket: ticket,
      bytes: image.bytes,
      size: image.bytes.length,
      sha256: image.sha256,
    );
    return ticket.mediaId;
  }

  static PreparedUploadImage _prepared({
    required XFile file,
    required Uint8List bytes,
    required String mimeType,
    required int width,
    required int height,
  }) {
    final extension = mimeType == 'image/png'
        ? '.png'
        : mimeType == 'image/webp'
        ? '.webp'
        : '.jpg';
    final originalName = file.name.replaceAll('\\', '/').split('/').last;
    final stem = originalName.replaceFirst(RegExp(r'\.[^.]*$'), '').trim();
    final fileName = '${stem.isEmpty ? 'image' : stem}$extension';
    return PreparedUploadImage(
      fileName: fileName,
      mimeType: mimeType,
      bytes: bytes,
      sha256: sha256.convert(bytes).toString(),
      width: width,
      height: height,
    );
  }

  static Uint8List _encodeJpegWithinLimit(img.Image image, int maxBytes) {
    for (final quality in [88, 82, 76, 70, 64]) {
      final output = img.encodeJpg(image, quality: quality);
      if (output.length <= maxBytes) return Uint8List.fromList(output);
    }
    return Uint8List.fromList(img.encodeJpg(image, quality: 58));
  }

  static String _detectMime(Uint8List bytes, String fileName) {
    if (_startsWith(bytes, const [0xff, 0xd8, 0xff])) return 'image/jpeg';
    if (_startsWith(bytes, const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        _ascii(bytes, 0, 4) == 'RIFF' &&
        _ascii(bytes, 8, 12) == 'WEBP') {
      return 'image/webp';
    }
    if (_isHeic(bytes, fileName)) return 'image/heic';
    throw const PublishException('仅支持 JPG、PNG、WEBP 图片');
  }

  static bool _isHeic(Uint8List bytes, String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) return true;
    if (bytes.length < 12 || _ascii(bytes, 4, 8) != 'ftyp') return false;
    final brand = _ascii(bytes, 8, 12);
    return brand == 'heic' ||
        brand == 'heix' ||
        brand == 'hevc' ||
        brand == 'hevx' ||
        brand == 'mif1' ||
        brand == 'msf1';
  }

  static bool _startsWith(Uint8List bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }

  static String _ascii(Uint8List bytes, int start, int end) =>
      String.fromCharCodes(bytes.sublist(start, end));

  static Future<Uint8List> _platformDecodeToPng(Uint8List bytes) async {
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('platform image conversion returned no data');
      }
      return Uint8List.view(
        data.buffer,
        data.offsetInBytes,
        data.lengthInBytes,
      );
    } catch (_) {
      throw const PublishException('HEIC 图片暂不支持，请先转换为 JPG、PNG 或 WebP');
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }
}

class PreparedUploadImage {
  const PreparedUploadImage({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
    required this.sha256,
    required this.width,
    required this.height,
  });

  final String fileName;
  final String mimeType;
  final Uint8List bytes;
  final String sha256;
  final int width;
  final int height;
}

int _max(int first, int second) => first > second ? first : second;
