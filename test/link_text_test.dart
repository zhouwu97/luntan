import 'package:flutter_test/flutter_test.dart';
import 'package:luntan/widgets/link_text.dart';

void main() {
  group('extractContentLinks', () {
    test('extracts URL when followed by Chinese characters without spaces', () {
      const text = 'https://galgamex.com/这里面有挺多来着';
      final links = extractContentLinks(text);

      expect(links.length, 1);
      expect(links.first.text, 'https://galgamex.com/');
      expect(links.first.uri.toString(), 'https://galgamex.com/');
      expect(links.first.start, 0);
      expect(links.first.end, 'https://galgamex.com/'.length);
    });

    test('extracts www links and normalizes to https', () {
      const text = '推荐访问 www.example.com/page?id=1 看看';
      final links = extractContentLinks(text);

      expect(links.length, 1);
      expect(links.first.text, 'www.example.com/page?id=1');
      expect(links.first.uri.toString(), 'https://www.example.com/page?id=1');
    });

    test('trims trailing punctuation', () {
      const text = '访问 (https://example.com/test)。很有用！';
      final links = extractContentLinks(text);

      expect(links.length, 1);
      expect(links.first.text, 'https://example.com/test');
      expect(links.first.uri.toString(), 'https://example.com/test');
    });
  });
}
