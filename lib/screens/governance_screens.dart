import 'package:flutter/material.dart';

import '../data/api/platform_repository.dart';
import '../theme/app_theme.dart';

class AccountStatusScreen extends StatefulWidget {
  const AccountStatusScreen({
    super.key,
    required this.repository,
    this.onOpenAction,
  });
  final PlatformRepository repository;
  final ValueChanged<String>? onOpenAction;
  @override
  State<AccountStatusScreen> createState() => _AccountStatusScreenState();
}

class _AccountStatusScreenState extends State<AccountStatusScreen> {
  late Future<AccountStatusData> future;
  @override
  void initState() {
    super.initState();
    future = widget.repository.getAccountStatus();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('账号状态')),
    body: FutureBuilder<AccountStatusData>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () =>
                  setState(() => future = widget.repository.getAccountStatus()),
              child: const Text('加载失败，重试'),
            ),
          );
        }
        final data = snapshot.data!;
        final active = data.status == 'active';
        return RefreshIndicator(
          onRefresh: () async =>
              setState(() => future = widget.repository.getAccountStatus()),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: active
                            ? const Color(0xFFE7F8EE)
                            : const Color(0xFFFFE9E9),
                        child: Icon(
                          active
                              ? Icons.check_rounded
                              : Icons.warning_amber_rounded,
                          color: active ? Colors.green : Colors.red,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data.username,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              active
                                  ? '账号正常'
                                  : '账号${_statusLabel(data.status)}',
                              style: TextStyle(
                                color: active ? Colors.green : Colors.red,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Chip(
                        label: Text(
                          data.accountType == 'guest' ? '游客身份' : '正式账号',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.mail_outline),
                  title: Text(data.email.isEmpty ? '未绑定邮箱' : data.email),
                  subtitle: Text(data.emailVerified ? '邮箱已验证' : '邮箱未验证'),
                  trailing: Icon(
                    data.emailVerified ? Icons.verified : Icons.error_outline,
                    color: data.emailVerified ? Colors.green : Colors.orange,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '处罚与限制记录',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
              ),
              const SizedBox(height: 8),
              if (data.punishments.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text(
                      '暂无处罚记录',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ),
                )
              else
                ...data.punishments.map(
                  (item) => Card(
                    child: ListTile(
                      leading: Icon(
                        _iconForPunishment(item.type),
                        color: Colors.orange,
                      ),
                      title: Text(_punishmentTitle(item)),
                      subtitle: Text(
                        '${item.reason}\n${_dateLabel(item.startsAt)}${item.endsAt == null ? '' : ' — ${_dateLabel(item.endsAt!)}'}',
                      ),
                      isThreeLine: true,
                      trailing: item.appealable && widget.onOpenAction != null
                          ? TextButton(
                              onPressed: () => widget.onOpenAction!(item.id),
                              child: const Text('申诉'),
                            )
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
  String _statusLabel(String value) => switch (value) {
    'suspended' => '受限',
    'deleted' => '已注销',
    _ => '异常',
  };
  String _punishmentTitle(AccountPunishment item) => item.type == 'moderation'
      ? '内容处罚：${item.action}'
      : item.type == 'ban'
      ? '账号封禁'
      : '账号限制：${item.type}';
  IconData _iconForPunishment(String type) => type == 'ban'
      ? Icons.block_outlined
      : type == 'moderation'
      ? Icons.gavel_outlined
      : Icons.timer_outlined;
  String _dateLabel(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

class AdminListScreen extends StatefulWidget {
  const AdminListScreen({
    super.key,
    required this.repository,
    required this.onOpenAdmin,
    required this.onOpenRisk,
  });
  final PlatformRepository repository;
  final ValueChanged<String> onOpenAdmin;
  final VoidCallback onOpenRisk;
  @override
  State<AdminListScreen> createState() => _AdminListScreenState();
}

class _AdminListScreenState extends State<AdminListScreen> {
  late Future<List<AdminSummary>> future;
  @override
  void initState() {
    super.initState();
    future = widget.repository.listAdmins();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('管理员治理'),
      actions: [
        IconButton(
          onPressed: widget.onOpenRisk,
          icon: const Icon(Icons.shield_outlined),
          tooltip: '风控中心',
        ),
      ],
    ),
    body: FutureBuilder<List<AdminSummary>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () =>
                  setState(() => future = widget.repository.listAdmins()),
              child: const Text('加载失败，重试'),
            ),
          );
        }
        final items = snapshot.data!;
        if (items.isEmpty) return const Center(child: Text('暂无管理员数据'));
        return RefreshIndicator(
          onRefresh: () async =>
              setState(() => future = widget.repository.listAdmins()),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, index) {
              final item = items[index];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      item.nickname.isEmpty
                          ? '?'
                          : item.nickname.characters.first,
                    ),
                  ),
                  title: Text(
                    item.nickname.isEmpty ? item.username : item.nickname,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${item.username} · ${item.roles.join('、')}\n最近操作 ${item.actionCount} 次',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => widget.onOpenAdmin(item.id),
                ),
              );
            },
          ),
        );
      },
    ),
  );
}

class AdminDetailScreen extends StatefulWidget {
  const AdminDetailScreen({
    super.key,
    required this.repository,
    required this.adminId,
  });
  final PlatformRepository repository;
  final String adminId;
  @override
  State<AdminDetailScreen> createState() => _AdminDetailScreenState();
}

class _AdminDetailScreenState extends State<AdminDetailScreen> {
  late Future<AdminDetail> future;
  @override
  void initState() {
    super.initState();
    future = widget.repository.getAdmin(widget.adminId);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('管理员详情')),
    body: FutureBuilder<AdminDetail>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => setState(
                () => future = widget.repository.getAdmin(widget.adminId),
              ),
              child: const Text('加载失败，重试'),
            ),
          );
        }
        final data = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.admin_panel_settings_outlined),
                ),
                title: Text(
                  data.nickname.isEmpty ? data.username : data.nickname,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                subtitle: Text(
                  '${data.username}\n${data.email.isEmpty ? '未绑定邮箱' : data.email}\n状态：${data.status}',
                ),
                isThreeLine: true,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '权限范围',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            const SizedBox(height: 8),
            ...data.roles.map(
              (role) => Card(
                child: ListTile(
                  leading: const Icon(Icons.key_outlined),
                  title: Text(role['name'] ?? ''),
                  subtitle: Text(
                    (role['community_id'] ?? '').isEmpty
                        ? '平台级权限'
                        : '社区：${role['community_id']}',
                  ),
                ),
              ),
            ),
            if (data.permissions.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                '可执行权限',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: data.permissions
                        .map((permission) => Chip(label: Text(permission)))
                        .toList(),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              '最近操作',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            const SizedBox(height: 8),
            if (data.recentActions.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    '暂无操作记录',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
              )
            else
              ...data.recentActions.map(
                (action) => Card(
                  child: ListTile(
                    title: Text(action.action),
                    subtitle: Text(
                      '${action.targetType} · ${action.targetId}\n${action.reason}',
                    ),
                    isThreeLine: true,
                    trailing: Text(
                      _dateLabel(action.createdAt),
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
  String _dateLabel(DateTime value) => '${value.month}/${value.day}';
}

class RiskCenterScreen extends StatefulWidget {
  const RiskCenterScreen({
    super.key,
    required this.repository,
    this.onOpenLogs,
  });
  final PlatformRepository repository;
  final VoidCallback? onOpenLogs;
  @override
  State<RiskCenterScreen> createState() => _RiskCenterScreenState();
}

class _RiskCenterScreenState extends State<RiskCenterScreen> {
  late Future<RiskOverview> future;
  @override
  void initState() {
    super.initState();
    future = widget.repository.getRiskOverview();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('风控中心'),
      actions: [
        if (widget.onOpenLogs != null)
          IconButton(
            onPressed: widget.onOpenLogs,
            icon: const Icon(Icons.fact_check_outlined),
            tooltip: '审计日志',
          ),
      ],
    ),
    body: FutureBuilder<RiskOverview>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () =>
                  setState(() => future = widget.repository.getRiskOverview()),
              child: const Text('加载失败，重试'),
            ),
          );
        }
        final data = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async =>
              setState(() => future = widget.repository.getRiskOverview()),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _metric(
                    '验证码请求',
                    '${data.codeRequests}',
                    Icons.mail_lock_outlined,
                  ),
                  _metric(
                    '异常 IP',
                    '${data.abnormalIps}',
                    Icons.public_off_outlined,
                  ),
                  _metric(
                    '自动限制',
                    '${data.automaticRestrictions}',
                    Icons.auto_awesome_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const Text(
                '最近风险事件',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
              ),
              const SizedBox(height: 8),
              if (data.events.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text(
                      '暂无风险事件',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ),
                )
              else
                ...data.events.map(
                  (event) => Card(
                    child: ListTile(
                      leading: Icon(
                        event.severity == 'high'
                            ? Icons.error
                            : Icons.info_outline,
                        color: event.severity == 'high'
                            ? Colors.red
                            : Colors.orange,
                      ),
                      title: Text(event.eventType),
                      subtitle: Text(
                        '${event.ipAddress.isEmpty ? '未知 IP' : event.ipAddress} · ${event.severity}',
                      ),
                      trailing: Text(
                        '${event.createdAt.hour.toString().padLeft(2, '0')}:${event.createdAt.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
  Widget _metric(String label, String value, IconData icon) => SizedBox(
    width: 160,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppTheme.primary),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      ),
    ),
  );
}

class AdminLogsScreen extends StatefulWidget {
  const AdminLogsScreen({super.key, required this.repository});
  final PlatformRepository repository;
  @override
  State<AdminLogsScreen> createState() => _AdminLogsScreenState();
}

class _AdminLogsScreenState extends State<AdminLogsScreen> {
  late Future<List<AdminLogEntry>> future;
  @override
  void initState() {
    super.initState();
    future = widget.repository.listAdminLogs();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('不可篡改审计日志')),
    body: FutureBuilder<List<AdminLogEntry>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () =>
                  setState(() => future = widget.repository.listAdminLogs()),
              child: const Text('加载失败，重试'),
            ),
          );
        }
        final items = snapshot.data!;
        if (items.isEmpty) return const Center(child: Text('暂无管理员操作'));
        return RefreshIndicator(
          onRefresh: () async =>
              setState(() => future = widget.repository.listAdminLogs()),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, index) {
              final item = items[index];
              return Card(
                child: ListTile(
                  title: Text(item.action),
                  subtitle: Text(
                    '${item.targetType} · ${item.targetId}\n${item.reason}\nprevious: ${_short(item.previousHash)}\nhash: ${_short(item.hash)}',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.link),
                ),
              );
            },
          ),
        );
      },
    ),
  );
  String _short(String value) => value.isEmpty
      ? '链起点'
      : '${value.substring(0, value.length > 12 ? 12 : value.length)}…';
}
