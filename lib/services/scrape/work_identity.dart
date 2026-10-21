// Identity rules used only by the new works scrape pipeline.
//
// This file intentionally does not depend on work_code_canonicalizer.dart.
// The legacy canonicalizer contains alias reconciliation that is still needed
// by a few presentation/image consumers, but it must not decide whether two
// newly scraped works are the same work.

import '../../models/scrape_source_settings.dart';
import 'scrape_models.dart';

final class ScrapeTitleIdentity {
  const ScrapeTitleIdentity({
    required this.key,
    required this.isUsable,
    required this.isSpecialEdition,
  });

  final String key;
  final bool isUsable;
  final bool isSpecialEdition;
}

/// The conservative work identity used by the new multi-source scrape path.
///
/// This is intentionally separate from work_code_canonicalizer.dart. A
/// source image token can look code-like (for example ssis00875 or
/// h_346rebd00975), but it is not a work code and must never enter this
/// parser.
final class ScrapeWorkCodeIdentity {
  const ScrapeWorkCodeIdentity({
    required this.surface,
    required this.key,
    required this.displayCode,
    required this.isStructured,
    this.isSpecialEdition = false,
  });

  final String surface;
  final String key;
  final String displayCode;
  final bool isStructured;
  final bool isSpecialEdition;
}

/// Optional source-declared context for edition and cross-platform identity
/// resolution. It is intentionally not a generic prefix/number grammar.
final class ScrapeWorkIdentityEvidence {
  const ScrapeWorkIdentityEvidence({
    this.canonicalCode,
    this.makerCode,
    this.manufacturer,
    this.label,
    this.series,
    this.aliases = const [],
    this.platformIds = const {},
  });

  final String? canonicalCode;
  final String? makerCode;
  final String? manufacturer;
  final String? label;
  final String? series;
  final List<String> aliases;
  final Map<String, String> platformIds;

  Iterable<String> get declaredCodes sync* {
    for (final value in <String?>[canonicalCode, makerCode]) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) yield trimmed;
    }
    yield* aliases
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty);
    yield* platformIds.values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty);
  }
}

const _specialEditionMarkers = <String>['【特典版】', '[特典版]'];

ScrapeTitleIdentity scrapeTitleIdentity(String? title) {
  var value = _normalizeTitleSurface(title);
  var isSpecialEdition = false;

  for (final marker in _specialEditionMarkers) {
    if (value.startsWith(marker)) {
      value = value.substring(marker.length).trim();
      isSpecialEdition = true;
      break;
    }
    if (value.endsWith(marker)) {
      value = value.substring(0, value.length - marker.length).trim();
      isSpecialEdition = true;
      break;
    }
  }

  return ScrapeTitleIdentity(
    key: value.toLowerCase(),
    isUsable: value.isNotEmpty,
    isSpecialEdition: isSpecialEdition,
  );
}

/// Normalizes only code surface differences for new cross-source matching.
///
/// In particular, this deliberately preserves numeric prefixes, number
/// padding, and separator presence. It must not turn a legacy alias such as
/// `1STZY00017` into `STZY-017`.
String? normalizeScrapeWorkCodeSurface(String? raw) {
  final value = _normalizeCodeSurface(raw).replaceAll(RegExp(r'\s+'), '');
  if (value.isEmpty) {
    return null;
  }
  return value.toUpperCase();
}

/// Parses only the safe work-code forms supported by the current scrape
/// contract. Numeric padding is preserved for identity comparison. The only
/// source-specific padding rule is the observed START separatorless
/// representation (START00023 == START-023). It is deliberately not a
/// global zero-trimming rule, so SIVR00303 remains different from SIVR-303.
ScrapeWorkCodeIdentity? parseScrapeWorkCodeIdentity(
  String? raw, {
  ScrapeWorkIdentityEvidence? evidence,
}) {
  final surface = normalizeScrapeWorkCodeSurface(raw);
  if (surface == null) {
    return null;
  }

  // V/T/VT/VT2/EC and BD are edition markers only inside the explicitly
  // supported SOD product-line grammar. A code such as FOO-123-EC remains a
  // distinct surface; no global suffix or prefix rule changes its identity.
  final edition = _scopedSodEdition(surface, evidence);
  final baseSurface = edition?.baseSurface ?? surface;
  final parsed = _parseScrapeWorkCodeIdentitySurface(baseSurface);
  if (parsed.isStructured) {
    final scoped = _scopedSodIdentity(
      parsed,
      evidence,
      isSpecialEdition: edition != null,
    );
    return ScrapeWorkCodeIdentity(
      surface: surface,
      key: scoped?.key ?? parsed.key,
      displayCode: scoped?.displayCode ?? parsed.displayCode,
      isStructured: true,
      isSpecialEdition: edition != null,
    );
  }
  return parsed;
}

ScrapeWorkCodeIdentity? _scopedSodIdentity(
  ScrapeWorkCodeIdentity identity,
  ScrapeWorkIdentityEvidence? evidence, {
  required bool isSpecialEdition,
}) {
  if (!_hasSodContext(evidence)) return null;
  final match = RegExp(
    r'^(START|STARS)-(\d+)$',
  ).firstMatch(identity.displayCode);
  if (match == null) return null;
  final prefix = match.group(1)!;
  final digits = match.group(2)!.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  return ScrapeWorkCodeIdentity(
    surface: identity.surface,
    key: '${prefix.toLowerCase()}$digits',
    displayCode: '$prefix-${_formatSodDigits(digits)}',
    isStructured: true,
    isSpecialEdition: isSpecialEdition,
  );
}

String _formatSodDigits(String digits) {
  final normalized = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  return normalized.padLeft(3, '0');
}

({String baseSurface, bool isSpecial})? _scopedSodEdition(
  String surface,
  ScrapeWorkIdentityEvidence? evidence,
) {
  if (!_hasSodContext(evidence)) return null;
  final terminalEdition = RegExp(
    r'^(.+?)-?(VT2|VT|V|T)(?:-?EC)?$',
  ).firstMatch(surface);
  if (terminalEdition != null && _isScopedSodBase(terminalEdition.group(1)!)) {
    return (baseSurface: terminalEdition.group(1)!, isSpecial: true);
  }
  final ecEdition = RegExp(r'^(.+?)-EC$').firstMatch(surface);
  if (ecEdition != null && _isScopedSodBase(ecEdition.group(1)!)) {
    return (baseSurface: ecEdition.group(1)!, isSpecial: true);
  }

  // STARSBD-859 is accepted only when the same source also identifies the
  // product line as SOD. Without that evidence it remains STARSBD-859.
  final bdVariant = RegExp(r'^(STARS)BD-(\d+)$').firstMatch(surface);
  if (bdVariant != null && _hasSodContext(evidence)) {
    return (
      baseSurface: '${bdVariant.group(1)}-${bdVariant.group(2)}',
      isSpecial: true,
    );
  }
  return null;
}

bool _isScopedSodBase(String surface) {
  return RegExp(r'^(START|STARS)-\d+$').hasMatch(surface);
}

bool _hasSodContext(ScrapeWorkIdentityEvidence? evidence) {
  if (evidence == null) return false;
  final text = [
    evidence.manufacturer,
    evidence.label,
    evidence.series,
  ].whereType<String>().join(' ').toLowerCase();
  return RegExp(r'\bsod\b|sodクリエイト|sod create').hasMatch(text);
}

ScrapeWorkCodeIdentity _parseScrapeWorkCodeIdentitySurface(String surface) {
  final separated = RegExp(r'^([A-Z0-9][A-Z0-9]*)-(\d+)$').firstMatch(surface);
  if (separated != null) {
    final prefix = separated.group(1)!;
    final digits = separated.group(2)!;
    return ScrapeWorkCodeIdentity(
      surface: surface,
      key: '${prefix.toLowerCase()}$digits',
      displayCode: '$prefix-$digits',
      isStructured: true,
    );
  }

  // A separatorless form is only accepted when the prefix is alphabetic and
  // the numeric part is long enough to be a real product number. This keeps
  // short opaque values such as AB12 and compound values such as
  // FC2-PPV_123-999 out of the structured grammar.
  final separatorless = RegExp(r'^([A-Z]{2,})(\d+)$').firstMatch(surface);
  if (separatorless != null && separatorless.group(2)!.length >= 3) {
    final prefix = separatorless.group(1)!;
    final digits = separatorless.group(2)!;
    if (prefix == 'START' && digits.length == 5 && digits.startsWith('00')) {
      final startDigits = digits.substring(2);
      return ScrapeWorkCodeIdentity(
        surface: surface,
        key: 'start$startDigits',
        displayCode: 'START-$startDigits',
        isStructured: true,
      );
    }
    return ScrapeWorkCodeIdentity(
      surface: surface,
      key: '${prefix.toLowerCase()}$digits',
      displayCode: '$prefix-$digits',
      isStructured: true,
    );
  }

  return ScrapeWorkCodeIdentity(
    surface: surface,
    key: 'opaque:${surface.toLowerCase()}',
    displayCode: surface,
    isStructured: false,
  );
}

String? scrapeWorkCodeIdentityKey(
  String? raw, {
  ScrapeWorkIdentityEvidence? evidence,
}) => parseScrapeWorkCodeIdentity(raw, evidence: evidence)?.key;

bool scrapeWorkCodeIsSpecialEdition(
  String? raw, {
  ScrapeWorkIdentityEvidence? evidence,
}) =>
    parseScrapeWorkCodeIdentity(raw, evidence: evidence)?.isSpecialEdition ??
    false;

bool scrapeWorkCodesEqual(
  String? left,
  String? right, {
  ScrapeWorkIdentityEvidence? evidence,
}) {
  final leftKey = parseScrapeWorkCodeIdentity(left, evidence: evidence)?.key;
  final rightKey = parseScrapeWorkCodeIdentity(right, evidence: evidence)?.key;
  return leftKey != null && leftKey == rightKey;
}

/// Resolves one summary to a grouping key for the aggregate pipeline.
///
/// A typed external identity may explicitly bridge a maker code and platform
/// aliases. The START/107START/1start bridge is therefore applied only when
/// those aliases are declared on the same source record; the bare code parser
/// never performs that collapse.
String? scrapeWorkIdentityKeyForSummary(ScrapeWorkSummary summary) {
  return scrapeWorkResolvedIdentityKey(
    rawCode: summary.rawCode ?? summary.code,
    externalIdentity: summary.externalIdentity,
    identityEvidence: scrapeWorkIdentityEvidenceForSummary(summary),
    fallback: 'uri:${summary.source.storageValue}:${summary.detailUri}',
  );
}

String? scrapeWorkIdentityKeyForDetails(ScrapeWorkDetails details) {
  return scrapeWorkResolvedIdentityKey(
    rawCode: details.rawCode ?? details.code,
    externalIdentity: details.externalIdentity,
    identityEvidence: scrapeWorkIdentityEvidenceForDetails(details),
    fallback:
        'uri:${details.source.storageValue}:${details.sourceUri ?? details.code}',
  );
}

String? scrapeWorkResolvedIdentityKey({
  required String? rawCode,
  ScrapeExternalWorkIdentity? externalIdentity,
  ScrapeWorkIdentityEvidence? identityEvidence,
  required String fallback,
}) {
  final evidence = identityEvidence ?? _identityEvidence(externalIdentity);
  final bridgeKey = _declaredScopedBridgeKey(
    externalIdentity,
    evidence: evidence,
  );
  if (bridgeKey != null) return 'code:$bridgeKey';
  final identity = parseScrapeWorkCodeIdentity(rawCode, evidence: evidence);
  if (identity != null) return 'code:${identity.key}';
  final canonical =
      externalIdentity?.canonicalCode ?? externalIdentity?.makerCode;
  final canonicalIdentity = parseScrapeWorkCodeIdentity(
    canonical,
    evidence: evidence,
  );
  if (canonicalIdentity != null) return 'code:${canonicalIdentity.key}';
  return fallback;
}

ScrapeWorkIdentityEvidence? _identityEvidence(
  ScrapeExternalWorkIdentity? identity,
) {
  if (identity == null || identity.isEmpty) return null;
  return ScrapeWorkIdentityEvidence(
    canonicalCode: identity.canonicalCode,
    makerCode: identity.makerCode,
    manufacturer: identity.manufacturer,
    label: identity.label,
    series: identity.series,
    aliases: identity.aliases,
    platformIds: identity.platformIds,
  );
}

ScrapeWorkIdentityEvidence? scrapeWorkIdentityEvidenceForSummary(
  ScrapeWorkSummary summary,
) {
  return _identityEvidenceForSource(
    identity: summary.externalIdentity,
    rawCode: summary.rawCode ?? summary.code,
    source: summary.source,
    catalogEvidence: summary.catalogEvidence,
  );
}

ScrapeWorkIdentityEvidence? scrapeWorkIdentityEvidenceForDetails(
  ScrapeWorkDetails details,
) {
  return _identityEvidenceForSource(
    identity: details.externalIdentity,
    rawCode: details.rawCode ?? details.code,
    source: details.source,
    manufacturer: details.studio,
    label: details.publisher,
    series: details.series,
    catalogEvidence: details.catalogEvidence,
  );
}

ScrapeWorkIdentityEvidence? _identityEvidenceForSource({
  required ScrapeExternalWorkIdentity? identity,
  required String? rawCode,
  required ScrapeSourceId source,
  String? manufacturer,
  String? label,
  String? series,
  Iterable<ScrapeCatalogWorkEvidence> catalogEvidence = const [],
}) {
  final base = _identityEvidence(identity);
  final sourceCatalog = catalogEvidence.where(
    (evidence) => evidence.source == source,
  );

  String? firstValue(Iterable<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  final resolvedManufacturer = firstValue([
    base?.manufacturer,
    manufacturer,
    ...sourceCatalog.map((evidence) => evidence.manufacturer),
  ]);
  final resolvedLabel = firstValue([
    base?.label,
    label,
    ...sourceCatalog.map((evidence) => evidence.label),
  ]);
  final resolvedSeries = firstValue([
    base?.series,
    series,
    ...sourceCatalog.map((evidence) => evidence.series),
  ]);

  var effectiveManufacturer = resolvedManufacturer;
  if (source == ScrapeSourceId.javbus &&
      _looksLikeSodCode(rawCode) &&
      effectiveManufacturer == null &&
      resolvedLabel == null &&
      resolvedSeries == null) {
    // JavBus often exposes only the SOD-shaped code. This is a source-local
    // identity hint, not a global prefix rule and not product classification.
    effectiveManufacturer = 'SOD';
  }

  if (base == null &&
      effectiveManufacturer == null &&
      resolvedLabel == null &&
      resolvedSeries == null) {
    return null;
  }

  if (base != null &&
      effectiveManufacturer == base.manufacturer &&
      resolvedLabel == base.label &&
      resolvedSeries == base.series) {
    return base;
  }

  return ScrapeWorkIdentityEvidence(
    canonicalCode: base?.canonicalCode,
    makerCode: base?.makerCode,
    manufacturer: effectiveManufacturer,
    label: resolvedLabel,
    series: resolvedSeries,
    aliases: base?.aliases ?? const [],
    platformIds: base?.platformIds ?? const {},
  );
}

bool _looksLikeSodCode(String? raw) {
  final surface = normalizeScrapeWorkCodeSurface(raw);
  return surface != null &&
      RegExp(r'^(?:START|STARS)(?:BD)?(?:-|\d)').hasMatch(surface);
}

String? _declaredScopedBridgeKey(
  ScrapeExternalWorkIdentity? identity, {
  ScrapeWorkIdentityEvidence? evidence,
}) {
  if (identity == null) return null;
  final declared = identity.declaredCodes.toList(growable: false);
  final startNumbers = <String>{};
  final starsNumbers = <String>{};
  for (final raw in declared) {
    final normalized = normalizeScrapeWorkCodeSurface(raw);
    if (normalized == null) continue;
    final compact = normalized.replaceAll('-', '');
    final start = RegExp(r'^(?:107|1)?START0*(\d+)$').firstMatch(compact);
    if (start != null) startNumbers.add(start.group(1)!);
    final stars = RegExp(r'^STARS(?:BD)?0*(\d+)$').firstMatch(compact);
    if (stars != null) starsNumbers.add(stars.group(1)!);
  }
  if (startNumbers.length == 1 && starsNumbers.isEmpty) {
    return 'start${startNumbers.single}';
  }
  if (starsNumbers.length == 1 &&
      startNumbers.isEmpty &&
      _hasSodContext(evidence)) {
    return 'stars${starsNumbers.single}';
  }
  return null;
}

/// Returns the canonical display spelling without using the legacy alias
/// table. The selected spelling is for storage/UI only; surface remains
/// available to source-specific image lookup when needed.
String? preferredScrapeWorkCode(
  Iterable<String?> rawCodes, {
  ScrapeWorkIdentityEvidence? evidence,
}) {
  final identities = rawCodes
      .map((raw) => parseScrapeWorkCodeIdentity(raw, evidence: evidence))
      .whereType<ScrapeWorkCodeIdentity>()
      .toList(growable: false);
  if (identities.isEmpty) {
    return null;
  }

  final structured = identities.where((item) => item.isStructured).toList();
  if (structured.isNotEmpty) {
    structured.sort((left, right) {
      final leftHyphen = left.displayCode.contains('-') ? 0 : 1;
      final rightHyphen = right.displayCode.contains('-') ? 0 : 1;
      final hyphenComparison = leftHyphen.compareTo(rightHyphen);
      if (hyphenComparison != 0) {
        return hyphenComparison;
      }
      return left.displayCode.compareTo(right.displayCode);
    });
    return structured.first.displayCode;
  }
  return identities.first.displayCode;
}

/// Storage spelling for one chosen source record. Unlike
/// [preferredScrapeWorkCode], this preserves a real V/T/VT edition suffix
/// when no ordinary candidate was selected for that identity.
String? scrapeWorkStorageCode(String? rawCode) {
  final identity = parseScrapeWorkCodeIdentity(rawCode);
  if (identity == null) return null;
  return identity.isSpecialEdition ? identity.surface : identity.displayCode;
}

/// Returns the clean canonical storage spelling for the new works pipeline.
///
/// Unlike the legacy storage helper above, a trusted SOD edition context is
/// allowed to collapse a V/T/VT/EC/BD surface even when that edition is the
/// only catalog record. Cross-platform aliases are considered only when the
/// source declared them on the same record.
String? scrapeWorkCanonicalStorageCode(
  String? rawCode, {
  ScrapeExternalWorkIdentity? externalIdentity,
  ScrapeWorkIdentityEvidence? identityEvidence,
}) {
  final evidence = identityEvidence ?? _identityEvidence(externalIdentity);
  final declared = <String?>[
    externalIdentity?.canonicalCode,
    externalIdentity?.makerCode,
    ...?externalIdentity?.aliases,
    ...?externalIdentity?.platformIds.values,
    rawCode,
  ];
  final bridgeKey = _declaredScopedBridgeKey(
    externalIdentity,
    evidence: evidence,
  );
  if (bridgeKey != null) {
    final prefix = bridgeKey.startsWith('start') ? 'START' : 'STARS';
    return '$prefix-${_formatSodDigits(bridgeKey.substring(prefix.toLowerCase().length))}';
  }
  for (final candidate in declared) {
    final identity = parseScrapeWorkCodeIdentity(candidate, evidence: evidence);
    if (identity == null || !identity.isStructured) continue;
    return identity.displayCode;
  }
  return scrapeWorkStorageCode(rawCode);
}

/// Compares metadata only when one side lacks a code. The actress is already
/// the operation's common subject, so title plus one independent source
/// attribute (release date, publisher, or studio) is the minimum evidence.
bool scrapeWorkMetadataLikelySame({
  required String? firstTitle,
  required String? firstReleaseDate,
  required String? firstPublisher,
  required String? firstStudio,
  required String? secondTitle,
  required String? secondReleaseDate,
  required String? secondPublisher,
  required String? secondStudio,
}) {
  final firstTitleKey = scrapeTitleIdentity(firstTitle);
  final secondTitleKey = scrapeTitleIdentity(secondTitle);
  if (!firstTitleKey.isUsable ||
      !secondTitleKey.isUsable ||
      firstTitleKey.key != secondTitleKey.key) {
    return false;
  }

  var corroboration = 0;
  final firstDate = _normalizeMetadataValue(firstReleaseDate);
  final secondDate = _normalizeMetadataValue(secondReleaseDate);
  if (firstDate != null && secondDate != null && firstDate == secondDate) {
    corroboration++;
  }
  final firstPublisherKey = _normalizeMetadataValue(firstPublisher);
  final secondPublisherKey = _normalizeMetadataValue(secondPublisher);
  if (firstPublisherKey != null &&
      secondPublisherKey != null &&
      firstPublisherKey == secondPublisherKey) {
    corroboration++;
  }
  final firstStudioKey = _normalizeMetadataValue(firstStudio);
  final secondStudioKey = _normalizeMetadataValue(secondStudio);
  if (firstStudioKey != null &&
      secondStudioKey != null &&
      firstStudioKey == secondStudioKey) {
    corroboration++;
  }
  return corroboration > 0;
}

/// Returns true only for the publisher spelling supported by the current
/// parser fixtures/first-party samples. Do not infer this from a work code.
bool isRebeccaPublisher(String? publisher) {
  final normalized = _normalizePublisherSurface(publisher).toLowerCase();
  return normalized
      .split(RegExp(r'[/／,，、|&]'))
      .map((part) => part.trim())
      .any((part) => part == 'rebecca');
}

String _normalizeTitleSurface(String? raw) {
  if (raw == null) {
    return '';
  }
  return raw.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _normalizePublisherSurface(String? raw) {
  if (raw == null) {
    return '';
  }
  return raw.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String? _normalizeMetadataValue(String? raw) {
  final value = raw?.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
  return value == null || value.isEmpty ? null : value;
}

String _normalizeCodeSurface(String? raw) {
  if (raw == null) {
    return '';
  }
  final folded = raw.runes.map((rune) {
    if (rune >= 0xFF01 && rune <= 0xFF5E) {
      return String.fromCharCode(rune - 0xFEE0);
    }
    if (rune == 0x3000) {
      return ' ';
    }
    return String.fromCharCode(rune);
  }).join();
  return folded
      .replaceAll(RegExp(r'[‐‑‒–—−﹘﹣－]'), '-')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
