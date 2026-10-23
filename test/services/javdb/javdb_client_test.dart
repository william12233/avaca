import 'package:avaca/services/javdb/javdb_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the native actor directory when JAVDB is reachable', () async {
    final transport = _FakeJavDbTransport('''
      <a href="/actors/abc"><img src="/avatars/abc.jpg">甲女</a>
      <a href="/actors/abc">甲女</a>
      <a href="/actors/xyz">乙女</a>
      <a href="/tags/label">作品標籤</a>
    ''');
    final client = JavDbClient(transport: transport);

    final page = await client.fetchActors();

    expect(transport.requested, [Uri.parse('https://javdb.com/actors')]);
    expect(page.items.map((item) => item.name), ['甲女', '乙女']);
    expect(page.items.first.uri.path, '/actors/abc');
    expect(page.items.first.imageUri?.path, '/avatars/abc.jpg');
  });

  test('surfaces Cloudflare or other HTTP failures as unavailable', () async {
    final uri = Uri.parse('https://javdb.com/');
    final transport = _FailingJavDbTransport(uri, 403);
    final client = JavDbClient(transport: transport);

    expect(
      client.checkConnection,
      throwsA(
        isA<JavDbRequestException>().having(
          (error) => error.statusCode,
          'statusCode',
          403,
        ),
      ),
    );
  });
}

final class _FakeJavDbTransport implements JavDbTransport {
  _FakeJavDbTransport(this.source);

  final String source;
  final requested = <Uri>[];

  @override
  Future<String> get(Uri uri) async {
    requested.add(uri);
    return source;
  }
}

final class _FailingJavDbTransport implements JavDbTransport {
  _FailingJavDbTransport(this.uri, this.statusCode);

  final Uri uri;
  final int statusCode;

  @override
  Future<String> get(Uri requested) async {
    throw JavDbRequestException(uri, statusCode);
  }
}
