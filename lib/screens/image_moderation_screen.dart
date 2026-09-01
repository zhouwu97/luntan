import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../data/api/api_client.dart';
import '../data/api/platform_repository.dart';
import '../domain/models.dart';
import '../theme/app_theme.dart';
import '../widgets/app_network_image.dart';

/// 管理员图片打码处理页面。
/// 仅处理图片类型媒体，支持涂抹轨迹、马赛克/模糊效果切换、撤销、清除打码、
/// 服务端同步保存和初始/修改版本回溯。
class ImageModerationScreen extends StatefulWidget {
  const ImageModerationScreen({
    super.key,
    required this.post,
    this.initialMediaIndex = 0,
    this.platformRepository,
    this.onSaved,
    this.canRestoreCensored = false,
  });

  final Post post;
  final int initialMediaIndex;
  final PlatformRepository? platformRepository;
  final VoidCallback? onSaved;
  final bool canRestoreCensored;

  @override
  State<ImageModerationScreen> createState() => _ImageModerationScreenState();
}

class _ImageModerationScreenState extends State<ImageModerationScreen> {
  late int _selectedImageIndex;
  late List<MaskRegion> _currentRegions;
  final List<List<MaskRegion>> _undoHistory = [];
  String _currentType = 'mosaic'; // 'mosaic' or 'blur'
  double _brushSize = 0.045;
  List<Offset>? _activeStroke;
  bool _isSaving = false;
  Uint8List? _sourceBytes;
  String? _sourceMediaId;
  String? _sourceLoadError;
  List<MediaModerationVersion> _moderationHistory = const [];
  bool _historyLoading = false;

  List<MediaAsset> get _images => widget.post.images;

  @override
  void initState() {
    super.initState();
    _selectedImageIndex = widget.initialMediaIndex.clamp(
      0,
      _images.isEmpty ? 0 : _images.length - 1,
    );
    _loadCurrentMediaRegions();
    _loadCurrentMediaSource();
    _loadCurrentMediaHistory();
  }

  void _loadCurrentMediaRegions() {
    if (_images.isNotEmpty) {
      final media = _images[_selectedImageIndex];
      _currentRegions = List<MaskRegion>.from(media.maskRegions);
    } else {
      _currentRegions = [];
    }
    _undoHistory.clear();
    _activeStroke = null;
  }

  Future<void> _loadCurrentMediaHistory() async {
    _moderationHistory = const [];
    if (_images.isEmpty || widget.platformRepository == null) {
      if (mounted) setState(() {});
      return;
    }
    final mediaId = _images[_selectedImageIndex].id;
    setState(() => _historyLoading = true);
    try {
      final history = await widget.platformRepository!
          .getMediaModerationHistory(mediaId: mediaId);
      if (!mounted || _images[_selectedImageIndex].id != mediaId) return;
      setState(() => _moderationHistory = history);
    } catch (_) {
      // 版本接口不可用时不阻断当前打码流程，服务端仍是最终审计来源。
    } finally {
      if (mounted && _images[_selectedImageIndex].id == mediaId) {
        setState(() => _historyLoading = false);
      }
    }
  }

  Future<void> _loadCurrentMediaSource() async {
    _sourceBytes = null;
    _sourceMediaId = null;
    _sourceLoadError = null;
    if (_images.isEmpty || widget.platformRepository == null) {
      if (mounted) setState(() {});
      return;
    }
    final media = _images[_selectedImageIndex];
    if (!media.isCensored) {
      if (mounted) setState(() {});
      return;
    }
    final mediaID = media.id;
    try {
      final bytes = await widget.platformRepository!.getAdminMediaSource(
        mediaId: mediaID,
      );
      if (!mounted || _images[_selectedImageIndex].id != mediaID) return;
      setState(() {
        _sourceBytes = Uint8List.fromList(bytes);
        _sourceMediaId = mediaID;
      });
    } catch (error) {
      if (!mounted || _images[_selectedImageIndex].id != mediaID) return;
      setState(() => _sourceLoadError = '原图加载失败，请重试');
    }
  }

  void _pushHistory() {
    _undoHistory.add(List<MaskRegion>.from(_currentRegions));
  }

  void _undo() {
    if (_undoHistory.isNotEmpty) {
      setState(() {
        _currentRegions = _undoHistory.removeLast();
      });
    }
  }

  void _clearAll() {
    _pushHistory();
    setState(() {
      _currentRegions.clear();
    });
  }

  Future<void> _saveModeration({bool resetToNormal = false}) async {
    if (_isSaving || _images.isEmpty) return;
    final media = _images[_selectedImageIndex];

    if (resetToNormal && !widget.canRestoreCensored) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('只有超级管理员可以恢复未打码原图'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    if (!resetToNormal && _currentRegions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先在图片上涂抹需要遮挡的内容'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final status = resetToNormal ? 'normal' : 'censored';
      final regions = resetToNormal ? <MaskRegion>[] : _currentRegions;

      if (widget.platformRepository != null) {
        await widget.platformRepository!.moderateMedia(
          mediaId: media.id,
          moderationStatus: status,
          maskRegions: regions,
          reason: status == 'censored' ? '管理员手动打码' : '恢复正常展示',
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'censored' ? '打码处理已保存，服务端已生成打码图变体' : '已恢复原图正常展示',
          ),
          backgroundColor: AppTheme.primary,
        ),
      );
      widget.onSaved?.call();
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userFacingApiMessage(e, fallback: '图片处理失败，请稍后重试')),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _beginStroke(Offset position) {
    setState(() => _activeStroke = <Offset>[position]);
  }

  void _appendStroke(Offset position) {
    final stroke = _activeStroke;
    if (stroke == null || stroke.length >= 512) return;
    if (stroke.isNotEmpty && (stroke.last - position).distance < 1.5) return;
    setState(() => stroke.add(position));
  }

  void _finishStroke(double canvasW, double canvasH) {
    final stroke = _activeStroke;
    if (stroke == null || stroke.isEmpty || canvasW <= 0 || canvasH <= 0) {
      setState(() => _activeStroke = null);
      return;
    }
    final points = stroke
        .map(
          (point) => MaskPoint(
            x: (point.dx / canvasW).clamp(0.0, 1.0),
            y: (point.dy / canvasH).clamp(0.0, 1.0),
          ),
        )
        .toList(growable: false);
    var left = points.map((point) => point.x).reduce((a, b) => a < b ? a : b);
    var top = points.map((point) => point.y).reduce((a, b) => a < b ? a : b);
    var right = points.map((point) => point.x).reduce((a, b) => a > b ? a : b);
    var bottom = points.map((point) => point.y).reduce((a, b) => a > b ? a : b);
    const minBox = 0.004;
    if (right - left < minBox) {
      final center = (left + right) / 2;
      left = (center - minBox / 2).clamp(0.0, 1.0 - minBox);
      right = left + minBox;
    }
    if (bottom - top < minBox) {
      final center = (top + bottom) / 2;
      top = (center - minBox / 2).clamp(0.0, 1.0 - minBox);
      bottom = top + minBox;
    }
    _pushHistory();
    setState(() {
      _currentRegions.add(
        MaskRegion(
          x: left,
          y: top,
          width: right - left,
          height: bottom - top,
          type: _currentType,
          points: points,
          brushSize: _brushSize,
        ),
      );
      _activeStroke = null;
    });
  }

  Widget _buildSourceImage(MediaAsset currentMedia, String imageUrl) {
    if (currentMedia.isCensored && widget.platformRepository != null) {
      if (_sourceMediaId == currentMedia.id && _sourceBytes != null) {
        return Image.memory(
          _sourceBytes!,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => _sourceError('原图无法显示'),
        );
      }
      if (_sourceLoadError != null) {
        return _sourceError(
          _sourceLoadError!,
          onRetry: _loadCurrentMediaSource,
        );
      }
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    return AppNetworkImage(
      url: imageUrl,
      fit: BoxFit.contain,
      errorBuilder: (_) => _sourceError('图片加载中或无法访问'),
    );
  }

  Widget _sourceError(String message, {VoidCallback? onRetry}) {
    return Container(
      color: Colors.black26,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: const TextStyle(color: Colors.white70)),
            if (onRetry != null) ...[
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _isSaving ? null : onRetry,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),
                child: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatHistoryTime(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    if (_images.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF181A20),
        appBar: AppBar(
          backgroundColor: const Color(0xFF23262F),
          title: const Text('图片处理', style: TextStyle(color: Colors.white)),
        ),
        body: const Center(
          child: Text('该帖子没有图片可处理', style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    final currentMedia = _images[_selectedImageIndex];
    final imageUrl =
        currentMedia.originalUrl ??
        currentMedia.detailUrl ??
        currentMedia.url ??
        '';

    return Scaffold(
      backgroundColor: const Color(0xFF181A20),
      appBar: AppBar(
        backgroundColor: const Color(0xFF23262F),
        elevation: 0,
        title: Text(
          '图片处理 (${_selectedImageIndex + 1}/${_images.length})',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip: '撤销上一步',
            icon: Icon(
              Icons.undo,
              color: (!_isSaving && _undoHistory.isNotEmpty)
                  ? Colors.white
                  : Colors.white38,
            ),
            onPressed: (!_isSaving && _undoHistory.isNotEmpty) ? _undo : null,
          ),
          IconButton(
            tooltip: '清空打码',
            icon: Icon(
              Icons.delete_outline,
              color: (!_isSaving && _currentRegions.isNotEmpty)
                  ? Colors.redAccent
                  : Colors.white38,
            ),
            onPressed: (!_isSaving && _currentRegions.isNotEmpty)
                ? _clearAll
                : null,
          ),
          TextButton(
            onPressed: _isSaving ? null : () => _saveModeration(),
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    '保存打码',
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (_images.length > 1)
            Container(
              height: 72,
              color: const Color(0xFF23262F),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _images.length,
                itemBuilder: (context, index) {
                  final m = _images[index];
                  final isSelected = index == _selectedImageIndex;
                  return GestureDetector(
                    onTap: _isSaving
                        ? null
                        : () {
                            if (index != _selectedImageIndex) {
                              setState(() {
                                _selectedImageIndex = index;
                                _loadCurrentMediaRegions();
                              });
                              _loadCurrentMediaSource();
                              _loadCurrentMediaHistory();
                            }
                          },
                    child: Container(
                      width: 56,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.primary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: AppNetworkImage(
                        url: m.thumbUrl ?? m.url,
                        fit: BoxFit.cover,
                        errorBuilder: (_) => Container(
                          color: Colors.grey[800],
                          child: const Icon(Icons.image, color: Colors.white54),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          Expanded(
            child: IgnorePointer(
              ignoring: _isSaving,
              child: Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final imgW = currentMedia.width?.toDouble() ?? 800;
                    final imgH = currentMedia.height?.toDouble() ?? 600;
                    final aspect = (imgW > 0 && imgH > 0) ? imgW / imgH : 4 / 3;

                    return AspectRatio(
                      aspectRatio: aspect,
                      child: LayoutBuilder(
                        builder: (canvasCtx, canvasConstraints) {
                          final canvasW = canvasConstraints.maxWidth;
                          final canvasH = canvasConstraints.maxHeight;

                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              _buildSourceImage(currentMedia, imageUrl),
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanStart: (details) =>
                                    _beginStroke(details.localPosition),
                                onPanUpdate: (details) =>
                                    _appendStroke(details.localPosition),
                                onPanEnd: (_) =>
                                    _finishStroke(canvasW, canvasH),
                                onPanCancel: () {
                                  if (mounted) {
                                    setState(() => _activeStroke = null);
                                  }
                                },
                                child: CustomPaint(
                                  painter: _MaskCanvasPainter(
                                    regions: _currentRegions,
                                    activeStroke: _activeStroke,
                                    brushSize: _brushSize,
                                    currentType: _currentType,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          if (_historyLoading || _moderationHistory.isNotEmpty)
            Container(
              height: 88,
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              color: const Color(0xFF1F222A),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '版本记录',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Expanded(
                    child: _historyLoading && _moderationHistory.isEmpty
                        ? const Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.primary,
                              ),
                            ),
                          )
                        : ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _moderationHistory.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 6),
                            itemBuilder: (context, index) {
                              final version = _moderationHistory[index];
                              final label = version.isInitial
                                  ? '初发布·未打码'
                                  : version.moderationStatus == 'censored'
                                  ? '已打码'
                                  : '已恢复原图';
                              return Container(
                                width: 138,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2A2E38),
                                  borderRadius: BorderRadius.circular(7),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'v${version.versionNo}  $label',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      version.reason.isEmpty
                                          ? '无备注'
                                          : version.reason,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 10,
                                      ),
                                    ),
                                    Text(
                                      _formatHistoryTime(version.createdAt),
                                      style: const TextStyle(
                                        color: Colors.white38,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          IgnorePointer(
            ignoring: _isSaving,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              decoration: const BoxDecoration(
                color: Color(0xFF23262F),
                border: Border(
                  top: BorderSide(color: Color(0xFF353945), width: 1),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.brush_outlined,
                          color: AppTheme.primary,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            '在图片上直接涂抹需要遮挡的内容',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (currentMedia.isCensored &&
                            widget.canRestoreCensored)
                          TextButton.icon(
                            icon: const Icon(
                              Icons.restore,
                              color: Colors.orangeAccent,
                              size: 17,
                            ),
                            label: const Text(
                              '恢复原图',
                              style: TextStyle(color: Colors.orangeAccent),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () =>
                                _saveModeration(resetToNormal: true),
                          )
                        else if (currentMedia.isCensored)
                          const Text(
                            '仅超级管理员可恢复',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          '遮挡样式',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        ChoiceChip(
                          label: const Text('马赛克'),
                          selected: _currentType == 'mosaic',
                          selectedColor: AppTheme.primary,
                          onSelected: (val) {
                            if (val) setState(() => _currentType = 'mosaic');
                          },
                        ),
                        ChoiceChip(
                          label: const Text('毛玻璃模糊'),
                          selected: _currentType == 'blur',
                          selectedColor: AppTheme.primary,
                          onSelected: (val) {
                            if (val) setState(() => _currentType = 'blur');
                          },
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Text(
                          '笔刷大小',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        Expanded(
                          child: Slider(
                            value: _brushSize,
                            min: 0.01,
                            max: 0.12,
                            divisions: 22,
                            activeColor: AppTheme.primary,
                            inactiveColor: Colors.white24,
                            onChanged: (value) =>
                                setState(() => _brushSize = value),
                          ),
                        ),
                        SizedBox(
                          width: 36,
                          child: Text(
                            '${(_brushSize * 100).round()}%',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MaskCanvasPainter extends CustomPainter {
  _MaskCanvasPainter({
    required this.regions,
    this.activeStroke,
    required this.brushSize,
    required this.currentType,
  });

  final List<MaskRegion> regions;
  final List<Offset>? activeStroke;
  final double brushSize;
  final String currentType;

  Path _pathForPoints(List<MaskPoint> points, Size size) {
    final path = Path();
    if (points.isEmpty) return path;
    path.moveTo(points.first.x * size.width, points.first.y * size.height);
    for (final point in points.skip(1)) {
      path.lineTo(point.x * size.width, point.y * size.height);
    }
    return path;
  }

  void _drawStroke(
    Canvas canvas,
    List<MaskPoint> points,
    Size size, {
    required double width,
    required Color color,
    PaintingStyle style = PaintingStyle.stroke,
    StrokeCap cap = StrokeCap.round,
  }) {
    if (points.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..style = style
      ..strokeWidth = width
      ..strokeCap = cap
      ..strokeJoin = StrokeJoin.round;
    final path = _pathForPoints(points, size);
    if (points.length == 1) {
      canvas.drawCircle(
        Offset(points.first.x * size.width, points.first.y * size.height),
        width / 2,
        paint,
      );
    } else {
      canvas.drawPath(path, paint);
    }
  }

  void _drawActiveStroke(
    Canvas canvas,
    List<Offset> points,
    Size size, {
    required double width,
    required Color color,
  }) {
    if (points.isEmpty) return;
    final normalized = points
        .map(
          (point) => MaskPoint(
            x: (point.dx / size.width).clamp(0.0, 1.0),
            y: (point.dy / size.height).clamp(0.0, 1.0),
          ),
        )
        .toList(growable: false);
    _drawStroke(canvas, normalized, size, width: width, color: color);
  }

  double _brushPixelSize(double normalizedSize, Size size) {
    final shortEdge = size.width < size.height ? size.width : size.height;
    return (normalizedSize.clamp(0.01, 0.25) * shortEdge).clamp(
      4.0,
      shortEdge * 0.8,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final mosaicPaint = Paint()
      ..color = const Color(0xCC333333)
      ..style = PaintingStyle.fill;

    final blurPaint = Paint()
      ..color = const Color(0xAAEEEEEE)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = AppTheme.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final gridPaint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int i = 0; i < regions.length; i++) {
      final r = regions[i];
      if (r.points.isNotEmpty) {
        final width = _brushPixelSize(r.brushSize, size);
        final overlayColor = r.type == 'blur'
            ? const Color(0xAAEEEEEE)
            : const Color(0xCC333333);
        _drawStroke(canvas, r.points, size, width: width, color: overlayColor);
        if (r.type == 'mosaic') {
          // 在涂抹轨迹上叠加细纹，帮助管理员确认马赛克覆盖范围。
          _drawStroke(
            canvas,
            r.points,
            size,
            width: 1.0,
            color: Colors.white24,
          );
        }
        _drawStroke(
          canvas,
          r.points,
          size,
          width: 1.5,
          color: AppTheme.primary,
        );
        continue;
      }
      final rect = Rect.fromLTWH(
        r.x * size.width,
        r.y * size.height,
        r.width * size.width,
        r.height * size.height,
      );

      canvas.drawRect(rect, r.type == 'blur' ? blurPaint : mosaicPaint);

      if (r.type == 'mosaic') {
        const double step = 12.0;
        for (double x = rect.left; x < rect.right; x += step) {
          canvas.drawLine(
            Offset(x, rect.top),
            Offset(x, rect.bottom),
            gridPaint,
          );
        }
        for (double y = rect.top; y < rect.bottom; y += step) {
          canvas.drawLine(
            Offset(rect.left, y),
            Offset(rect.right, y),
            gridPaint,
          );
        }
      }

      canvas.drawRect(rect, borderPaint);
    }

    final active = activeStroke;
    if (active != null && active.isNotEmpty) {
      _drawActiveStroke(
        canvas,
        active,
        size,
        width: _brushPixelSize(brushSize, size),
        color: currentType == 'blur'
            ? const Color(0xAAEEEEEE)
            : const Color(0xCC333333),
      );
      _drawActiveStroke(
        canvas,
        active,
        size,
        width: 2.0,
        color: Colors.yellowAccent,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MaskCanvasPainter oldDelegate) => true;
}
