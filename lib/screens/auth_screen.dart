import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/auth_controller.dart';
import '../data/api/api_client.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

enum _AuthStep { email, code }

/// 现代化多步骤认证入口：邮箱 → 验证码分格校验 → 完善资料与登录。
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
  final emailController = TextEditingController();
  final codeController = TextEditingController();
  final nicknameController = TextEditingController();

  final emailFocusNode = FocusNode();
  final codeFocusNode = FocusNode();

  _AuthStep _currentStep = _AuthStep.email;
  Timer? countdownTimer;
  int retryAfter = 0;
  String? devCode;
  bool isRequestingCode = false;
  bool isLoggingIn = false;
  bool _showNicknameField = false;

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
    emailController.addListener(_onEmailChanged);
  }

  @override
  void dispose() {
    countdownTimer?.cancel();
    emailController.removeListener(_onEmailChanged);
    emailController.dispose();
    codeController.dispose();
    nicknameController.dispose();
    emailFocusNode.dispose();
    codeFocusNode.dispose();
    super.dispose();
  }

  void _onEmailChanged() {
    if (mounted) setState(() {});
  }

  Future<void> requestCode() async {
    final email = emailController.text.trim();
    if (!_looksLikeEmail(email)) {
      _feedback('请输入有效的邮箱地址');
      return;
    }

    setState(() => isRequestingCode = true);
    try {
      final challenge = await widget.controller.requestEmailCode(email);
      if (!mounted) return;

      setState(() {
        isRequestingCode = false;
        if (challenge != null) {
          retryAfter = challenge.retryAfter;
          devCode = challenge.devCode;
        }
        _currentStep = _AuthStep.code;
      });
      _startCountdown();
      // 切换到第二步后自动聚焦验证码
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) codeFocusNode.requestFocus();
      });
    } catch (error) {
      if (mounted) {
        setState(() => isRequestingCode = false);
        _feedback(userFacingApiMessage(error, fallback: '验证码发送失败，请稍后重试'));
      }
    }
  }

  Future<void> submit() async {
    if (_currentStep == _AuthStep.email) {
      await requestCode();
      return;
    }

    final email = emailController.text.trim();
    final code = codeController.text.trim();
    if (code.length != 6) {
      _feedback('请输入 6 位验证码');
      return;
    }

    setState(() => isLoggingIn = true);
    try {
      final success = await widget.controller.loginWithEmailCode(
        email: email,
        code: code,
        nickname: nicknameController.text.trim(),
      );

      if (!mounted) return;
      setState(() => isLoggingIn = false);

      if (success && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
        return;
      }

      if (!success) {
        _feedback(
          userFacingApiMessage(
            widget.controller.error ?? StateError('auth'),
            fallback: '登录失败，请重试',
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => isLoggingIn = false);
        _feedback(userFacingApiMessage(error, fallback: '登录失败，请重试'));
      }
    }
  }

  void _backToEmailStep() {
    countdownTimer?.cancel();
    setState(() {
      _currentStep = _AuthStep.email;
      codeController.clear();
      devCode = null;
      retryAfter = 0;
    });
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) emailFocusNode.requestFocus();
    });
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
                title: '邮箱账号登录（完整体验）',
                desc: '发布帖子、参与投票、收藏精华、关注作者、积分与等级成长。',
              ),
              const SizedBox(height: 12),
              _buildPrivilegeRow(
                icon: Icons.visibility_rounded,
                iconColor: AppTheme.primary,
                title: '游客模式体验',
                desc: '快速浏览社区所有公开内容，发表即时评论与内容举报。',
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
                  child: const Text('我知道了', style: TextStyle(fontWeight: FontWeight.bold)),
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
        isLoggingIn;
    final authError = widget.controller.error;
    final canBrowseAsGuest =
        authError is ApiException &&
        (authError.type == ApiErrorType.networkUnavailable ||
            authError.type == ApiErrorType.timeout);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          // 背景微晕影渐变装饰
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
                      // 顶部返回/退出操作栏
                      Row(
                        children: [
                          if (_currentStep == _AuthStep.code)
                            IconButton(
                              onPressed: busy ? null : _backToEmailStep,
                              icon: const Icon(Icons.arrow_back_ios_new_rounded),
                              color: AppTheme.textPrimary,
                              tooltip: '修改邮箱',
                            )
                          else
                            IconButton(
                              onPressed: busy ? null : widget.onBrowse,
                              icon: const Icon(Icons.close_rounded),
                              color: AppTheme.textSecondary,
                              tooltip: '返回浏览',
                            ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _showPrivilegeDetails,
                            icon: const Icon(Icons.info_outline_rounded, size: 16),
                            label: const Text('权限说明', style: TextStyle(fontSize: 13)),
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // 主卡片容器
                      Container(
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: AppTheme.border.withValues(alpha: 0.6),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF182A3D).withValues(alpha: 0.06),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(28),
                        child: AnimatedSwitcher(
                          duration: AppMotion.page,
                          switchInCurve: AppMotion.standard,
                          switchOutCurve: AppMotion.standard,
                          transitionBuilder: (child, animation) {
                            final isCodeStep = child.key == const ValueKey('step_code');
                            final beginOffset = isCodeStep
                                ? const Offset(0.12, 0.0)
                                : const Offset(-0.12, 0.0);
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: beginOffset,
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: _currentStep == _AuthStep.email
                              ? _buildEmailStep(busy, canBrowseAsGuest)
                              : _buildCodeStep(busy),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // 底部辅助入口
                      if (_currentStep == _AuthStep.email) ...[
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

  /// Step 1: 邮箱输入页面
  Widget _buildEmailStep(bool busy, bool canBrowseAsGuest) {
    final emailText = emailController.text.trim();
    final showSuffixChips = emailText.isNotEmpty && !emailText.contains('@');

    return Column(
      key: const ValueKey('step_email'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 品牌与欢迎徽标
        Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.forum_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '欢迎登录校园论坛',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.textPrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    canBrowseAsGuest
                        ? '网络连接异常，建议重试或以游客体验'
                        : '免密验证码登录，快捷安全',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 28),

        // 邮箱输入框
        const Text(
          '邮箱地址',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: emailController,
          focusNode: emailFocusNode,
          enabled: !busy,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => requestCode(),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: '请输入你的邮箱',
            hintStyle: const TextStyle(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.normal,
              fontSize: 14,
            ),
            prefixIcon: const Icon(Icons.mail_outline_rounded, color: AppTheme.primary),
            suffixIcon: emailText.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.cancel_rounded, size: 18, color: AppTheme.textSecondary),
                    onPressed: busy ? null : () => emailController.clear(),
                  )
                : null,
          ),
        ),

        // 快捷邮箱后缀选择标签
        if (showSuffixChips) ...[
          const SizedBox(height: 10),
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
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    onPressed: busy ? null : () => _applyDomainSuffix(domain),
                  ),
                );
              }).toList(),
            ),
          ),
        ],

        const SizedBox(height: 24),

        // 获取验证码按钮
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: busy ? null : requestCode,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              elevation: 2,
              shadowColor: AppTheme.primary.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '获取验证码',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(width: 6),
                      Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  /// Step 2: 验证码与完善资料页面
  Widget _buildCodeStep(bool busy) {
    final email = emailController.text.trim();
    final code = codeController.text.trim();

    return Column(
      key: const ValueKey('step_code'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题与接收邮箱
        const Text(
          '输入 6 位验证码',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              '已发送至 ',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.surfaceBlue,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                email,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.highlight,
                ),
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              onTap: busy ? null : _backToEmailStep,
              borderRadius: BorderRadius.circular(4),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  '修改',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // 开发环境便捷测试码胶囊
        if (devCode != null && devCode!.isNotEmpty) ...[
          InkWell(
            onTap: busy
                ? null
                : () {
                    codeController.text = devCode!;
                    setState(() {});
                    submit();
                  },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.levelBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.mint.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bolt_rounded, size: 16, color: AppTheme.levelText),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '开发环境验证码: $devCode (点击自动填入)',
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
          const SizedBox(height: 16),
        ],

        // 六位分格验证码输入框
        _PinCodeInput(
          controller: codeController,
          focusNode: codeFocusNode,
          enabled: !busy,
          onCompleted: (val) => submit(),
          onChanged: (val) => setState(() {}),
        ),

        const SizedBox(height: 14),

        // 重新获取倒计时
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: busy || retryAfter > 0 ? null : requestCode,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                foregroundColor: AppTheme.primary,
              ),
              child: Text(
                retryAfter > 0 ? '${retryAfter}s 后可重新获取' : '重新发送验证码',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: retryAfter > 0 ? AppTheme.textSecondary : AppTheme.primary,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () {
                setState(() => _showNicknameField = !_showNicknameField);
              },
              icon: Icon(
                _showNicknameField ? Icons.expand_less_rounded : Icons.add_circle_outline_rounded,
                size: 15,
              ),
              label: Text(
                _showNicknameField ? '收起昵称' : '设置昵称(选填)',
                style: const TextStyle(fontSize: 13),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.textSecondary,
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),

        // 可选昵称展开输入
        if (_showNicknameField) ...[
          const SizedBox(height: 10),
          TextField(
            controller: nicknameController,
            enabled: !busy,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: '起一个独特的昵称吧',
              labelText: '用户昵称 (可选)',
              prefixIcon: Icon(Icons.badge_outlined, color: AppTheme.primary),
              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ],

        const SizedBox(height: 22),

        // 确认登录按钮
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: busy || code.length != 6 ? null : submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              elevation: 2,
              shadowColor: AppTheme.primary.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    '验证并进入论坛',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// 现代化 6 位分格验证码输入组件
class _PinCodeInput extends StatelessWidget {
  const _PinCodeInput({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onCompleted,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final ValueChanged<String> onCompleted;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // 隐藏的真实输入框，负责接收键盘输入、粘贴与数字限制
        Opacity(
          opacity: 0.0,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (val) {
              onChanged(val);
              if (val.length == 6) {
                onCompleted(val);
              }
            },
          ),
        ),

        // 视觉呈现的 6 个独立分格方块
        GestureDetector(
          onTap: () {
            if (enabled) {
              focusNode.requestFocus();
            }
          },
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(6, (index) {
              final text = controller.text;
              final hasChar = index < text.length;
              final char = hasChar ? text[index] : '';
              final isCurrent = index == text.length && focusNode.hasFocus;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 46,
                height: 52,
                decoration: BoxDecoration(
                  color: isCurrent
                      ? Colors.white
                      : hasChar
                      ? AppTheme.surfaceBlue.withValues(alpha: 0.6)
                      : AppTheme.surfaceBlue,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isCurrent
                        ? AppTheme.primary
                        : hasChar
                        ? AppTheme.highlight.withValues(alpha: 0.5)
                        : AppTheme.border.withValues(alpha: 0.8),
                    width: isCurrent ? 2.0 : 1.2,
                  ),
                  boxShadow: isCurrent
                      ? [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  char,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}
