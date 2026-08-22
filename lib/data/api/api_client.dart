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

class ApiClient {
  ApiClient({
    required Uri baseUri,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _baseUri = baseUri,
       _client = client ?? http.Client();

  final Uri _baseUri;
  final http.Client _client;
  final Duration timeout;

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    final uri = _baseUri
        .resolve(path)
        .replace(queryParameters: queryParameters);
    late http.Response response;
    try {
      response = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(timeout);
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
      throw ApiException(
        type: ApiErrorType.unknown,
        message: '请求失败',
        cause: error,
      );
    }
    dynamic payload;
    try {
      payload = _decodePayload(response.body);
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
      throw const ApiException(
        type: ApiErrorType.unknown,
        message: '服务返回格式错误',
      );
    }
    return payload;
  }

  void close() => _client.close();

  dynamic _decodePayload(String body) {
    if (body.trim().isEmpty) return <String, dynamic>{};
    return jsonDecode(body);
  }

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
