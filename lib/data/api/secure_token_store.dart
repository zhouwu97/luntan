import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';

/// access/refresh token 使用平台安全存储；MemoryTokenStore 仍保留给测试，
/// SharedPreferencesTokenStore 作为旧版本迁移兼容实现。
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
