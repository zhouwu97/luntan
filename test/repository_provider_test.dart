import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/data/repository_provider.dart';

void main() {
  test('没有 API 地址时保持 Mock 模式', () {
    expect(resolveApiBaseUrl(configured: '  ', appEnv: 'production'), isEmpty);
  });

  test('QA 允许使用 HTTP', () {
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
}
