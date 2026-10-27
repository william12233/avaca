import '../../models/scrape_work_category.dart';
import '../../models/scrape_exclusion_policy.dart';
import '../../models/scrape_source_settings.dart';
import 'scrape_models.dart';

enum ScrapeCategoryEvidenceState { matched, knownOther, unknown }

final class ScrapeCategoryClassification {
  ScrapeCategoryClassification({
    required Set<ScrapeWorkCategory> categories,
    required List<String> observedTokens,
    required Set<ScrapeSourceId> sources,
  }) : categories = Set.unmodifiable(categories),
       observedTokens = List.unmodifiable(observedTokens),
       sources = Set.unmodifiable(sources);

  final Set<ScrapeWorkCategory> categories;
  final List<String> observedTokens;
  final Set<ScrapeSourceId> sources;

  ScrapeCategoryEvidenceState stateFor(Iterable<ScrapeWorkCategory> selected) {
    final selectedSet = selected.toSet();
    if (selectedSet.isEmpty) return ScrapeCategoryEvidenceState.matched;
    if (categories.any(selectedSet.contains)) {
      return ScrapeCategoryEvidenceState.matched;
    }
    return categories.isEmpty
        ? ScrapeCategoryEvidenceState.unknown
        : ScrapeCategoryEvidenceState.knownOther;
  }
}

final class ScrapeCategoryDecision {
  const ScrapeCategoryDecision({
    required this.finalAction,
    required this.evidenceState,
    required this.reasonCodes,
    required this.matchedCategories,
    required this.observedCategories,
    required this.evidenceSources,
  });

  final ScrapeFinalAction finalAction;
  final ScrapeCategoryEvidenceState evidenceState;
  final List<String> reasonCodes;
  final List<ScrapeWorkCategory> matchedCategories;
  final List<ScrapeWorkCategory> observedCategories;
  final List<ScrapeSourceId> evidenceSources;

  bool get reviewRequired => finalAction == ScrapeFinalAction.keepReview;

  String get reason => reasonCodes.join(',');

  Map<String, Object?> toMetadata() => {
    'categoryPolicyVersion': ScrapeCategoryClassifier.version,
    'categoryEvidenceState': evidenceState.name,
    'categoryReasons': reasonCodes,
    'matchedCategories': matchedCategories
        .map((category) => category.storageValue)
        .toList(growable: false),
    'observedCategories': observedCategories
        .map((category) => category.storageValue)
        .toList(growable: false),
    'categoryEvidenceSources': evidenceSources
        .map((source) => source.storageValue)
        .toList(growable: false),
  };
}

/// Maps source-declared tags and metadata to the small, stable set of user
/// facing scrape categories. It deliberately does not infer categories from
/// performer counts, work-code prefixes, or free-form titles.
final class ScrapeCategoryClassifier {
  const ScrapeCategoryClassifier._();

  static const version = 'category-v1';

  static const catalogSources = <ScrapeSourceId>{
    ScrapeSourceId.avbase,
    ScrapeSourceId.avwiki,
  };

  static const detailSources = <ScrapeSourceId>{
    ScrapeSourceId.javbus,
    ScrapeSourceId.avbase,
    ScrapeSourceId.avwiki,
  };

  static const _aliases = <ScrapeWorkCategory, List<String>>{
    ScrapeWorkCategory.single: ['単体作品', '單體作品', '単体', '單體', 'solo', 'single'],
    ScrapeWorkCategory.multi: [
      '3p',
      '4p',
      '3p・4p',
      '3p/4p',
      '複数',
      '複数人',
      '多人数',
      '多人',
      '共演',
      'multi',
      'co-performance',
    ],
    ScrapeWorkCategory.photo: [
      '写真',
      '写真集',
      '寫真',
      '寫真集',
      'photo',
      'photobook',
      'グラビア',
    ],
    ScrapeWorkCategory.retrospective: [
      'best',
      'ベスト',
      'ベスト・総集編',
      '総集編',
      '回顧',
      'collection',
      'compilation',
      'anthology',
      '作品集',
    ],
    ScrapeWorkCategory.vr: ['vr', 'vr専用', 'vr作品', 'ハイクオリティvr'],
  };

  static ScrapeCategoryClassification classify({
    Iterable<ScrapeCatalogWorkEvidence> catalogEvidence = const [],
    Iterable<ScrapeWorkDetails> details = const [],
  }) {
    final categories = <ScrapeWorkCategory>{};
    final observedTokens = <String>[];
    final observedTokenKeys = <String>{};
    final sources = <ScrapeSourceId>{};

    void inspect(ScrapeSourceId source, Iterable<String> values) {
      final tokens = values
          .map(_cleanToken)
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
      if (tokens.isEmpty) return;
      sources.add(source);
      for (final token in tokens) {
        final key = _tokenKey(token);
        if (key.isNotEmpty && observedTokenKeys.add(key)) {
          observedTokens.add(token);
        }
        for (final entry in _aliases.entries) {
          if (_matchesCategory(entry.key, token)) {
            categories.add(entry.key);
          }
        }
      }
    }

    for (final evidence in catalogEvidence) {
      inspect(evidence.source, [
        ...evidence.tags,
        ...evidence.provenanceHints,
        ?evidence.series,
        ?evidence.label,
      ]);
    }

    for (final detail in details) {
      final facts = detail.provenanceFacts;
      inspect(detail.source, [
        ...detail.genres,
        ...facts.genres,
        ...facts.tags,
        ?detail.series,
        ?detail.publisher,
      ]);
      for (final evidence in detail.catalogEvidence) {
        inspect(evidence.source, [
          ...evidence.tags,
          ...evidence.provenanceHints,
          ?evidence.series,
          ?evidence.label,
        ]);
      }
    }

    return ScrapeCategoryClassification(
      categories: categories,
      observedTokens: observedTokens,
      sources: sources,
    );
  }

  static ScrapeCategoryDecision decide({
    required Iterable<ScrapeWorkCategory> selectedCategories,
    required ScrapeCategoryClassification classification,
  }) {
    final selected = selectedCategories.toSet();
    if (selected.isEmpty) {
      return ScrapeCategoryDecision(
        finalAction: ScrapeFinalAction.keep,
        evidenceState: ScrapeCategoryEvidenceState.matched,
        reasonCodes: const ['category_filter_disabled'],
        matchedCategories: const [],
        observedCategories: classification.categories.toList(growable: false),
        evidenceSources: classification.sources.toList(growable: false),
      );
    }

    final matched = classification.categories
        .where(selected.contains)
        .toList(growable: false);
    final state = classification.stateFor(selected);
    final action = switch (state) {
      ScrapeCategoryEvidenceState.matched => ScrapeFinalAction.keep,
      ScrapeCategoryEvidenceState.knownOther => ScrapeFinalAction.exclude,
      ScrapeCategoryEvidenceState.unknown => ScrapeFinalAction.keepReview,
    };
    final reason = switch (state) {
      ScrapeCategoryEvidenceState.matched => 'category_match',
      ScrapeCategoryEvidenceState.knownOther => 'category_not_selected',
      ScrapeCategoryEvidenceState.unknown => 'category_unresolved',
    };
    return ScrapeCategoryDecision(
      finalAction: action,
      evidenceState: state,
      reasonCodes: [reason],
      matchedCategories: matched,
      observedCategories: classification.categories.toList(growable: false),
      evidenceSources: classification.sources.toList(growable: false),
    );
  }

  static bool _matchesCategory(ScrapeWorkCategory category, String raw) {
    final value = _tokenKey(raw);
    if (value.isEmpty) return false;
    for (final alias in _aliases[category]!) {
      final aliasKey = _tokenKey(alias);
      if (aliasKey.isEmpty) continue;
      if (category == ScrapeWorkCategory.vr && aliasKey == 'vr') {
        if (RegExp(
          r'(^|[^a-z0-9])vr([^a-z0-9]|$)',
          caseSensitive: false,
        ).hasMatch(raw)) {
          return true;
        }
        continue;
      }
      if (value == aliasKey || value.contains(aliasKey)) return true;
    }
    return false;
  }

  static String _cleanToken(String value) => value.trim();

  static String _tokenKey(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('　', '')
        .replaceAll(RegExp(r'[\s_・·／/|,，、:：()（）\[\]【】]+'), '');
  }
}
