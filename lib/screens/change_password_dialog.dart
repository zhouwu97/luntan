import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/auth_controller.dart';
import '../data/api/api_client.dart';
import '../theme/app_theme.dart';

enum _PasswordVerificationMethod { currentPassword, emailCode }

/// 已登录账号的改密弹窗：支持当前密码和当前账号邮箱验证码两种验证方式。
class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({
    super.key,
    required this.controller,
    required this.email,
    this.onSuccess,
  });

  final AuthController controller;
  final String email;
  final VoidCallback? onSuccess;

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final formKey = GlobalKey<FormState>();
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final currentPasswordController = TextEditingController();
  final emailCodeController = TextEditingController();
  final emailCodeFocusNode = FocusNode();

  Timer? countdownTimer;
  _PasswordVerificationMethod verificationMethod =
      _PasswordVerificationMethod.currentPassword;
  int retryAfter = 0;
  bool requestingCode = false;
  bool submitting = false;
  bool obscureNewPassword = true;
  bool obscureConfirmPassword = true;
  bool obscureCurrentPassword = true;
  String? errorMessage;

  @override
  void dispose() {
    countdownTimer?.cancel();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    currentPasswordController.dispose();
    emailCodeController.dispose();
    emailCodeFocusNode.dispose();
    super.dispose();
  }

  void selectVerificationMethod(_PasswordVerificationMethod method) {
    if (verificationMethod == method || submitting) return;
    setState(() {
      verificationMethod = method;
      errorMessage = null;
    });
  }

  Future<void> requestEmailCode() async {
    if (requestingCode || retryAfter > 0 || submitting) return;
    setState(() {
      requestingCode = true;
      errorMessage = null;
    });
    try {
      final challenge = await widget.controller.requestEmailCode(
        widget.email,
        scene: 'password_reset',
      );
      if (!mounted) return;
      setState(() {
        requestingCode = false;
        retryAfter = challenge?.retryAfter ?? 60;
      });
      startCountdown();
      emailCodeFocusNode.requestFocus();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        requestingCode = false;
        errorMessage = userFacingApiMessage(error, fallback: '验证码发送失败，请稍后重试');
      });
    }
  }

  void startCountdown() {
    countdownTimer?.cancel();
    countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (retryAfter <= 1) {
        countdownTimer?.cancel();
        setState(() => retryAfter = 0);
        return;
      }
      setState(() => retryAfter -= 1);
    });
  }

  String? validateNewPassword(String? value) {
    if (value == null || value.isEmpty) return '请输入新密码';
    if (value.runes.length < 8) return '密码长度不能少于 8 位';
    return null;
  }

  String? validateConfirmPassword(String? value) {
    if (value != newPasswordController.text) return '两次输入的密码不一致';
    return null;
  }

  String? validateCurrentPassword(String? value) {
    if (verificationMethod == _PasswordVerificationMethod.currentPassword &&
        (value == null || value.isEmpty)) {
      return '请输入当前密码';
    }
    return null;
  }

  String? validateEmailCode(String? value) {
    if (verificationMethod != _PasswordVerificationMethod.emailCode) {
      return null;
    }
    if (value == null || !RegExp(r'^\d{6}$').hasMatch(value.trim())) {
      return '请输入 6 位数字验证码';
    }
    return null;
  }

  Future<void> submit() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    setState(() {
      submitting = true;
      errorMessage = null;
    });
    try {
      await widget.controller.setPassword(
        password: newPasswordController.text,
        currentPassword:
            verificationMethod == _PasswordVerificationMethod.currentPassword
            ? currentPasswordController.text
            : null,
        emailCode: verificationMethod == _PasswordVerificationMethod.emailCode
            ? emailCodeController.text.trim()
            : null,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSuccess?.call();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        submitting = false;
        errorMessage = userFacingApiMessage(error, fallback: '密码修改失败，请稍后重试');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final maskedEmail = _maskedEmail(widget.email);
    return AlertDialog(
      scrollable: false,
      title: const Text('修改密码', style: TextStyle(fontWeight: FontWeight.w800)),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 440,
          maxHeight: MediaQuery.sizeOf(context).height * 0.68,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '修改成功后，其他设备将退出登录。邮箱验证码仅发送到当前账号的已验证邮箱。',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: newPasswordController,
                  enabled: !submitting,
                  obscureText: obscureNewPassword,
                  validator: validateNewPassword,
                  textInputAction: TextInputAction.next,
                  decoration: _inputDecoration(
                    labelText: '新密码（至少 8 位）',
                    icon: Icons.lock_outline_rounded,
                    suffixIcon: IconButton(
                      tooltip: obscureNewPassword ? '显示密码' : '隐藏密码',
                      onPressed: () => setState(
                        () => obscureNewPassword = !obscureNewPassword,
                      ),
                      icon: Icon(
                        obscureNewPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: confirmPasswordController,
                  enabled: !submitting,
                  obscureText: obscureConfirmPassword,
                  validator: validateConfirmPassword,
                  textInputAction: TextInputAction.next,
                  decoration: _inputDecoration(
                    labelText: '确认新密码',
                    icon: Icons.lock_outline_rounded,
                    suffixIcon: IconButton(
                      tooltip: obscureConfirmPassword ? '显示密码' : '隐藏密码',
                      onPressed: () => setState(
                        () => obscureConfirmPassword = !obscureConfirmPassword,
                      ),
                      icon: Icon(
                        obscureConfirmPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '验证身份',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('输入当前密码'),
                      selected:
                          verificationMethod ==
                          _PasswordVerificationMethod.currentPassword,
                      onSelected: (_) => selectVerificationMethod(
                        _PasswordVerificationMethod.currentPassword,
                      ),
                    ),
                    ChoiceChip(
                      label: const Text('邮箱验证码'),
                      selected:
                          verificationMethod ==
                          _PasswordVerificationMethod.emailCode,
                      onSelected: (_) => selectVerificationMethod(
                        _PasswordVerificationMethod.emailCode,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (verificationMethod ==
                    _PasswordVerificationMethod.currentPassword)
                  TextFormField(
                    controller: currentPasswordController,
                    enabled: !submitting,
                    obscureText: obscureCurrentPassword,
                    validator: validateCurrentPassword,
                    textInputAction: TextInputAction.done,
                    decoration: _inputDecoration(
                      labelText: '当前密码',
                      icon: Icons.verified_user_outlined,
                      suffixIcon: IconButton(
                        tooltip: obscureCurrentPassword ? '显示密码' : '隐藏密码',
                        onPressed: () => setState(
                          () =>
                              obscureCurrentPassword = !obscureCurrentPassword,
                        ),
                        icon: Icon(
                          obscureCurrentPassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  )
                else ...[
                  Text(
                    '验证码将发送至 $maskedEmail',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: emailCodeController,
                          focusNode: emailCodeFocusNode,
                          enabled: !submitting,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          validator: validateEmailCode,
                          decoration: _inputDecoration(
                            labelText: '6 位验证码',
                            icon: Icons.mark_email_read_outlined,
                            counterText: '',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 56,
                        child: OutlinedButton(
                          onPressed:
                              requestingCode || retryAfter > 0 || submitting
                              ? null
                              : requestEmailCode,
                          child: requestingCode
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  retryAfter > 0 ? '${retryAfter}s' : '获取验证码',
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    errorMessage!,
                    style: const TextStyle(
                      color: Color(0xFFE5484D),
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: submitting ? null : submit,
          child: submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('确认修改'),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration({
    required String labelText,
    required IconData icon,
    Widget? suffixIcon,
    String? counterText,
  }) {
    return InputDecoration(
      labelText: labelText,
      prefixIcon: Icon(icon, size: 20),
      suffixIcon: suffixIcon,
      counterText: counterText,
    );
  }

  String _maskedEmail(String email) {
    final at = email.indexOf('@');
    if (at <= 0) return '当前邮箱';
    final local = email.substring(0, at);
    final visible = local.length <= 2
        ? local.substring(0, 1)
        : local.substring(0, 2);
    return '$visible***${email.substring(at)}';
  }
}
