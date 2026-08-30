import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/mock_forum_data.dart';
import 'app_network_image.dart';

/// 帖子媒体预览的使用场景。
enum PostMediaPreviewMode { feed, detail }

/// Feed 单图预览宽度 = 可用宽度 × [kFeedSingleImageWidthFactor]。
const double kFeedSingleImageWidthFactor = 0.70;

/// Feed 单图预览最大宽度。
const double kFeedSingleImageMaxWidth = 250.0;

/// 宽高比低于该值视为长截图，改用 3:4 预览框顶部裁切。
const double kFeedLongImageRatio = 0.75;

/// Feed 单图缺少宽高元数据时的兜底比例。
const double kFeedSingleImageFallbackRatio = 4.0 / 3.0;

/// Feed 多图最多展示的张数，超出部分在最后一张叠加 +N。
const int kFeedMaxImages = 9;

/// Feed 多图瓦片间距。
const double kFeedGridSpacing = 6.0;

/// 计算 Feed 单图预览尺寸（宽度优先模型）。
///
/// 比例 >= [kFeedLongImageRatio] 时按原比例完整展示；
/// 比例 < [kFeedLongImageRatio] 视为长图，返回固定 3:4 预览框。
@visibleForTesting
Size calculateFeedSingleImageSize({
  required double availableWidth,
  double? aspectRatio,
}) {
  final width = math.min(
    availableWidth * kFeedSingleImageWidthFactor,
    kFeedSingleImageMaxWidth,
  );
  final ratio = aspectRatio ?? kFeedSingleImageFallbackRatio;
  final height = ratio < kFeedLongImageRatio
      ? width / kFeedLongImageRatio
      : width / ratio;
  return Size(width, height);
}

/// 媒体元数据里的宽高比（width / height），缺失或非法时返回 null。
double? mediaAssetRatio(PostMedia media) {
  final width = media.width?.toDouble();
  final height = media.height?.toDouble();
  if (width == null ||
      height == null ||
      !width.isFinite ||
      !height.isFinite) {
    return null;
  }
  if (width <= 0 || height <= 0) return null;
  return width / height;
}

/// 帖子媒体预览。
///
/// Feed 场景（贴吧式信息流）：
/// - 单图宽度优先：预览宽 = min(内容宽 × 0.70, 250dp)，左对齐；比例 ≥ 0.75 按原比例完整展示，< 0.75 视为长图，用 3:4 预览框顶部裁切并提示“长图”；
/// - 多图统一方形瓦片：2 图一行两列，3 图一行三列，4 图 2×2，5 张及以上三列九宫格；最多展示 9 张，超出部分在第 9 张叠加 +N，全部 cover + 顶部对齐。
///
/// Detail 场景：
/// - 纵向真实比例完整展示全部图片，撑满正文宽度，支持长截图自然向下滚动，无固定600px上限与浅蓝letterbox。
class PostMediaPreview extends StatelessWidget {
  const PostMediaPreview({
    super.key,
    required this.images,
    this.onTap,
    this.onImageTap,
    this.mode = PostMediaPreviewMode.feed,
  });

  final List<PostMedia> images;
  final VoidCallback? onTap;
  final ValueChanged<int>? onImageTap;
  final PostMediaPreviewMode mode;

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return const SizedBox.shrink();
    if (mode == PostMediaPreviewMode.detail) {
      return _buildDetailStream(context);
    }
    return _buildFeedStream(context);
  }

  // ---------------------------------------------------------------------------
  // Detail 场景：纵向真实比例流
  // ---------------------------------------------------------------------------
  Widget _buildDetailStream(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: List.generate(images.length, (index) {
          final image = images[index];
          final ratio = _naturalRatio(image, fallback: 4.0 / 3.0);
          return Padding(
            padding: EdgeInsets.only(
              bottom: index < images.length - 1 ? 10.0 : 0.0,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final height = width / ratio;
                return SizedBox(
                  width: width,
                  height: height,
                  child: _tile(
                    context,
                    image,
                    index: index,
                    mode: PostMediaPreviewMode.detail,
                  ),
                );
              },
            ),
          );
        }),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Feed 场景：单图宽度优先 + 多图方形瓦片网格
  // ---------------------------------------------------------------------------
  Widget _buildFeedStream(BuildContext context) {
    final count = images.length;
    Widget content;

    switch (count) {
      case 1:
        content = _buildFeedSingleImage(context, images.first);
      case 2:
        content = _buildFeedGrid(context, images, columns: 2);
      case 3:
        content = _buildFeedGrid(context, images, columns: 3);
      case 4:
        content = _buildFeedGrid(context, images, columns: 2);
      default:
        content = _buildFeedGrid(context, images, columns: 3);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: content,
    );
  }

  /// 单图：宽度优先 + 长图 3:4 顶部裁切。
  Widget _buildFeedSingleImage(BuildContext context, PostMedia media) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final rawRatio = mediaAssetRatio(media);
        final size = calculateFeedSingleImageSize(
          availableWidth: constraints.maxWidth,
          aspectRatio: rawRatio,
        );
        final isLongImage = rawRatio != null && rawRatio < kFeedLongImageRatio;

        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: _tile(
              context,
              media,
              index: 0,
              mode: PostMediaPreviewMode.feed,
              fit: isLongImage ? BoxFit.cover : BoxFit.contain,
              alignment: isLongImage ? Alignment.topCenter : Alignment.center,
              showLongImageBadge: isLongImage,
            ),
          ),
        );
      },
    );
  }

  /// 多图：columns 列方形瓦片网格，超出 9 张在最后一张叠加 +N。
  Widget _buildFeedGrid(
    BuildContext context,
    List<PostMedia> items, {
    required int columns,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final tileWidth = (width - kFeedGridSpacing * (columns - 1)) / columns;
        final visibleCount = math.min(items.length, kFeedMaxImages);
        final rowCount = (visibleCount + columns - 1) ~/ columns;
        final extraCount = items.length - visibleCount;

        return SizedBox(
          width: width,
          height: tileWidth * rowCount + kFeedGridSpacing * (rowCount - 1),
          child: Wrap(
            spacing: kFeedGridSpacing,
            runSpacing: kFeedGridSpacing,
            children: [
              for (var i = 0; i < visibleCount; i++)
                SizedBox(
                  width: tileWidth,
                  height: tileWidth,
                  child: _tile(
                    context,
                    items[i],
                    index: i,
                    mode: PostMediaPreviewMode.feed,
                    alignment: Alignment.topCenter,
                    extraOverlayCount:
                        extraCount > 0 && i == visibleCount - 1
                            ? extraCount
                            : null,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 比例与辅助工具
  // ---------------------------------------------------------------------------
  double _naturalRatio(PostMedia media, {double fallback = 4.0 / 3.0}) {
    final raw = mediaAssetRatio(media);
    if (raw == null) return fallback;
    return raw.clamp(0.1, 4.0).toDouble();
  }

  // ---------------------------------------------------------------------------
  // 单元格渲染
  // ---------------------------------------------------------------------------
  Widget _tile(
    BuildContext context,
    PostMedia media, {
    required int index,
    required PostMediaPreviewMode mode,
    BoxFit fit = BoxFit.cover,
    Alignment alignment = Alignment.center,
    bool showLongImageBadge = false,
    int? extraOverlayCount,
  }) {
    final imageUrl = mode == PostMediaPreviewMode.detail
        ? media.detailUrl
        : media.previewUrl;

    final tile = LayoutBuilder(
      builder: (context, constraints) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageUrl != null && imageUrl.isNotEmpty)
                AppNetworkImage(
                  url: imageUrl,
                  fit: fit,
                  alignment: alignment,
                  aspectRatio: mediaAssetRatio(media),
                  errorBuilder: (_) => _fallback(media),
                )
              else
                _fallback(media),

              // 裁剪长图弱提示（仅比例钳制时出现）
              if (showLongImageBadge)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6.5,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xCC0B1726),
                      borderRadius: BorderRadius.circular(4.5),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '长图',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                          ),
                        ),
                        SizedBox(width: 2.5),
                        Icon(
                          Icons.north_east_rounded,
                          size: 10.5,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                ),

              // 多图第4张覆盖 +N 蒙层
              if (extraOverlayCount != null)
                Container(
                  color: const Color(0x73000000),
                  alignment: Alignment.center,
                  child: Text(
                    '+$extraOverlayCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );

    if (onImageTap != null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onImageTap!(index),
        child: tile,
      );
    }
    if (onTap != null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: tile,
      );
    }
    return tile;
  }

  Widget _fallback(PostMedia media) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: media.colors.map(Color.new).toList(),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_outlined,
              color: Colors.white.withValues(alpha: .9),
              size: 28,
            ),
            const SizedBox(height: 4),
            Text(
              media.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MediaGalleryScreen extends StatefulWidget {
  const MediaGalleryScreen({
    super.key,
    required this.images,
    this.initialIndex = 0,
  });

  final List<PostMedia> images;
  final int initialIndex;

  @override
  State<MediaGalleryScreen> createState() => _MediaGalleryScreenState();
}

class _MediaGalleryScreenState extends State<MediaGalleryScreen> {
  late final PageController pageController;
  late int index;
  bool showingOriginal = false;

  @override
  void initState() {
    super.initState();
    index = widget.initialIndex.clamp(0, widget.images.length - 1);
    pageController = PageController(initialPage: index);
  }

  @override
  void dispose() {
    pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C1724),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text('${index + 1} / ${widget.images.length}'),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: pageController,
              itemCount: widget.images.length,
              onPageChanged: (value) => setState(() {
                index = value;
                // 每张图默认先展示详情图，避免滑到下一张时意外加载原图。
                showingOriginal = false;
              }),
              itemBuilder: (context, itemIndex) {
                final image = widget.images[itemIndex];
                final imageUrl = showingOriginal
                    ? image.original?.url ?? image.detailUrl
                    : image.detailUrl;
                return InteractiveViewer(
                  key: ValueKey(imageUrl),
                  minScale: 1,
                  maxScale: 3,
                  child: Center(
                    child: imageUrl == null
                        ? _fallback(image)
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final dpr = MediaQuery.devicePixelRatioOf(
                                context,
                              );
                              // 全屏查看支持双指放大，按 2 倍约束解码保证放大清晰度。
                              final zoomWidth =
                                  constraints.maxWidth.isFinite &&
                                      constraints.maxWidth > 0
                                  ? (constraints.maxWidth * dpr * 2)
                                        .round()
                                        .clamp(1, 8192)
                                  : null;
                              // 已知比例时解码高度按原图比例展开；未知比例时
                              // 只按宽度降采样、由 ResizeImage 按原图比例推断
                              // 高度——绝不能按显示框双轴精确缩放压扁位图。
                              return AppNetworkImage(
                                url: imageUrl,
                                fit: BoxFit.contain,
                                aspectRatio: mediaAssetRatio(image),
                                memCacheWidth: zoomWidth,
                                autoMemCacheSize: false,
                                errorBuilder: (_) => _fallback(image),
                              );
                            },
                          ),
                  ),
                );
              },
            ),
          ),
          if (_hasOriginalImage)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => showingOriginal = true),
                  icon: const Icon(Icons.high_quality_outlined),
                  label: const Text('查看原图'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: .6)),
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool get _hasOriginalImage {
    final originalUrl = widget.images[index].original?.url;
    return originalUrl != null &&
        originalUrl.isNotEmpty &&
        originalUrl != widget.images[index].detailUrl &&
        !showingOriginal;
  }

  Widget _fallback(PostMedia media) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: media.colors.map(Color.new).toList(),
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Center(
          child: Text(
            media.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
