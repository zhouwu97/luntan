import 'package:flutter/material.dart';

import 'app.dart';
import 'data/api/api_client.dart';
import 'data/repository_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  late final ForumRepositories repositories;
  try {
    repositories = await ForumRepositories.create();
  } catch (_) {
    // Web 的安全存储可能因 HTTP、浏览器策略或插件初始化失败；这不应
    // 阻断 runApp。保留真实 API，只把令牌存储降级为本次会话内存实现。
    repositories = ForumRepositories.fromEnvironment(
      tokenStore: MemoryTokenStore(),
    );
  }
  if (repositories.isApiMode) {
    debugPrint('[LUNTAN ENV] mode=API');
    debugPrint('[LUNTAN ENV] api=${apiBaseUrlFromEnvironment()}');
  } else {
    debugPrint('[LUNTAN ENV] mode=MOCK');
  }
  runApp(LuntanApp(repositories: repositories));
}
