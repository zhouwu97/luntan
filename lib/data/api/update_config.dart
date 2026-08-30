import 'dart:core';

/// 官方正式更新服务器默认入口。
///
/// 无论客户端当前处于 Mock 模式、本地测试环境，还是 API 处于离线状态，
/// 更新检查默认直接连接官方更新服务，确保用户随时能收到版本通知并下载官方 APK。
const defaultOfficialUpdateBaseUrl = 'https://shengbeijiang.com';

/// 解析更新服务的 Base URL。
///
/// 优先级：
/// 1. 显式传入的 [overrideBaseUrl]（用于测试或指定特定节点注入）
/// 2. 编译期配置 `UPDATE_BASE_URL`
/// 3. 编译期配置 `API_BASE_URL`
/// 4. 官方正式更新服务默认入口 [defaultOfficialUpdateBaseUrl] (`https://shengbeijiang.com`)
String resolveUpdateBaseUrl({String? overrideBaseUrl}) {
  if (overrideBaseUrl != null && overrideBaseUrl.trim().isNotEmpty) {
    return _normalizeBaseUrl(overrideBaseUrl.trim());
  }

  const configuredUpdateUrl = String.fromEnvironment('UPDATE_BASE_URL');
  if (configuredUpdateUrl.trim().isNotEmpty) {
    return _normalizeBaseUrl(configuredUpdateUrl.trim());
  }

  const configuredApiUrl = String.fromEnvironment('API_BASE_URL');
  if (configuredApiUrl.trim().isNotEmpty) {
    return _normalizeBaseUrl(configuredApiUrl.trim());
  }

  return _normalizeBaseUrl(defaultOfficialUpdateBaseUrl);
}

String _normalizeBaseUrl(String raw) {
  var url = raw.trim();
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}
