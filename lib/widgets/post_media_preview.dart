import 'package:flutter/material.dart';

import '../data/mock_forum_data.dart';
import 'app_network_image.dart';

/// 帖子媒体预览的使用场景。
enum PostMediaPreviewMode { feed, detail }

/// 帖子媒体预览。
///
/// Feed 场景：
/// - 单图采用「比例钳制（0.72 ~ 1.78）」，3:4、4:5、1:1、4:3、16:9 完整展示，超长图（<0.72）高度限制在 width/0.72，极长图（<0.60）采用顶部对齐并在右下角轻量提示“长图 ↗”；
/// - 多图采用拼图布局（2图左右并排、3图左大右小上下排、4图及以上2×2网格，第4张叠加+N）。
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
  // Feed 场景：单图比例钳制 + 多图拼图
  // ---------------------------------------------------------------------------
  Widget _buildFeedStream(BuildContext context) {
    final count = images.length;
    Widget content;

    if (count == 1) {
      content = _buildFeedSingleImage(context, images.first);
    } else if (count == 2) {
      content = _buildFeedTwoImages(context, images);
    } else if (count == 3) {
      content = _buildFeedThreeImages(context, images);
    } else {
      content = _buildFeedFourPlusImages(context, images);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: content,
    );
  }

  /// 单图自适应预览（比例钳制 0.72 ~ 1.78）
  Widget _buildFeedSingleImage(BuildContext context, PostMedia media) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final rawRatio = _rawRatio(media);
        final ratio = (rawRatio ?? (4.0 / 3.0)).clamp(0.72, 1.78).toDouble();
        final width = constraints.maxWidth;
        final height = width / ratio;
        final isLongCrop = rawRatio != null && rawRatio < 0.72;
        final isTopCrop = rawRatio != null && rawRatio < 0.60;

        return SizedBox(
          width: width,
          height: height,
          child: _tile(
            context,
            media,
            index: 0,
            mode: PostMediaPreviewMode.feed,
            alignment: isTopCrop ? Alignment.topCenter : Alignment.center,
            showLongImageBadge: isLongCrop,
          ),
        );
      },
    );
  }

  /// 2张图：左右等分拼图
  Widget _buildFeedTwoImages(BuildContext context, List<PostMedia> items) {
    const spacing = 6.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final itemWidth = (width - spacing) / 2;
        final height = itemWidth * 0.95;

        return SizedBox(
          width: width,
          height: height,
          child: Row(
            children: [
              Expanded(
                child: _tile(
                  context,
                  items[0],
                  index: 0,
                  mode: PostMediaPreviewMode.feed,
                ),
              ),
              const SizedBox(width: spacing),
              Expanded(
                child: _tile(
                  context,
                  items[1],
                  index: 1,
                  mode: PostMediaPreviewMode.feed,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 3张图：左大 + 右二上下排列拼图
  Widget _buildFeedThreeImages(BuildContext context, List<PostMedia> items) {
    const spacing = 6.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = width * 0.60;
        final leftWidth = (width - spacing) * 0.58;
        final rightWidth = (width - spacing) * 0.42;

        return SizedBox(
          width: width,
          height: height,
          child: Row(
            children: [
              SizedBox(
                width: leftWidth,
                height: height,
                child: _tile(
                  context,
                  items[0],
                  index: 0,
                  mode: PostMediaPreviewMode.feed,
                ),
              ),
              const SizedBox(width: spacing),
              SizedBox(
                width: rightWidth,
                height: height,
                child: Column(
                  children: [
                    Expanded(
                      child: _tile(
                        context,
                        items[1],
                        index: 1,
                        mode: PostMediaPreviewMode.feed,
                      ),
                    ),
                    const SizedBox(height: spacing),
                    Expanded(
                      child: _tile(
                        context,
                        items[2],
                        index: 2,
                        mode: PostMediaPreviewMode.feed,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 4张及以上：2×2 宫格拼图，第4张支持覆盖 +N
  Widget _buildFeedFourPlusImages(BuildContext context, List<PostMedia> items) {
    const spacing = 6.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final itemHeight = (width - spacing) / 2 * 0.88;
        final totalHeight = itemHeight * 2 + spacing;
        final extraCount = items.length - 4;

        return SizedBox(
          width: width,
          height: totalHeight,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _tile(
                        context,
                        items[0],
                        index: 0,
                        mode: PostMediaPreviewMode.feed,
                      ),
                    ),
                    const SizedBox(width: spacing),
                    Expanded(
                      child: _tile(
                        context,
                        items[1],
                        index: 1,
                        mode: PostMediaPreviewMode.feed,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: spacing),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _tile(
                        context,
                        items[2],
                        index: 2,
                        mode: PostMediaPreviewMode.feed,
                      ),
                    ),
                    const SizedBox(width: spacing),
                    Expanded(
                      child: _tile(
                        context,
                        items[3],
                        index: 3,
                        mode: PostMediaPreviewMode.feed,
                        extraOverlayCount: extraCount > 0 ? extraCount : null,
                      ),
                    ),
                  ],
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
  double? _rawRatio(PostMedia media) {
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

  double _naturalRatio(PostMedia media, {double fallback = 4.0 / 3.0}) {
    final raw = _rawRatio(media);
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
                  fit: BoxFit.cover,
                  alignment: alignment,
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
                              return AppNetworkImage(
                                url: imageUrl,
                                fit: BoxFit.contain,
                                memCacheWidth: zoomWidth,
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
