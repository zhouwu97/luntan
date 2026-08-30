import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../data/api/publish_repository.dart';
import '../theme/app_theme.dart';

enum ProfileImageKind { avatar, background }

/// 选图后进入系统裁剪页；用户取消选图或裁剪时返回 null。
/// 交互对齐 xynewui：头像锁 1:1，背景自由比例并限制 1920px / 质量 85。
/// web 上 image_cropper 强制要求 WebUiSettings，否则裁剪直接抛错。
Future<CroppedFile?> pickAndCropProfileImage({
  required BuildContext context,
  required ProfileImageKind kind,
  ImageSource source = ImageSource.gallery,
}) async {
  final picked = await ImagePicker().pickImage(
    source: source,
    imageQuality: kind == ProfileImageKind.avatar ? 90 : 88,
  );
  if (picked == null) return null;
  if (!context.mounted) return null;
  final isAvatar = kind == ProfileImageKind.avatar;
  final title = isAvatar ? '裁剪头像' : '调整背景图';
  return ImageCropper().cropImage(
    sourcePath: picked.path,
    maxWidth: isAvatar ? null : 1920,
    maxHeight: isAvatar ? null : 1920,
    compressQuality: isAvatar ? 90 : 85,
    aspectRatio: isAvatar ? const CropAspectRatio(ratioX: 1, ratioY: 1) : null,
    uiSettings: [
      if (kIsWeb)
        WebUiSettings(
          context: context,
          size: CropperSize(width: 480, height: isAvatar ? 480 : 320),
        )
      else ...[
        AndroidUiSettings(
          toolbarTitle: title,
          toolbarColor: Colors.black,
          toolbarWidgetColor: Colors.white,
          statusBarLight: false,
          backgroundColor: Colors.black,
          activeControlsWidgetColor: AppTheme.primary,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: isAvatar,
        ),
        IOSUiSettings(
          title: title,
          aspectRatioLockEnabled: isAvatar,
          resetButtonHidden: isAvatar,
          resetAspectRatioEnabled: !isAvatar,
        ),
      ],
    ],
  );
}

/// CroppedFile 没有 name 字段；web 上 path 是 blob 地址取不到扩展名，
/// 此时按 jpg 兜底命名（裁剪默认输出 jpeg），保证上传凭证拿到合法文件名。
String profileImageFileName(CroppedFile file, String prefix) {
  final name = file.path.replaceAll('\\', '/').split('/').last.toLowerCase();
  final hasImageExtension =
      name.endsWith('.png') ||
      name.endsWith('.jpg') ||
      name.endsWith('.jpeg');
  if (hasImageExtension) return name;
  return '$prefix${DateTime.now().millisecondsSinceEpoch}.jpg';
}

String profileImageMimeType(String fileName) =>
    fileName.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';

/// 走发布媒体上传通道（sha256 去重 + 预签名凭证），返回 mediaId。
Future<String> uploadProfileMedia(
  PublishRepository publisher, {
  required CroppedFile file,
  required Uint8List bytes,
  required String fileNamePrefix,
}) async {
  final fileName = profileImageFileName(file, fileNamePrefix);
  final mimeType = profileImageMimeType(fileName);
  final digest = sha256.convert(bytes).toString();
  final ticket = await publisher.requestMediaUpload(
    fileName: fileName,
    mimeType: mimeType,
    size: bytes.length,
    sha256: digest,
  );
  if (DateTime.now().isAfter(ticket.expiresAt)) {
    throw const PublishException('图片上传凭证已过期，请重新选择');
  }
  await publisher.uploadMedia(
    ticket: ticket,
    bytes: bytes,
    size: bytes.length,
    sha256: digest,
  );
  return ticket.mediaId;
}
