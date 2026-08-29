import 'package:flutter/material.dart';

import '../data/api/api_client.dart';
import '../data/api/platform_repository.dart';
import '../theme/app_theme.dart';
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
      if (note == null) return;
    }
    setState(() => processing = true);
    try {
      await widget.platformRepository.reviewRankingSubmission(
        id: item.id,
        approve: approve,
        note: note,
      );
      if (!mounted) return;
      _feedback(approve ? '已通过，玩具已进入综合热榜' : '已驳回该投稿');
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
          return AlertDialog(
            title: Text('驳回「${item.name}」'),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              maxLength: 200,
              decoration: const InputDecoration(hintText: '填写驳回原因（可留空）'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, null),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(dialogContext, controller.text.trim()),
                child: const Text('驳回'),
              ),
            ],
          );
        },
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('玩具提交审核')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Wrap(
            spacing: 8,
            children: [
              for (final option in const [
                ('pending', '待审核'),
                ('approved', '已通过'),
                ('rejected', '已驳回'),
              ])
                ChoiceChip(
                  label: Text(option.$2),
                  selected: status == option.$1,
                  onSelected: processing
                      ? null
                      : (selected) {
                          if (!selected || status == option.$1) return;
                          setState(() => status = option.$1);
                          _load();
                        },
                ),
            ],
          ),
        ),
        Expanded(child: _body()),
      ],
    ),
  );

  Widget _body() {
    if (loading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && items.isEmpty) {
      return Center(
        child: TextButton(onPressed: _load, child: const Text('加载失败，重试')),
      );
    }
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: const [
            SizedBox(height: 180),
            Center(
              child: Text(
                '暂无投稿',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return Card(
            key: ValueKey(item.id),
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
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
                              : Image.network(
                                  item.coverUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const ColoredBox(
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
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '提交者：${item.submitterNickname} · ${_dateLabel(item.createdAt)}',
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
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
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceBlue,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              tag,
                              style: const TextStyle(fontSize: 11),
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
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ],
                  if (item.status == 'pending' &&
                      item.reviewNote.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '备注：${item.reviewNote}',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (item.status == 'pending') ...[
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: processing
                              ? null
                              : () => _review(item, false),
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
            ),
          );
        },
      ),
    );
  }

  String _dateLabel(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
