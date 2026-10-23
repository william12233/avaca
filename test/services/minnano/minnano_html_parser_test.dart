import 'package:avaca/services/minnano/minnano_html_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const pageUri = 'https://www.minnano-av.com/actress618082.html';
  const workUri = 'https://www.minnano-av.com/av195939.html';

  test('parses Minnano actress profile and semantic work rows', () {
    const source = '''
      <h2>小湊よつ葉 （こみなとよつは / Kominato Yotsuha）</h2>
      <table>
        <tr><td><span>別名</span><p>井上理香子【アイドル】 （いのうえりかこ / Inoue Rikako）</p></td></tr>
        <tr><td><span>生年月日</span><p>1996年05月29日（現在 30歳）</p></td></tr>
        <tr><td><span>サイズ</span><p>T154 / B83(Cカップ) / W59 / H80 / S</p></td></tr>
      </table>
      <img src="/p_actress_125_125/022/618082.jpg?newav">
      <table class="tbllist av">
        <tr><th>作品タイトル</th><th>発売日</th></tr>
        <tr><td><a href="av195939.html"><h3 class="ttl">催罠光線で支配された金髪ギャル 小湊よつ葉</h3></a></td><td>2026/05/18</td></tr>
      </table>
    ''';

    final page = MinnanoHtmlParser().parseActressPage(
      source,
      pageUri: Uri.parse(pageUri),
    );

    expect(page.details.name, '小湊よつ葉');
    expect(page.details.birthDate, '1996-05-29');
    expect(page.details.height, '154');
    expect(page.details.cup, 'C');
    expect(page.details.bwh, 'B83 / W59 / H80');
    expect(page.aliases, ['井上理香子']);
    expect(page.details.avatarUrl?.toString(), contains('/p_actress_125_125/'));
    expect(page.works.single.detailUri.toString(), workUri);
    expect(page.works.single.releaseDate, '2026-05-18');
    expect(page.works.single.code, isNull);
  });

  test('parses Minnano work code, maker, performers, and package image', () {
    const source = '''
      <table class="prof-table">
        <tr><td>作品名</td><td><h2>催罠光線で支配された金髪ギャル 小湊よつ葉</h2></td></tr>
        <tr><td>品番</td><td><span class="product-code-copy" data-code="START-489">START-489</span></td></tr>
        <tr><td>発売日</td><td>2026年05月 18日</td></tr>
        <tr><td>メーカー/レーベル</td><td><a>SODクリエイト</a> / <a>SODSTAR</a></td></tr>
        <tr><td>出演者</td><td><a href="../actress618082.html">小湊よつ葉</a></td></tr>
      </table>
      <img class="jacket-image" src="p_package/2605/195939.jpg">
    ''';

    final details = MinnanoHtmlParser().parseWorkPage(
      source,
      pageUri: Uri.parse(workUri),
    );

    expect(details.code, 'START-489');
    expect(details.title, contains('小湊よつ葉'));
    expect(details.releaseDate, '2026-05-18');
    expect(details.studio, 'SODクリエイト');
    expect(details.publisher, 'SODSTAR');
    expect(details.performerCount, 1);
    expect(details.imageUris.single.toString(), contains('/p_package/'));
  });

  test('parses a direct actress profile from its canonical link', () {
    const source = '''
      <head>
        <link rel="canonical" href="https://www.minnano-av.com/actress945093.html">
      </head>
      <body><h1>河北彩花（かわきたさいか / Kawakita Saika）</h1></body>
    ''';

    final results = MinnanoHtmlParser().parseActressSearchResults(
      source,
      pageUri: Uri.parse(
        'https://www.minnano-av.com/search_result.php?search_scope=actress',
      ),
    );

    expect(results, hasLength(1));
    expect(results.single.name, '河北彩花');
    expect(
      results.single.uri.toString(),
      'https://www.minnano-av.com/actress945093.html',
    );
  });

  test('deduplicates canonical direct profiles already listed as anchors', () {
    const source = '''
      <head>
        <link rel="canonical" href="/actress945093.html">
      </head>
      <body>
        <h2>河北彩花（かわきたさいか）</h2>
        <a href="/actress945093.html">河北彩花</a>
      </body>
    ''';

    final results = MinnanoHtmlParser().parseActressSearchResults(
      source,
      pageUri: Uri.parse('https://www.minnano-av.com/search_result.php'),
    );

    expect(results, hasLength(1));
    expect(results.single.name, '河北彩花');
  });

  test('does not create a result from an unsafe or non-actress canonical link', () {
    const sources = [
      '<link rel="canonical" href="/av195939.html"><h1>河北彩花</h1>',
      '<link rel="canonical" href="http://www.minnano-av.com/actress945093.html"><h1>河北彩花</h1>',
      '<link rel="canonical" href="https://example.com/actress945093.html"><h1>河北彩花</h1>',
      '<link rel="canonical" href="/actress945093.html">',
    ];

    for (final source in sources) {
      final results = MinnanoHtmlParser().parseActressSearchResults(
        source,
        pageUri: Uri.parse('https://www.minnano-av.com/search_result.php'),
      );

      expect(results, isEmpty, reason: source);
    }
  });
}
