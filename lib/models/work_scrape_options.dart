import 'dart:convert';

import 'scrape_exclusion_policy.dart';

class WorkScrapeOptions {
  const WorkScrapeOptions({
    this.syncDetails = true,
    this.replaceActressImage = false,
    this.fillMissingOnly = true,
    this.retryWorkCodes = const [],
    this.scrapeAliases = false,
    this.autoExcludeDerivedWorks = true,
    this.exactAllows = const [],
    this.exactDenies = const [],
  });

  final bool syncDetails;
  final bool replaceActressImage;
  final bool fillMissingOnly;
  final List<String> retryWorkCodes;
  final bool scrapeAliases;
  final bool autoExcludeDerivedWorks;
  final List<ScrapeExactAllowRule> exactAllows;
  final List<ScrapeExactDenyRule> exactDenies;

  WorkScrapeOptions copyWith({
    bool? syncDetails,
    bool? replaceActressImage,
    bool? fillMissingOnly,
    List<String>? retryWorkCodes,
    bool? scrapeAliases,
    bool? autoExcludeDerivedWorks,
    List<ScrapeExactAllowRule>? exactAllows,
    List<ScrapeExactDenyRule>? exactDenies,
  }) => WorkScrapeOptions(
    syncDetails: syncDetails ?? this.syncDetails,
    replaceActressImage: replaceActressImage ?? this.replaceActressImage,
    fillMissingOnly: fillMissingOnly ?? this.fillMissingOnly,
    retryWorkCodes: retryWorkCodes ?? this.retryWorkCodes,
    scrapeAliases: scrapeAliases ?? this.scrapeAliases,
    autoExcludeDerivedWorks:
        autoExcludeDerivedWorks ?? this.autoExcludeDerivedWorks,
    exactAllows: exactAllows ?? this.exactAllows,
    exactDenies: exactDenies ?? this.exactDenies,
  );

  String encode() {
    return jsonEncode({
      'syncDetails': syncDetails,
      'replaceActressImage': replaceActressImage,
      'fillMissingOnly': fillMissingOnly,
      'retryWorkCodes': retryWorkCodes,
      'scrapeAliases': scrapeAliases,
      'autoExcludeDerivedWorks': autoExcludeDerivedWorks,
      'exactAllows': exactAllows.map((item) => item.toJson()).toList(),
      'exactDenies': exactDenies.map((item) => item.toJson()).toList(),
    });
  }

  static WorkScrapeOptions decode(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const WorkScrapeOptions();
    }

    try {
      final json = jsonDecode(value);
      if (json is! Map<String, dynamic>) {
        return const WorkScrapeOptions();
      }
      // Legacy exclusion keys are intentionally ignored. Unknown JSON keys
      // remain readable so an older settings record can be rewritten without
      // allowing prefix or family semantics back into the active model.
      final retryCodes = json['retryWorkCodes'];
      final exactAllows = <ScrapeExactAllowRule>[];
      if (json['exactAllows'] is List) {
        for (final item in json['exactAllows'] as List) {
          try {
            exactAllows.add(ScrapeExactAllowRule.fromJson(item));
          } on FormatException {
            // Ignore malformed optional entries while preserving old settings.
          }
        }
      }
      final exactDenies = <ScrapeExactDenyRule>[];
      if (json['exactDenies'] is List) {
        for (final item in json['exactDenies'] as List) {
          try {
            exactDenies.add(ScrapeExactDenyRule.fromJson(item));
          } on FormatException {
            // Ignore malformed optional entries while preserving old settings.
          }
        }
      }
      return WorkScrapeOptions(
        syncDetails: json['syncDetails'] is bool
            ? json['syncDetails'] as bool
            : true,
        replaceActressImage: json['replaceActressImage'] is bool
            ? json['replaceActressImage'] as bool
            : false,
        fillMissingOnly: json['fillMissingOnly'] is bool
            ? json['fillMissingOnly'] as bool
            : true,
        retryWorkCodes: retryCodes is List
            ? retryCodes
                  .whereType<String>()
                  .map((value) => value.trim().toUpperCase())
                  .where((value) => value.isNotEmpty)
                  .toSet()
                  .toList(growable: false)
            : const [],
        scrapeAliases: json['scrapeAliases'] is bool
            ? json['scrapeAliases'] as bool
            : false,
        autoExcludeDerivedWorks: json['autoExcludeDerivedWorks'] is bool
            ? json['autoExcludeDerivedWorks'] as bool
            : true,
        exactAllows: List.unmodifiable(exactAllows),
        exactDenies: List.unmodifiable(exactDenies),
      );
    } on FormatException {
      return const WorkScrapeOptions();
    }
  }
}
