import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

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
  });

  final ApiErrorType type;
  final String message;
  final int? statusCode;
  final Object? cause;

  @override
  String toString() =>
      'ApiException(type: $type, statusCode: $statusCode, message: $message)';
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
    TokenStore? tokenStore,
  }) : _baseUri = baseUri,
       _client = client ?? http.Client(),
       _tokenStore = tokenStore;

  final Uri _baseUri;
  final http.Client _client;
  final Duration timeout;
  final TokenStore? _tokenStore;
  Future<void>? _refreshInFlight;

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

  Future<Map<String, dynamic>> postJson(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) async {
    return _request(method: 'POST', path: path, body: body, headers: headers);
  }

  Future<Map<String, dynamic>> patchJson(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) async {
    return _request(method: 'PATCH', path: path, body: body, headers: headers);
  }

  Future<void> deleteJson(String path, {Map<String, String>? headers}) async {
    await _request(method: 'DELETE', path: path, headers: headers);
  }

  void close() => _client.close();

  Future<Map<String, dynamic>> _request({
    required String method,
    required String path,
    Object? body,
    Map<String, String>? queryParameters,
    Map<String, String>? headers,
    bool allowRefresh = true,
  }) async {
    var response = await _send(
      method: method,
      path: path,
      body: body,
      queryParameters: queryParameters,
      headers: headers,
    );
    if (response.statusCode == 401 &&
        allowRefresh &&
        _tokenStore != null &&
        _canRefreshForPath(path)) {
      await _refreshSingleFlight();
      response = await _send(
        method: method,
        path: path,
        body: body,
        queryParameters: queryParameters,
        headers: headers,
      );
      if (response.statusCode == 401) {
        await _tokenStore.clear();
      }
    }
    return _decodeResponse(response);
  }

  Future<http.Response> _send({
    required String method,
    required String path,
    Object? body,
    Map<String, String>? queryParameters,
    Map<String, String>? headers,
  }) async {
    final uri = _baseUri
        .resolve(path)
        .replace(queryParameters: queryParameters);
    final requestHeaders = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      ...?headers,
    };
    final accessToken = await _tokenStore?.readAccessToken();
    if (accessToken != null && accessToken.isNotEmpty) {
      requestHeaders['Authorization'] = 'Bearer $accessToken';
    }
    final encodedBody = body == null ? null : jsonEncode(body);
    try {
      return await switch (method) {
        'GET' => _client.get(uri, headers: requestHeaders).timeout(timeout),
        'POST' =>
          _client
              .post(uri, headers: requestHeaders, body: encodedBody)
              .timeout(timeout),
        'PATCH' =>
          _client
              .patch(uri, headers: requestHeaders, body: encodedBody)
              .timeout(timeout),
        'DELETE' =>
          _client.delete(uri, headers: requestHeaders).timeout(timeout),
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

  Future<void> _refreshAccessToken() async {
    final store = _tokenStore;
    if (store == null) return;
    try {
      final refreshToken = await store.readRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        throw const ApiException(
          type: ApiErrorType.unauthorized,
          message: '登录状态已失效',
          statusCode: 401,
        );
      }
      final payload = await _request(
        method: 'POST',
        path: '/api/v1/auth/refresh',
        body: {'refresh_token': refreshToken},
        allowRefresh: false,
      );
      final accessToken = payload['access_token'];
      final nextRefreshToken = payload['refresh_token'];
      if (accessToken is! String ||
          accessToken.isEmpty ||
          nextRefreshToken is! String ||
          nextRefreshToken.isEmpty) {
        throw const ApiException(
          type: ApiErrorType.unknown,
          message: '刷新令牌响应格式错误',
        );
      }
      await store.save(
        AuthTokens(
          accessToken: accessToken,
          refreshToken: nextRefreshToken,
          tokenType: payload['token_type'] as String? ?? 'Bearer',
          expiresIn: (payload['expires_in'] as num?)?.toInt(),
        ),
      );
    } catch (error) {
      await store.clear();
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
}
