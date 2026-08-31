import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'http_client.dart';

enum ApiErrorType {
  networkUnavailable,
  timeout,
  unauthorized,
  forbidden,
  notFound,
  conflict,
  rateLimited,
  serverError,
  unknown,
}

class ApiException implements Exception {
  const ApiException({
    required this.type,
    required this.message,
    this.statusCode,
    this.cause,
    this.code,
    this.requestId,
    this.details,
  });

  final ApiErrorType type;
  final String message;
  final int? statusCode;
  final Object? cause;
  final String? code;
  final String? requestId;
  final dynamic details;

  @override
  String toString() =>
      'ApiException(type: $type, code: $code, statusCode: $statusCode, message: $message)';
}

String userFacingApiMessage(Object error, {String fallback = '操作失败，请稍后重试'}) {
  if (error is! ApiException) return fallback;
  switch (error.code) {
    case 'INVALID_EMAIL':
      return '请输入有效的邮箱地址';
    case 'INVALID_EMAIL_CODE':
      return '验证码错误，请检查后重试';
    case 'EMAIL_CODE_EXPIRED':
      return '验证码已过期，请重新获取';
    case 'EMAIL_CODE_RATE_LIMITED':
      return '验证码发送太频繁，请稍后再试';
    case 'EMAIL_ALREADY_REGISTERED':
      return '该邮箱已注册，请直接登录';
    case 'EMAIL_NOT_REGISTERED':
      return '该邮箱尚未注册，请先注册';
    case 'INVALID_CREDENTIALS':
      return '邮箱或密码错误';
    case 'PASSWORD_NOT_SET':
      return '该账号尚未设置密码，请使用验证码登录';
    case 'CURRENT_PASSWORD_REQUIRED':
      return '请输入当前密码后再修改';
    case 'INVALID_PASSWORD':
      return '密码长度不能少于 8 位';
    case 'MAIL_UNAVAILABLE':
      return '邮件服务暂时不可用，请稍后再试';
    case 'REGISTERED_ACCOUNT_REQUIRED':
      return '游客可以评论和举报，登录邮箱账号后才能发布内容';
    case 'USER_MUTED':
      return '账号当前处于禁言状态，暂不能发表评论；请在账号状态查看解除时间';
    case 'STORE_ORDER_REVIEW_PENDING':
      return '已有兑换申请正在审核，请等待审核完成后再申请';
  }
  return switch (error.type) {
    ApiErrorType.unauthorized => '登录状态已失效，请重新登录',
    ApiErrorType.forbidden => '你暂时没有权限执行此操作',
    ApiErrorType.notFound => '内容不存在或已被删除',
    ApiErrorType.rateLimited => '操作太频繁，请稍后再试',
    ApiErrorType.timeout => '暂时无法连接服务器，请稍后重试',
    ApiErrorType.networkUnavailable => '暂时无法连接服务器，请稍后重试',
    ApiErrorType.serverError => '服务暂时不可用，请稍后重试',
    ApiErrorType.conflict =>
      error.message.isEmpty ? '操作冲突，请刷新后重试' : error.message,
    ApiErrorType.unknown => error.message.isEmpty ? fallback : error.message,
  };
}

class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    this.tokenType = 'Bearer',
    this.expiresIn,
  });

  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final int? expiresIn;
}

abstract interface class TokenStore {
  /// Web 端的长期会话由服务端 HttpOnly Cookie 保管，响应体可以省略
  /// refresh token；原生存储仍要求响应体提供可轮换的 refresh token。
  bool get usesHttpOnlyRefreshCookie;

  Future<String?> readAccessToken();

  Future<String?> readRefreshToken();

  Future<void> save(AuthTokens tokens);

  Future<void> clear();
}

/// 默认的进程内令牌存储，便于测试和未接入平台存储的场景。
class MemoryTokenStore implements TokenStore {
  MemoryTokenStore({String? accessToken, String? refreshToken})
    : _accessToken = accessToken,
      _refreshToken = refreshToken;

  String? _accessToken;
  String? _refreshToken;

  @override
  bool get usesHttpOnlyRefreshCookie => false;

  @override
  Future<String?> readAccessToken() async => _accessToken;

  @override
  Future<String?> readRefreshToken() async => _refreshToken;

  @override
  Future<void> save(AuthTokens tokens) async {
    _accessToken = tokens.accessToken;
    _refreshToken = tokens.refreshToken;
  }

  @override
  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
  }
}

class ApiClient {
  ApiClient({
    required Uri baseUri,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
    this.uploadTimeout = const Duration(seconds: 120),
    TokenStore? tokenStore,
    this.onSessionInvalidated,
  }) : _baseUri = baseUri,
       _client = client ?? createHttpClient(),
       _tokenStore = tokenStore;

  final Uri _baseUri;
  final http.Client _client;
  final Duration timeout;

  /// 直传媒体不复用普通 API 的短超时；上传凭证和完成确认仍走 [timeout]。
  final Duration uploadTimeout;
  final TokenStore? _tokenStore;
  void Function()? onSessionInvalidated;
  Future<void>? _refreshInFlight;
  bool _sessionInvalidationNotified = false;

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    return _request(
      method: 'GET',
      path: path,
      queryParameters: queryParameters,
    );
  }

  /// 请求需要鉴权的二进制资源，例如管理员审核源图。
  /// 非 2xx 响应仍按统一 API 错误格式解析，并复用访问令牌刷新流程。
  Future<Uint8List> getBytes(
    String path, {
    Map<String, String>? headers,
    Duration? requestTimeout,
  }) async {
    var response = await _send(
      method: 'GET',
      path: path,
      headers: headers,
      requestTimeout: requestTimeout,
    );
    if (response.statusCode == 401 &&
        _tokenStore != null &&
        await _hasStoredSession() &&
        _canRefreshForPath(path)) {
      try {
        await _refreshSingleFlight();
      } catch (error) {
        if (_shouldClearCredentials(error)) _notifySessionInvalidated();
        rethrow;
      }
      response = await _send(
        method: 'GET',
        path: path,
        headers: headers,
        requestTimeout: requestTimeout,
      );
      if (response.statusCode == 401) {
        await _tokenStore.clear();
        _notifySessionInvalidated();
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _decodeResponse(response);
    }
    return Uint8List.fromList(response.bodyBytes);
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    Object? body,
    Map<String, String>? headers,
    Duration? requestTimeout,
  }) async {
    return _request(
      method: 'POST',
      path: path,
      body: body,
      headers: headers,
      requestTimeout: requestTimeout,
    );
  }

  Future<Map<String, dynamic>> patchJson(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) async {
    return _request(method: 'PATCH', path: path, body: body, headers: headers);
  }

  Future<Map<String, dynamic>> putJson(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) async {
    return _request(method: 'PUT', path: path, body: body, headers: headers);
  }

  Future<void> deleteJson(String path, {Map<String, String>? headers}) async {
    await _request(method: 'DELETE', path: path, headers: headers);
  }

  Future<void> uploadBytes(
    Uri uploadUri,
    List<int> bytes, {
    required String contentType,
  }) async {
    final response = await _send(
      method: 'PUT',
      path: uploadUri.toString(),
      rawBody: bytes,
      headers: {'Content-Type': contentType},
      includeAuthToken: false,
      requestTimeout: uploadTimeout,
    );
    _decodeResponse(response);
  }

  void close() => _client.close();

  Future<Map<String, dynamic>> _request({
    required String method,
    required String path,
    Object? body,
    Map<String, String>? queryParameters,
    Map<String, String>? headers,
    bool allowRefresh = true,
    Duration? requestTimeout,
  }) async {
    var response = await _send(
      method: method,
      path: path,
      body: body,
      queryParameters: queryParameters,
      headers: headers,
      requestTimeout: requestTimeout,
    );
    if (response.statusCode == 401 &&
        allowRefresh &&
        _tokenStore != null &&
        await _hasStoredSession() &&
        _canRefreshForPath(path)) {
      try {
        await _refreshSingleFlight();
      } catch (error) {
        if (_shouldClearCredentials(error)) {
          _notifySessionInvalidated();
        }
        rethrow;
      }
      response = await _send(
        method: method,
        path: path,
        body: body,
        queryParameters: queryParameters,
        headers: headers,
        requestTimeout: requestTimeout,
      );
      if (response.statusCode == 401) {
        await _tokenStore.clear();
        _notifySessionInvalidated();
      }
    }
    return _decodeResponse(response);
  }

  Future<http.Response> _send({
    required String method,
    required String path,
    Object? body,
    List<int>? rawBody,
    Map<String, String>? queryParameters,
    Map<String, String>? headers,
    bool includeAuthToken = true,
    Duration? requestTimeout,
  }) async {
    final uri = _baseUri
        .resolve(path)
        .replace(queryParameters: queryParameters);
    final requestHeaders = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      ...?headers,
    };
    if (includeAuthToken) {
      final accessToken = await _tokenStore?.readAccessToken();
      if (accessToken != null && accessToken.isNotEmpty) {
        requestHeaders['Authorization'] = 'Bearer $accessToken';
      }
    }
    final encodedBody = rawBody ?? (body == null ? null : jsonEncode(body));
    try {
      final effectiveTimeout = requestTimeout ?? timeout;
      return await switch (method) {
        'GET' =>
          _client.get(uri, headers: requestHeaders).timeout(effectiveTimeout),
        'POST' =>
          _client
              .post(uri, headers: requestHeaders, body: encodedBody)
              .timeout(effectiveTimeout),
        'PATCH' =>
          _client
              .patch(uri, headers: requestHeaders, body: encodedBody)
              .timeout(effectiveTimeout),
        'PUT' =>
          _client
              .put(uri, headers: requestHeaders, body: encodedBody)
              .timeout(effectiveTimeout),
        'DELETE' =>
          _client
              .delete(uri, headers: requestHeaders)
              .timeout(effectiveTimeout),
        _ => throw StateError('unsupported HTTP method: $method'),
      };
    } on TimeoutException catch (error) {
      throw ApiException(
        type: ApiErrorType.timeout,
        message: '请求超时',
        cause: error,
      );
    } on http.ClientException catch (error) {
      throw ApiException(
        type: ApiErrorType.networkUnavailable,
        message: '网络不可用',
        cause: error,
      );
    } on FormatException catch (error) {
      throw ApiException(
        type: ApiErrorType.unknown,
        message: '服务返回格式错误',
        cause: error,
      );
    } catch (error) {
      if (error is ApiException) rethrow;
      throw ApiException(
        type: ApiErrorType.unknown,
        message: '请求失败',
        cause: error,
      );
    }
  }

  Future<void> _refreshSingleFlight() async {
    final running = _refreshInFlight;
    if (running != null) return running;
    final future = _refreshAccessToken();
    _refreshInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_refreshInFlight, future)) _refreshInFlight = null;
    }
  }

  Future<bool> _hasStoredSession() async {
    final store = _tokenStore;
    if (store == null) return false;
    final accessToken = await store.readAccessToken();
    final refreshToken = await store.readRefreshToken();
    // 未登录访问公开接口时，401 只交给调用方处理，不应触发全局“登录过期”。
    return (accessToken?.isNotEmpty ?? false) ||
        (refreshToken?.isNotEmpty ?? false);
  }

  Future<void> _refreshAccessToken() async {
    final store = _tokenStore;
    if (store == null) return;
    try {
      final refreshToken = await store.readRefreshToken();
      // Web 端本地没有 refresh token（由 HttpOnly cookie 携带），body 里
      // 省略该字段，服务端回退读取 cookie。
      final bodyToken = (refreshToken == null || refreshToken.isEmpty)
          ? null
          : refreshToken;
      final payload = await _request(
        method: 'POST',
        path: '/api/v1/auth/refresh',
        body: {'refresh_token': ?bodyToken},
        allowRefresh: false,
      );
      final accessToken = payload['access_token'];
      final nextRefreshToken = payload['refresh_token'];
      // cookie 刷新成功的响应不返回 refresh_token，只要求 access_token。
      if (accessToken is! String || accessToken.isEmpty) {
        throw const ApiException(
          type: ApiErrorType.unknown,
          message: '刷新令牌响应格式错误',
        );
      }
      await store.save(
        AuthTokens(
          accessToken: accessToken,
          refreshToken: nextRefreshToken is String ? nextRefreshToken : '',
          tokenType: payload['token_type'] as String? ?? 'Bearer',
          expiresIn: (payload['expires_in'] as num?)?.toInt(),
        ),
      );
      _sessionInvalidationNotified = false;
    } catch (error) {
      if (_shouldClearCredentials(error)) await store.clear();
      rethrow;
    }
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    dynamic payload;
    try {
      payload = response.body.trim().isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
    } on FormatException catch (error) {
      throw ApiException(
        type: ApiErrorType.unknown,
        message: '服务返回格式错误',
        cause: error,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        type: _mapStatus(response.statusCode),
        statusCode: response.statusCode,
        message: _messageFromPayload(payload),
        code: _stringFromPayload(payload, 'code'),
        requestId: _stringFromPayload(payload, 'request_id'),
        details: _valueFromPayload(payload, 'details'),
      );
    }
    if (payload is! Map<String, dynamic>) {
      throw const ApiException(type: ApiErrorType.unknown, message: '服务返回格式错误');
    }
    return payload;
  }

  bool _canRefreshForPath(String path) => !path.startsWith('/api/v1/auth/');

  ApiErrorType _mapStatus(int statusCode) => switch (statusCode) {
    401 => ApiErrorType.unauthorized,
    403 => ApiErrorType.forbidden,
    404 => ApiErrorType.notFound,
    409 => ApiErrorType.conflict,
    429 => ApiErrorType.rateLimited,
    >= 500 => ApiErrorType.serverError,
    _ => ApiErrorType.unknown,
  };

  String _messageFromPayload(dynamic payload) {
    if (payload is Map<String, dynamic> && payload['message'] is String) {
      return payload['message'] as String;
    }
    return '请求失败';
  }

  bool _shouldClearCredentials(Object error) =>
      error is ApiException &&
      error.type == ApiErrorType.unauthorized &&
      error.statusCode == 401;

  void _notifySessionInvalidated() {
    if (_sessionInvalidationNotified) return;
    _sessionInvalidationNotified = true;
    onSessionInvalidated?.call();
  }

  String? _stringFromPayload(dynamic payload, String key) {
    final value = _valueFromPayload(payload, key);
    return value is String && value.isNotEmpty ? value : null;
  }

  dynamic _valueFromPayload(dynamic payload, String key) =>
      payload is Map<String, dynamic> ? payload[key] : null;
}
