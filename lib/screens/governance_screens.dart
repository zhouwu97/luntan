import 'dart:async';

import 'package:flutter/material.dart';

import '../data/api/api_client.dart';
import '../data/api/appeal_repository.dart';
import '../data/api/platform_repository.dart';
import '../domain/models.dart';
import '../domain/repositories.dart';
import '../theme/app_theme.dart';
import '../widgets/app_network_image.dart';

String _safePublicAccountLabel(String? publicId, String username) {
  final pid = publicId?.trim();
  if (pid != null && pid.isNotEmpty && pid != '0') {
    return 'ID: $pid';
  }
  final trimmed = username.trim();
  if (trimmed.startsWith('email_') ||
      trimmed.startsWith('usr_') ||
      trimmed.startsWith('acct_')) {
    final idx = trimmed.indexOf('_');
    return 'ID: ${trimmed.substring(idx + 1)}';
  }
  if (trimmed.isNotEmpty) {
    return '@$trimmed';
  }
  return '';
}

String _formatRoleName(String raw) {
  if (raw.isEmpty) return '普通用户';
  String role = raw;
  String? community;
  if (raw.contains(':')) {
    final parts = raw.split(':');
    role = parts[0].trim();
    community = parts.sublist(1).join(':').trim();
  }
  final roleName = switch (role) {
    'platform_admin' => '平台管理员',
    'platform_moderator' => '平台审核员',
    'community_owner' => '社区管理员',
    'community_moderator' => '社区版主',
    'super_admin' => '超级管理员',
    _ => role,
  };
  if (community != null && community.isNotEmpty) {
    return '$roleName（$community）';
  }
  return roleName;
}

String _formatPermissionName(String permission) => switch (permission) {
  'moderation.action' => '内容审核与处置',
  'report.review' => '举报申诉审核',
  'audit.read' => '审计日志查看',
  'user.manage' => '用户状态与处罚',
  'user.ban.global' => '全局网络封禁',
  'admin.manage' => '管理员授权',
  'store.order.review' => '兑换申请审核',
  _ => permission,
};

String _formatActionCode(String action) => switch (action) {
  'mute' => '禁言账号',
  'ban' => '封禁账号',
  'restore' => '恢复账号',
  'delete' => '删除违规内容',
  'hide' => '隐藏内容',
  'role.update' || 'update_roles' => '调整管理员角色',
  'ip.ban' || 'create_ip_restriction' => '封禁 IP',
  'ip.revoke' || 'revoke_ip_restriction' => '解封 IP',
  'appeal.approve' => '申诉通过',
  'appeal.reject' => '申诉驳回',
  'recommendation.add' => '添加首页推荐',
  'recommendation.remove' => '移除首页推荐',
  'recommendation.reorder' => '调整推荐顺序',
  'store.order.approve' => '兑换审核通过',
  'store.order.reject' => '兑换审核不通过',
  _ => action,
};

String _formatTargetType(String type) => switch (type) {
  'post' => '帖子',
  'comment' => '评论',
  'user' => '用户',
  'ip' => 'IP 地址',
  'moderation_case' => '审核案件',
  'moderation_action' => '处罚记录',
  'appeal' || 'moderation_appeal' => '申诉记录',
  'store_order' => '兑换订单',
  _ => type.isEmpty ? '目标对象' : type,
};

String _formatRiskSeverity(String severity) => switch (severity) {
  'high' => '高风险',
  'medium' => '中风险',
  'low' => '低风险',
  'info' => '提示',
  _ => severity,
};

String _formatRiskEventType(String eventType) => switch (eventType) {
  'sms_limit' || 'code_request' => '验证码频控',
  'abnormal_ip' => '异常 IP 访问',
  'auto_restriction' => '系统自动限制',
  'rate_limit' => '请求超频',
  _ => eventType,
};

String _managedStatusLabel(String value) => switch (value) {
  'active' => '正常',
  'suspended' => '已暂停',
  'deleted' => '已注销',
  _ => value.isEmpty ? '未知状态' : value,
};

/// 治理中心工作台：按服务端 capability 汇总治理入口，提供清晰的信息分区与指标卡片。
class GovernanceCenterScreen extends StatefulWidget {
  const GovernanceCenterScreen({
    super.key,
    this.repository,
    this.appealRepository,
    this.onOpenModeration,
    this.onOpenAppeals,
    this.onOpenRecommendations,
    this.onOpenActivities,
    this.onOpenRankingSubmissions,
    this.onOpenStoreOrderReview,
    this.onOpenAdmins,
    this.onOpenUsers,
    this.onOpenRisk,
    this.onOpenIPRestrictions,
    this.onOpenLogs,
  });

  final PlatformRepository? repository;
  final AppealRepository? appealRepository;
  final VoidCallback? onOpenModeration;
  final VoidCallback? onOpenAppeals;
  final VoidCallback? onOpenRecommendations;
  final VoidCallback? onOpenActivities;
  final VoidCallback? onOpenRankingSubmissions;
  final VoidCallback? onOpenStoreOrderReview;
  final VoidCallback? onOpenAdmins;
  final VoidCallback? onOpenUsers;
  final VoidCallback? onOpenRisk;
  final VoidCallback? onOpenIPRestrictions;
  final VoidCallback? onOpenLogs;

  @override
  State<GovernanceCenterScreen> createState() => _GovernanceCenterScreenState();
}

class _GovernanceCenterScreenState extends State<GovernanceCenterScreen> {
  int? _pendingCasesCount;
  int? _riskEventsCount;
  int? _pendingAppealsCount;

  @override
  void initState() {
    super.initState();
    _loadLiveStats();
  }

  Future<void> _loadLiveStats() async {
    if (widget.repository != null) {
      try {
        final cases = await widget.repository!.listModerationCases(
          status: 'pending',
        );
        if (mounted) setState(() => _pendingCasesCount = cases.items.length);
      } catch (_) {}
      try {
        final risk = await widget.repository!.getRiskOverview();
        if (mounted) setState(() => _riskEventsCount = risk.events.length);
      } catch (_) {}
    }
    if (widget.appealRepository != null) {
      try {
        final appeals = await widget.appealRepository!.listModerationAppeals(
          status: 'pending',
        );
        if (mounted)
          setState(() => _pendingAppealsCount = appeals.items.length);
      } catch (_) {}
    }
  }

  bool get _hasAnyAccess =>
      widget.onOpenModeration != null ||
      widget.onOpenAppeals != null ||
      widget.onOpenRecommendations != null ||
      widget.onOpenActivities != null ||
      widget.onOpenRankingSubmissions != null ||
      widget.onOpenStoreOrderReview != null ||
      widget.onOpenAdmins != null ||
      widget.onOpenUsers != null ||
      widget.onOpenRisk != null ||
      widget.onOpenIPRestrictions != null ||
      widget.onOpenLogs != null;

  @override
  Widget build(BuildContext context) {
    if (!_hasAnyAccess) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text(
            '治理中心',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          backgroundColor: AppTheme.background,
          elevation: 0,
        ),
        body: const Center(
          child: Text(
            '当前账号没有可用的治理权限',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13.5),
          ),
        ),
      );
    }

    final hasModerationGroup =
        widget.onOpenModeration != null ||
        widget.onOpenAppeals != null ||
        widget.onOpenRecommendations != null ||
        widget.onOpenActivities != null ||
        widget.onOpenRankingSubmissions != null ||
        widget.onOpenStoreOrderReview != null;

    final hasUserGroup =
        widget.onOpenUsers != null ||
        widget.onOpenAdmins != null ||
        widget.onOpenRisk != null ||
        widget.onOpenIPRestrictions != null ||
        widget.onOpenLogs != null;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text(
          '治理中心',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
        backgroundColor: AppTheme.background,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 36),
        children: [
          // 治理工作台概览头部 Hero 卡片
          Container(
            margin: const EdgeInsets.only(top: 2, bottom: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF608EF3), Color(0xFF547BE0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4B76D3).withValues(alpha: 0.26),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.shield_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '治理工作台',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.onOpenAdmins != null
                                ? '超级管理员控制台 · 权限实时生效'
                                : '内容与用户治理控制台',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _heroStatItem('${_pendingCasesCount ?? 3}', '待复核'),
                    const SizedBox(width: 18),
                    _heroStatItem('${_riskEventsCount ?? 1}', '风险事件'),
                    const SizedBox(width: 18),
                    _heroStatItem('${_pendingAppealsCount ?? 0}', '待申诉'),
                  ],
                ),
              ],
            ),
          ),

          // 核心审核与运营工作区
          if (hasModerationGroup) ...[
            _sectionHeader('内容审核与推荐'),
            _GovernanceSection(
              children: [
                if (widget.onOpenModeration != null)
                  _GovernanceRow(
                    icon: Icons.gavel_rounded,
                    iconBg: AppTheme.softBlue,
                    iconColor: AppTheme.primary,
                    title: '审核与用户处罚',
                    subtitle: '举报、审核、隐藏恢复、禁言与封禁',
                    badgeText: '核心',
                    badgeBg: AppTheme.softBlue,
                    badgeColor: AppTheme.primary,
                    onTap: widget.onOpenModeration!,
                  ),
                if (widget.onOpenAppeals != null)
                  _GovernanceRow(
                    icon: Icons.rate_review_outlined,
                    iconBg: AppTheme.softAmber,
                    iconColor: AppTheme.orange,
                    title: '申诉处理',
                    subtitle: '查看并处理用户对处罚的申诉',
                    onTap: widget.onOpenAppeals!,
                  ),
                if (widget.onOpenRecommendations != null)
                  _GovernanceRow(
                    icon: Icons.push_pin_outlined,
                    iconBg: AppTheme.softViolet,
                    iconColor: AppTheme.purple,
                    title: '首页推荐',
                    subtitle: '管理人工精选与推荐顺序',
                    onTap: widget.onOpenRecommendations!,
                  ),
                if (widget.onOpenActivities != null)
                  _GovernanceRow(
                    icon: Icons.event_available_outlined,
                    iconBg: AppTheme.softMint,
                    iconColor: AppTheme.mint,
                    title: '活动管理',
                    subtitle: '创建、编辑、发布与下架社区活动',
                    badgeText: '运营',
                    badgeBg: AppTheme.softMint,
                    badgeColor: AppTheme.mint,
                    onTap: widget.onOpenActivities!,
                  ),
                if (widget.onOpenRankingSubmissions != null)
                  _GovernanceRow(
                    icon: Icons.toys_outlined,
                    iconBg: AppTheme.softBlue,
                    iconColor: AppTheme.primary,
                    title: '玩具提交审核',
                    subtitle: '审核用户投稿的榜单玩具',
                    badgeText: '榜单',
                    badgeBg: AppTheme.softBlue,
                    badgeColor: AppTheme.primary,
                    onTap: widget.onOpenRankingSubmissions!,
                  ),
                if (widget.onOpenStoreOrderReview != null)
                  _GovernanceRow(
                    icon: Icons.card_giftcard_outlined,
                    iconBg: AppTheme.softRose,
                    iconColor: AppTheme.pink,
                    title: '兑换审核',
                    subtitle: '查看用户发帖与评论，审核积分兑换申请',
                    badgeText: '运营',
                    badgeBg: AppTheme.softRose,
                    badgeColor: AppTheme.pink,
                    onTap: widget.onOpenStoreOrderReview!,
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // 用户与权限管理
          if (hasUserGroup) ...[
            _sectionHeader('账号与授权'),
            _GovernanceSection(
              children: [
                if (widget.onOpenUsers != null)
                  _GovernanceRow(
                    icon: Icons.manage_accounts_outlined,
                    iconBg: AppTheme.softBlue,
                    iconColor: AppTheme.primary,
                    title: '用户管理',
                    subtitle: '查询账号、分页浏览、查看发布与处罚',
                    onTap: widget.onOpenUsers!,
                  ),
                if (widget.onOpenAdmins != null)
                  _GovernanceRow(
                    icon: Icons.admin_panel_settings_outlined,
                    iconBg: AppTheme.softViolet,
                    iconColor: AppTheme.purple,
                    title: '管理员管理',
                    subtitle: '角色授权、权限范围与操作记录',
                    badgeText: '超管',
                    badgeBg: AppTheme.softViolet,
                    badgeColor: AppTheme.purple,
                    onTap: widget.onOpenAdmins!,
                  ),
                if (widget.onOpenRisk != null)
                  _GovernanceRow(
                    icon: Icons.shield_outlined,
                    iconBg: AppTheme.softRose,
                    iconColor: AppTheme.pink,
                    title: '风控中心',
                    subtitle: '验证码、异常 IP、自动限制与风险事件',
                    onTap: widget.onOpenRisk!,
                  ),
                if (widget.onOpenIPRestrictions != null)
                  _GovernanceRow(
                    icon: Icons.public_off_outlined,
                    iconBg: AppTheme.softRose,
                    iconColor: AppTheme.pink,
                    title: 'IP 限制',
                    subtitle: '管理网络 IP / CIDR 封禁与解封',
                    badgeText: '超管',
                    badgeBg: AppTheme.softRose,
                    badgeColor: AppTheme.pink,
                    onTap: widget.onOpenIPRestrictions!,
                  ),
                if (widget.onOpenLogs != null)
                  _GovernanceRow(
                    icon: Icons.fact_check_outlined,
                    iconBg: AppTheme.softViolet,
                    iconColor: AppTheme.purple,
                    title: '操作日志',
                    subtitle: '不可篡改的管理员操作审计记录',
                    onTap: widget.onOpenLogs!,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _heroStatItem(String count, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          count,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppTheme.textSecondary,
      ),
    ),
  );
}

class _GovernanceSection extends StatelessWidget {
  const _GovernanceSection({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
        boxShadow: const [AppTheme.cardShadow],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              const Divider(
                height: 1,
                indent: 58,
                endIndent: 14,
                color: Color(0xFFEDF2F7),
              ),
          ],
        ],
      ),
    );
  }
}

class _GovernanceRow extends StatelessWidget {
  const _GovernanceRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.badgeText,
    this.badgeBg,
    this.badgeColor,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String? badgeText;
  final Color? badgeBg;
  final Color? badgeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 66),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: iconColor, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          if (badgeText != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: badgeBg ?? AppTheme.softBlue,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                badgeText!,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: badgeColor ?? AppTheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF8FA3B8),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ManagedUserListScreen extends StatefulWidget {
  const ManagedUserListScreen({
    super.key,
    required this.repository,
    this.onOpenPostId,
  });

  final PlatformRepository repository;
  final ValueChanged<String>? onOpenPostId;

  @override
  State<ManagedUserListScreen> createState() => _ManagedUserListScreenState();
}

class _ManagedUserListScreenState extends State<ManagedUserListScreen> {
  final searchController = TextEditingController();
  final scrollController = ScrollController();

  final List<ManagedUserSummary> _items = [];
  String? _nextCursor;
  bool _hasMore = false;
  bool _loadingInitial = false;
  bool _loadingMore = false;
  String? _errorText;
  String? _loadMoreErrorText;
  String? _statusFilter;
  Timer? _debounceTimer;
  int _searchRequestId = 0;

  @override
  void initState() {
    super.initState();
    scrollController.addListener(_onScroll);
    searchController.addListener(_onSearchChanged);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    scrollController.removeListener(_onScroll);
    scrollController.dispose();
    searchController.removeListener(_onSearchChanged);
    searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _loadFirstPage();
    });
  }

  void _onScroll() {
    if (_loadingInitial || _loadingMore || !_hasMore) return;
    if (scrollController.position.pixels >=
        scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadFirstPage() async {
    final currentRequestId = ++_searchRequestId;
    setState(() {
      _loadingInitial = true;
      _errorText = null;
      _loadMoreErrorText = null;
    });
    try {
      final page = await widget.repository.listManagedUsersPage(
        query: searchController.text.trim(),
        status: _statusFilter,
      );
      if (!mounted || currentRequestId != _searchRequestId) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loadingInitial = false;
      });
    } catch (e) {
      if (!mounted || currentRequestId != _searchRequestId) return;
      setState(() {
        _loadingInitial = false;
        _errorText = userFacingApiMessage(e, fallback: '加载用户列表失败，请检查网络后重试');
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _nextCursor == null) return;
    final currentRequestId = _searchRequestId;
    setState(() {
      _loadingMore = true;
      _loadMoreErrorText = null;
    });
    try {
      final page = await widget.repository.listManagedUsersPage(
        query: searchController.text.trim(),
        status: _statusFilter,
        cursor: _nextCursor,
      );
      if (!mounted || currentRequestId != _searchRequestId) return;
      setState(() {
        _items.addAll(page.items);
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || currentRequestId != _searchRequestId) return;
      setState(() {
        _loadingMore = false;
        _loadMoreErrorText = userFacingApiMessage(e, fallback: '加载下一页失败');
      });
    }
  }

  void _onStatusChanged(String? status) {
    if (_statusFilter == status) return;
    setState(() => _statusFilter = status);
    _loadFirstPage();
  }

  void _search() {
    _debounceTimer?.cancel();
    _loadFirstPage();
  }

  Future<void> _open(ManagedUserSummary user) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ManagedUserDetailScreen(
          repository: widget.repository,
          userId: user.id,
          onOpenPostId: widget.onOpenPostId,
        ),
      ),
    );
    if (mounted) _loadFirstPage();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.background,
    appBar: AppBar(
      title: const Text(
        '用户管理',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
      ),
      backgroundColor: AppTheme.background,
      elevation: 0,
    ),
    body: Column(
      children: [
        // 搜索栏
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
          child: Container(
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFEDF5FC),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(
                  Icons.search_rounded,
                  color: Color(0xFF5E748A),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textPrimary,
                    ),
                    decoration: const InputDecoration(
                      hintText: '搜索用户 ID、用户名、昵称或邮箱',
                      hintStyle: TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF8B9FB3),
                      ),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                if (searchController.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      searchController.clear();
                      _search();
                    },
                    child: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: Color(0xFF7A8FA5),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // 状态筛选 Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: Row(
            children: [
              _filterChip('全部', null),
              const SizedBox(width: 8),
              _filterChip('正常', 'active'),
              const SizedBox(width: 8),
              _filterChip('已暂停', 'suspended'),
              const SizedBox(width: 8),
              _filterChip('已注销', 'deleted'),
            ],
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    ),
  );

  Widget _filterChip(String label, String? status) {
    final isSelected = _statusFilter == status;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => _onStatusChanged(status),
      showCheckmark: false,
      backgroundColor: Colors.white,
      selectedColor: AppTheme.softBlue,
      side: BorderSide(
        color: isSelected ? const Color(0xFFD7E6FF) : const Color(0xFFD4DFE9),
      ),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
        color: isSelected ? const Color(0xFF3E78CC) : const Color(0xFF6B8197),
      ),
    );
  }

  Widget _buildBody() {
    if (_loadingInitial) {
      return ListView.separated(
        padding: const EdgeInsets.all(14),
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, _) => Container(
          height: 74,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF0F6),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      height: 12,
                      width: 100,
                      color: const Color(0xFFEAF0F6),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 10,
                      width: 160,
                      color: const Color(0xFFEAF0F6),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_errorText != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 36,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: 10),
            Text(
              _errorText!,
              style: const TextStyle(color: AppTheme.pink, fontSize: 13),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _loadFirstPage,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('重新加载'),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadFirstPage,
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
                    child: const Icon(
                      Icons.person_search_rounded,
                      size: 28,
                      color: Color(0xFF6B8299),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '没有匹配的用户',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF304A65),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '请尝试调整搜索关键词或状态筛选',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFirstPage,
      child: ListView.separated(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
        itemCount: _items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, index) {
          if (index == _items.length) {
            return _buildFooter();
          }
          final user = _items[index];
          final name = user.nickname.isEmpty ? user.username : user.nickname;
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
              boxShadow: const [AppTheme.cardShadow],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _open(user),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCE9FF),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          name.characters.isEmpty ? '?' : name.characters.first,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF315E9E),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                      color: AppTheme.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                _userStatusBadge(user.status),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${user.username}${user.email.isEmpty ? ' · 未绑定邮箱' : ' · ${user.email}'}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (user.roles.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: user.roles
                                    .map(
                                      (r) => Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppTheme.softBlue,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          _formatRoleName(r),
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.primary,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF8FA3B8),
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFooter() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_loadMoreErrorText != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: TextButton(
            onPressed: _loadMore,
            child: Text('加载失败，点击重试 (${_loadMoreErrorText!})'),
          ),
        ),
      );
    }
    if (!_hasMore && _items.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            '已加载全部 ${_items.length} 位用户',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11.5,
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _userStatusBadge(String status) {
    final (label, color, bg) = switch (status) {
      'active' => ('正常', const Color(0xFF2C8C77), const Color(0xFFEDF8F5)),
      'suspended' => ('已暂停', const Color(0xFFBD772F), const Color(0xFFFFF2E4)),
      'deleted' => ('已注销', const Color(0xFF667F97), const Color(0xFFEDF2F8)),
      _ => (status, const Color(0xFF667F97), const Color(0xFFEDF2F8)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class ManagedUserDetailScreen extends StatefulWidget {
  const ManagedUserDetailScreen({
    super.key,
    required this.repository,
    required this.userId,
    this.onOpenPostId,
  });

  final PlatformRepository repository;
  final String userId;
  final ValueChanged<String>? onOpenPostId;

  @override
  State<ManagedUserDetailScreen> createState() =>
      _ManagedUserDetailScreenState();
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
          action == 'restore'
              ? '恢复账号'
              : action == 'ban'
              ? '封禁账号'
              : '禁言账号',
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
        setState(
          () => future = widget.repository.getManagedUser(widget.userId),
        );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('处理已生效')));
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
                leading: CircleAvatar(
                  child: Text(
                    name.characters.isEmpty ? '?' : name.characters.first,
                  ),
                ),
                title: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: Text(
                  '${user.username}\n${user.email.isEmpty ? '未绑定邮箱' : user.email}\n账号状态：${_managedStatusLabel(user.status)}',
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
            const Text(
              '角色权限',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: user.roles.isEmpty
                  ? [
                      const Chip(
                        avatar: Icon(Icons.person_outline, size: 16),
                        label: Text('普通用户'),
                      ),
                    ]
                  : user.roles
                        .map(
                          (r) => Chip(
                            avatar: const Icon(Icons.badge_outlined, size: 16),
                            label: Text(_formatRoleName(r)),
                          ),
                        )
                        .toList(),
            ),
            const SizedBox(height: 16),
            const Text(
              '处罚记录',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (user.punishments.isEmpty)
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
              ...user.punishments.map(
                (item) => Card(
                  child: ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.warning_amber_outlined,
                      color: Colors.orange,
                    ),
                    title: Text(
                      '${_formatActionCode(item['type']?.toString() ?? '')}：${item['reason'] ?? ''}',
                    ),
                    subtitle: Text('${item['starts_at'] ?? ''}'),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            const Text(
              '最近发布',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (user.recentPosts.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    '暂无帖子记录',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
              )
            else
              ...user.recentPosts.map((item) {
                final postId = (item['id'] ?? '').toString();
                final canOpen =
                    widget.onOpenPostId != null && postId.isNotEmpty;
                return Card(
                  child: ListTile(
                    dense: true,
                    title: Text(
                      '${item['title'] ?? '无标题'}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text('${item['content'] ?? ''}'),
                    trailing: canOpen ? const Icon(Icons.chevron_right) : null,
                    onTap: canOpen ? () => widget.onOpenPostId!(postId) : null,
                  ),
                );
              }),
          ],
        );
      },
    ),
  );
}

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
    backgroundColor: AppTheme.background,
    appBar: AppBar(
      title: const Text(
        '账号状态',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
      ),
      backgroundColor: AppTheme.background,
      elevation: 0,
    ),
    body: FutureBuilder<AccountStatusData>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 36,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(height: 10),
                const Text(
                  '加载账号状态失败',
                  style: TextStyle(color: AppTheme.pink, fontSize: 13),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: () => setState(
                    () => future = widget.repository.getAccountStatus(),
                  ),
                  child: const Text('重新加载'),
                ),
              ],
            ),
          );
        }
        final data = snapshot.data!;
        final active = data.status == 'active';
        return RefreshIndicator(
          onRefresh: () async =>
              setState(() => future = widget.repository.getAccountStatus()),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 32),
            children: [
              // 状态卡片
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppTheme.border),
                  boxShadow: const [AppTheme.cardShadow],
                ),
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: active ? AppTheme.softMint : AppTheme.softRose,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        active
                            ? Icons.verified_user_rounded
                            : Icons.warning_amber_rounded,
                        color: active ? AppTheme.mint : AppTheme.pink,
                        size: 24,
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
                              fontSize: 16,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            active
                                ? '账号状态正常 · 无违规记录'
                                : '账号处于${_statusLabel(data.status)}状态',
                            style: TextStyle(
                              color: active
                                  ? const Color(0xFF2C8C77)
                                  : const Color(0xFFD44333),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEDF5FC),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        data.accountType == 'guest' ? '游客' : '正式账号',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF486A8A),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 邮箱卡片
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppTheme.border),
                  boxShadow: const [AppTheme.cardShadow],
                ),
                child: ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.softBlue,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.mail_outline_rounded,
                      color: AppTheme.primary,
                      size: 18,
                    ),
                  ),
                  title: Text(
                    data.email.isEmpty ? '未绑定邮箱' : data.email,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  subtitle: Text(
                    data.emailVerified ? '邮箱已完成验证' : '邮箱未验证',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  trailing: Icon(
                    data.emailVerified
                        ? Icons.check_circle_rounded
                        : Icons.info_outline_rounded,
                    color: data.emailVerified ? AppTheme.mint : AppTheme.orange,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 处罚与限制记录
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  '处罚与限制记录',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              if (data.punishments.isEmpty)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.border),
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: 24,
                    horizontal: 16,
                  ),
                  alignment: Alignment.center,
                  child: const Column(
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 32,
                        color: Color(0xFF8B9FB3),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '当前没有处罚与限制记录',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...data.punishments.map(
                  (item) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.border),
                      boxShadow: const [AppTheme.cardShadow],
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppTheme.softRose,
                            borderRadius: BorderRadius.circular(11),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            _iconForPunishment(item.type),
                            color: AppTheme.pink,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _punishmentTitle(item),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${item.reason}\n${_dateLabel(item.startsAt)}${item.endsAt == null ? ' · 长期' : ' — ${_dateLabel(item.endsAt!)}'}',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppTheme.textSecondary,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (item.appealable && widget.onOpenAction != null)
                          FilledButton.tonal(
                            onPressed: () => widget.onOpenAction!(item.id),
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              '申诉',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                      ],
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
      ? Icons.block_rounded
      : type == 'moderation'
      ? Icons.gavel_rounded
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
        // 搜索栏
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
          child: Container(
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFEDF5FC),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(
                  Icons.search_rounded,
                  color: Color(0xFF5E748A),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textPrimary,
                    ),
                    decoration: const InputDecoration(
                      hintText: '搜索管理员昵称或邮箱',
                      hintStyle: TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF8B9FB3),
                      ),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                if (searchController.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      searchController.clear();
                      _search();
                    },
                    child: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: Color(0xFF7A8FA5),
                    ),
                  ),
              ],
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '加载失败',
                        style: TextStyle(color: AppTheme.pink),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => setState(
                          () => future = widget.repository.listAdmins(),
                        ),
                        child: const Text('点击重试'),
                      ),
                    ],
                  ),
                );
              }
              final items = snapshot.data!;
              if (items.isEmpty) {
                return const Center(
                  child: Text(
                    '暂无管理员数据',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () async =>
                    setState(() => future = widget.repository.listAdmins()),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 80),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, index) {
                    final item = items[index];
                    final name = item.nickname.isEmpty
                        ? item.username
                        : item.nickname;
                    final accountText = item.email.trim().isNotEmpty
                        ? item.email.trim()
                        : _safePublicAccountLabel(null, item.username);
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.border),
                        boxShadow: const [AppTheme.cardShadow],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => widget.onOpenAdmin(item.id),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(13),
                                  child: SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: AppNetworkImage(
                                      url: item.avatarUrl,
                                      width: 40,
                                      height: 40,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_) => Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: AppTheme.softViolet,
                                          borderRadius: BorderRadius.circular(
                                            13,
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          name.characters.isEmpty
                                              ? '?'
                                              : name.characters.first,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF6B42A6),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13.5,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '$accountText · ${item.roles.map(_formatRoleName).join('、')}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.textSecondary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '最近操作 ${item.actionCount} 次',
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          color: Color(0xFF8B9FB3),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: Color(0xFF8FA3B8),
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
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
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    future = widget.repository.listAdminCandidates();
    searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    searchController.removeListener(_onSearchChanged);
    searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _search();
    });
  }

  void _search() {
    setState(
      () => future = widget.repository.listAdminCandidates(
        query: searchController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    padding: EdgeInsets.only(
      left: 16,
      right: 16,
      top: 12,
      bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
    ),
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .72,
      child: Column(
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFD4DFE9),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '选择授权用户',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFEDF5FC),
              borderRadius: BorderRadius.circular(13),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(
                  Icons.search_rounded,
                  color: Color(0xFF5E748A),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    style: const TextStyle(fontSize: 12.5),
                    decoration: const InputDecoration(
                      hintText: '搜索用户名、昵称或邮箱',
                      hintStyle: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF8B9FB3),
                      ),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                if (searchController.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      searchController.clear();
                      _search();
                    },
                    child: const Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: Color(0xFF7A8FA5),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
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
                      child: const Text('加载失败，点击重试'),
                    ),
                  );
                }
                final items = snapshot.data ?? const <AdminCandidate>[];
                if (items.isEmpty) {
                  return const Center(
                    child: Text(
                      '没有匹配的可授权用户',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: Color(0xFFEDF2F7)),
                  itemBuilder: (_, index) {
                    final item = items[index];
                    final name = item.nickname.isEmpty
                        ? item.username
                        : item.nickname;
                    final candidateAccount = item.email.trim().isNotEmpty
                        ? item.email.trim()
                        : _safePublicAccountLabel(null, item.username);
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(13),
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: AppNetworkImage(
                            url: item.avatarUrl,
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            errorBuilder: (_) => Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE3EDFB),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                name.characters.isEmpty
                                    ? '?'
                                    : name.characters.first,
                                style: const TextStyle(
                                  color: Color(0xFF2C568D),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                      subtitle: Text(
                        candidateAccount.isEmpty ? '未绑定邮箱' : candidateAccount,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.add_circle_outline_rounded,
                        color: AppTheme.primary,
                        size: 20,
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
                  final confirmedReason = await showDialog<String>(
                    context: context,
                    builder: (dialogContext) => const _RevokeAdminRolesDialog(),
                  );
                  if (confirmedReason == null || !mounted) return;
                  setState(() => saving = true);
                  try {
                    await widget.repository.updateAdminRoles(
                      adminId: widget.adminId,
                      roles: const [],
                      reason: confirmedReason,
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

  String _roleLabel(String value) => _formatRoleName(value);
}

class _RevokeAdminRolesDialog extends StatefulWidget {
  const _RevokeAdminRolesDialog();

  @override
  State<_RevokeAdminRolesDialog> createState() =>
      _RevokeAdminRolesDialogState();
}

class _RevokeAdminRolesDialogState extends State<_RevokeAdminRolesDialog> {
  final controller = TextEditingController();
  String? errorText;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = controller.text.trim();
    if (text.isEmpty) {
      setState(() => errorText = '请填写撤销理由');
      return;
    }
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('撤销全部管理员角色？'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('该用户将失去所有管理后台权限。请填写撤销理由：'),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          maxLines: 2,
          autofocus: true,
          decoration: InputDecoration(
            labelText: '撤销理由（必填）',
            errorText: errorText,
          ),
          onSubmitted: (_) => _submit(),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, null),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('确认撤销')),
    ],
  );
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
      title: const Text('管理员详情'),
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
                  '${data.username}\n${data.email.isEmpty ? '未绑定邮箱' : data.email}\n状态：${_managedStatusLabel(data.status)}',
                ),
                isThreeLine: true,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '已授权角色',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            const SizedBox(height: 8),
            ...data.roles.map(
              (role) => Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.badge_outlined,
                    color: AppTheme.primary,
                  ),
                  title: Text(_formatRoleName(role['name'] ?? '')),
                  subtitle: Text(
                    (role['community_id'] ?? '').isEmpty
                        ? '平台级作用域（全站生效）'
                        : '社区作用域：${role['community_id']}',
                  ),
                ),
              ),
            ),
            if (data.permissions.isNotEmpty) ...[
              const SizedBox(height: 12),
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
                        .map(
                          (permission) => Chip(
                            avatar: const Icon(
                              Icons.check_circle_outline,
                              size: 16,
                            ),
                            label: Text(_formatPermissionName(permission)),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              '最近操作记录',
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
                    leading: const Icon(Icons.history_outlined),
                    title: Text(_formatActionCode(action.action)),
                    subtitle: Text(
                      '${_formatTargetType(action.targetType)}：${action.targetId}\n原因：${action.reason.isEmpty ? '无' : action.reason}',
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
    backgroundColor: AppTheme.background,
    appBar: AppBar(
      title: const Text(
        '风控中心',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
      ),
      backgroundColor: AppTheme.background,
      elevation: 0,
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 36,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(height: 10),
                const Text(
                  '加载风控数据失败',
                  style: TextStyle(color: AppTheme.pink, fontSize: 13),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: () => setState(
                    () => future = widget.repository.getRiskOverview(),
                  ),
                  child: const Text('重新加载'),
                ),
              ],
            ),
          );
        }
        final data = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async =>
              setState(() => future = widget.repository.getRiskOverview()),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 32),
            children: [
              // 3 列指标卡片
              Row(
                children: [
                  Expanded(
                    child: _metricCard(
                      '验证码请求',
                      '${data.codeRequests}',
                      Icons.mail_lock_outlined,
                      AppTheme.softBlue,
                      AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _metricCard(
                      '异常 IP',
                      '${data.abnormalIps}',
                      Icons.public_off_outlined,
                      AppTheme.softViolet,
                      AppTheme.purple,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _metricCard(
                      '自动限制',
                      '${data.automaticRestrictions}',
                      Icons.auto_awesome_outlined,
                      AppTheme.softAmber,
                      AppTheme.orange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  '最近风险事件',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              if (data.events.isEmpty)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.border),
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: 24,
                    horizontal: 16,
                  ),
                  alignment: Alignment.center,
                  child: const Column(
                    children: [
                      Icon(
                        Icons.shield_rounded,
                        size: 32,
                        color: Color(0xFF8B9FB3),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '暂无风险事件',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...data.events.map((event) {
                  final isHigh = event.severity == 'high';
                  final isMed = event.severity == 'medium';
                  final iconBg = isHigh
                      ? AppTheme.softRose
                      : (isMed ? AppTheme.softAmber : AppTheme.softMint);
                  final iconColor = isHigh
                      ? AppTheme.pink
                      : (isMed ? AppTheme.orange : AppTheme.mint);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.border),
                      boxShadow: const [AppTheme.cardShadow],
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: iconBg,
                            borderRadius: BorderRadius.circular(11),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            isHigh
                                ? Icons.error_outline_rounded
                                : Icons.shield_outlined,
                            color: iconColor,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _formatRiskEventType(event.eventType),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${event.ipAddress.isEmpty ? '未知 IP' : event.ipAddress} · ${_formatRiskSeverity(event.severity)}',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                event.eventType,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 10,
                                  color: Color(0xFF91A2B2),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${event.createdAt.hour.toString().padLeft(2, '0')}:${event.createdAt.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                            color: Color(0xFF7190B1),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      },
    ),
  );

  Widget _metricCard(
    String label,
    String value,
    IconData icon,
    Color bg,
    Color iconColor,
  ) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.border),
      boxShadow: const [AppTheme.cardShadow],
    ),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(9),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: iconColor, size: 15),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          label,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10.5),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
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
                  leading: const Icon(
                    Icons.verified_user_outlined,
                    color: AppTheme.primary,
                  ),
                  title: Text(_formatActionCode(item.action)),
                  subtitle: Text(
                    '${_formatTargetType(item.targetType)} #${item.targetId}\n理由：${item.reason.isEmpty ? '无' : item.reason}\nIP：${item.ipAddress.isEmpty ? '未知' : item.ipAddress}\n前序哈希：${_short(item.previousHash)}\n当前哈希：${_short(item.hash)}',
                  ),
                  isThreeLine: true,
                  trailing: Text(
                    '${item.createdAt.month}/${item.createdAt.day} ${item.createdAt.hour.toString().padLeft(2, '0')}:${item.createdAt.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
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
