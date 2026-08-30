import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:luntan/data/api/http_client.dart';

void main() {
  test('默认客户端可按当前平台创建并关闭', () {
    final client = createHttpClient();
    expect(client, isA<http.Client>());
    client.close();
  });
}
