import 'dart:core';

/// 官方正式更新服务器默认入口。
///
/// 无论客户端当前处于 Mock 模式、本地测试环境，还是 API 处于离线状态，
/// 更新检查默认直接连接官方更新服务，确保用户随时能收到版本通知并下载官方 APK。
const defaultOfficialUpdateBaseUrl = 'https://shengbeijiang.com';

const _configuredAppEnv = String.fromEnvironment(
  'APP_ENV',
  defaultValue: 'development',
);
const _configuredReleaseBuild = bool.fromEnvironment('dart.vm.product');

/// 判断当前构建是否必须执行正式更新服务的安全策略。
///
/// 正式环境始终要求 HTTPS；发布构建若没有显式设置 APP_ENV，也按正式构建
/// 处理，避免把开发默认值带入线上安装包。
bool isProductionUpdateBuild({String? appEnv, bool? releaseBuild}) {
  final environment = (appEnv ?? _configuredAppEnv).trim().toLowerCase();
  final isRelease = releaseBuild ?? _configuredReleaseBuild;
  return environment == 'production' ||
      (isRelease && environment == 'development');
}

/// 解析更新服务的 Base URL。
///
/// 优先级：
/// 1. 显式传入的 [overrideBaseUrl]（用于测试或指定特定节点注入）
/// 2. 编译期配置 `UPDATE_BASE_URL`
/// 3. 编译期配置 `API_BASE_URL`
/// 4. 官方正式更新服务默认入口 [defaultOfficialUpdateBaseUrl] (`https://shengbeijiang.com`)
String resolveUpdateBaseUrl({
  String? overrideBaseUrl,
  String? appEnv,
  bool? releaseBuild,
}) {
  final production = isProductionUpdateBuild(
    appEnv: appEnv,
    releaseBuild: releaseBuild,
  );
  if (overrideBaseUrl != null && overrideBaseUrl.trim().isNotEmpty) {
    return _normalizeBaseUrl(overrideBaseUrl.trim(), production: production);
  }

  const configuredUpdateUrl = String.fromEnvironment('UPDATE_BASE_URL');
  if (configuredUpdateUrl.trim().isNotEmpty) {
    return _normalizeBaseUrl(
      configuredUpdateUrl.trim(),
      production: production,
    );
  }

  const configuredApiUrl = String.fromEnvironment('API_BASE_URL');
  if (configuredApiUrl.trim().isNotEmpty) {
    return _normalizeBaseUrl(configuredApiUrl.trim(), production: production);
  }

  return _normalizeBaseUrl(
    defaultOfficialUpdateBaseUrl,
    production: production,
  );
}

String _normalizeBaseUrl(String raw, {required bool production}) {
  var url = raw.trim();
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  final parsed = Uri.tryParse(url);
  if (parsed == null ||
      !parsed.hasScheme ||
      parsed.host.isEmpty ||
      (parsed.scheme != 'http' && parsed.scheme != 'https') ||
      parsed.userInfo.isNotEmpty ||
      parsed.fragment.isNotEmpty ||
      parsed.query.isNotEmpty) {
    throw StateError('更新服务器必须是完整的 HTTP(S) URL');
  }
  if (production && parsed.scheme != 'https') {
    throw StateError('正式更新服务器必须使用 HTTPS');
  }
  return url;
}
