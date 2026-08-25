import 'package:flutter/material.dart';

import '../data/mock_forum_data.dart';
import '../theme/app_theme.dart';

/// 帖子媒体预览。
///
/// 列表只使用稳定尺寸的缩略图，详情页通过 [MediaGalleryScreen] 查看原图，
/// 避免原图解码把长列表撑开或造成明显跳动。
class PostMediaPreview extends StatelessWidget {
  const PostMediaPreview({super.key, required this.images, this.onTap});

  final List<PostMedia> images;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return const SizedBox.shrink();
    final shown = images.length > 4 ? images.take(4).toList() : images;
    final more = images.length > 4 ? images.length - 4 : 0;
    final layout = _layout(shown, more);
    return Padding(
      padding: const EdgeInsets.only(top: 11),
      child: onTap == null
          ? layout
          : GestureDetector(onTap: onTap, child: layout),
    );
  }

  Widget _layout(List<PostMedia> shown, int more) {
    switch (shown.length) {
      case 1:
        return LayoutBuilder(
          builder: (context, constraints) {
            final height = (constraints.maxWidth / _ratio(shown.first))
                .clamp(132.0, 240.0)
                .toDouble();
            return SizedBox(
              width: constraints.maxWidth,
              height: height,
              child: _tile(shown.first),
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
                  Expanded(child: _tile(shown[0])),
                  const SizedBox(width: 5),
                  Expanded(child: _tile(shown[1])),
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
              Expanded(flex: 16, child: _tile(shown[0])),
              const SizedBox(width: 5),
              Expanded(
                flex: 10,
                child: Column(
                  children: [
                    Expanded(child: _tile(shown[1])),
                    const SizedBox(height: 5),
                    Expanded(child: _tile(shown[2])),
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
                    Expanded(child: _tile(shown[0])),
                    const SizedBox(width: 5),
                    Expanded(child: _tile(shown[1])),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _tile(shown[2])),
                    const SizedBox(width: 5),
                    Expanded(
                      child: _tile(
                        shown[3],
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
    final width = media.width?.toDouble() ?? 4;
    final height = media.height?.toDouble() ?? 3;
    return (width / height).clamp(.72, 1.78);
  }

  Widget _tile(PostMedia media, {String? overlay}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final cacheWidth =
            constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? (constraints.maxWidth * dpr).round()
            : null;
        final cacheHeight =
            constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? (constraints.maxHeight * dpr).round()
            : null;
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (media.url != null)
                Image.network(
                  media.url!,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                  cacheWidth: cacheWidth,
                  cacheHeight: cacheHeight,
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
                              duration: AppTheme.fastMotion,
                              curve: AppTheme.contentCurve,
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
      body: PageView.builder(
        controller: pageController,
        itemCount: widget.images.length,
        onPageChanged: (value) => setState(() => index = value),
        itemBuilder: (context, itemIndex) {
          final image = widget.images[itemIndex];
          return InteractiveViewer(
            minScale: 1,
            maxScale: 3,
            child: Center(
              child: image.url == null
                  ? _fallback(image)
                  : Image.network(
                      image.url!,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          _fallback(image),
                    ),
            ),
          );
        },
      ),
    );
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
