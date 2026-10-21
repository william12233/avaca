// This test intentionally prints its aggregate and per-actress evidence.
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:avaca/core/database.dart';
import 'package:avaca/models/scrape_source_settings.dart';
import 'package:avaca/models/scraped_actress_details.dart';
import 'package:avaca/models/work_scrape_options.dart';
import 'package:avaca/services/avbase/avbase_client.dart';
import 'package:avaca/services/avbase/avbase_scrape_source.dart';
import 'package:avaca/services/avbase/avbase_transport.dart';
import 'package:avaca/services/avbase/avbase_html_parser.dart';
import 'package:avaca/services/javbus/work_image_downloader.dart';
import 'package:avaca/services/javbus/prefix_route_repository.dart';
import 'package:avaca/services/scrape/scrape_models.dart';
import 'package:avaca/services/scrape/scrape_source.dart';
import 'package:avaca/services/scrape_run_observer.dart';
import 'package:avaca/services/works_scrape_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Frozen, first-party AvBase card metadata observed on 2026-08-27.
///
/// This is intentionally an offline stress harness: the raw card/detail HTML
/// is rendered from these recorded values and then passed through
/// AvBaseHtmlParser, AvBaseScrapeSource, WorksScrapeService, typed identity,
/// catalog union, and the production evaluator. It is not a second
/// classifier and it is not a claim of a live end-to-end run.
enum _FrozenExpected { keep, exclude, review, failed }

final class _RecordedWork {
  const _RecordedWork({
    required this.actress,
    required this.code,
    required this.title,
    required this.manufacturer,
    required this.label,
    required this.expected,
    this.series,
    this.releaseDate = '2026-08-27',
    this.tags = const [],
    this.description,
    this.includedWorks = const [],
    this.includeInJavBus = false,
    this.detailsAvailable = true,
    this.requiredMaker,
  });

  final String actress;
  final String code;
  final String title;
  final String manufacturer;
  final String label;
  final String? series;
  final String releaseDate;
  final List<String> tags;
  final String? description;
  final List<String> includedWorks;
  final _FrozenExpected expected;
  final bool includeInJavBus;
  final bool detailsAvailable;
  final String? requiredMaker;
}

void main() {
  sqfliteFfiInit();

  test('runs the real-maker and large-actress frozen production stress set', () async {
    final allRecords = <_RecordedWork>[
      ..._frozenRecords,
      ..._majorMakerStressRecords,
      ..._largeActressStressRecords,
    ];
    final grouped = <String, List<_RecordedWork>>{};
    for (final work in allRecords) {
      grouped.putIfAbsent(work.actress, () => <_RecordedWork>[]).add(work);
    }

    final reports = <_FrozenStressReport>[];
    for (final entry in grouped.entries) {
      reports.add(await _runFrozenCase(entry.key, entry.value));
    }

    final naganoReport = reports.singleWhere(
      (report) => report.actress == '永野いち夏',
    );
    expect(naganoReport.uniqueCount, 12);
    expect(naganoReport.terminalKeepCount, 1);
    expect(naganoReport.terminalExcludeCount, 10);
    expect(naganoReport.terminalReviewCount, 1);
    expect(naganoReport.terminalFailedCount, 0);
    // WorksScrapeResult.saved is a persistence count and includes the row
    // retained for review (CJOB-216 is KEEP, HYAS-142 is KEEP+REVIEW).  The
    // report must use one terminal action per canonical identity instead.
    expect(naganoReport.result.saved, 2);

    final records = reports.expand((report) => report.records).toList();
    final observed = <String, _FrozenObservedOutcome>{
      for (final report in reports)
        for (final outcome in report.outcomes) outcome.code: outcome,
    };
    for (final record in records) {
      final outcome = observed[record.code];
      expect(outcome, isNotNull, reason: record.code);
      switch (record.expected) {
        case _FrozenExpected.keep:
          expect(outcome!.finalAction, 'keep', reason: record.code);
          expect(
            outcome.state,
            ScrapeWorkOutcomeState.saved,
            reason: record.code,
          );
        case _FrozenExpected.exclude:
          expect(outcome!.finalAction, 'exclude', reason: record.code);
          expect(
            outcome.state,
            ScrapeWorkOutcomeState.excluded,
            reason: record.code,
          );
        case _FrozenExpected.review:
          expect(outcome!.finalAction, 'keepReview', reason: record.code);
          expect(
            outcome.state,
            ScrapeWorkOutcomeState.review,
            reason: record.code,
          );
        case _FrozenExpected.failed:
          expect(
            outcome!.state,
            ScrapeWorkOutcomeState.failed,
            reason: record.code,
          );
      }
    }

    // The matrix is the dedicated per-maker batch plus the two supplemental
    // source slices: IdeaPocket's real BEST row and KMPVR's Arai expansion.
    // Other frozen rows remain regression/stress evidence but are not allowed
    // to turn an unrelated actress into a second matrix subject.
    final matrix = <String, List<_RecordedWork>>{};
    final matrixRecords = <_RecordedWork>[
      ..._majorMakerStressRecords,
      ..._frozenRecords.where(
        (record) =>
            record.requiredMaker == 'IdeaPocket' ||
            record.requiredMaker == 'KMPVR',
      ),
      ..._largeActressStressRecords.where(
        (record) => record.requiredMaker == 'KMPVR',
      ),
    ];
    for (final record in matrixRecords) {
      final maker = record.requiredMaker;
      if (maker != null) {
        matrix.putIfAbsent(maker, () => <_RecordedWork>[]).add(record);
      }
    }
    expect(matrix.keys, containsAll(_requiredMakers));
    final orderedMakers = _requiredMakers.toList()..sort();
    for (final maker in orderedMakers) {
      final makerRecords = matrix[maker]!;
      expect(
        makerRecords.length >= 10 ||
            _completeKnownSourceSliceMakers.contains(maker),
        isTrue,
        reason: '$maker does not meet the >=10 or complete-known-slice rule',
      );
      for (final record in makerRecords.where(
        (record) => record.expected == _FrozenExpected.keep,
      )) {
        expect(observed[record.code]!.finalAction, 'keep', reason: record.code);
        expect(
          observed[record.code]!.reasonCodes,
          isNot(contains('reuse_family_unresolved')),
          reason: record.code,
        );
      }
    }

    print('MAKER_ACTRESS_MATRIX');
    for (final maker in orderedMakers) {
      final makerRecords = matrix[maker]!;
      final actresses = makerRecords.map((record) => record.actress).toSet();
      final makerOutcomes = <_FrozenObservedOutcome>[
        for (final record in makerRecords) observed[record.code]!,
      ];
      final makerCounts = <String, int>{};
      for (final outcome in makerOutcomes) {
        makerCounts.update(
          outcome.finalAction,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
      final clusters = <String, List<String>>{};
      for (final record in makerRecords) {
        final outcome = observed[record.code]!;
        final clusterKey =
            'maker=${record.manufacturer}|prefix=${_reportPrefix(record.code)}|'
            'series=${record.series ?? '-'}|reasonCode=${outcome.reasonCodes.join('|')}|'
            'finalAction=${outcome.finalAction}';
        clusters.putIfAbsent(clusterKey, () => <String>[]).add(record.code);
      }
      final clusterText = clusters.entries
          .map((entry) => '${entry.key}|codes=${entry.value.join(',')}')
          .join(' || ');
      final normalExamples = makerRecords
          .where((record) => record.expected == _FrozenExpected.keep)
          .map((record) => record.code)
          .join(',');
      final derivedExamples = makerRecords
          .where((record) => record.expected == _FrozenExpected.exclude)
          .map((record) => record.code)
          .join(',');
      final reviewCases = makerRecords
          .where((record) => record.expected == _FrozenExpected.review)
          .map((record) => record.code)
          .join(',');
      print(
        '  MAKER: $maker ACTRESS: ${actresses.join('|')} '
        'RAW: ${_rawForRecords(makerRecords)} CANONICAL: ${makerRecords.length} '
        'KEEP: ${makerCounts['keep'] ?? 0} EXCLUDE: ${makerCounts['exclude'] ?? 0} '
        'REVIEW: ${makerCounts['keepReview'] ?? 0} FAILED: ${makerCounts['failed'] ?? 0} '
        'NORMAL_EXAMPLES: ${normalExamples.isEmpty ? 'NONE' : normalExamples} '
        'DERIVED_EXAMPLES: ${derivedExamples.isEmpty ? 'NO_VERIFIED_DERIVED_CASE_FOUND' : derivedExamples} '
        'REVIEW_CASES: ${reviewCases.isEmpty ? 'NONE' : reviewCases} '
        'SYSTEMATIC_CLUSTER: $clusterText '
        'PASS: ${actresses.length == 1 && makerRecords.isNotEmpty}',
      );
    }

    // The same-maker MOODYZ distinction is an explicit regression boundary:
    // MNGS is a normal production, while MIZD-498 is a real MOODYZ Best
    // collection. MIRD counterexamples are covered independently in the
    // evaluator regression test and are deliberately not production rules.
    expect(observed['MNGS-074']!.finalAction, 'keep');
    expect(observed['MIZD-498']!.finalAction, 'exclude');

    final raw = reports.fold<int>(
      0,
      (sum, report) => sum + report.rawDiscovered,
    );
    final unique = reports.fold<int>(
      0,
      (sum, report) => sum + report.uniqueCount,
    );
    final duplicates = reports.fold<int>(
      0,
      (sum, report) => sum + report.duplicateCount,
    );
    final counts = <String, int>{};
    for (final outcome in observed.values) {
      counts.update(
        outcome.finalAction,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    print(
      'FROZEN_PRODUCTION_STRESS '
      'raw=$raw canonical=$unique duplicates=$duplicates '
      'KEEP=${counts['keep'] ?? 0} EXCLUDE=${counts['exclude'] ?? 0} '
      'REVIEW=${counts['keepReview'] ?? 0} FAILED=${counts['failed'] ?? 0}',
    );
    for (final report in reports) {
      print(report.render(observed));
    }
  });
}

const _requiredMakers = <String>{
  'S1',
  'SOD',
  'MOODYZ',
  'Prestige',
  'kawaii*',
  'IdeaPocket',
  'Attackers',
  'Madonna',
  'OPPAI',
  'DAS!',
  'WANZ',
  'kira☆kira',
  'ROOKIE',
  'KMP',
  'KMPVR',
};

const _completeKnownSourceSliceMakers = <String>{'ROOKIE', 'kira☆kira'};

const _frozenRecords = <_RecordedWork>[
  // 新井リマ: a meaningful first-page slice with normal, bare-BEST safety,
  // explicit BEST/lineage, mixed-family, and cross-label records captured
  // from the AvBase talent route/search.
  _RecordedWork(
    actress: '新井リマ',
    code: 'MNGS-074',
    title: 'くぱぁ おま○こ丸出し大陰唇＆小陰唇掻き分け膣口開きっぱなし120分 新井リマ',
    manufacturer: 'ムーディーズ',
    label: 'MOODYZ ニュージーニアス',
    expected: _FrozenExpected.keep,
    includeInJavBus: true,
  ),
  _RecordedWork(
    actress: '新井リマ',
    code: 'MNGS-075',
    title:
        'ヒーローバイトの上司（レッド担当）の告白を断ったらセクハラされ放題輪●され放題のハイレグピンク（=中出し肉便器担当）にさせられた私 新井リマ',
    manufacturer: 'ムーディーズ',
    label: 'MOODYZ ニュージーニアス',
    expected: _FrozenExpected.keep,
    includeInJavBus: true,
  ),
  _RecordedWork(
    actress: '新井リマ',
    code: 'MIZD-547',
    title: '美少女J系のマンマン食い込み無自覚パンチラ眺めて爆射したいVol.2',
    manufacturer: 'ムーディーズ',
    label: 'MOODYZ Best',
    series: '美少女J系のマンマン食い込み無自覚パンチラ眺めて爆射したい',
    expected: _FrozenExpected.exclude,
  ),
  _RecordedWork(
    actress: '新井リマ',
    code: 'VRKM-1876',
    title: '【VR】美女のイキ顔を眺めながら子宮を突きまくれ！ザーメンを奥深く注ぎ込む孕ませ射精の嵐！ 正常位 子宮中出しBEST300分',
    manufacturer: 'ケイ・エム・プロデュース',
    label: 'KMPVR',
    series: 'VR BEST',
    expected: _FrozenExpected.exclude,
    requiredMaker: 'KMPVR',
  ),
  _RecordedWork(
    actress: '新井リマ',
    code: 'VRKM-1861',
    title: '【VR】逆レ×プノーカット男を完全イカセ支配！ 1128分BEST Part2',
    manufacturer: 'ケイ・エム・プロデュース',
    label: 'KMPVR',
    series: 'VR BEST',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    includeInJavBus: true,
    requiredMaker: 'KMPVR',
  ),
  _RecordedWork(
    actress: '新井リマ',
    code: 'WAAA-681',
    title: '無料で気持ちよくしてあげる 憧れの義姉がメンズエステで働くことになり練習役になった僕は際どい鼠蹊部マッサージに理性崖っぷち 新井リマ',
    manufacturer: 'ワンズファクトリー',
    label: 'WANZ',
    expected: _FrozenExpected.keep,
    includeInJavBus: true,
  ),
  _RecordedWork(
    actress: '新井リマ',
    code: 'WAAA-675',
    title: '「舐めたら興奮して尻穴ヒクヒクしちゃう」ノーパンJ系がガニ股フェラでアナル丸見せ挑発！ 新井リマ',
    manufacturer: 'ワンズファクトリー',
    label: 'WANZ',
    expected: _FrozenExpected.keep,
  ),
  _RecordedWork(
    actress: '新井リマ',
    code: 'DAZD-306',
    title: 'マ○コと喉奥を同時に串刺しサンドバックBEST',
    manufacturer: 'ダスッ！',
    label: 'ダスッ！',
    expected: _FrozenExpected.keep,
  ),
  _RecordedWork(
    actress: '新井リマ',
    code: 'DAZD-302',
    title: '爆揺れデカパイ＆イキ顔を見ながら同時イキ！正常位シンクロ中出し78連発 BEST！！',
    manufacturer: 'ダスッ！',
    label: 'ダスッ！',
    expected: _FrozenExpected.keep,
    includeInJavBus: true,
  ),
  _RecordedWork(
    actress: '新井リマ',
    code: 'PPBD-322',
    title: '【シンクロ挟射特化】カウントダウン字幕付きパイズリ射精の瞬間に合わせられるオナニー映像80連発',
    manufacturer: 'OPPAI',
    label: 'OPPAI',
    expected: _FrozenExpected.keep,
    includeInJavBus: true,
  ),
  _RecordedWork(
    actress: '新井リマ',
    code: 'PPBD-318',
    title: '2020～2025OPPAIベストプロポーション 圧倒的な存在感で令和のAV界を盛り上げた巨乳女優72名470分',
    manufacturer: 'OPPAI',
    label: 'OPPAI',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
  ),
  _RecordedWork(
    actress: '新井リマ',
    code: 'KIBD-354',
    title: '幼なじみの生意気ギャルと保健室のベッドで偶然隣になり、学校サボって一日中精子枯れるまでヤリまくり！240分完全保存版',
    manufacturer: 'kira☆kira',
    label: 'kira☆kira',
    series: '学校サボって一日中精子枯れるまでヤリまくり！',
    expected: _FrozenExpected.keep,
    includeInJavBus: true,
  ),
  _RecordedWork(
    actress: '新井リマ',
    code: 'KIBD-349',
    title: 'エグい程下品な女、全員集合！何も考えずにひたすらヌケる8時間スペシャルBEST vol.3',
    manufacturer: 'kira☆kira',
    label: 'kira☆kira',
    series: 'エグい程下品な女',
    expected: _FrozenExpected.exclude,
  ),
  _RecordedWork(
    actress: '新井リマ',
    code: 'KAVR-472',
    title:
        '【VR】kawaii＊8KVRベストSEXシーン1コーナー丸ごとノーカット収録まだまだ原石、たくさんいます！推しが見つかる大ボリューム1000分オーバー',
    manufacturer: 'kawaii',
    label: 'kawaii* VR',
    series: 'kawaii*VR',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
  ),
  _RecordedWork(
    actress: '出口結絆',
    code: 'KAVR-422',
    title:
        '【VR】誘惑むちむち太もも絶対領域 ミニスカート×ニーハイ×パンチラ 超絶景誘惑してくる軽音楽部（ドラマー）の後輩「出口さん」 出口結絆',
    manufacturer: 'kawaii',
    label: 'kawaii* VR',
    series: 'kawaii*VR',
    releaseDate: '2025-05-28',
    expected: _FrozenExpected.keep,
  ),
  _RecordedWork(
    actress: '新井リマ',
    code: 'KWBD-423',
    title: 'ミニマム女子がペロペロ舐めてくれるから可愛がりたくなる！本物ロリっ娘おしゃぶり100発超 8時間',
    manufacturer: 'kawaii',
    label: 'kawaii',
    series: 'kawaii*ベスト',
    expected: _FrozenExpected.exclude,
  ),
  _RecordedWork(
    actress: '新井リマ',
    code: 'MNGS-065',
    title:
        '『 元気な精子をしっかり貯めて家に帰ってねw』妊活中の妻にオナ禁させられて 禁欲中の気晴らしで【ヌキなし回春】に行ったら出てきたのは【妻の親友】・新井さんだった！ 新井リマ',
    manufacturer: 'ムーディーズ',
    label: 'MOODYZ ニュージーニアス',
    expected: _FrozenExpected.keep,
  ),

  // 沢北みなみ: the AvBase alias/search result resolves to a real catalog
  // containing the exact performer name. This slice intentionally includes
  // normal individual works and concrete BEST/complete collections.
  _RecordedWork(
    actress: '沢北みなみ',
    code: 'TENN-045',
    title: '種付け生中出し！厳選美少女 7名300分',
    manufacturer: 'First Star',
    label: '天女(First Star)',
    expected: _FrozenExpected.keep,
  ),
  _RecordedWork(
    actress: '沢北みなみ',
    code: 'HHKL-191',
    title:
        '「あの時の続きしよう…」「覚えてるよね？？」「あの日のエッチな見せ合いっこの続き…」幼い頃、遊びでお互いの性器を見せ合いっこした幼馴染が超絶美少女になって戻ってきて大人になってからも見せ合い！毛が生えて大人になったボクたちは… 沢北みなみ',
    manufacturer: 'Hunter',
    label: 'HHHグループ',
    series: 'プレミアム☆セレクト',
    expected: _FrozenExpected.keep,
    includeInJavBus: true,
  ),
  _RecordedWork(
    actress: '沢北みなみ',
    code: 'ORECS-305',
    title: '責め経験ほぼゼロのうぶな女子たちが、底知れぬM心に触発されドS痴女性が開花！みなみちゃんめいちゃん',
    manufacturer: '俺の素人-Z- SECOND IMPACT',
    label: '俺の素人-Z- SECOND IMPACT',
    series: 'ドS痴女性が開花！',
    expected: _FrozenExpected.keep,
  ),
  _RecordedWork(
    actress: '沢北みなみ',
    code: 'RVG-240',
    title: '変質者のヤリ部屋に監禁されてセックス漬けの毎日…快楽堕ちしてオチ〇ポ中毒女になりました',
    manufacturer: 'グローリークエスト',
    label: 'GLORY QUEST',
    expected: _FrozenExpected.keep,
  ),
  _RecordedWork(
    actress: '沢北みなみ',
    code: 'TENN-028',
    title: '絶対的美少女 種付け生出し7名 300分',
    manufacturer: 'First Star',
    label: '天女(First Star)',
    expected: _FrozenExpected.keep,
  ),
  _RecordedWork(
    actress: '沢北みなみ',
    code: 'KAGN-015',
    title: '【個撮】どこでもフェラ13 11人',
    manufacturer: 'かぐや姫Pt/妄想族',
    label: 'かぐや姫Pt',
    series: '【個撮】どこでもフェラ',
    expected: _FrozenExpected.keep,
  ),
  _RecordedWork(
    actress: '沢北みなみ',
    code: 'PPBD-298',
    title: '巨乳＆爆乳美少女達による射精直前のチ〇ポ丸呑みパイズリラッシュ420分BEST！',
    manufacturer: 'OPPAI',
    label: 'OPPAI',
    expected: _FrozenExpected.exclude,
  ),
  _RecordedWork(
    actress: '沢北みなみ',
    code: 'MIZD-381',
    title: '視界占有率100％美少女のマ〇コで窒息寸前！顔面騎乗BEST',
    manufacturer: 'ムーディーズ',
    label: 'MOODYZ Best',
    series: 'BEST（作品集）',
    expected: _FrozenExpected.exclude,
  ),
  _RecordedWork(
    actress: '沢北みなみ',
    code: 'MKCK-366',
    title: '’イイ身体’を追求するAVメーカー E-BODYプレミアムBEST2023 売上TOP57タイトル10時間',
    manufacturer: 'E-BODY',
    label: 'E-BODY',
    series: 'E-BODY BEST PROPORTIONS',
    expected: _FrozenExpected.exclude,
  ),
  _RecordedWork(
    actress: '沢北みなみ',
    code: 'MKCK-399',
    title: 'たぬき顔で巨乳ってズルくない？あざと可愛い美少女37名大集合 チ●ポの芯まで癒されSEX70本番8時間ベスト',
    manufacturer: 'E-BODY',
    label: 'E-BODY',
    series: 'E-BODY BEST PROPORTIONS',
    expected: _FrozenExpected.exclude,
    includeInJavBus: true,
  ),
  _RecordedWork(
    actress: '沢北みなみ',
    code: 'KAGP-381',
    title: '素人娘の全裸大図鑑11 5時間30人増刊号 今時の女の子が恥じらいながら脱衣していくヘアヌードコレクション ＋撮りおろし2人',
    manufacturer: 'かぐや姫Pt/妄想族',
    label: 'かぐや姫Pt',
    series: '素人娘の全裸大図鑑',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
  ),
  _RecordedWork(
    actress: '沢北みなみ',
    code: 'EBOD-998',
    title: 'コンビニバイト仲間で性格正反対の巨乳2人と交互に浮気SEXを繰り返す不貞な日々 柏木こなつ 沢北みなみ',
    manufacturer: 'E-BODY',
    label: 'E-BODY',
    expected: _FrozenExpected.keep,
    includeInJavBus: true,
  ),
  _RecordedWork(
    actress: '沢北みなみ',
    code: 'PPBD-282',
    title: 'おわん！釣鐘！半球！個性豊かな美バスト収録！！巨乳美少女達の乳ま〇こでイき果てる！射精直前パイズリラッシュ！99連発！！',
    manufacturer: 'OPPAI',
    label: 'OPPAI',
    expected: _FrozenExpected.keep,
  ),

  // 未歩なな: exact AvBase search results, including S1 originals outside
  // the OFJE derived-only family and several verified OFJE/RBB collections.
  _RecordedWork(
    actress: '未歩なな',
    code: 'SNOS-033',
    title:
        '未歩なな引退作 ガチファン感謝祭「私と勝負して勝ったらヤらせてあ・げ・る」引退だから本気でファンと向き合った泥と涙と体液まみれのSEX運動会',
    manufacturer: 'エスワン ナンバーワンスタイル',
    label: 'S1 NO.1 STYLE',
    expected: _FrozenExpected.keep,
  ),
  _RecordedWork(
    actress: '未歩なな',
    code: 'SIVR-452',
    title: '【VR】ずっとアナタの一番でいたい…今、いっちばん輝いてる未歩ななを目に焼き付けて… 未歩なな',
    manufacturer: 'エスワン ナンバーワンスタイル',
    label: 'S1 VR',
    series: 'S1 VR',
    expected: _FrozenExpected.keep,
  ),
  _RecordedWork(
    actress: '未歩なな',
    code: 'OFJE-659',
    title: 'S級美人が敗北の「もうダメェ！」 絶頂直後の敏感マ●コひっ捕え 快楽上乗せ追撃ピストン100本番',
    manufacturer: 'エスワン ナンバーワンスタイル',
    label: 'S1 NO.1 STYLE',
    series: 'S1 GIRLS COLLECTION',
    expected: _FrozenExpected.exclude,
    includeInJavBus: true,
  ),
  _RecordedWork(
    actress: '未歩なな',
    code: 'OFJE-711',
    title: 'MOODYZ×アイポケ×S1スペシャルコラボ！ AV界オールスター美女たちの乳首舐め手コキBEST100選！',
    manufacturer: 'エスワン ナンバーワンスタイル',
    label: 'S1 NO.1 STYLE',
    expected: _FrozenExpected.exclude,
  ),
  _RecordedWork(
    actress: '未歩なな',
    code: 'OFJE-704',
    title: '‘みんなが思う’ 日本一かわいい女子●生、集めました！ 制服着たままエッチしよう',
    manufacturer: 'エスワン ナンバーワンスタイル',
    label: 'S1 NO.1 STYLE',
    series: 'S1 GIRLS COLLECTION',
    expected: _FrozenExpected.exclude,
  ),
  _RecordedWork(
    actress: '未歩なな',
    code: 'RBB-337',
    title: '芸能人級のルックスを誇るSランク嬢に心ゆくまで奉仕される至高の風俗店40選 オール本番オプション付き8時間BEST',
    manufacturer: 'ROOKIE',
    label: 'ROOKIE',
    series: 'ROOKIEベスト',
    expected: _FrozenExpected.exclude,
    includeInJavBus: true,
  ),
  _RecordedWork(
    actress: '未歩なな',
    code: 'OFJE-624',
    title: '未歩なな 完全引退 ラストAV 全39作コンプリート16時間',
    manufacturer: 'エスワン ナンバーワンスタイル',
    label: 'S1 NO.1 STYLE',
    series: 'S1 GIRLS COLLECTION',
    expected: _FrozenExpected.exclude,
  ),
  _RecordedWork(
    actress: '未歩なな',
    code: 'OFJE-621',
    title: '人生全て捨ててもちちくり合いたい… 悪魔的に尊い女子●生たちと 制服着たまま禁断60セックス',
    manufacturer: 'エスワン ナンバーワンスタイル',
    label: 'S1 NO.1 STYLE',
    series: 'S1 GIRLS COLLECTION',
    expected: _FrozenExpected.exclude,
  ),
  _RecordedWork(
    actress: '未歩なな',
    code: 'OFJE-615',
    title: '「今エスワン女優とSEXしてるじゃん！」美人がイキよがるのを完全アナタ目線で！バーチャルSEXハメ撮り49本番',
    manufacturer: 'エスワン ナンバーワンスタイル',
    label: 'S1 NO.1 STYLE',
    series: 'S1 GIRLS COLLECTION',
    expected: _FrozenExpected.exclude,
  ),
  _RecordedWork(
    actress: '未歩なな',
    code: 'SONE-998',
    title:
        '未歩なな引退発表ラストハードSEX 玩具やったら巨チン挿れて媚薬やったら大乱交やって 継ぎ足し継ぎ足し継ぎ足しオーバーキル100イカセ',
    manufacturer: 'エスワン ナンバーワンスタイル',
    label: 'S1 NO.1 STYLE',
    expected: _FrozenExpected.keep,
  ),
  _RecordedWork(
    actress: '未歩なな',
    code: 'OFJE-594',
    title: 'S1オールスター23名大集合 全7タイトル全部入り 完全ベスト版16時間 未公開の40人越え乱交初収録',
    manufacturer: 'エスワン ナンバーワンスタイル',
    label: 'S1 NO.1 STYLE',
    series: 'S1 GIRLS COLLECTION',
    expected: _FrozenExpected.exclude,
  ),
  _RecordedWork(
    actress: '未歩なな',
    code: 'SIVR-446',
    title:
        '【VR】遅すぎたアオハル「君が好き。最後に思い出、作りたい」卒業直前で学園のアイドル 未歩ななちゃんに告られて…在学中にしか叶えられないこっそり校内シチュ×制服セックス',
    manufacturer: 'エスワン ナンバーワンスタイル',
    label: 'S1 VR',
    series: 'S1 VR',
    expected: _FrozenExpected.keep,
    includeInJavBus: true,
  ),
  _RecordedWork(
    actress: '未歩なな',
    code: 'SIVR-380',
    title:
        '【VR】AV業界を席巻する超豪華S1専属女優25名とSEXできる！超スーパー最高画質 8KVRベスト第2弾！没入感MAX厳選SEX26コーナー1000分…',
    manufacturer: 'エスワン ナンバーワンスタイル',
    label: 'S1 VR',
    series: 'S1 VR',
    expected: _FrozenExpected.failed,
    includeInJavBus: true,
    detailsAvailable: false,
  ),

  // 永野いち夏: the existing frozen provenance corpus is carried into the
  // same parser/service path here, including the corrected real MIZD-498.
  _RecordedWork(
    actress: '永野いち夏',
    code: 'MIZD-498',
    title: '美少女J系のマンマン食い込み無自覚パンチラ眺めて爆射したい',
    manufacturer: 'ムーディーズ',
    label: 'MOODYZ Best',
    description: 'パンチラ、それは性の目覚めの出発点。美少女J系の無自覚なパンチラを眺めてオナニーしたいアナタに送るベスト。',
    tags: ['パンチラ', 'パンスト・タイツ', '女子校生', '制服', '独占配信'],
    expected: _FrozenExpected.exclude,
  ),
  _RecordedWork(
    actress: '永野いち夏',
    code: 'CJOB-213',
    title: '見つめて乳首をカリカリ！さすさす！こねこね！主観乳首責めで何度も射精ブッコぬかれる僕。',
    manufacturer: 'CJOB',
    label: 'CJOB',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    includeInJavBus: true,
  ),
  _RecordedWork(
    actress: '永野いち夏',
    code: 'CJOB-196',
    title: 'スキルもテクニックも超SSS級！もう射精してるってばぁ！ド痴女の天才SEX 100本番BEST！8時間！',
    manufacturer: 'CJOB',
    label: 'CJOB',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
  ),
  _RecordedWork(
    actress: '永野いち夏',
    code: 'UMSO-600',
    title: 'セーラー美少女BEST11人',
    manufacturer: 'ケイ・エム・プロデュース',
    label: 'UMANAMI',
    expected: _FrozenExpected.exclude,
  ),
  _RecordedWork(
    actress: '永野いち夏',
    code: 'UMSO-643',
    title: '折れそうなくらい華奢なスレンダーボディ美少女12人',
    manufacturer: 'ケイ・エム・プロデュース',
    label: 'UMANAMI',
    tags: ['ベスト・総集編', 'スレンダー', '貧乳・微乳'],
    expected: _FrozenExpected.exclude,
    includeInJavBus: true,
  ),
  _RecordedWork(
    actress: '永野いち夏',
    code: 'HNVR-153',
    title: '【VR】正常位中出し 美少女たちの目を見つめながらイク！女の子64人と連続でリアル生SEXを堪能する323分',
    manufacturer: 'HNVR',
    label: 'HNVR',
    tags: ['ベスト・総集編', '数珠つなぎ', '単体作品', '3P・4P'],
    includedWorks: ['HNVR-007', 'HNVR-010', 'HNVR-019', 'HNVR-022'],
    expected: _FrozenExpected.exclude,
  ),
  _RecordedWork(
    actress: '永野いち夏',
    code: 'SETH-012',
    title: '【VR】制服限定！J系SEXノーカットBEST30 43時間',
    manufacturer: 'SETH',
    label: 'SETH',
    tags: ['ベスト・総集編', 'ハイクオリティVR', 'VR専用', '単体作品'],
    includedWorks: ['3DSVR-838', '3DSVR-849', '3DSVR-923', '3DSVR-387'],
    expected: _FrozenExpected.exclude,
  ),
  _RecordedWork(
    actress: '永野いち夏',
    code: 'FOOMVD-026',
    title:
        'オチ〇ンポ好き痴女が集結！神テク舐めまわし＆バキューム密着限界吸引フェラでザーメン搾取 700分 120発射精・100口内発射・73回ごっくん収録！',
    manufacturer: 'FOOMVD',
    label: 'FOOMVD',
    tags: ['ベスト・総集編'],
    includedWorks: ['FOCS-256'],
    expected: _FrozenExpected.exclude,
  ),
  _RecordedWork(
    actress: '永野いち夏',
    code: 'TOMNVD-019',
    title:
        '子宮めがけて執拗に突き上げで「止めちゃダメぇ！」と涙目で痙攣し限界超え連続昇天！騎乗位・抱え上げ・立ちバックで汗だく絶叫60名濃厚ハードピストンBEST！520分',
    manufacturer: 'TOMNVD',
    label: 'TOMNVD',
    expected: _FrozenExpected.exclude,
  ),
  _RecordedWork(
    actress: '永野いち夏',
    code: 'HYAS-142',
    title: '可愛い女の子がチュパチュパおしゃぶりフェラ100人8時間2枚組',
    manufacturer: 'HYAS',
    label: 'HYAS',
    expected: _FrozenExpected.review,
    includeInJavBus: true,
  ),
  _RecordedWork(
    actress: '永野いち夏',
    code: 'CJOB-216',
    title: '永野いち夏 BEST FRIEND',
    manufacturer: 'CJOB',
    label: 'CJOB',
    expected: _FrozenExpected.keep,
  ),
  _RecordedWork(
    actress: '永野いち夏',
    code: 'UMSO-650',
    title: '美少女BEST50本番',
    manufacturer: 'ケイ・エム・プロデュース',
    label: 'UMANAMI',
    expected: _FrozenExpected.exclude,
  ),

  // Real maker matrix counterexamples outside the known derived-only code
  // families. Each is a real AvBase code/title pair observed by maker search.
  _RecordedWork(
    actress: '松永あかり',
    code: 'START-635',
    title: '99発のホンモノ精子大量ぶっかけ 松永あかり SODSTAR完全転職 SOD退社記念作品',
    manufacturer: 'SODクリエイト',
    label: 'SODSTAR',
    expected: _FrozenExpected.keep,
  ),
  _RecordedWork(
    actress: '三佳詩',
    code: 'ABF-386',
    title: '性欲に支配された倒錯カップルの同棲中出し性交録。 三佳詩',
    manufacturer: 'プレステージ',
    label: 'ABSOLUTELY FANTASIA',
    series: '同棲中出し性交録。',
    expected: _FrozenExpected.keep,
  ),
  _RecordedWork(
    actress: '神田真弥',
    code: 'IPZZ-988',
    title: '男に選ばれるオンナは内面で惚れさせるー。 告白された人数50人超えの天性のモテ美容部員 AVデビュー 神田真弥',
    manufacturer: 'アイデアポケット',
    label: 'ティッシュ',
    expected: _FrozenExpected.keep,
  ),
  _RecordedWork(
    actress: '希島あいり',
    code: 'IDBD-953',
    title: 'IDEAPOCKET 2024 超豪華29タイトル収録 至極の15時間BEST FINAL WEAPON',
    manufacturer: 'アイデアポケット',
    label: 'アイデアポケットBEST',
    series: 'アイデアポケットBEST',
    expected: _FrozenExpected.exclude,
    requiredMaker: 'IdeaPocket',
  ),
  _RecordedWork(
    actress: '鳳みゆ',
    code: 'ADN-806',
    title: '大嫌いな義父に潮を吹かされまくった若妻 鳳みゆ',
    manufacturer: 'アタッカーズ',
    label: '大人のドラマ',
    expected: _FrozenExpected.keep,
  ),
  _RecordedWork(
    actress: '秋月夕',
    code: 'ROE-561',
    title: 'MONROE専属 現役モデル人妻まさかの中出し解禁！！ 美しい友人の母、接吻と受精に溺れた日々―。 秋月夕',
    manufacturer: 'マドンナ',
    label: 'MONROE',
    series: '美しい友人の母、接吻と受精に溺れた日々―。',
    expected: _FrozenExpected.keep,
  ),
  _RecordedWork(
    actress: '翔すずめ',
    code: 'DASD-868',
    title: '抱き心地100点満点 どんな無茶にも神対応 Gcup女子DEBUT 翔すずめ',
    manufacturer: 'ダスッ！',
    label: 'ダスッ！',
    series: 'DAS DEBUT',
    expected: _FrozenExpected.keep,
  ),
  _RecordedWork(
    actress: '成海美雨',
    code: 'KIBD-355',
    title: 'むちむち肉感デカ尻ギャルにガン突きバックピストン94連発！ 成海美雨',
    manufacturer: 'kira☆kira',
    label: 'kira☆kira',
    expected: _FrozenExpected.keep,
  ),
  _RecordedWork(
    actress: '成海美雨',
    code: 'KIBD-353',
    title:
        'ギャルセフレとタダハメベストッ！！＃個撮＃マッチングアプリ＃ハメ撮り＃素人＃裏アカ＃顔射＃スレンダー＃ノリ良い＃高身長＃低身長＃美脚＃潮吹き＃イチャラブ＃ほろ酔い＃セフレ＃原宿系',
    manufacturer: 'kira☆kira',
    label: 'kira☆kira',
    series: 'kira☆kira BEST',
    expected: _FrozenExpected.exclude,
  ),
  _RecordedWork(
    actress: '逢沢みゆ',
    code: 'RKI-757',
    title: 'どうせ死ぬから、好きにして 人生最後の思い出に欲望のままに快楽を貪り生ハメ中出し＆首絞めSEXでイキまくる 逢沢みゆ',
    manufacturer: 'ROOKIE',
    label: 'ROOKIE',
    expected: _FrozenExpected.keep,
  ),
  _RecordedWork(
    actress: '篠田ゆう',
    code: 'UMSO-657',
    title: '回覧板を届けに行ったら、裸族の隣の奥さんがオマ〇コとアナルをじっくり見せてくれた件VOL.03',
    manufacturer: 'ケイ・エム・プロデュース',
    label: 'UMANAMI',
    expected: _FrozenExpected.keep,
  ),
  _RecordedWork(
    actress: '安堂はるの',
    code: 'VRKM-1909',
    title: '【VR】ドMなスプリットタンのランカー嬢に出禁覚悟の10発中出し 安堂はるの',
    manufacturer: 'ケイ・エム・プロデュース',
    label: 'KMPVR',
    series: 'ピンサロ再現',
    expected: _FrozenExpected.keep,
  ),
];

/// Compact frozen rows for the maker matrix.  These are source-record rows:
/// where a source snapshot exposed the code, maker, label, and cast but not a
/// reusable title string, the title intentionally remains code-plus-cast and
/// carries no derived marker.  That makes the no-signal KEEP boundary
/// testable without inventing reuse evidence.
_RecordedWork _matrixRecord({
  required String actress,
  required String code,
  required String title,
  required String manufacturer,
  required String label,
  required _FrozenExpected expected,
  required String requiredMaker,
  String? series,
  List<String> tags = const <String>[],
  String? description,
  List<String> includedWorks = const <String>[],
  bool includeInJavBus = false,
  String releaseDate = '2026-08-27',
}) => _RecordedWork(
  actress: actress,
  code: code,
  title: title,
  manufacturer: manufacturer,
  label: label,
  series: series,
  releaseDate: releaseDate,
  tags: tags,
  description: description,
  includedWorks: includedWorks,
  expected: expected,
  includeInJavBus: includeInJavBus,
  requiredMaker: requiredMaker,
);

int _rawForRecords(Iterable<_RecordedWork> records) {
  final rows = records.toList(growable: false);
  return rows.length + rows.where((record) => record.includeInJavBus).length;
}

final _majorMakerStressRecords = <_RecordedWork>[
  // S1: 河北彩花.  SNOS originals and OFJE S1 GIRLS COLLECTION rows exercise
  // the same maker with both ordinary and concrete collection evidence.
  _matrixRecord(
    actress: '河北彩花',
    code: 'SNOS-377',
    title: '「今日はアブノーマルなエッチがしたい…」そう甘えるCA彼女を無茶苦茶にしたらドMに目覚めた 河北彩花',
    manufacturer: 'エスワン ナンバーワンスタイル',
    label: 'S1 NO.1 STYLE',
    expected: _FrozenExpected.keep,
    requiredMaker: 'S1',
    includeInJavBus: true,
  ),
  _matrixRecord(
    actress: '河北彩花',
    code: 'SNOS-371',
    title: '河北彩花の素の優しさと思いやり特化 関東巡行 筆おろしドキュメント',
    manufacturer: 'エスワン ナンバーワンスタイル',
    label: 'S1 NO.1 STYLE',
    expected: _FrozenExpected.keep,
    requiredMaker: 'S1',
  ),
  _matrixRecord(
    actress: '河北彩花',
    code: 'OFJE-655',
    title: 'エッロいオンナとエッロいベロキス 脳もチ●ポもトロける唾液みどろ110接吻性交 12時間スペシャル',
    manufacturer: 'エスワン ナンバーワンスタイル',
    label: 'S1 NO.1 STYLE',
    series: 'S1 GIRLS COLLECTION',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    requiredMaker: 'S1',
  ),
  _matrixRecord(
    actress: '河北彩花',
    code: 'OFJE-654',
    title: 'S1史上最高の女体が汚いおっさんにねっちょり舐め犯される 熟練ベロ技に堕ちたS1美女たち40本番7時間',
    manufacturer: 'エスワン ナンバーワンスタイル',
    label: 'S1 NO.1 STYLE',
    series: 'S1 GIRLS COLLECTION',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    requiredMaker: 'S1',
  ),
  _matrixRecord(
    actress: '河北彩花',
    code: 'SNOS-320',
    title: '出張先、二人きりの温泉旅館 僕を慕う圧倒的美人な後輩に迫られたら寝取られても仕方がない 河北彩花',
    manufacturer: 'エスワン ナンバーワンスタイル',
    label: 'S1 NO.1 STYLE',
    expected: _FrozenExpected.keep,
    requiredMaker: 'S1',
  ),
  _matrixRecord(
    actress: '河北彩花',
    code: 'OFJE-648',
    title: '極上フェイス美女がこんなトコまでしゃぶってくれる！？スーパーお下品献身フェラチオ50',
    manufacturer: 'エスワン ナンバーワンスタイル',
    label: 'S1 NO.1 STYLE',
    series: 'S1 GIRLS COLLECTION',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    requiredMaker: 'S1',
  ),
  _matrixRecord(
    actress: '河北彩花',
    code: 'OFJE-647',
    title: 'この世で一番エロいモノってS1女優の汗だくボディじゃない？女体堪能SEXフルコース8時間',
    manufacturer: 'エスワン ナンバーワンスタイル',
    label: 'S1 NO.1 STYLE',
    series: 'S1 GIRLS COLLECTION',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    requiredMaker: 'S1',
    includeInJavBus: true,
  ),
  _matrixRecord(
    actress: '河北彩花',
    code: 'SNOS-275',
    title: '河北彩花の尊い美顔を心おきなく拝みたい。',
    manufacturer: 'エスワン ナンバーワンスタイル',
    label: 'S1 NO.1 STYLE',
    expected: _FrozenExpected.keep,
    requiredMaker: 'S1',
  ),
  _matrixRecord(
    actress: '河北彩花',
    code: 'OFJE-640',
    title: '29人のS1絶世美女たちがアナタのチ●ポを溺愛して尽くしてくれる好き好きオナニーサポート80連発',
    manufacturer: 'エスワン ナンバーワンスタイル',
    label: 'S1 NO.1 STYLE',
    series: 'S1 GIRLS COLLECTION',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    requiredMaker: 'S1',
  ),
  _matrixRecord(
    actress: '河北彩花',
    code: 'OFJE-639',
    title: '業界トップ女優達がぶっ壊れる！過去最大級の大絶頂で体液じっとり女体堪能8時間',
    manufacturer: 'エスワン ナンバーワンスタイル',
    label: 'S1 NO.1 STYLE',
    series: 'S1 GIRLS COLLECTION',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    requiredMaker: 'S1',
  ),

  // SOD: みながわ千遥.  These ten SODstar/SODVR rows are ordinary source
  // records; no derived case is asserted without collection metadata.
  _matrixRecord(
    actress: 'みながわ千遥',
    code: 'STARS-149',
    title: '45日間禁欲生活のち、性欲バースト12発中出し みながわ千遥',
    manufacturer: 'SODクリエイト',
    label: 'SODSTAR',
    expected: _FrozenExpected.keep,
    requiredMaker: 'SOD',
    includeInJavBus: true,
  ),
  _matrixRecord(
    actress: 'みながわ千遥',
    code: '3DSVR-554',
    title: '【VR】尾行VR 追跡バック視点 巨乳女教師に後ろから無理やりねじ込む みながわ千遥',
    manufacturer: 'SODクリエイト',
    label: 'SODVR',
    expected: _FrozenExpected.keep,
    requiredMaker: 'SOD',
  ),
  _matrixRecord(
    actress: 'みながわ千遥',
    code: '3DSVR-546',
    title: '【VR】彼女と旅行に行ったら元カノとまさかの再会 嫉妬した元カノに求められて復縁SEX',
    manufacturer: 'SODクリエイト',
    label: 'SODVR',
    expected: _FrozenExpected.keep,
    requiredMaker: 'SOD',
  ),
  _matrixRecord(
    actress: 'みながわ千遥',
    code: 'STARS-135',
    title: 'みながわ千遥ちゃん タオル一枚男湯入ってみませんか？ HARD',
    manufacturer: 'SODクリエイト',
    label: 'SODSTAR',
    expected: _FrozenExpected.keep,
    requiredMaker: 'SOD',
  ),
  _matrixRecord(
    actress: 'みながわ千遥',
    code: '3DSVR-530',
    title: '【VR】みながわ千遥と密着して何度も射精する主観VR',
    manufacturer: 'SODクリエイト',
    label: 'SODVR',
    expected: _FrozenExpected.keep,
    requiredMaker: 'SOD',
    includeInJavBus: true,
  ),
  _matrixRecord(
    actress: 'みながわ千遥',
    code: 'STARS-120',
    title: 'SODstar 11 SEX BUBBLE PARTY 2019 プールで感度アゲアゲイキまくり編',
    manufacturer: 'SODクリエイト',
    label: 'SODSTAR',
    expected: _FrozenExpected.keep,
    requiredMaker: 'SOD',
  ),
  _matrixRecord(
    actress: 'みながわ千遥',
    code: 'STARS-119',
    title: '童貞のフリした絶倫兄弟が姉の友達にハードピストン 連続中出し みながわ千遥',
    manufacturer: 'SODクリエイト',
    label: 'SODSTAR',
    expected: _FrozenExpected.keep,
    requiredMaker: 'SOD',
  ),
  _matrixRecord(
    actress: 'みながわ千遥',
    code: 'STARS-102',
    title: 'ナマ派 初中出し解禁 みながわ千遥',
    manufacturer: 'SODクリエイト',
    label: 'SODSTAR',
    expected: _FrozenExpected.keep,
    requiredMaker: 'SOD',
  ),
  _matrixRecord(
    actress: 'みながわ千遥',
    code: 'STARS-092',
    title: '狙われた巨乳看護師 執拗なまでに舐めまわされた白い肌 みながわ千遥',
    manufacturer: 'SODクリエイト',
    label: 'SODSTAR',
    expected: _FrozenExpected.keep,
    requiredMaker: 'SOD',
  ),
  _matrixRecord(
    actress: 'みながわ千遥',
    code: 'STARS-082',
    title: '旅行中にフラれたボクを優しく癒してくれる愛しの温泉仲居さん 完全主観接客',
    manufacturer: 'SODクリエイト',
    label: 'SODSTAR',
    expected: _FrozenExpected.keep,
    requiredMaker: 'SOD',
  ),

  // MOODYZ: 美園和花.  The MNGS code family is deliberately represented as
  // normal no-signal works, not as a family-level exclusion rule.
  _matrixRecord(
    actress: '美園和花',
    code: 'MNGS-001',
    title: '本人vsAI ハーレム痴女近未来AI共演潮潮スプラッシュ!! 美園和花＆AI美園和花',
    manufacturer: 'ムーディーズ',
    label: 'MOODYZ ニュージーニアス',
    expected: _FrozenExpected.keep,
    requiredMaker: 'MOODYZ',
  ),
  _matrixRecord(
    actress: '美園和花',
    code: 'MNGS-006',
    title: 'MNGS-006 美園和花',
    manufacturer: 'ムーディーズ',
    label: 'MOODYZ ニュージーニアス',
    expected: _FrozenExpected.keep,
    requiredMaker: 'MOODYZ',
  ),
  _matrixRecord(
    actress: '美園和花',
    code: 'MNGS-022',
    title: 'MNGS-022 美園和花',
    manufacturer: 'ムーディーズ',
    label: 'MOODYZ ニュージーニアス',
    expected: _FrozenExpected.keep,
    requiredMaker: 'MOODYZ',
    includeInJavBus: true,
  ),
  _matrixRecord(
    actress: '美園和花',
    code: 'MNGS-027',
    title: 'MNGS-027 美園和花',
    manufacturer: 'ムーディーズ',
    label: 'MOODYZ ニュージーニアス',
    expected: _FrozenExpected.keep,
    requiredMaker: 'MOODYZ',
  ),
  _matrixRecord(
    actress: '美園和花',
    code: 'MNGS-031',
    title: 'MNGS-031 美園和花',
    manufacturer: 'ムーディーズ',
    label: 'MOODYZ ニュージーニアス',
    expected: _FrozenExpected.keep,
    requiredMaker: 'MOODYZ',
  ),
  _matrixRecord(
    actress: '美園和花',
    code: 'MNGS-042',
    title: 'MNGS-042 美園和花',
    manufacturer: 'ムーディーズ',
    label: 'MOODYZ ニュージーニアス',
    expected: _FrozenExpected.keep,
    requiredMaker: 'MOODYZ',
  ),
  _matrixRecord(
    actress: '美園和花',
    code: 'MNGS-053',
    title: 'MNGS-053 美園和花',
    manufacturer: 'ムーディーズ',
    label: 'MOODYZ ニュージーニアス',
    expected: _FrozenExpected.keep,
    requiredMaker: 'MOODYZ',
  ),
  _matrixRecord(
    actress: '美園和花',
    code: 'MNGS-060',
    title: 'MNGS-060 美園和花',
    manufacturer: 'ムーディーズ',
    label: 'MOODYZ ニュージーニアス',
    expected: _FrozenExpected.keep,
    requiredMaker: 'MOODYZ',
  ),
  _matrixRecord(
    actress: '美園和花',
    code: 'MNGS-064',
    title: 'MNGS-064 美園和花',
    manufacturer: 'ムーディーズ',
    label: 'MOODYZ ニュージーニアス',
    expected: _FrozenExpected.keep,
    requiredMaker: 'MOODYZ',
  ),
  _matrixRecord(
    actress: '美園和花',
    code: 'MNGS-076',
    title: 'ドコでも即ハメおねだり中出しOKレンタル彼女 美園和花',
    manufacturer: 'ムーディーズ',
    label: 'MOODYZ ニュージーニアス',
    expected: _FrozenExpected.keep,
    requiredMaker: 'MOODYZ',
  ),

  // Prestige: 川村真矢.  These are the ten exact ABP/CHN/YRH/GGG source
  // rows from the actress filmography.
  _matrixRecord(
    actress: '川村真矢',
    code: 'CHN-008',
    title: '新・素人娘、お貸しします。VOL.04',
    manufacturer: 'プレステージ',
    label: 'PRESTIGE',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Prestige',
  ),
  _matrixRecord(
    actress: '川村真矢',
    code: 'ABP-030',
    title: 'プレステージ夏祭り2013 南国成分由来 川村まや汁120％',
    manufacturer: 'プレステージ',
    label: 'PRESTIGE',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Prestige',
    includeInJavBus: true,
  ),
  _matrixRecord(
    actress: '川村真矢',
    code: 'ABP-043',
    title: '隣の綺麗なお姉さん',
    manufacturer: 'プレステージ',
    label: 'PRESTIGE',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Prestige',
  ),
  _matrixRecord(
    actress: '川村真矢',
    code: 'ABP-056',
    title: '一泊二日、美少女完全予約制。第二章 川村まやの場合',
    manufacturer: 'プレステージ',
    label: 'PRESTIGE',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Prestige',
  ),
  _matrixRecord(
    actress: '川村真矢',
    code: 'ABP-070',
    title: '川村まやがご奉仕しちゃう 超最新やみつきエステ',
    manufacturer: 'プレステージ',
    label: 'PRESTIGE',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Prestige',
  ),
  _matrixRecord(
    actress: '川村真矢',
    code: 'YRH-024',
    title: '青春スクールメモリーズ 第2期',
    manufacturer: 'プレステージ',
    label: 'PRESTIGE',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Prestige',
  ),
  _matrixRecord(
    actress: '川村真矢',
    code: 'GGG-001',
    title: 'プレステージ専属女優 in 風俗アイランド!!',
    manufacturer: 'プレステージ',
    label: 'PRESTIGE',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Prestige',
  ),
  _matrixRecord(
    actress: '川村真矢',
    code: 'ABP-086',
    title: '川村まや、満足度満点ソープDX',
    manufacturer: 'プレステージ',
    label: 'PRESTIGE',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Prestige',
  ),
  _matrixRecord(
    actress: '川村真矢',
    code: 'ABP-096',
    title: '濃密な接吻と欲情ベロキス性交 03',
    manufacturer: 'プレステージ',
    label: 'PRESTIGE',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Prestige',
    includeInJavBus: true,
  ),
  _matrixRecord(
    actress: '川村真矢',
    code: 'ABP-113',
    title: '彼女の妹は、誘惑ヤリたがり娘。',
    manufacturer: 'プレステージ',
    label: 'PRESTIGE',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Prestige',
  ),

  // kawaii*: 櫻由羅.  Eleven ordinary KAWD works and one explicit personal
  // best provide a same-maker derived discriminator.
  _matrixRecord(
    actress: '櫻由羅',
    code: 'KAWD-509',
    title: '新人!kawaii*専属デビュ→奇跡の逸材☆次世代アイドル誕生',
    manufacturer: 'kawaii',
    label: 'kawaii*',
    expected: _FrozenExpected.keep,
    requiredMaker: 'kawaii*',
  ),
  _matrixRecord(
    actress: '櫻由羅',
    code: 'KAWD-515',
    title: 'ゆらちゃんの感度びんびん初体験',
    manufacturer: 'kawaii',
    label: 'kawaii*',
    expected: _FrozenExpected.keep,
    requiredMaker: 'kawaii*',
  ),
  _matrixRecord(
    actress: '櫻由羅',
    code: 'KAWD-522',
    title: 'kawaii* High School 学校でセックchu',
    manufacturer: 'kawaii',
    label: 'kawaii*',
    expected: _FrozenExpected.keep,
    requiredMaker: 'kawaii*',
  ),
  _matrixRecord(
    actress: '櫻由羅',
    code: 'KAWD-530',
    title: '完全主観でイク!2人っきりのゆらり温泉旅',
    manufacturer: 'kawaii',
    label: 'kawaii*',
    expected: _FrozenExpected.keep,
    requiredMaker: 'kawaii*',
    includeInJavBus: true,
  ),
  _matrixRecord(
    actress: '櫻由羅',
    code: 'KAWD-541',
    title: '顔射解禁☆いきなり一撃大量顔射',
    manufacturer: 'kawaii',
    label: 'kawaii*',
    expected: _FrozenExpected.keep,
    requiredMaker: 'kawaii*',
  ),
  _matrixRecord(
    actress: '櫻由羅',
    code: 'KAWD-552',
    title: 'さくらゆらの全力オナニーサポーター',
    manufacturer: 'kawaii',
    label: 'kawaii*',
    expected: _FrozenExpected.keep,
    requiredMaker: 'kawaii*',
  ),
  _matrixRecord(
    actress: '櫻由羅',
    code: 'KAWD-563',
    title: 'デカチン大乱交',
    manufacturer: 'kawaii',
    label: 'kawaii*',
    expected: _FrozenExpected.keep,
    requiredMaker: 'kawaii*',
  ),
  _matrixRecord(
    actress: '櫻由羅',
    code: 'KAWD-573',
    title: 'モテナイ男子限定!さくらゆらの逆ナンパ調査隊',
    manufacturer: 'kawaii',
    label: 'kawaii*',
    expected: _FrozenExpected.keep,
    requiredMaker: 'kawaii*',
  ),
  _matrixRecord(
    actress: '櫻由羅',
    code: 'KAWD-583',
    title: 'さくらゆらのコスプレ風俗4本番4時間スペシャル',
    manufacturer: 'kawaii',
    label: 'kawaii*',
    expected: _FrozenExpected.keep,
    requiredMaker: 'kawaii*',
  ),
  _matrixRecord(
    actress: '櫻由羅',
    code: 'KAWD-592',
    title: 'ゆらの膣中で一緒にイって',
    manufacturer: 'kawaii',
    label: 'kawaii*',
    expected: _FrozenExpected.keep,
    requiredMaker: 'kawaii*',
  ),
  _matrixRecord(
    actress: '櫻由羅',
    code: 'KAWD-605',
    title: 'ほろ苦い大人の初体験',
    manufacturer: 'kawaii',
    label: 'kawaii*',
    expected: _FrozenExpected.keep,
    requiredMaker: 'kawaii*',
  ),
  _matrixRecord(
    actress: '櫻由羅',
    code: 'KWBD-167',
    title: 'さくらゆらデビュー1周年記念☆ゆらぽだょ8時間special',
    manufacturer: 'kawaii',
    label: 'kawaii*',
    series: 'kawaii* 個人ベスト',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    requiredMaker: 'kawaii*',
  ),

  // IdeaPocket: 希島あいり.  These IPZ titles are individual works; the
  // already-frozen IDBD-953 supplies the concrete collection counterexample.
  _matrixRecord(
    actress: '希島あいり',
    code: 'IPZ-158',
    title: 'FIRST IMPRESSION 71 希島あいり',
    manufacturer: 'アイデアポケット',
    label: 'ティッシュ',
    series: 'FIRST IMPRESSION',
    expected: _FrozenExpected.keep,
    requiredMaker: 'IdeaPocket',
  ),
  _matrixRecord(
    actress: '希島あいり',
    code: 'IPZ-185',
    title: '初顔射解禁 希島あいり',
    manufacturer: 'アイデアポケット',
    label: 'ティッシュ',
    expected: _FrozenExpected.keep,
    requiredMaker: 'IdeaPocket',
    includeInJavBus: true,
  ),
  _matrixRecord(
    actress: '希島あいり',
    code: 'IPZ-205',
    title: '3P解禁 希島あいり',
    manufacturer: 'アイデアポケット',
    label: 'ティッシュ',
    expected: _FrozenExpected.keep,
    requiredMaker: 'IdeaPocket',
  ),
  _matrixRecord(
    actress: '希島あいり',
    code: 'IPZ-229',
    title: '制服美少女4本番 希島あいり',
    manufacturer: 'アイデアポケット',
    label: 'ティッシュ',
    expected: _FrozenExpected.keep,
    requiredMaker: 'IdeaPocket',
  ),
  _matrixRecord(
    actress: '希島あいり',
    code: 'IPZ-249',
    title: '濃厚な接吻とSEX 希島あいり',
    manufacturer: 'アイデアポケット',
    label: 'ティッシュ',
    expected: _FrozenExpected.keep,
    requiredMaker: 'IdeaPocket',
  ),
  _matrixRecord(
    actress: '希島あいり',
    code: 'IPZ-283',
    title: '僕とあいりの甘～い性活',
    manufacturer: 'アイデアポケット',
    label: 'ティッシュ',
    expected: _FrozenExpected.keep,
    requiredMaker: 'IdeaPocket',
  ),
  _matrixRecord(
    actress: '希島あいり',
    code: 'IPZ-299',
    title: 'あいり先生の誘惑授業',
    manufacturer: 'アイデアポケット',
    label: 'ティッシュ',
    expected: _FrozenExpected.keep,
    requiredMaker: 'IdeaPocket',
  ),
  _matrixRecord(
    actress: '希島あいり',
    code: 'IPZ-322',
    title: 'スプラッシュSEX あいりの大量潮噴き',
    manufacturer: 'アイデアポケット',
    label: 'ティッシュ',
    expected: _FrozenExpected.keep,
    requiredMaker: 'IdeaPocket',
  ),
  _matrixRecord(
    actress: '希島あいり',
    code: 'IPZ-356',
    title: '彼女の姉貴とイケナイ関係',
    manufacturer: 'アイデアポケット',
    label: 'ティッシュ',
    expected: _FrozenExpected.keep,
    requiredMaker: 'IdeaPocket',
  ),
  _matrixRecord(
    actress: '希島あいり',
    code: 'IPZ-376',
    title: '希島あいりとヴァーチャルデート',
    manufacturer: 'アイデアポケット',
    label: 'ティッシュ',
    expected: _FrozenExpected.keep,
    requiredMaker: 'IdeaPocket',
  ),
  _matrixRecord(
    actress: '希島あいり',
    code: 'IPZ-397',
    title: 'おもらし清純ナースの失禁看護',
    manufacturer: 'アイデアポケット',
    label: 'ティッシュ',
    expected: _FrozenExpected.keep,
    requiredMaker: 'IdeaPocket',
  ),

  // Attackers: 石原莉奈.  Ordinary SHKD/ADN/RBD titles plus a real
  // ATTACKERS BEST row keep the family boundary at narrower evidence.
  _matrixRecord(
    actress: '石原莉奈',
    code: 'SHKD-541',
    title: 'SHKD-541 石原莉奈',
    manufacturer: 'アタッカーズ',
    label: 'ATTACKERS',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Attackers',
  ),
  _matrixRecord(
    actress: '石原莉奈',
    code: 'SHKD-546',
    title: 'SHKD-546 石原莉奈',
    manufacturer: 'アタッカーズ',
    label: 'ATTACKERS',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Attackers',
    includeInJavBus: true,
  ),
  _matrixRecord(
    actress: '石原莉奈',
    code: 'RBD-598',
    title: 'RBD-598 石原莉奈',
    manufacturer: 'アタッカーズ',
    label: 'ATTACKERS',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Attackers',
  ),
  _matrixRecord(
    actress: '石原莉奈',
    code: 'ADN-046',
    title: 'ADN-046 石原莉奈',
    manufacturer: 'アタッカーズ',
    label: 'ATTACKERS',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Attackers',
  ),
  _matrixRecord(
    actress: '石原莉奈',
    code: 'SHKD-595',
    title: 'SHKD-595 石原莉奈',
    manufacturer: 'アタッカーズ',
    label: 'ATTACKERS',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Attackers',
  ),
  _matrixRecord(
    actress: '石原莉奈',
    code: 'RBD-667',
    title: 'RBD-667 石原莉奈',
    manufacturer: 'アタッカーズ',
    label: 'ATTACKERS',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Attackers',
  ),
  _matrixRecord(
    actress: '石原莉奈',
    code: 'ADN-057',
    title: 'ADN-057 石原莉奈',
    manufacturer: 'アタッカーズ',
    label: 'ATTACKERS',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Attackers',
    includeInJavBus: true,
  ),
  _matrixRecord(
    actress: '石原莉奈',
    code: 'RBD-682',
    title: 'RBD-682 石原莉奈',
    manufacturer: 'アタッカーズ',
    label: 'ATTACKERS',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Attackers',
  ),
  _matrixRecord(
    actress: '石原莉奈',
    code: 'RBD-690',
    title: 'RBD-690 石原莉奈',
    manufacturer: 'アタッカーズ',
    label: 'ATTACKERS',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Attackers',
  ),
  _matrixRecord(
    actress: '石原莉奈',
    code: 'RBD-697',
    title: 'RBD-697 石原莉奈',
    manufacturer: 'アタッカーズ',
    label: 'ATTACKERS',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Attackers',
  ),
  _matrixRecord(
    actress: '石原莉奈',
    code: 'ATKD-254',
    title: 'ATTACKERS PRESENTS THE BEST OF 石原莉奈',
    manufacturer: 'アタッカーズ',
    label: 'ATTACKERS',
    series: 'ATTACKERS BEST',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    requiredMaker: 'Attackers',
  ),

  // Madonna: 水戸かな.  The source filmography gives ten ordinary JUQ
  // records and one explicit single-actress best.
  _matrixRecord(
    actress: '水戸かな',
    code: 'JUQ-192',
    title: 'ヌードモデルNTR カメラマンと羞恥に溺れた妻の衝撃的浮気映像 水戸かな',
    manufacturer: 'マドンナ',
    label: 'Madonna',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Madonna',
  ),
  _matrixRecord(
    actress: '水戸かな',
    code: 'JUQ-210',
    title: 'いつでも、どこでも、何度でも 僕の新婚生活が崩壊するまで隣人に中出し搾精されて 水戸かな',
    manufacturer: 'マドンナ',
    label: 'Madonna',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Madonna',
    includeInJavBus: true,
  ),
  _matrixRecord(
    actress: '水戸かな',
    code: 'JUQ-214',
    title: '義姉にロングスカートの中でこっそり密着搾精されて 水戸かな',
    manufacturer: 'マドンナ',
    label: 'Madonna',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Madonna',
  ),
  _matrixRecord(
    actress: '水戸かな',
    code: 'JUQ-234',
    title: '息子の友人ともう5年間セフレ関係を続けています 水戸かな',
    manufacturer: 'マドンナ',
    label: 'Madonna',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Madonna',
  ),
  _matrixRecord(
    actress: '水戸かな',
    code: 'JUQ-256',
    title: '合鍵をもらった人妻が男子学生が卒業するまで中出しされた一人暮らし部屋 水戸かな',
    manufacturer: 'マドンナ',
    label: 'Madonna',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Madonna',
  ),
  _matrixRecord(
    actress: '水戸かな',
    code: 'JUQ-290',
    title: '専属・水戸かなが妖艶に舞い踊る ストリップ劇場で舞う人妻',
    manufacturer: 'マドンナ',
    label: 'Madonna',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Madonna',
  ),
  _matrixRecord(
    actress: '水戸かな',
    code: 'JUQ-388',
    title: '30歳になっても童貞の義弟に同情して一生の願いを受け挿れたら 水戸かな',
    manufacturer: 'マドンナ',
    label: 'Madonna',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Madonna',
  ),
  _matrixRecord(
    actress: '水戸かな',
    code: 'JUQ-417',
    title: '夫の身代わりになった高慢女上司、恥辱のクレーム対応 水戸かな',
    manufacturer: 'マドンナ',
    label: 'Madonna',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Madonna',
  ),
  _matrixRecord(
    actress: '水戸かな',
    code: 'JUQ-453',
    title: '出張ペアエステNTR 薄布1枚隔てた向こう側、淫猥な施術で絶頂させられた妻 水戸かな',
    manufacturer: 'マドンナ',
    label: 'Madonna',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Madonna',
    includeInJavBus: true,
  ),
  _matrixRecord(
    actress: '水戸かな',
    code: 'JUQ-489',
    title: '想いと唇が重なる濃密接吻ソープ 水戸かな',
    manufacturer: 'マドンナ',
    label: 'Madonna',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Madonna',
  ),
  _matrixRecord(
    actress: '水戸かな',
    code: 'JUMS-031',
    title: 'こんにちは水戸です。私の総集編見ていかないですか？4枚組16時間 Madonna専属BEST 水戸かな',
    manufacturer: 'マドンナ',
    label: 'Madonna',
    series: 'Madonna 単体ベスト',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    requiredMaker: 'Madonna',
  ),

  // OPPAI: JULIA.  PPPD individual titles are KEEP; PPBD-148 is the
  // concrete single-actress best counterexample.
  _matrixRecord(
    actress: 'JULIA',
    code: 'PPPD-616',
    title: 'おっぱい密着ホールドSEX 柔乳Jカップに包まれて快感射精',
    manufacturer: 'OPPAI',
    label: 'OPPAI',
    expected: _FrozenExpected.keep,
    requiredMaker: 'OPPAI',
  ),
  _matrixRecord(
    actress: 'JULIA',
    code: 'PPPD-626',
    title: '男を勃起させる卑猥なBODY デカ乳敏感デリヘル嬢',
    manufacturer: 'OPPAI',
    label: 'OPPAI',
    expected: _FrozenExpected.keep,
    requiredMaker: 'OPPAI',
    includeInJavBus: true,
  ),
  _matrixRecord(
    actress: 'JULIA',
    code: 'PPPD-635',
    title: '強制的におっぱいを与えたがる授乳願望痴女の顔面圧迫プレス',
    manufacturer: 'OPPAI',
    label: 'OPPAI',
    expected: _FrozenExpected.keep,
    requiredMaker: 'OPPAI',
  ),
  _matrixRecord(
    actress: 'JULIA',
    code: 'PPPD-642',
    title: 'うまのりパイズリ挿乳ピストン 最後はもの凄いマウント挟射',
    manufacturer: 'OPPAI',
    label: 'OPPAI',
    expected: _FrozenExpected.keep,
    requiredMaker: 'OPPAI',
  ),
  _matrixRecord(
    actress: 'JULIA',
    code: 'PPPD-643',
    title: 'Jcup高級ランジェリー販売員の誘惑セールス術',
    manufacturer: 'OPPAI',
    label: 'OPPAI',
    expected: _FrozenExpected.keep,
    requiredMaker: 'OPPAI',
  ),
  _matrixRecord(
    actress: 'JULIA',
    code: 'PPPD-661',
    title: '東京の下町エリアで人気のおっパブ店にJULIAが潜入して1日店長',
    manufacturer: 'OPPAI',
    label: 'OPPAI',
    expected: _FrozenExpected.keep,
    requiredMaker: 'OPPAI',
  ),
  _matrixRecord(
    actress: 'JULIA',
    code: 'PPPD-670',
    title: '巨乳兄嫁のおっぱい暴力で何度も射精させられた僕',
    manufacturer: 'OPPAI',
    label: 'OPPAI',
    expected: _FrozenExpected.keep,
    requiredMaker: 'OPPAI',
  ),
  _matrixRecord(
    actress: 'JULIA',
    code: 'PPPD-687',
    title: '僕のセフレは中出し好きの巨乳な姉貴',
    manufacturer: 'OPPAI',
    label: 'OPPAI',
    expected: _FrozenExpected.keep,
    requiredMaker: 'OPPAI',
  ),
  _matrixRecord(
    actress: 'JULIA',
    code: 'PPPD-695',
    title: '友達の教育ママを乳奴隷',
    manufacturer: 'OPPAI',
    label: 'OPPAI',
    expected: _FrozenExpected.keep,
    requiredMaker: 'OPPAI',
  ),
  _matrixRecord(
    actress: 'JULIA',
    code: 'PPPD-702',
    title: '巨乳デリヘルを呼んだらやってきたのは俺をいつも叱りつけていた美人教師J',
    manufacturer: 'OPPAI',
    label: 'OPPAI',
    expected: _FrozenExpected.keep,
    requiredMaker: 'OPPAI',
  ),
  _matrixRecord(
    actress: 'JULIA',
    code: 'PPBD-148',
    title: 'JULIA 20タイトル 8時間BEST',
    manufacturer: 'OPPAI',
    label: 'OPPAI',
    series: 'OPPAI 単体ベスト',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    requiredMaker: 'OPPAI',
  ),

  // DAS!: 小澤マリア.  DASD is used for original works and DAZD rows are
  // explicit compilations in the source record set.
  _matrixRecord(
    actress: '小澤マリア',
    code: 'DASD-021',
    title: '小便ぶっかけ 美人ハーフ英語女教師小澤マリア20連発中出し！',
    manufacturer: 'ダスッ！',
    label: 'ダスッ！',
    expected: _FrozenExpected.keep,
    requiredMaker: 'DAS!',
  ),
  _matrixRecord(
    actress: '小澤マリア',
    code: 'DASD-026',
    title: '100連発中出し！',
    manufacturer: 'ダスッ！',
    label: 'ダスッ！',
    expected: _FrozenExpected.keep,
    requiredMaker: 'DAS!',
  ),
  _matrixRecord(
    actress: '小澤マリア',
    code: 'DASD-031',
    title: 'アナル奴隷浣腸噴射！小澤マリア',
    manufacturer: 'ダスッ！',
    label: 'ダスッ！',
    expected: _FrozenExpected.keep,
    requiredMaker: 'DAS!',
  ),
  _matrixRecord(
    actress: '小澤マリア',
    code: 'DAZD-001',
    title: '100発連続中出し！',
    manufacturer: 'ダスッ！',
    label: 'ダスッ！',
    series: 'DAS compilation',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    requiredMaker: 'DAS!',
  ),
  _matrixRecord(
    actress: '小澤マリア',
    code: 'DAZD-002',
    title: 'ダスッ！総集編4時間',
    manufacturer: 'ダスッ！',
    label: 'ダスッ！',
    series: 'DAS compilation',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    requiredMaker: 'DAS!',
  ),
  _matrixRecord(
    actress: '小澤マリア',
    code: 'DAZD-003',
    title: '100連発潮吹き！',
    manufacturer: 'ダスッ！',
    label: 'ダスッ！',
    series: 'DAS compilation',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    requiredMaker: 'DAS!',
  ),
  _matrixRecord(
    actress: '小澤マリア',
    code: 'DAZD-009',
    title: 'イカセ地獄！悶絶アクメ4時間',
    manufacturer: 'ダスッ！',
    label: 'ダスッ！',
    series: 'DAS compilation',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    requiredMaker: 'DAS!',
  ),
  _matrixRecord(
    actress: '小澤マリア',
    code: 'DAZD-010',
    title: 'Best Collection Golden Showers 4 Hours',
    manufacturer: 'ダスッ！',
    label: 'ダスッ！',
    series: 'DAS compilation',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    requiredMaker: 'DAS!',
    includeInJavBus: true,
  ),
  _matrixRecord(
    actress: '小澤マリア',
    code: 'DAZD-011',
    title: '誰のかわからぬ子種で孕め！連続中出し8時間',
    manufacturer: 'ダスッ！',
    label: 'ダスッ！',
    series: 'DAS compilation',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    requiredMaker: 'DAS!',
  ),
  _matrixRecord(
    actress: '小澤マリア',
    code: 'DAZD-012',
    title: '勤務中に犯せ！働く女達を強姦4時間',
    manufacturer: 'ダスッ！',
    label: 'ダスッ！',
    series: 'DAS compilation',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    requiredMaker: 'DAS!',
  ),
  _matrixRecord(
    actress: '小澤マリア',
    code: 'DAZD-013',
    title: '2008年上半期！総集編8時間',
    manufacturer: 'ダスッ！',
    label: 'ダスッ！',
    series: 'DAS compilation',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    requiredMaker: 'DAS!',
  ),
  _matrixRecord(
    actress: '小澤マリア',
    code: 'DAZD-014',
    title: '顔面受精した女達！臭いザーメンで溺れてしまえ！',
    manufacturer: 'ダスッ！',
    label: 'ダスッ！',
    series: 'DAS compilation',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    requiredMaker: 'DAS!',
  ),

  // WANZ: JULIA.  These ten WANZ individual works are a second same-actor
  // source slice and intentionally have no collection metadata.
  _matrixRecord(
    actress: 'JULIA',
    code: 'WANZ-744',
    title: 'JULIAの凄テクを我慢できれば生★中出しSEX!',
    manufacturer: 'ワンズファクトリー',
    label: 'WANZ',
    expected: _FrozenExpected.keep,
    requiredMaker: 'WANZ',
  ),
  _matrixRecord(
    actress: 'JULIA',
    code: 'WANZ-768',
    title: 'じゅりあの体内に242発の媚薬濃縮精液注入',
    manufacturer: 'ワンズファクトリー',
    label: 'WANZ',
    expected: _FrozenExpected.keep,
    requiredMaker: 'WANZ',
    includeInJavBus: true,
  ),
  _matrixRecord(
    actress: 'JULIA',
    code: 'WANZ-782',
    title: 'オナニー出来ない僕を義姉がねっとり腰振り優しい騎乗位',
    manufacturer: 'ワンズファクトリー',
    label: 'WANZ',
    expected: _FrozenExpected.keep,
    requiredMaker: 'WANZ',
  ),
  _matrixRecord(
    actress: 'JULIA',
    code: 'WANZ-792',
    title: '妊娠OK!! 色気むんむんで迫ってくる爆乳ヤリマン不倫人妻',
    manufacturer: 'ワンズファクトリー',
    label: 'WANZ',
    expected: _FrozenExpected.keep,
    requiredMaker: 'WANZ',
  ),
  _matrixRecord(
    actress: 'JULIA',
    code: 'WANZ-796',
    title: 'もうイッてるってばぁ！状態で何度も中出し！',
    manufacturer: 'ワンズファクトリー',
    label: 'WANZ',
    expected: _FrozenExpected.keep,
    requiredMaker: 'WANZ',
  ),
  _matrixRecord(
    actress: 'JULIA',
    code: 'WANZ-808',
    title: '男汁ぶっかけ痴漢バス 絶倫チ●ポ集団に狙われザーメン凌辱中出し輪姦',
    manufacturer: 'ワンズファクトリー',
    label: 'WANZ',
    expected: _FrozenExpected.keep,
    requiredMaker: 'WANZ',
  ),
  _matrixRecord(
    actress: 'JULIA',
    code: 'WANZ-823',
    title: 'ムカツク女教師をぶっかけ乳奴隷にしてやった',
    manufacturer: 'ワンズファクトリー',
    label: 'WANZ',
    expected: _FrozenExpected.keep,
    requiredMaker: 'WANZ',
  ),
  _matrixRecord(
    actress: 'JULIA',
    code: 'WANZ-826',
    title: '絶頂体位開発 一番キモチ良い体位で中出し性交 Jcup Special',
    manufacturer: 'ワンズファクトリー',
    label: 'WANZ',
    expected: _FrozenExpected.keep,
    requiredMaker: 'WANZ',
  ),
  _matrixRecord(
    actress: 'JULIA',
    code: 'WANZ-838',
    title: 'ご無沙汰ママ。ねっちょりい～っぱい中出しさせてあげる',
    manufacturer: 'ワンズファクトリー',
    label: 'WANZ',
    expected: _FrozenExpected.keep,
    requiredMaker: 'WANZ',
  ),
  _matrixRecord(
    actress: 'JULIA',
    code: 'WANZ-847',
    title: 'いきなりノーパンノーブラ 神エロ露出女がこっそりチ●ポを痴女ってくる奇跡体験',
    manufacturer: 'ワンズファクトリー',
    label: 'WANZ',
    expected: _FrozenExpected.keep,
    requiredMaker: 'WANZ',
  ),

  // kira☆kira: 川村真矢.  The available source slice contains five
  // cross-series BLACK/KISD rows; no derived case is invented here.
  _matrixRecord(
    actress: '川村真矢',
    code: 'BLK-159',
    title: 'kira☆kira BLACK GAL DEBUT 日焼け黒ギャル専属デビュー',
    manufacturer: 'kira☆kira',
    label: 'kira☆kira',
    series: 'BLACK GAL',
    expected: _FrozenExpected.keep,
    requiredMaker: 'kira☆kira',
  ),
  _matrixRecord(
    actress: '川村真矢',
    code: 'BLK-167',
    title: 'kira☆kiraサマーフェスタ2014 BLACK GAL BEACH RESORT',
    manufacturer: 'kira☆kira',
    label: 'kira☆kira',
    series: 'BLACK GAL',
    expected: _FrozenExpected.keep,
    requiredMaker: 'kira☆kira',
    includeInJavBus: true,
  ),
  _matrixRecord(
    actress: '川村真矢',
    code: 'KISD-082',
    title: 'kira★kira SPECIAL 公衆便所逆レイプ サンドイッチ逆3P強制中出し',
    manufacturer: 'kira☆kira',
    label: 'kira☆kira',
    series: 'kira☆kira SPECIAL',
    expected: _FrozenExpected.keep,
    requiredMaker: 'kira☆kira',
  ),
  _matrixRecord(
    actress: '川村真矢',
    code: 'KISD-083',
    title: 'kira★kira8周年×美6周年スペシャルコラボ企画 白衣の大量ナマ中出しギャルナース研修生',
    manufacturer: 'kira☆kira',
    label: 'kira☆kira',
    series: 'kira☆kira SPECIAL',
    expected: _FrozenExpected.keep,
    requiredMaker: 'kira☆kira',
  ),
  _matrixRecord(
    actress: '川村真矢',
    code: 'BLK-216',
    title: 'kira★kira BLACK GALS ヤリマンGAL姉妹と24時間ラブラブ同棲性活',
    manufacturer: 'kira☆kira',
    label: 'kira☆kira',
    series: 'BLACK GALS',
    expected: _FrozenExpected.keep,
    requiredMaker: 'kira☆kira',
  ),

  // ROOKIE: 長谷川リホ.  The source slice exposes these nine RBB works;
  // it is the complete RBB subset in that frozen actress snapshot.  RBB is
  // a verified derived-only ROOKIE family, so the complete slice is expected
  // to exclude; no normal ROOKIE row is fabricated from a different actress.
  _matrixRecord(
    actress: '長谷川リホ',
    code: 'RBB-073',
    title: 'RBB-073 長谷川リホ',
    manufacturer: 'ROOKIE',
    label: 'ROOKIE',
    expected: _FrozenExpected.exclude,
    requiredMaker: 'ROOKIE',
  ),
  _matrixRecord(
    actress: '長谷川リホ',
    code: 'RBB-098',
    title: 'RBB-098 長谷川リホ',
    manufacturer: 'ROOKIE',
    label: 'ROOKIE',
    expected: _FrozenExpected.exclude,
    requiredMaker: 'ROOKIE',
    includeInJavBus: true,
  ),
  _matrixRecord(
    actress: '長谷川リホ',
    code: 'RBB-101',
    title: 'RBB-101 長谷川リホ',
    manufacturer: 'ROOKIE',
    label: 'ROOKIE',
    expected: _FrozenExpected.exclude,
    requiredMaker: 'ROOKIE',
  ),
  _matrixRecord(
    actress: '長谷川リホ',
    code: 'RBB-106',
    title: 'RBB-106 長谷川リホ',
    manufacturer: 'ROOKIE',
    label: 'ROOKIE',
    expected: _FrozenExpected.exclude,
    requiredMaker: 'ROOKIE',
  ),
  _matrixRecord(
    actress: '長谷川リホ',
    code: 'RBB-113',
    title: 'RBB-113 長谷川リホ',
    manufacturer: 'ROOKIE',
    label: 'ROOKIE',
    expected: _FrozenExpected.exclude,
    requiredMaker: 'ROOKIE',
  ),
  _matrixRecord(
    actress: '長谷川リホ',
    code: 'RBB-117',
    title: 'RBB-117 長谷川リホ',
    manufacturer: 'ROOKIE',
    label: 'ROOKIE',
    expected: _FrozenExpected.exclude,
    requiredMaker: 'ROOKIE',
  ),
  _matrixRecord(
    actress: '長谷川リホ',
    code: 'RBB-120',
    title: 'RBB-120 長谷川リホ',
    manufacturer: 'ROOKIE',
    label: 'ROOKIE',
    expected: _FrozenExpected.exclude,
    requiredMaker: 'ROOKIE',
  ),
  _matrixRecord(
    actress: '長谷川リホ',
    code: 'RBB-126',
    title: 'RBB-126 長谷川リホ',
    manufacturer: 'ROOKIE',
    label: 'ROOKIE',
    expected: _FrozenExpected.exclude,
    requiredMaker: 'ROOKIE',
  ),
  _matrixRecord(
    actress: '長谷川リホ',
    code: 'RBB-129',
    title: 'RBB-129 長谷川リホ',
    manufacturer: 'ROOKIE',
    label: 'ROOKIE',
    expected: _FrozenExpected.exclude,
    requiredMaker: 'ROOKIE',
  ),

  // KMP: 本真ゆり.  The source snapshot has ten KMP manufacturer rows; no
  // reuse signal is attached merely because the maker is KMP.
  _matrixRecord(
    actress: '本真ゆり',
    code: 'VRKM-1777',
    title: 'VRKM-1777 本真ゆり',
    manufacturer: 'ケイ・エム・プロデュース',
    label: 'KMP',
    expected: _FrozenExpected.keep,
    requiredMaker: 'KMP',
  ),
  _matrixRecord(
    actress: '本真ゆり',
    code: 'VRKM-1776',
    title: 'VRKM-1776 本真ゆり',
    manufacturer: 'ケイ・エム・プロデュース',
    label: 'KMP',
    expected: _FrozenExpected.keep,
    requiredMaker: 'KMP',
    includeInJavBus: true,
  ),
  _matrixRecord(
    actress: '本真ゆり',
    code: 'HYAS-148',
    title: 'HYAS-148 本真ゆり',
    manufacturer: 'ケイ・エム・プロデュース',
    label: 'KMP',
    expected: _FrozenExpected.keep,
    requiredMaker: 'KMP',
  ),
  _matrixRecord(
    actress: '本真ゆり',
    code: 'UMSO-636',
    title: 'UMSO-636 本真ゆり',
    manufacturer: 'ケイ・エム・プロデュース',
    label: 'KMP',
    expected: _FrozenExpected.keep,
    requiredMaker: 'KMP',
  ),
  _matrixRecord(
    actress: '本真ゆり',
    code: 'HYAS-147',
    title: 'HYAS-147 本真ゆり',
    manufacturer: 'ケイ・エム・プロデュース',
    label: 'KMP',
    expected: _FrozenExpected.keep,
    requiredMaker: 'KMP',
  ),
  _matrixRecord(
    actress: '本真ゆり',
    code: 'VRKM-1736',
    title: 'VRKM-1736 本真ゆり',
    manufacturer: 'ケイ・エム・プロデュース',
    label: 'KMP',
    expected: _FrozenExpected.keep,
    requiredMaker: 'KMP',
  ),
  _matrixRecord(
    actress: '本真ゆり',
    code: 'UMSO-625',
    title: 'UMSO-625 本真ゆり',
    manufacturer: 'ケイ・エム・プロデュース',
    label: 'KMP',
    expected: _FrozenExpected.keep,
    requiredMaker: 'KMP',
  ),
  _matrixRecord(
    actress: '本真ゆり',
    code: 'VRKM-1709',
    title: 'VRKM-1709 本真ゆり',
    manufacturer: 'ケイ・エム・プロデュース',
    label: 'KMP',
    expected: _FrozenExpected.keep,
    requiredMaker: 'KMP',
  ),
  _matrixRecord(
    actress: '本真ゆり',
    code: 'UMSO-618',
    title: 'UMSO-618 本真ゆり',
    manufacturer: 'ケイ・エム・プロデュース',
    label: 'KMP',
    expected: _FrozenExpected.keep,
    requiredMaker: 'KMP',
    includeInJavBus: true,
  ),
  _matrixRecord(
    actress: '本真ゆり',
    code: 'VRKM-1687',
    title: 'VRKM-1687 本真ゆり',
    manufacturer: 'ケイ・エム・プロデュース',
    label: 'KMP',
    expected: _FrozenExpected.keep,
    requiredMaker: 'KMP',
  ),
];

final _largeActressStressRecords = <_RecordedWork>[
  // 新井リマ expansion: current source rows cover additional LEO, million,
  // KMPVR, WANZ, DAS, and collection families without changing accepted
  // classifier semantics.
  _matrixRecord(
    actress: '新井リマ',
    code: 'UMD-1028',
    title: '男なら一度はやられてみたいっ！！厳選のドスケベ痴女プレイ集ベスト6！！（お姉さん編） Part13',
    manufacturer: 'LEO',
    label: 'LEO',
    series: '男なら一度はやられてみたいっ！！',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    requiredMaker: 'LEO',
    includeInJavBus: true,
  ),
  _matrixRecord(
    actress: '新井リマ',
    code: 'MKMP-758',
    title: '百発絶頂エクスタシー激射精BEST',
    manufacturer: 'million',
    label: 'million',
    series: 'million BEST',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    requiredMaker: 'million',
  ),
  _matrixRecord(
    actress: '新井リマ',
    code: 'VRKM-1877',
    title: '【VR】美しさ・可愛さ・エロさが爆発した奇跡の女優 大感謝BEST10タイトル300分',
    manufacturer: 'ケイ・エム・プロデュース',
    label: 'KMPVR',
    series: 'VR BEST',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    requiredMaker: 'KMPVR',
  ),
  _matrixRecord(
    actress: '新井リマ',
    code: 'RROY-022',
    title: '腰振り極上！抱き心地バツグン！乳揺れ最高！スレンダー巨乳との中出しセックス9名4時間BEST',
    manufacturer: 'ロイヤル',
    label: 'HHHグループ',
    series: 'ロイヤル BEST',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    requiredMaker: 'ロイヤル',
  ),
  _matrixRecord(
    actress: '新井リマ',
    code: 'CJOD-530',
    title: '帰省先のド田舎で、幼馴染のリマと5年振りの再会。美顔見つめベロキス中出しで搾り取られ続けたボク。',
    manufacturer: '痴女ヘブン',
    label: '痴女ヘブン',
    expected: _FrozenExpected.keep,
    requiredMaker: '痴女ヘブン',
  ),
  _matrixRecord(
    actress: '新井リマ',
    code: 'MKMP-750',
    title: 'KMPの激アツ作品をこれでもかと詰め込みました！全レーベル網羅！！×人気作品厳選！！お中元スペシャル！！',
    manufacturer: 'million',
    label: 'million',
    series: 'KMP作品厳選スペシャル',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    requiredMaker: 'million',
  ),
  _matrixRecord(
    actress: '新井リマ',
    code: 'VRKM-1860',
    title: '【VR】深夜の誰もいないオフィスで仕事もSEXも残業中 オフィスSEX BEST',
    manufacturer: 'ケイ・エム・プロデュース',
    label: 'KMPVR',
    series: 'VR BEST',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    requiredMaker: 'KMPVR',
    includeInJavBus: true,
  ),
  _matrixRecord(
    actress: '新井リマ',
    code: 'VRKM-1853',
    title: '【VR】唾液まみれで溺れイキ！！ダラぢゅるよだれ接吻性交300分BEST',
    manufacturer: 'ケイ・エム・プロデュース',
    label: 'KMPVR',
    series: 'VR BEST',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    requiredMaker: 'KMPVR',
  ),
  _matrixRecord(
    actress: '新井リマ',
    code: 'VRKM-1862',
    title: '【VR】これが令和のブチアゲSEXパーティー！！NO SEX NO LIFE 1000分OVER BEST',
    manufacturer: 'ケイ・エム・プロデュース',
    label: 'KMPVR',
    series: 'VR BEST',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    requiredMaker: 'KMPVR',
  ),
  _matrixRecord(
    actress: '新井リマ',
    code: 'CJOD-526',
    title: '愛羅武ち○こ 一途に吸い付く義理人情 超ギャルフェラ本気BEST',
    manufacturer: '痴女ヘブン',
    label: '痴女ヘブン',
    series: '痴女ヘブン BEST',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    requiredMaker: '痴女ヘブン',
  ),
  _matrixRecord(
    actress: '新井リマ',
    code: 'PXVR-471',
    title: '【VR】癒しの極上アングル！絶世エステティシャン21人の最高エステ体験BEST',
    manufacturer: 'P-BOX VR',
    label: 'P-BOX VR',
    series: 'P-BOX VR BEST',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    requiredMaker: 'P-BOX VR',
  ),
  _matrixRecord(
    actress: '新井リマ',
    code: 'VRKM-1837',
    title: '【VR】淫らに！貪欲に！下品に！理性が吹き飛ぶ危険すぎ快感！NTR BEST5時間',
    manufacturer: 'ケイ・エム・プロデュース',
    label: 'KMPVR',
    series: 'VR BEST',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    requiredMaker: 'KMPVR',
  ),
  _matrixRecord(
    actress: '新井リマ',
    code: 'BBSS-104',
    title: 'No玩具！やっぱりレズは直接触れ合うのが一番幸せ！THE NATURAL LESBIAN BEST4時間',
    manufacturer: 'ビビアン',
    label: 'ビビアン',
    series: 'ビビアン BEST',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    requiredMaker: 'ビビアン',
  ),
  _matrixRecord(
    actress: '新井リマ',
    code: 'VRKM-1832',
    title: '【VR】イキ声が耳に響いて脳が絶頂する危険なBEST300分',
    manufacturer: 'ケイ・エム・プロデュース',
    label: 'KMPVR',
    series: 'VR BEST',
    tags: ['ベスト・総集編'],
    expected: _FrozenExpected.exclude,
    requiredMaker: 'KMPVR',
  ),
  _matrixRecord(
    actress: '新井リマ',
    code: 'WAAA-662',
    title:
        '妻にノーブラ乳首浮きワンピース誘惑させる隣人の変態旦那の罠にハマりハニトラ寝取らせ中出し不倫に狂わされたボク孕ませ20発NTR 新井リマ',
    manufacturer: 'ワンズファクトリー',
    label: 'WANZ',
    expected: _FrozenExpected.keep,
    requiredMaker: 'WANZ',
  ),
  _matrixRecord(
    actress: '新井リマ',
    code: 'SAVR-0909',
    title: '【VR】クラスの顔面ビジュアル最高峰の制服美少女とヤリまくり絶頂FESTIVAL 顔面優勝3PSEX編',
    manufacturer: 'ケイ・エム・プロデュース',
    label: 'KMPVR-彩',
    series: 'KMPVR-彩',
    expected: _FrozenExpected.keep,
    requiredMaker: 'KMPVR',
  ),
  _matrixRecord(
    actress: '新井リマ',
    code: 'SAVR-0906',
    title: '【VR】KMPVR-彩 新井リマ SAVR-0906',
    manufacturer: 'ケイ・エム・プロデュース',
    label: 'KMPVR-彩',
    series: 'KMPVR-彩',
    expected: _FrozenExpected.keep,
    requiredMaker: 'KMPVR',
  ),

  // 沢北みなみ expansion: the real source-record slice exercises E-BODY,
  // OPPAI, K-Tribe, Prestige, Peters, 本中, and multiple identity aliases.
  _matrixRecord(
    actress: '沢北みなみ',
    code: 'MKCK-407',
    title: 'MKCK-407 E-BODY HD 2025 沢北みなみ',
    manufacturer: 'E-BODY',
    label: 'E-BODY',
    expected: _FrozenExpected.keep,
    requiredMaker: 'E-BODY',
    includeInJavBus: true,
  ),
  _matrixRecord(
    actress: '沢北みなみ',
    code: 'MKCK-398',
    title: 'MKCK-398 E-BODY HD 2025 沢北みなみ',
    manufacturer: 'E-BODY',
    label: 'E-BODY',
    expected: _FrozenExpected.keep,
    requiredMaker: 'E-BODY',
  ),
  _matrixRecord(
    actress: '沢北みなみ',
    code: 'MKCK-373',
    title: 'MKCK-373 E-BODY HD 2024 沢北みなみ',
    manufacturer: 'E-BODY',
    label: 'E-BODY',
    expected: _FrozenExpected.keep,
    requiredMaker: 'E-BODY',
  ),
  _matrixRecord(
    actress: '沢北みなみ',
    code: 'NMGT-014',
    title: 'NMGT-014 NEWMEGATORA HD 2024 沢北みなみ',
    manufacturer: 'NEWMEGATORA',
    label: 'NEWMEGATORA',
    expected: _FrozenExpected.keep,
    requiredMaker: 'NEWMEGATORA',
  ),
  _matrixRecord(
    actress: '沢北みなみ',
    code: 'KTST-003',
    title: 'KTST-003 K-Tribe HD 2024 沢北みなみ',
    manufacturer: 'K-Tribe',
    label: 'K-Tribe',
    expected: _FrozenExpected.keep,
    requiredMaker: 'K-Tribe',
  ),
  _matrixRecord(
    actress: '沢北みなみ',
    code: 'OVG-209',
    title: 'OVG-209 GLORY QUEST HD 2024 沢北みなみ',
    manufacturer: 'グローリークエスト',
    label: 'GLORY QUEST',
    expected: _FrozenExpected.keep,
    requiredMaker: 'GLORY QUEST',
  ),
  _matrixRecord(
    actress: '沢北みなみ',
    code: 'MAAN-850',
    title: 'MAAN-850 街角シロウトナンパ HD 2024 沢北みなみ',
    manufacturer: '街角シロウトナンパ',
    label: '街角シロウトナンパ',
    expected: _FrozenExpected.keep,
    requiredMaker: '街角シロウトナンパ',
    includeInJavBus: true,
  ),
  _matrixRecord(
    actress: '沢北みなみ',
    code: 'APAO-038',
    title: 'APAO-038 Aurora Project ANNEX HD 2023 沢北みなみ',
    manufacturer: 'オーロラプロジェクト・アネックス',
    label: 'Aurora Project ANNEX',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Aurora Project ANNEX',
  ),
  _matrixRecord(
    actress: '沢北みなみ',
    code: 'PTS-506',
    title: 'PTS-506 Peters HD 2023 沢北みなみ',
    manufacturer: 'Peters',
    label: 'Peters',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Peters',
  ),
  _matrixRecord(
    actress: '沢北みなみ',
    code: 'IENFH294-05',
    title: 'IENFH294-05 Ienergy HD 2023 沢北みなみ',
    manufacturer: 'Ienergy',
    label: 'Ienergy',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Ienergy',
  ),
  _matrixRecord(
    actress: '沢北みなみ',
    code: 'CLT-069',
    title: 'CLT-069 Peters HD 2023 沢北みなみ',
    manufacturer: 'Peters',
    label: 'Peters',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Peters',
  ),
  _matrixRecord(
    actress: '沢北みなみ',
    code: 'PPPE-127',
    title: 'PPPE-127 OPPAI HD 2023 沢北みなみ',
    manufacturer: 'OPPAI',
    label: 'OPPAI',
    expected: _FrozenExpected.keep,
    requiredMaker: 'OPPAI',
  ),
  _matrixRecord(
    actress: '沢北みなみ',
    code: 'HMN-384',
    title: 'HMN-384 本中 HD 2023 沢北みなみ',
    manufacturer: '本中',
    label: '本中',
    expected: _FrozenExpected.keep,
    requiredMaker: '本中',
  ),
  _matrixRecord(
    actress: '沢北みなみ',
    code: 'MIAA-849',
    title: 'MIAA-849 MOODYZ HD 2023 沢北みなみ',
    manufacturer: 'ムーディーズ',
    label: 'MOODYZ',
    expected: _FrozenExpected.keep,
    requiredMaker: 'MOODYZ',
  ),
  _matrixRecord(
    actress: '沢北みなみ',
    code: 'KTRA-521',
    title: 'KTRA-521 K-Tribe HD 2023 沢北みなみ',
    manufacturer: 'K-Tribe',
    label: 'K-Tribe',
    expected: _FrozenExpected.keep,
    requiredMaker: 'K-Tribe',
  ),
  _matrixRecord(
    actress: '沢北みなみ',
    code: 'KTRA-517',
    title: 'KTRA-517 K-Tribe HD 2023 沢北みなみ',
    manufacturer: 'K-Tribe',
    label: 'K-Tribe',
    expected: _FrozenExpected.keep,
    requiredMaker: 'K-Tribe',
  ),
  _matrixRecord(
    actress: '沢北みなみ',
    code: 'FCP-154',
    title: 'FCP-154 Prestige HD 2023 沢北みなみ',
    manufacturer: 'プレステージ',
    label: 'Prestige',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Prestige',
  ),
  _matrixRecord(
    actress: '沢北みなみ',
    code: 'ZOZO-148',
    title: 'ZOZO-148 Sadistic Village Now! HD 2023 沢北みなみ',
    manufacturer: 'サディスティックヴィレッジ',
    label: 'Sadistic Village Now!',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Sadistic Village',
  ),
  _matrixRecord(
    actress: '沢北みなみ',
    code: 'MASM-011',
    title: 'MASM-011 かぐや姫Pt HD 2023 沢北みなみ',
    manufacturer: 'かぐや姫Pt/妄想族',
    label: 'かぐや姫Pt',
    expected: _FrozenExpected.keep,
    requiredMaker: 'かぐや姫Pt',
  ),
  _matrixRecord(
    actress: '沢北みなみ',
    code: 'APAK-248',
    title: 'APAK-248 Aurora Project ANNEX HD 2023 沢北みなみ',
    manufacturer: 'オーロラプロジェクト・アネックス',
    label: 'Aurora Project ANNEX',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Aurora Project ANNEX',
  ),
  _matrixRecord(
    actress: '沢北みなみ',
    code: 'SVSHA-005',
    title: 'SVSHA-005 Sadistic Village HD 2023 沢北みなみ',
    manufacturer: 'サディスティックヴィレッジ',
    label: 'Sadistic Village',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Sadistic Village',
  ),
  _matrixRecord(
    actress: '沢北みなみ',
    code: 'LULU-193',
    title: 'LULU-193 LUNATICS HD 2023 沢北みなみ',
    manufacturer: 'LUNATICS',
    label: 'LUNATICS',
    expected: _FrozenExpected.keep,
    requiredMaker: 'LUNATICS',
  ),
  _matrixRecord(
    actress: '沢北みなみ',
    code: 'FCP-144',
    title: 'FCP-144 Prestige HD 2023 沢北みなみ',
    manufacturer: 'プレステージ',
    label: 'Prestige',
    expected: _FrozenExpected.keep,
    requiredMaker: 'Prestige',
  ),
];

Future<_FrozenStressReport> _runFrozenCase(
  String actressName,
  List<_RecordedWork> records,
) async {
  final directory = await Directory.systemTemp.createTemp(
    'avaca_frozen_production_stress_',
  );
  final database = AppDatabase.forTesting(
    baseDir: directory.path,
    databaseFactory: databaseFactoryFfi,
  );
  await database.init();
  await database.addActress(name: actressName);
  final actressId =
      (await (await database.database).query('actresses')).single['id'] as int;

  final transport = _FrozenAvBaseTransport(records);
  final avBase = AvBaseScrapeSource(
    AvBaseClient(transport: transport, parser: AvBaseHtmlParser()),
  );
  final javBus = _FrozenJavBusSource(records);
  final service = WorksScrapeService(
    db: database,
    sources: {ScrapeSourceId.javbus: javBus, ScrapeSourceId.avbase: avBase},
    workImageDownloader: WorkImageDownloader(
      transport: _NoImageTransport(),
      routeRepository: PrefixRouteRepository.inMemory(),
      evidenceRouteLearningEnabled: false,
    ),
    imageDirectory: directory.path,
    javBusDetailDelay: Duration.zero,
  );
  final observer = _FrozenObserver();
  try {
    final result = await service.scrape(
      actressId: actressId,
      actressName: actressName,
      options: const WorkScrapeOptions(
        syncDetails: false,
        fillMissingOnly: false,
      ),
      sourceSettings: const ScrapeSourceSettings(
        actressDetailsSource: ScrapeSourceId.avbase,
        worksSources: [ScrapeSourceId.javbus, ScrapeSourceId.avbase],
        aliasSource: ScrapeSourceId.avbase,
      ),
      observer: observer,
      onProgress: observer.onProgress,
    );
    final finalProgress = observer.progress.lastWhere(
      (progress) => progress.phase == WorksScrapePhase.completed,
      orElse: () => observer.progress.last,
    );
    final report = _FrozenStressReport(
      actress: actressName,
      records: records,
      outcomes: List.unmodifiable(observer.outcomes),
      result: result,
      rawDiscovered: finalProgress.rawDiscovered,
      uniqueCount: finalProgress.detailTotal,
      duplicateCount: finalProgress.duplicateCount,
    );
    report.assertTerminalInvariants();
    return report;
  } finally {
    service.close();
    await database.close();
    await directory.delete(recursive: true);
  }
}

final class _FrozenStressReport {
  const _FrozenStressReport({
    required this.actress,
    required this.records,
    required this.outcomes,
    required this.result,
    required this.rawDiscovered,
    required this.uniqueCount,
    required this.duplicateCount,
  });

  final String actress;
  final List<_RecordedWork> records;
  final List<_FrozenObservedOutcome> outcomes;
  final WorksScrapeResult result;
  final int rawDiscovered;
  final int uniqueCount;
  final int duplicateCount;

  Map<String, List<_FrozenObservedOutcome>> get _outcomesByStorageCode {
    final grouped = <String, List<_FrozenObservedOutcome>>{};
    for (final outcome in outcomes) {
      final storageCode = outcome.code.trim().toUpperCase();
      grouped
          .putIfAbsent(storageCode, () => <_FrozenObservedOutcome>[])
          .add(outcome);
    }
    return grouped;
  }

  Iterable<_FrozenObservedOutcome> get _terminalOutcomes =>
      _outcomesByStorageCode.values.map((items) => items.single);

  int get terminalKeepCount => _terminalOutcomes
      .where((outcome) => outcome.finalAction == 'keep')
      .length;

  int get terminalExcludeCount => _terminalOutcomes
      .where((outcome) => outcome.finalAction == 'exclude')
      .length;

  int get terminalReviewCount => _terminalOutcomes
      .where(
        (outcome) =>
            outcome.finalAction == 'keepReview' ||
            outcome.state == ScrapeWorkOutcomeState.review,
      )
      .length;

  int get terminalFailedCount => _terminalOutcomes
      .where(
        (outcome) =>
            outcome.finalAction == 'failed' ||
            outcome.state == ScrapeWorkOutcomeState.failed,
      )
      .length;

  void assertTerminalInvariants() {
    final recordCodes = records
        .map((record) => record.code.trim().toUpperCase())
        .toList(growable: false);
    final recordCodeSet = recordCodes.toSet();
    final outcomesByCode = _outcomesByStorageCode;
    final terminal = _terminalOutcomes.toList(growable: false);

    expect(rawDiscovered >= uniqueCount, isTrue, reason: actress);
    expect(
      rawDiscovered - uniqueCount,
      duplicateCount,
      reason: '$actress duplicate accounting',
    );
    expect(
      recordCodeSet.length,
      recordCodes.length,
      reason: '$actress duplicate canonical storage code in fixture',
    );
    expect(
      recordCodes.length,
      uniqueCount,
      reason: '$actress canonical fixture count',
    );
    expect(
      outcomesByCode.length,
      uniqueCount,
      reason: '$actress canonical outcome count',
    );
    expect(
      outcomesByCode.keys,
      containsAll(recordCodeSet),
      reason: '$actress missing canonical terminal outcome',
    );
    expect(
      outcomesByCode.values.every((items) => items.length == 1),
      isTrue,
      reason: '$actress canonical identity has multiple terminal results',
    );
    expect(
      terminal.every(
        (outcome) =>
            outcome.finalAction == 'keep' ||
            outcome.finalAction == 'exclude' ||
            outcome.finalAction == 'keepReview' ||
            outcome.finalAction == 'failed',
      ),
      isTrue,
      reason: '$actress contains a non-terminal/cancelled canonical outcome',
    );

    for (final entry in outcomesByCode.entries) {
      final actions = entry.value.map((outcome) => outcome.finalAction).toSet();
      expect(
        actions.contains('keep') && actions.contains('exclude'),
        isFalse,
        reason: '${entry.key} is both KEEP and EXCLUDE',
      );
      expect(
        actions.contains('keep') && actions.contains('keepReview'),
        isFalse,
        reason: '${entry.key} is both KEEP and REVIEW',
      );
    }

    expect(
      uniqueCount,
      terminalKeepCount +
          terminalExcludeCount +
          terminalReviewCount +
          terminalFailedCount,
      reason: '$actress terminal action invariant',
    );
  }

  String render(Map<String, _FrozenObservedOutcome> observed) {
    final rows = <String>[];
    final clusters = <String, List<String>>{};
    for (final record in records) {
      final outcome = observed[record.code];
      final reasonCode = outcome?.reasonCodes.join('|') ?? 'detailsUnavailable';
      final finalAction = outcome?.finalAction ?? 'failed';
      final clusterKey =
          'maker=${record.manufacturer}|prefix=${_reportPrefix(record.code)}|'
          'series=${record.series ?? '-'}|reasonCode=$reasonCode|'
          'finalAction=$finalAction';
      clusters.putIfAbsent(clusterKey, () => <String>[]).add(record.code);
      rows.add('${record.code}:$finalAction:$reasonCode');
    }
    final clusterRows = clusters.entries
        .map((entry) => '${entry.key}|codes=${entry.value.join(',')}')
        .join(' || ');
    return '  $actress raw=$rawDiscovered canonical=$uniqueCount '
        'duplicates=$duplicateCount KEEP=$terminalKeepCount '
        'EXCLUDE=$terminalExcludeCount REVIEW=$terminalReviewCount '
        'FAILED=$terminalFailedCount saved=${result.saved} :: clusters=$clusterRows :: '
        'codes=${rows.join(', ')}';
  }
}

final class _FrozenObservedOutcome {
  const _FrozenObservedOutcome({
    required this.code,
    required this.state,
    required this.finalAction,
    required this.reasonCodes,
  });

  final String code;
  final ScrapeWorkOutcomeState state;
  final String finalAction;
  final List<String> reasonCodes;
}

final class _FrozenObserver extends ScrapeRunObserver {
  final progress = <WorksScrapeProgress>[];
  final outcomes = <_FrozenObservedOutcome>[];

  @override
  void onProgress(WorksScrapeProgress value) {
    progress.add(value);
  }

  @override
  void onWorkOutcome({
    required String code,
    required ScrapeSourceId source,
    required ScrapeWorkOutcomeState outcome,
    Object? error,
    String? reason,
    Iterable<String> imageFailureVariants = const <String>[],
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final rawReasons = metadata['reasonCodes'];
    final reasons = rawReasons is Iterable
        ? rawReasons.map((value) => value.toString()).toList(growable: false)
        : [?reason];
    outcomes.add(
      _FrozenObservedOutcome(
        code: code,
        state: outcome,
        finalAction: metadata['finalAction']?.toString() ?? outcome.name,
        reasonCodes: reasons,
      ),
    );
  }
}

final class _FrozenAvBaseTransport implements AvBaseTransport {
  _FrozenAvBaseTransport(Iterable<_RecordedWork> records)
    : _records = {for (final record in records) record.code: record};

  final Map<String, _RecordedWork> _records;
  final requests = <Uri>[];

  @override
  Future<String> get(Uri uri) async {
    requests.add(uri);
    final segments = uri.pathSegments;
    if (segments.isNotEmpty && segments.first == 'talents') {
      final actress = segments.last;
      if (segments.length == 1) {
        return '<html><body><h1>$actress</h1></body></html>';
      }
      return _actressHtml(actress);
    }
    if (segments.isNotEmpty && segments.first == 'works') {
      final queryCode = uri.queryParameters['q']?.trim();
      if (queryCode != null && queryCode.isNotEmpty) {
        final record = _records[queryCode.toUpperCase()];
        if (record == null || !record.detailsAvailable) {
          throw StateError('frozen search detail unavailable for $queryCode');
        }
        return '<html><body><a href="/works/${record.code}">${record.code}</a></body></html>';
      }
      final code = _codeFromSlug(Uri.decodeComponent(segments.last));
      final record = _records[code];
      if (record == null || !record.detailsAvailable) {
        throw StateError('frozen detail unavailable for $code');
      }
      return _detailHtml(record);
    }
    throw StateError('unexpected frozen AvBase request: $uri');
  }

  String _actressHtml(String actress) {
    final records = _records.values
        .where((record) => record.actress == actress)
        .toList(growable: false);
    return '''
      <html><body>
        <h1>${_escapeHtml(actress)}</h1>
        ${records.map(_cardHtml).join()}
      </body></html>
    ''';
  }
}

final class _FrozenJavBusSource implements ScrapeSource {
  _FrozenJavBusSource(Iterable<_RecordedWork> records)
    : _records = records.where((record) => record.includeInJavBus).toList();

  final List<_RecordedWork> _records;

  @override
  ScrapeSourceId get id => ScrapeSourceId.javbus;

  @override
  Future<List<ScrapeActressSearchResult>> searchActresses(String name) async =>
      [
        ScrapeActressSearchResult(
          source: id,
          name: name,
          uri: Uri.parse('https://www.javbus.com/star/frozen'),
        ),
      ];

  @override
  Future<ScrapeActressPage> fetchActressPage(
    ScrapeActressSearchResult actress,
  ) async => ScrapeActressPage(
    source: id,
    details: ScrapedActressDetails(name: actress.name),
    works: _summaries(),
  );

  @override
  Future<List<ScrapeWorkSummary>> fetchActressWorks(
    ScrapeActressSearchResult actress, {
    required ScrapeActressPage firstPage,
    bool Function()? isCancelled,
    void Function(ScrapeCollectionProgress progress)? onProgress,
  }) async {
    onProgress?.call(
      ScrapeCollectionProgress(
        currentPage: 1,
        totalPages: 1,
        discovered: firstPage.works.length,
      ),
    );
    return firstPage.works;
  }

  @override
  Future<ScrapeWorkDetails> fetchWorkDetails(ScrapeWorkSummary work) async {
    final record = _records.firstWhere((item) => item.code == work.code);
    if (!record.detailsAvailable) {
      throw StateError('frozen JavBus detail unavailable for ${record.code}');
    }
    return ScrapeWorkDetails(
      source: id,
      code: record.code,
      rawCode: record.code,
      title: record.title,
      releaseDate: record.releaseDate,
      performerCount: 1,
    );
  }

  @override
  bool acceptsImageUri(Uri uri) => false;

  @override
  void close() {}

  List<ScrapeWorkSummary> _summaries() => [
    for (final record in _records)
      ScrapeWorkSummary(
        source: id,
        code: record.code,
        rawCode: record.code,
        title: record.title,
        detailUri: Uri.parse('https://www.javbus.com/${record.code}'),
        releaseDate: record.releaseDate,
      ),
  ];
}

final class _NoImageTransport implements BinaryTransport {
  @override
  Future<BinaryResponse> get(Uri uri) async =>
      const BinaryResponse(statusCode: 404, bodyBytes: []);
}

String _cardHtml(_RecordedWork record) {
  final series = record.series == null
      ? '<span>-</span>'
      : '<a href="/series/${Uri.encodeComponent(record.series!)}">${_escapeHtml(record.series!)}</a>';
  final tags = record.tags
      .map(
        (tag) =>
            '<a href="/tags/${Uri.encodeComponent(tag)}">${_escapeHtml(tag)}</a>',
      )
      .join();
  return '''
    <div class="bg-background border border-light rounded-lg overflow-hidden h-full">
      <div class="bg-muted py-2 flex flex-col gap-2">
        <div class="px-2 flex items-center gap-2 text-xs">
          <div dir="rtl"><span class="text-gray-400">${_escapeHtml(record.code)}</span></div>
          <a href="/works/date/${record.releaseDate}">${record.releaseDate}</a>
        </div>
        <div class="px-2 text-xs text-gray-500 flex">
          <a href="/makers/${Uri.encodeComponent(record.manufacturer)}">${_escapeHtml(record.manufacturer)}</a>
          <a href="/labels/${Uri.encodeComponent(record.label)}">${_escapeHtml(record.label)}</a>
          $series
        </div>
      </div>
      <div class="flex min-w-0 border-y border-light">
        <div class="grow flex flex-col border-l border-light"><div class="grow">
          <a data-slot="button" href="/works/${record.code}">${_escapeHtml(record.title)}</a>
        </div><div class="flex bg-muted pl-2">$tags</div></div>
      </div>
    </div>
  ''';
}

String _detailHtml(_RecordedWork record) {
  final fields = StringBuffer()
    ..write('<dt>発売日</dt><dd>${record.releaseDate}</dd>')
    ..write('<dt>メーカー</dt><dd>${_escapeHtml(record.manufacturer)}</dd>')
    ..write('<dt>レーベル</dt><dd>${_escapeHtml(record.label)}</dd>');
  if (record.series != null) {
    fields.write('<dt>シリーズ</dt><dd>${_escapeHtml(record.series!)}</dd>');
  }
  final tags = record.tags
      .map(
        (tag) =>
            '<a href="/tags/${Uri.encodeComponent(tag)}">${_escapeHtml(tag)}</a>',
      )
      .join();
  final included = record.includedWorks.isEmpty
      ? ''
      : '''<section><h2>収録作品</h2>${record.includedWorks.map((code) => '<a href="/works/$code">$code</a>').join()}</section>''';
  final description = record.description == null
      ? ''
      : '<section><h2>紹介文</h2><p>${_escapeHtml(record.description!)}</p></section>';
  final tagSection = record.tags.isEmpty
      ? ''
      : '<section><h2>タグ・説明文</h2>$tags</section>';
  return '''
    <html><body>
      <h1>${_escapeHtml(record.code)} ${_escapeHtml(record.title)}</h1>
      <dl>$fields</dl>
      $description
      $tagSection
      $included
    </body></html>
  ''';
}

String _codeFromSlug(String slug) {
  final colon = slug.lastIndexOf(':');
  return (colon >= 0 ? slug.substring(colon + 1) : slug).toUpperCase();
}

String _reportPrefix(String code) {
  final match = RegExp(r'^([A-Za-z0-9]+)-\d+').firstMatch(code);
  return match?.group(1)?.toUpperCase() ?? 'UNKNOWN';
}

String _escapeHtml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
