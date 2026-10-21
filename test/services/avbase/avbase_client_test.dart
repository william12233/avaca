import 'package:avaca/services/avbase/avbase_client.dart';
import 'package:avaca/services/avbase/avbase_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'uses direct talent route and continues through AvBase pagination',
    () async {
      final transport = _FakeAvBaseTransport();
      final client = AvBaseClient(transport: transport, maxPages: 3);

      final search = await client.searchActresses('石川澪');
      final firstPage = await client.fetchActressPage(search.single.uri);
      final pageProgress = <(int, int, int)>[];
      final collection = await client.fetchAllActressWorks(
        search.single.uri,
        firstPage: firstPage,
        onProgress: (current, total, discovered) =>
            pageProgress.add((current, total, discovered)),
      );

      expect(search.single.uri.path, '/talents/${Uri.encodeComponent('石川澪')}');
      expect(collection.works.map((work) => work.code), [
        'MIZD-549',
        'MIZD-550',
      ]);
      expect(collection.issues, isEmpty);
      expect(pageProgress, [(1, 2, 1), (2, 2, 2)]);
      expect(
        transport.requests.any((uri) => uri.queryParameters['page'] == '1'),
        isTrue,
      );
    },
  );

  test('resolves an exact work code through the source search route', () async {
    final transport = _FakeAvBaseTransport();
    final client = AvBaseClient(transport: transport);

    final details = await client.fetchWorkDetailsByCode('SETH-012');

    expect(details.code, 'SETH-012');
    expect(transport.requests[0].path, '/works');
    expect(transport.requests[0].queryParameters['q'], 'SETH-012');
    expect(transport.requests[1].path, '/works/sodcreate:SETH-012');
  });
}

final class _FakeAvBaseTransport implements AvBaseTransport {
  final requests = <Uri>[];

  @override
  Future<String> get(Uri uri) async {
    requests.add(uri);
    if (uri.path == '/works' && uri.queryParameters['q'] == 'SETH-012') {
      return '<a href="/works/sodcreate:SETH-012">SETH-012</a>';
    }
    if (uri.path == '/works/sodcreate:SETH-012') {
      return '''
        <html><body><h1>SETH-012 制服限定</h1>
        <dl><dt>発売日</dt><dd>2024/06/17</dd></dl>
        </body></html>
      ''';
    }
    if (uri.queryParameters['page'] == '1') {
      return _talentPage(code: 'MIZD-550', pageLinks: '');
    }
    return _talentPage(
      code: 'MIZD-549',
      pageLinks: '<a href="?q=&page=0">0</a><a href="?q=&page=1">1</a>',
    );
  }

  String _talentPage({required String code, required String pageLinks}) {
    return '''
      <html><body>
        <h1>石川澪</h1>
        <div class="bg-background border border-light rounded-lg overflow-hidden h-full">
          <a data-slot="button" href="/works/$code">$code title</a>
        </div>
        $pageLinks
      </body></html>
    ''';
  }
}
