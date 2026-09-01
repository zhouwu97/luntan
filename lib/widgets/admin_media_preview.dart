import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/api/platform_repository.dart';

/// 管理员审核证据的私有图片预览。
///
/// 不能使用 [AppNetworkImage]：审核案件可能对应 pending/hidden 内容，
/// 且管理员媒体接口要求 Authorization。这里通过仓储取二进制，使用
/// Image.memory 渲染，不写入公开 URL 缓存。
class AdminMediaPreview extends StatefulWidget {
  const AdminMediaPreview({
    super.key,
    required this.repository,
    required this.media,
    this.width = 120,
    this.height = 120,
  });

  final PlatformRepository repository;
  final ModerationMediaEvidence media;
  final double width;
  final double height;

  @override
  State<AdminMediaPreview> createState() => _AdminMediaPreviewState();
}

class _AdminMediaPreviewState extends State<AdminMediaPreview> {
  late Future<Uint8List> _bytesFuture;

  @override
  void initState() {
    super.initState();
    _bytesFuture = _loadBytes();
  }

  @override
  void didUpdateWidget(covariant AdminMediaPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.id != widget.media.id) {
      _bytesFuture = _loadBytes();
    }
  }

  Future<Uint8List> _loadBytes() async {
    final bytes = await widget.repository.getAdminMediaPreview(
      mediaId: widget.media.id,
    );
    return Uint8List.fromList(bytes);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: FutureBuilder<Uint8List>(
          future: _bytesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const ColoredBox(
                color: Color(0xFFEFF4F8),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            final bytes = snapshot.data;
            if (bytes == null || bytes.isEmpty) return _error();
            return Image.memory(
              bytes,
              fit: BoxFit.cover,
              cacheWidth: 768,
              errorBuilder: (_, _, _) => _error(),
            );
          },
        ),
      ),
    );
  }

  Widget _error() {
    return const ColoredBox(
      color: Color(0xFFF4F6F9),
      child: Center(
        child: Icon(Icons.broken_image_outlined, color: Color(0xFF9AAABD)),
      ),
    );
  }
}
