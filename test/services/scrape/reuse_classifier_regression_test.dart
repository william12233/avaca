import 'package:avaca/models/scrape_exclusion_policy.dart';
import 'package:avaca/models/scrape_rules.dart';
import 'package:avaca/models/scrape_source_settings.dart';
import 'package:avaca/models/work.dart';
import 'package:avaca/services/scrape/scrape_models.dart';
import 'package:avaca/services/scrape/scrape_product_family_registry.dart';
import 'package:avaca/services/scrape/work_identity.dart';
import 'package:avaca/services/scrape_exclusion_policy_evaluator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps the requested normal STARS regression matrix', () {
    const normalStarsCodes = [
      'STARS-087',
      'STARS-127',
      'STARS-145',
      'STARS-161',
      'STARS-174',
      'STARS-190',
      'STARS-205',
      'STARS-220',
      'STARS-232',
      'STARS-244',
      'STARS-256',
      'STARS-266',
      'STARS-287',
      'STARS-296',
      'STARS-315',
      'STARS-332',
      'STARS-334',
    ];

    for (final code in normalStarsCodes) {
      final decision = _evaluator().evaluate(
        code: code,
        details: [_details(code, '普通新作單體作品', studio: 'SODクリエイト')],
      );

      expect(decision.finalAction, ScrapeFinalAction.keep, reason: code);
      expect(
        decision.resolutionState,
        ScrapeResolutionState.decisiveKeep,
        reason: code,
      );
      expect(
        decision.evidence.where(
          (item) => item.kind == ScrapeEvidenceKind.productFamilySuspicion,
        ),
        isEmpty,
        reason: code,
      );
      expect(decision.reviewRequired, isFalse, reason: code);
    }
  });

  test('canonicalizes SOD identity only when source context is present', () {
    const sodEvidence = ScrapeWorkIdentityEvidence(manufacturer: 'SODクリエイト');
    final contextual = [
      for (final code in const [
        'STARS-087',
        'STARS-87',
        'STARS-087-V',
        'STARS-087-VT',
        'STARS-087-VT2-EC',
        'STARSBD-087',
      ])
        parseScrapeWorkCodeIdentity(code, evidence: sodEvidence),
    ];
    expect(
      contextual.map((identity) => identity?.displayCode),
      everyElement('STARS-087'),
    );
    expect(parseScrapeWorkCodeIdentity('STARS-87')?.displayCode, 'STARS-87');
    expect(
      scrapeWorkCodesEqual('SIVR00303', 'SIVR-303', evidence: sodEvidence),
      isFalse,
    );
  });

  test('excludes the researched derived-only product families', () {
    const cases = {
      'OFJE-453': 'S1 NO.1 STYLE',
      'OFJE-455': 'S1 NO.1 STYLE',
      'OFJE-462': 'S1 NO.1 STYLE',
      'OFJE-470': 'S1 NO.1 STYLE',
      'OFJE-480': 'S1 NO.1 STYLE',
      'OFJE-494': 'S1 NO.1 STYLE',
      'MIZD-270': 'MOODYZ',
      'RBB-249': 'ROOKIE',
      'RBB-253': 'ROOKIE',
      'RBB-265': 'ROOKIE',
    };

    for (final entry in cases.entries) {
      final decision = _evaluator().evaluate(
        code: entry.key,
        details: [_details(entry.key, '普通作品名', studio: entry.value)],
      );

      expect(
        decision.finalAction,
        ScrapeFinalAction.exclude,
        reason: entry.key,
      );
      expect(
        decision.resolutionState,
        ScrapeResolutionState.decisiveExclude,
        reason: entry.key,
      );
      expect(
        decision.evidence,
        contains(
          predicate<ScrapeEvidenceAtom>(
            (item) =>
                item.kind == ScrapeEvidenceKind.verifiedDerivedFamily &&
                item.strength == ScrapeEvidenceStrength.strong,
          ),
        ),
        reason: entry.key,
      );
      expect(decision.reviewRequired, isFalse, reason: entry.key);
    }
  });

  test('covers every verified family without adding a bare prefix rule', () {
    const cases = {
      'OFJE-900': 'S1 NO.1 STYLE',
      'MIZD-900': 'MOODYZ',
      'RBB-900': 'ROOKIE',
      'KWBD-900': 'kawaii*',
      'IDBD-900': 'IdeaPocket',
    };

    for (final entry in cases.entries) {
      final decision = _evaluator().evaluate(
        code: entry.key,
        details: [_details(entry.key, '普通新作', studio: entry.value)],
      );
      expect(
        decision.finalAction,
        ScrapeFinalAction.exclude,
        reason: entry.key,
      );
      expect(
        decision.evidence.any(
          (item) => item.kind == ScrapeEvidenceKind.verifiedDerivedFamily,
        ),
        isTrue,
        reason: entry.key,
      );
    }

    final barePrefix = _evaluator().evaluate(
      code: 'OFJE-999',
      details: [_details('OFJE-999', '普通新作')],
    );
    expect(barePrefix.finalAction, ScrapeFinalAction.keep);
    expect(barePrefix.evidence, isEmpty);
  });

  test('keeps the mixed KIBD family neutral and uses source markers', () {
    final normal = _evaluator().evaluate(
      code: 'KIBD-355',
      details: [
        _details(
          'KIBD-355',
          'むちむち肉感デカ尻ギャルにガン突きバックピストン94連発！',
          studio: 'kira☆kira',
          publisher: 'kira☆kira',
        ),
      ],
    );
    expect(normal.finalAction, ScrapeFinalAction.keep);
    expect(normal.resolutionState, ScrapeResolutionState.decisiveKeep);
    expect(normal.reviewRequired, isFalse);
    expect(normal.reasonCodes, ['no_reuse_signal']);
    expect(
      normal.evidence.where(
        (item) => item.kind == ScrapeEvidenceKind.productFamilySuspicion,
      ),
      isEmpty,
    );

    final derived = _evaluator().evaluate(
      code: 'KIBD-353',
      details: [
        _details(
          'KIBD-353',
          'ギャルセフレとタダハメベストッ！！',
          studio: 'kira☆kira',
          publisher: 'kira☆kira',
          series: 'kira☆kira BEST',
        ),
      ],
    );
    expect(derived.finalAction, ScrapeFinalAction.exclude);
    expect(
      derived.evidence,
      contains(
        predicate<ScrapeEvidenceAtom>(
          (item) =>
              item.kind == ScrapeEvidenceKind.verifiedDerivedFamily &&
              item.ruleId == 'source_declared_derived_product_line',
        ),
      ),
    );

    final titleOnlyDerived = _evaluator().evaluate(
      code: 'KIBD-356',
      details: [
        _details(
          'KIBD-356',
          '俺だけに従順なギャルセフレと中出し三昧BEST',
          studio: 'kira☆kira',
          publisher: 'kira☆kira',
        ),
      ],
    );
    expect(titleOnlyDerived.finalAction, ScrapeFinalAction.exclude);
    expect(
      titleOnlyDerived.resolutionState,
      ScrapeResolutionState.decisiveExclude,
    );

    final normalWithPresentationWording = _evaluator().evaluate(
      code: 'KIBD-354',
      details: [
        _details(
          'KIBD-354',
          '幼なじみの生意気ギャルと保健室で240分完全保存版',
          studio: 'kira☆kira',
          publisher: 'kira☆kira',
          series: '学校サボって一日中精子枯れるまでヤリまくり！',
        ),
      ],
    );
    expect(normalWithPresentationWording.finalAction, ScrapeFinalAction.keep);
    expect(normalWithPresentationWording.reviewRequired, isFalse);
  });

  test('models mixed family prefix matches as neutral diagnostics', () {
    final match = ScrapeProductFamilyRegistry.match(
      code: 'KIBD-355',
      manufacturer: 'kira☆kira',
      label: 'kira☆kira',
    );
    expect(match, isNotNull);
    expect(match!.disposition, ScrapeProductFamilyDisposition.neutralMixed);
  });

  test('general mixed-family logic keeps PPBD originals and excludes BEST', () {
    // Frozen AvBase records observed on 2026-08-27: PPBD-322 is an ordinary
    // high-volume release, while PPBD-323 explicitly declares an 8-hour BEST
    // collection in its title and series metadata.
    final normal = _evaluator().evaluate(
      code: 'PPBD-322',
      details: [
        _details(
          'PPBD-322',
          '【シンクロ挟射特化】カウントダウン字幕付きパイズリ射精の瞬間に合わせられるオナニー映像80連発',
          studio: 'OPPAI',
          publisher: 'OPPAI',
        ),
      ],
    );
    expect(normal.finalAction, ScrapeFinalAction.keep);
    expect(normal.resolutionState, ScrapeResolutionState.decisiveKeep);
    expect(normal.reviewRequired, isFalse);
    expect(normal.evidence, isEmpty);

    final derived = _evaluator().evaluate(
      code: 'PPBD-323',
      details: [
        _details(
          'PPBD-323',
          '彼女のお姉さんは巨乳と中出しOKで僕を誘惑6タイトル大ボリューム8時間BEST vol.10',
          studio: 'OPPAI',
          publisher: 'OPPAI',
          series: '彼女の●●さんは巨乳と中出しOKで僕を誘惑',
        ),
      ],
    );
    expect(derived.finalAction, ScrapeFinalAction.exclude);
    expect(derived.resolutionState, ScrapeResolutionState.decisiveExclude);
    expect(
      derived.evidence,
      contains(
        predicate<ScrapeEvidenceAtom>(
          (item) =>
              item.kind == ScrapeEvidenceKind.verifiedDerivedFamily &&
              item.ruleId == 'source_declared_derived_product_line',
        ),
      ),
    );

    final match = ScrapeProductFamilyRegistry.match(
      code: 'PPBD-322',
      manufacturer: 'OPPAI',
      label: 'OPPAI',
    );
    expect(match, isNotNull);
    expect(match!.disposition, ScrapeProductFamilyDisposition.neutralMixed);
  });

  test('accepts Japanese catalog maker and label evidence', () {
    final cases = {
      'MIZD-270': ('ムーディーズ', 'MOODYZ Best'),
      'IDBD-995': ('アイデアポケット', 'アイデアポケットBEST'),
    };
    for (final entry in cases.entries) {
      final decision = _evaluator().evaluate(
        code: entry.key,
        details: [
          _details(
            entry.key,
            'catalogued work',
            studio: entry.value.$1,
            publisher: entry.value.$2,
          ),
        ],
      );
      expect(
        decision.finalAction,
        ScrapeFinalAction.exclude,
        reason: entry.key,
      );
      expect(
        decision.evidence.any(
          (item) => item.kind == ScrapeEvidenceKind.verifiedDerivedFamily,
        ),
        isTrue,
        reason: entry.key,
      );
    }
  });

  test('uses a maker-matching exact series as general derived evidence', () {
    final decision = _evaluator().evaluate(
      code: 'SER-001',
      details: [
        _details(
          'SER-001',
          'E-BODY premium BEST 2023',
          studio: 'E-BODY',
          publisher: 'E-BODY',
          series: 'E-BODY BEST PROPORTIONS',
        ),
      ],
    );

    expect(decision.finalAction, ScrapeFinalAction.exclude);
    expect(decision.resolutionState, ScrapeResolutionState.decisiveExclude);
    expect(
      decision.evidence,
      contains(
        predicate<ScrapeEvidenceAtom>(
          (item) =>
              item.kind == ScrapeEvidenceKind.verifiedDerivedFamily &&
              item.ruleId == 'source_declared_derived_product_line',
        ),
      ),
    );
  });

  test('keeps MOODYZ MIRD counterexamples without reuse evidence', () {
    const cases = {
      'MIRD-270': 'MOODYZ MIRD original work 270',
      'MIRD-272': 'MOODYZ MIRD original work 272',
      'MIRD-274': 'MOODYZ MIRD original work 274',
    };

    for (final entry in cases.entries) {
      final decision = _evaluator().evaluate(
        code: entry.key,
        details: [
          _details(
            entry.key,
            entry.value,
            studio: 'MOODYZ',
            publisher: 'MOODYZ',
          ),
        ],
      );

      expect(decision.finalAction, ScrapeFinalAction.keep, reason: entry.key);
      expect(
        decision.resolutionState,
        ScrapeResolutionState.decisiveKeep,
        reason: entry.key,
      );
      expect(decision.reviewRequired, isFalse, reason: entry.key);
      expect(
        decision.evidence.where(
          (item) =>
              item.kind == ScrapeEvidenceKind.productFamilySuspicion ||
              item.kind == ScrapeEvidenceKind.verifiedDerivedFamily,
        ),
        isEmpty,
        reason: entry.key,
      );
    }
  });

  test(
    'keeps suspicion-only families provisional until evidence is exhausted',
    () {
      const cases = {
        'ATKD-001': 'Attackers',
        'JUSD-001': 'Madonna',
        'THN-001': 'Prestige',
      };

      for (final entry in cases.entries) {
        final provisional = _evaluator().evaluate(
          code: entry.key,
          details: [_details(entry.key, '普通作品', studio: entry.value)],
          evidenceExhausted: false,
        );
        expect(
          provisional.finalAction,
          ScrapeFinalAction.keep,
          reason: entry.key,
        );
        expect(
          provisional.resolutionState,
          ScrapeResolutionState.needsEvidence,
          reason: entry.key,
        );
        expect(provisional.reviewRequired, isFalse, reason: entry.key);

        final exhausted = _evaluator().evaluate(
          code: entry.key,
          details: [_details(entry.key, '普通作品', studio: entry.value)],
        );
        expect(
          exhausted.finalAction,
          ScrapeFinalAction.keepReview,
          reason: entry.key,
        );
        expect(
          exhausted.resolutionState,
          ScrapeResolutionState.finalReview,
          reason: entry.key,
        );
        expect(exhausted.reviewRequired, isTrue, reason: entry.key);
      }
    },
  );

  test('does not infer reuse from the mandatory maker matrix alone', () {
    const makers = {
      'MATRIX-S1': 'S1 NO.1 STYLE',
      'MATRIX-MOODYZ': 'MOODYZ',
      'MATRIX-PRESTIGE': 'Prestige',
      'MATRIX-KAWAII': 'kawaii*',
      'MATRIX-011': 'IdeaPocket',
      'MATRIX-ATTACKERS': 'Attackers',
      'MATRIX-MADONNA': 'Madonna',
      'MATRIX-OPPAI': 'OPPAI',
      'MATRIX-DAS': 'DAS!',
      'MATRIX-WANZ': 'WANZ',
      'MATRIX-KIRA': 'kira☆kira',
      'MATRIX-ROOKIE': 'ROOKIE',
      'MATRIX-KMP': 'KMP',
      'MATRIX-KMPVR': 'KMPVR',
    };

    for (final entry in makers.entries) {
      final decision = _evaluator().evaluate(
        code: entry.key,
        details: [_details(entry.key, '新作單體作品', studio: entry.value)],
      );
      expect(decision.finalAction, ScrapeFinalAction.keep, reason: entry.key);
      expect(decision.reviewRequired, isFalse, reason: entry.key);
    }
  });

  test('keeps ordinary semantic formats and unknown provenance', () {
    final cases = <String, ScrapeWorkDetails>{
      'normal solo': _details('SAFE-001', '新作單體作品'),
      'genuine costar': _details(
        'SAFE-002',
        '完全新撮共演作品',
        coPerformance: ScrapeCoPerformance.sharedProduction,
      ),
      'independent multi-actress': _details(
        'SAFE-003',
        '三段獨立新拍作品',
        coPerformance: ScrapeCoPerformance.independentSegments,
        performers: const [
          WorkPerformer(name: '女優一'),
          WorkPerformer(name: '女優二'),
        ],
      ),
      'new VR': _details('SIVR-003', 'VR新作'),
      'multiview': _details('3DSVR-003', 'マルチアングル選択型'),
      'long duration': _details('SAFE-004', '180分ロング新作', durationMinutes: 180),
      'anniversary': _details('SAFE-005', '10周年記念新作'),
      'uncut': _details('SAFE-006', '完全ノーカット新作'),
      'three acts': _details('SAFE-007', '3本番新作'),
      'five acts': _details('SAFE-008', '5本番新作'),
      'high volume': _details('SAFE-009', '多人新作', performerCount: 30),
      'unknown provenance': _details('SAFE-010', '來源未標示作品'),
    };

    for (final entry in cases.entries) {
      final decision = _evaluator().evaluate(
        code: entry.value.code,
        details: [entry.value],
      );
      expect(
        decision.finalAction,
        isNot(ScrapeFinalAction.exclude),
        reason: entry.key,
      );
      expect(decision.reviewRequired, isFalse, reason: entry.key);
    }
  });

  test('does not treat safe maker metadata phrases as derived evidence', () {
    for (final series in const [
      'BEST FRIEND',
      'bestfriendship',
      'incomplete',
    ]) {
      final decision = _evaluator().evaluate(
        code: 'SAFE-${series.hashCode}',
        details: [
          _details(
            'SAFE-${series.hashCode}',
            '普通作品',
            studio: 'MOODYZ',
            series: series,
          ),
        ],
      );
      expect(decision.finalAction, ScrapeFinalAction.keep, reason: series);
      expect(
        decision.evidence.where(
          (item) => item.strength != ScrapeEvidenceStrength.weak,
        ),
        isEmpty,
        reason: series,
      );
      expect(
        decision.evidence.where(
          (item) => item.kind == ScrapeEvidenceKind.verifiedDerivedFamily,
        ),
        isEmpty,
        reason: series,
      );
    }
  });
}

ScrapeExclusionPolicyEvaluator _evaluator() {
  return ScrapeExclusionPolicyEvaluator(
    ScrapePolicySnapshot.current(
      rules: ScrapeRules.builtin,
      exactAllows: const [],
      exactDenies: const [],
      autoExcludeDerivedWorks: true,
    ),
  );
}

ScrapeWorkDetails _details(
  String code,
  String title, {
  String? studio,
  String? publisher,
  String? series,
  ScrapeCoPerformance coPerformance = ScrapeCoPerformance.unknown,
  int? durationMinutes,
  int? performerCount,
  List<WorkPerformer>? performers,
}) {
  return ScrapeWorkDetails(
    source: ScrapeSourceId.avwiki,
    code: code,
    title: title,
    studio: studio,
    publisher: publisher,
    series: series,
    coPerformance: coPerformance,
    durationMinutes: durationMinutes,
    performerCount: performerCount,
    performers: performers,
  );
}
