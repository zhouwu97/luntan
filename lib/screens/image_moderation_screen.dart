import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../data/api/api_client.dart';
import '../data/api/platform_repository.dart';
import '../domain/models.dart';
import '../theme/app_theme.dart';
import '../widgets/app_network_image.dart';

/// 管理员图片打码处理页面。
/// 支持涂抹轨迹、马赛克/模糊真实预览、撤销/重做、橡皮擦（整笔删除）、
/// 服务端同步保存和版本历史回溯。
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
  final List<List<MaskRegion>> _redoHistory = [];

  String _currentType = 'mosaic'; // 'mosaic' | 'blur'
  String _currentTool = 'brush'; // 'brush' | 'eraser'
  double _brushSize = 0.04;
  List<Offset>? _activeStroke;
  bool _isSaving = false;

  // Decoded source image and pre-generated mosaic variant for real preview.
  ui.Image? _decodedImage;
  ui.Image? _mosaicImage;
  Uint8List? _sourceBytes;
  String? _sourceLoadError;

  // Version history.
  List<MediaModerationVersion> _moderationHistory = const [];
  bool _historyLoading = false;

  // Canvas dimensions set by LayoutBuilder — used for coordinate normalisation
  // and eraser hit testing.
  double _canvasW = 0;
  double _canvasH = 0;

  // Whether an undo snapshot was already pushed during the current eraser swipe
  // (so all deletions in one swipe revert as a single undo step).
  bool _eraserUndoPushed = false;

  List<MediaAsset> get _images => widget.post.images;

  // ──────────────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _selectedImageIndex = widget.initialMediaIndex.clamp(
      0,
      _images.isEmpty ? 0 : _images.length - 1,
    );
    _loadCurrentMediaRegions();
    _loadAndDecodeImage();
    _loadCurrentMediaHistory();
  }

  @override
  void dispose() {
    _decodedImage?.dispose();
    _mosaicImage?.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────
  // Data loading
  // ──────────────────────────────────────────────────────────────

  void _loadCurrentMediaRegions() {
    if (_images.isNotEmpty) {
      _currentRegions = List<MaskRegion>.from(
        _images[_selectedImageIndex].maskRegions,
      );
    } else {
      _currentRegions = [];
    }
    _undoHistory.clear();
    _redoHistory.clear();
    _activeStroke = null;
  }

  /// Loads the source image bytes, decodes them into a [ui.Image], and
  /// pre-generates the pixelated mosaic variant for real-time preview.
  Future<void> _loadAndDecodeImage() async {
    _decodedImage?.dispose();
    _mosaicImage?.dispose();
    _decodedImage = null;
    _mosaicImage = null;
    _sourceBytes = null;
    _sourceLoadError = null;
    if (mounted) setState(() {});

    if (_images.isEmpty) return;

    final media = _images[_selectedImageIndex];
    final mediaId = media.id;

    try {
      ui.Image decoded;

      if (media.isCensored && widget.platformRepository != null) {
        // Admin endpoint returns the uncensored original bytes.
        final bytes = await widget.platformRepository!.getAdminMediaSource(
          mediaId: mediaId,
        );
        if (!mounted || _images[_selectedImageIndex].id != mediaId) return;
        _sourceBytes = Uint8List.fromList(bytes);
        decoded = await _decodePreviewImage(_sourceBytes!);
        _sourceBytes = null;
      } else {
        // 编辑遮罩使用归一化坐标，不需要解码原始大图。
        // 使用媒体网关 detail variant 获取编码字节进行有界解码。
        // 绝不使用 NetworkImage 进行解码，避免大图 OOM。
        final bytes = widget.platformRepository != null
            ? await widget.platformRepository!.getMediaPreviewBytesById(mediaId)
            : await _fetchRawImageBytes(media.detail?.url ?? media.url ?? '');
        if (!mounted || _images[_selectedImageIndex].id != mediaId) return;
        decoded = await _decodePreviewImage(Uint8List.fromList(bytes));
      }

      if (!mounted || _images[_selectedImageIndex].id != mediaId) {
        decoded.dispose();
        return;
      }

      final mosaicVariant = await _buildMosaicVariant(decoded);
      if (!mounted || _images[_selectedImageIndex].id != mediaId) {
        decoded.dispose();
        mosaicVariant.dispose();
        return;
      }

      setState(() {
        _decodedImage = decoded;
        _mosaicImage = mosaicVariant;
      });
    } catch (_) {
      if (mounted &&
          _images.isNotEmpty &&
          _images[_selectedImageIndex].id == mediaId) {
        setState(() => _sourceLoadError = '原图加载失败，请重试');
      }
    }
  }

  /// Decodes a bounded preview so large originals do not allocate full-size
  /// RGBA buffers in the editor. Mask coordinates remain normalised.
  Future<ui.Image> _decodePreviewImage(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    const maxDimension = 2048;
    final scale = min(
      1.0,
      maxDimension / max(descriptor.width, descriptor.height),
    );
    final targetWidth = max(1, (descriptor.width * scale).round());
    final targetHeight = max(1, (descriptor.height * scale).round());
    final codec = await descriptor.instantiateCodec(
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  }

  /// Fetches raw image bytes directly via HTTP, without decoding.
  /// Fallback for when PlatformRepository is not available.
  Future<Uint8List> _fetchRawImageBytes(String url) async {
    final uri = Uri.parse(url);
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception('Failed to load image: ${response.statusCode}');
      }
      final bytes = await consolidateHttpClientResponseBytes(response);
      return bytes;
    } finally {
      client.close();
    }
  }

  /// Generates a pixelated (mosaic) variant by down-scaling then up-scaling
  /// with nearest-neighbour interpolation.  Block size matches the server's
  /// `max(8, (w+h)/100)`.
  Future<ui.Image> _buildMosaicVariant(ui.Image source) async {
    final w = source.width;
    final h = source.height;
    final block = max(8, (w + h) ~/ 100);
    final sw = max(1, w ~/ block);
    final sh = max(1, h ~/ block);

    // Down-scale.
    final r1 = ui.PictureRecorder();
    Canvas(r1).drawImageRect(
      source,
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Rect.fromLTWH(0, 0, sw.toDouble(), sh.toDouble()),
      Paint(),
    );
    final small = await r1.endRecording().toImage(sw, sh);

    // Nearest-neighbour up-scale.
    final r2 = ui.PictureRecorder();
    Canvas(r2).drawImageRect(
      small,
      Rect.fromLTWH(0, 0, sw.toDouble(), sh.toDouble()),
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..filterQuality = FilterQuality.none,
    );
    final result = await r2.endRecording().toImage(w, h);
    small.dispose();
    return result;
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
      if (mounted &&
          _images.isNotEmpty &&
          _images[_selectedImageIndex].id == mediaId) {
        setState(() => _historyLoading = false);
      }
    }
  }

  // ──────────────────────────────────────────────────────────────
  // Undo / Redo / Clear
  // ──────────────────────────────────────────────────────────────

  void _pushUndo() {
    _undoHistory.add(List<MaskRegion>.from(_currentRegions));
    _redoHistory.clear();
  }

  void _undo() {
    if (_undoHistory.isEmpty) return;
    setState(() {
      _redoHistory.add(List<MaskRegion>.from(_currentRegions));
      _currentRegions = _undoHistory.removeLast();
    });
  }

  void _redo() {
    if (_redoHistory.isEmpty) return;
    setState(() {
      _undoHistory.add(List<MaskRegion>.from(_currentRegions));
      _currentRegions = _redoHistory.removeLast();
    });
  }

  void _confirmClearAll() {
    if (_currentRegions.isEmpty) return;
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF23262F),
        title: const Text('清除全部打码？', style: TextStyle(color: Colors.white)),
        content: const Text(
          '当前图片上的所有未保存打码都会被移除。',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('清除'),
          ),
        ],
      ),
    ).then((yes) {
      if (yes == true && mounted) {
        _pushUndo();
        setState(() => _currentRegions.clear());
      }
    });
  }

  // ──────────────────────────────────────────────────────────────
  // Gesture Handling (Brush / Eraser)
  // ──────────────────────────────────────────────────────────────

  void _onPanStart(Offset pos) {
    if (_currentTool == 'eraser') {
      _eraserUndoPushed = false;
      _tryEraseAt(pos);
    } else {
      setState(() => _activeStroke = <Offset>[pos]);
    }
  }

  void _onPanUpdate(Offset pos) {
    if (_currentTool == 'eraser') {
      _tryEraseAt(pos);
    } else {
      final s = _activeStroke;
      if (s == null || s.length >= 512) return;
      if (s.isNotEmpty && (s.last - pos).distance < 1.5) return;
      setState(() => s.add(pos));
    }
  }

  void _onPanEnd() {
    if (_currentTool == 'eraser') {
      _eraserUndoPushed = false;
      return;
    }
    _commitStroke();
  }

  void _onPanCancel() {
    if (mounted) setState(() => _activeStroke = null);
    _eraserUndoPushed = false;
  }

  void _commitStroke() {
    final stroke = _activeStroke;
    if (stroke == null || stroke.isEmpty || _canvasW <= 0 || _canvasH <= 0) {
      setState(() => _activeStroke = null);
      return;
    }

    final points = stroke
        .map(
          (p) => MaskPoint(
            x: (p.dx / _canvasW).clamp(0.0, 1.0),
            y: (p.dy / _canvasH).clamp(0.0, 1.0),
          ),
        )
        .toList(growable: false);

    var left = points.map((p) => p.x).reduce(min);
    var top = points.map((p) => p.y).reduce(min);
    var right = points.map((p) => p.x).reduce(max);
    var bottom = points.map((p) => p.y).reduce(max);

    const minBox = 0.004;
    if (right - left < minBox) {
      final cx = (left + right) / 2;
      left = (cx - minBox / 2).clamp(0.0, 1.0 - minBox);
      right = left + minBox;
    }
    if (bottom - top < minBox) {
      final cy = (top + bottom) / 2;
      top = (cy - minBox / 2).clamp(0.0, 1.0 - minBox);
      bottom = top + minBox;
    }

    _pushUndo();
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

  /// Removes the top-most region whose brush stroke covers [pos].
  void _tryEraseAt(Offset pos) {
    if (_canvasW <= 0 || _canvasH <= 0) return;
    final nx = (pos.dx / _canvasW).clamp(0.0, 1.0);
    final ny = (pos.dy / _canvasH).clamp(0.0, 1.0);

    for (int i = _currentRegions.length - 1; i >= 0; i--) {
      if (_hitTestRegion(_currentRegions[i], nx, ny)) {
        if (!_eraserUndoPushed) {
          _pushUndo();
          _eraserUndoPushed = true;
        }
        setState(() => _currentRegions.removeAt(i));
        return;
      }
    }
  }

  /// Point-in-brush hit test mirroring the server's `pointInBrush`.
  bool _hitTestRegion(MaskRegion r, double nx, double ny) {
    if (r.points.isEmpty) {
      return nx >= r.x &&
          nx <= r.x + r.width &&
          ny >= r.y &&
          ny <= r.y + r.height;
    }
    final se = min(_canvasW, _canvasH);
    final radius = max(4.0, r.brushSize * se / 2);
    final px = nx * _canvasW;
    final py = ny * _canvasH;

    for (int i = 0; i < r.points.length; i++) {
      final ax = r.points[i].x * _canvasW;
      final ay = r.points[i].y * _canvasH;
      if (i == 0) {
        if (_distSq(px, py, ax, ay, ax, ay) <= radius * radius) return true;
        continue;
      }
      final bx = r.points[i - 1].x * _canvasW;
      final by = r.points[i - 1].y * _canvasH;
      if (_distSq(px, py, ax, ay, bx, by) <= radius * radius) return true;
    }
    return false;
  }

  /// Squared distance from point (px, py) to line segment (ax, ay)→(bx, by).
  static double _distSq(
    double px,
    double py,
    double ax,
    double ay,
    double bx,
    double by,
  ) {
    final dx = bx - ax, dy = by - ay;
    if (dx == 0 && dy == 0) {
      final ex = px - ax, ey = py - ay;
      return ex * ex + ey * ey;
    }
    final t = (((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)).clamp(
      0.0,
      1.0,
    );
    final cx = ax + t * dx - px, cy = ay + t * dy - py;
    return cx * cx + cy * cy;
  }

  // ──────────────────────────────────────────────────────────────
  // Save
  // ──────────────────────────────────────────────────────────────

  Future<void> _saveModeration({bool resetToNormal = false}) async {
    if (_isSaving || _images.isEmpty) return;
    final media = _images[_selectedImageIndex];

    if (resetToNormal && !widget.canRestoreCensored) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('只有超级管理员可以恢复未打码原图'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    if (!resetToNormal && _currentRegions.isEmpty) {
      if (!mounted) return;
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

  // ──────────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────────

  void _switchImage(int index) {
    if (index == _selectedImageIndex || _isSaving) return;
    setState(() {
      _selectedImageIndex = index;
      _loadCurrentMediaRegions();
    });
    _loadAndDecodeImage();
    _loadCurrentMediaHistory();
  }

  String _fmtTime(DateTime dt) {
    final l = dt.toLocal();
    return '${l.month.toString().padLeft(2, '0')}-'
        '${l.day.toString().padLeft(2, '0')} '
        '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}';
  }

  // ──────────────────────────────────────────────────────────────
  // Build
  // ──────────────────────────────────────────────────────────────

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

    return Scaffold(
      backgroundColor: const Color(0xFF181A20),
      appBar: _appBar(),
      body: Column(
        children: [
          if (_images.length > 1) _thumbStrip(),
          Expanded(
            child: IgnorePointer(ignoring: _isSaving, child: _editorCanvas()),
          ),
          _versionBar(),
          IgnorePointer(ignoring: _isSaving, child: _toolbar()),
        ],
      ),
    );
  }

  // ── AppBar ──────────────────────────────────────────────────

  PreferredSizeWidget _appBar() {
    return AppBar(
      backgroundColor: const Color(0xFF23262F),
      elevation: 0,
      title: Text(
        '图片打码 ${_selectedImageIndex + 1}/${_images.length}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.bold,
        ),
      ),
      actions: [
        IconButton(
          tooltip: '撤销',
          icon: Icon(
            Icons.undo,
            color: _undoHistory.isNotEmpty && !_isSaving
                ? Colors.white
                : Colors.white38,
          ),
          onPressed: _undoHistory.isNotEmpty && !_isSaving ? _undo : null,
        ),
        IconButton(
          tooltip: '重做',
          icon: Icon(
            Icons.redo,
            color: _redoHistory.isNotEmpty && !_isSaving
                ? Colors.white
                : Colors.white38,
          ),
          onPressed: _redoHistory.isNotEmpty && !_isSaving ? _redo : null,
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          enabled: !_isSaving,
          color: const Color(0xFF2A2E38),
          onSelected: (v) {
            if (v == 'clear') _confirmClearAll();
            if (v == 'restore') _saveModeration(resetToNormal: true);
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'clear',
              enabled: _currentRegions.isNotEmpty,
              child: const Row(
                children: [
                  Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                  SizedBox(width: 8),
                  Text('清除全部打码', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
            if (_images[_selectedImageIndex].isCensored &&
                widget.canRestoreCensored)
              const PopupMenuItem(
                value: 'restore',
                child: Row(
                  children: [
                    Icon(Icons.restore, color: Colors.orangeAccent, size: 20),
                    SizedBox(width: 8),
                    Text('恢复未打码版本', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ── Image Thumbnail Strip ──────────────────────────────────

  Widget _thumbStrip() {
    return Container(
      height: 72,
      color: const Color(0xFF23262F),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _images.length,
        itemBuilder: (_, i) {
          final m = _images[i];
          final sel = i == _selectedImageIndex;
          return GestureDetector(
            onTap: () => _switchImage(i),
            child: Container(
              width: 56,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: sel ? AppTheme.primary : Colors.transparent,
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
    );
  }

  // ── Editor Canvas ──────────────────────────────────────────

  Widget _editorCanvas() {
    if (_decodedImage == null) {
      if (_sourceLoadError != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _sourceLoadError!,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _isSaving ? null : _loadAndDecodeImage,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),
                child: const Text('重试'),
              ),
            ],
          ),
        );
      }
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    final imgW = _decodedImage!.width.toDouble();
    final imgH = _decodedImage!.height.toDouble();
    final aspect = (imgW > 0 && imgH > 0) ? imgW / imgH : 4 / 3;

    return Center(
      child: AspectRatio(
        aspectRatio: aspect,
        child: LayoutBuilder(
          builder: (_, cons) {
            _canvasW = cons.maxWidth;
            _canvasH = cons.maxHeight;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) => _onPanStart(d.localPosition),
              onPanUpdate: (d) => _onPanUpdate(d.localPosition),
              onPanEnd: (_) => _onPanEnd(),
              onPanCancel: _onPanCancel,
              child: RepaintBoundary(
                child: CustomPaint(
                  size: Size(_canvasW, _canvasH),
                  isComplex: true,
                  willChange: true,
                  painter: _EffectPainter(
                    source: _decodedImage!,
                    mosaic: _mosaicImage,
                    regions: _currentRegions,
                    activeStroke: _activeStroke,
                    brushSize: _brushSize,
                    activeType: _currentType,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Version Summary Bar ────────────────────────────────────

  Widget _versionBar() {
    if (!_historyLoading && _moderationHistory.isEmpty) {
      return const SizedBox.shrink();
    }

    String label;
    if (_historyLoading && _moderationHistory.isEmpty) {
      label = '加载中…';
    } else {
      final v = _moderationHistory.first;
      label = v.isInitial
          ? 'v${v.versionNo} · 初发布 · 未打码'
          : v.moderationStatus == 'censored'
          ? 'v${v.versionNo} · 已打码'
          : 'v${v.versionNo} · 已恢复原图';
    }

    return InkWell(
      onTap: _moderationHistory.isNotEmpty ? _showVersionSheet : null,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: const BoxDecoration(
          color: Color(0xFF1F222A),
          border: Border(
            top: BorderSide(color: Color(0xFF353945), width: 0.5),
            bottom: BorderSide(color: Color(0xFF353945), width: 0.5),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.history, color: Colors.white54, size: 18),
            const SizedBox(width: 8),
            const Text(
              '版本',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_moderationHistory.isNotEmpty)
              const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
          ],
        ),
      ),
    );
  }

  void _showVersionSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1F222A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '版本记录',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.45,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                itemCount: _moderationHistory.length,
                itemBuilder: (_, i) => _versionTile(i),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _versionTile(int index) {
    final v = _moderationHistory[index];
    final isLast = index == _moderationHistory.length - 1;
    final statusLabel = v.isInitial
        ? '初发布 · 未打码'
        : v.moderationStatus == 'censored'
        ? '已打码'
        : '已恢复原图';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline dot + connector.
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: v.isInitial ? Colors.transparent : AppTheme.primary,
                    border: Border.all(
                      color: v.isInitial ? Colors.white54 : AppTheme.primary,
                      width: 2,
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(child: Container(width: 1.5, color: Colors.white24)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'v${v.versionNo}  $statusLabel',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _fmtTime(v.createdAt),
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  if (v.reason.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        v.reason,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom Toolbar ─────────────────────────────────────────

  Widget _toolbar() {
    final previewDia = (_brushSize * 100).clamp(6.0, 36.0);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      decoration: const BoxDecoration(
        color: Color(0xFF23262F),
        border: Border(top: BorderSide(color: Color(0xFF353945), width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Effect type
            _labelRow('效果', [
              _chip(
                '马赛克',
                _currentType == 'mosaic',
                () => setState(() => _currentType = 'mosaic'),
              ),
              const SizedBox(width: 8),
              _chip(
                '模糊',
                _currentType == 'blur',
                () => setState(() => _currentType = 'blur'),
              ),
            ]),
            const SizedBox(height: 8),

            // Tool
            _labelRow('工具', [
              _chip(
                '画笔',
                _currentTool == 'brush',
                () => setState(() => _currentTool = 'brush'),
                icon: Icons.brush_outlined,
              ),
              const SizedBox(width: 8),
              _chip(
                '橡皮擦',
                _currentTool == 'eraser',
                () => setState(() => _currentTool = 'eraser'),
                icon: Icons.auto_fix_normal,
              ),
            ]),
            const SizedBox(height: 6),

            // Brush size
            Row(
              children: [
                const SizedBox(
                  width: 48,
                  child: Text(
                    '大小',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7,
                      ),
                    ),
                    child: Slider(
                      value: _brushSize,
                      min: 0.01,
                      max: 0.12,
                      divisions: 22,
                      activeColor: AppTheme.primary,
                      inactiveColor: Colors.white24,
                      onChanged: (v) => setState(() => _brushSize = v),
                    ),
                  ),
                ),
                Container(
                  width: max(previewDia, 6),
                  height: max(previewDia, 6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white54, width: 1.5),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 32,
                  child: Text(
                    '${(_brushSize * 100).round()}%',
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Primary action
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                onPressed: _isSaving ? null : () => _saveModeration(),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        '保存并应用',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Reusable chip helpers ──────────────────────────────────

  Widget _labelRow(String label, List<Widget> children) {
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  Widget _chip(
    String label,
    bool selected,
    VoidCallback onTap, {
    IconData? icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : const Color(0xFF2A2E38),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppTheme.primary : Colors.white24,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 15,
                color: selected ? Colors.white : Colors.white70,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontSize: 13,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// Real Effect Preview Painter
//
// Renders the source image with true mosaic / Gaussian-blur effects
// applied only inside the brush-stroke mask, matching the server's
// `processor.go` semantics (saveLayer + BlendMode.srcIn).
// ──────────────────────────────────────────────────────────────────

class _EffectPainter extends CustomPainter {
  _EffectPainter({
    required this.source,
    this.mosaic,
    required this.regions,
    this.activeStroke,
    required this.brushSize,
    required this.activeType,
  });

  final ui.Image source;
  final ui.Image? mosaic;
  final List<MaskRegion> regions;
  final List<Offset>? activeStroke;
  final double brushSize;
  final String activeType;

  @override
  void paint(Canvas canvas, Size size) {
    final srcW = source.width.toDouble();
    final srcH = source.height.toDouble();
    final srcRect = Rect.fromLTWH(0, 0, srcW, srcH);
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);

    // 1. Draw source image.
    canvas.drawImageRect(source, srcRect, dst, Paint());

    // 2. Committed effect regions.
    for (final r in regions) {
      _paintRegion(canvas, size, r, srcRect, dst);
    }

    // 3. Active stroke real-time preview.
    _paintActiveStroke(canvas, size, srcRect, dst);
  }

  // ── Per-region rendering ──────────────────────────────────

  void _paintRegion(
    Canvas canvas,
    Size size,
    MaskRegion r,
    Rect srcRect,
    Rect dst,
  ) {
    if (r.points.isEmpty) {
      _paintRectRegion(canvas, size, r, srcRect, dst);
      return;
    }

    final path = _smoothPath(r.points, size);
    final bpx = _brushPx(r.brushSize, size);

    canvas.saveLayer(dst, Paint());
    _strokeMask(canvas, path, bpx);
    if (r.points.length == 1) {
      _dotMask(canvas, r.points.first, size, bpx);
    }
    _compositeEffect(canvas, r.type, srcRect, dst, r.brushSize, size);
    canvas.restore();
  }

  /// Backwards-compatible handling for legacy rectangle-based regions.
  void _paintRectRegion(
    Canvas canvas,
    Size size,
    MaskRegion r,
    Rect srcRect,
    Rect dst,
  ) {
    final rect = Rect.fromLTWH(
      r.x * size.width,
      r.y * size.height,
      r.width * size.width,
      r.height * size.height,
    );

    if (r.type == 'blur') {
      final sigma = _sigma(0.04, size);
      canvas.saveLayer(
        rect,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      );
      canvas.drawImageRect(source, srcRect, dst, Paint());
      canvas.restore();
    } else if (mosaic != null) {
      canvas.save();
      canvas.clipRect(rect);
      canvas.drawImageRect(
        mosaic!,
        Rect.fromLTWH(
          0,
          0,
          mosaic!.width.toDouble(),
          mosaic!.height.toDouble(),
        ),
        dst,
        Paint(),
      );
      canvas.restore();
    }
  }

  // ── Active stroke rendering ───────────────────────────────

  void _paintActiveStroke(Canvas canvas, Size size, Rect srcRect, Rect dst) {
    final pts = activeStroke;
    if (pts == null || pts.isEmpty) return;

    final maskPts = pts
        .map(
          (p) => MaskPoint(
            x: (p.dx / size.width).clamp(0.0, 1.0),
            y: (p.dy / size.height).clamp(0.0, 1.0),
          ),
        )
        .toList();
    final path = _smoothPath(maskPts, size);
    final bpx = _brushPx(brushSize, size);

    // Real effect preview.
    canvas.saveLayer(dst, Paint());
    _strokeMask(canvas, path, bpx);
    if (maskPts.length == 1) {
      _dotMask(canvas, maskPts.first, size, bpx);
    }
    _compositeEffect(canvas, activeType, srcRect, dst, brushSize, size);
    canvas.restore();

    // Faint guide line so the user can see the exact path.
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0x40FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  // ── Shared compositing helpers ────────────────────────────

  /// Draws the white-stroke mask that defines the effect coverage area.
  void _strokeMask(Canvas canvas, Path path, double bpx) {
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = bpx
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  /// Fills a single-point dot mask.
  void _dotMask(Canvas canvas, MaskPoint pt, Size size, double bpx) {
    canvas.drawCircle(
      Offset(pt.x * size.width, pt.y * size.height),
      bpx / 2,
      Paint()..color = const Color(0xFFFFFFFF),
    );
  }

  /// Draws the effect image (blur or mosaic) through the previously drawn
  /// mask using [BlendMode.srcIn].
  void _compositeEffect(
    Canvas canvas,
    String type,
    Rect srcRect,
    Rect dst,
    double bSize,
    Size canvasSize,
  ) {
    if (type == 'blur') {
      final s = _sigma(bSize, canvasSize);
      canvas.drawImageRect(
        source,
        srcRect,
        dst,
        Paint()
          ..blendMode = BlendMode.srcIn
          ..imageFilter = ui.ImageFilter.blur(sigmaX: s, sigmaY: s),
      );
    } else if (mosaic != null) {
      canvas.drawImageRect(
        mosaic!,
        Rect.fromLTWH(
          0,
          0,
          mosaic!.width.toDouble(),
          mosaic!.height.toDouble(),
        ),
        dst,
        Paint()..blendMode = BlendMode.srcIn,
      );
    } else {
      // Fallback while mosaic image is still generating.
      canvas.drawRect(
        dst,
        Paint()
          ..blendMode = BlendMode.srcIn
          ..color = const Color(0xCC808080),
      );
    }
  }

  // ── Path & metric helpers ─────────────────────────────────

  /// Builds a smooth centre-line path using midpoint quadratic Bézier curves.
  Path _smoothPath(List<MaskPoint> pts, Size s) {
    final path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(pts.first.x * s.width, pts.first.y * s.height);
    if (pts.length < 3) {
      for (final p in pts.skip(1)) {
        path.lineTo(p.x * s.width, p.y * s.height);
      }
      return path;
    }
    for (var i = 1; i < pts.length - 1; i++) {
      final cx = pts[i].x * s.width, cy = pts[i].y * s.height;
      final nx = pts[i + 1].x * s.width, ny = pts[i + 1].y * s.height;
      path.quadraticBezierTo(cx, cy, (cx + nx) / 2, (cy + ny) / 2);
    }
    path.lineTo(pts.last.x * s.width, pts.last.y * s.height);
    return path;
  }

  double _brushPx(double norm, Size s) {
    final se = s.width < s.height ? s.width : s.height;
    return (norm.clamp(0.01, 0.25) * se).clamp(4.0, se * 0.8);
  }

  /// Converts the server's box-blur kernel into an approximate Gaussian sigma
  /// in canvas-pixel space.
  double _sigma(double bSize, Size s) {
    final se = min(s.width, s.height);
    final radiusPx = max(4.0, bSize * se / 2);
    return max(4.0, radiusPx * 0.75);
  }

  @override
  bool shouldRepaint(covariant _EffectPainter old) => true;
}
