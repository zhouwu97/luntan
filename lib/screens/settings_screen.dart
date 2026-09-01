import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_update_sheet.dart';
import '../controllers/app_update_coordinator.dart';
import '../theme/app_theme.dart';
import '../widgets/app_network_image.dart';

/// 个人中心的完整设置页。
///
/// 设置项只接收页面实际支持的回调，避免展示点击后没有行为的“假入口”。
class SettingsCenterScreen extends StatelessWidget {
  const SettingsCenterScreen({
    super.key,
    required this.onOpenMessages,
    required this.onFeedback,
    this.isGuest = false,
    this.accountSubtitle,
    this.accountDisplayName,
    this.accountAvatarUrl,
    this.onRequireAuth,
    this.onOpenGovernance,
    this.onOpenAppeals,
    this.onOpenAccountStatus,
    this.onChangePassword,
    this.onClearHistory,
    this.onLogout,
    this.onDeleteAccount,
    this.updateCoordinator,
  });

  final VoidCallback onOpenMessages;
  final ValueChanged<String> onFeedback;
  final bool isGuest;
  final String? accountSubtitle;
  final String? accountDisplayName;
  final String? accountAvatarUrl;
  final VoidCallback? onRequireAuth;
  final VoidCallback? onOpenGovernance;
  final VoidCallback? onOpenAppeals;
  final VoidCallback? onOpenAccountStatus;
  final VoidCallback? onChangePassword;
  final Future<void> Function()? onClearHistory;
  final Future<void> Function()? onLogout;
  final Future<void> Function()? onDeleteAccount;
  final AppUpdateCoordinator? updateCoordinator;

  @override
  Widget build(BuildContext context) {
    final email = accountSubtitle ?? (isGuest ? '未绑定邮箱 · 游客体验' : '已登录账号');
    final isEmailVerified =
        !isGuest && accountSubtitle != null && accountSubtitle!.contains('@');

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text(
          '设置',
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
          // 1. 账号卡片
          const _SectionHeader(title: '账号'),
          _AccountHeaderCard(
            isGuest: isGuest,
            email: email,
            isVerified: isEmailVerified,
            avatarUrl: accountAvatarUrl,
            displayName: accountDisplayName ?? '圣',
            onTap: isGuest ? onRequireAuth : null,
          ),
          const SizedBox(height: 16),

          // 2. 账号与安全
          if (!isGuest && onChangePassword != null) ...[
            const _SectionHeader(title: '账号与安全'),
            _SettingsSection(
              children: [
                _SettingsRow(
                  icon: Icons.lock_reset_rounded,
                  iconBg: AppTheme.softBlue,
                  iconColor: AppTheme.primary,
                  title: '修改密码',
                  subtitle: '使用当前密码或邮箱验证码验证身份',
                  onTap: onChangePassword,
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // 3. 内容与隐私
          const _SectionHeader(title: '内容与隐私'),
          _SettingsSection(
            children: [
              _SettingsRow(
                icon: Icons.notifications_none_rounded,
                iconBg: AppTheme.softBlue,
                iconColor: AppTheme.primary,
                title: '通知中心',
                subtitle: '回复、点赞、社区与账号通知',
                onTap: onOpenMessages,
              ),
              _SettingsRow(
                icon: Icons.shield_outlined,
                iconBg: AppTheme.softMint,
                iconColor: AppTheme.mint,
                title: '隐私与安全',
                subtitle: '公开内容、账号数据与设备存储说明',
                onTap: () => _showPrivacyDialog(context),
              ),
              if (onClearHistory != null)
                _SettingsRow(
                  icon: Icons.history_rounded,
                  iconBg: AppTheme.softViolet,
                  iconColor: AppTheme.purple,
                  title: '清空浏览历史',
                  subtitle: '删除当前账号保存的浏览记录',
                  onTap: () => _confirmClearHistory(context),
                ),
            ],
          ),

          // 4. 社区管理 (权限动态展示)
          if (onOpenGovernance != null ||
              onOpenAppeals != null ||
              onOpenAccountStatus != null) ...[
            const SizedBox(height: 16),
            const _SectionHeader(title: '社区管理'),
            _SettingsSection(
              children: [
                if (onOpenGovernance != null)
                  _SettingsRow(
                    icon: Icons.gavel_rounded,
                    iconBg: AppTheme.softBlue,
                    iconColor: AppTheme.primary,
                    title: '治理中心',
                    subtitle: '审核、申诉、推荐、活动与权限管理',
                    onTap: onOpenGovernance,
                  ),
                if (onOpenAppeals != null)
                  _SettingsRow(
                    icon: Icons.rate_review_outlined,
                    iconBg: AppTheme.softAmber,
                    iconColor: AppTheme.orange,
                    title: '我的申诉',
                    subtitle: '查看已提交的申诉及处理结果',
                    onTap: onOpenAppeals,
                  ),
                if (onOpenAccountStatus != null)
                  _SettingsRow(
                    icon: Icons.shield_outlined,
                    iconBg: AppTheme.softRose,
                    iconColor: AppTheme.pink,
                    title: '账号处罚详情',
                    subtitle: '当前限制、处罚原因与历史记录',
                    onTap: onOpenAccountStatus,
                  ),
              ],
            ),
          ],

          // 5. 关于
          const SizedBox(height: 16),
          const _SectionHeader(title: '关于'),
          _SettingsSection(
            children: [
              _UpdateRow(
                onFeedback: onFeedback,
                updateCoordinator: updateCoordinator,
              ),
              _SettingsRow(
                icon: Icons.info_outline_rounded,
                iconBg: AppTheme.softViolet,
                iconColor: AppTheme.purple,
                title: '关于圣杯酱',
                subtitle: '社区规则、版本信息与反馈',
                onTap: () => _showAboutDialog(context),
              ),
            ],
          ),

          // 6. 账号操作
          if (onLogout != null || onDeleteAccount != null) ...[
            const SizedBox(height: 16),
            const _SectionHeader(title: '账号操作'),
            if (onLogout != null)
              _ActionCardButton(
                title: '退出登录',
                isDanger: true,
                onTap: () => _confirmLogout(context),
              ),
            if (onDeleteAccount != null) ...[
              const SizedBox(height: 10),
              _ActionCardButton(
                title: '注销账号',
                subtitle: '账号、认证信息和互动数据将被彻底清理',
                isDanger: true,
                onTap: () => _deleteAccount(context),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _confirmClearHistory(BuildContext context) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              '清空浏览历史',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            content: const Text(
              '将删除当前账号保存的浏览记录，此操作不可撤销。',
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: AppTheme.textSecondary,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text(
                  '取消',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.pink,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('确认清空'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !context.mounted) return;

    try {
      await onClearHistory?.call();
      if (context.mounted) onFeedback('浏览历史已清空');
    } catch (_) {
      if (context.mounted) onFeedback('清空浏览历史失败，请稍后重试');
    }
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              '退出登录',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            content: const Text(
              '退出后需要重新验证账号才能访问个人数据。',
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: AppTheme.textSecondary,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text(
                  '取消',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.pink,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('确认退出'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !context.mounted) return;
    Navigator.of(context).pop();
    await onLogout?.call();
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              '确认注销账号？',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            content: const Text(
              '账号、认证信息、互动和通知将被清理，且无法恢复。请确认你已备份需要保留的内容。',
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: AppTheme.textSecondary,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text(
                  '取消',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.pink,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('继续注销'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;
    Navigator.of(context).pop();
    try {
      await onDeleteAccount?.call();
    } catch (_) {
      if (context.mounted) onFeedback('注销失败，请稍后重试');
    }
  }

  void _showPrivacyDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          '隐私与安全',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        content: const Text(
          '公开帖子和评论会展示给社区成员。登录凭证保存在设备安全存储中；浏览历史用于账号体验。只有在你主动提交资料、评论或举报时，相关内容才会发送到服务器。',
          style: TextStyle(
            fontSize: 13,
            height: 1.65,
            color: AppTheme.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              '知道了',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.softBlue,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: const Text(
                '圣',
                style: TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              '关于圣杯酱',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
          ],
        ),
        content: const Text(
          '圣杯酱 · 玩具交流轻社区\n\n遵循友好、诚实与克制的社区原则。保持轻量设计，无打扰通知与无意义冗余。感谢每一位热爱分享的同好！',
          style: TextStyle(
            fontSize: 13,
            height: 1.65,
            color: AppTheme.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              '确定',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
      child: Text(
        title,
        style: const TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AccountHeaderCard extends StatelessWidget {
  const _AccountHeaderCard({
    required this.isGuest,
    required this.email,
    required this.isVerified,
    this.avatarUrl,
    this.displayName = '圣',
    this.onTap,
  });

  final bool isGuest;
  final String email;
  final bool isVerified;
  final String? avatarUrl;
  final String displayName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fallbackChar = isGuest
        ? '游'
        : (displayName.trim().isNotEmpty
              ? displayName.trim().characters.first
              : '圣');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDCE9F7)),
        boxShadow: const [AppTheme.cardShadow],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                // 头像
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: AppNetworkImage(
                      url: avatarUrl,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (_) => Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6F9FFF), Color(0xFF5483ED)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          fallbackChar,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 账号信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isGuest ? '游客体验' : '当前账号',
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        email,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isVerified
                              ? const Color(0xFFE4F7F1)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isVerified ? '已验证' : (isGuest ? '登录 / 绑定邮箱' : '正常状态'),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isVerified
                                ? const Color(0xFF2E8A76)
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTap != null)
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF7089A2),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.children});
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

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                // 语义色底图标
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
                // 标题与副描述
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.textSecondary,
                            height: 1.35,
                          ),
                        ),
                      ],
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

class _UpdateRow extends StatefulWidget {
  const _UpdateRow({required this.onFeedback, this.updateCoordinator});

  final ValueChanged<String> onFeedback;
  final AppUpdateCoordinator? updateCoordinator;

  @override
  State<_UpdateRow> createState() => _UpdateRowState();
}

class _UpdateRowState extends State<_UpdateRow> {
  String _versionLabel = '正在读取版本';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _versionLabel = '当前版本 v${info.version}');
    } catch (_) {
      if (!mounted) return;
      setState(() => _versionLabel = '点击检查是否有新版本');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsRow(
      icon: Icons.system_update_alt_rounded,
      iconBg: AppTheme.softBlue,
      iconColor: AppTheme.primary,
      title: '检查更新',
      subtitle: _versionLabel,
      onTap: () =>
          showAppUpdateSheet(context, coordinator: widget.updateCoordinator),
    );
  }
}

class _ActionCardButton extends StatelessWidget {
  const _ActionCardButton({
    required this.title,
    this.subtitle,
    this.isDanger = false,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final bool isDanger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDanger ? const Color(0xFFF0DDE1) : AppTheme.border,
        ),
        boxShadow: const [AppTheme.cardShadow],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Column(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDanger
                        ? const Color(0xFFCB6374)
                        : AppTheme.textPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
