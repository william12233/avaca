import 'dart:convert';

import '../scrape/work_code_canonicalizer.dart';

/// The only origins from which an evidence-derived work-image route may be
/// generated.  A descriptor is always created from an already observed URL;
/// it is never produced by guessing a CDN host or path.
enum WorkImageLearnedRouteSource { dmmDigitalVideo, mgstageImages }

enum WorkImageLearnedVariantMode { dmmPsPl, mgstagePfPb, singleCover }

enum WorkImageLearnedCandidateStatus {
  provisional,
  verified,
  degraded,
  quarantined,
}

enum WorkImageTemplatePartKind { literal, prefix, number }

final class WorkImageTemplatePart {
  const WorkImageTemplatePart.literal(this.value)
    : kind = WorkImageTemplatePartKind.literal,
      numberWidth = null;

  const WorkImageTemplatePart.prefix()
    : kind = WorkImageTemplatePartKind.prefix,
      value = null,
      numberWidth = null;

  const WorkImageTemplatePart.number({this.numberWidth})
    : kind = WorkImageTemplatePartKind.number,
      value = null;

  final WorkImageTemplatePartKind kind;
  final String? value;
  final int? numberWidth;

  String render({required String prefix, required String number}) {
    return switch (kind) {
      WorkImageTemplatePartKind.literal => value!,
      WorkImageTemplatePartKind.prefix => prefix,
      WorkImageTemplatePartKind.number =>
        numberWidth == null ? number : number.padLeft(numberWidth!, '0'),
    };
  }

  String get canonicalKey => switch (kind) {
    WorkImageTemplatePartKind.literal => 'l:${jsonEncode(value)}',
    WorkImageTemplatePartKind.prefix => 'p',
    WorkImageTemplatePartKind.number => 'n:${numberWidth ?? 0}',
  };
}

final class WorkImageTemplateSegment {
  WorkImageTemplateSegment(Iterable<WorkImageTemplatePart> parts)
    : parts = List.unmodifiable(parts);

  final List<WorkImageTemplatePart> parts;

  String render({required String prefix, required String number}) {
    return parts
        .map((part) => part.render(prefix: prefix, number: number))
        .join();
  }

  String get canonicalKey => parts.map((part) => part.canonicalKey).join(',');
}

final class WorkImageLearnedRouteDescriptor {
  WorkImageLearnedRouteDescriptor({
    required this.source,
    required this.variantMode,
    required Iterable<WorkImageTemplateSegment> cardPath,
    required Iterable<WorkImageTemplateSegment> detailPath,
  }) : cardPath = List.unmodifiable(cardPath),
       detailPath = List.unmodifiable(detailPath);

  final WorkImageLearnedRouteSource source;
  final WorkImageLearnedVariantMode variantMode;
  final List<WorkImageTemplateSegment> cardPath;
  final List<WorkImageTemplateSegment> detailPath;

  String get canonicalKey => [
    source.name,
    variantMode.name,
    cardPath.map((segment) => segment.canonicalKey).join('/'),
    detailPath.map((segment) => segment.canonicalKey).join('/'),
  ].join('|');

  bool get isPairedVariant =>
      variantMode == WorkImageLearnedVariantMode.dmmPsPl ||
      variantMode == WorkImageLearnedVariantMode.mgstagePfPb;
}

final class WorkImageLearnedRouteCandidate {
  WorkImageLearnedRouteCandidate({
    required this.descriptor,
    this.successCount = 0,
    this.failureCount = 0,
    this.consecutiveDefinitiveFailures = 0,
    Iterable<String> verifiedWorkCodes = const [],
    Iterable<String> failedWorkCodes = const [],
    this.lastSuccessAt,
    this.lastFailureAt,
    this.quarantinedAt,
    this.lastEvidenceWorkCode,
    this.lastEvidenceHost,
    this.lastEvidencePath,
    this.lastEvidenceSource,
  }) : verifiedWorkCodes = _boundedCandidateCodes(verifiedWorkCodes),
       failedWorkCodes = _boundedCandidateCodes(failedWorkCodes);

  final WorkImageLearnedRouteDescriptor descriptor;
  final int successCount;
  final int failureCount;
  final int consecutiveDefinitiveFailures;
  final List<String> verifiedWorkCodes;
  final List<String> failedWorkCodes;
  final DateTime? lastSuccessAt;
  final DateTime? lastFailureAt;
  final DateTime? quarantinedAt;
  final String? lastEvidenceWorkCode;
  final String? lastEvidenceHost;
  final String? lastEvidencePath;
  final String? lastEvidenceSource;

  WorkImageLearnedCandidateStatus get status {
    if (quarantinedAt != null) {
      return WorkImageLearnedCandidateStatus.quarantined;
    }
    if (verifiedWorkCodes.length >= 2) {
      return WorkImageLearnedCandidateStatus.verified;
    }
    if (consecutiveDefinitiveFailures > 0 && successCount > 0) {
      return WorkImageLearnedCandidateStatus.degraded;
    }
    return WorkImageLearnedCandidateStatus.provisional;
  }

  bool get isUsable => status != WorkImageLearnedCandidateStatus.quarantined;

  WorkImageLearnedRouteCandidate withSuccess({
    required String workCode,
    required DateTime at,
    required Uri evidenceUri,
  }) {
    final canonical = canonicalizeWorkCode(workCode) ?? workCode.trim();
    final distinct = !verifiedWorkCodes.contains(canonical);
    return WorkImageLearnedRouteCandidate(
      descriptor: descriptor,
      successCount: successCount + (distinct ? 1 : 0),
      failureCount: failureCount,
      consecutiveDefinitiveFailures: 0,
      verifiedWorkCodes: distinct
          ? [...verifiedWorkCodes, canonical]
          : verifiedWorkCodes,
      failedWorkCodes: failedWorkCodes,
      lastSuccessAt: at,
      lastFailureAt: lastFailureAt,
      quarantinedAt: null,
      lastEvidenceWorkCode: canonical,
      lastEvidenceHost: evidenceUri.host.toLowerCase(),
      lastEvidencePath: evidenceUri.path,
      lastEvidenceSource: descriptor.source.name,
    );
  }

  WorkImageLearnedRouteCandidate withDefinitiveFailure({
    required String? workCode,
    required DateTime at,
  }) {
    final canonical = workCode == null
        ? null
        : canonicalizeWorkCode(workCode) ?? workCode.trim();
    final distinctFailure =
        canonical != null && !failedWorkCodes.contains(canonical);
    final nextFailures = distinctFailure
        ? [...failedWorkCodes, canonical]
        : failedWorkCodes;
    final shouldQuarantine = verifiedWorkCodes.length < 2
        ? distinctFailure && verifiedWorkCodes.any((code) => code != canonical)
        : nextFailures.length >= 2;
    return WorkImageLearnedRouteCandidate(
      descriptor: descriptor,
      successCount: successCount,
      failureCount: failureCount + 1,
      consecutiveDefinitiveFailures: consecutiveDefinitiveFailures + 1,
      verifiedWorkCodes: verifiedWorkCodes,
      failedWorkCodes: nextFailures,
      lastSuccessAt: lastSuccessAt,
      lastFailureAt: at,
      quarantinedAt: shouldQuarantine ? at : quarantinedAt,
      lastEvidenceWorkCode: lastEvidenceWorkCode,
      lastEvidenceHost: lastEvidenceHost,
      lastEvidencePath: lastEvidencePath,
      lastEvidenceSource: lastEvidenceSource,
    );
  }

  WorkImageLearnedRouteCandidate quarantine(DateTime at) {
    return WorkImageLearnedRouteCandidate(
      descriptor: descriptor,
      successCount: successCount,
      failureCount: failureCount,
      consecutiveDefinitiveFailures: consecutiveDefinitiveFailures,
      verifiedWorkCodes: verifiedWorkCodes,
      failedWorkCodes: failedWorkCodes,
      lastSuccessAt: lastSuccessAt,
      lastFailureAt: lastFailureAt,
      quarantinedAt: at,
      lastEvidenceWorkCode: lastEvidenceWorkCode,
      lastEvidenceHost: lastEvidenceHost,
      lastEvidencePath: lastEvidencePath,
      lastEvidenceSource: lastEvidenceSource,
    );
  }
}

final class WorkImageLearnedPrefixRoute {
  WorkImageLearnedPrefixRoute({
    required this.prefix,
    Iterable<WorkImageLearnedRouteCandidate> candidates = const [],
    this.preferredDescriptorKey,
  }) : candidates = List.unmodifiable(
         candidates.toList()..sort(compareLearnedRouteCandidates),
       );

  final String prefix;
  final List<WorkImageLearnedRouteCandidate> candidates;
  final String? preferredDescriptorKey;

  WorkImageLearnedRouteCandidate? candidateFor(String descriptorKey) {
    for (final candidate in candidates) {
      if (candidate.descriptor.canonicalKey == descriptorKey) return candidate;
    }
    return null;
  }
}

final class WorkImageLearnedRouteDocument {
  const WorkImageLearnedRouteDocument({
    required this.schemaVersion,
    required this.routes,
  });

  static const currentSchemaVersion = 1;

  factory WorkImageLearnedRouteDocument.empty() {
    return const WorkImageLearnedRouteDocument(
      schemaVersion: currentSchemaVersion,
      routes: <String, WorkImageLearnedPrefixRoute>{},
    );
  }

  final int schemaVersion;
  final Map<String, WorkImageLearnedPrefixRoute> routes;
}

int compareLearnedRouteCandidates(
  WorkImageLearnedRouteCandidate left,
  WorkImageLearnedRouteCandidate right,
) {
  final leftPreferred = left.status == WorkImageLearnedCandidateStatus.verified
      ? 0
      : left.status == WorkImageLearnedCandidateStatus.provisional
      ? 1
      : left.status == WorkImageLearnedCandidateStatus.degraded
      ? 2
      : 3;
  final rightPreferred =
      right.status == WorkImageLearnedCandidateStatus.verified
      ? 0
      : right.status == WorkImageLearnedCandidateStatus.provisional
      ? 1
      : right.status == WorkImageLearnedCandidateStatus.degraded
      ? 2
      : 3;
  final byStatus = leftPreferred.compareTo(rightPreferred);
  if (byStatus != 0) return byStatus;
  final bySuccess = right.successCount.compareTo(left.successCount);
  if (bySuccess != 0) return bySuccess;
  return left.descriptor.canonicalKey.compareTo(right.descriptor.canonicalKey);
}

/// Extracts a route only when one observed official image URI proves the
/// complete structure needed to render both variants later.
final class WorkImageEvidenceRouteParser {
  const WorkImageEvidenceRouteParser();

  WorkImageLearnedRouteDescriptor? parse({
    required Uri evidenceUri,
    required String code,
  }) {
    final canonical = canonicalizeWorkCode(code);
    if (canonical == null) return null;
    final codeMatch = RegExp(
      r'^([A-Z][A-Z0-9]*)-([0-9]+)$',
    ).firstMatch(canonical);
    if (codeMatch == null) return null;
    final prefix = codeMatch.group(1)!.toLowerCase();
    final number = int.tryParse(codeMatch.group(2)!);
    if (number == null) return null;

    if (_isDmmHost(evidenceUri)) {
      return _parseDmm(evidenceUri, prefix: prefix, number: number);
    }
    if (evidenceUri.host.toLowerCase() == 'image.mgstage.com') {
      return _parseMgStage(evidenceUri, prefix: prefix, number: number);
    }
    return null;
  }

  WorkImageLearnedRouteDescriptor? _parseDmm(
    Uri uri, {
    required String prefix,
    required int number,
  }) {
    if (!_isStrictHttpsUri(uri) ||
        uri.path.contains(RegExp(r'%2f|%5c', caseSensitive: false))) {
      return null;
    }
    final segments = uri.pathSegments;
    final host = uri.host.toLowerCase();
    final normalizedSegments = <String>[];
    if (host == 'pics.dmm.co.jp') {
      if (segments.length != 4 ||
          segments[0] != 'digital' ||
          segments[1] != 'video') {
        return null;
      }
      normalizedSegments.addAll(segments);
    } else if (host == 'awsimgsrc.dmm.co.jp') {
      if (segments.length != 5 ||
          (segments[0] != 'pics' && segments[0] != 'pics_dig') ||
          segments[1] != 'digital' ||
          segments[2] != 'video') {
        return null;
      }
      normalizedSegments.addAll(segments.skip(1));
    } else {
      return null;
    }
    final token = normalizedSegments[2].toLowerCase();
    final filename = normalizedSegments[3].toLowerCase();
    if (!RegExp(r'^[a-z0-9_.-]+$').hasMatch(token) ||
        !RegExp(r'^[a-z0-9_.-]+\.jpg$').hasMatch(filename) ||
        !filename.startsWith(token)) {
      return null;
    }
    final suffix = filename.substring(token.length);
    if (suffix != 'jp-1.jpg' && suffix != 'ps.jpg' && suffix != 'pl.jpg') {
      return null;
    }
    final tokenParts = _tokenParts(token, prefix: prefix, number: number);
    if (tokenParts == null) return null;
    final tokenSegment = WorkImageTemplateSegment(tokenParts);
    final common = <WorkImageTemplateSegment>[
      WorkImageTemplateSegment([
        const WorkImageTemplatePart.literal('pics_dig'),
      ]),
      WorkImageTemplateSegment([
        const WorkImageTemplatePart.literal('digital'),
      ]),
      WorkImageTemplateSegment([const WorkImageTemplatePart.literal('video')]),
      tokenSegment,
    ];
    final card = [
      ...common,
      WorkImageTemplateSegment([
        ...tokenParts,
        const WorkImageTemplatePart.literal('ps.jpg'),
      ]),
    ];
    final detail = [
      ...common,
      WorkImageTemplateSegment([
        ...tokenParts,
        const WorkImageTemplatePart.literal('pl.jpg'),
      ]),
    ];
    return WorkImageLearnedRouteDescriptor(
      source: WorkImageLearnedRouteSource.dmmDigitalVideo,
      variantMode: WorkImageLearnedVariantMode.dmmPsPl,
      cardPath: card,
      detailPath: detail,
    );
  }

  WorkImageLearnedRouteDescriptor? _parseMgStage(
    Uri uri, {
    required String prefix,
    required int number,
  }) {
    if (!_isStrictHttpsUri(uri) ||
        uri.path.contains(RegExp(r'%2f|%5c', caseSensitive: false))) {
      return null;
    }
    final segments = uri.pathSegments;
    if (segments.length < 3 || segments.length > 8 || segments[0] != 'images') {
      return null;
    }
    if (segments.any(
      (segment) =>
          segment.isEmpty || !RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(segment),
    )) {
      return null;
    }
    final filename = segments.last.toLowerCase();
    if (!filename.endsWith('.jpg')) return null;
    final match = RegExp(
      r'^(.*)' + RegExp.escape(prefix) + r'-(\d+)(\.jpg)$',
      caseSensitive: false,
    ).firstMatch(filename);
    if (match == null || int.tryParse(match.group(2)!) != number) return null;
    final numberText = match.group(2)!;
    final prefixIndex = filename.indexOf(prefix);
    if (prefixIndex < 0) return null;
    final prefixEnd = prefixIndex + prefix.length;
    if (prefixEnd >= filename.length || filename[prefixEnd] != '-') return null;

    final prefixParts = _replaceCodeInSegment(
      filename,
      prefix: prefix,
      number: number,
      numberWidth: numberText.length,
      separator: '-',
    );
    if (prefixParts == null) return null;

    final common = <WorkImageTemplateSegment>[];
    for (var index = 0; index < segments.length - 1; index++) {
      final segment = segments[index];
      if (segment.toLowerCase() == prefix) {
        common.add(
          WorkImageTemplateSegment([const WorkImageTemplatePart.prefix()]),
        );
      } else if (int.tryParse(segment) == number) {
        common.add(
          WorkImageTemplateSegment([
            WorkImageTemplatePart.number(numberWidth: segment.length),
          ]),
        );
      } else {
        common.add(
          WorkImageTemplateSegment([
            WorkImageTemplatePart.literal(segment.toLowerCase()),
          ]),
        );
      }
    }
    final fileSegment = WorkImageTemplateSegment(prefixParts);
    final lowerPrefix = filename.substring(0, filename.indexOf(prefix));
    final paired =
        lowerPrefix.startsWith('pf_e_') || lowerPrefix.startsWith('pb_e_');
    if (paired) {
      final cardFile = WorkImageTemplateSegment(
        _replacePrefixLiteral(prefixParts, 'pb_e_', 'pf_e_'),
      );
      final detailFile = WorkImageTemplateSegment(
        _replacePrefixLiteral(prefixParts, 'pf_e_', 'pb_e_'),
      );
      return WorkImageLearnedRouteDescriptor(
        source: WorkImageLearnedRouteSource.mgstageImages,
        variantMode: WorkImageLearnedVariantMode.mgstagePfPb,
        cardPath: [...common, cardFile],
        detailPath: [...common, detailFile],
      );
    }
    return WorkImageLearnedRouteDescriptor(
      source: WorkImageLearnedRouteSource.mgstageImages,
      variantMode: WorkImageLearnedVariantMode.singleCover,
      cardPath: [...common, fileSegment],
      detailPath: [...common, fileSegment],
    );
  }

  List<WorkImageTemplatePart>? _tokenParts(
    String token, {
    required String prefix,
    required int number,
  }) {
    final candidates = <List<WorkImageTemplatePart>>[];
    var searchStart = 0;
    while (searchStart < token.length) {
      final index = token.indexOf(prefix, searchStart);
      if (index < 0) break;
      final numberMatch = RegExp(
        r'^\d+',
      ).firstMatch(token.substring(index + prefix.length));
      if (numberMatch != null) {
        final digits = numberMatch.group(0)!;
        if (int.tryParse(digits) == number) {
          final leading = token.substring(0, index);
          final trailing = token.substring(
            index + prefix.length + digits.length,
          );
          if (_safeLiteral(leading) && _safeLiteral(trailing)) {
            candidates.add([
              if (leading.isNotEmpty) WorkImageTemplatePart.literal(leading),
              const WorkImageTemplatePart.prefix(),
              WorkImageTemplatePart.number(numberWidth: digits.length),
              if (trailing.isNotEmpty) WorkImageTemplatePart.literal(trailing),
            ]);
          }
        }
      }
      searchStart = index + 1;
    }
    if (candidates.length != 1) return null;
    return candidates.single;
  }

  List<WorkImageTemplatePart>? _replaceCodeInSegment(
    String segment, {
    required String prefix,
    required int number,
    required int numberWidth,
    required String separator,
  }) {
    final match = RegExp(
      r'^(.*)' +
          RegExp.escape(prefix) +
          RegExp.escape(separator) +
          r'(\d+)(\.jpg)$',
      caseSensitive: false,
    ).firstMatch(segment);
    if (match == null || int.tryParse(match.group(2)!) != number) return null;
    final leading = match.group(1)!;
    if (!_safeLiteral(leading)) return null;
    return [
      if (leading.isNotEmpty) WorkImageTemplatePart.literal(leading),
      const WorkImageTemplatePart.prefix(),
      const WorkImageTemplatePart.literal('-'),
      WorkImageTemplatePart.number(numberWidth: numberWidth),
      const WorkImageTemplatePart.literal('.jpg'),
    ];
  }

  List<WorkImageTemplatePart> _replacePrefixLiteral(
    List<WorkImageTemplatePart> parts,
    String from,
    String to,
  ) {
    if (parts.isEmpty ||
        parts.first.kind != WorkImageTemplatePartKind.literal ||
        parts.first.value != from) {
      return parts;
    }
    return [WorkImageTemplatePart.literal(to), ...parts.skip(1)];
  }

  bool _safeLiteral(String value) =>
      value.length <= 64 && RegExp(r'^[a-z0-9_.-]*$').hasMatch(value);

  bool _isDmmHost(Uri uri) {
    final host = uri.host.toLowerCase();
    return host == 'awsimgsrc.dmm.co.jp' || host == 'pics.dmm.co.jp';
  }

  bool _isStrictHttpsUri(Uri uri) {
    return uri.scheme.toLowerCase() == 'https' &&
        uri.userInfo.isEmpty &&
        (uri.port == 0 || uri.port == 443) &&
        uri.query.isEmpty &&
        uri.fragment.isEmpty;
  }
}

final class WorkImageLearnedRouteDocumentCodec {
  const WorkImageLearnedRouteDocumentCodec._();

  static const maxRoutes = 10000;
  static const maxCandidatesPerPrefix = 8;
  static const maxPathSegments = 8;
  static const maxTemplatePartsPerSegment = 16;
  static const maxStoredWorkCodes = 2;

  static String encode(WorkImageLearnedRouteDocument document) {
    final routes = <String, Object?>{};
    for (final prefix in document.routes.keys.toList()..sort()) {
      final route = document.routes[prefix]!;
      routes[prefix] = {
        'preferredDescriptorKey': route.preferredDescriptorKey,
        'candidates': route.candidates.map(_encodeCandidate).toList(),
      };
    }
    return const JsonEncoder.withIndent('  ').convert({
      'kind': 'avaca.workImageLearnedRoutes',
      'schemaVersion': WorkImageLearnedRouteDocument.currentSchemaVersion,
      'routes': routes,
    });
  }

  static WorkImageLearnedRouteDocument decode(String rawJson) {
    dynamic decoded;
    try {
      decoded = jsonDecode(rawJson);
    } on Object catch (error) {
      throw FormatException('Invalid learned route JSON: $error');
    }
    if (decoded is! Map) {
      throw const FormatException('Invalid learned route document.');
    }
    final map = Map<String, dynamic>.from(decoded);
    _allowOnly(map, {'kind', 'schemaVersion', 'routes'});
    if (map['kind'] != 'avaca.workImageLearnedRoutes' ||
        map['schemaVersion'] !=
            WorkImageLearnedRouteDocument.currentSchemaVersion) {
      throw const FormatException('Unsupported learned route document.');
    }
    final rawRoutes = map['routes'];
    if (rawRoutes is! Map || rawRoutes.length > maxRoutes) {
      throw const FormatException('Invalid learned route map.');
    }
    final routes = <String, WorkImageLearnedPrefixRoute>{};
    for (final entry in rawRoutes.entries) {
      final prefix = normalizeWorkImagePrefix(entry.key?.toString());
      if (prefix == null || routes.containsKey(prefix)) {
        throw const FormatException('Invalid or duplicate learned Prefix.');
      }
      final value = entry.value;
      if (value is! Map) {
        throw const FormatException('Invalid learned Prefix route.');
      }
      final routeMap = Map<String, dynamic>.from(value);
      _allowOnly(routeMap, {'preferredDescriptorKey', 'candidates'});
      final rawCandidates = routeMap['candidates'];
      if (rawCandidates is! List ||
          rawCandidates.length > maxCandidatesPerPrefix ||
          rawCandidates.isEmpty) {
        throw const FormatException('Invalid learned route candidates.');
      }
      final candidates = <WorkImageLearnedRouteCandidate>[];
      for (final rawCandidate in rawCandidates) {
        final candidate = _decodeCandidate(rawCandidate);
        if (candidates.any(
          (item) =>
              item.descriptor.canonicalKey == candidate.descriptor.canonicalKey,
        )) {
          throw const FormatException('Duplicate learned descriptor.');
        }
        candidates.add(candidate);
      }
      final preferred = routeMap['preferredDescriptorKey'] as String?;
      if (preferred != null &&
          candidates.every(
            (candidate) => candidate.descriptor.canonicalKey != preferred,
          )) {
        throw const FormatException('Unknown preferred learned descriptor.');
      }
      routes[prefix] = WorkImageLearnedPrefixRoute(
        prefix: prefix,
        candidates: candidates,
        preferredDescriptorKey: preferred,
      );
    }
    return WorkImageLearnedRouteDocument(
      schemaVersion: WorkImageLearnedRouteDocument.currentSchemaVersion,
      routes: routes,
    );
  }

  static Map<String, Object?> _encodeCandidate(
    WorkImageLearnedRouteCandidate candidate,
  ) {
    return {
      'descriptor': _encodeDescriptor(candidate.descriptor),
      'successCount': candidate.successCount,
      'failureCount': candidate.failureCount,
      'consecutiveDefinitiveFailures': candidate.consecutiveDefinitiveFailures,
      'verifiedWorkCodes': candidate.verifiedWorkCodes,
      'failedWorkCodes': candidate.failedWorkCodes,
      'lastSuccessAt': candidate.lastSuccessAt?.toUtc().toIso8601String(),
      'lastFailureAt': candidate.lastFailureAt?.toUtc().toIso8601String(),
      'quarantinedAt': candidate.quarantinedAt?.toUtc().toIso8601String(),
      'lastEvidenceWorkCode': candidate.lastEvidenceWorkCode,
      'lastEvidenceHost': candidate.lastEvidenceHost,
      'lastEvidencePath': candidate.lastEvidencePath,
      'lastEvidenceSource': candidate.lastEvidenceSource,
    };
  }

  static Map<String, Object?> _encodeDescriptor(
    WorkImageLearnedRouteDescriptor descriptor,
  ) {
    _validateDescriptor(descriptor);
    return {
      'source': descriptor.source.name,
      'variantMode': descriptor.variantMode.name,
      'cardPath': descriptor.cardPath.map(_encodeSegment).toList(),
      'detailPath': descriptor.detailPath.map(_encodeSegment).toList(),
    };
  }

  static Map<String, Object?> _encodeSegment(WorkImageTemplateSegment segment) {
    return {
      'parts': segment.parts.map((part) {
        return switch (part.kind) {
          WorkImageTemplatePartKind.literal => {
            'kind': 'literal',
            'value': part.value,
          },
          WorkImageTemplatePartKind.prefix => {'kind': 'prefix'},
          WorkImageTemplatePartKind.number => {
            'kind': 'number',
            if (part.numberWidth != null) 'width': part.numberWidth,
          },
        };
      }).toList(),
    };
  }

  static WorkImageLearnedRouteCandidate _decodeCandidate(dynamic raw) {
    if (raw is! Map) throw const FormatException('Invalid learned candidate.');
    final map = Map<String, dynamic>.from(raw);
    _allowOnly(map, {
      'descriptor',
      'successCount',
      'failureCount',
      'consecutiveDefinitiveFailures',
      'verifiedWorkCodes',
      'failedWorkCodes',
      'lastSuccessAt',
      'lastFailureAt',
      'quarantinedAt',
      'lastEvidenceWorkCode',
      'lastEvidenceHost',
      'lastEvidencePath',
      'lastEvidenceSource',
    });
    final successCount = _count(map['successCount']);
    final failureCount = _count(map['failureCount']);
    final consecutive = _count(map['consecutiveDefinitiveFailures']);
    final verified = _codes(map['verifiedWorkCodes']);
    final failed = _codes(map['failedWorkCodes']);
    if (verified.length > maxStoredWorkCodes ||
        failed.length > maxStoredWorkCodes) {
      throw const FormatException('Too many learned work IDs.');
    }
    return WorkImageLearnedRouteCandidate(
      descriptor: _decodeDescriptor(map['descriptor']),
      successCount: successCount,
      failureCount: failureCount,
      consecutiveDefinitiveFailures: consecutive,
      verifiedWorkCodes: verified,
      failedWorkCodes: failed,
      lastSuccessAt: _time(map['lastSuccessAt']),
      lastFailureAt: _time(map['lastFailureAt']),
      quarantinedAt: _time(map['quarantinedAt']),
      lastEvidenceWorkCode: _optionalString(map['lastEvidenceWorkCode']),
      lastEvidenceHost: _optionalString(map['lastEvidenceHost']),
      lastEvidencePath: _optionalString(map['lastEvidencePath']),
      lastEvidenceSource: _optionalString(map['lastEvidenceSource']),
    );
  }

  static WorkImageLearnedRouteDescriptor _decodeDescriptor(dynamic raw) {
    if (raw is! Map) throw const FormatException('Invalid learned descriptor.');
    final map = Map<String, dynamic>.from(raw);
    _allowOnly(map, {'source', 'variantMode', 'cardPath', 'detailPath'});
    final source = WorkImageLearnedRouteSource.values.firstWhere(
      (value) => value.name == map['source'],
      orElse: () => throw const FormatException('Unknown learned source.'),
    );
    final mode = WorkImageLearnedVariantMode.values.firstWhere(
      (value) => value.name == map['variantMode'],
      orElse: () =>
          throw const FormatException('Unknown learned variant mode.'),
    );
    final card = _decodePath(map['cardPath']);
    final detail = _decodePath(map['detailPath']);
    final descriptor = WorkImageLearnedRouteDescriptor(
      source: source,
      variantMode: mode,
      cardPath: card,
      detailPath: detail,
    );
    if (descriptor.cardPath.isEmpty || descriptor.detailPath.isEmpty) {
      throw const FormatException('Empty learned route path.');
    }
    if (source == WorkImageLearnedRouteSource.dmmDigitalVideo &&
        mode != WorkImageLearnedVariantMode.dmmPsPl) {
      throw const FormatException('Invalid DMM learned variant mode.');
    }
    if (source == WorkImageLearnedRouteSource.mgstageImages &&
        mode == WorkImageLearnedVariantMode.dmmPsPl) {
      throw const FormatException('Invalid MGStage learned variant mode.');
    }
    _validateDescriptor(descriptor);
    return descriptor;
  }

  static void _validateDescriptor(WorkImageLearnedRouteDescriptor descriptor) {
    bool hasKind(
      List<WorkImageTemplateSegment> path,
      WorkImageTemplatePartKind kind,
    ) {
      return path.any(
        (segment) => segment.parts.any((part) => part.kind == kind),
      );
    }

    if (!hasKind(descriptor.cardPath, WorkImageTemplatePartKind.prefix) ||
        !hasKind(descriptor.detailPath, WorkImageTemplatePartKind.prefix) ||
        !hasKind(descriptor.cardPath, WorkImageTemplatePartKind.number) ||
        !hasKind(descriptor.detailPath, WorkImageTemplatePartKind.number)) {
      throw const FormatException(
        'A learned descriptor must bind both Prefix and number.',
      );
    }
    for (final path in [descriptor.cardPath, descriptor.detailPath]) {
      if (path.isEmpty || path.length > maxPathSegments) {
        throw const FormatException('Invalid learned descriptor path length.');
      }
      for (final segment in path) {
        if (segment.parts.isEmpty ||
            segment.parts.length > maxTemplatePartsPerSegment) {
          throw const FormatException('Invalid learned descriptor segment.');
        }
        for (final part in segment.parts) {
          if (part.kind == WorkImageTemplatePartKind.literal &&
              (part.value == '.' || part.value == '..')) {
            throw const FormatException('Unsafe learned descriptor literal.');
          }
        }
      }
    }
    if (descriptor.source == WorkImageLearnedRouteSource.dmmDigitalVideo) {
      for (final path in [descriptor.cardPath, descriptor.detailPath]) {
        if (path.length < 5 ||
            !_literalSegment(path[0], 'pics_dig') ||
            !_literalSegment(path[1], 'digital') ||
            !_literalSegment(path[2], 'video')) {
          throw const FormatException('Invalid DMM learned descriptor base.');
        }
      }
    } else {
      for (final path in [descriptor.cardPath, descriptor.detailPath]) {
        if (!_literalSegment(path.first, 'images')) {
          throw const FormatException(
            'Invalid MGStage learned descriptor base.',
          );
        }
      }
    }
  }

  static bool _literalSegment(
    WorkImageTemplateSegment segment,
    String expected,
  ) {
    return segment.parts.length == 1 &&
        segment.parts.first.kind == WorkImageTemplatePartKind.literal &&
        segment.parts.first.value == expected;
  }

  static List<WorkImageTemplateSegment> _decodePath(dynamic raw) {
    if (raw is! List || raw.isEmpty || raw.length > maxPathSegments) {
      throw const FormatException('Invalid learned route path.');
    }
    return raw.map(_decodeSegment).toList(growable: false);
  }

  static WorkImageTemplateSegment _decodeSegment(dynamic raw) {
    if (raw is! Map) {
      throw const FormatException('Invalid learned path segment.');
    }
    final map = Map<String, dynamic>.from(raw);
    _allowOnly(map, {'parts'});
    final rawParts = map['parts'];
    if (rawParts is! List ||
        rawParts.isEmpty ||
        rawParts.length > maxTemplatePartsPerSegment) {
      throw const FormatException('Invalid learned template parts.');
    }
    return WorkImageTemplateSegment(
      rawParts.map((rawPart) {
        if (rawPart is! Map) {
          throw const FormatException('Invalid learned part.');
        }
        final part = Map<String, dynamic>.from(rawPart);
        final kind = part['kind'];
        switch (kind) {
          case 'literal':
            _allowOnly(part, {'kind', 'value'});
            final value = part['value'];
            if (value is! String ||
                value.length > 64 ||
                !RegExp(r'^[a-z0-9_.-]*$').hasMatch(value)) {
              throw const FormatException('Invalid learned literal.');
            }
            return WorkImageTemplatePart.literal(value);
          case 'prefix':
            _allowOnly(part, {'kind'});
            return const WorkImageTemplatePart.prefix();
          case 'number':
            _allowOnly(part, {'kind', 'width'});
            final width = part['width'];
            if (width != null && (width is! int || width < 1 || width > 12)) {
              throw const FormatException('Invalid learned number width.');
            }
            return WorkImageTemplatePart.number(numberWidth: width as int?);
          default:
            throw const FormatException('Unknown learned template part.');
        }
      }),
    );
  }

  static List<String> _codes(dynamic raw) {
    if (raw is! List) throw const FormatException('Invalid learned work IDs.');
    final result = <String>[];
    for (final value in raw) {
      if (value is! String ||
          canonicalizeWorkCode(value) == null ||
          result.contains(canonicalizeWorkCode(value))) {
        throw const FormatException('Invalid learned work ID.');
      }
      result.add(canonicalizeWorkCode(value)!);
    }
    return result;
  }

  static int _count(dynamic raw) {
    if (raw == null) return 0;
    if (raw is! int || raw < 0 || raw > 0x7fffffff) {
      throw const FormatException('Invalid learned statistic.');
    }
    return raw;
  }

  static DateTime? _time(dynamic raw) {
    if (raw == null) return null;
    if (raw is! String) {
      throw const FormatException('Invalid learned timestamp.');
    }
    try {
      return DateTime.parse(raw).toUtc();
    } on FormatException {
      throw const FormatException('Invalid learned timestamp.');
    }
  }

  static String? _optionalString(dynamic raw) {
    if (raw == null) return null;
    if (raw is! String || raw.length > 256) {
      throw const FormatException('Invalid learned metadata.');
    }
    return raw;
  }

  static void _allowOnly(Map<String, dynamic> map, Set<String> allowed) {
    if (map.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException('Unknown learned route field.');
    }
  }
}

List<String> _boundedCandidateCodes(Iterable<String> values) {
  final result = <String>[];
  for (final value in values) {
    if (result.length == 2) break;
    if (!result.contains(value)) result.add(value);
  }
  return List.unmodifiable(result);
}
