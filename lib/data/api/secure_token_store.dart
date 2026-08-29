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

class LocalTokenStore implements TokenStore {
  LocalTokenStore();

  static const _accessTokenKey = 'luntan.auth.access_token';
  static const _refreshTokenKey = 'luntan.auth.refresh_token';

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
  Future<String?> readRefreshToken() async =>
      (await _store()).getString(_refreshTokenKey);

  @override
  Future<void> save(AuthTokens tokens) async {
    final store = await _store();
    await store.setString(_accessTokenKey, tokens.accessToken);
    await store.setString(_refreshTokenKey, tokens.refreshToken);
  }

  @override
  Future<void> clear() async {
    final store = await _store();
    await store.remove(_accessTokenKey);
    await store.remove(_refreshTokenKey);
  }
}

/// 按平台选择默认令牌存储：Web 用 localStorage，其余用平台安全存储。
TokenStore createDefaultTokenStore() =>
    kIsWeb ? LocalTokenStore() : SecureTokenStore();
