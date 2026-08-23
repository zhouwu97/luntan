import 'package:flutter/material.dart';

import '../controllers/auth_controller.dart';
import '../data/api/api_client.dart';
import '../theme/app_theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.controller, required this.onBrowse});

  final AuthController controller;
  final VoidCallback onBrowse;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final nicknameController = TextEditingController();
  bool registerMode = false;

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    nicknameController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final username = usernameController.text.trim();
    final password = passwordController.text;
    if (username.isEmpty || password.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入用户名和至少 8 位密码')));
      return;
    }
    final success = registerMode
        ? await widget.controller.register(username: username, password: password, nickname: nicknameController.text.trim())
        : await widget.controller.login(username: username, password: password);
    if (success && mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    if (!success && mounted) {
      final error = widget.controller.error;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(userFacingApiMessage(error ?? StateError('auth'), fallback: '登录失败，请重试'))));
    }
  }

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
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 62, height: 62, decoration: BoxDecoration(gradient: AppTheme.primaryGradient, borderRadius: BorderRadius.circular(20)), child: const Icon(Icons.forum_rounded, color: Colors.white, size: 32)),
                const SizedBox(height: 22),
                Text(registerMode ? '加入浅蓝论坛' : '欢迎回到浅蓝论坛', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppTheme.textPrimary)),
                const SizedBox(height: 8),
                Text(offline ? '暂时无法连接服务器，可以先浏览公开内容' : '登录后发布、回复、点赞和收藏', style: const TextStyle(color: AppTheme.textSecondary, height: 1.5)),
                const SizedBox(height: 26),
                if (registerMode) ...[TextField(controller: nicknameController, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: '昵称（可选）')), const SizedBox(height: 12)],
                TextField(controller: usernameController, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: '用户名')),
                const SizedBox(height: 12),
                TextField(controller: passwordController, obscureText: true, onSubmitted: (_) => submit(), decoration: const InputDecoration(labelText: '密码', helperText: '至少 8 位')),
                const SizedBox(height: 18),
                SizedBox(width: double.infinity, height: 48, child: FilledButton(onPressed: busy ? null : submit, style: FilledButton.styleFrom(backgroundColor: AppTheme.primary), child: Text(busy ? '处理中…' : registerMode ? '注册并进入' : '登录'))),
                const SizedBox(height: 8),
                Center(child: TextButton(onPressed: busy ? null : () => setState(() => registerMode = !registerMode), child: Text(registerMode ? '已有账号？去登录' : '没有账号？去注册'))),
                Center(child: TextButton(onPressed: widget.onBrowse, child: const Text('先浏览公开内容'))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
