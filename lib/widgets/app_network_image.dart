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

bool _isAppMediaPath(Uri uri) {
  return uri.path.startsWith('/imported-media/') ||
      uri.path.startsWith('/api/v1/media-file/');
}

/// 把服务端返回的媒体地址归一化为可请求的绝对 URL。
///
/// 返回 null 表示无法构造可请求地址，调用方应展示占位图而不是抛错。
String? resolveMediaUrl(String? raw) {
  final trimmed = raw?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  final parsed = Uri.tryParse(trimmed);
  final scheme = parsed?.scheme.toLowerCase();
  if (scheme == 'http') {
    final base = _mediaBaseUri;
    if (parsed != null &&
        base != null &&
        base.scheme.toLowerCase() == 'https' &&
        _isAppMediaPath(parsed)) {
      // 兼容历史接口写入的源站 HTTP/IP 地址，避免 Android 明文策略和
      // Web 混合内容策略拦截自有媒体；外部 HTTP 图片保持原地址不变。
      return base
          .replace(
            path: parsed.path,
            query: parsed.hasQuery ? parsed.query : null,
            fragment: parsed.hasFragment ? parsed.fragment : null,
          )
          .toString();
    }
    return trimmed;
  }
  if (scheme == 'https' || scheme == 'blob' || scheme == 'data') {
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

/// 用户头像全局运行时缓存，避免旧版接口未联表返回头像时出现空白。
class UserAvatarCache {
  static final Map<String, String> _cache = <String, String>{};

  static String? get(String? userId) {
    if (userId == null || userId.isEmpty) return null;
    return _cache[userId];
  }

  static void set(String? userId, String? avatarUrl) {
    if (userId == null || userId.isEmpty) return;
    final trimmed = avatarUrl?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      _cache[userId] = trimmed;
    }
  }
}

/// 网络图片的统一封装。
///
/// - 基于 [CachedNetworkImage] 提供跨重启缓存（Android/iOS 有磁盘缓存；
///   Web 平台依赖 Flutter ImageCache + 浏览器 HTTP 缓存）；
/// - 自动按布局约束 × DPR 计算解码宽度（`memCacheWidth`），列表滚动时
///   不再把原图解码成整幅位图；
/// - 统一占位与错误回退，URL 为空或非法时直接展示回退而不是抛异常。
///
/// **Web 平台注意事项**：
/// - `cached_network_image` 在 Web 上没有自己的持久化缓存层；
/// - 图片缓存完全依赖：Flutter 内存 ImageCache + 浏览器 HTTP 缓存；
/// - 页面路由切换可能导致 Widget 树重建，如果图片从 ImageCache 被淘汰
///   且浏览器缓存策略不理想，会重新请求图片；
/// - 服务端应该为媒体响应设置合理的 Cache-Control/ETag 头。
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
          const ColoredBox(color: Color(0xFFF4F6F9), child: SizedBox.expand());
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
        if (ratio != null && ratio > 0) {
          if (autoWidth != null) {
            // 解码目标按原图比例展开、长边封顶；比例正确的位图交给
            // cover/contain 去裁切或留白，而不是在解码阶段被压扁。
            final rawHeight = (autoWidth / ratio).round();
            if (rawHeight > 4096) {
              autoHeight = 4096;
              autoWidth = (4096 * ratio).round().clamp(1, 4096);
            } else {
              autoHeight = rawHeight.clamp(1, 4096);
            }
          } else if (autoHeight != null) {
            autoWidth = (autoHeight * ratio).round().clamp(1, 4096);
          }
        } else {
          // 不知道原图比例时绝对不要同时指定解码宽高。
          //
          // 只限制一个方向，让 Flutter 根据原始图片比例
          // 自动计算另一方向，否则非方图/长图会在解码阶段被拉伸。
          if (autoWidth != null && autoHeight != null) {
            autoHeight = null;
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
  return CachedNetworkImageProvider(resolved, maxWidth: maxWidth);
}
