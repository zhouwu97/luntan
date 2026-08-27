import 'package:flutter/material.dart';

import '../data/mock_forum_data.dart';

/// 帖子媒体预览的使用场景。
enum PostMediaPreviewMode { feed, detail }

/// 帖子媒体预览。
///
/// Feed 按真实比例自适应展示大图与垂直多图，极长图增加展开提示；
/// 详情页则按顺序纵向完整展开所有图片，自然向下滚动，不加固定高度限制与蓝边。
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

  Widget _buildDetailStream(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: List.generate(images.length, (index) {
          final image = images[index];
          final ratio = _naturalRatio(image, fallback: 4 / 3);
          return Padding(
            padding: EdgeInsets.only(bottom: index < images.length - 1 ? 10.0 : 0.0),
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

  Widget _buildFeedStream(BuildContext context) {
    final shown = images.length > 3 ? images.take(3).toList() : images;
    final totalCount = images.length;

    Widget content;
    if (shown.length == 1) {
      content = LayoutBuilder(
        builder: (context, constraints) {
          final media = shown.first;
          final rawRatio = _rawRatio(media);
          final isExtremeLong = rawRatio != null && rawRatio < 0.45;
          final ratio = (rawRatio ?? (4.0 / 3.0)).clamp(0.55, 2.2).toDouble();
          final width = constraints.maxWidth;
          final height = width / ratio;

          return SizedBox(
            width: width,
            height: height,
            child: _tile(
              context,
              media,
              index: 0,
              mode: PostMediaPreviewMode.feed,
              isExtremeLong: isExtremeLong,
            ),
          );
        },
      );
    } else if (shown.length == 2) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFeedItem(context, shown[0], index: 0),
          const SizedBox(height: 8),
          _buildFeedItem(context, shown[1], index: 1),
        ],
      );
    } else {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFeedItem(context, shown[0], index: 0),
          const SizedBox(height: 8),
          _buildFeedItem(context, shown[1], index: 1),
          const SizedBox(height: 8),
          _buildFeedItem(
            context,
            shown[2],
            index: 2,
            countBadge: totalCount > 3 ? '共 $totalCount 张' : null,
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: content,
    );
  }

  Widget _buildFeedItem(
    BuildContext context,
    PostMedia media, {
    required int index,
    String? countBadge,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final rawRatio = _rawRatio(media);
        final isExtremeLong = rawRatio != null && rawRatio < 0.45;
        final ratio = (rawRatio ?? (16.0 / 10.0)).clamp(0.75, 2.2).toDouble();
        final width = constraints.maxWidth;
        final height = width / ratio;

        return SizedBox(
          width: width,
          height: height,
          child: _tile(
            context,
            media,
            index: index,
            mode: PostMediaPreviewMode.feed,
            countBadge: countBadge,
            isExtremeLong: isExtremeLong,
          ),
        );
      },
    );
  }

  double? _rawRatio(PostMedia media) {
    final width = media.width?.toDouble();
    final height = media.height?.toDouble();
    if (width == null || height == null || !width.isFinite || !height.isFinite) {
      return null;
    }
    if (width <= 0 || height <= 0) return null;
    return width / height;
  }

  double _naturalRatio(PostMedia media, {double fallback = 4.0 / 3.0}) {
    final raw = _rawRatio(media);
    if (raw == null) return fallback;
    return raw.clamp(0.2, 3.5).toDouble();
  }

  Widget _tile(
    BuildContext context,
    PostMedia media, {
    required int index,
    required PostMediaPreviewMode mode,
    String? countBadge,
    bool isExtremeLong = false,
  }) {
    final imageUrl = mode == PostMediaPreviewMode.detail
        ? media.detailUrl
        : media.previewUrl;

    final tile = LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final cacheWidth = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? (constraints.maxWidth * dpr).round()
            : null;

        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageUrl != null && imageUrl.isNotEmpty)
                Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                  cacheWidth: cacheWidth,
                  frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        const ColoredBox(color: Color(0xFFF4F6F9)),
                        AnimatedOpacity(
                          opacity: frame != null || wasSynchronouslyLoaded ? 1 : 0,
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOut,
                          child: child,
                        ),
                      ],
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => _fallback(media),
                )
              else
                _fallback(media),

              // 极长图底部提示
              if (isExtremeLong && mode == PostMediaPreviewMode.feed)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, Color(0xB30B1726)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.unfold_more_rounded,
                          size: 15,
                          color: Colors.white,
                        ),
                        SizedBox(width: 4),
                        Text(
                          '长图 · 点击查看完整图片',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // 多图数量角标
              if (countBadge != null)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: const Color(0xCC0B1726),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      countBadge,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
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
                              final cacheWidth =
                                  constraints.maxWidth.isFinite &&
                                      constraints.maxWidth > 0
                                  ? (constraints.maxWidth * dpr * 2).round()
                                  : null;
                              return Image.network(
                                imageUrl,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.medium,
                                cacheWidth: cacheWidth,
                                errorBuilder: (context, error, stackTrace) =>
                                    _fallback(image),
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
