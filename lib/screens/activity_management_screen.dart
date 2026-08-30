import 'package:flutter/material.dart';

import '../data/api/api_client.dart';
import '../data/api/platform_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/app_network_image.dart';

class ActivityManagementScreen extends StatefulWidget {
  const ActivityManagementScreen({
    super.key,
    required this.repository,
    required this.onFeedback,
  });

  final PlatformRepository repository;
  final ValueChanged<String> onFeedback;

  @override
  State<ActivityManagementScreen> createState() => _ActivityManagementScreenState();
}

class _ActivityManagementScreenState extends State<ActivityManagementScreen> {
  String _selectedStatus = 'all';
  late Future<List<ActivityItem>> _future;

  final List<(String key, String label)> _statusFilters = const [
    ('all', '全部'),
    ('active', '进行中'),
    ('upcoming', '未开始'),
    ('draft', '草稿'),
    ('ended', '已结束'),
    ('offline', '已下架'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _future = widget.repository.listAdminActivities(
        status: _selectedStatus == 'all' ? null : _selectedStatus,
      );
    });
  }

  Future<void> _openEditor([ActivityItem? item]) async {
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ActivityEditorSheet(
        repository: widget.repository,
        initialItem: item,
      ),
    );

    if (updated == true && mounted) {
      widget.onFeedback(item == null ? '活动已创建' : '活动已更新');
      _load();
    }
  }

  Future<void> _publishActivity(ActivityItem item) async {
    try {
      await widget.repository.publishAdminActivity(item.id);
      if (!mounted) return;
      widget.onFeedback('活动已发布');
      _load();
    } catch (error) {
      if (mounted) {
        widget.onFeedback(userFacingApiMessage(error, fallback: '发布失败'));
      }
    }
  }

  Future<void> _offlineActivity(ActivityItem item) async {
    try {
      await widget.repository.offlineAdminActivity(item.id);
      if (!mounted) return;
      widget.onFeedback('活动已下架');
      _load();
    } catch (error) {
      if (mounted) {
        widget.onFeedback(userFacingApiMessage(error, fallback: '下架失败'));
      }
    }
  }

  Future<void> _deleteActivity(ActivityItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除活动'),
        content: Text('确定要删除活动「${item.title}」吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.pink),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await widget.repository.deleteAdminActivity(item.id);
        if (!mounted) return;
        widget.onFeedback('活动已删除');
        _load();
      } catch (error) {
        if (mounted) {
          widget.onFeedback(userFacingApiMessage(error, fallback: '删除失败'));
        }
      }
    }
  }

  Color _statusColor(String status) => switch (status) {
    'active' => AppTheme.primary,
    'upcoming' => AppTheme.orange,
    'draft' => AppTheme.textSecondary,
    'ended' => Colors.blueGrey,
    'offline' => AppTheme.pink,
    _ => AppTheme.textSecondary,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('活动管理', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add_rounded),
            tooltip: '新建活动',
          ),
        ],
      ),
      body: Column(
        children: [
          // 状态筛选 Tab
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: _statusFilters.map((filter) {
                final isSelected = _selectedStatus == filter.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(filter.$2),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedStatus = filter.$1;
                          _load();
                        });
                      }
                    },
                    selectedColor: AppTheme.surfaceBlue,
                    checkmarkColor: AppTheme.primary,
                    labelStyle: TextStyle(
                      color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.normal,
                      fontSize: 13,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),
          // 活动列表
          Expanded(
            child: FutureBuilder<List<ActivityItem>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          userFacingApiMessage(snapshot.error ?? Object(), fallback: '活动列表加载失败'),
                          style: const TextStyle(color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _load,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  );
                }

                final items = snapshot.data ?? [];
                if (items.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.event_busy_outlined, size: 54, color: AppTheme.textSecondary),
                        const SizedBox(height: 12),
                        const Text('暂无活动数据', style: TextStyle(color: AppTheme.textSecondary)),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => _openEditor(),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('新建第一个活动'),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async => _load(),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _ActivityCard(
                        item: item,
                        statusColor: _statusColor(item.status),
                        onEdit: () => _openEditor(item),
                        onPublish: () => _publishActivity(item),
                        onOffline: () => _offlineActivity(item),
                        onDelete: () => _deleteActivity(item),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('新建活动'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.item,
    required this.statusColor,
    required this.onEdit,
    required this.onPublish,
    required this.onOffline,
    required this.onDelete,
  });

  final ActivityItem item;
  final Color statusColor;
  final VoidCallback onEdit;
  final VoidCallback onPublish;
  final VoidCallback onOffline;
  final VoidCallback onDelete;

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return '未设置';
    final local = dt.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.coverUrl != null && item.coverUrl!.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  height: 120,
                  width: double.infinity,
                  child: AppNetworkImage(
                    url: item.coverUrl!,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    item.statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (item.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                item.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.access_time_rounded, size: 14, color: AppTheme.textSecondary),
                const SizedBox(width: 4),
                Text(
                  '${_formatDateTime(item.startAt)} ~ ${_formatDateTime(item.endAt)}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
            if (item.location.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 14, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      item.location,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('编辑'),
                ),
                if (item.status == 'draft' || item.status == 'offline')
                  TextButton.icon(
                    onPressed: onPublish,
                    icon: const Icon(Icons.cloud_upload_outlined, size: 16),
                    label: const Text('发布'),
                  ),
                if (item.status == 'active' || item.status == 'upcoming')
                  TextButton.icon(
                    onPressed: onOffline,
                    icon: const Icon(Icons.cloud_off_outlined, size: 16),
                    label: const Text('下架'),
                  ),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.pink),
                  tooltip: '删除活动',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityEditorSheet extends StatefulWidget {
  const _ActivityEditorSheet({
    required this.repository,
    this.initialItem,
  });

  final PlatformRepository repository;
  final ActivityItem? initialItem;

  @override
  State<_ActivityEditorSheet> createState() => _ActivityEditorSheetState();
}

class _ActivityEditorSheetState extends State<_ActivityEditorSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _descController;
  late final TextEditingController _coverUrlController;
  late final TextEditingController _locationController;

  DateTime? _startAt;
  DateTime? _endAt;
  String _status = 'draft';
  bool _submitting = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;
    _titleController = TextEditingController(text: item?.title ?? '');
    _descController = TextEditingController(text: item?.description ?? '');
    _coverUrlController = TextEditingController(text: item?.coverUrl ?? '');
    _locationController = TextEditingController(text: item?.location ?? '');
    _startAt = item?.startAt;
    _endAt = item?.endAt;
    _status = item?.status ?? 'draft';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _coverUrlController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime(bool isStart) async {
    final now = DateTime.now();
    final initialDate = (isStart ? _startAt : _endAt) ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
    );
    if (time == null || !mounted) return;

    final combined = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _startAt = combined;
      } else {
        _endAt = combined;
      }
    });
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _errorText = '请输入活动标题');
      return;
    }

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      if (widget.initialItem == null) {
        await widget.repository.createAdminActivity(
          title: title,
          description: _descController.text.trim(),
          coverUrl: _coverUrlController.text.trim(),
          startAt: _startAt,
          endAt: _endAt,
          location: _locationController.text.trim(),
          status: _status,
        );
      } else {
        await widget.repository.updateAdminActivity(
          id: widget.initialItem!.id,
          title: title,
          description: _descController.text.trim(),
          coverUrl: _coverUrlController.text.trim(),
          startAt: _startAt,
          endAt: _endAt,
          location: _locationController.text.trim(),
          status: _status,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _errorText = userFacingApiMessage(error, fallback: '保存失败，请重试');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isEditing = widget.initialItem != null;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      child: ListView(
        shrinkWrap: true,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isEditing ? '编辑活动' : '新建活动',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_errorText != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_errorText!, style: const TextStyle(color: AppTheme.pink, fontSize: 13)),
            ),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: '活动标题 *',
              hintText: '输入清晰响亮的活动标题',
            ),
            maxLength: 50,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descController,
            decoration: const InputDecoration(
              labelText: '活动描述',
              hintText: '详细介绍活动规则、参与方式、奖励内容等',
            ),
            maxLines: 4,
            maxLength: 1000,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _coverUrlController,
            decoration: const InputDecoration(
              labelText: '封面图链接（可选）',
              hintText: 'https://...',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _locationController,
            decoration: const InputDecoration(
              labelText: '活动地点 / 线上入口（可选）',
              hintText: '例如：线上活动 / 学生活动中心',
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDateTime(true),
                  icon: const Icon(Icons.calendar_today_outlined, size: 16),
                  label: Text(
                    _startAt == null
                        ? '设置开始时间'
                        : '开始: ${_startAt!.month}/${_startAt!.day} ${_startAt!.hour}:${_startAt!.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDateTime(false),
                  icon: const Icon(Icons.event_available_outlined, size: 16),
                  label: Text(
                    _endAt == null
                        ? '设置结束时间'
                        : '结束: ${_endAt!.month}/${_endAt!.day} ${_endAt!.hour}:${_endAt!.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: '活动状态'),
            items: const [
              DropdownMenuItem(value: 'draft', child: Text('草稿')),
              DropdownMenuItem(value: 'upcoming', child: Text('未开始')),
              DropdownMenuItem(value: 'active', child: Text('进行中')),
              DropdownMenuItem(value: 'ended', child: Text('已结束')),
              DropdownMenuItem(value: 'offline', child: Text('已下架')),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _status = val);
            },
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _submitting ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              minimumSize: const Size.fromHeight(48),
            ),
            child: Text(_submitting ? '保存中…' : '保存活动'),
          ),
        ],
      ),
    );
  }
}
