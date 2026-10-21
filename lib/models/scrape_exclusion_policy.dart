import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'scrape_rules.dart';

/// The three policy outcomes are deliberately separate from transport and
/// parser failures.  A review decision is still a successful scrape.
enum ScrapeFinalAction { keep, keepReview, exclude }

/// Internal resolution state.  [needsEvidence] is deliberately separate from
/// a user-facing review decision: it means another enabled source should be
/// queried before the work is counted as REVIEW.
enum ScrapeResolutionState {
  decisiveKeep,
  decisiveExclude,
  needsEvidence,
  conflict,
  finalReview,
}

/// Diagnostic provenance classes. Unknown evidence is a neutral, keep-safe
/// result; it is not proof that a product reuses prior material.
enum ScrapeProvenanceClass {
  originalSolo,
  originalCostar,
  derivedBundle,
  derivedOmnibus,
  derivedExtract,
  derivedSplit,
  derivedReissue,
  derivedRemaster,
  derivedReedit,
  mixedOldNew,
  unknown,
}

enum ScrapeProvenanceVerdict { keep, exclude, keepUncertain }

enum ScrapeEvidenceLevel { none, review, strong }

enum ScrapeEvidenceStrength { weak, medium, strong }

enum ScrapeEvidencePolarity {
  supportsCompilation,
  supportsOriginalWork,
  neutral,
}

enum ScrapeEvidenceKind {
  explicitCompilation,
  omnibus,
  anthologyCollection,
  bestOfPriorWorks,
  completePriorWorks,
  includedPriorWorks,
  extractedFromPriorWork,
  splitFromPriorWork,
  packageEdition,
  reissue,
  remaster,
  reedit,
  mixedOldNew,
  independentSegments,
  genuineCoPerformance,
  possibleCoPerformance,
  bonusNewMaterial,
  priorWorkCollection,
  editedPresentation,
  viewpointSelection,
  highVolumePresentation,
  explicitOriginalWork,
  productFamilySuspicion,
  verifiedDerivedFamily,
}

enum ScrapePolicyOrigin { builtin, remote, user }

extension ScrapePolicyOriginCodec on ScrapePolicyOrigin {
  String get storageValue => switch (this) {
    ScrapePolicyOrigin.builtin => 'builtin',
    ScrapePolicyOrigin.remote => 'remote',
    ScrapePolicyOrigin.user => 'user',
  };
}

class ScrapeExactAllowRule {
  const ScrapeExactAllowRule({
    required this.code,
    this.source,
    this.includeSpecialEditions = false,
  });

  final String code;
  final String? source;
  final bool includeSpecialEditions;

  String get normalizedCode => normalizeScrapePolicyCode(code);

  bool matches(String candidateCode, {String? sourceId}) {
    final expectedSource = source?.trim().toLowerCase();
    if (expectedSource != null &&
        expectedSource.isNotEmpty &&
        expectedSource != sourceId?.trim().toLowerCase()) {
      return false;
    }
    return manualRuleMatches(normalizedCode, candidateCode);
  }

  Map<String, Object?> toJson() => {
    'code': code,
    if (source != null && source!.trim().isNotEmpty) 'source': source,
    'includeSpecialEditions': includeSpecialEditions,
  };

  factory ScrapeExactAllowRule.fromJson(Object? source) {
    if (source is! Map) {
      throw const FormatException('Exact allow rule must be an object.');
    }
    final map = Map<String, Object?>.from(source);
    final code = map['code']?.toString().trim() ?? '';
    if (code.isEmpty || code.length > 80) {
      throw const FormatException('Exact allow rule has an invalid code.');
    }
    final sourceId = map['source']?.toString().trim();
    return ScrapeExactAllowRule(
      code: code,
      source: sourceId == null || sourceId.isEmpty ? null : sourceId,
      includeSpecialEditions: map['includeSpecialEditions'] == true,
    );
  }
}

class ScrapeExactDenyRule {
  const ScrapeExactDenyRule({required this.code, this.source});

  final String code;
  final String? source;

  String get normalizedCode => normalizeScrapePolicyCode(code);

  bool matches(String candidateCode, {String? sourceId}) {
    final expectedSource = source?.trim().toLowerCase();
    if (expectedSource != null &&
        expectedSource.isNotEmpty &&
        expectedSource != sourceId?.trim().toLowerCase()) {
      return false;
    }
    return manualRuleMatches(normalizedCode, candidateCode);
  }

  Map<String, Object?> toJson() => {
    'code': code,
    if (source != null && source!.trim().isNotEmpty) 'source': source,
  };

  factory ScrapeExactDenyRule.fromJson(Object? source) {
    if (source is! Map) {
      throw const FormatException('Exact deny rule must be an object.');
    }
    final map = Map<String, Object?>.from(source);
    final code = map['code']?.toString().trim() ?? '';
    if (code.isEmpty || code.length > 80) {
      throw const FormatException('Exact deny rule has an invalid code.');
    }
    final sourceId = map['source']?.toString().trim();
    return ScrapeExactDenyRule(
      code: code,
      source: sourceId == null || sourceId.isEmpty ? null : sourceId,
    );
  }
}

/// Immutable policy materialized when a job is created.
class ScrapePolicySnapshot {
  ScrapePolicySnapshot._({
    required this.schemaVersion,
    required this.policyVersion,
    required this.rulesVersion,
    required this.classifierVersion,
    required this.rulesBundleDigest,
    required this.snapshotDigest,
    required this.autoExcludeDerivedWorks,
    required List<ScrapeExactAllowRule> exactAllows,
    required List<ScrapeExactDenyRule> exactDenies,
  }) : exactAllows = List.unmodifiable(exactAllows),
       exactDenies = List.unmodifiable(exactDenies);

  static const currentSchemaVersion = 4;
  static const currentPolicyVersion = 'provenance-v4';
  static const currentClassifierVersion = 'semantic-v4';

  final int schemaVersion;
  final String policyVersion;
  final String rulesVersion;
  final String classifierVersion;
  final String rulesBundleDigest;
  final String snapshotDigest;
  final bool autoExcludeDerivedWorks;
  final List<ScrapeExactAllowRule> exactAllows;
  final List<ScrapeExactDenyRule> exactDenies;

  static ScrapePolicySnapshot current({
    required ScrapeRules rules,
    required List<ScrapeExactAllowRule> exactAllows,
    bool autoExcludeDerivedWorks = true,
    List<ScrapeExactDenyRule> exactDenies = const [],
  }) {
    final allowList = exactAllows
        .where((rule) => rule.normalizedCode.isNotEmpty)
        .toList(growable: false);
    final denyList = exactDenies
        .where((rule) => rule.normalizedCode.isNotEmpty)
        .toList(growable: false);
    final bundle = {
      'rules': rules.toJson(),
      'classifierVersion': currentClassifierVersion,
    };
    final bundleDigest = _digest(bundle);
    final payload = {
      'schemaVersion': currentSchemaVersion,
      'policyVersion': currentPolicyVersion,
      'rulesVersion': rules.rulesVersion,
      'classifierVersion': currentClassifierVersion,
      'rulesBundleDigest': bundleDigest,
      'autoExcludeDerivedWorks': autoExcludeDerivedWorks,
      'exactAllows': allowList.map((item) => item.toJson()).toList(),
      'exactDenies': denyList.map((item) => item.toJson()).toList(),
    };
    return ScrapePolicySnapshot._(
      schemaVersion: currentSchemaVersion,
      policyVersion: currentPolicyVersion,
      rulesVersion: rules.rulesVersion,
      classifierVersion: currentClassifierVersion,
      rulesBundleDigest: bundleDigest,
      snapshotDigest: _digest(payload),
      autoExcludeDerivedWorks: autoExcludeDerivedWorks,
      exactAllows: allowList,
      exactDenies: denyList,
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'policyVersion': policyVersion,
    'rulesVersion': rulesVersion,
    'classifierVersion': classifierVersion,
    'rulesBundleDigest': rulesBundleDigest,
    'snapshotDigest': snapshotDigest,
    'autoExcludeDerivedWorks': autoExcludeDerivedWorks,
    'exactAllows': exactAllows.map((item) => item.toJson()).toList(),
    'exactDenies': exactDenies.map((item) => item.toJson()).toList(),
  };

  String encode() => jsonEncode(toJson());

  factory ScrapePolicySnapshot.fromEncoded({
    required String? encoded,
    required List<ScrapeExactAllowRule> exactAllows,
    bool autoExcludeDerivedWorks = true,
    List<ScrapeExactDenyRule> exactDenies = const [],
  }) {
    ScrapePolicySnapshot fallback() => ScrapePolicySnapshot.current(
      rules: ScrapeRules.builtin,
      exactAllows: exactAllows,
      autoExcludeDerivedWorks: autoExcludeDerivedWorks,
      exactDenies: exactDenies,
    );

    if (encoded == null || encoded.trim().isEmpty) {
      return fallback();
    }
    try {
      final raw = jsonDecode(encoded);
      if (raw is! Map) throw const FormatException('Invalid policy snapshot.');
      final map = Map<String, Object?>.from(raw);
      final schema = _int(map['schemaVersion']);
      final version = map['policyVersion']?.toString();
      if (schema != currentSchemaVersion || version != currentPolicyVersion) {
        return fallback();
      }
      // provenance-v3 snapshots may carry excludedPrefixes and managedFamilies.
      // They are deliberately never read here; only current exact overrides
      // can enter the active policy snapshot.
      final automaticExclusion = map['autoExcludeDerivedWorks'] is bool
          ? map['autoExcludeDerivedWorks'] as bool
          : autoExcludeDerivedWorks;
      final allows = <ScrapeExactAllowRule>[];
      if (map['exactAllows'] is List) {
        for (final item in map['exactAllows'] as List) {
          try {
            allows.add(ScrapeExactAllowRule.fromJson(item));
          } on FormatException {
            // See the managed-family compatibility comment above.
          }
        }
      }
      final denies = <ScrapeExactDenyRule>[];
      if (map['exactDenies'] is List) {
        for (final item in map['exactDenies'] as List) {
          try {
            denies.add(ScrapeExactDenyRule.fromJson(item));
          } on FormatException {
            // Ignore malformed optional entries while preserving the job.
          }
        }
      }
      final rulesVersion =
          map['rulesVersion']?.toString() ?? ScrapeRules.builtin.rulesVersion;
      final classifierVersion =
          map['classifierVersion']?.toString() ?? currentClassifierVersion;
      final rulesBundleDigest = map['rulesBundleDigest']?.toString() ?? '';
      final snapshotDigest = map['snapshotDigest']?.toString() ?? '';
      if (classifierVersion != currentClassifierVersion ||
          rulesBundleDigest.isEmpty ||
          snapshotDigest.isEmpty) {
        return fallback();
      }
      final snapshotPayload = {
        'schemaVersion': schema,
        'policyVersion': version,
        'rulesVersion': rulesVersion,
        'classifierVersion': classifierVersion,
        'rulesBundleDigest': rulesBundleDigest,
        'autoExcludeDerivedWorks': automaticExclusion,
        'exactAllows': allows.map((item) => item.toJson()).toList(),
        'exactDenies': denies.map((item) => item.toJson()).toList(),
      };
      if (_digest(snapshotPayload) != snapshotDigest) {
        return fallback();
      }
      final snapshot = ScrapePolicySnapshot._(
        schemaVersion: schema,
        policyVersion: version!,
        rulesVersion: rulesVersion,
        classifierVersion: classifierVersion,
        rulesBundleDigest: rulesBundleDigest,
        snapshotDigest: snapshotDigest,
        autoExcludeDerivedWorks: automaticExclusion,
        exactAllows: allows,
        exactDenies: denies,
      );
      return snapshot;
    } on Object {
      return fallback();
    }
  }
}

String normalizeScrapePolicyCode(String value) {
  return value.replaceAll(RegExp(r'\s+'), '').trim().toUpperCase();
}

/// Matches a manual work rule against a scraped work-code surface.
///
/// Manual rules support either a complete work code or the family prefix at
/// the start of a structured work code.  The existing work-code grammar uses
/// a hyphen between that prefix and its numeric code, so the hyphen is the
/// only prefix boundary accepted here.  This intentionally does not call the
/// legacy work-code canonicalizer or infer any cross-source identity alias.
bool manualRuleMatches(String rule, String workCode) {
  final normalizedRule = normalizeScrapePolicyCode(rule);
  final normalizedWorkCode = normalizeScrapePolicyCode(workCode);
  if (normalizedRule.isEmpty || normalizedWorkCode.isEmpty) {
    return false;
  }
  if (normalizedRule == normalizedWorkCode) {
    return true;
  }

  if (!RegExp(r'^[A-Z0-9]+$').hasMatch(normalizedRule)) {
    return false;
  }
  final boundary = '$normalizedRule-';
  if (!normalizedWorkCode.startsWith(boundary) ||
      normalizedWorkCode.length == boundary.length) {
    return false;
  }

  final nextCodeUnit = normalizedWorkCode.codeUnitAt(boundary.length);
  return nextCodeUnit >= 0x30 && nextCodeUnit <= 0x39;
}

String _digest(Object value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();

int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
