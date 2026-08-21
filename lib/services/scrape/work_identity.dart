// Identity rules used only by the new works scrape pipeline.
//
// This file intentionally does not depend on work_code_canonicalizer.dart.
// The legacy canonicalizer contains alias reconciliation that is still needed
// by a few presentation/image consumers, but it must not decide whether two
// newly scraped works are the same work.

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
ScrapeWorkCodeIdentity? parseScrapeWorkCodeIdentity(String? raw) {
  final surface = normalizeScrapeWorkCodeSurface(raw);
  if (surface == null) {
    return null;
  }

  // Sources use both START-276V and STARS-859-T spellings. Only strip a
  // terminal edition marker, then require the remaining surface to be a
  // structured work code before treating it as the ordinary identity.
  final editionMatch = RegExp(r'^(.+?)-?(VT|T|V)$').firstMatch(surface);
  final baseSurface = editionMatch?.group(1) ?? surface;
  final parsed = _parseScrapeWorkCodeIdentitySurface(baseSurface);
  if (editionMatch != null && parsed.isStructured) {
    return ScrapeWorkCodeIdentity(
      surface: surface,
      key: parsed.key,
      displayCode: parsed.displayCode,
      isStructured: true,
      isSpecialEdition: true,
    );
  }
  return parsed;
}

ScrapeWorkCodeIdentity _parseScrapeWorkCodeIdentitySurface(String surface) {
  final separated = RegExp(r'^([A-Z0-9][A-Z0-9]*)-(\d+)$').firstMatch(surface);
  if (separated != null) {
    final prefix = separated.group(1)!;
    final digits = separated.group(2)!;
    return ScrapeWorkCodeIdentity(
      surface: surface,
      key: prefix.toLowerCase() + digits,
      displayCode: prefix + '-' + digits,
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
        key: 'start' + startDigits,
        displayCode: 'START-' + startDigits,
        isStructured: true,
      );
    }
    return ScrapeWorkCodeIdentity(
      surface: surface,
      key: prefix.toLowerCase() + digits,
      displayCode: prefix + '-' + digits,
      isStructured: true,
    );
  }

  return ScrapeWorkCodeIdentity(
    surface: surface,
    key: 'opaque:' + surface.toLowerCase(),
    displayCode: surface,
    isStructured: false,
  );
}

String? scrapeWorkCodeIdentityKey(String? raw) =>
    parseScrapeWorkCodeIdentity(raw)?.key;

bool scrapeWorkCodeIsSpecialEdition(String? raw) =>
    parseScrapeWorkCodeIdentity(raw)?.isSpecialEdition ?? false;

bool scrapeWorkCodesEqual(String? left, String? right) {
  final leftKey = scrapeWorkCodeIdentityKey(left);
  final rightKey = scrapeWorkCodeIdentityKey(right);
  return leftKey != null && leftKey == rightKey;
}

/// Returns the canonical display spelling without using the legacy alias
/// table. The selected spelling is for storage/UI only; surface remains
/// available to source-specific image lookup when needed.
String? preferredScrapeWorkCode(Iterable<String?> rawCodes) {
  final identities = rawCodes
      .map(parseScrapeWorkCodeIdentity)
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
