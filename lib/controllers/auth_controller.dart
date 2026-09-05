import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/api/api_client.dart';
import '../data/api/auth_repository.dart';
import '../data/api/profile_repository.dart';
import '../widgets/app_network_image.dart';
import '../data/cache/image_cache_manager.dart';

enum AuthStatus {
  unknown,
  unauthenticated,
  authenticating,
  authenticated,
  error,
}

class AuthController extends ChangeNotifier {
  AuthController({
    required AuthRepository repository,
    ProfileRepository? profileRepository,
  }) : _repository = repository,
       _profileRepository = profileRepository;

  final AuthRepository _repository;
  final ProfileRepository? _profileRepository;
  AuthStatus status = AuthStatus.unknown;
  AuthUser? user;
  ApiException? error;

  /// 由 API 客户端在 refresh token 也失效时调用，统一清理根状态。
  void invalidateSession() {
    unawaited(ForumImageCaches.clearPrivate());
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
      await _enrichAvatar();
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

  /// 主动刷新当前登录用户资料（如头像、昵称、等级更新后）。
  Future<void> refreshUser() async {
    try {
      final updated = await _repository.me();
      user = updated;
      await _enrichAvatar();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _enrichAvatar() async {
    final currentUser = user;
    if (currentUser == null) return;
    if (currentUser.avatarUrl != null && currentUser.avatarUrl!.isNotEmpty) {
      UserAvatarCache.set(currentUser.id, currentUser.avatarUrl);
      return;
    }
    final cached = UserAvatarCache.get(currentUser.id);
    if (cached != null && cached.isNotEmpty) {
      if (user?.id == currentUser.id) {
        user = currentUser.copyWith(avatarUrl: cached);
      }
      return;
    }
    if (_profileRepository != null) {
      try {
        final profile = await _profileRepository.getProfile();
        if (profile.avatarUrl != null &&
            profile.avatarUrl!.isNotEmpty &&
            user?.id == currentUser.id) {
          user = currentUser.copyWith(
            avatarUrl: profile.avatarUrl,
            avatarMediaId: profile.avatarMediaId,
          );
          UserAvatarCache.set(currentUser.id, profile.avatarUrl);
        }
      } catch (_) {}
    }
  }

  void updateAvatar(String? avatarUrl, [String? avatarMediaId]) {
    if (user == null) return;
    UserAvatarCache.set(user!.id, avatarUrl);
    user = user!.copyWith(avatarUrl: avatarUrl, avatarMediaId: avatarMediaId);
    notifyListeners();
  }

  Future<bool> loginWithPassword({
    required String email,
    required String password,
  }) async {
    status = AuthStatus.authenticating;
    error = null;
    notifyListeners();
    try {
      final session = await _repository.loginWithPassword(
        email: email,
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
    } catch (cause) {
      // 平台层异常（安全存储不可用、插件缺失等）不是 ApiException；若不
      // 复位状态，status 会永久停在 authenticating，登录按钮一直置灰。
      status = AuthStatus.error;
      error = ApiException(
        type: ApiErrorType.unknown,
        message: '操作失败，请稍后重试',
        cause: cause,
      );
      user = null;
      return false;
    } finally {
      notifyListeners();
    }
  }

  Future<bool> login({
    String? username,
    String? email,
    required String password,
  }) async {
    status = AuthStatus.authenticating;
    error = null;
    notifyListeners();
    try {
      final session = await _repository.login(
        username: username,
        email: email,
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
    } catch (cause) {
      // 平台层异常（安全存储不可用、插件缺失等）不是 ApiException；若不
      // 复位状态，status 会永久停在 authenticating，登录按钮一直置灰。
      status = AuthStatus.error;
      error = ApiException(
        type: ApiErrorType.unknown,
        message: '操作失败，请稍后重试',
        cause: cause,
      );
      user = null;
      return false;
    } finally {
      notifyListeners();
    }
  }

  Future<bool> register({
    required String email,
    required String password,
    String? nickname,
    String? code,
  }) async {
    status = AuthStatus.authenticating;
    error = null;
    notifyListeners();
    try {
      final session = await _repository.register(
        email: email,
        password: password,
        nickname: nickname,
        code: code,
      );
      await _adoptSession(session);
      status = AuthStatus.authenticated;
      return true;
    } on ApiException catch (exception) {
      status = AuthStatus.error;
      error = exception;
      user = null;
      return false;
    } catch (cause) {
      // 平台层异常（安全存储不可用、插件缺失等）不是 ApiException；若不
      // 复位状态，status 会永久停在 authenticating，登录按钮一直置灰。
      status = AuthStatus.error;
      error = ApiException(
        type: ApiErrorType.unknown,
        message: '操作失败，请稍后重试',
        cause: cause,
      );
      user = null;
      return false;
    } finally {
      notifyListeners();
    }
  }

  Future<EmailCodeChallenge?> requestEmailCode(
    String email, {
    String scene = 'login',
  }) async {
    try {
      error = null;
      return await _repository.requestEmailCode(email, scene: scene);
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
    } catch (cause) {
      // 平台层异常（安全存储不可用、插件缺失等）不是 ApiException；若不
      // 复位状态，status 会永久停在 authenticating，登录按钮一直置灰。
      status = AuthStatus.error;
      error = ApiException(
        type: ApiErrorType.unknown,
        message: '操作失败，请稍后重试',
        cause: cause,
      );
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
    } catch (cause) {
      // 平台层异常（安全存储不可用、插件缺失等）不是 ApiException；若不
      // 复位状态，status 会永久停在 authenticating，登录按钮一直置灰。
      status = AuthStatus.error;
      error = ApiException(
        type: ApiErrorType.unknown,
        message: '操作失败，请稍后重试',
        cause: cause,
      );
      user = null;
      return false;
    } finally {
      notifyListeners();
    }
  }

  /// 首次设置密码（未设过密码的账号无需旧密码），成功后刷新用户态。
  Future<void> setPassword({
    required String password,
    String? currentPassword,
    String? emailCode,
  }) async {
    error = null;
    try {
      await _repository.setPassword(
        password: password,
        currentPassword: currentPassword,
        emailCode: emailCode,
      );
    } on ApiException catch (exception) {
      error = exception;
      notifyListeners();
      rethrow;
    }
    try {
      user = await _repository.me();
    } catch (_) {
      // 密码已设置成功，用户态刷新失败不影响本次结果。
    }
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await _repository.logout();
    } finally {
      await ForumImageCaches.clearPrivate();
      user = null;
      error = null;
      status = AuthStatus.unauthenticated;
      notifyListeners();
    }
  }

  Future<void> _adoptSession(AuthSession session) async {
    user = session.user;
    // 登录响应负责立即进入主界面；/me 再补齐角色能力，任何失败都保留
    // 登录响应中的基础账号信息，避免权限查询短暂失败把登录判成失败。
    try {
      user = await _repository.me();
      await _enrichAvatar();
    } catch (_) {
      // 能力缺失时客户端默认按最小权限处理，后端仍是最终权限边界。
      await _enrichAvatar();
    }
  }
}
