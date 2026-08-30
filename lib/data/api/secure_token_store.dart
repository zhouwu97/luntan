import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// access/refresh token 使用平台安全存储；MemoryTokenStore 仍保留给测试。
///
/// Web 上 flutter_secure_storage 依赖 WebCrypto subtle；HTTP 部署（如 QA）
/// 不是安全上下文，subtle 不存在导致所有读写直接抛异常，登录会话永远存不
/// 下来。浏览器端因此退化为 localStorage（shared_preferences），原生端仍
/// 使用各平台安全存储。
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _accessTokenKey = 'luntan.auth.access_token';
  static const _refreshTokenKey = 'luntan.auth.refresh_token';

  final FlutterSecureStorage _storage;

  static Future<SecureTokenStore> create() async => SecureTokenStore();

  @override
  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);

  @override
  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);

  @override
  Future<void> save(AuthTokens tokens) async {
    await _storage.write(key: _accessTokenKey, value: tokens.accessToken);
    await _storage.write(key: _refreshTokenKey, value: tokens.refreshToken);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }
}

/// Web 端只持久化短时效 access token；refresh token 由服务端
/// `luntan_refresh` HttpOnly cookie（Path=/api/v1/auth）保管，浏览器
/// localStorage 不再接触长效凭证，XSS 无法窃取续期凭证。
class WebTokenStore implements TokenStore {
  WebTokenStore();

  static const _accessTokenKey = 'luntan.auth.access_token';
  static const _legacyRefreshTokenKey = 'luntan.auth.refresh_token';

  static SharedPreferences? _prefs;
  static Future<SharedPreferences>? _loading;

  Future<SharedPreferences> _store() {
    final cached = _prefs;
    if (cached != null) return Future.value(cached);
    return _loading ??= SharedPreferences.getInstance().then((value) {
      _prefs = value;
      return value;
    });
  }

  @override
  Future<String?> readAccessToken() async =>
      (await _store()).getString(_accessTokenKey);

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> save(AuthTokens tokens) async {
    final store = await _store();
    await store.setString(_accessTokenKey, tokens.accessToken);
    // 迁移历史版本遗留的明文 refresh token。
    await store.remove(_legacyRefreshTokenKey);
  }

  @override
  Future<void> clear() async {
    final store = await _store();
    await store.remove(_accessTokenKey);
    await store.remove(_legacyRefreshTokenKey);
  }
}

/// 按平台选择默认令牌存储：Web 只存 access token（refresh 走 HttpOnly
/// cookie），原生端用平台安全存储。
TokenStore createDefaultTokenStore() =>
    kIsWeb ? WebTokenStore() : SecureTokenStore();
