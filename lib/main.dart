import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsBinding;

import 'app.dart';
import 'data/repository_provider.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 浏览器端到端验收（快照/读屏）通过 ?a11y=1 显式开启语义树。
  if (kIsWeb && Uri.base.queryParameters['a11y'] == '1') {
    SemanticsBinding.instance.ensureSemantics();
    debugPrint(
      '[A11Y] ensureSemantics done, enabled=${SemanticsBinding.instance.semanticsEnabled}',
    );
  }
  runApp(buildLuntanRootApp());
}

/// 构造应用根组件。
///
/// 生产构建的环境校验必须保留，但校验失败不能让 Android 永远停在原生
/// 启动页。将仓储构造保持为同步路径，也避免任何异步初始化阻塞首帧。
Widget buildLuntanRootApp({ForumRepositories Function()? loadRepositories}) {
  try {
    final repositories =
        (loadRepositories ??
        () => ForumRepositories.fromEnvironment(
          defaultBaseUrl: defaultDevelopmentApiBaseUrl,
        ))();
    if (repositories.isApiMode) {
      debugPrint('[LUNTAN ENV] mode=API');
      debugPrint(
        '[LUNTAN ENV] api=${apiBaseUrlFromEnvironment(defaultBaseUrl: defaultDevelopmentApiBaseUrl)}',
      );
    } else {
      debugPrint('[LUNTAN ENV] mode=MOCK');
    }
    return LuntanApp(repositories: repositories);
  } catch (error) {
    debugPrint('[LUNTAN STARTUP] failed: $error');
    return LuntanStartupErrorApp(error: error);
  }
}

/// 启动配置或本地依赖异常时的可见错误页。
///
/// 该页面专门覆盖 `runApp` 之前抛错的场景，让用户能看到修复方向，而不
/// 是看到没有任何交互反馈的 Android 原生 Flutter 标志。
class LuntanStartupErrorApp extends StatelessWidget {
  const LuntanStartupErrorApp({super.key, required this.error});

  final Object error;

  bool get isApiConfigurationError => error.toString().contains('API_BASE_URL');

  @override
  Widget build(BuildContext context) {
    final message = isApiConfigurationError
        ? '请配置 API_BASE_URL 后重新构建应用'
        : '应用初始化失败，请关闭应用后重试';
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '圣杯酱',
      theme: AppTheme.light,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 56,
                    color: AppTheme.primary,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '应用配置异常',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      height: 1.5,
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
