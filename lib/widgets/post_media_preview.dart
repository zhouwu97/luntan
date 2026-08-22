import 'package:flutter/material.dart';

import '../data/mock_forum_data.dart';

class PostMediaPreview extends StatelessWidget {
  const PostMediaPreview({super.key, required this.images, this.onTap});

  final List<PostMedia> images;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return const SizedBox.shrink();
    final shown = images.length > 4 ? images.take(4).toList() : images;
    final more = images.length > 4 ? images.length - 4 : 0;
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: _layout(shown, more),
      ),
    );
  }

  Widget _layout(List<PostMedia> shown, int more) {
    switch (shown.length) {
      case 1:
        return Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300, maxHeight: 220),
            child: AspectRatio(aspectRatio: 1.58, child: _tile(shown[0])),
          ),
        );
      case 2:
        return SizedBox(height: 122, width: 332, child: Row(children: [Expanded(child: _tile(shown[0])), const SizedBox(width: 8), Expanded(child: _tile(shown[1]))]));
      case 3:
        return SizedBox(
          height: 164,
          width: 332,
          child: Row(
            children: [
              Expanded(flex: 2, child: _tile(shown[0])),
              const SizedBox(width: 8),
              Expanded(child: Column(children: [Expanded(child: _tile(shown[1])), const SizedBox(height: 8), Expanded(child: _tile(shown[2]))])),
            ],
          ),
        );
      default:
        return SizedBox(
          height: 164,
          width: 332,
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8),
            itemCount: shown.length,
            itemBuilder: (_, index) => _tile(shown[index], overlay: index == shown.length - 1 && more > 0 ? '+$more' : null),
          ),
        );
    }
  }

  Widget _tile(PostMedia media, {String? overlay}) {
    return Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: media.colors.map(Color.new).toList(),
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Center(child: Text(media.emoji, style: const TextStyle(fontSize: 32))),
            ),
            Positioned(left: 10, bottom: 8, child: Text(media.label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, shadows: [Shadow(color: Color(0x66000000), blurRadius: 4)]))),
            if (overlay != null)
              DecoratedBox(
                decoration: const BoxDecoration(color: Color(0x990E2037)),
                child: Center(child: Text(overlay, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800))),
              ),
          ],
        ),
      );
  }
}

class MediaGalleryScreen extends StatelessWidget {
  const MediaGalleryScreen({super.key, required this.images});

  final List<PostMedia> images;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('图片 ${images.length} 张')),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12),
        itemCount: images.length,
        itemBuilder: (_, index) {
          final image = images[index];
          return Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(18)),
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: LinearGradient(colors: image.colors.map(Color.new).toList(), begin: Alignment.topLeft, end: Alignment.bottomRight)),
              child: Center(child: Text(image.emoji, style: const TextStyle(fontSize: 48))),
            ),
          );
        },
      ),
    );
  }
}
