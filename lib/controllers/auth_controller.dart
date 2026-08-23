import 'package:flutter/foundation.dart';

import '../data/api/auth_repository.dart';
import '../data/api/api_client.dart';

enum AuthStatus {
  unknown,
  unauthenticated,
  authenticating,
  authenticated,
  error,
}

class AuthController extends ChangeNotifier {
  AuthController({required AuthRepository repository})
    : _repository = repository;

  final AuthRepository _repository;
  AuthStatus status = AuthStatus.unknown;
  AuthUser? user;
  ApiException? error;

  Future<void> initialize() async {
    try {
      user = await _repository.me();
      status = AuthStatus.authenticated;
      error = null;
    } on ApiException catch (exception) {
      final hasSession = await _repository.hasStoredSession();
      // 只有明确的 401 才能清空登录态；断网、超时和服务端异常要保留
      // session，让用户可以重试而不是被误登出。
      status = exception.type == ApiErrorType.unauthorized
          ? AuthStatus.unauthenticated
          : hasSession
          ? AuthStatus.error
          : AuthStatus.unauthenticated;
      error = exception;
      if (status == AuthStatus.unauthenticated) user = null;
    }
    notifyListeners();
  }

  Future<bool> login({
    required String username,
    required String password,
  }) async {
    status = AuthStatus.authenticating;
    error = null;
    notifyListeners();
    try {
      final session = await _repository.login(
        username: username,
        password: password,
      );
      user = session.user;
      status = AuthStatus.authenticated;
      return true;
    } on ApiException catch (exception) {
      status = AuthStatus.error;
      error = exception;
      user = null;
      return false;
    } finally {
      notifyListeners();
    }
  }

  Future<bool> register({
    required String username,
    required String password,
    String? nickname,
  }) async {
    status = AuthStatus.authenticating;
    error = null;
    notifyListeners();
    try {
      final session = await _repository.register(
        username: username,
        password: password,
        nickname: nickname,
      );
      user = session.user;
      status = AuthStatus.authenticated;
      return true;
    } on ApiException catch (exception) {
      status = AuthStatus.error;
      error = exception;
      user = null;
      return false;
    } finally {
      notifyListeners();
    }
  }

  Future<void> logout() async {
    try {
      await _repository.logout();
    } finally {
      user = null;
      error = null;
      status = AuthStatus.unauthenticated;
      notifyListeners();
    }
  }
}
