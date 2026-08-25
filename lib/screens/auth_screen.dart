import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/auth_controller.dart';
import '../data/api/api_client.dart';
import '../theme/app_theme.dart';

/// 无密码认证入口：邮箱 → 验证码 → 账号。
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
  Timer? countdownTimer;
  int retryAfter = 0;
  bool codeSent = false;
  String? deliveryHint;

  @override
  void dispose() {
    countdownTimer?.cancel();
    emailController.dispose();
    codeController.dispose();
    nicknameController.dispose();
    super.dispose();
  }

  Future<void> requestCode() async {
    final email = emailController.text.trim();
    if (!_looksLikeEmail(email)) {
      _feedback('请输入有效的邮箱地址');
      return;
    }
    try {
      final challenge = await widget.controller.requestEmailCode(email);
      if (!mounted || challenge == null) return;
      setState(() {
        codeSent = true;
        retryAfter = challenge.retryAfter;
        deliveryHint = challenge.devCode == null
            ? '验证码已发送到 $email'
            : '开发环境验证码：${challenge.devCode}';
      });
      _startCountdown();
    } catch (error) {
      if (mounted)
        _feedback(userFacingApiMessage(error, fallback: '验证码发送失败，请稍后重试'));
    }
  }

  Future<void> submit() async {
    if (!codeSent) {
      await requestCode();
      return;
    }
    final email = emailController.text.trim();
    final code = codeController.text.trim();
    if (code.length != 6) {
      _feedback('请输入 6 位验证码');
      return;
    }
    final success = await widget.controller.loginWithEmailCode(
      email: email,
      code: code,
      nickname: nicknameController.text.trim(),
    );
    if (success && mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    if (!success && mounted) {
      _feedback(
        userFacingApiMessage(
          widget.controller.error ?? StateError('auth'),
          fallback: '登录失败，请重试',
        ),
      );
    }
  }

  Future<void> enterGuest() async {
    if (widget.onGuest != null) {
      widget.onGuest!();
      return;
    }
    final success = await widget.controller.guest();
    if (success && mounted && Navigator.of(context).canPop())
      Navigator.of(context).pop();
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

  void _feedback(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final busy = widget.controller.status == AuthStatus.authenticating;
    final offline = widget.controller.status == AuthStatus.error;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.forum_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    '邮箱验证码登录',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    offline ? '暂时无法连接服务器，可以进入游客模式浏览' : '不设密码，使用邮箱验证码进入校园论坛',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 26),
                  TextField(
                    controller: emailController,
                    enabled: !busy,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '邮箱',
                      prefixIcon: Icon(Icons.mail_outline),
                    ),
                  ),
                  if (codeSent) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: codeController,
                      enabled: !busy,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: InputDecoration(
                        labelText: '验证码',
                        prefixIcon: const Icon(Icons.verified_user_outlined),
                        counterText: '',
                        helperText: deliveryHint,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: nicknameController,
                      enabled: !busy,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: '昵称（可选）',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: busy ? null : submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                      ),
                      child: Text(
                        busy
                            ? '处理中…'
                            : codeSent
                            ? '验证并进入'
                            : '获取验证码',
                      ),
                    ),
                  ),
                  if (codeSent)
                    Center(
                      child: TextButton(
                        onPressed: busy || retryAfter > 0 ? null : requestCode,
                        child: Text(
                          retryAfter > 0 ? '${retryAfter}s 后重新获取' : '重新获取验证码',
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Center(
                    child: TextButton.icon(
                      onPressed: busy ? null : enterGuest,
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('进入游客模式'),
                    ),
                  ),
                  Center(
                    child: TextButton(
                      onPressed: widget.onBrowse,
                      child: const Text('仅浏览公开内容'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
