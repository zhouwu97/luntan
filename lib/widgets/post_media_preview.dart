import 'package:flutter/material.dart';

import '../data/mock_forum_data.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

/// 帖子媒体预览的使用场景。
enum PostMediaPreviewMode { feed, detail }

/// 帖子媒体预览。
///
/// Feed 使用稳定尺寸的缩略图，详情使用 detail 变体并允许更高的单图区域。
/// 图片始终保持源文件比例，不用拉伸填充；Feed 缩略图只做居中裁切，
/// 详情页则完整显示图片，不裁切内容。
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
    final shown = images.length > 4 ? images.take(4).toList() : images;
    final more = images.length > 4 ? images.length - 4 : 0;
    final layout = _layout(shown, more);
    return Padding(
      padding: const EdgeInsets.only(top: 11),
      child: onImageTap != null || onTap == null
          ? layout
          : GestureDetector(onTap: onTap, child: layout),
    );
  }

  Widget _layout(List<PostMedia> shown, int more) {
    switch (shown.length) {
      case 1:
        return LayoutBuilder(
          builder: (context, constraints) {
            final height = mode == PostMediaPreviewMode.detail
                ? (constraints.maxWidth / _ratio(shown.first))
                      .clamp(180.0, 600.0)
                      .toDouble()
                : (constraints.maxWidth * .62).clamp(180.0, 240.0).toDouble();
            return SizedBox(
              width: constraints.maxWidth,
              height: height,
              child: _tile(shown.first, index: 0),
            );
          },
        );
      case 2:
        return LayoutBuilder(
          builder: (context, constraints) {
            final height = ((constraints.maxWidth - 5) / 2)
                .clamp(132.0, 190.0)
                .toDouble();
            return SizedBox(
              height: height,
              child: Row(
                children: [
                  Expanded(child: _tile(shown[0], index: 0)),
                  const SizedBox(width: 5),
                  Expanded(child: _tile(shown[1], index: 1)),
                ],
              ),
            );
          },
        );
      case 3:
        return SizedBox(
          height: 194,
          child: Row(
            children: [
              Expanded(flex: 16, child: _tile(shown[0], index: 0)),
              const SizedBox(width: 5),
              Expanded(
                flex: 10,
                child: Column(
                  children: [
                    Expanded(child: _tile(shown[1], index: 1)),
                    const SizedBox(height: 5),
                    Expanded(child: _tile(shown[2], index: 2)),
                  ],
                ),
              ),
            ],
          ),
        );
      default:
        return AspectRatio(
          aspectRatio: 1,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _tile(shown[0], index: 0)),
                    const SizedBox(width: 5),
                    Expanded(child: _tile(shown[1], index: 1)),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _tile(shown[2], index: 2)),
                    const SizedBox(width: 5),
                    Expanded(
                      child: _tile(
                        shown[3],
                        index: 3,
                        overlay: more > 0 ? '+$more' : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
    }
  }

  double _ratio(PostMedia media) {
    final width = media.width?.toDouble();
    final height = media.height?.toDouble();
    if (width == null ||
        height == null ||
        !width.isFinite ||
        !height.isFinite) {
      return 4.0 / 3.0;
    }
    if (width <= 0 || height <= 0) return 4.0 / 3.0;
    // 仅限制极端/恶意元数据，正常图片的真实比例不做截断。
    return (width / height).clamp(.35, 3.0).toDouble();
  }

  Widget _tile(PostMedia media, {required int index, String? overlay}) {
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final cacheWidth =
            constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? (constraints.maxWidth * dpr).round()
            : null;
        // 只指定解码宽度，Flutter 会按原图比例计算高度；不能把卡片的
        // 横向容器高度作为 cacheHeight，否则竖图会在解码阶段被压扁。
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_imageUrl(media) != null)
                Image.network(
                  _imageUrl(media)!,
                  // Feed 缩略图使用 cover 做居中裁切；详情页必须 contain，
                  // 让用户看到完整图片。两种模式都不会拉伸原图。
                  fit: mode == PostMediaPreviewMode.detail
                      ? BoxFit.contain
                      : BoxFit.cover,
                  filterQuality: FilterQuality.low,
                  cacheWidth: cacheWidth,
                  frameBuilder:
                      (context, child, frame, wasSynchronouslyLoaded) {
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            const ColoredBox(color: AppTheme.surfaceBlue),
                            AnimatedOpacity(
                              opacity: frame == null && !wasSynchronouslyLoaded
                                  ? 0
                                  : 1,
                              duration: AppMotion.duration(
                                context,
                                AppMotion.fast,
                              ),
                              curve: AppMotion.standard,
                              child: child,
                            ),
                          ],
                        );
                      },
                  errorBuilder: (context, error, stackTrace) =>
                      _fallback(media),
                )
              else
                _fallback(media),
              if (overlay != null)
                const DecoratedBox(
                  decoration: BoxDecoration(color: Color(0x990E2037)),
                  child: Center(),
                ),
              if (overlay != null)
                Center(
                  child: Text(
                    overlay,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
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
        child: content,
      );
    }
    return content;
  }

  String? _imageUrl(PostMedia media) =>
      mode == PostMediaPreviewMode.detail ? media.detailUrl : media.previewUrl;

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
              size: 30,
            ),
            const SizedBox(height: 5),
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
