import 'package:avaca/models/scrape_exclusion_policy.dart';
import 'package:avaca/models/scrape_rules.dart';
import 'package:avaca/models/scrape_source_settings.dart';
import 'package:avaca/models/work.dart';
import 'package:avaca/services/scrape/scrape_classification_context.dart';
import 'package:avaca/services/scrape/scrape_models.dart';
import 'package:avaca/services/scrape/provenance_semantics.dart';
import 'package:avaca/services/scrape_exclusion_policy_evaluator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps edited and viewpoint presentations without reuse evidence', () {
    final evaluator = _evaluator();

    expect(
      evaluator
          .evaluate(
            code: '3DSVR-485',
            details: [_details('3DSVR-485', 'マルチアングル編集')],
          )
          .finalAction,
      ScrapeFinalAction.keep,
    );
    expect(
      evaluator
          .evaluate(
            code: '3DSVR-531',
            details: [_details('3DSVR-531', 'マルチアングル選択型')],
          )
          .finalAction,
      ScrapeFinalAction.keep,
    );
    expect(
      evaluator
          .evaluate(
            code: '3DSVR-436',
            details: [_details('3DSVR-436', '同時多発×3視点選択型')],
          )
          .finalAction,
      ScrapeFinalAction.keep,
    );
  });

  test('excludes explicit compilation evidence', () {
    final decision = _evaluator().evaluate(
      code: '3DSVR-737',
      details: [_details('3DSVR-737', '総集編')],
    );

    expect(decision.finalAction, ScrapeFinalAction.exclude);
    expect(decision.evidenceLevel, ScrapeEvidenceLevel.strong);
    expect(decision.reasonCodes, contains('strong_compilation_evidence'));
  });

  test(
    'does not assign a family-specific verdict to OFJE or unknown families',
    () {
      final ofje = _evaluator().evaluate(
        code: 'OFJE-605',
        details: [_details('OFJE-605', '普通の単体作品')],
      );
      final unknownFamily = _evaluator().evaluate(
        code: 'MIZD-605',
        details: [_details('MIZD-605', '普通の單體作品')],
      );

      expect(ofje.finalAction, ScrapeFinalAction.keep);
      expect(ofje.reasonCodes, ['no_reuse_signal']);
      expect(ofje.policyMatches, isEmpty);
      expect(unknownFamily.reasonCodes, ofje.reasonCodes);
      expect(unknownFamily.finalAction, ofje.finalAction);
    },
  );

  test(
    'allows an exact surface even when its title looks like a compilation',
    () {
      final decision = _evaluator(
        exactAllows: const [ScrapeExactAllowRule(code: 'OFJE-605')],
      ).evaluate(code: 'OFJE-605', details: [_details('OFJE-605', '総集編')]);

      expect(decision.finalAction, ScrapeFinalAction.keep);
      expect(decision.reasonCodes, ['exact_allow']);
    },
  );

  test('allows every work in a manually allowed prefix', () {
    for (final code in const ['KCKC-212', 'TSC-015']) {
      final decision = _evaluator(
        exactAllows: [ScrapeExactAllowRule(code: code.split('-').first)],
      ).evaluate(code: code, details: [_details(code, '普通作品')]);

      expect(decision.finalAction, ScrapeFinalAction.keep, reason: code);
      expect(decision.reasonCodes, ['exact_allow'], reason: code);
    }
  });

  test('keeps explicit original work and excludes prior-work collections', () {
    final original = _evaluator().evaluate(
      code: 'MOON-001',
      details: [_details('MOON-001', '完全ノーカット撮り下ろし')],
    );
    final prior = _evaluator().evaluate(
      code: 'MOON-002',
      details: [_details('MOON-002', '全出演作品 BEST')],
    );

    expect(original.finalAction, ScrapeFinalAction.keep);
    expect(prior.finalAction, ScrapeFinalAction.exclude);
  });

  test('does not use performer count as a type predicate', () {
    final decision = _evaluator().evaluate(
      code: 'MIX-001',
      details: [_details('MIX-001', '単体作品', performerCount: 30)],
    );

    expect(decision.finalAction, ScrapeFinalAction.keep);
    expect(decision.verdict, ScrapeProvenanceVerdict.keep);
  });

  test('does not infer shared production from cast count', () {
    final decision = _evaluator().evaluate(
      code: 'MIX-CAST-001',
      details: [
        _details(
          'MIX-CAST-001',
          '多人作品',
          performers: const [
            WorkPerformer(name: '女優一'),
            WorkPerformer(name: '女優二'),
          ],
        ),
      ],
    );

    expect(decision.finalAction, ScrapeFinalAction.keep);
    expect(decision.provenanceClass, ScrapeProvenanceClass.unknown);
  });

  test('separates new independent segments from reused segments and hints', () {
    final independent = _evaluator().evaluate(
      code: 'PASN-029',
      details: [
        _details(
          'PASN-029',
          '三段独立新拍作品',
          performers: const [
            WorkPerformer(name: '女優一'),
            WorkPerformer(name: '女優二'),
            WorkPerformer(name: '女優三'),
          ],
          provenanceFacts: const ScrapeWorkProvenanceFacts(
            coPerformance: ScrapeCoPerformance.independentSegments,
          ),
        ),
      ],
    );
    final reused = _evaluator().evaluate(
      code: 'PASN-030',
      details: [
        _details(
          'PASN-030',
          '三段作品',
          provenanceFacts: const ScrapeWorkProvenanceFacts(
            reusedIndependentSegments: true,
          ),
        ),
      ],
    );
    final priorPackage = _evaluator().evaluate(
      code: 'PASN-031',
      details: [
        _details(
          'PASN-031',
          '作品パッケージ',
          provenanceFacts: const ScrapeWorkProvenanceFacts(
            packageOfPriorWorks: true,
          ),
        ),
      ],
    );
    final familyHint = _evaluator().evaluate(
      code: 'OFJE-605',
      details: [_details('OFJE-605', '普通の単体作品', studio: 'S1 NO.1 STYLE')],
    );
    final highVolumeHint = _evaluator().evaluate(
      code: 'SAFE-VOLUME-001',
      details: [_details('SAFE-VOLUME-001', '100人8時間2枚組')],
    );

    expect(independent.finalAction, ScrapeFinalAction.keep);
    expect(reused.finalAction, ScrapeFinalAction.exclude);
    expect(priorPackage.finalAction, ScrapeFinalAction.exclude);
    expect(familyHint.finalAction, ScrapeFinalAction.exclude);
    expect(familyHint.resolutionState, ScrapeResolutionState.decisiveExclude);
    expect(
      familyHint.evidence.any(
        (item) =>
            item.kind == ScrapeEvidenceKind.verifiedDerivedFamily &&
            item.strength == ScrapeEvidenceStrength.strong,
      ),
      isTrue,
    );
    final safeFamilyTitle = _evaluator().evaluate(
      code: 'OFJE-606',
      details: [_details('OFJE-606', 'BEST FRIEND', studio: 'S1 NO.1 STYLE')],
    );
    final collectionFamilyTitle = _evaluator().evaluate(
      code: 'OFJE-607',
      details: [
        _details('OFJE-607', 'BEST COLLECTION', studio: 'S1 NO.1 STYLE'),
      ],
    );
    expect(safeFamilyTitle.finalAction, ScrapeFinalAction.exclude);
    expect(collectionFamilyTitle.finalAction, ScrapeFinalAction.exclude);
    expect(
      collectionFamilyTitle.evidence.any(
        (item) =>
            item.kind == ScrapeEvidenceKind.verifiedDerivedFamily &&
            item.strength == ScrapeEvidenceStrength.strong,
      ),
      isTrue,
    );
    expect(highVolumeHint.finalAction, ScrapeFinalAction.keepReview);
    expect(highVolumeHint.finalAction, isNot(ScrapeFinalAction.exclude));
  });

  test('uses review when source surfaces conflict', () {
    final decision = _evaluator().evaluate(
      code: 'MIX-002',
      details: [
        _details('MIX-002', '総集編'),
        _details('MIX-002', '完全ノーカット撮り下ろし'),
      ],
    );

    expect(decision.finalAction, ScrapeFinalAction.keepReview);
    expect(decision.hasConflict, isTrue);
    expect(decision.reasonCodes, ['source_provenance_conflict']);
  });

  test('keeps provisional suspicion out of the final review count', () {
    final provisional = _evaluator().evaluate(
      code: 'ATKD-001',
      details: [_details('ATKD-001', '單體作品', studio: 'Attackers')],
      evidenceExhausted: false,
    );
    expect(provisional.finalAction, ScrapeFinalAction.keep);
    expect(provisional.resolutionState, ScrapeResolutionState.needsEvidence);
    expect(provisional.reviewRequired, isFalse);

    final exhausted = _evaluator().evaluate(
      code: 'ATKD-001',
      details: [_details('ATKD-001', '單體作品', studio: 'Attackers')],
    );
    expect(exhausted.finalAction, ScrapeFinalAction.keepReview);
    expect(exhausted.resolutionState, ScrapeResolutionState.finalReview);
    expect(exhausted.reviewRequired, isTrue);
  });

  test('uses source-scoped catalog evidence for verified derived families', () {
    final decision = _evaluator().evaluate(
      code: 'MIZD-270',
      details: [
        _details(
          'MIZD-270',
          '普通の作品名',
          catalogEvidence: const [
            ScrapeCatalogWorkEvidence(
              source: ScrapeSourceId.avbase,
              code: 'MIZD-270',
              title: '普通の作品名',
              manufacturer: 'MOODYZ',
              series: 'BEST',
            ),
          ],
        ),
      ],
    );

    expect(decision.finalAction, ScrapeFinalAction.exclude);
    expect(decision.reasonCodes, contains('strong_compilation_evidence'));
    expect(
      decision.evidence.any(
        (item) =>
            item.source == ScrapeSourceId.avbase &&
            item.kind == ScrapeEvidenceKind.verifiedDerivedFamily,
      ),
      isTrue,
    );
  });

  test(
    'requires high-confidence context around BEST and safe title tokens',
    () {
      for (final title in const [
        'BEST',
        'ベスト',
        '完全版',
        'マルチアングル',
        '4K COLLECTION',
        '新作',
      ]) {
        final decision = _evaluator().evaluate(
          code: 'SAFE-${title.hashCode}',
          details: [_details('SAFE-${title.hashCode}', title)],
        );
        expect(
          decision.finalAction,
          isNot(ScrapeFinalAction.exclude),
          reason: title,
        );
      }

      for (final title in const [
        '100本番BEST！8時間！',
        '制服限定BEST30 43時間',
        'BEST11人',
        'BEST COLLECTION',
      ]) {
        final decision = _evaluator().evaluate(
          code: 'DERIVED-${title.hashCode}',
          details: [_details('DERIVED-${title.hashCode}', title)],
        );
        expect(decision.finalAction, ScrapeFinalAction.exclude, reason: title);
      }
    },
  );

  test('covers the adversarial semantic safety matrix', () {
    for (final title in const [
      '全4本番',
      '全3本番ぶっ通しSEX',
      '全5本番完全新撮',
      'BEST',
      'ベスト',
      'BEST FRIEND',
      '彼女は僕のベストフレンド',
      '最高のベストコンディションSEX',
      'デビュー作から1年、さらに進化した彼女',
      'デビュー作から半年ぶりの再会',
      '大共演',
      '豪華大共演',
      '20人大共演',
      '共演スペシャル',
      'コラボ',
      'ストーリー作品',
      '完全版',
      '4K COLLECTION',
      'マルチアングル編集',
    ]) {
      final decision = _evaluator().evaluate(
        code: 'SAFE-${title.hashCode}',
        details: [_details('SAFE-${title.hashCode}', title)],
      );
      expect(
        decision.finalAction,
        isNot(ScrapeFinalAction.exclude),
        reason: title,
      );
    }
  });

  test('covers the high-confidence derived semantic matrix', () {
    for (final title in const [
      '8時間BEST',
      'BEST11人',
      '永久保存版 8時間ベスト',
      '制服限定BEST30 43時間',
      '100本番BEST！8時間！',
      'BEST COLLECTION',
      'COMPLETE BEST',
      '全12作品',
      '全12タイトル',
      '全12タイトル全部入り',
      '全4本収録',
      '12作品収録',
      '4タイトル全部入り',
      'デビュー作から現在まで',
      'デビュー作から全出演作品を収録',
      '過去作品を厳選収録',
      '総集編',
      '名場面集',
      'BEST・未公開新作映像収録',
      'BEST・撮り下ろし特典映像付き',
      'BEST11人・完全撮り下ろし特典映像付き',
      'BEST・完全撮り下ろし特典映像',
      '総集編・特典映像は全編撮り下ろし',
      '過去作品収録＋完全新撮ボーナス映像',
      'COMPLETE BEST＋全編撮り下ろし特典',
      '総集編＋新撮ボーナス映像',
      '過去作品収録＋新作カット',
      '全作品収録＋撮り下ろし映像',
      'COMPLETE BEST＋新撮特典',
    ]) {
      final decision = _evaluator().evaluate(
        code: 'DERIVED-MATRIX-${title.hashCode}',
        details: [_details('DERIVED-MATRIX-${title.hashCode}', title)],
      );
      expect(decision.finalAction, ScrapeFinalAction.exclude, reason: title);
      expect(decision.evidence, isNotEmpty, reason: title);
    }
  });

  test(
    'keeps bonus-only material uncertain and distinguishes whole production',
    () {
      for (final title in const [
        '撮り下ろし特典',
        '新撮特典',
        '新撮ボーナス',
        '未公開新作映像',
        '撮り下ろし',
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
          ScrapeProvenanceSemantics.newMaterialScope(title),
          ScrapeNewMaterialScope.bonusOnly,
          reason: title,
        );
        final decision = _evaluator().evaluate(
          code: 'BONUS-${title.hashCode}',
          details: [_details('BONUS-${title.hashCode}', title)],
        );
        expect(decision.finalAction, ScrapeFinalAction.keep, reason: title);
        expect(
          decision.evidence.any(
            (item) => item.kind == ScrapeEvidenceKind.bonusNewMaterial,
          ),
          isTrue,
          reason: title,
        );
      }

      for (final title in const [
        '全編撮り下ろし',
        '全編新撮',
        '全編新撮の大型共演',
        '完全新撮作品',
        '完全撮り下ろし新作',
        '完全新撮の大型共演',
        '全編撮り下ろし大共演',
      ]) {
        expect(
          ScrapeProvenanceSemantics.newMaterialScope(title),
          ScrapeNewMaterialScope.wholeProduction,
          reason: title,
        );
        expect(
          _evaluator()
              .evaluate(
                code: 'WHOLE-${title.hashCode}',
                details: [_details('WHOLE-${title.hashCode}', title)],
              )
              .finalAction,
          ScrapeFinalAction.keep,
          reason: title,
        );
      }

      for (final title in const [
        'BEST11人・完全撮り下ろし特典映像付き',
        'BEST・完全撮り下ろし特典映像',
        '総集編・特典映像は全編撮り下ろし',
        '過去作品収録＋完全新撮ボーナス映像',
        'COMPLETE BEST＋全編撮り下ろし特典',
        'BEST11人・全編撮り下ろしの特典映像',
        'BEST・完全新撮による特典映像',
        '総集編・全編新撮で収録した特典映像',
        '過去作品収録＋完全撮り下ろしのボーナス映像',
      ]) {
        final mixed = _evaluator().evaluate(
          code: 'MIXED-BONUS-${title.hashCode}',
          details: [_details('MIXED-BONUS-${title.hashCode}', title)],
        );
        expect(mixed.finalAction, ScrapeFinalAction.exclude, reason: title);
        expect(
          mixed.provenanceClass,
          ScrapeProvenanceClass.mixedOldNew,
          reason: title,
        );
        expect(mixed.hasConflict, isFalse, reason: title);
        expect(
          mixed.evidence.any(
            (item) =>
                item.kind == ScrapeEvidenceKind.mixedOldNew &&
                item.polarity == ScrapeEvidencePolarity.supportsCompilation,
          ),
          isTrue,
          reason: title,
        );
      }
    },
  );

  test(
    'covers collection false negatives without using cast or runtime alone',
    () {
      for (final title in const [
        'BEST50本番',
        'ベスト50本番',
        'BEST30！43時間',
        'BEST30・43時間',
        'BEST30、43時間',
        'BEST30選',
        'BEST100選',
        '12作品を収録',
        '12タイトルを収録',
        '4本を収録',
        '4本を完全収録',
        '全12作',
        '全12作収録',
        '全12作・完全収録',
        '全12作 BEST',
      ]) {
        final decision = _evaluator().evaluate(
          code: 'COLLECTION-${title.hashCode}',
          details: [_details('COLLECTION-${title.hashCode}', title)],
        );
        expect(decision.finalAction, ScrapeFinalAction.exclude, reason: title);
      }

      for (final title in const [
        '全4本番',
        '全3本番',
        '全5本番完全新撮',
        '全12作戦',
        '全12作業',
        '全12作成',
        '全12作品制作中',
      ]) {
        final decision = _evaluator().evaluate(
          code: 'SAFE-COUNT-${title.hashCode}',
          details: [_details('SAFE-COUNT-${title.hashCode}', title)],
        );
        expect(
          decision.finalAction,
          isNot(ScrapeFinalAction.exclude),
          reason: title,
        );
      }
    },
  );

  test(
    'preserves target-title BEST suffixes and rejects only standalone target BEST',
    () {
      final context = const ScrapeClassificationContext(
        targetActressName: '永野いち夏',
      );
      for (final title in const [
        '永野いち夏 BEST FRIEND',
        '永野いち夏 ベストフレンド',
        '永野いち夏 BEST PARTNER',
        '永野いち夏 BEST CONDITION',
        '永野いち夏 ベストパートナー',
        '永野いち夏 ベストコンディション',
      ]) {
        final decision = _evaluator().evaluate(
          code: 'TARGET-SAFE-${title.hashCode}',
          details: [_details('TARGET-SAFE-${title.hashCode}', title)],
          classificationContext: context,
        );
        expect(
          decision.finalAction,
          isNot(ScrapeFinalAction.exclude),
          reason: title,
        );
      }

      for (final title in const [
        '永野いち夏 BEST',
        '永野いち夏 12時間BEST',
        '永野いち夏 BEST COLLECTION',
      ]) {
        final decision = _evaluator().evaluate(
          code: 'TARGET-DERIVED-${title.hashCode}',
          details: [_details('TARGET-DERIVED-${title.hashCode}', title)],
          classificationContext: context,
        );
        expect(decision.finalAction, ScrapeFinalAction.exclude, reason: title);
      }
    },
  );

  test(
    'requires explicit prior-work wording and contextual English markers',
    () {
      for (final title in const [
        '旧作を完全収録',
        '過去作を完全収録',
        '既存作品を完全収録',
        '旧作品を厳選完全収録',
        '過去作品を厳選して収録',
        'old works included',
        'previous works collected',
        'old titles reissued',
      ]) {
        expect(
          ScrapeProvenanceSemantics.containsExplicitPriorWorkStatement(title),
          isTrue,
          reason: title,
        );
        final decision = _evaluator().evaluate(
          code: 'PRIOR-MODIFIER-${title.hashCode}',
          details: [_details('PRIOR-MODIFIER-${title.hashCode}', title)],
        );
        expect(decision.finalAction, ScrapeFinalAction.exclude, reason: title);
        expect(
          decision.evidence.any(
            (item) =>
                item.polarity == ScrapeEvidencePolarity.supportsCompilation,
          ),
          isTrue,
          reason: title,
        );
      }
    },
  );

  test('enforces metamorphic provenance safety invariants', () {
    final weakCoPerformance = [
      'BEST11人・一堂に会して',
      'BEST11人・全員参加',
      'BEST11人・同じ現場で',
    ];
    for (final title in weakCoPerformance) {
      final decision = _evaluator().evaluate(
        code: 'META-CO-${title.hashCode}',
        details: [_details('META-CO-${title.hashCode}', title)],
      );
      expect(decision.finalAction, ScrapeFinalAction.exclude, reason: title);
      expect(decision.hasConflict, isFalse, reason: title);
    }

    for (final title in const [
      'BEST11人',
      'BEST11人・撮り下ろし特典',
      'BEST11人・未公開新作映像',
    ]) {
      final decision = _evaluator().evaluate(
        code: 'META-BONUS-${title.hashCode}',
        details: [_details('META-BONUS-${title.hashCode}', title)],
      );
      expect(decision.finalAction, ScrapeFinalAction.exclude, reason: title);
    }

    for (final title in const [
      'BEST・完全版',
      'BEST・4K',
      'BEST・マルチアングル',
      'BEST・選択型',
      'old',
      'previous',
      'old model',
      'previous title',
      'GOLD・全編撮り下ろし新作',
      '18-year-old model・全編撮り下ろし',
    ]) {
      final decision = _evaluator().evaluate(
        code: 'META-SAFE-${title.hashCode}',
        details: [_details('META-SAFE-${title.hashCode}', title)],
      );
      expect(
        decision.finalAction,
        isNot(ScrapeFinalAction.exclude),
        reason: title,
      );
    }

    for (final title in const ['100人8時間', '64人323分', '30名参加']) {
      final decision = _evaluator().evaluate(
        code: 'META-COUNT-${title.hashCode}',
        details: [_details('META-COUNT-${title.hashCode}', title)],
      );
      expect(decision.finalAction, ScrapeFinalAction.keep, reason: title);
    }
  });

  test('uses explicit target identity for actress BEST semantics', () {
    final naganoContext = const ScrapeClassificationContext(
      targetActressName: '永野いち夏',
    );
    final aliasContext = const ScrapeClassificationContext(
      targetActressName: 'A',
      targetAliases: ['B'],
    );
    final genericNameContext = const ScrapeClassificationContext(
      targetActressName: '女優名',
    );

    expect(
      _evaluator()
          .evaluate(
            code: 'TARGET-NAGANO',
            details: [_details('TARGET-NAGANO', '永野いち夏 BEST')],
            classificationContext: naganoContext,
          )
          .finalAction,
      ScrapeFinalAction.exclude,
    );
    for (final title in const [
      'AIKA BEST',
      'AIKABEST',
      'AIKA-BEST',
      'AIKA・BEST',
      'AIKA：BEST',
      'AIKA 12時間BEST',
    ]) {
      final decision = _evaluator().evaluate(
        code: 'TARGET-AIKA-EXACT-${title.hashCode}',
        details: [_details('TARGET-AIKA-EXACT-${title.hashCode}', title)],
        classificationContext: const ScrapeClassificationContext(
          targetActressName: 'AIKA',
        ),
      );
      expect(decision.finalAction, ScrapeFinalAction.exclude, reason: title);
    }
    for (final title in const [
      'MAIKA BEST',
      'XAIKA BEST',
      'SAIKA BEST',
      'AIKANA BEST',
    ]) {
      final decision = _evaluator().evaluate(
        code: 'TARGET-AIKA-BOUNDARY-${title.hashCode}',
        details: [_details('TARGET-AIKA-BOUNDARY-${title.hashCode}', title)],
        classificationContext: const ScrapeClassificationContext(
          targetActressName: 'AIKA',
        ),
      );
      expect(
        decision.finalAction,
        isNot(ScrapeFinalAction.exclude),
        reason: title,
      );
      expect(
        decision.evidence.where(
          (item) => item.ruleId == 'semantic_target_actress_best',
        ),
        isEmpty,
        reason: title,
      );
    }
    for (final title in const [
      'AIKA BEST FRIEND',
      'AIKA BEST PARTNER',
      'AIKA BEST CONDITION',
    ]) {
      final decision = _evaluator().evaluate(
        code: 'TARGET-AIKA-SAFE-${title.hashCode}',
        details: [_details('TARGET-AIKA-SAFE-${title.hashCode}', title)],
        classificationContext: const ScrapeClassificationContext(
          targetActressName: 'AIKA',
        ),
      );
      expect(
        decision.finalAction,
        isNot(ScrapeFinalAction.exclude),
        reason: title,
      );
      expect(
        decision.evidence.where(
          (item) => item.ruleId == 'semantic_target_actress_best',
        ),
        isEmpty,
        reason: title,
      );
    }
    for (final title in const ['永野いち夏BEST', '永野いち夏・BEST', '永野いち夏-BEST']) {
      final decision = _evaluator().evaluate(
        code: 'TARGET-NAGANO-SEPARATOR-${title.hashCode}',
        details: [_details('TARGET-NAGANO-SEPARATOR-${title.hashCode}', title)],
        classificationContext: naganoContext,
      );
      expect(decision.finalAction, ScrapeFinalAction.exclude, reason: title);
    }
    final prefixedNagano = _evaluator().evaluate(
      code: 'TARGET-NAGANO-BOUNDARY',
      details: [_details('TARGET-NAGANO-BOUNDARY', '新永野いち夏 BEST')],
      classificationContext: naganoContext,
    );
    expect(prefixedNagano.finalAction, isNot(ScrapeFinalAction.exclude));
    expect(
      prefixedNagano.evidence.where(
        (item) => item.ruleId == 'semantic_target_actress_best',
      ),
      isEmpty,
    );
    expect(
      _evaluator()
          .evaluate(
            code: 'TARGET-GENERIC-NAME',
            details: [_details('TARGET-GENERIC-NAME', '女優名 BEST')],
            classificationContext: genericNameContext,
          )
          .finalAction,
      ScrapeFinalAction.exclude,
    );
    expect(
      _evaluator()
          .evaluate(
            code: 'TARGET-NAGANO-RUNTIME',
            details: [_details('TARGET-NAGANO-RUNTIME', '永野いち夏 12時間BEST')],
            classificationContext: naganoContext,
          )
          .finalAction,
      ScrapeFinalAction.exclude,
    );
    expect(
      _evaluator()
          .evaluate(
            code: 'TARGET-AIKA-WRONG',
            details: [_details('TARGET-AIKA-WRONG', 'AIKA BEST')],
            classificationContext: naganoContext,
          )
          .finalAction,
      isNot(ScrapeFinalAction.exclude),
    );
    expect(
      _evaluator()
          .evaluate(
            code: 'TARGET-AIKA',
            details: [_details('TARGET-AIKA', 'AIKA BEST')],
            classificationContext: const ScrapeClassificationContext(
              targetActressName: 'AIKA',
            ),
          )
          .finalAction,
      ScrapeFinalAction.exclude,
    );
    expect(
      _evaluator()
          .evaluate(
            code: 'TARGET-ALIAS',
            details: [_details('TARGET-ALIAS', 'B 8時間BEST')],
            classificationContext: aliasContext,
          )
          .finalAction,
      ScrapeFinalAction.exclude,
    );
    expect(
      _evaluator()
          .evaluate(
            code: 'TARGET-SAFE-FRIEND',
            details: [_details('TARGET-SAFE-FRIEND', '彼女は僕のベストフレンド')],
            classificationContext: naganoContext,
          )
          .finalAction,
      ScrapeFinalAction.keep,
    );
  });

  test(
    'keeps proven shared new productions but not weak co-performance hints',
    () {
      final weak = _evaluator().evaluate(
        code: 'SHARED-HINT',
        details: [
          _details(
            'SHARED-HINT',
            '大共演',
            provenanceFacts: const ScrapeWorkProvenanceFacts(
              coPerformance: ScrapeCoPerformance.possibleSharedProduction,
            ),
          ),
        ],
      );
      final proven = _evaluator().evaluate(
        code: 'SHARED-PROVEN',
        details: [
          _details(
            'SHARED-PROVEN',
            '20人大共演・全員同時出演・全編撮り下ろし新作',
            provenanceFacts: const ScrapeWorkProvenanceFacts(
              coPerformance: ScrapeCoPerformance.sharedProduction,
            ),
          ),
        ],
      );
      final concreteLineage = _evaluator().evaluate(
        code: 'SHARED-LINEAGE',
        details: [
          _details(
            'SHARED-LINEAGE',
            '豪華大共演',
            provenanceFacts: const ScrapeWorkProvenanceFacts(
              includedWorks: ['OLD-001', 'OLD-002', 'OLD-003'],
              coPerformance: ScrapeCoPerformance.possibleSharedProduction,
            ),
          ),
        ],
      );
      final bestWithHint = _evaluator().evaluate(
        code: 'SHARED-BEST',
        details: [
          _details(
            'SHARED-BEST',
            '豪華共演BEST11人',
            provenanceFacts: const ScrapeWorkProvenanceFacts(
              coPerformance: ScrapeCoPerformance.possibleSharedProduction,
            ),
          ),
        ],
      );
      final concreteProvenShared = _evaluator().evaluate(
        code: 'SHARED-LINEAGE-PROVEN',
        details: [
          _details(
            'SHARED-LINEAGE-PROVEN',
            '豪華大共演',
            provenanceFacts: const ScrapeWorkProvenanceFacts(
              includedWorks: ['OLD-004', 'OLD-005'],
              coPerformance: ScrapeCoPerformance.sharedProduction,
            ),
          ),
        ],
      );

      expect(weak.finalAction, ScrapeFinalAction.keep);
      expect(weak.reasonCodes, contains('no_reuse_signal'));
      expect(proven.finalAction, ScrapeFinalAction.keep);
      expect(proven.provenanceClass, ScrapeProvenanceClass.originalCostar);
      expect(concreteLineage.finalAction, ScrapeFinalAction.exclude);
      expect(concreteLineage.hasConflict, isFalse);
      expect(bestWithHint.finalAction, ScrapeFinalAction.exclude);
      expect(bestWithHint.hasConflict, isFalse);
      expect(concreteProvenShared.finalAction, ScrapeFinalAction.exclude);
      expect(concreteProvenShared.hasConflict, isFalse);
    },
  );

  test('excludes mixed old material with a new bonus but not new作 alone', () {
    final mixed = _evaluator().evaluate(
      code: 'MIXED-001',
      details: [_details('MIXED-001', '過去作品収録・新作映像収録')],
    );
    final newOnly = _evaluator().evaluate(
      code: 'NEW-001',
      details: [_details('NEW-001', '新作映像')],
    );
    final newBonusWithoutReuse = _evaluator().evaluate(
      code: 'NEW-002',
      details: [_details('NEW-002', '新作映像収録')],
    );
    final bestWithBonus = _evaluator().evaluate(
      code: 'MIXED-002',
      details: [_details('MIXED-002', 'BEST・未公開新作映像')],
    );

    expect(mixed.finalAction, ScrapeFinalAction.exclude);
    expect(newOnly.finalAction, ScrapeFinalAction.keep);
    expect(newBonusWithoutReuse.finalAction, ScrapeFinalAction.keep);
    expect(bestWithBonus.finalAction, ScrapeFinalAction.exclude);
  });

  test(
    'closes real re-edit, reissue, and premium-repackage provenance gaps',
    () {
      final reeditTitles = const [
        '未公開映像収録のプレミアムエディション！ディレクターズカット版 新人NO.1STYLE 河北彩花 AVデビュー',
        'IPZZ-080 未公開映像収録のプレミアムエディション！ディレクターズカット版 BEAUTY VENUS VI',
        'REPLAY ドリーム学園3 ディレクターズカット版',
        "director's cut",
        '再編集版',
      ];
      for (final title in reeditTitles) {
        final decision = _evaluator().evaluate(
          code: 'REEDIT-${title.hashCode}',
          details: [_details('REEDIT-${title.hashCode}', title)],
        );

        expect(decision.finalAction, ScrapeFinalAction.exclude, reason: title);
        expect(
          decision.evidence.any(
            (item) =>
                item.kind == ScrapeEvidenceKind.reedit &&
                item.polarity == ScrapeEvidencePolarity.supportsCompilation,
          ),
          isTrue,
          reason: title,
        );
      }

      final reissueTitles = const [
        '未公開映像収録のプレミアムエディション！河北彩花 既存作品',
        'LOVE GIRL (REPLAY版)',
        'ブラックパール(再販版)',
        '再リリース作品',
      ];
      for (final title in reissueTitles) {
        final decision = _evaluator().evaluate(
          code: 'REISSUE-${title.hashCode}',
          details: [_details('REISSUE-${title.hashCode}', title)],
        );

        expect(decision.finalAction, ScrapeFinalAction.exclude, reason: title);
        expect(
          decision.evidence.any(
            (item) =>
                item.kind == ScrapeEvidenceKind.reissue &&
                item.polarity == ScrapeEvidencePolarity.supportsCompilation,
          ),
          isTrue,
          reason: title,
        );
      }

      final premiumOnly = _evaluator().evaluate(
        code: 'PREMIUM-001',
        details: [_details('PREMIUM-001', '未公開映像収録のプレミアムエディション')],
      );
      expect(
        premiumOnly.evidence.any(
          (item) => item.ruleId == 'semantic_premium_repackage',
        ),
        isTrue,
      );
    },
  );

  test('keeps standalone premium, unreleased, and editing labels safe', () {
    for (final title in const [
      '未公開映像',
      '未公開映像収録',
      'プレミアムエディション',
      '完全版',
      'マルチアングル編集',
    ]) {
      final decision = _evaluator().evaluate(
        code: 'REEDIT-SAFE-${title.hashCode}',
        details: [_details('REEDIT-SAFE-${title.hashCode}', title)],
      );

      expect(
        decision.finalAction,
        isNot(ScrapeFinalAction.exclude),
        reason: title,
      );
      expect(
        decision.evidence.where(
          (item) =>
              item.strength == ScrapeEvidenceStrength.strong &&
              item.polarity == ScrapeEvidencePolarity.supportsCompilation,
        ),
        isEmpty,
        reason: title,
      );
    }
  });

  test('a former prefix never excludes an otherwise unknown work', () {
    final decision = _evaluator().evaluate(
      code: 'FC2-001',
      details: [_details('FC2-001', '普通作品')],
    );

    expect(decision.finalAction, ScrapeFinalAction.keep);
    expect(decision.reasonCodes, ['no_reuse_signal']);
  });

  test('unions source-scoped exact allows across all resolved surfaces', () {
    final decision =
        _evaluator(
          exactAllows: const [
            ScrapeExactAllowRule(code: 'MIX-003', source: 'javbus'),
            ScrapeExactAllowRule(code: 'MIX-003', source: 'avbase'),
          ],
        ).evaluate(
          code: 'MIX-003',
          details: [
            _details('MIX-003', '總集編', source: ScrapeSourceId.javbus),
            _details('MIX-003', '總集', source: ScrapeSourceId.avbase),
          ],
        );

    expect(decision.finalAction, ScrapeFinalAction.keep);
    expect(decision.reasonCodes, ['exact_allow']);
    expect(decision.policyMatches, hasLength(2));
  });

  test(
    'a later generic exact allow can cover an earlier source-specific match',
    () {
      final decision =
          _evaluator(
            exactAllows: const [
              ScrapeExactAllowRule(code: 'MIX-004', source: 'javbus'),
              ScrapeExactAllowRule(code: 'MIX-004'),
            ],
          ).evaluate(
            code: 'MIX-004',
            details: [
              _details('MIX-004', '總集', source: ScrapeSourceId.javbus),
              _details('MIX-004', '總集', source: ScrapeSourceId.avbase),
            ],
          );

      expect(decision.finalAction, ScrapeFinalAction.keep);
    },
  );

  test('classifies concrete lineage as a derived work', () {
    final decision = _evaluator().evaluate(
      code: 'COLL-001',
      details: [
        _details(
          'COLL-001',
          '作品集',
          provenanceFacts: const ScrapeWorkProvenanceFacts(
            includedWorks: ['OLD-001', 'OLD-002'],
          ),
        ),
      ],
    );

    expect(decision.finalAction, ScrapeFinalAction.exclude);
    expect(decision.provenanceClass, ScrapeProvenanceClass.derivedOmnibus);
    expect(decision.verdict, ScrapeProvenanceVerdict.exclude);
  });

  test('keeps a concrete shared co-performance', () {
    final decision = _evaluator().evaluate(
      code: 'COSTAR-001',
      details: [
        _details(
          'COSTAR-001',
          '共演新作',
          provenanceFacts: const ScrapeWorkProvenanceFacts(
            coPerformance: ScrapeCoPerformance.sharedProduction,
          ),
        ),
      ],
    );

    expect(decision.finalAction, ScrapeFinalAction.keep);
    expect(decision.provenanceClass, ScrapeProvenanceClass.originalCostar);
  });

  test(
    'disabling the automatic filter never turns strong lineage into exclude',
    () {
      final decision = _evaluator(autoExcludeDerivedWorks: false).evaluate(
        code: 'COLL-002',
        details: [
          _details(
            'COLL-002',
            '作品集',
            provenanceFacts: const ScrapeWorkProvenanceFacts(
              includedWorks: ['OLD-003'],
            ),
          ),
        ],
      );

      expect(decision.finalAction, ScrapeFinalAction.keepReview);
      expect(decision.reasonCodes, contains('derived_work_filter_disabled'));
    },
  );

  test('supports an exact manual deny rule', () {
    final decision = _evaluator(
      exactDenies: const [ScrapeExactDenyRule(code: 'MANUAL-001')],
    ).evaluate(code: 'MANUAL-001', details: [_details('MANUAL-001', '普通作品')]);

    expect(decision.finalAction, ScrapeFinalAction.exclude);
    expect(decision.reasonCodes, ['exact_deny']);
  });

  test('excludes every work in a manually denied prefix', () {
    for (final code in const ['KCKC-212', 'TSC-028']) {
      final decision = _evaluator(
        exactDenies: [ScrapeExactDenyRule(code: code.split('-').first)],
      ).evaluate(code: code, details: [_details(code, '普通作品')]);

      expect(decision.finalAction, ScrapeFinalAction.exclude, reason: code);
      expect(decision.reasonCodes, ['exact_deny'], reason: code);
    }
  });

  test('conflicting exact allow and deny rules fail open to review', () {
    final decision =
        _evaluator(
          exactAllows: const [ScrapeExactAllowRule(code: 'CONFLICT-001')],
          exactDenies: const [ScrapeExactDenyRule(code: 'CONFLICT-001')],
        ).evaluate(
          code: 'CONFLICT-001',
          details: [_details('CONFLICT-001', '普通作品')],
        );

    expect(decision.finalAction, ScrapeFinalAction.keepReview);
    expect(decision.reasonCodes, ['manual_override_conflict']);
    expect(decision.hasConflict, isTrue);
  });
}

ScrapeExclusionPolicyEvaluator _evaluator({
  List<ScrapeExactAllowRule> exactAllows = const [],
  List<ScrapeExactDenyRule> exactDenies = const [],
  bool autoExcludeDerivedWorks = true,
}) {
  return ScrapeExclusionPolicyEvaluator(
    ScrapePolicySnapshot.current(
      rules: ScrapeRules.builtin,
      exactAllows: exactAllows,
      exactDenies: exactDenies,
      autoExcludeDerivedWorks: autoExcludeDerivedWorks,
    ),
  );
}

ScrapeWorkDetails _details(
  String code,
  String title, {
  int? performerCount,
  ScrapeSourceId source = ScrapeSourceId.javbus,
  ScrapeWorkProvenanceFacts provenanceFacts = const ScrapeWorkProvenanceFacts(),
  List<WorkPerformer>? performers,
  String? studio,
  String? publisher,
  String? series,
  List<ScrapeCatalogWorkEvidence> catalogEvidence = const [],
}) {
  return ScrapeWorkDetails(
    source: source,
    code: code,
    title: title,
    performerCount: performerCount,
    performers: performers,
    studio: studio,
    publisher: publisher,
    series: series,
    provenanceFacts: provenanceFacts,
    catalogEvidence: catalogEvidence,
  );
}
