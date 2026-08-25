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

  /// 由 API 客户端在 refresh token 也失效时调用，统一清理根状态。
  void invalidateSession() {
    user = null;
    error = const ApiException(
      type: ApiErrorType.unauthorized,
      statusCode: 401,
      message: '登录状态已失效',
    );
    status = AuthStatus.unauthenticated;
    notifyListeners();
  }

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
    } catch (cause) {
      // 浏览器安全存储、插件或运行时初始化失败不应让启动页永久停在
      // unknown；公开内容仍可浏览，登录操作会在用户主动重试时反馈错误。
      status = AuthStatus.unauthenticated;
      user = null;
      error = ApiException(
        type: ApiErrorType.unknown,
        message: '登录状态初始化失败，请稍后重试',
        cause: cause,
      );
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
      await _adoptSession(session);
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
      await _adoptSession(session);
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

  Future<EmailCodeChallenge?> requestEmailCode(String email) async {
    try {
      error = null;
      return await _repository.requestEmailCode(email);
    } on ApiException catch (exception) {
      error = exception;
      rethrow;
    }
  }

  Future<bool> loginWithEmailCode({
    required String email,
    required String code,
    String? nickname,
  }) async {
    status = AuthStatus.authenticating;
    error = null;
    notifyListeners();
    try {
      final session = await _repository.loginWithEmailCode(
        email: email,
        code: code,
        nickname: nickname,
      );
      await _adoptSession(session);
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

  Future<bool> guest() async {
    status = AuthStatus.authenticating;
    error = null;
    notifyListeners();
    try {
      final session = await _repository.guest();
      await _adoptSession(session);
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

  Future<void> _adoptSession(AuthSession session) async {
    user = session.user;
    // 登录响应负责立即进入主界面；/me 再补齐角色能力，失败时保留
    // 登录响应中的基础账号信息，避免权限查询短暂失败把登录判成失败。
    try {
      user = await _repository.me();
    } on ApiException {
      // 能力缺失时客户端默认按最小权限处理，后端仍是最终权限边界。
    }
  }
}
