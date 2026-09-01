import 'package:flutter/material.dart';

import '../app_network_image.dart';

/// 评论图片的统一全屏预览入口，支持多图切换、缩放与加载失败状态。
class CommentImageViewer {
  const CommentImageViewer._();

  static Future<void> open(
    BuildContext context, {
    required List<String> imageUrls,
    int initialIndex = 0,
  }) {
    final urls = imageUrls.where((url) => url.trim().isNotEmpty).toList();
    if (urls.isEmpty) return Future.value();
    final index = initialIndex.clamp(0, urls.length - 1);
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            _CommentImageViewerPage(imageUrls: urls, initialIndex: index),
      ),
    );
  }
}

class _CommentImageViewerPage extends StatefulWidget {
  const _CommentImageViewerPage({
    required this.imageUrls,
    required this.initialIndex,
  });

  final List<String> imageUrls;
  final int initialIndex;

  @override
  State<_CommentImageViewerPage> createState() =>
      _CommentImageViewerPageState();
}

class _CommentImageViewerPageState extends State<_CommentImageViewerPage> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      elevation: 0,
      title: widget.imageUrls.length > 1
          ? Text('${_currentIndex + 1} / ${widget.imageUrls.length}')
          : null,
    ),
    body: PageView.builder(
      controller: _pageController,
      itemCount: widget.imageUrls.length,
      onPageChanged: (index) => setState(() => _currentIndex = index),
      itemBuilder: (_, index) => Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: AppNetworkImage(
            url: widget.imageUrls[index],
            fit: BoxFit.contain,
            errorBuilder: (_) => const Icon(
              Icons.broken_image_outlined,
              color: Colors.white54,
              size: 64,
            ),
          ),
        ),
      ),
    ),
  );
}
