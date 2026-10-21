/// Shared, deliberately narrow semantic propositions used by source parsers
/// and the provenance evaluator.
///
/// These helpers only return a positive proposition when the surrounding
/// wording is strong enough to support a derived-work decision.  A bare
/// `BEST`, `ベスト`, `新作`, or `コレクション` is intentionally not enough.
enum ScrapeNewMaterialScope { none, bonusOnly, wholeProduction }

final class ScrapeProvenanceSemantics {
  const ScrapeProvenanceSemantics._();

  static final RegExp _wholeProductionPattern = RegExp(
    r'全編\s*(?:完全\s*)?(?:新撮|撮り下ろし)|完全\s*(?:ノーカット\s*)?(?:新撮|撮り下ろし)(?:\s*(?:新作|作品|映像))?|完全\s*(?:新撮|撮り下ろし)\s*(?:の\s*)?(?:大型共演|大共演)',
    caseSensitive: false,
  );

  static final RegExp _bonusScopedNewMaterialPattern = RegExp(
    r'(?:全編|完全)\s*(?:ノーカット\s*)?(?:新撮|撮り下ろし)(?:\s*(?:の|による|で\s*収録した|として(?:\s*収録(?:した)?)?))?\s*(?:特典|ボーナス|bonus)(?:\s*(?:映像|作品|カット|footage|video))?|(?:特典|ボーナス|bonus)(?:\s*(?:映像|作品|カット|footage|video))?\s*(?:は|として(?:\s*収録(?:した)?)?)?\s*(?:全編|完全)\s*(?:ノーカット\s*)?(?:新撮|撮り下ろし)',
    caseSensitive: false,
  );

  static final RegExp _bonusOnlyNewMaterialPattern = RegExp(
    r'未公開|新作(?:映像|カット|特典)|撮り下ろし(?:\s*(?:特典|ボーナス|映像|カット))?|新撮(?:\s*(?:特典|ボーナス|映像|カット))?|bonus',
    caseSensitive: false,
  );

  static final RegExp _strongReeditPattern = RegExp(
    r"再編集|ディレクターズ?[\s・･-]*カット(?:版)?|\bdirector(?:['’]?s)?\s*cut(?:\s*(?:version|edition))?|\bre[\s-]?edit(?:ed)?",
    caseSensitive: false,
  );

  static final RegExp _strongReissuePattern = RegExp(
    r'再発売|復刻|再収録|再販(?:版|商品)|再リリース|\bre[\s-]?issue(?:d)?|\bre[\s-]?release(?:d)?|\breplay\s*版',
    caseSensitive: false,
  );

  static final RegExp _premiumRepackagePattern = RegExp(
    r'(?:未公開映像\s*(?:を\s*)?(?:追加\s*)?収録)[^\n]{0,12}(?:プレミアム\s*エディション|premium\s*edition)|(?:プレミアム\s*エディション|premium\s*edition)[^\n]{0,24}(?:未公開映像\s*(?:を\s*)?(?:追加\s*)?収録)',
    caseSensitive: false,
  );

  static final RegExp _bestWithBonusPattern = RegExp(
    r'(?:best(?!\s*(?:friend|partner|condition)\b)(?![a-z0-9])|ベスト(?![\s・･]*(?:フレンド|パートナー|コンディション)))[\s・･:：+＋,，、-]{0,8}(?:全編|完全|ノーカット)?\s*(?:未公開|新作(?:映像|カット|特典)?|撮り下ろし|新撮|bonus)|(?:未公開|新作(?:映像|カット|特典)?|撮り下ろし|新撮|bonus)[^\n]{0,12}(?:best(?!\s*(?:friend|partner|condition)\b)(?![a-z0-9])|ベスト(?![\s・･]*(?:フレンド|パートナー|コンディション)))',
    caseSensitive: false,
  );

  static final RegExp _provenSharedProductionPattern = RegExp(
    r'全員\s*同時出演|同一シーンで共演|同一撮影企画|同一収録で全員共演|全編\s*(?:完全\s*)?(?:新撮|撮り下ろし)\s*(?:大共演|大型共演)|完全\s*(?:新撮|撮り下ろし)\s*の?\s*(?:大型共演|大共演)',
    caseSensitive: false,
  );

  static final RegExp _sharedProductionHintPattern = RegExp(
    r'共演|同時出演|同じ.*作品|同一.*作品|大共演|豪華共演|コラボ',
    caseSensitive: false,
  );

  static final RegExp _explicitPriorWorkStatementPattern = RegExp(
    r'(?:過去|既存|旧)(?:の)?作(?:品)?\s*(?:\d+\s*(?:本|作品|タイトル))?\s*(?:を|が)?\s*(?:再\s*)?(?:(?:完全|厳選|まとめて|すべて|全て)(?:\s*して)?\s*)*(?:収録|収録する|収録済み)|(?:old|previous)\s+(?:works?|titles?)\s+(?:included|collected|reissued|re-released)',
    caseSensitive: false,
  );

  static final RegExp _targetBestSuffixPattern = RegExp(
    r'^\s*(?:[・･\-–—:：/／]\s*)?(?:\d+\s*(?:時間|分|hours?|minutes?|h|min)\s*)?(?:best(?!\s*(?:friend|partner|condition)\b)(?![a-z0-9])|ベスト(?![\s・･]*(?:フレンド|パートナー|コンディション))(?![ぁ-んァ-ン一-龯a-z0-9]))',
    caseSensitive: false,
  );

  static final RegExp _strongSplitPattern = RegExp(
    r'分割版|分割販売|元作品\s*(?:から|を)\s*分割|個別版|単独版|split\s+(?:edition|from\s+(?:a\s+)?(?:prior|original)\s+work)|(?:prior|original)\s+work\s+(?:split|divided)',
    caseSensitive: false,
  );

  static final RegExp _independentSegmentsPattern = RegExp(
    r'各女優\s*(?:それぞれ\s*)?別作品(?:を|から)?収録|出演者ごとの独立作品|それぞれ別作品から収録|各作品を個別(?:に)?収録|独立した\s*(?:\d+|○)?\s*作品をまとめて収録|独立(?:した)?作品を(?:まとめて)?収録',
    caseSensitive: false,
  );

  static String normalize(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final normalized = switch (rune) {
        >= 0xFF01 && <= 0xFF5E => rune - 0xFEE0,
        0x3000 => 0x20,
        _ => rune,
      };
      buffer.writeCharCode(normalized);
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
  }

  static String? explicitCompilationLabel(String value) {
    final text = normalize(value);
    final match = RegExp(
      r'ベスト\s*[・･]\s*(?:総集編|総集篇|総集成)|総集編|総集篇|総集成|オムニバス|アンソロジー|作品集|選集|傑作選|名場面集|名作集',
      caseSensitive: false,
    ).firstMatch(text);
    return match?.group(0);
  }

  /// A maker-declared product line can be decisive when the source exposes
  /// the line name in a title/series/tag/description field. The maker gate,
  /// explicit maker-named series check, and bounded marker check keep safe
  /// phrases such as BEST FRIEND from becoming reuse evidence.
  static ScrapeSemanticProposition? sourceDeclaredDerivedProductLine({
    required String? manufacturer,
    required String? label,
    required String? series,
    required Iterable<String> tags,
    required String? description,
    String? title,
  }) {
    final makerText = normalize(
      [
        manufacturer ?? '',
        label ?? '',
      ].where((value) => value.isNotEmpty).join(' '),
    );
    if (makerText.isEmpty) return null;
    final normalizedSeries = normalize(series ?? '');
    final seriesDeclaresMaker =
        normalizedSeries.isNotEmpty &&
        [manufacturer, label]
            .whereType<String>()
            .map(normalize)
            .where((value) => value.length >= 3)
            .any((maker) => normalizedSeries.contains(maker));
    final values = <String?>[
      title,
      label,
      series,
      ...tags,
      description,
    ].whereType<String>();
    final knownMaker =
        RegExp(
          r's1\s*(?:no\.?\s*1|no1)\s*style|エスワン|moodyz|ムーディーズ|rookie|kawaii\s*\*?|kira\s*☆\s*kira|kirakira|ideapocket|idea\s*pocket|アイデアポケット|attackers|アタッカーズ|madonna|マドンナ|prestige|プレステージ|oppai|オッパイ|vr',
          caseSensitive: false,
        ).hasMatch(makerText) ||
        seriesDeclaresMaker;
    if (!knownMaker) return null;
    for (final value in values) {
      final text = normalize(value);
      final marker = _sourceDeclaredDerivedMarker(text);
      if (marker != null) {
        return ScrapeSemanticProposition(
          ruleId: 'source_declared_derived_product_line',
          observedText: '$makerText + $marker',
        );
      }
    }
    return null;
  }

  static String? _sourceDeclaredDerivedMarker(String text) {
    final bestPattern = RegExp(
      r'(^|[^a-z0-9])best(?=$|[^a-z0-9])',
      caseSensitive: false,
    );
    for (final match in bestPattern.allMatches(text)) {
      final suffix = text.substring(match.end);
      if (RegExp(
        r'^\s*(?:[-–—:：/／・･]\s*)?(?:friend|partner|condition)\b',
        caseSensitive: false,
      ).hasMatch(suffix)) {
        continue;
      }
      return 'best';
    }

    final marker = RegExp(
      r'ベスト(?![\s・･]*(?:フレンド|パートナー|コンディション))(?![ぁ-んァ-ン一-龯a-z0-9])|総集編|総集篇|総集成|作品集|全作品|(?:^|[^a-z0-9])collection(?=$|[^a-z0-9])|(?:^|[^a-z0-9])complete(?=$|[^a-z0-9])',
      caseSensitive: false,
    ).firstMatch(text);
    if (marker == null) return null;
    final value = marker.group(0)!;
    return value.trim().isEmpty ? marker.group(0) : value.trim();
  }

  /// Returns a title/metadata proposition that identifies a prior-work
  /// collection, or null when the text only contains a safe standalone token.
  static ScrapeSemanticProposition? strongReuseProposition(
    Iterable<String> values,
  ) {
    final text = normalize(values.join(' '));
    if (text.isEmpty) return null;
    final patterns = <({RegExp pattern, String ruleId})>[
      (
        pattern: RegExp(
          r'(?:\d+\s*(?:時間|分|hours?|minutes?|h|min)\s*(?:best|ベスト)|(?:best|ベスト)\s*\d+\s*[\s!！・:：,，、-]{0,4}\s*\d+\s*(?:時間|分|hours?|minutes?|h|min)|(?:best|ベスト)[\s!！・:：,，、-]{0,4}\d+\s*(?:時間|分|hours?|minutes?|h|min)|(?:best|ベスト)\s*\d+\s+\d+\s*(?:時間|分|hours?|minutes?|h|min))',
          caseSensitive: false,
        ),
        ruleId: 'semantic_best_runtime_collection',
      ),
      (
        pattern: RegExp(
          r'(?:best|ベスト)\s*\d+\s*(?:人|作品|タイトル|本番|本(?!番)|選)|\d+\s*本番[^\s]{0,8}(?:best|ベスト)|\d+\s*(?:人|作品|タイトル|本(?!番))[^\s]{0,6}(?:best|ベスト)',
          caseSensitive: false,
        ),
        ruleId: 'semantic_best_cast_collection',
      ),
      (
        pattern: RegExp(
          r'(?:best|ベスト)\s*(?:of|collection)|(?:complete|コンプリート)\s*(?:best|ベスト)|(?:best|ベスト)\s*(?:complete|コンプリート)',
          caseSensitive: false,
        ),
        ruleId: 'semantic_best_collection',
      ),
      (
        pattern: RegExp(
          r'(?:永久\s*)?保存版\s*(?:best|ベスト)|(?:best|ベスト)\s*(?:永久\s*)?保存版|(?:厳選|傑作)\s*(?:best|ベスト)|(?:best|ベスト)\s*(?:厳選|傑作)',
          caseSensitive: false,
        ),
        ruleId: 'semantic_best_preserved_collection',
      ),
      (
        pattern: RegExp(
          r'全\s*\d+\s*(?:作品|タイトル|作)(?=$|[\s!！・:：,，、\-+＋/／()（）【】「」『』。．.,]|(?:を|が|は)?\s*(?:収録|完全収録|全部入り|厳選|セット|best|ベスト))|全\s*\d+\s*本(?=\s*(?:収録|全部入り))|全出演作品|全作品|出演作品(?:全部|すべて|全て)|\d+\s*(?:タイトル|作品|本)\s*(?:を\s*)?(?:完全\s*)?(?:全部入り|収録)',
          caseSensitive: false,
        ),
        ruleId: 'semantic_work_count_collection',
      ),
      (
        pattern: RegExp(
          r'デビュー(?:作)?から(?:現在まで|最新作まで|全作品|全出演作品|\d+\s*(?:作品|タイトル|本)\s*(?:を)?収録|厳選収録)|歴代作品|過去作品|既存作品|再収録|厳選収録|名場面集',
          caseSensitive: false,
        ),
        ruleId: 'semantic_retrospective_range',
      ),
    ];
    for (final rule in patterns) {
      final pattern = rule.pattern;
      final match = pattern.firstMatch(text);
      if (match != null) {
        return ScrapeSemanticProposition(
          ruleId: rule.ruleId,
          observedText: match.group(0)!,
        );
      }
    }
    return null;
  }

  static ScrapeSemanticProposition? targetActressBestProposition(
    String value,
    Iterable<String> normalizedTargetNames,
  ) {
    final text = normalize(value);
    for (final name in normalizedTargetNames) {
      final normalizedName = normalize(name);
      if (normalizedName.isEmpty) continue;
      var searchStart = 0;
      while (searchStart < text.length) {
        final nameIndex = text.indexOf(normalizedName, searchStart);
        if (nameIndex < 0) break;
        final nameEnd = nameIndex + normalizedName.length;
        final before = nameIndex == 0
            ? null
            : text.substring(0, nameIndex).runes.last;
        final suffix = text.substring(nameEnd);
        if (!_isNameAdjacentRune(before)) {
          final match = _targetBestSuffixPattern.firstMatch(suffix);
          if (match != null) {
            return ScrapeSemanticProposition(
              ruleId: 'semantic_target_actress_best',
              observedText: text.substring(nameIndex, nameEnd + match.end),
            );
          }
        }
        searchStart = nameEnd;
      }
    }
    return null;
  }

  static bool _isNameAdjacentRune(int? rune) {
    if (rune == null) return false;
    return rune >= 0x30 && rune <= 0x39 ||
        rune >= 0x41 && rune <= 0x5A ||
        rune >= 0x61 && rune <= 0x7A ||
        rune >= 0x3040 && rune <= 0x30FF ||
        rune >= 0x3400 && rune <= 0x4DBF ||
        rune >= 0x4E00 && rune <= 0x9FFF ||
        rune >= 0xF900 && rune <= 0xFAFF ||
        rune >= 0xFF66 && rune <= 0xFF9D;
  }

  static bool containsReliableOriginal(String value) {
    return newMaterialScope(value) == ScrapeNewMaterialScope.wholeProduction;
  }

  static ScrapeNewMaterialScope newMaterialScope(String value) {
    final text = normalize(value);
    if (_bonusScopedNewMaterialPattern.hasMatch(text)) {
      return ScrapeNewMaterialScope.bonusOnly;
    }
    if (_wholeProductionPattern.hasMatch(text)) {
      return ScrapeNewMaterialScope.wholeProduction;
    }
    if (_bonusOnlyNewMaterialPattern.hasMatch(text)) {
      return ScrapeNewMaterialScope.bonusOnly;
    }
    return ScrapeNewMaterialScope.none;
  }

  static bool containsOldMaterialWithNewBonus(String value) {
    final text = normalize(value);
    return newMaterialScope(text) == ScrapeNewMaterialScope.bonusOnly &&
        containsStrongReuseEvidence(text);
  }

  static bool containsStrongReuseEvidence(String value) {
    final text = normalize(value);
    return explicitCompilationLabel(text) != null ||
        strongReuseProposition([text]) != null ||
        containsExplicitPriorWorkStatement(text) ||
        _bestWithBonusPattern.hasMatch(text);
  }

  static ScrapeSemanticProposition? strongReeditProposition(String value) {
    final match = _strongReeditPattern.firstMatch(normalize(value));
    return match == null
        ? null
        : ScrapeSemanticProposition(
            ruleId: 'semantic_strong_reedit',
            observedText: match.group(0)!,
          );
  }

  static bool containsStrongReeditEvidence(String value) {
    return strongReeditProposition(value) != null;
  }

  static ScrapeSemanticProposition? strongReissueProposition(String value) {
    final match = _strongReissuePattern.firstMatch(normalize(value));
    return match == null
        ? null
        : ScrapeSemanticProposition(
            ruleId: 'semantic_strong_reissue',
            observedText: match.group(0)!,
          );
  }

  static bool containsStrongReissueEvidence(String value) {
    return strongReissueProposition(value) != null;
  }

  static ScrapeSemanticProposition? premiumRepackageProposition(String value) {
    final match = _premiumRepackagePattern.firstMatch(normalize(value));
    return match == null
        ? null
        : ScrapeSemanticProposition(
            ruleId: 'semantic_premium_repackage',
            observedText: match.group(0)!,
          );
  }

  static bool containsPremiumRepackageEvidence(String value) {
    return premiumRepackageProposition(value) != null;
  }

  static bool containsExplicitPriorWorkStatement(String value) {
    return _explicitPriorWorkStatementPattern.hasMatch(normalize(value));
  }

  static bool containsStrongSplitEvidence(String value) {
    return _strongSplitPattern.hasMatch(normalize(value));
  }

  static bool containsIndependentSegments(String value) {
    return _independentSegmentsPattern.hasMatch(normalize(value));
  }

  /// A large cast plus a long runtime is only a secondary-source suspicion
  /// when the same record also describes a package/collection structure. The
  /// numbers by themselves are ordinary product metadata and remain neutral.
  static bool containsCollectionStructureSuspicion(String value) {
    final text = normalize(value);
    final hasLargeCast = RegExp(r'\d{2,}\s*(?:人|名)').hasMatch(text);
    final hasRuntime = RegExp(
      r'\d+\s*(?:時間|分|hours?|minutes?|h|min)',
      caseSensitive: false,
    ).hasMatch(text);
    final hasPackageShape = RegExp(
      r'枚組|disc|collection|作品集|総集編|best|ベスト|全部入り',
      caseSensitive: false,
    ).hasMatch(text);
    return hasLargeCast && hasRuntime && hasPackageShape;
  }

  static bool containsProvenSharedProduction(String value) {
    return _provenSharedProductionPattern.hasMatch(normalize(value));
  }

  static bool containsSharedProductionHint(String value) {
    return _sharedProductionHintPattern.hasMatch(normalize(value));
  }
}

final class ScrapeSemanticProposition {
  const ScrapeSemanticProposition({
    required this.ruleId,
    required this.observedText,
  });

  final String ruleId;
  final String observedText;
}
