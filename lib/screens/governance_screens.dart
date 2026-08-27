import 'package:flutter/material.dart';

import '../data/api/api_client.dart';
import '../data/api/platform_repository.dart';
import '../domain/models.dart';
import '../domain/repositories.dart';
import '../theme/app_theme.dart';

/// 按服务端 capability 汇总治理入口，避免把低权限管理员困在超级管理员
/// 才能访问的“管理员管理 -> 风控中心”路径中。
class GovernanceCenterScreen extends StatelessWidget {
  const GovernanceCenterScreen({
    super.key,
    this.onOpenModeration,
    this.onOpenAppeals,
    this.onOpenRecommendations,
    this.onOpenAdmins,
    this.onOpenUsers,
    this.onOpenRisk,
    this.onOpenIPRestrictions,
    this.onOpenLogs,
  });

  final VoidCallback? onOpenModeration;
  final VoidCallback? onOpenAppeals;
  final VoidCallback? onOpenRecommendations;
  final VoidCallback? onOpenAdmins;
  final VoidCallback? onOpenUsers;
  final VoidCallback? onOpenRisk;
  final VoidCallback? onOpenIPRestrictions;
  final VoidCallback? onOpenLogs;

  @override
  Widget build(BuildContext context) {
    final entries = <Widget>[
      if (onOpenModeration != null)
        _entry(
          icon: Icons.gavel_outlined,
          title: '审核与用户处罚',
          subtitle: '待审核、举报案件、隐藏恢复、禁言与封禁',
          onTap: onOpenModeration!,
        ),
      if (onOpenAppeals != null)
        _entry(
          icon: Icons.assignment_return_outlined,
          title: '申诉处理',
          subtitle: '查看并处理用户对处罚的申诉',
          onTap: onOpenAppeals!,
        ),
      if (onOpenRecommendations != null)
        _entry(
          icon: Icons.push_pin_outlined,
          title: '首页推荐',
          subtitle: '管理首页人工推荐内容',
          onTap: onOpenRecommendations!,
        ),
      if (onOpenAdmins != null)
        _entry(
          icon: Icons.admin_panel_settings_outlined,
          title: '管理员管理',
          subtitle: '授权角色与社区范围',
          onTap: onOpenAdmins!,
        ),
      if (onOpenUsers != null)
        _entry(
          icon: Icons.manage_accounts_outlined,
          title: '用户管理',
          subtitle: '查询账号、查看内容记录并执行禁言/封禁/恢复',
          onTap: onOpenUsers!,
        ),
      if (onOpenRisk != null)
        _entry(
          icon: Icons.shield_outlined,
          title: '风控中心',
          subtitle: '查看验证码、异常 IP 与自动限制事件',
          onTap: onOpenRisk!,
        ),
      if (onOpenIPRestrictions != null)
        _entry(
          icon: Icons.public_off_outlined,
          title: 'IP 限制',
          subtitle: '管理网络范围封禁',
          onTap: onOpenIPRestrictions!,
        ),
      if (onOpenLogs != null)
        _entry(
          icon: Icons.fact_check_outlined,
          title: '操作日志',
          subtitle: '查看不可篡改的管理员审计链',
          onTap: onOpenLogs!,
        ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('治理中心')),
      body: entries.isEmpty
          ? const Center(child: Text('当前账号没有可用的治理权限'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, index) => entries[index],
            ),
    );
  }

  Widget _entry({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) => Card(
    child: ListTile(
      leading: Icon(icon, color: AppTheme.primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}

class ManagedUserListScreen extends StatefulWidget {
  const ManagedUserListScreen({super.key, required this.repository});

  final PlatformRepository repository;

  @override
  State<ManagedUserListScreen> createState() => _ManagedUserListScreenState();
}

class _ManagedUserListScreenState extends State<ManagedUserListScreen> {
  final searchController = TextEditingController();
  late Future<List<ManagedUserSummary>> future;

  @override
  void initState() {
    super.initState();
    future = widget.repository.listManagedUsers();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  void _search() {
    setState(
      () => future = widget.repository.listManagedUsers(
        query: searchController.text,
      ),
    );
  }

  Future<void> _open(ManagedUserSummary user) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ManagedUserDetailScreen(
          repository: widget.repository,
          userId: user.id,
        ),
      ),
    );
    if (mounted) _search();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('用户管理')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              labelText: '搜索用户 ID、用户名、昵称或邮箱',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: _search,
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<ManagedUserSummary>>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: TextButton(
                    onPressed: _search,
                    child: const Text('加载失败，重试'),
                  ),
                );
              }
              final items = snapshot.data ?? const <ManagedUserSummary>[];
              if (items.isEmpty) return const Center(child: Text('没有匹配的用户'));
              return RefreshIndicator(
                onRefresh: () async => setState(
                  () => future = widget.repository.listManagedUsers(
                    query: searchController.text,
                  ),
                ),
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, index) {
                    final user = items[index];
                    final name = user.nickname.isEmpty
                        ? user.username
                        : user.nickname;
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Text(name.characters.first)),
                        title: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${user.username} · ${_managedStatusLabel(user.status)}'
                          '${user.roles.isEmpty ? '' : '\n${user.roles.join('、')}'}',
                        ),
                        isThreeLine: user.roles.isNotEmpty,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _open(user),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class ManagedUserDetailScreen extends StatefulWidget {
  const ManagedUserDetailScreen({
    super.key,
    required this.repository,
    required this.userId,
  });

  final PlatformRepository repository;
  final String userId;

  @override
  State<ManagedUserDetailScreen> createState() => _ManagedUserDetailScreenState();
}

class _ManagedUserDetailScreenState extends State<ManagedUserDetailScreen> {
  late Future<ManagedUserDetail> future;

  @override
  void initState() {
    super.initState();
    future = widget.repository.getManagedUser(widget.userId);
  }

  Future<void> _action(String action) async {
    final reasonController = TextEditingController();
    final durationController = TextEditingController(text: '7');
    final result = await showDialog<({String reason, int duration})>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          action == 'restore' ? '恢复账号' : action == 'ban' ? '封禁账号' : '禁言账号',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '处理理由（必填）'),
            ),
            if (action != 'restore')
              TextField(
                controller: durationController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '天数（0 表示长期）'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final reason = reasonController.text.trim();
              final duration = int.tryParse(durationController.text) ?? -1;
              if (reason.isEmpty || duration < 0) return;
              Navigator.pop(context, (reason: reason, duration: duration));
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
    reasonController.dispose();
    durationController.dispose();
    if (!mounted || result == null) return;
    try {
      await widget.repository.applyManagedUserAction(
        userId: widget.userId,
        action: action,
        reason: result.reason,
        durationDays: result.duration,
        permanent: action != 'restore' && result.duration == 0,
      );
      if (mounted) {
        setState(() => future = widget.repository.getManagedUser(widget.userId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('处理已生效')),
        );
      }
    } catch (cause) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userFacingApiMessage(cause, fallback: '账号处理失败')),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('用户详情')),
    body: FutureBuilder<ManagedUserDetail>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => setState(
                () => future = widget.repository.getManagedUser(widget.userId),
              ),
              child: const Text('加载失败，重试'),
            ),
          );
        }
        final user = snapshot.data!;
        final name = user.nickname.isEmpty ? user.username : user.nickname;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: CircleAvatar(child: Text(name.characters.first)),
                title: Text(
                  name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${user.username}\n${user.email.isEmpty ? '未绑定邮箱' : user.email}\n${_managedStatusLabel(user.status)}',
                ),
                isThreeLine: true,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!user.muted)
                  FilledButton.tonal(
                    onPressed: () => _action('mute'),
                    child: const Text('禁言'),
                  ),
                if (!user.banned)
                  FilledButton.tonal(
                    onPressed: () => _action('ban'),
                    child: const Text('封禁'),
                  ),
                if (user.muted || user.banned || user.status != 'active')
                  OutlinedButton(
                    onPressed: () => _action('restore'),
                    child: const Text('恢复账号'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '角色：${user.roles.isEmpty ? '普通用户' : user.roles.join('、')}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            const Text('处罚记录', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            if (user.punishments.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('暂无处罚记录'),
              ),
            ...user.punishments.map(
              (item) => ListTile(
                dense: true,
                leading: const Icon(Icons.warning_amber_outlined),
                title: Text('${item['type'] ?? '处理'}：${item['reason'] ?? ''}'),
                subtitle: Text('${item['starts_at'] ?? ''}'),
              ),
            ),
            const SizedBox(height: 12),
            const Text('最近发布', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            if (user.recentPosts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('暂无帖子记录'),
              ),
            ...user.recentPosts.map(
              (item) => ListTile(
                dense: true,
                title: Text('${item['title'] ?? '无标题'}'),
                subtitle: Text('${item['content'] ?? ''}'),
              ),
            ),
          ],
        );
      },
    ),
  );
}

String _managedStatusLabel(String value) => switch (value) {
  'active' => '正常',
  'suspended' => '已暂停',
  'deleted' => '已注销',
  _ => value.isEmpty ? '未知状态' : value,
};

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
    this.onOpenRisk,
    this.onOpenRecommendations,
    this.communityRepository,
  });
  final PlatformRepository repository;
  final ValueChanged<String> onOpenAdmin;
  final VoidCallback? onOpenRisk;
  final VoidCallback? onOpenRecommendations;
  final CommunityRepository? communityRepository;
  @override
  State<AdminListScreen> createState() => _AdminListScreenState();
}

class _AdminListScreenState extends State<AdminListScreen> {
  late Future<List<AdminSummary>> future;
  final searchController = TextEditingController();
  @override
  void initState() {
    super.initState();
    future = widget.repository.listAdmins();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  void _search() {
    setState(
      () => future = widget.repository.listAdmins(query: searchController.text),
    );
  }

  Future<void> _addAdmin() async {
    final candidate = await showModalBottomSheet<AdminCandidate>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AdminCandidatePicker(repository: widget.repository),
    );
    if (!mounted || candidate == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdminRoleEditorScreen(
          repository: widget.repository,
          communityRepository: widget.communityRepository,
          adminId: candidate.id,
          displayName: candidate.nickname.isEmpty
              ? candidate.username
              : candidate.nickname,
          onSaved: _search,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('管理员管理'),
      actions: [
        if (widget.onOpenRecommendations != null)
          IconButton(
            onPressed: widget.onOpenRecommendations,
            icon: const Icon(Icons.push_pin_outlined),
            tooltip: '首页推荐',
          ),
        if (widget.onOpenRisk != null)
          IconButton(
            onPressed: widget.onOpenRisk,
            icon: const Icon(Icons.shield_outlined),
            tooltip: '风控中心',
          ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _addAdmin,
      icon: const Icon(Icons.person_add_alt_1),
      label: const Text('添加管理员'),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              labelText: '搜索用户',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: _search,
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<AdminSummary>>(
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
        ),
      ],
    ),
  );
}

class _AdminCandidatePicker extends StatefulWidget {
  const _AdminCandidatePicker({required this.repository});

  final PlatformRepository repository;

  @override
  State<_AdminCandidatePicker> createState() => _AdminCandidatePickerState();
}

class _AdminCandidatePickerState extends State<_AdminCandidatePicker> {
  final searchController = TextEditingController();
  late Future<List<AdminCandidate>> future;

  @override
  void initState() {
    super.initState();
    future = widget.repository.listAdminCandidates();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  void _search() {
    setState(
      () => future = widget.repository.listAdminCandidates(
        query: searchController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      left: 16,
      right: 16,
      top: 8,
      bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
    ),
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .72,
      child: Column(
        children: [
          const Text(
            '选择用户',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              labelText: '搜索用户名、昵称或邮箱',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: _search,
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<AdminCandidate>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: TextButton(
                      onPressed: _search,
                      child: const Text('加载失败，重试'),
                    ),
                  );
                }
                final items = snapshot.data ?? const <AdminCandidate>[];
                if (items.isEmpty) {
                  return const Center(child: Text('没有匹配的可授权用户'));
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final item = items[index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          item.nickname.isEmpty
                              ? '?'
                              : item.nickname.characters.first,
                        ),
                      ),
                      title: Text(
                        item.nickname.isEmpty ? item.username : item.nickname,
                      ),
                      subtitle: Text(
                        '${item.username} · ${item.email.isEmpty ? '未绑定邮箱' : item.email}',
                      ),
                      onTap: () => Navigator.pop(context, item),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class AdminRoleEditorScreen extends StatefulWidget {
  const AdminRoleEditorScreen({
    super.key,
    required this.repository,
    required this.adminId,
    required this.displayName,
    this.communityRepository,
    this.initialRoles = const [],
    this.onSaved,
  });

  final PlatformRepository repository;
  final CommunityRepository? communityRepository;
  final String adminId;
  final String displayName;
  final List<AdminRoleAssignment> initialRoles;
  final VoidCallback? onSaved;

  @override
  State<AdminRoleEditorScreen> createState() => _AdminRoleEditorScreenState();
}

class _AdminRoleEditorScreenState extends State<AdminRoleEditorScreen> {
  static const roleOptions = <String>[
    'platform_admin',
    'platform_moderator',
    'community_owner',
    'community_moderator',
    'super_admin',
  ];
  String role = 'platform_moderator';
  String? communityId;
  int? editingIndex;
  final assignments = <AdminRoleAssignment>[];
  final communityController = TextEditingController();
  final reasonController = TextEditingController();
  late Future<List<Community>> communities;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    for (final item in widget.initialRoles) {
      if (!roleOptions.contains(item.name)) continue;
      final key = '${item.name}|${item.communityId ?? ''}';
      if (assignments.any(
        (existing) => '${existing.name}|${existing.communityId ?? ''}' == key,
      )) {
        continue;
      }
      assignments.add(item);
    }
    communities =
        widget.communityRepository?.getCommunities(
          status: CommunityStatus.active,
        ) ??
        Future.value(const <Community>[]);
  }

  @override
  void dispose() {
    communityController.dispose();
    reasonController.dispose();
    super.dispose();
  }

  bool get isCommunityRole =>
      role == 'community_owner' || role == 'community_moderator';

  void _editAssignment(int index) {
    final item = assignments[index];
    setState(() {
      editingIndex = index;
      role = item.name;
      communityId = item.communityId;
      communityController.text = item.communityId ?? '';
    });
  }

  void _removeAssignment(int index) {
    setState(() {
      assignments.removeAt(index);
      if (editingIndex == index) {
        editingIndex = null;
        role = 'platform_moderator';
        communityId = null;
        communityController.clear();
      } else if (editingIndex != null && editingIndex! > index) {
        editingIndex = editingIndex! - 1;
      }
    });
  }

  void _resetDraft() {
    setState(() {
      editingIndex = null;
      role = 'platform_moderator';
      communityId = null;
      communityController.clear();
    });
  }

  void _addOrUpdateAssignment() {
    final selectedCommunity = communityController.text.trim();
    if (isCommunityRole && selectedCommunity.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('社区角色必须填写社区范围')));
      return;
    }
    final item = AdminRoleAssignment(
      name: role,
      communityId: isCommunityRole ? selectedCommunity : null,
    );
    final duplicate = assignments.indexWhere(
      (existing) =>
          existing.name == item.name &&
          existing.communityId == item.communityId,
    );
    setState(() {
      if (editingIndex != null) {
        assignments[editingIndex!] = item;
      } else if (duplicate >= 0) {
        assignments[duplicate] = item;
      } else {
        assignments.add(item);
      }
      editingIndex = null;
      role = 'platform_moderator';
      communityId = null;
      communityController.clear();
    });
  }

  Future<void> _save() async {
    if (reasonController.text.trim().isEmpty) {
      setState(() {});
      return;
    }
    setState(() => saving = true);
    try {
      await widget.repository.updateAdminRoles(
        adminId: widget.adminId,
        roles: List.unmodifiable(assignments),
        reason: reasonController.text.trim(),
      );
      widget.onSaved?.call();
      if (mounted) Navigator.pop(context);
    } catch (cause) {
      if (mounted) {
        setState(() => saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userFacingApiMessage(cause, fallback: '角色调整失败')),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('授权角色')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          widget.displayName,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 18),
        if (assignments.isNotEmpty) ...[
          const Text(
            '当前角色（提交时将完整替换）',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ...assignments.asMap().entries.map(
            (entry) => Card(
              child: ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(_roleLabel(entry.value.name)),
                subtitle: entry.value.communityId == null
                    ? null
                    : Text('社区范围：${entry.value.communityId}'),
                trailing: Wrap(
                  children: [
                    IconButton(
                      tooltip: '编辑角色',
                      onPressed: saving
                          ? null
                          : () => _editAssignment(entry.key),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: '移除角色',
                      onPressed: saving
                          ? null
                          : () => _removeAssignment(entry.key),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text(
          editingIndex == null ? '添加角色' : '编辑角色',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: role,
          decoration: const InputDecoration(labelText: '角色'),
          items: roleOptions
              .map(
                (item) => DropdownMenuItem(
                  value: item,
                  child: Text(_roleLabel(item)),
                ),
              )
              .toList(),
          onChanged: saving
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() {
                    role = value;
                    if (!isCommunityRole) {
                      communityId = null;
                      communityController.clear();
                    }
                  });
                },
        ),
        if (isCommunityRole) ...[
          const SizedBox(height: 12),
          FutureBuilder<List<Community>>(
            future: communities,
            builder: (context, snapshot) {
              final items = snapshot.data ?? const <Community>[];
              if (items.isEmpty) {
                return TextField(
                  controller: communityController,
                  enabled: !saving,
                  decoration: const InputDecoration(labelText: '社区 ID（高级操作）'),
                );
              }
              return DropdownButtonFormField<String>(
                initialValue:
                    items.any((item) => item.id == communityController.text)
                    ? communityController.text
                    : null,
                decoration: const InputDecoration(labelText: '社区范围'),
                items: items
                    .map(
                      (item) => DropdownMenuItem(
                        value: item.id,
                        child: Text(item.name),
                      ),
                    )
                    .toList(),
                onChanged: saving
                    ? null
                    : (value) => setState(() {
                        communityId = value;
                        communityController.text = value ?? '';
                      }),
              );
            },
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: saving ? null : _addOrUpdateAssignment,
                icon: Icon(
                  editingIndex == null ? Icons.add : Icons.save_outlined,
                ),
                label: Text(editingIndex == null ? '添加角色' : '保存角色'),
              ),
            ),
            if (editingIndex != null) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: saving ? null : _resetDraft,
                child: const Text('取消编辑'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: reasonController,
          enabled: !saving,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: '操作理由（必填）',
            errorText: reasonController.text.trim().isEmpty && saving
                ? '请填写理由'
                : null,
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: saving ? null : _save,
          icon: const Icon(Icons.check),
          label: Text(saving ? '提交中…' : '确认授权'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: saving
              ? null
              : () async {
                  final navigator = Navigator.of(context);
                  final messenger = ScaffoldMessenger.of(context);
                  final confirmed =
                      await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('撤销全部管理员角色？'),
                          content: const Text('该用户将失去所有管理员权限。'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('确认撤销'),
                            ),
                          ],
                        ),
                      ) ??
                      false;
                  if (!confirmed || !mounted) return;
                  setState(() => saving = true);
                  try {
                    await widget.repository.updateAdminRoles(
                      adminId: widget.adminId,
                      roles: const [],
                      reason: '撤销管理员权限',
                    );
                    widget.onSaved?.call();
                    if (!mounted) return;
                    navigator.pop();
                  } catch (cause) {
                    if (mounted) {
                      setState(() => saving = false);
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            userFacingApiMessage(cause, fallback: '撤销管理员权限失败'),
                          ),
                        ),
                      );
                    }
                  }
                },
          icon: const Icon(Icons.person_remove_outlined),
          label: const Text('撤销管理员权限'),
        ),
      ],
    ),
  );

  String _roleLabel(String value) => switch (value) {
    'platform_admin' => '平台管理员',
    'platform_moderator' => '平台审核员',
    'community_owner' => '社区管理员',
    'community_moderator' => '社区版主',
    'super_admin' => '超级管理员',
    _ => value,
  };
}

class AdminDetailScreen extends StatefulWidget {
  const AdminDetailScreen({
    super.key,
    required this.repository,
    required this.adminId,
    this.communityRepository,
  });
  final PlatformRepository repository;
  final String adminId;
  final CommunityRepository? communityRepository;
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

  Future<void> _editRoles() async {
    try {
      final data = await future;
      if (!mounted) return;
      final roles = data.roles
          .map(
            (item) => AdminRoleAssignment(
              name: item['name'] ?? '',
              communityId: (item['community_id'] ?? '').isEmpty
                  ? null
                  : item['community_id'],
            ),
          )
          .toList();
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AdminRoleEditorScreen(
            repository: widget.repository,
            communityRepository: widget.communityRepository,
            adminId: widget.adminId,
            displayName: data.nickname.isEmpty ? data.username : data.nickname,
            initialRoles: roles,
            onSaved: () => setState(
              () => future = widget.repository.getAdmin(widget.adminId),
            ),
          ),
        ),
      );
    } catch (cause) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userFacingApiMessage(cause, fallback: '管理员信息加载失败')),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('管理员管理 · 详情'),
      actions: [
        IconButton(
          onPressed: _editRoles,
          icon: const Icon(Icons.manage_accounts_outlined),
          tooltip: '调整角色',
        ),
      ],
    ),
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
    this.canBanIP = true,
  });
  final PlatformRepository repository;
  final VoidCallback? onOpenLogs;
  final bool canBanIP;
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
        if (widget.canBanIP)
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    IPRestrictionsScreen(repository: widget.repository),
              ),
            ),
            icon: const Icon(Icons.public_off_outlined),
            tooltip: 'IP 限制',
          ),
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

class IPRestrictionsScreen extends StatefulWidget {
  const IPRestrictionsScreen({super.key, required this.repository});

  final PlatformRepository repository;

  @override
  State<IPRestrictionsScreen> createState() => _IPRestrictionsScreenState();
}

class _IPRestrictionsScreenState extends State<IPRestrictionsScreen> {
  late Future<List<IpRestriction>> future;

  @override
  void initState() {
    super.initState();
    future = widget.repository.listIPRestrictions();
  }

  Future<void> _reload() async {
    setState(() => future = widget.repository.listIPRestrictions());
    await future;
  }

  Future<void> _add() async {
    final cidrController = TextEditingController();
    final reasonController = TextEditingController();
    var durationDays = 0;
    var permanent = true;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('新增 IP 限制'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: cidrController,
                decoration: const InputDecoration(
                  labelText: 'IP 地址',
                  hintText: '默认填写单个 IPv4/IPv6；高级操作可填 CIDR',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: reasonController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '原因（必填）'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: durationDays,
                decoration: const InputDecoration(labelText: '有效期'),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('永久')),
                  DropdownMenuItem(value: 1, child: Text('1 天')),
                  DropdownMenuItem(value: 7, child: Text('7 天')),
                  DropdownMenuItem(value: 30, child: Text('30 天')),
                ],
                onChanged: (value) => setDialogState(() {
                  durationDays = value ?? 0;
                  permanent = durationDays == 0;
                }),
              ),
              const SizedBox(height: 10),
              const Text(
                '请确认地址范围，避免误封整个校园网。',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                if (cidrController.text.trim().isEmpty ||
                    reasonController.text.trim().isEmpty) {
                  return;
                }
                try {
                  await widget.repository.createIPRestriction(
                    cidr: cidrController.text.trim(),
                    reason: reasonController.text.trim(),
                    durationDays: durationDays,
                    permanent: permanent,
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                } catch (cause) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(
                        content: Text(
                          userFacingApiMessage(cause, fallback: 'IP 限制创建失败'),
                        ),
                      ),
                    );
                  }
                }
              },
              child: const Text('确认封禁'),
            ),
          ],
        ),
      ),
    );
    cidrController.dispose();
    reasonController.dispose();
    if (result == true && mounted) await _reload();
  }

  Future<void> _revoke(IpRestriction item) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('撤销 IP 限制？'),
            content: Text('${item.cidr}\n${item.reason}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认撤销'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      await widget.repository.revokeIPRestriction(item.id);
      if (mounted) await _reload();
    } catch (cause) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(userFacingApiMessage(cause, fallback: 'IP 限制撤销失败')),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('IP 限制'),
      actions: [
        IconButton(
          onPressed: _add,
          icon: const Icon(Icons.add),
          tooltip: '新增限制',
        ),
      ],
    ),
    body: FutureBuilder<List<IpRestriction>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: TextButton(onPressed: _reload, child: const Text('加载失败，重试')),
          );
        }
        final items = snapshot.data ?? const <IpRestriction>[];
        if (items.isEmpty) return const Center(child: Text('暂无 IP 限制'));
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, index) {
              final item = items[index];
              return Card(
                child: ListTile(
                  leading: Icon(
                    item.active ? Icons.block : Icons.check_circle_outline,
                    color: item.active ? Colors.red : Colors.green,
                  ),
                  title: Text(
                    item.cidr,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${item.reason}\n${item.endsAt == null ? '永久' : '截止 ${item.endsAt}'}',
                  ),
                  isThreeLine: true,
                  trailing: item.active
                      ? TextButton(
                          onPressed: () => _revoke(item),
                          child: const Text('撤销'),
                        )
                      : const Text('已撤销'),
                ),
              );
            },
          ),
        );
      },
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
                    '${item.targetType} · ${item.targetId}\n${item.reason}\nIP：${item.ipAddress.isEmpty ? '未知' : item.ipAddress}\nprevious: ${_short(item.previousHash)}\nhash: ${_short(item.hash)}',
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
