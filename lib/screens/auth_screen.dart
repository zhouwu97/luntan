import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/auth_controller.dart';
import '../data/api/api_client.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

enum AuthMode { login, register }

enum LoginMethod { code, password }

/// 统一登录/注册认证中心：支持验证码登录、密码登录与新用户注册/游客转正。
class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.controller,
    required this.onBrowse,
    this.onGuest,
  });

  final AuthController controller;
  final VoidCallback onBrowse;
  final VoidCallback? onGuest;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  AuthMode _mode = AuthMode.login;
  LoginMethod _loginMethod = LoginMethod.code;

  final emailController = TextEditingController();
  final codeController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final nicknameController = TextEditingController();

  final emailFocusNode = FocusNode();
  final codeFocusNode = FocusNode();
  final passwordFocusNode = FocusNode();
  final confirmPasswordFocusNode = FocusNode();
  final nicknameFocusNode = FocusNode();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  Timer? countdownTimer;
  int retryAfter = 0;
  String? devCode;
  bool isRequestingCode = false;
  bool isSubmitting = false;

  static const List<String> _suggestedDomains = [
    '@qq.com',
    '@163.com',
    '@gmail.com',
    '@stu.edu.cn',
    '@foxmail.com',
    '@outlook.com',
  ];

  @override
  void initState() {
    super.initState();
    emailController.addListener(_onFieldChanged);
    codeController.addListener(_onFieldChanged);
    passwordController.addListener(_onFieldChanged);
    confirmPasswordController.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    countdownTimer?.cancel();
    emailController.removeListener(_onFieldChanged);
    codeController.removeListener(_onFieldChanged);
    passwordController.removeListener(_onFieldChanged);
    confirmPasswordController.removeListener(_onFieldChanged);

    emailController.dispose();
    codeController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    nicknameController.dispose();

    emailFocusNode.dispose();
    codeFocusNode.dispose();
    passwordFocusNode.dispose();
    confirmPasswordFocusNode.dispose();
    nicknameFocusNode.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  void _switchMode(AuthMode newMode) {
    if (_mode == newMode) return;
    setState(() {
      _mode = newMode;
      codeController.clear();
      passwordController.clear();
      confirmPasswordController.clear();
      devCode = null;
    });
  }

  void _switchLoginMethod(LoginMethod newMethod) {
    if (_loginMethod == newMethod) return;
    setState(() {
      _loginMethod = newMethod;
      codeController.clear();
      passwordController.clear();
      devCode = null;
    });
  }

  Future<void> requestCode() async {
    final email = emailController.text.trim();
    if (!_looksLikeEmail(email)) {
      _feedback('请输入有效的邮箱地址');
      emailFocusNode.requestFocus();
      return;
    }

    final scene = _mode == AuthMode.register ? 'register' : 'login';

    setState(() => isRequestingCode = true);
    try {
      final challenge = await widget.controller.requestEmailCode(
        email,
        scene: scene,
      );
      if (!mounted) return;

      setState(() {
        isRequestingCode = false;
        if (challenge != null) {
          retryAfter = challenge.retryAfter;
          devCode = challenge.devCode;
        }
      });
      _startCountdown();
      _feedback('验证码已发送至你的邮箱');
      codeFocusNode.requestFocus();
    } catch (error) {
      if (!mounted) return;
      setState(() => isRequestingCode = false);
      _handleAuthError(error);
    }
  }

  Future<void> submit() async {
    final email = emailController.text.trim();
    if (!_looksLikeEmail(email)) {
      _feedback('请输入有效的邮箱地址');
      emailFocusNode.requestFocus();
      return;
    }

    if (_mode == AuthMode.login) {
      if (_loginMethod == LoginMethod.code) {
        final code = codeController.text.trim();
        if (code.length != 6) {
          _feedback('请输入 6 位数字验证码');
          codeFocusNode.requestFocus();
          return;
        }

        setState(() => isSubmitting = true);
        try {
          final success = await widget.controller.loginWithEmailCode(
            email: email,
            code: code,
          );
          if (!mounted) return;
          setState(() => isSubmitting = false);
          if (success) {
            _onAuthSuccess();
          } else {
            _handleAuthError(widget.controller.error ?? StateError('login'));
          }
        } catch (error) {
          if (!mounted) return;
          setState(() => isSubmitting = false);
          _handleAuthError(error);
        }
      } else {
        // 密码登录
        final password = passwordController.text;
        if (password.isEmpty) {
          _feedback('请输入密码');
          passwordFocusNode.requestFocus();
          return;
        }

        setState(() => isSubmitting = true);
        try {
          final success = await widget.controller.loginWithPassword(
            email: email,
            password: password,
          );
          if (!mounted) return;
          setState(() => isSubmitting = false);
          if (success) {
            _onAuthSuccess();
          } else {
            _handleAuthError(widget.controller.error ?? StateError('login'));
          }
        } catch (error) {
          if (!mounted) return;
          setState(() => isSubmitting = false);
          _handleAuthError(error);
        }
      }
    } else {
      // 注册流程
      final code = codeController.text.trim();
      if (code.length != 6) {
        _feedback('请输入 6 位数字验证码');
        codeFocusNode.requestFocus();
        return;
      }
      final password = passwordController.text;
      if (password.length < 8) {
        _feedback('密码长度不能少于 8 位');
        passwordFocusNode.requestFocus();
        return;
      }
      final confirmPassword = confirmPasswordController.text;
      if (password != confirmPassword) {
        _feedback('两次输入的密码不一致，请重新输入');
        confirmPasswordFocusNode.requestFocus();
        return;
      }

      setState(() => isSubmitting = true);
      try {
        final success = await widget.controller.register(
          email: email,
          code: code,
          password: password,
          nickname: nicknameController.text.trim(),
        );
        if (!mounted) return;
        setState(() => isSubmitting = false);
        if (success) {
          _onAuthSuccess();
        } else {
          _handleAuthError(widget.controller.error ?? StateError('register'));
        }
      } catch (error) {
        if (!mounted) return;
        setState(() => isSubmitting = false);
        _handleAuthError(error);
      }
    }
  }

  void _onAuthSuccess() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _handleAuthError(Object error) {
    if (error is ApiException) {
      if (error.code == 'EMAIL_NOT_REGISTERED') {
        _feedbackWithAction(
          '该邮箱尚未注册，请先注册',
          actionLabel: '去注册',
          onAction: () => _switchMode(AuthMode.register),
        );
        return;
      }
      if (error.code == 'EMAIL_ALREADY_REGISTERED') {
        _feedbackWithAction(
          '该邮箱已注册，请直接登录',
          actionLabel: '去登录',
          onAction: () => _switchMode(AuthMode.login),
        );
        return;
      }
    }
    _feedback(userFacingApiMessage(error, fallback: '操作失败，请稍后重试'));
  }

  Future<void> enterGuest() async {
    if (widget.onGuest != null) {
      widget.onGuest!();
      return;
    }
    final success = await widget.controller.guest();
    if (success && mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _startCountdown() {
    countdownTimer?.cancel();
    countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (retryAfter <= 1) {
        countdownTimer?.cancel();
        setState(() => retryAfter = 0);
      } else {
        setState(() => retryAfter--);
      }
    });
  }

  bool _looksLikeEmail(String value) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);

  void _feedback(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _feedbackWithAction(
    String message, {
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: actionLabel,
          textColor: AppTheme.sky,
          onPressed: onAction,
        ),
      ),
    );
  }

  void _applyDomainSuffix(String suffix) {
    final current = emailController.text.trim();
    final atIndex = current.indexOf('@');
    if (atIndex >= 0) {
      final prefix = current.substring(0, atIndex);
      emailController.text = '$prefix$suffix';
    } else {
      emailController.text = '$current$suffix';
    }
    emailController.selection = TextSelection.fromPosition(
      TextPosition(offset: emailController.text.length),
    );
  }

  void _showPrivilegeDetails() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                '账号权限说明',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 14),
              _buildPrivilegeRow(
                icon: Icons.check_circle_rounded,
                iconColor: AppTheme.mint,
                title: '正式邮箱账号（完整体验）',
                desc: '发布帖子、参与投票、收藏精华、关注作者、积分与等级成长。',
              ),
              const SizedBox(height: 12),
              _buildPrivilegeRow(
                icon: Icons.visibility_rounded,
                iconColor: AppTheme.primary,
                title: '游客模式体验',
                desc: '快速浏览社区所有公开内容，发表即时评论与内容举报；经验正常累计，注册后一键原地转正。',
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.surfaceBlue,
                    foregroundColor: AppTheme.primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    '我知道了',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrivilegeRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 20, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy =
        widget.controller.status == AuthStatus.authenticating ||
        isRequestingCode ||
        isSubmitting;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          // 背景装饰微光
          Positioned(
            top: -100,
            right: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.sky.withValues(alpha: 0.25),
                    AppTheme.sky.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            left: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.primary.withValues(alpha: 0.15),
                    AppTheme.primary.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 顶部导航栏
                      Row(
                        children: [
                          IconButton(
                            onPressed: busy ? null : widget.onBrowse,
                            icon: const Icon(Icons.close_rounded),
                            color: AppTheme.textSecondary,
                            tooltip: '返回浏览',
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _showPrivilegeDetails,
                            icon: const Icon(
                              Icons.info_outline_rounded,
                              size: 16,
                            ),
                            label: const Text(
                              '权限说明',
                              style: TextStyle(fontSize: 13),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // 主认证卡片
                      Container(
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: AppTheme.border.withValues(alpha: 0.6),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF182A3D,
                              ).withValues(alpha: 0.06),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 标题与品牌标
                            _buildHeader(),
                            const SizedBox(height: 20),

                            // 主 Tab: 登录 / 注册
                            _buildPrimaryTabs(busy),
                            const SizedBox(height: 18),

                            // 登录模式下的二级 Switcher：验证码登录 / 密码登录
                            if (_mode == AuthMode.login) ...[
                              _buildLoginMethodSwitcher(busy),
                              const SizedBox(height: 18),
                            ],

                            // 表单内容
                            AnimatedSwitcher(
                              duration: AppMotion.page,
                              switchInCurve: AppMotion.standard,
                              switchOutCurve: AppMotion.standard,
                              child: _mode == AuthMode.login
                                  ? (_loginMethod == LoginMethod.code
                                      ? _buildCodeLoginForm(busy)
                                      : _buildPasswordLoginForm(busy))
                                  : _buildRegisterForm(busy),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // 底部辅助入口
                      OutlinedButton.icon(
                        onPressed: busy ? null : enterGuest,
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        label: const Text(
                          '暂不登录，以游客身份体验',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.textPrimary,
                          side: BorderSide(
                            color: AppTheme.border.withValues(alpha: 0.8),
                          ),
                          backgroundColor: Colors.white.withValues(alpha: 0.8),
                          minimumSize: const Size(double.infinity, 46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: widget.onBrowse,
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.textSecondary,
                        ),
                        child: const Text('返回浏览公开帖子'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.forum_rounded,
            color: Colors.white,
            size: 26,
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '欢迎来到校园论坛',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
              SizedBox(height: 2),
              Text(
                '登录账号或创建新的账号',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPrimaryTabs(bool busy) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlue.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTabItem(
              title: '登录',
              isActive: _mode == AuthMode.login,
              onTap: busy ? null : () => _switchMode(AuthMode.login),
            ),
          ),
          Expanded(
            child: _buildTabItem(
              title: '注册',
              isActive: _mode == AuthMode.register,
              onTap: busy ? null : () => _switchMode(AuthMode.register),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabItem({
    required String title,
    required bool isActive,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
            color: isActive ? AppTheme.primary : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildLoginMethodSwitcher(bool busy) {
    return Row(
      children: [
        _buildSubTabButton(
          title: '验证码登录',
          isActive: _loginMethod == LoginMethod.code,
          onTap: busy ? null : () => _switchLoginMethod(LoginMethod.code),
        ),
        const SizedBox(width: 8),
        _buildSubTabButton(
          title: '密码登录',
          isActive: _loginMethod == LoginMethod.password,
          onTap: busy ? null : () => _switchLoginMethod(LoginMethod.password),
        ),
      ],
    );
  }

  Widget _buildSubTabButton({
    required String title,
    required bool isActive,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? AppTheme.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color: isActive ? AppTheme.primary : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildEmailField(bool busy) {
    final emailText = emailController.text.trim();
    final showSuffixChips = emailText.isNotEmpty && !emailText.contains('@');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '邮箱',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: emailController,
          focusNode: emailFocusNode,
          enabled: !busy,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: '请输入邮箱地址',
            hintStyle: const TextStyle(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.normal,
              fontSize: 14,
            ),
            prefixIcon: const Icon(
              Icons.mail_outline_rounded,
              color: AppTheme.primary,
              size: 20,
            ),
            suffixIcon: emailText.isNotEmpty
                ? IconButton(
                    icon: const Icon(
                      Icons.cancel_rounded,
                      size: 18,
                      color: AppTheme.textSecondary,
                    ),
                    onPressed: busy ? null : () => emailController.clear(),
                  )
                : null,
          ),
        ),
        if (showSuffixChips) ...[
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _suggestedDomains.map((domain) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    label: Text(
                      domain,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.highlight,
                      ),
                    ),
                    backgroundColor: AppTheme.surfaceBlue,
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 0,
                    ),
                    onPressed: busy ? null : () => _applyDomainSuffix(domain),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCodeField(bool busy) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '验证码',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: codeController,
          focusNode: codeFocusNode,
          enabled: !busy,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => submit(),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.0,
            color: AppTheme.textPrimary,
          ),
          decoration: InputDecoration(
            counterText: '',
            hintText: '请输入 6 位验证码',
            hintStyle: const TextStyle(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.normal,
              fontSize: 14,
              letterSpacing: 0,
            ),
            prefixIcon: const Icon(
              Icons.dialpad_rounded,
              color: AppTheme.primary,
              size: 20,
            ),
            suffixIcon: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: TextButton(
                onPressed: busy || retryAfter > 0 ? null : requestCode,
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: isRequestingCode
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        retryAfter > 0 ? '${retryAfter}s 后重发' : '获取验证码',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: retryAfter > 0
                              ? AppTheme.textSecondary
                              : AppTheme.primary,
                        ),
                      ),
              ),
            ),
          ),
        ),
        if (devCode != null && devCode!.isNotEmpty) ...[
          const SizedBox(height: 8),
          InkWell(
            onTap: busy
                ? null
                : () {
                    codeController.text = devCode!;
                    setState(() {});
                  },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.levelBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.mint.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.bolt_rounded,
                    size: 15,
                    color: AppTheme.levelText,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '开发环境验证码: $devCode (点击填入)',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.levelText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// 1. 验证码登录表单
  Widget _buildCodeLoginForm(bool busy) {
    return Column(
      key: const ValueKey('form_code_login'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildEmailField(busy),
        const SizedBox(height: 16),
        _buildCodeField(busy),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: busy ? null : submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              elevation: 2,
              shadowColor: AppTheme.primary.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    '登录并进入论坛',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ],
    );
  }

  /// 2. 密码登录表单
  Widget _buildPasswordLoginForm(bool busy) {
    return Column(
      key: const ValueKey('form_password_login'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildEmailField(busy),
        const SizedBox(height: 16),
        const Text(
          '密码',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: passwordController,
          focusNode: passwordFocusNode,
          enabled: !busy,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => submit(),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: '请输入密码',
            hintStyle: const TextStyle(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.normal,
              fontSize: 14,
            ),
            prefixIcon: const Icon(
              Icons.lock_outline_rounded,
              color: AppTheme.primary,
              size: 20,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                size: 20,
                color: AppTheme.textSecondary,
              ),
              onPressed: () {
                setState(() => _obscurePassword = !_obscurePassword);
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: busy
                ? null
                : () => _switchLoginMethod(LoginMethod.code),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
              padding: EdgeInsets.zero,
            ),
            child: const Text(
              '忘记密码？使用验证码登录',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: busy ? null : submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              elevation: 2,
              shadowColor: AppTheme.primary.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    '登录',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ],
    );
  }

  /// 3. 注册表单
  Widget _buildRegisterForm(bool busy) {
    return Column(
      key: const ValueKey('form_register'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildEmailField(busy),
        const SizedBox(height: 14),
        _buildCodeField(busy),
        const SizedBox(height: 14),
        const Text(
          '设置密码',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: passwordController,
          focusNode: passwordFocusNode,
          enabled: !busy,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.next,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: '至少 8 位密码',
            hintStyle: const TextStyle(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.normal,
              fontSize: 14,
            ),
            prefixIcon: const Icon(
              Icons.lock_outline_rounded,
              color: AppTheme.primary,
              size: 20,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                size: 20,
                color: AppTheme.textSecondary,
              ),
              onPressed: () {
                setState(() => _obscurePassword = !_obscurePassword);
              },
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          '确认密码',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: confirmPasswordController,
          focusNode: confirmPasswordFocusNode,
          enabled: !busy,
          obscureText: _obscureConfirmPassword,
          textInputAction: TextInputAction.next,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: '再次输入密码',
            hintStyle: const TextStyle(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.normal,
              fontSize: 14,
            ),
            prefixIcon: const Icon(
              Icons.lock_reset_rounded,
              color: AppTheme.primary,
              size: 20,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirmPassword
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                size: 20,
                color: AppTheme.textSecondary,
              ),
              onPressed: () {
                setState(
                  () => _obscureConfirmPassword = !_obscureConfirmPassword,
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          '昵称（选填）',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: nicknameController,
          focusNode: nicknameFocusNode,
          enabled: !busy,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => submit(),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
          decoration: const InputDecoration(
            hintText: '给自己起一个昵称',
            hintStyle: TextStyle(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.normal,
              fontSize: 14,
            ),
            prefixIcon: Icon(
              Icons.badge_outlined,
              color: AppTheme.primary,
              size: 20,
            ),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: busy ? null : submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              elevation: 2,
              shadowColor: AppTheme.primary.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    '注册并进入论坛',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ],
    );
  }
}
