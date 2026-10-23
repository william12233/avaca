import 'package:avaca/services/minnano/minnano_client.dart';
import 'package:avaca/services/minnano/minnano_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('connection check requests the Minnano homepage', () async {
    final transport = _RecordingMinnanoTransport();
    final client = MinnanoClient(transport: transport);

    await client.checkConnection();

    expect(transport.requested, [Uri.parse('https://www.minnano-av.com/')]);
  });

  test('fetches the actress ranking endpoint once', () async {
    final transport = _RecordingMinnanoTransport();
    final client = MinnanoClient(transport: transport);

    final ranking = await client.fetchActressRanking();

    expect(ranking.single.name, '甲女');
    expect(transport.requested.single.path, '/ranking_actress.php');
  });

  test('fetches the native actress directory instead of a ranking', () async {
    final transport = _RecordingMinnanoTransport();
    final client = MinnanoClient(transport: transport);

    final tags = await client.fetchActressTags();
    final list = await client.fetchActressList(
      Uri.parse('https://www.minnano-av.com/actress_list.php?tag_a_id=10093'),
    );

    expect(tags.first.key, 'all');
    expect(transport.requested[0].path, '/actress_list.html');
    expect(transport.requested[1].queryParameters['tag_a_id'], '10093');
    expect(list.items.single.name, '未歩なな');
  });

  test('keeps S1 discoverable when its native page is empty', () async {
    final transport = _EmptyMinnanoTransport();
    final client = MinnanoClient(transport: transport);

    final tags = await client.fetchActressTags();

    expect(tags.map((tag) => tag.key), contains('10093'));
    expect(
      transport.requested,
      contains(
        Uri.parse('https://www.minnano-av.com/actress_list.php?tag_a_id=10093'),
      ),
    );
  });

  test('uses the real search form and actress.php pagination shape', () async {
    final transport = _RecordingMinnanoTransport();
    final client = MinnanoClient(transport: transport);

    final matches = await client.searchActresses('小湊よつ葉');
    expect(matches.single.uri.toString(), contains('actress618082.html'));
    expect(
      transport.requested.first.queryParameters['search_scope'],
      'actress',
    );
    expect(transport.requested.first.queryParameters['search_word'], '小湊よつ葉');
    expect(transport.requested.first.queryParameters['search'], ' Go ');

    final firstPage = await client.fetchActressPage(matches.single.uri);
    final works = await client.fetchAllActressWorks(
      matches.single.uri,
      firstPage: firstPage,
    );

    expect(works.map((work) => work.detailUri.path), [
      '/av1.html',
      '/av2.html',
    ]);
    expect(
      transport.requested.any(
        (uri) =>
            uri.path == '/actress.php' &&
            uri.queryParameters['actress_id'] == '618082' &&
            uri.queryParameters['page'] == '2',
      ),
      isTrue,
    );
  });

  test(
    'returns an actress when search redirects to a direct profile page',
    () async {
      final transport = _RecordingMinnanoTransport();
      final client = MinnanoClient(transport: transport);

      final matches = await client.searchActresses('河北彩花');

      expect(matches, hasLength(1));
      expect(matches.single.name, '河北彩花');
      expect(
        matches.single.uri,
        Uri.parse('https://www.minnano-av.com/actress945093.html'),
      );
      expect(
        transport.requested.first.queryParameters['search_scope'],
        'actress',
      );
      expect(transport.requested.first.queryParameters['search_word'], '河北彩花');
    },
  );
}

final class _EmptyMinnanoTransport implements MinnanoTransport {
  final requested = <Uri>[];

  @override
  Future<String> get(Uri uri) async {
    requested.add(uri);
    return '<html><body></body></html>';
  }
}

final class _RecordingMinnanoTransport implements MinnanoTransport {
  final requested = <Uri>[];

  @override
  Future<String> get(Uri uri) async {
    requested.add(uri);
    if (uri.path == '/') {
      return '<html><body>ok</body></html>';
    }
    if (uri.path == '/search_result.php') {
      if (uri.queryParameters['search_word'] == '河北彩花') {
        return '''
          <link rel="canonical" href="https://www.minnano-av.com/actress945093.html">
          <h1>河北彩花（かわきたさいか）</h1>
        ''';
      }
      return '<a href="actress618082.html">小湊よつ葉</a>';
    }
    if (uri.path == '/ranking_actress.php') {
      return '''
        <script type="application/ld+json">
          {"@type":"ItemList","itemListElement":[
            {"@type":"ListItem","position":1,"url":"/actress1.html","name":"甲女"}
          ]}
        </script>
        <table class="tbllist"><tr><td>1</td><td>
          <a href="actress1.html"><img src="/p_actress_125_125/001/1.jpg">甲女</a>
        </td></tr></table>
      ''';
    }
    if (uri.path == '/actress_list.html') {
      return '<a href="actress_list.php?tag_a_id=10093">S1</a>';
    }
    if (uri.path == '/actress_list.php') {
      return '''
        <title>「S1」AV女優一覧 1名</title>
        <link rel="next" href="/actress_list.php?tag_a_id=10093&amp;page=2">
        <table class="tbllist"><tr><td><a href="actress205870.html">
          <img src="/p_actress_125_125/022/205870.jpg">
        </a></td><td><h2><a href="actress205870.html">未歩なな</a></h2></td></tr></table>
      ''';
    }
    if (uri.path == '/actress618082.html') {
      return _actressPage(
        '<tr><td><a href="av1.html"><h3 class="ttl">第一作</h3></a></td>'
        '<td>2026/05/18</td></tr>',
      );
    }
    if (uri.path == '/actress.php') {
      return _actressPage(
        '<tr><td><a href="av2.html"><h3 class="ttl">第二作</h3></a></td>'
        '<td>2026/05/19</td></tr>',
      );
    }
    throw StateError('Unexpected URI: $uri');
  }

  String _actressPage(String workRow) {
    return '''
      <h2>小湊よつ葉</h2>
      <table><tr><td><span>生年月日</span><p>1996年05月29日</p></td></tr></table>
      <table class="tbllist av">$workRow</table>
      <a href="/actress.php?actress_id=618082&page=2">2</a>
    ''';
  }
}
