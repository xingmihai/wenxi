import 'package:flutter_test/flutter_test.dart';
import 'package:asterlink/domain/links.dart';
import 'package:asterlink/domain/models.dart';

void main() {
  const url = 'https://share.feijipan.com/s/Share123';
  final variants = <String>[
    '$url?code=a123',
    '我通过小飞机分享了文件\n链接：$url\n提取码：a123',
    '$url（访问密码：a123）',
    '$url(提取码:a123)',
    '[$url?code=a123]($url?code=a123)',
    '[下载文件]($url?code=a123)',
    '`$url?code=a123`',
    'share.feijipan.com/s/Share123?code=a123',
    'HTTP://SHARE.FEIJIPAN.COM/s/Share123/?CODE=a123',
    'https://www.feijipan.com/#/s/Share123?code=a123',
    '$url#code=a123',
    '$url#pwd=a123',
    '$url#a123',
    '$url?code=%61%31%32%33',
    '$url?code=a123&from=share 密码：b456',
    '$url?password=b456&code=a123',
  ];
  for (var i = 0; i < variants.length; i++) {
    test('Feijipan copied share format $i', () {
      final link = LinkParser.parse(variants[i]).single;
      expect(link.kind, LinkKind.cloudShare);
      expect(link.platform, CloudPlatform.feijipan);
      expect(link.shareId, 'Share123');
      expect(link.passcode, 'a123');
      expect(LinkParser.shareId(CloudPlatform.feijipan, link.url), 'Share123');
    });
  }

  test('Feijipan does not mistake pages and lookalike sites for shares', () {
    for (final address in [
      'https://www.feijipan.com/console/files/0',
      'https://share.feijipan.com/',
      'https://share.feijipan.com/s/',
      'https://share.feijipan.com/s/Share123/extra',
      'https://www.feijipan.com/help#/s/Share123',
      'https://feijipan.com.evil.test/s/Share123',
      'https://evil.test/?redirect=https://share.feijipan.com/s/Share123',
    ]) {
      expect(
        LinkParser.parse(address).where((l) => l.kind == LinkKind.cloudShare),
        isEmpty,
        reason: address,
      );
    }
  });

  test('Feijipan extraction codes require four complete letters or digits', () {
    for (final code in ['abc', 'abcde', 'a12_', 'a123%26tail', '']) {
      final link = LinkParser.parse('$url?code=$code').single;
      expect(link.passcode, isNull, reason: code);
    }
  });

  test(
    'Neighboring shares keep their own codes and duplicate copies merge',
    () {
      final links = LinkParser.parse(
        '$url 提取码：a123\nhttps://share.feijipan.com/s/Other456 密码：b456',
      );
      expect(links.map((l) => l.passcode), ['a123', 'b456']);
      final duplicate = LinkParser.parse('$url\n$url 提取码：a123');
      expect(duplicate.single.passcode, 'a123');
    },
  );
}
