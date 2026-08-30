import 'package:flutter_test/flutter_test.dart';
import 'package:luntan/widgets/app_network_image.dart';

void main() {
  tearDown(() => configureAppMediaBaseUrl(null));

  test('HTTPS API 将旧源站媒体地址升级到正式域名', () {
    configureAppMediaBaseUrl(Uri.parse('https://shengbeijiang.com'));

    expect(
      resolveMediaUrl(
        'http://43.161.249.91/imported-media/user-media/image.jpg',
      ),
      'https://shengbeijiang.com/imported-media/user-media/image.jpg',
    );
    expect(
      resolveMediaUrl(
        'http://43.161.249.91/api/v1/media-file/image.jpg?size=detail',
      ),
      'https://shengbeijiang.com/api/v1/media-file/image.jpg?size=detail',
    );
  });

  test('不改写外部 HTTP 图片，也不影响 HTTP 开发环境', () {
    configureAppMediaBaseUrl(Uri.parse('https://shengbeijiang.com'));
    expect(
      resolveMediaUrl('http://images.example.com/photo.jpg'),
      'http://images.example.com/photo.jpg',
    );

    configureAppMediaBaseUrl(Uri.parse('http://127.0.0.1:18080'));
    expect(
      resolveMediaUrl('http://127.0.0.1:18080/imported-media/photo.jpg'),
      'http://127.0.0.1:18080/imported-media/photo.jpg',
    );
  });
}
