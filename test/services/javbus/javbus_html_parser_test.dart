import 'package:avaca/services/javbus/javbus_html_parser.dart';
import 'package:avaca/services/javbus/javbus_models.dart';
import 'package:avaca/services/scrape/scrape_models.dart';
import 'package:avaca/models/scrape_source_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final parser = JavBusHtmlParser();

  test('parses actress details, works and pagination from an actress page', () {
    final page = parser.parseActressPage(
      _actressHtml,
      pageUri: Uri.parse('https://www.javbus.com/star/uly'),
    );

    expect(page.details.name, '涼森れむ');
    expect(
      page.details.avatarUrl.toString(),
      'https://www.javbus.com/pics/actress/uly_a.jpg',
    );
    expect(page.details.birthDate, '1997-12-03');
    expect(page.details.height, '160');
    expect(page.details.cup, 'D');
    expect(page.details.bust, '87');
    expect(page.details.waist, '58');
    expect(page.details.hip, '85');
    expect(page.pageCount, 2);
    expect(page.works.map((work) => work.code), ['ABF-183', 'FC2-123']);
    expect(page.works.map((work) => work.rawCode), ['ABF-183', 'FC2-123']);
    expect(page.works.first.title, '第一部作品');
    expect(page.works.first.releaseDate, '2024-07-16');
    expect(
      page.works.first.detailUri.toString(),
      'https://www.javbus.com/ABF-183',
    );
  });

  test('parses selected detail fields from a work page', () {
    final work = parser.parseWorkPage(
      _workHtml,
      pageUri: Uri.parse('https://www.javbus.com/ABF-183'),
    );

    expect(work.code, 'ABF-183');
    expect(work.rawCode, 'ABF-183');
    expect(work.title, '詳細作品標題');
    expect(work.releaseDate, '2024-07-16');
    expect(work.durationMinutes, 120);
    expect(work.studio, 'プレステージ');
    expect(work.publisher, 'ABS');
    expect(work.series, 'PRESTIGE PREMIUM');
    expect(work.provenanceFacts.genres, ['高畫質', '女上位']);
    expect(work.provenanceFacts.tags, ['高畫質', '女上位']);
    expect(work.catalogEvidence.single.source, ScrapeSourceId.javbus);
    expect(work.catalogEvidence.single.code, 'ABF-183');
    expect(work.catalogEvidence.single.manufacturer, 'プレステージ');
    expect(work.catalogEvidence.single.series, 'PRESTIGE PREMIUM');
  });

  test('removes V T and VT edition suffixes from scraped work codes', () {
    final actressPage = parser.parseActressPage('''
      <a class="movie-box" href="/STARS-859-V"><date>STARS-859-V</date></a>
      <a class="movie-box" href="/STARS-757-T"><date>STARS-757-T</date></a>
      <a class="movie-box" href="/STARS-715-VT"><date>STARS-715-VT</date></a>
      <a class="movie-box" href="/STARS-859-VR"><date>STARS-859-VR</date></a>
      <a class="movie-box" href="/FC2-PPV_123-999"><date>FC2-PPV_123-999</date></a>
      ''', pageUri: Uri.parse('https://www.javbus.com/star/zen'));
    final details = parser.parseWorkPage('''
      <h3>STARS-859-V 特典版標題</h3>
      <div class="info"><p><span class="header">識別碼:</span> STARS-859-V</p></div>
      ''', pageUri: Uri.parse('https://www.javbus.com/STARS-859-V'));

    expect(actressPage.works.map((work) => work.code), [
      'STARS-859',
      'STARS-757',
      'STARS-715',
      'STARS-859-VR',
      'FC2-PPV_123-999',
    ]);
    expect(details.code, 'STARS-859');
    expect(details.rawCode, 'STARS-859-V');
    expect(details.title, '特典版標題');
  });

  test('keeps a separatorless code available to the new scrape identity', () {
    final page = parser.parseActressPage(
      '<a class="movie-box" href="/SIVR00303">'
      '<div class="photo-info"><span>作品</span>'
      '<date>SIVR00303</date><date>2024-01-01</date></div></a>',
      pageUri: Uri.parse('https://www.javbus.com/star/zen'),
    );

    expect(page.works.single.code, 'SIVR00303');
    expect(page.works.single.rawCode, 'SIVR00303');
    expect(page.works.single.catalogEvidence.single.code, 'SIVR00303');
    expect(
      page.works.single.catalogEvidence.single.source,
      ScrapeSourceId.javbus,
    );
  });

  test('does not promote weak JavBus co-performance wording', () {
    final hint = parser.parseWorkPage(
      '<h3>HINT-001 豪華共演コラボ</h3>',
      pageUri: Uri.parse('https://www.javbus.com/HINT-001'),
    );
    final proven = parser.parseWorkPage(
      '<h3>PROVEN-001 全員同時出演・全編撮り下ろし新作</h3>',
      pageUri: Uri.parse('https://www.javbus.com/PROVEN-001'),
    );

    expect(
      hint.provenanceFacts.coPerformance,
      ScrapeCoPerformance.possibleSharedProduction,
    );
    expect(
      proven.provenanceFacts.coPerformance,
      ScrapeCoPerformance.sharedProduction,
    );
  });

  test('keeps JavBus lineage, split, and independent-segment facts narrow', () {
    JavBusWorkDetails parse(String title) => parser.parseWorkPage(
      '<html><body><h3>MATRIX-001 $title</h3></body></html>',
      pageUri: Uri.parse('https://www.javbus.com/MATRIX-001'),
    );

    for (final title in const ['BEST11人', 'BEST COLLECTION', '全12作', '総集編']) {
      final facts = parse(title).provenanceFacts;
      expect(facts.containsPriorWorks, isNull, reason: title);
    }
    for (final title in const ['過去作品を収録', '既存作品を再収録', '旧作4本を収録']) {
      expect(
        parse(title).provenanceFacts.containsPriorWorks,
        isTrue,
        reason: title,
      );
    }
    for (final title in const [
      '完全撮り下ろし特典映像',
      '特典映像は全編撮り下ろし',
      '完全新撮ボーナス映像',
      '全編撮り下ろし特典',
      '全編撮り下ろしの特典映像',
      '完全新撮による特典映像',
      '全編新撮で収録した特典映像',
      '完全撮り下ろしのボーナス映像',
      '特典として全編撮り下ろし',
      'ボーナス映像は完全新撮',
    ]) {
      expect(
        parse(title).provenanceFacts.explicitOriginalProduction,
        isNull,
        reason: title,
      );
    }
    for (final title in const [
      '全編新撮の大型共演',
      '完全新撮作品',
      '完全撮り下ろし作品',
      '全編撮り下ろし新作',
    ]) {
      expect(
        parse(title).provenanceFacts.explicitOriginalProduction,
        isTrue,
        reason: title,
      );
    }
    for (final title in const [
      '旧作を完全収録',
      '過去作を完全収録',
      '既存作品を完全収録',
      '旧作品を厳選完全収録',
      '過去作品を厳選して収録',
    ]) {
      expect(
        parse(title).provenanceFacts.containsPriorWorks,
        isTrue,
        reason: title,
      );
    }

    for (final title in const ['個別', '各', '各作品', 'それぞれ', '分割', 'split']) {
      final facts = parse(title).provenanceFacts;
      expect(facts.coPerformance, ScrapeCoPerformance.unknown, reason: title);
      expect(facts.splitFromPriorWork, isNull, reason: title);
    }
    for (final title in const [
      '分割版',
      '分割販売',
      '元作品から分割',
      '個別版',
      '単独版',
      'split edition',
      'split from prior work',
    ]) {
      expect(
        parse(title).provenanceFacts.splitFromPriorWork,
        isTrue,
        reason: title,
      );
    }
    for (final title in const [
      '各女優それぞれ別作品を収録',
      '出演者ごとの独立作品',
      'それぞれ別作品から収録',
      '各作品を個別収録',
      '独立した3作品をまとめて収録',
    ]) {
      expect(
        parse(title).provenanceFacts.coPerformance,
        ScrapeCoPerformance.independentSegments,
        reason: title,
      );
    }
  });

  test('shares strong re-edit and reissue semantics with the evaluator', () {
    JavBusWorkDetails parse(String title) => parser.parseWorkPage(
      '<html><body><h3>MATRIX-SEMANTIC $title</h3></body></html>',
      pageUri: Uri.parse('https://www.javbus.com/MATRIX-SEMANTIC'),
    );

    for (final title in const [
      'ディレクターズカット版',
      "director's cut",
      'directors cut',
      '再編集版',
      're-edited',
    ]) {
      expect(parse(title).provenanceFacts.reedited, isTrue, reason: title);
    }
    for (final title in const [
      '再販版',
      '再販商品',
      '再リリース',
      'REPLAY版',
      're-release',
      '未公開映像収録のプレミアムエディション',
    ]) {
      expect(parse(title).provenanceFacts.reissue, isTrue, reason: title);
    }
    for (final title in const ['未公開映像', 'プレミアムエディション', '完全版', 'マルチアングル編集']) {
      final facts = parse(title).provenanceFacts;
      expect(facts.reissue, isNull, reason: title);
      expect(facts.reedited, isNull, reason: title);
    }

    final codeOnlyMarker = parser.parseWorkPage(
      '<html><body><h3>MATRIX-REEDIT 未公開映像</h3></body></html>',
      pageUri: Uri.parse('https://www.javbus.com/MATRIX-REEDIT'),
    );
    expect(codeOnlyMarker.provenanceFacts.reissue, isNull);
    expect(codeOnlyMarker.provenanceFacts.reedited, isNull);
  });

  test('only promotes explicit JavBus shared-production propositions', () {
    JavBusWorkDetails parse(String title) => parser.parseWorkPage(
      '<html><body><h3>MATRIX-SHARED $title</h3></body></html>',
      pageUri: Uri.parse('https://www.javbus.com/MATRIX-SHARED'),
    );

    for (final title in const ['一堂に会して', '全員参加', '同じ現場で', '全員が同一企画に参加']) {
      expect(
        parse(title).provenanceFacts.coPerformance,
        isNot(ScrapeCoPerformance.sharedProduction),
        reason: title,
      );
    }
    for (final title in const [
      '全員同時出演',
      '同一シーンで共演',
      '同一撮影企画',
      '同一収録で全員共演',
      '全編撮り下ろし大共演',
      '完全新撮の大型共演',
    ]) {
      expect(
        parse(title).provenanceFacts.coPerformance,
        ScrapeCoPerformance.sharedProduction,
        reason: title,
      );
    }
  });

  test('parses unique actresses only from the work actress section', () {
    final work = parser.parseWorkPage(
      _multiActressWorkHtml,
      pageUri: Uri.parse('https://www.javbus.com/DOCD-096'),
    );

    expect(work.actressUris.map((uri) => uri.toString()), [
      'https://www.javbus.com/star/14jf',
      'https://www.javbus.com/star/1426',
    ]);
    expect(work.performers?.map((performer) => performer.name), [
      '喜多川みら',
      '谷村凪咲',
    ]);
    expect(
      work.performers?.map((performer) => performer.sourceUri.toString()),
      ['https://www.javbus.com/star/14jf', 'https://www.javbus.com/star/1426'],
    );
  });

  test('treats empty and placeholder actress images as unavailable', () {
    final empty = parser.parseActressPage(
      '<div class="avatar-box"><img src=""><div class="photo-info"><span>小湊よつ葉</span></div></div>',
      pageUri: Uri.parse('https://www.javbus.com/star/zen'),
    );
    final placeholder = parser.parseActressPage(
      '<div class="avatar-box"><img src="https://pics.dmm.co.jp/mono/actjpgs/nowprinting.gif"><div class="photo-info"><span>星まりあ</span></div></div>',
      pageUri: Uri.parse('https://www.javbus.com/star/muw'),
    );

    expect(empty.details.avatarUrl, isNull);
    expect(placeholder.details.avatarUrl, isNull);
  });

  test('parses actress search results and resolves relative links', () {
    final results = parser.parseActressSearchResults(
      _searchHtml,
      pageUri: Uri.parse('https://www.javbus.com/searchstar/remu'),
    );

    expect(results, hasLength(1));
    expect(results.single.name, '涼森れむ');
    expect(results.single.uri.toString(), 'https://www.javbus.com/star/uly');
  });
}

const _actressHtml = '''
<html><body>
  <div class="avatar-box">
    <div class="photo-frame"><img src="/pics/actress/uly_a.jpg"></div>
    <div class="photo-info">
      <span>涼森れむ</span>
      <p>生日: 1997-12-03</p><p>身高: 160cm</p><p>罩杯: D</p>
      <p>胸圍: 87cm</p><p>腰圍: 58cm</p><p>臀圍: 85cm</p>
    </div>
  </div>
  <a class="movie-box" href="/ABF-183">
    <div class="photo-info"><span>第一部作品</span><date>ABF-183</date><date>2024-07-16</date></div>
  </a>
  <a class="movie-box" href="/FC2-123">
    <div class="photo-info"><span>排除作品</span><date>FC2-123</date><date>2024-06-01</date></div>
  </a>
  <ul class="pagination"><li><a href="/star/uly/1">1</a></li><li><a href="/star/uly/2">2</a></li></ul>
</body></html>
''';

const _workHtml = '''
<html><body>
  <h3>ABF-183 詳細作品標題</h3>
  <div class="info">
    <p><span class="header">識別碼:</span> ABF-183</p>
    <p><span class="header">發行日期:</span> 2024-07-16</p>
    <p><span class="header">長度:</span> 120分鐘</p>
    <p><span class="header">製作商:</span> <a>プレステージ</a></p>
    <p><span class="header">發行商:</span> <a>ABS</a></p>
    <p><span class="header">系列:</span> <a>PRESTIGE PREMIUM</a></p>
    <p class="header">類別:<span id="genre-toggle">+</span></p>
    <p>
      <span class="genre"><label><input type="checkbox"><a href="/genre/1">高畫質</a></label></span>
      <span class="genre"><label><input type="checkbox"><a href="/genre/2">女上位</a></label></span>
    </p>
  </div>
</body></html>
''';

const _searchHtml = '''
<html><body>
  <a class="avatar-box text-center" href="/star/uly">
    <div class="photo-info"><span class="mleft">涼森れむ<button>有碼</button></span></div>
  </a>
</body></html>
''';

const _multiActressWorkHtml = '''
<html><body>
  <a href="/star/unrelated">頁面其他女優</a>
  <h3>DOCD-096 多人作品</h3>
  <div class="info">
    <p><span class="header">識別碼:</span> DOCD-096</p>
    <p class="star-show"><span class="header">演員</span>:</p>
    <ul>
      <li><a href="/star/14jf">喜多川みら</a></li>
      <li><a href="/star/1426">谷村凪咲</a></li>
    </ul>
    <p>
      <a href="/star/14jf">喜多川みら</a>
      <a href="/star/1426">谷村凪咲</a>
    </p>
  </div>
</body></html>
''';
