import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// 使用平台偏好存储保存会话令牌；生产环境可替换为系统安全存储实现。
class SharedPreferencesTokenStore implements TokenStore {
  SharedPreferencesTokenStore(this._preferences);

  static const _accessTokenKey = 'luntan.auth.access_token';
  static const _refreshTokenKey = 'luntan.auth.refresh_token';

  final SharedPreferences _preferences;

  static Future<SharedPreferencesTokenStore> create() async {
    return SharedPreferencesTokenStore(await SharedPreferences.getInstance());
  }

  @override
  Future<String?> readAccessToken() async =>
      _preferences.getString(_accessTokenKey);

  @override
  Future<String?> readRefreshToken() async =>
      _preferences.getString(_refreshTokenKey);

  @override
  Future<void> save(AuthTokens tokens) async {
    await _preferences.setString(_accessTokenKey, tokens.accessToken);
    await _preferences.setString(_refreshTokenKey, tokens.refreshToken);
  }

  @override
  Future<void> clear() async {
    await _preferences.remove(_accessTokenKey);
    await _preferences.remove(_refreshTokenKey);
  }
}
