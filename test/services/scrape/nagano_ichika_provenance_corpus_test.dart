import 'package:avaca/models/scrape_exclusion_policy.dart';
import 'package:avaca/models/scrape_rules.dart';
import 'package:avaca/models/scrape_source_settings.dart';
import 'package:avaca/services/scrape/scrape_classification_context.dart';
import 'package:avaca/services/scrape/scrape_models.dart';
import 'package:avaca/services/scrape_exclusion_policy_evaluator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('classifies a real 永野いち夏 AvBase regression corpus', () {
    final evaluator = ScrapeExclusionPolicyEvaluator(
      ScrapePolicySnapshot.current(
        rules: ScrapeRules.builtin,
        exactAllows: const [],
      ),
    );
    final context = const ScrapeClassificationContext(
      targetActressName: '永野いち夏',
    );

    for (final fixture in _naganoIchikaCorpus) {
      final decision = evaluator.evaluate(
        code: fixture.code,
        details: [
          ScrapeWorkDetails(
            source: ScrapeSourceId.avbase,
            code: fixture.code,
            title: fixture.title,
            releaseDate: fixture.releaseDate,
            durationMinutes: fixture.durationMinutes,
            studio: fixture.studio,
            publisher: fixture.publisher,
            description: fixture.description,
            provenanceFacts: ScrapeWorkProvenanceFacts(
              includedWorks: fixture.includedWorks,
              tags: fixture.tags,
            ),
          ),
        ],
        classificationContext: context,
      );

      expect(
        decision.finalAction,
        fixture.expectedAction,
        reason: '${fixture.code}: ${fixture.title}',
      );
      if (fixture.expectedAction == ScrapeFinalAction.exclude) {
        expect(decision.evidence, isNotEmpty, reason: fixture.code);
      }
    }
  });
}

final class _NaganoCorpusFixture {
  const _NaganoCorpusFixture({
    required this.code,
    required this.title,
    this.releaseDate,
    required this.expectedAction,
    this.durationMinutes,
    this.studio,
    this.publisher,
    this.description,
    this.tags = const [],
    this.includedWorks = const [],
  });

  final String code;
  final String title;
  final String? releaseDate;
  final int? durationMinutes;
  final String? studio;
  final String? publisher;
  final String? description;
  final List<String> tags;
  final List<String> includedWorks;
  final ScrapeFinalAction expectedAction;
}

// Titles and metadata were captured from the live AvBase 永野いち夏 talent
// route on 2026-08-26.  The expected decisions intentionally distinguish
// explicit compilation evidence from large but ambiguous cast/runtime text.
const _naganoIchikaCorpus = <_NaganoCorpusFixture>[
  _NaganoCorpusFixture(
    code: 'MIZD-498',
    title: '美少女J系のマンマン食い込み無自覚パンチラ眺めて爆射したい',
    studio: 'ムーディーズ',
    publisher: 'MOODYZ Best',
    description:
        'パンチラ、それは性の目覚めの出発点。美少女J系の無自覚なパンチラを眺めてオナニーしたいアナタに送るベスト。スカートひらり、ぷにマン食い込むピタパンに目が釘付けになる100コーナー以上を厳選収録。',
    tags: ['パンチラ', 'パンスト・タイツ', '女子校生', '制服', '独占配信'],
    expectedAction: ScrapeFinalAction.exclude,
  ),
  _NaganoCorpusFixture(
    code: 'CJOB-213',
    title: '見つめて乳首をカリカリ！さすさす！こねこね！主観乳首責めで何度も射精ブッコぬかれる僕。',
    releaseDate: '2026-08-21',
    tags: ['ベスト・総集編'],
    expectedAction: ScrapeFinalAction.exclude,
  ),
  _NaganoCorpusFixture(
    code: 'CJOB-196',
    title: 'スキルもテクニックも超SSS級！もう射精してるってばぁ！ド痴女の天才SEX 100本番BEST！8時間！',
    releaseDate: '2026-01-23',
    durationMinutes: 481,
    tags: ['ベスト・総集編'],
    expectedAction: ScrapeFinalAction.exclude,
  ),
  _NaganoCorpusFixture(
    code: 'UMSO-600',
    title: 'セーラー美少女BEST11人',
    expectedAction: ScrapeFinalAction.exclude,
  ),
  _NaganoCorpusFixture(
    code: 'UMSO-643',
    title: '折れそうなくらい華奢なスレンダーボディ美少女12人',
    releaseDate: '2026-05-22',
    durationMinutes: 243,
    tags: ['ベスト・総集編', 'スレンダー', '貧乳・微乳'],
    expectedAction: ScrapeFinalAction.exclude,
  ),
  _NaganoCorpusFixture(
    code: 'UMSO-643',
    title: '折れそうなくらい華奢なスレンダーボディ美少女12人',
    durationMinutes: 243,
    expectedAction: ScrapeFinalAction.keep,
  ),
  _NaganoCorpusFixture(
    code: 'HNVR-153',
    title: '【VR】正常位中出し 美少女たちの目を見つめながらイク！女の子64人と連続でリアル生SEXを堪能する323分',
    releaseDate: '2026-02-25',
    durationMinutes: 323,
    tags: ['ベスト・総集編', '数珠つなぎ', '単体作品', '3P・4P'],
    includedWorks: ['HNVR-007', 'HNVR-010', 'HNVR-019', 'HNVR-022'],
    expectedAction: ScrapeFinalAction.exclude,
  ),
  _NaganoCorpusFixture(
    code: 'SETH-012',
    title: '【VR】制服限定！J系SEXノーカットBEST30 43時間',
    releaseDate: '2024-06-17',
    durationMinutes: 2585,
    tags: ['ベスト・総集編', 'ハイクオリティVR', 'VR専用', '単体作品'],
    includedWorks: ['3DSVR-838', '3DSVR-849', '3DSVR-923', '3DSVR-387'],
    expectedAction: ScrapeFinalAction.exclude,
  ),
  _NaganoCorpusFixture(
    code: 'FOOMVD-026',
    title:
        'オチ〇ンポ好き痴女が集結！神テク舐めまわし＆バキューム密着限界吸引フェラでザーメン搾取 700分 120発射精・100口内発射・73回ごっくん収録！',
    releaseDate: '2025-11-30',
    durationMinutes: 700,
    tags: ['ベスト・総集編'],
    includedWorks: ['FOCS-256'],
    expectedAction: ScrapeFinalAction.exclude,
  ),
  _NaganoCorpusFixture(
    code: 'TOMNVD-019',
    title:
        '子宮めがけて執拗に突き上げで「止めちゃダメぇ！」と涙目で痙攣し限界超え連続昇天！騎乗位・抱え上げ・立ちバックで汗だく絶叫60名濃厚ハードピストンBEST！520分',
    durationMinutes: 520,
    expectedAction: ScrapeFinalAction.exclude,
  ),
  _NaganoCorpusFixture(
    code: 'HYAS-142',
    title: '可愛い女の子がチュパチュパおしゃぶりフェラ100人8時間2枚組',
    releaseDate: '2025-04-04',
    durationMinutes: 480,
    expectedAction: ScrapeFinalAction.keepReview,
  ),
  _NaganoCorpusFixture(
    code: 'SETH-016',
    title: '【VR】歴代最高 総KISS数2500回超！イチャラブキスノーカットBEST 1849分',
    durationMinutes: 1849,
    expectedAction: ScrapeFinalAction.exclude,
  ),
  _NaganoCorpusFixture(
    code: 'AMBS-083',
    title: '美少女のかわいいお尻！バックファックベスト40人',
    releaseDate: '2025-05-30',
    expectedAction: ScrapeFinalAction.exclude,
  ),
  _NaganoCorpusFixture(
    code: 'UMSO-650',
    title: '美少女BEST50本番',
    expectedAction: ScrapeFinalAction.exclude,
  ),
  _NaganoCorpusFixture(
    code: 'UMSO-651',
    title: '美少女ベスト50本番',
    expectedAction: ScrapeFinalAction.exclude,
  ),
  _NaganoCorpusFixture(
    code: 'SETH-020',
    title: '制服限定BEST30！43時間',
    expectedAction: ScrapeFinalAction.exclude,
  ),
  _NaganoCorpusFixture(
    code: 'SETH-021',
    title: '制服限定BEST30・43時間',
    expectedAction: ScrapeFinalAction.exclude,
  ),
  _NaganoCorpusFixture(
    code: 'SETH-022',
    title: '制服限定BEST30、43時間',
    expectedAction: ScrapeFinalAction.exclude,
  ),
  _NaganoCorpusFixture(
    code: 'AMBS-084',
    title: '美少女BEST30選',
    expectedAction: ScrapeFinalAction.exclude,
  ),
  _NaganoCorpusFixture(
    code: 'AMBS-085',
    title: '美少女BEST100選',
    expectedAction: ScrapeFinalAction.exclude,
  ),
  _NaganoCorpusFixture(
    code: 'CJOB-214',
    title: 'BEST11人・撮り下ろし特典映像付き',
    expectedAction: ScrapeFinalAction.exclude,
  ),
  _NaganoCorpusFixture(
    code: 'CJOB-215',
    title: 'BEST11人・完全撮り下ろし特典映像付き',
    expectedAction: ScrapeFinalAction.exclude,
  ),
  _NaganoCorpusFixture(
    code: 'CJOB-216',
    title: '永野いち夏 BEST FRIEND',
    expectedAction: ScrapeFinalAction.keep,
  ),
];
