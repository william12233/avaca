import 'package:flutter_test/flutter_test.dart';

import 'package:avaca/services/scrape_event_sanitizer.dart';

void main() {
  test('removes credentials, query strings, paths, and html', () {
    final value = ScrapeEventSanitizer.message(
      'Authorization: Bearer secret-token https://example.com/a?q=secret '
      r'C:\private\session.html <html>body</html>',
    );

    expect(value, isNot(contains('secret-token')));
    expect(value, isNot(contains('?q=')));
    expect(value, isNot(contains('private')));
    expect(value, isNot(contains('<html>')));
    expect(
      value.length,
      lessThanOrEqualTo(ScrapeEventSanitizer.maxMessageBytes),
    );
  });

  test('drops sensitive metadata keys and bounds collections', () {
    final sanitized = ScrapeEventSanitizer.metadata({
      'source': 'javbus',
      'Cookie': 'secret',
      'body': '<html>secret</html>',
      'codes': List<String>.generate(80, (index) => 'code-$index'),
    });

    expect(sanitized.containsKey('Cookie'), isFalse);
    expect(sanitized.containsKey('body'), isFalse);
    expect((sanitized['codes'] as List).length, 32);
  });
}
