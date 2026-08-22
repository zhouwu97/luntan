import 'api_client.dart';

class AuthUser {
  const AuthUser({
    required this.id,
    required this.username,
    required this.nickname,
    required this.level,
    required this.status,
  });

  final String id;
  final String username;
  final String nickname;
  final int level;
  final String status;
}

class AuthSession {
  const AuthSession({required this.user, required this.tokens});

  final AuthUser user;
  final AuthTokens tokens;
}

class AuthRepository {
  AuthRepository({required ApiClient client, required TokenStore tokenStore})
    : _client = client,
      _tokenStore = tokenStore;

  final ApiClient _client;
  final TokenStore _tokenStore;

  Future<AuthSession> register({
    required String username,
    required String password,
    String? nickname,
  }) async {
    final payload = await _client.postJson(
      '/api/v1/auth/register',
      body: {
        'username': username,
        'password': password,
        if (nickname != null && nickname.trim().isNotEmpty)
          'nickname': nickname,
      },
    );
    return _saveSession(payload);
  }

  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    final payload = await _client.postJson(
      '/api/v1/auth/login',
      body: {'username': username, 'password': password},
    );
    return _saveSession(payload);
  }

  Future<AuthUser> me() async {
    return _userFromJson(await _client.getJson('/api/v1/me'));
  }

  Future<void> logout() async {
    try {
      final refreshToken = await _tokenStore.readRefreshToken();
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _client.postJson(
          '/api/v1/auth/logout',
          body: {'refresh_token': refreshToken},
        );
      }
    } finally {
      await _tokenStore.clear();
    }
  }

  Future<void> deleteAccount() async {
    try {
      await _client.deleteJson('/api/v1/me');
    } finally {
      await _tokenStore.clear();
    }
  }

  Future<AuthSession> _saveSession(Map<String, dynamic> payload) async {
    final accessToken = payload['access_token'];
    final refreshToken = payload['refresh_token'];
    if (accessToken is! String ||
        accessToken.isEmpty ||
        refreshToken is! String ||
        refreshToken.isEmpty) {
      throw const ApiException(type: ApiErrorType.unknown, message: '登录响应格式错误');
    }
    final tokens = AuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      tokenType: payload['token_type'] as String? ?? 'Bearer',
      expiresIn: (payload['expires_in'] as num?)?.toInt(),
    );
    await _tokenStore.save(tokens);
    final userPayload = payload['user'];
    if (userPayload is! Map) {
      throw const ApiException(type: ApiErrorType.unknown, message: '用户信息格式错误');
    }
    return AuthSession(
      user: _userFromJson(Map<String, dynamic>.from(userPayload)),
      tokens: tokens,
    );
  }

  AuthUser _userFromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: _string(json['id']),
      username: _string(json['username']),
      nickname: _string(json['nickname']),
      level: _int(json['level'], fallback: 1),
      status: _string(json['status']),
    );
  }

  String _string(dynamic value) => value is String ? value : '';

  int _int(dynamic value, {required int fallback}) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? fallback;
}
