import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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
    this.onRequireAuth,
    this.onOpenGovernance,
    this.onOpenAppeals,
    this.onOpenAccountStatus,
    this.onClearHistory,
    this.onLogout,
    this.onDeleteAccount,
  });

  final VoidCallback onOpenMessages;
  final ValueChanged<String> onFeedback;
  final bool isGuest;
  final String? accountSubtitle;
  final VoidCallback? onRequireAuth;
  final VoidCallback? onOpenGovernance;
  final VoidCallback? onOpenAppeals;
  final VoidCallback? onOpenAccountStatus;
  final Future<void> Function()? onClearHistory;
  final Future<void> Function()? onLogout;
  final Future<void> Function()? onDeleteAccount;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
        children: [
          _SettingsSection(
            title: '账号',
            children: [
              if (isGuest)
                _SettingsTile(
                  icon: Icons.mail_outline_rounded,
                  title: '登录 / 绑定邮箱',
                  subtitle: '登录后可保存收藏、关注和个人数据',
                  color: AppTheme.primary,
                  onTap: onRequireAuth,
                )
              else
                _SettingsTile(
                  icon: Icons.account_circle_outlined,
                  title: '当前账号',
                  subtitle: accountSubtitle ?? '当前账号已登录',
                  color: AppTheme.primary,
                ),
            ],
          ),
          const SizedBox(height: 14),
          _SettingsSection(
            title: '内容与隐私',
            children: [
              _SettingsTile(
                icon: Icons.notifications_none_rounded,
                title: '通知中心',
                subtitle: '查看回复、系统和账号通知',
                onTap: onOpenMessages,
              ),
              _SettingsTile(
                icon: Icons.shield_outlined,
                title: '隐私与安全',
                subtitle: '了解公开内容和账号数据的使用方式',
                onTap: () => _showPrivacyDialog(context),
              ),
              if (onClearHistory != null)
                _SettingsTile(
                  icon: Icons.history_rounded,
                  title: '清空浏览历史',
                  subtitle: '删除当前账号保存的浏览记录',
                  onTap: () => _clearHistory(context),
                ),
            ],
          ),
          if (onOpenGovernance != null ||
              onOpenAppeals != null ||
              onOpenAccountStatus != null) ...[
            const SizedBox(height: 14),
            _SettingsSection(
              title: '社区管理',
              children: [
                if (onOpenGovernance != null)
                  _SettingsTile(
                    icon: Icons.gavel_outlined,
                    title: '治理中心',
                    subtitle: '审核、申诉、推荐、风控与权限管理',
                    color: AppTheme.primary,
                    onTap: onOpenGovernance,
                  ),
                if (onOpenAppeals != null)
                  _SettingsTile(
                    icon: Icons.rate_review_outlined,
                    title: '我的申诉',
                    subtitle: '查看已提交的申诉及处理结果',
                    onTap: onOpenAppeals,
                  ),
                if (onOpenAccountStatus != null)
                  _SettingsTile(
                    icon: Icons.account_balance_outlined,
                    title: '账号处罚详情',
                    subtitle: '查看账号当前限制和历史处理记录',
                    onTap: onOpenAccountStatus,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          _SettingsSection(
            title: '关于',
            children: [
              _SettingsTile(
                icon: Icons.info_outline_rounded,
                title: '关于杯友酱',
                subtitle: '版本 v1.0.0 · 社区规则与反馈',
                onTap: () => onFeedback('当前版本 v1.0.0'),
              ),
            ],
          ),
          if (onLogout != null || onDeleteAccount != null) ...[
            const SizedBox(height: 14),
            _SettingsSection(
              title: '账号操作',
              children: [
                if (onLogout != null)
                  _SettingsTile(
                    icon: Icons.logout_rounded,
                    title: '退出登录',
                    color: AppTheme.pink,
                    onTap: () => _logout(context),
                  ),
                if (onDeleteAccount != null)
                  _SettingsTile(
                    icon: Icons.person_off_outlined,
                    title: '注销账号',
                    subtitle: '账号、认证信息和互动数据将被清理',
                    color: AppTheme.pink,
                    onTap: () => _deleteAccount(context),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _clearHistory(BuildContext context) async {
    try {
      await onClearHistory?.call();
      if (context.mounted) onFeedback('浏览历史已清空');
    } catch (_) {
      if (context.mounted) onFeedback('清空浏览历史失败，请稍后重试');
    }
  }

  Future<void> _logout(BuildContext context) async {
    Navigator.of(context).pop();
    await onLogout?.call();
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('确认注销账号？'),
            content: const Text('账号、认证信息、互动和通知将被清理，且无法恢复。请确认你已备份需要保留的内容。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
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
        title: const Text('隐私与安全'),
        content: const Text(
          '公开帖子和评论会展示给社区成员。登录凭证会保存在设备安全存储中；游客可以浏览、评论和举报，登录邮箱账号后才能保存个人数据。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
        child: Text(
          title,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      Material(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      ),
    ],
  );
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.color,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: color ?? AppTheme.textSecondary),
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle!),
    trailing: onTap == null
        ? null
        : const Icon(
            Icons.chevron_right_rounded,
            color: AppTheme.textSecondary,
          ),
    onTap: onTap,
  );
}
