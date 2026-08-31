import 'package:flutter/material.dart';
import '../data/api/platform_repository.dart';
import '../domain/models.dart';
import '../theme/app_theme.dart';

/// 管理员图片打码处理页面。
/// 支持多区域框选、马赛克/模糊效果切换、撤销、清除打码与服务端同步保存。
class ImageModerationScreen extends StatefulWidget {
  const ImageModerationScreen({
    super.key,
    required this.post,
    this.initialMediaIndex = 0,
    this.platformRepository,
    this.onSaved,
  });

  final Post post;
  final int initialMediaIndex;
  final PlatformRepository? platformRepository;
  final VoidCallback? onSaved;

  @override
  State<ImageModerationScreen> createState() => _ImageModerationScreenState();
}

class _ImageModerationScreenState extends State<ImageModerationScreen> {
  late int _selectedMediaIndex;
  late List<MaskRegion> _currentRegions;
  final List<List<MaskRegion>> _undoHistory = [];
  String _currentType = 'mosaic'; // 'mosaic' or 'blur'
  int? _selectedRegionIndex;
  Offset? _dragStart;
  Offset? _dragCurrent;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedMediaIndex = widget.initialMediaIndex.clamp(0, widget.post.media.isEmpty ? 0 : widget.post.media.length - 1);
    _loadCurrentMediaRegions();
  }

  void _loadCurrentMediaRegions() {
    if (widget.post.media.isNotEmpty) {
      final media = widget.post.media[_selectedMediaIndex];
      _currentRegions = List<MaskRegion>.from(media.maskRegions);
    } else {
      _currentRegions = [];
    }
    _undoHistory.clear();
    _selectedRegionIndex = null;
    _dragStart = null;
    _dragCurrent = null;
  }

  void _pushHistory() {
    _undoHistory.add(List<MaskRegion>.from(_currentRegions));
  }

  void _undo() {
    if (_undoHistory.isNotEmpty) {
      setState(() {
        _currentRegions = _undoHistory.removeLast();
        _selectedRegionIndex = null;
      });
    }
  }

  void _clearAll() {
    _pushHistory();
    setState(() {
      _currentRegions.clear();
      _selectedRegionIndex = null;
    });
  }

  Future<void> _saveModeration({bool resetToNormal = false}) async {
    if (widget.post.media.isEmpty) return;
    final media = widget.post.media[_selectedMediaIndex];

    setState(() => _isSaving = true);
    try {
      final status = (resetToNormal || _currentRegions.isEmpty) ? 'normal' : 'censored';
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
          content: Text(status == 'censored' ? '打码处理已保存，服务端已生成打码图变体' : '已恢复原图正常展示'),
          backgroundColor: AppTheme.primary,
        ),
      );
      widget.onSaved?.call();
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('保存出错: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.post.media.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('图片处理')),
        body: const Center(child: Text('该帖子没有图片')),
      );
    }

    final currentMedia = widget.post.media[_selectedMediaIndex];
    final imageUrl = currentMedia.originalUrl ?? currentMedia.detailUrl ?? currentMedia.url ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF181A20),
      appBar: AppBar(
        backgroundColor: const Color(0xFF23262F),
        elevation: 0,
        title: Text(
          '图片处理 (${_selectedMediaIndex + 1}/${widget.post.media.length})',
          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: '撤销上一步',
            icon: Icon(Icons.undo, color: _undoHistory.isNotEmpty ? Colors.white : Colors.white38),
            onPressed: _undoHistory.isNotEmpty ? _undo : null,
          ),
          IconButton(
            tooltip: '清空打码',
            icon: Icon(Icons.delete_outline, color: _currentRegions.isNotEmpty ? Colors.redAccent : Colors.white38),
            onPressed: _currentRegions.isNotEmpty ? _clearAll : null,
          ),
          TextButton(
            onPressed: _isSaving ? null : () => _saveModeration(),
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('保存打码', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // 顶部图片选择栏（如果多张图）
          if (widget.post.media.length > 1)
            Container(
              height: 72,
              color: const Color(0xFF23262F),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: widget.post.media.length,
                itemBuilder: (context, index) {
                  final m = widget.post.media[index];
                  final isSelected = index == _selectedMediaIndex;
                  return GestureDetector(
                    onTap: () {
                      if (index != _selectedMediaIndex) {
                        setState(() {
                          _selectedMediaIndex = index;
                          _loadCurrentMediaRegions();
                        });
                      }
                    },
                    child: Container(
                      width: 56,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isSelected ? AppTheme.primary : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.network(
                        m.thumbUrl ?? m.url ?? '',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey[800],
                          child: const Icon(Icons.image, color: Colors.white54),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

          // 打码画布区域
          Expanded(
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final imgW = currentMedia.width?.toDouble() ?? 800;
                  final imgH = currentMedia.height?.toDouble() ?? 600;
                  final aspect = (imgW > 0 && imgH > 0) ? imgW / imgH : 4 / 3;

                  return AspectRatio(
                    aspectRatio: aspect,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // 底层图片
                        Image.network(
                          imageUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.black26,
                            child: const Center(
                              child: Text('图片加载中或无法访问', style: TextStyle(color: Colors.white70)),
                            ),
                          ),
                        ),

                        // 手势框选层
                        GestureDetector(
                          onPanStart: (details) {
                            setState(() {
                              _dragStart = details.localPosition;
                              _dragCurrent = details.localPosition;
                              _selectedRegionIndex = null;
                            });
                          },
                          onPanUpdate: (details) {
                            setState(() {
                              _dragCurrent = details.localPosition;
                            });
                          },
                          onPanEnd: (details) {
                            if (_dragStart != null && _dragCurrent != null) {
                              final renderBox = context.findRenderObject() as RenderBox?;
                              if (renderBox != null) {
                                final size = renderBox.size;
                                final left = (_dragStart!.dx < _dragCurrent!.dx ? _dragStart!.dx : _dragCurrent!.dx).clamp(0.0, size.width);
                                final top = (_dragStart!.dy < _dragCurrent!.dy ? _dragStart!.dy : _dragCurrent!.dy).clamp(0.0, size.height);
                                final right = (_dragStart!.dx > _dragCurrent!.dx ? _dragStart!.dx : _dragCurrent!.dx).clamp(0.0, size.width);
                                final bottom = (_dragStart!.dy > _dragCurrent!.dy ? _dragStart!.dy : _dragCurrent!.dy).clamp(0.0, size.height);

                                final boxW = right - left;
                                final boxH = bottom - top;

                                // 最小阈值过滤误触
                                if (boxW > 10 && boxH > 10 && size.width > 0 && size.height > 0) {
                                  _pushHistory();
                                  _currentRegions.add(
                                    MaskRegion(
                                      x: (left / size.width).clamp(0.0, 1.0),
                                      y: (top / size.height).clamp(0.0, 1.0),
                                      width: (boxW / size.width).clamp(0.0, 1.0),
                                      height: (boxH / size.height).clamp(0.0, 1.0),
                                      type: _currentType,
                                    ),
                                  );
                                }
                              }
                            }
                            setState(() {
                              _dragStart = null;
                              _dragCurrent = null;
                            });
                          },
                          child: CustomPaint(
                            painter: _MaskCanvasPainter(
                              regions: _currentRegions,
                              dragStart: _dragStart,
                              dragCurrent: _dragCurrent,
                              currentType: _currentType,
                              selectedIndex: _selectedRegionIndex,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),

          // 底部控制面板
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF23262F),
              border: Border(top: BorderSide(color: Color(0xFF353945), width: 1)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  const Text('遮挡样式：', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('马赛克'),
                    selected: _currentType == 'mosaic',
                    selectedColor: AppTheme.primary,
                    onSelected: (val) {
                      if (val) setState(() => _currentType = 'mosaic');
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('毛玻璃模糊'),
                    selected: _currentType == 'blur',
                    selectedColor: AppTheme.primary,
                    onSelected: (val) {
                      if (val) setState(() => _currentType = 'blur');
                    },
                  ),
                  const Spacer(),
                  if (currentMedia.isCensored)
                    TextButton.icon(
                      icon: const Icon(Icons.refresh, color: Colors.orangeAccent, size: 18),
                      label: const Text('恢复原图', style: TextStyle(color: Colors.orangeAccent)),
                      onPressed: () => _saveModeration(resetToNormal: true),
                    ),
                ],
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
    this.dragStart,
    this.dragCurrent,
    required this.currentType,
    this.selectedIndex,
  });

  final List<MaskRegion> regions;
  final Offset? dragStart;
  final Offset? dragCurrent;
  final String currentType;
  final int? selectedIndex;

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

    // 绘制已保存/已添加的区域
    for (int i = 0; i < regions.length; i++) {
      final r = regions[i];
      final rect = Rect.fromLTWH(
        r.x * size.width,
        r.y * size.height,
        r.width * size.width,
        r.height * size.height,
      );

      // 遮罩底色
      canvas.drawRect(rect, r.type == 'blur' ? blurPaint : mosaicPaint);

      // 绘制马赛克方格示意网格
      if (r.type == 'mosaic') {
        const double step = 12.0;
        for (double x = rect.left; x < rect.right; x += step) {
          canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), gridPaint);
        }
        for (double y = rect.top; y < rect.bottom; y += step) {
          canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), gridPaint);
        }
      }

      // 边框
      canvas.drawRect(rect, borderPaint);

      // 标签文字
      final textPainter = TextPainter(
        text: TextSpan(
          text: r.type == 'blur' ? '模糊 #${i + 1}' : '马赛克 #${i + 1}',
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(rect.left + 4, rect.top + 4));
    }

    // 绘制当前拖拽中的新选框
    if (dragStart != null && dragCurrent != null) {
      final left = (dragStart!.dx < dragCurrent!.dx ? dragStart!.dx : dragCurrent!.dx).clamp(0.0, size.width);
      final top = (dragStart!.dy < dragCurrent!.dy ? dragStart!.dy : dragCurrent!.dy).clamp(0.0, size.height);
      final right = (dragStart!.dx > dragCurrent!.dx ? dragStart!.dx : dragCurrent!.dx).clamp(0.0, size.width);
      final bottom = (dragStart!.dy > dragCurrent!.dy ? dragStart!.dy : dragCurrent!.dy).clamp(0.0, size.height);
      final dragRect = Rect.fromLTRB(left, top, right, bottom);

      final dragFill = Paint()
        ..color = currentType == 'blur' ? const Color(0x77FFFFFF) : const Color(0x77000000)
        ..style = PaintingStyle.fill;

      final dragBorder = Paint()
        ..color = Colors.amberAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawRect(dragRect, dragFill);
      canvas.drawRect(dragRect, dragBorder);
    }
  }

  @override
  bool shouldRepaint(covariant _MaskCanvasPainter oldDelegate) => true;
}
