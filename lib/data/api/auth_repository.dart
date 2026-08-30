import '../../domain/models.dart';
import 'api_client.dart';

class AuthUser {
  const AuthUser({
    required this.id,
    required this.username,
    required this.nickname,
    required this.level,
    this.experience = 0,
    this.avatarMediaId,
    this.avatarUrl,
    this.growth,
    required this.status,
    this.accountType = 'email',
    this.email,
    this.emailVerified = false,
    this.emailVerifiedAt,
    this.hasPassword = false,
    this.commentRestricted = false,
    this.commentRestrictedUntil,
    this.capabilities = const {},
  });

  final String id;
  final String username;
  final String nickname;
  final int level;
  final int experience;
  final String? avatarMediaId;
  final String? avatarUrl;
  final GrowthState? growth;
  final String status;
  final String accountType;
  final String? email;
  final bool emailVerified;
  final DateTime? emailVerifiedAt;
  final bool hasPassword;
  final bool commentRestricted;
  final DateTime? commentRestrictedUntil;
  final Map<String, bool> capabilities;

  String? get avatar => avatarUrl;

  AuthUser copyWith({
    String? id,
    String? username,
    String? nickname,
    int? level,
    int? experience,
    String? avatarMediaId,
    String? avatarUrl,
    GrowthState? growth,
    String? status,
    String? accountType,
    String? email,
    bool? emailVerified,
    DateTime? emailVerifiedAt,
    bool? hasPassword,
    bool? commentRestricted,
    DateTime? commentRestrictedUntil,
    Map<String, bool>? capabilities,
  }) {
    return AuthUser(
      id: id ?? this.id,
      username: username ?? this.username,
      nickname: nickname ?? this.nickname,
      level: level ?? this.level,
      experience: experience ?? this.experience,
      avatarMediaId: avatarMediaId ?? this.avatarMediaId,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      growth: growth ?? this.growth,
      status: status ?? this.status,
      accountType: accountType ?? this.accountType,
      email: email ?? this.email,
      emailVerified: emailVerified ?? this.emailVerified,
      emailVerifiedAt: emailVerifiedAt ?? this.emailVerifiedAt,
      hasPassword: hasPassword ?? this.hasPassword,
      commentRestricted: commentRestricted ?? this.commentRestricted,
      commentRestrictedUntil: commentRestrictedUntil ?? this.commentRestrictedUntil,
      capabilities: capabilities ?? this.capabilities,
    );
  }

  bool capability(String name, {bool fallback = false}) =>
      capabilities[name] ?? fallback;

  bool get canPublish =>
      capability('can_publish', fallback: accountType != 'guest');

  bool get canCreatePoll =>
      capability('can_create_poll', fallback: accountType != 'guest');

  bool get canManageBookmarks => capability(
    'can_bookmark',
    fallback: capability(
      'can_manage_bookmarks',
      fallback: accountType != 'guest',
    ),
  );

  bool get canComment => capability('can_comment', fallback: true);

  bool get canReport => capability('can_report', fallback: true);

  bool get canLike => capability('can_like', fallback: true);

  bool get canFollow => capability('can_follow');

  bool get canUploadMedia =>
      capability('can_upload_media', fallback: canPublish);

  bool get canVote => capability('can_vote', fallback: accountType != 'guest');

  bool get canManageProfile =>
      capability('can_manage_profile', fallback: accountType != 'guest');

  bool get canModerate => capability('can_moderate');

  bool get canManageAdmins => capability('can_manage_admins');

  bool get canManageUsers => capability('can_manage_users');

  bool get canViewAdminLogs => capability('can_view_admin_logs');

  bool get canBanIP => capability('can_ban_ip');

  /// 统一读取业务能力，兼容旧服务端未返回完整 capabilities 的会话。
  bool can(String name) => switch (name) {
    'can_publish' => canPublish,
    'can_create_poll' => canCreatePoll,
    'can_bookmark' || 'can_manage_bookmarks' => canManageBookmarks,
    'can_comment' => canComment,
    'can_like' => canLike,
    'can_report' => canReport,
    'can_follow' => canFollow,
    'can_upload_media' => canUploadMedia,
    'can_vote' => canVote,
    'can_manage_profile' => canManageProfile,
    'can_moderate' => canModerate,
    'can_manage_admins' => canManageAdmins,
    'can_manage_users' => canManageUsers,
    'can_ban_ip' => canBanIP,
    'can_view_admin_logs' => canViewAdminLogs,
    _ => capability(name),
  };
}

class EmailCodeChallenge {
  const EmailCodeChallenge({
    required this.expiresIn,
    required this.retryAfter,
    required this.delivery,
    this.devCode,
  });

  final int expiresIn;
  final int retryAfter;
  final String delivery;
  final String? devCode;
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

  Future<bool> hasStoredSession() async {
    final accessToken = await _tokenStore.readAccessToken();
    final refreshToken = await _tokenStore.readRefreshToken();
    return (accessToken?.isNotEmpty ?? false) ||
        (refreshToken?.isNotEmpty ?? false);
  }

  Future<AuthSession> register({
    required String email,
    required String code,
    required String password,
    String? nickname,
  }) async {
    final payload = await _client.postJson(
      '/api/v1/auth/register',
      body: {
        'email': email.trim(),
        'code': code.trim(),
        'password': password,
        if (nickname != null && nickname.trim().isNotEmpty)
          'nickname': nickname.trim(),
      },
    );
    return _saveSession(payload);
  }

  Future<AuthSession> loginWithPassword({
    required String email,
    required String password,
  }) async {
    final payload = await _client.postJson(
      // 旧版线上服务只暴露 /auth/login；当前服务端也保留该路径，
      // 并根据 email 字段执行邮箱密码登录。
      '/api/v1/auth/login',
      body: {'email': email.trim(), 'password': password},
    );
    return _saveSession(payload);
  }

  Future<AuthSession> login({
    String? username,
    String? email,
    required String password,
  }) async {
    final targetEmail = email?.trim();
    if (targetEmail != null && targetEmail.isNotEmpty) {
      return loginWithPassword(email: targetEmail, password: password);
    }
    final targetUsername = username?.trim() ?? '';
    if (targetUsername.contains('@')) {
      return loginWithPassword(email: targetUsername, password: password);
    }
    final payload = await _client.postJson(
      '/api/v1/auth/login',
      body: {'username': targetUsername, 'password': password},
    );
    return _saveSession(payload);
  }

  Future<EmailCodeChallenge> requestEmailCode(
    String email, {
    String scene = 'login',
  }) async {
    final payload = await _client.postJson(
      // /email/request 是新旧服务端都支持的认证入口。
      '/api/v1/auth/email/request',
      body: {'email': email.trim(), 'scene': scene},
    );
    return EmailCodeChallenge(
      expiresIn: _int(payload['expires_in'], fallback: 600),
      retryAfter: _int(payload['retry_after'], fallback: 60),
      delivery: _string(payload['delivery']),
      devCode: payload['dev_code'] is String
          ? payload['dev_code'] as String
          : null,
    );
  }

  Future<AuthSession> loginWithEmailCode({
    required String email,
    required String code,
    String? nickname,
  }) async {
    final payload = await _client.postJson(
      // /email/verify 是新旧服务端都支持的验证码登录入口。
      '/api/v1/auth/email/verify',
      body: {
        'email': email.trim(),
        'code': code.trim(),
        if (nickname != null && nickname.trim().isNotEmpty)
          'nickname': nickname.trim(),
      },
    );
    return _saveSession(payload);
  }

  Future<AuthSession> guest() async {
    final payload = await _client.postJson('/api/v1/auth/guest');
    return _saveSession(payload);
  }

  Future<AuthUser> me() async {
    return _userFromJson(await _client.getJson('/api/v1/me'));
  }

  Future<void> setPassword({
    required String password,
    String? currentPassword,
  }) async {
    await _client.postJson(
      '/api/v1/me/password',
      body: {'password': password, 'current_password': ?currentPassword},
    );
  }

  Future<void> logout() async {
    try {
      final refreshToken = await _tokenStore.readRefreshToken();
      // Web 端 refresh token 在 HttpOnly cookie 里，body 通常为空；
      // 服务端收到后清除 cookie，未登录时也幂等返回 204。
      await _client.postJson(
        '/api/v1/auth/logout',
        body: {'refresh_token': ?refreshToken},
      );
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
    final bodyRefreshToken = refreshToken is String ? refreshToken : '';
    if (accessToken is! String ||
        accessToken.isEmpty ||
        (!_tokenStore.usesHttpOnlyRefreshCookie && bodyRefreshToken.isEmpty)) {
      throw const ApiException(type: ApiErrorType.unknown, message: '登录响应格式错误');
    }
    final tokens = AuthTokens(
      accessToken: accessToken,
      // Cookie-backed Web 会话不把服务端响应中的 refresh token 继续带入
      // 客户端状态，即使旧服务端意外返回了该字段也不落入本地存储。
      refreshToken: _tokenStore.usesHttpOnlyRefreshCookie
          ? ''
          : bodyRefreshToken,
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
    final accountType = _string(json['account_type']).isEmpty
        ? 'email'
        : _string(json['account_type']);
    final fallbackLevel = accountType == 'guest' ? 0 : 1;
    final level = _int(json['level'], fallback: fallbackLevel);
    final experience = _int(json['experience'], fallback: 0);
    final growth = json['growth'] is Map<String, dynamic>
        ? GrowthState.fromJson(
            json['growth'] as Map<String, dynamic>,
            fallbackLevel: level,
            accountType: accountType,
          )
        : GrowthState.fromJson(
            null,
            fallbackLevel: level,
            fallbackExperience: experience,
            accountType: accountType,
          );

    return AuthUser(
      id: _string(json['id']),
      username: _string(json['username']),
      nickname: _string(json['nickname']),
      level: growth.level,
      experience: experience,
      avatarMediaId: json['avatar_media_id'] is String && (json['avatar_media_id'] as String).isNotEmpty
          ? json['avatar_media_id'] as String
          : null,
      avatarUrl: json['avatar_url'] is String && (json['avatar_url'] as String).isNotEmpty
          ? json['avatar_url'] as String
          : null,
      growth: growth,
      status: _string(json['status']),
      accountType: accountType,
      email: json['email'] is String && (json['email'] as String).isNotEmpty
          ? json['email'] as String
          : null,
      emailVerified: json['email_verified'] == true,
      emailVerifiedAt: _date(json['email_verified_at']),
      hasPassword: json['has_password'] == true,
      commentRestricted: json['comment_restricted'] == true,
      commentRestrictedUntil: _date(json['comment_restricted_until']),
      capabilities: _capabilities(json['capabilities']),
    );
  }

  String _string(dynamic value) => value is String ? value : '';

  int _int(dynamic value, {required int fallback}) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

  DateTime? _date(dynamic value) =>
      value is String ? DateTime.tryParse(value) : null;

  Map<String, bool> _capabilities(dynamic value) {
    if (value is! Map) return const {};
    return Map.unmodifiable(
      value.map<String, bool>((key, item) => MapEntry('$key', item == true)),
    );
  }
}
