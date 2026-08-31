import 'package:flutter/material.dart';

import '../data/api/api_client.dart';
import '../data/api/platform_repository.dart';
import '../theme/app_theme.dart';
import '../theme/app_motion.dart';
import '../widgets/app_network_image.dart';
import 'ranking_toy_submission_screen.dart';

class RankingSubmissionReviewScreen extends StatefulWidget {
  const RankingSubmissionReviewScreen({
    super.key,
    required this.platformRepository,
    this.onFeedback,
  });

  final PlatformRepository platformRepository;
  final ValueChanged<String>? onFeedback;

  @override
  State<RankingSubmissionReviewScreen> createState() =>
      _RankingSubmissionReviewScreenState();
}

class _RankingSubmissionReviewScreenState
    extends State<RankingSubmissionReviewScreen> {
  String status = 'pending';
  List<RankingToySubmission> items = const [];
  Object? error;
  bool loading = true;
  bool processing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _feedback(String message) => widget.onFeedback?.call(message);

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final loaded = await widget.platformRepository.listRankingSubmissions(
        status: status,
      );
      if (!mounted) return;
      setState(() {
        items = loaded;
        loading = false;
      });
    } catch (cause) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = cause;
      });
    }
  }

  Future<void> _review(RankingToySubmission item, bool approve) async {
    if (processing) return;
    String? note;
    if (!approve) {
      note = await _askRejectNote(item);
      if (note == null || note.trim().isEmpty) return;
    }
    setState(() => processing = true);
    try {
      await widget.platformRepository.reviewRankingSubmission(
        id: item.id,
        approve: approve,
        note: note,
      );
      if (!mounted) return;
      _feedback(approve ? '已审核通过，玩具已录入综合热榜' : '已驳回该玩具投稿');
      await _load();
    } catch (cause) {
      if (!mounted) return;
      if (cause is ApiException && cause.type == ApiErrorType.conflict) {
        _feedback('该提交已被处理');
        await _load();
      } else {
        _feedback('操作失败，请稍后重试');
      }
    } finally {
      if (mounted) setState(() => processing = false);
    }
  }

  Future<String?> _askRejectNote(RankingToySubmission item) =>
      showDialog<String>(
        context: context,
        builder: (dialogContext) {
          final controller = TextEditingController();
          String? validationError;
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text('驳回投稿「${item.name}」', style: const TextStyle(fontWeight: FontWeight.w800)),
              content: TextField(
                controller: controller,
                autofocus: true,
                maxLines: 3,
                maxLength: 200,
                decoration: InputDecoration(
                  labelText: '驳回原因（必填）',
                  hintText: '请详细说明不符合规范的原因',
                  errorText: validationError,
                ),
                onChanged: (_) {
                  if (validationError != null) {
                    setDialogState(() => validationError = null);
                  }
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, null),
                  child: const Text('取消'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.pink),
                  onPressed: () {
                    final text = controller.text.trim();
                    if (text.isEmpty) {
                      setDialogState(() => validationError = '请填写驳回原因');
                      return;
                    }
                    Navigator.pop(dialogContext, text);
                  },
                  child: const Text('驳回'),
                ),
              ],
            ),
          );
        },
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.background,
    appBar: AppBar(
      title: const Text(
        '玩具提交审核',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
      ),
      backgroundColor: AppTheme.background,
      elevation: 0,
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
          child: Row(
            children: [
              for (final option in const [
                ('pending', '待审核'),
                ('approved', '已通过'),
                ('rejected', '已驳回'),
              ]) ...[
                _buildStatusChip(option.$2, option.$1),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        Expanded(child: _body()),
      ],
    ),
  );

  Widget _buildStatusChip(String label, String value) {
    final isSelected = status == value;
    return GestureDetector(
      onTap: processing
          ? null
          : () {
              if (status == value) return;
              setState(() => status = value);
              _load();
            },
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6.5),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.softBlue : Colors.white,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: isSelected ? const Color(0xFFD7E6FF) : const Color(0xFFD4DFE9),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? const Color(0xFF3E78CC) : const Color(0xFF6B8197),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (loading && items.isEmpty) {
      return ListView.separated(
        padding: const EdgeInsets.all(14),
        itemCount: 3,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, _) => Container(
          height: 110,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border),
          ),
        ),
      );
    }
    if (error != null && items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 36, color: AppTheme.textSecondary),
            const SizedBox(height: 10),
            const Text('加载投稿列表失败', style: TextStyle(color: AppTheme.pink, fontSize: 13)),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: _load, child: const Text('重新加载')),
          ],
        ),
      );
    }
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 100),
            Center(
              child: Column(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F1FA),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.toys_outlined, size: 28, color: Color(0xFF6B8299)),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '暂无投稿数据',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF304A65)),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '当前分类下没有需要审核的投稿',
                    style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 32),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = items[index];
          return Container(
            key: ValueKey(item.id),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
              boxShadow: const [AppTheme.cardShadow],
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 64,
                        height: 64,
                        child: item.coverUrl == null
                            ? const ColoredBox(
                                color: AppTheme.surfaceBlue,
                                child: Icon(
                                  Icons.toys_outlined,
                                  color: AppTheme.textSecondary,
                                ),
                              )
                            : AppNetworkImage(
                                url: item.coverUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_) => const ColoredBox(
                                  color: AppTheme.surfaceBlue,
                                  child: Icon(
                                    Icons.toys_outlined,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            [
                              rankingToyCategoryLabel(item.category),
                              if (item.intensity.isNotEmpty)
                                rankingToyIntensityLabel(item.intensity),
                              if (item.merchant.isNotEmpty) item.merchant,
                              if (item.releaseYear != null)
                                '${item.releaseYear}',
                            ].join(' · '),
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '提交者：${item.submitterNickname} · ${_dateLabel(item.createdAt)}',
                            style: const TextStyle(
                              color: Color(0xFF8B9FB3),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (item.tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tag in item.tags)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.softBlue,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            tag,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.primary),
                          ),
                        ),
                    ],
                  ),
                ],
                if (item.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    item.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppTheme.textSecondary),
                  ),
                ],
                if (item.status == 'pending' &&
                    item.reviewNote.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '备注：${item.reviewNote}',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ],
                if (item.status == 'pending') ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1, color: Color(0xFFEDF2F7)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: processing
                            ? null
                            : () => _review(item, false),
                        style: TextButton.styleFrom(foregroundColor: AppTheme.pink),
                        child: const Text('驳回'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: processing
                            ? null
                            : () => _review(item, true),
                        child: const Text('通过'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  String _dateLabel(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
