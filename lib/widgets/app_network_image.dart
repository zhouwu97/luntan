import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 媒体 URL 的基准地址，由启动流程注入 API base。
///
/// 服务端在未配置对象存储域名时可能返回相对媒体地址（如
/// `/api/v1/media-file/...` 或裸 objectKey），展示层统一在这里补全。
Uri? _mediaBaseUri;

void configureAppMediaBaseUrl(Uri? base) {
  _mediaBaseUri = base;
}

/// 把服务端返回的媒体地址归一化为可请求的绝对 URL。
///
/// 返回 null 表示无法构造可请求地址，调用方应展示占位图而不是抛错。
String? resolveMediaUrl(String? raw) {
  final trimmed = raw?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  final scheme = Uri.tryParse(trimmed)?.scheme.toLowerCase();
  if (scheme == 'http' || scheme == 'https' || scheme == 'blob' || scheme == 'data') {
    return trimmed;
  }
  final base = _mediaBaseUri;
  if (base == null) {
    return null;
  }
  final normalized = trimmed.startsWith('/') ? trimmed : '/$trimmed';
  final resolved = base.resolve(normalized);
  return resolved.toString();
}

/// 网络图片的统一封装。
///
/// - 基于 [CachedNetworkImage] 提供磁盘缓存：重启后无需重新下载；
/// - 自动按布局约束 × DPR 计算解码宽度（`memCacheWidth`），列表滚动时
///   不再把原图解码成整幅位图；
/// - 统一占位与错误回退，URL 为空或非法时直接展示回退而不是抛异常。
class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.placeholder,
    this.errorBuilder,
    this.memCacheWidth,
    this.memCacheHeight,
    this.aspectRatio,
    this.autoMemCacheSize = true,
    this.fadeInDuration = const Duration(milliseconds: 160),
  });

  final String? url;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Alignment alignment;
  final WidgetBuilder? placeholder;
  final WidgetBuilder? errorBuilder;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final Duration fadeInDuration;

  /// 原图宽高比（width / height）。
  ///
  /// 提供后自动解码高度按原图比例展开，而不是按布局框高度双轴
  /// 精确缩放——否则长图位图会先被压成预览框的形状再进入显示。
  final double? aspectRatio;

  /// 是否按布局约束自动推导解码尺寸。
  ///
  /// 设为 false 时只使用显式 [memCacheWidth]/[memCacheHeight]：
  /// 已知 [aspectRatio] 时高度按比例展开；比例未知时仅按宽度降采样，
  /// 由 ResizeImage 按原图比例推断高度，避免双轴精确缩放压扁位图。
  final bool autoMemCacheSize;

  @override
  Widget build(BuildContext context) {
    final resolved = resolveMediaUrl(url);
    if (resolved == null) {
      final builder = errorBuilder ?? placeholder;
      return builder?.call(context) ??
          const ColoredBox(
            color: Color(0xFFF4F6F9),
            child: SizedBox.expand(),
          );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
        var autoWidth = memCacheWidth;
        var autoHeight = memCacheHeight;
        if (autoMemCacheSize) {
          autoWidth ??= _autoCacheSide(constraints.maxWidth, dpr);
          autoHeight ??= _autoCacheSide(constraints.maxHeight, dpr);
        }
        final ratio = aspectRatio;
        if (ratio != null && ratio > 0 && autoWidth != null) {
          // 解码目标按原图比例展开、长边封顶；比例正确的位图交给
          // cover/contain 去裁切或留白，而不是在解码阶段被压扁。
          final rawHeight = (autoWidth / ratio).round();
          if (rawHeight > 4096) {
            autoHeight = 4096;
            autoWidth = (4096 * ratio).round().clamp(1, 4096);
          } else {
            autoHeight = rawHeight.clamp(1, 4096);
          }
        }

        return CachedNetworkImage(
          imageUrl: resolved,
          width: width,
          height: height,
          fit: fit,
          alignment: alignment,
          fadeInDuration: fadeInDuration,
          memCacheWidth: autoWidth,
          memCacheHeight: autoHeight,
          placeholder: placeholder != null
              ? (context, _) => placeholder!(context)
              : (context, _) => const ColoredBox(
                  color: Color(0xFFF4F6F9),
                  child: SizedBox.expand(),
                ),
          errorWidget: errorBuilder != null
              ? (context, _, _) => errorBuilder!(context)
              : (context, _, _) => const ColoredBox(
                  color: Color(0xFFF4F6F9),
                  child: SizedBox.expand(
                    child: FittedBox(
                      fit: BoxFit.none,
                      child: Icon(
                        Icons.broken_image_outlined,
                        size: 24,
                        color: Color(0xFFB9C0CC),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }

  /// 约束有限时按约束 × DPR 降采样；
  /// 传出值限制在合理像素范围内，避免极端布局产生超大位图。
  static int? _autoCacheSide(double constraint, double dpr) {
    if (!constraint.isFinite || constraint <= 0) {
      return null;
    }
    final pixels = (constraint * dpr).round();
    if (pixels <= 0) {
      return null;
    }
    return pixels.clamp(1, 4096);
  }
}

/// 供 [CircleAvatar.backgroundImage] 等需要 [ImageProvider] 的场景使用。
///
/// 解析失败时返回 null，调用方回退到默认头像/占位。
ImageProvider? appNetworkImageProvider(String? url, {int? maxWidth}) {
  final resolved = resolveMediaUrl(url);
  if (resolved == null) {
    return null;
  }
  return CachedNetworkImageProvider(
    resolved,
    maxWidth: maxWidth,
  );
}
