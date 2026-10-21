enum ScrapeProductFamilyDisposition {
  verifiedDerivedOnly,
  suspicionOnly,
  neutralMixed,
}

/// Source-scoped product-family evidence.
///
/// A match always requires the code family and maker/label metadata from the
/// same source record. Only families backed by real catalog research may use
/// [ScrapeProductFamilyDisposition.verifiedDerivedOnly]. A family proven to
/// contain both normal originals and derived products uses
/// [ScrapeProductFamilyDisposition.neutralMixed], so its prefix never creates
/// suspicion without record-level lineage or reuse evidence.
final class ScrapeProductFamilyMatch {
  const ScrapeProductFamilyMatch({
    required this.ruleId,
    required this.family,
    required this.disposition,
    required this.observedText,
    required this.hasCollectionMarker,
  });

  final String ruleId;
  final String family;
  final ScrapeProductFamilyDisposition disposition;
  final String observedText;
  final bool hasCollectionMarker;
}

final class ScrapeProductFamilyRule {
  const ScrapeProductFamilyRule({
    required this.ruleId,
    required this.family,
    required this.prefixes,
    required this.makerTokens,
    required this.reuseTokens,
    this.disposition = ScrapeProductFamilyDisposition.suspicionOnly,
  });

  final String ruleId;
  final String family;
  final Set<String> prefixes;
  final Set<String> makerTokens;
  final Set<String> reuseTokens;
  final ScrapeProductFamilyDisposition disposition;
}

final class ScrapeProductFamilyRegistry {
  const ScrapeProductFamilyRegistry._();

  /// These are deliberately narrow. New families must be added with
  /// first-party maker/label evidence and corpus coverage, not by prefix.
  static const knownRules = <ScrapeProductFamilyRule>[
    ScrapeProductFamilyRule(
      ruleId: 'known_s1_ofje_family',
      family: 'S1 NO.1 STYLE OFJE family',
      prefixes: {'OFJE'},
      makerTokens: {
        's1 no.1 style',
        's1 no1 style',
        's-one no.1 style',
        'エスワン',
      },
      reuseTokens: {'best', '総集編', '作品集', '全作品'},
      disposition: ScrapeProductFamilyDisposition.verifiedDerivedOnly,
    ),
    ScrapeProductFamilyRule(
      ruleId: 'known_moodyz_mizd_family',
      family: 'MOODYZ MIZD family',
      prefixes: {'MIZD'},
      makerTokens: {'moodyz', 'ムーディーズ'},
      reuseTokens: {'best', '総集編', '作品集', '全作品'},
      disposition: ScrapeProductFamilyDisposition.verifiedDerivedOnly,
    ),
    ScrapeProductFamilyRule(
      ruleId: 'known_kawaii_kwbd_family',
      family: 'kawaii* KWBD family',
      prefixes: {'KWBD'},
      makerTokens: {'kawaii', 'kawaii*'},
      reuseTokens: {'best', 'ベスト', '総集編', '作品集'},
      disposition: ScrapeProductFamilyDisposition.verifiedDerivedOnly,
    ),
    ScrapeProductFamilyRule(
      ruleId: 'known_rookie_rbb_family',
      family: 'ROOKIE RBB family',
      prefixes: {'RBB'},
      makerTokens: {'rookie'},
      reuseTokens: {'best', 'ベスト', '総集編', '作品集'},
      disposition: ScrapeProductFamilyDisposition.verifiedDerivedOnly,
    ),
    ScrapeProductFamilyRule(
      ruleId: 'known_attackers_atkd_family',
      family: 'Attackers ATKD family',
      prefixes: {'ATKD'},
      makerTokens: {'attackers'},
      reuseTokens: {'best', 'ベスト', '総集編', '作品集'},
    ),
    ScrapeProductFamilyRule(
      ruleId: 'known_ideapocket_idbd_family',
      family: 'IdeaPocket IDBD family',
      prefixes: {'IDBD'},
      makerTokens: {'ideapocket', 'idea pocket', 'アイデアポケット'},
      reuseTokens: {'best', 'ベスト', '総集編', '作品集'},
      disposition: ScrapeProductFamilyDisposition.verifiedDerivedOnly,
    ),
    ScrapeProductFamilyRule(
      ruleId: 'known_kirakira_kibd_family',
      family: 'kira☆kira KIBD family',
      prefixes: {'KIBD'},
      makerTokens: {'kira☆kira', 'kirakira'},
      reuseTokens: {'best', 'ベスト', '総集編', '作品集'},
      // Live catalog evidence contains ordinary KIBD new releases as well as
      // BEST works. The prefix is therefore diagnostic only; the record must
      // supply its own exact series/title/lineage evidence.
      disposition: ScrapeProductFamilyDisposition.neutralMixed,
    ),
    ScrapeProductFamilyRule(
      ruleId: 'known_madonna_jusd_family',
      family: 'Madonna JUSD family',
      prefixes: {'JUSD'},
      makerTokens: {'madonna'},
      reuseTokens: {'best', 'ベスト', '総集編', '作品集'},
    ),
    ScrapeProductFamilyRule(
      ruleId: 'known_oppai_ppbd_family',
      family: 'OPPAI PPBD family',
      prefixes: {'PPBD'},
      makerTokens: {'oppai'},
      reuseTokens: {'best', 'ベスト', '総集編', '作品集'},
      // Live catalog evidence contains ordinary high-volume PPBD releases
      // as well as BEST collections. The prefix is therefore neutral; only
      // record-level collection or lineage evidence can classify the work.
      disposition: ScrapeProductFamilyDisposition.neutralMixed,
    ),
    ScrapeProductFamilyRule(
      ruleId: 'known_prestige_thn_family',
      family: 'Prestige THUNDERBOLT THN family',
      prefixes: {'THN'},
      makerTokens: {'prestige thunderbolt', 'prestige'},
      reuseTokens: {'best', 'ベスト', '総集編', '作品集'},
    ),
  ];

  static ScrapeProductFamilyMatch? match({
    required String code,
    String? manufacturer,
    String? label,
    String? series,
    String? title,
  }) {
    final prefix = _codePrefix(code);
    if (prefix == null) return null;
    final makerText = _normalize([manufacturer, label]);
    final productText = _normalize([series, title]);
    for (final rule in knownRules) {
      if (!rule.prefixes.contains(prefix)) continue;
      if (!rule.makerTokens.any(makerText.contains)) continue;
      final reuseToken = rule.reuseTokens
          .where((token) => _containsReuseToken(productText, token))
          .firstOrNull;
      return ScrapeProductFamilyMatch(
        ruleId: rule.ruleId,
        family: rule.family,
        disposition: rule.disposition,
        observedText: reuseToken == null
            ? '$prefix + maker metadata'
            : '$prefix + maker metadata + $reuseToken',
        hasCollectionMarker: reuseToken != null,
      );
    }
    return null;
  }

  static String? _codePrefix(String code) {
    final match = RegExp(r'^([A-Za-z0-9]+)-\d+').firstMatch(code.trim());
    return match?.group(1)?.toUpperCase();
  }

  static String _normalize(Iterable<String?> values) {
    return values
        .whereType<String>()
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .join(' ');
  }

  static bool _containsReuseToken(String text, String token) {
    if (token == 'best' || token == 'ベスト') {
      final safeBestPhrase = token == 'best'
          ? RegExp(r'best\s*(?:friend|partner|condition)', caseSensitive: false)
          : RegExp(r'ベスト\s*(?:フレンド|パートナー|コンディション)');
      if (safeBestPhrase.hasMatch(text)) {
        return false;
      }
    }
    if (RegExp(r'^[a-z0-9 ]+$', caseSensitive: false).hasMatch(token)) {
      return RegExp(
        '(^|[^a-z0-9])${RegExp.escape(token)}([^a-z0-9]|\$)',
        caseSensitive: false,
      ).hasMatch(text);
    }
    return text.contains(token);
  }
}
