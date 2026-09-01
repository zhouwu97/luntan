import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/data/repository_provider.dart';

void main() {
  test('生产环境没有 API 地址时启动失败', () {
    expect(
      () => resolveApiBaseUrl(configured: '  ', appEnv: 'production'),
      throwsA(isA<StateError>()),
    );
  });

  test('开发环境没有 API 地址时保持 Mock 模式', () {
    expect(resolveApiBaseUrl(configured: '  ', appEnv: 'development'), isEmpty);
  });

  test('正式开发启动使用服务器 API 默认地址', () {
    expect(defaultDevelopmentApiBaseUrl, 'https://shengbeijiang.com');
    expect(
      apiBaseUrlFromEnvironment(defaultBaseUrl: defaultDevelopmentApiBaseUrl),
      defaultDevelopmentApiBaseUrl,
    );
  });

  test('QA 必须显式配置 API 地址并允许使用 HTTP', () {
    expect(
      () => resolveApiBaseUrl(configured: '  ', appEnv: 'qa'),
      throwsA(isA<StateError>()),
    );
    expect(
      resolveApiBaseUrl(configured: 'http://101.42.27.44', appEnv: 'qa'),
      'http://101.42.27.44',
    );
  });

  test('生产环境拒绝 HTTP API', () {
    expect(
      () => resolveApiBaseUrl(
        configured: 'http://101.42.27.44',
        appEnv: 'production',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('生产环境接受 HTTPS API', () {
    expect(
      resolveApiBaseUrl(
        configured: 'https://forum.example.edu',
        appEnv: 'production',
      ),
      'https://forum.example.edu',
    );
  });

  test('release 构建漏传环境参数时使用正式 HTTPS 默认地址', () {
    expect(
      apiBaseUrlFromEnvironment(
        defaultBaseUrl: defaultDevelopmentApiBaseUrl,
        releaseBuild: true,
      ),
      defaultDevelopmentApiBaseUrl,
    );
  });
}
