import '../scrape/work_identity.dart';
import '../scrape/work_code_canonicalizer.dart';
import 'work_image_learned_route.dart';
import 'work_image_route_resolver.dart';

enum WorkImageSource { dmm, mgstage }

enum WorkImageVariant { card, detail }

enum WorkImageTokenFamily {
  standardDmm,
  leadingOneDmm,
  h1711Dmm,
  rebeccaH346Dmm,
}

const approvedWorkImageEndpointExamples = <String>[
  'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
      'sone00833/sone00833ps.jpg',
  'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
      'sone00833/sone00833pl.jpg',
  'https://image.mgstage.com/images/prestige/abf/183/'
      'pf_e_abf-183.jpg',
  'https://image.mgstage.com/images/prestige/abf/183/'
      'pb_e_abf-183.jpg',
  'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
      'h_346rebd00975/h_346rebd00975pl.jpg',
  'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
      'h_346rebd00975/h_346rebd00975ps.jpg',
];

class WorkImageUrls {
  const WorkImageUrls({
    required this.card,
    required this.detail,
    required this.source,
  });

  final Uri card;
  final Uri detail;
  final WorkImageSource source;

  Uri forVariant(WorkImageVariant variant) {
    return variant == WorkImageVariant.card ? card : detail;
  }
}

/// Validates an evidence-derived URL against the descriptor that generated
/// it.  Comparing with the fully rendered expected URI is intentional: it
/// prevents a persisted descriptor from turning into an arbitrary URL even if
/// the descriptor JSON was edited outside the app.
bool isApprovedGeneratedLearnedWorkImageUri({
  required Uri uri,
  required String code,
  required WorkImageLearnedRouteDescriptor descriptor,
  required WorkImageVariant variant,
}) {
  try {
    final urls = _renderLearnedUrls(code: code, descriptor: descriptor);
    final expected = urls.forVariant(variant);
    final expectedHost =
        descriptor.source == WorkImageLearnedRouteSource.dmmDigitalVideo
        ? 'awsimgsrc.dmm.co.jp'
        : 'image.mgstage.com';
    return uri == expected &&
        uri.scheme == 'https' &&
        uri.host.toLowerCase() == expectedHost &&
        uri.userInfo.isEmpty &&
        (uri.port == 0 || uri.port == 443) &&
        uri.query.isEmpty &&
        uri.fragment.isEmpty;
  } on Object {
    return false;
  }
}

/// The only image URL families that the scrape pipeline may request.
///
/// Each family has exactly two approved variants:
/// DMM ps/pl, Prestige pf/pb, and Rebecca h_346 ps/pl. The matcher is kept
/// next to the formatter so a future caller cannot silently reintroduce a
/// seventh CDN path.
bool isApprovedWorkImageUri(Uri uri) {
  if (uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
    return false;
  }
  final host = uri.host.toLowerCase();
  final path = uri.path.toLowerCase();
  if (host == 'awsimgsrc.dmm.co.jp') {
    return RegExp(
          r'^/pics_dig/digital/video/(?:[a-z0-9]+|h_1711[a-z0-9]+)\d{5}/'
          r'(?:[a-z0-9]+|h_1711[a-z0-9]+)\d{5}(?:ps|pl)\.jpg$',
        ).hasMatch(path) ||
        RegExp(
          r'^/pics_dig/digital/video/h_346rebd\d{5}/'
          r'h_346rebd\d{5}(?:ps|pl)\.jpg$',
        ).hasMatch(path);
  }
  if (host == 'image.mgstage.com') {
    return RegExp(
      r'^/images/[a-z0-9]+/[a-z0-9]+/\d+/p(?:f|b)_e_[a-z0-9]+-\d+\.jpg$',
    ).hasMatch(path);
  }
  return false;
}

class WorkImagePolicy {
  const WorkImagePolicy();

  /// Returns the local filename used for a work image.
  ///
  /// Keep this aligned with the approved DMM token so a work such as START
  /// 489 is stored as start00489ps.jpg (card) or start00489pl.jpg (detail).
  String fileNameFor({
    required String code,
    required WorkImageVariant variant,
  }) {
    final imageCode = _localImageCode(code);
    final suffix = variant == WorkImageVariant.card ? 'ps' : 'pl';
    return imageCode + suffix + '.jpg';
  }

  WorkImageUrls urlsFor({
    required String code,
    String? studio,
    String? publisher,
    // Retained for compatibility with older callers. Route selection is
    // intentionally metadata-only and never inspects source image URLs.
    List<Uri> evidenceUris = const [],
    WorkImageRouteResolution? route,
  }) {
    final resolved =
        route ??
        const WorkImageRouteResolver().resolve(
          studio: studio,
          publisher: publisher,
        );
    if (!resolved.isResolved) {
      throw WorkImageRouteException(code, resolved.failureReason!);
    }
    return urlsForFamily(code: code, family: resolved.family!);
  }

  /// Builds URLs for one of the explicitly supported image families.
  ///
  /// Route selection belongs to PrefixRouteRepository/WorkImageDownloader;
  /// this method is intentionally only a formatter plus the existing host
  /// and path safety assertion.
  WorkImageUrls urlsForFamily({
    required String code,
    required WorkImageNormalizationFamily family,
  }) {
    final parts = _parseCode(code);
    if (family == WorkImageNormalizationFamily.mgstagePrestige) {
      final normalizedCode = parts.prefix + '-' + parts.number;
      final base =
          'https://image.mgstage.com/images/prestige/' +
          parts.prefix +
          '/' +
          parts.number;
      final urls = WorkImageUrls(
        card: Uri.parse(base + '/pf_e_' + normalizedCode + '.jpg'),
        detail: Uri.parse(base + '/pb_e_' + normalizedCode + '.jpg'),
        source: WorkImageSource.mgstage,
      );
      _assertApproved(urls);
      return urls;
    }
    if (family == WorkImageNormalizationFamily.mgstageSeikyouiku) {
      final tokenPrefix = '502' + parts.prefix;
      final token = tokenPrefix + '-' + parts.number;
      final base =
          'https://image.mgstage.com/images/seikyouiku/' +
          tokenPrefix +
          '/' +
          parts.number;
      final urls = WorkImageUrls(
        card: Uri.parse(base + '/pf_e_' + token + '.jpg'),
        detail: Uri.parse(base + '/pb_e_' + token + '.jpg'),
        source: WorkImageSource.mgstage,
      );
      _assertApproved(urls);
      return urls;
    }

    final imageCode = _dmmImageCode(parts, family);
    final base =
        'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/' +
        imageCode +
        '/' +
        imageCode;
    final urls = WorkImageUrls(
      card: Uri.parse(base + 'ps.jpg'),
      detail: Uri.parse(base + 'pl.jpg'),
      source: WorkImageSource.dmm,
    );
    _assertApproved(urls);
    return urls;
  }

  WorkImageUrls urlsForLearnedDescriptor({
    required String code,
    required WorkImageLearnedRouteDescriptor descriptor,
  }) {
    return _renderLearnedUrls(code: code, descriptor: descriptor);
  }

  String _dmmImageCode(
    ({String prefix, String number}) parts,
    WorkImageNormalizationFamily family,
  ) {
    final paddedNumber = parts.number.padLeft(5, '0');
    return switch (family) {
      WorkImageNormalizationFamily.dmmStandard => parts.prefix + paddedNumber,
      WorkImageNormalizationFamily.dmmLeadingOne =>
        '1' + parts.prefix + paddedNumber,
      WorkImageNormalizationFamily.dmmH1711 =>
        'h_1711' + parts.prefix + paddedNumber,
      WorkImageNormalizationFamily.dmmRebeccaH346 =>
        parts.prefix == 'rebd'
            ? 'h_346' + parts.prefix + paddedNumber
            : throw FormatException(
                'Rebecca H346 is not applicable to ${parts.prefix}.',
              ),
      WorkImageNormalizationFamily.mgstagePrestige ||
      WorkImageNormalizationFamily.mgstageSeikyouiku => throw StateError(
        'MGStage route must not format a DMM URL.',
      ),
    };
  }

  WorkImageTokenFamily? tokenFamilyFor(
    String code, {
    String? studio,
    String? publisher,
    // Retained for compatibility with older callers. Route selection is
    // intentionally metadata-only and never inspects source image URLs.
    List<Uri> evidenceUris = const [],
  }) {
    try {
      final route = const WorkImageRouteResolver().resolve(
        studio: studio,
        publisher: publisher,
      );
      if (!route.isResolved) {
        return null;
      }
      return switch (route.family!) {
        WorkImageNormalizationFamily.dmmStandard =>
          WorkImageTokenFamily.standardDmm,
        WorkImageNormalizationFamily.dmmLeadingOne =>
          WorkImageTokenFamily.leadingOneDmm,
        WorkImageNormalizationFamily.dmmH1711 => WorkImageTokenFamily.h1711Dmm,
        WorkImageNormalizationFamily.dmmRebeccaH346 =>
          WorkImageTokenFamily.rebeccaH346Dmm,
        WorkImageNormalizationFamily.mgstagePrestige ||
        WorkImageNormalizationFamily.mgstageSeikyouiku => null,
      };
    } on FormatException {
      return null;
    }
  }

  String _localImageCode(String code) {
    try {
      final parts = _parseCode(code);
      // Local filenames intentionally use the visible work code family. The
      // network token (1start..., h_1711..., h_346...) is only for its
      // approved endpoint and must not become a second work identity.
      return parts.prefix + parts.number.padLeft(5, '0');
    } on FormatException {
      final normalized = normalizeScrapeWorkCodeSurface(code)
          ?.toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'_+'), '_')
          .replaceAll(RegExp(r'^_|_$'), '');
      return normalized == null || normalized.isEmpty ? 'work' : normalized;
    }
  }

  ({String prefix, String number}) _parseCode(String code) {
    final identity = parseScrapeWorkCodeIdentity(code);
    if (identity == null || !identity.isStructured) {
      throw FormatException('Unsupported work code: ' + code);
    }
    final match = RegExp(
      r'^([A-Z0-9][A-Z0-9]*)-(\d+)$',
      caseSensitive: false,
    ).firstMatch(identity.displayCode);
    if (match == null) {
      throw FormatException('Unsupported work code: ' + code);
    }
    return (prefix: match.group(1)!.toLowerCase(), number: match.group(2)!);
  }

  void _assertApproved(WorkImageUrls urls) {
    if (!isApprovedWorkImageUri(urls.card) ||
        !isApprovedWorkImageUri(urls.detail)) {
      throw StateError('Work image policy generated an unapproved endpoint.');
    }
  }
}

WorkImageUrls _renderLearnedUrls({
  required String code,
  required WorkImageLearnedRouteDescriptor descriptor,
}) {
  final parts = _learnedCodeParts(code);
  if (parts == null) {
    throw FormatException('Unsupported work code: $code');
  }
  List<String> renderPath(List<WorkImageTemplateSegment> path) {
    if (path.isEmpty || path.length > 8) {
      throw const FormatException('Invalid learned route path.');
    }
    final rendered = [
      for (final segment in path)
        segment.render(prefix: parts.prefix, number: parts.number),
    ];
    if (rendered.any(
      (segment) =>
          segment.isEmpty ||
          segment == '.' ||
          segment == '..' ||
          segment.length > 128 ||
          !RegExp(r'^[a-z0-9_.-]+$').hasMatch(segment),
    )) {
      throw const FormatException('Invalid learned route segment.');
    }
    return rendered;
  }

  final cardSegments = renderPath(descriptor.cardPath);
  final detailSegments = renderPath(descriptor.detailPath);
  final baseHost =
      descriptor.source == WorkImageLearnedRouteSource.dmmDigitalVideo
      ? 'awsimgsrc.dmm.co.jp'
      : 'image.mgstage.com';
  if (descriptor.source == WorkImageLearnedRouteSource.dmmDigitalVideo) {
    if (descriptor.variantMode != WorkImageLearnedVariantMode.dmmPsPl ||
        !_hasPrefix(cardSegments, const ['pics_dig', 'digital', 'video']) ||
        !_hasPrefix(detailSegments, const ['pics_dig', 'digital', 'video']) ||
        !_samePrefix(cardSegments, detailSegments, 4) ||
        !cardSegments.last.endsWith('ps.jpg') ||
        !detailSegments.last.endsWith('pl.jpg')) {
      throw const FormatException('Invalid DMM learned route.');
    }
  } else {
    if (descriptor.variantMode == WorkImageLearnedVariantMode.dmmPsPl ||
        cardSegments.first != 'images' ||
        detailSegments.first != 'images') {
      throw const FormatException('Invalid MGStage learned route.');
    }
    if (descriptor.variantMode == WorkImageLearnedVariantMode.mgstagePfPb &&
        (!cardSegments.last.startsWith('pf_e_') ||
            !detailSegments.last.startsWith('pb_e_') ||
            !_samePrefix(
              cardSegments,
              detailSegments,
              cardSegments.length - 1,
            ))) {
      throw const FormatException('Invalid MGStage paired route.');
    }
    if (descriptor.variantMode == WorkImageLearnedVariantMode.singleCover &&
        !_samePrefix(cardSegments, detailSegments, cardSegments.length)) {
      throw const FormatException('Invalid MGStage single-cover route.');
    }
  }

  return WorkImageUrls(
    card: Uri.https(baseHost, '/${cardSegments.join('/')}'),
    detail: Uri.https(baseHost, '/${detailSegments.join('/')}'),
    source: descriptor.source == WorkImageLearnedRouteSource.dmmDigitalVideo
        ? WorkImageSource.dmm
        : WorkImageSource.mgstage,
  );
}

bool _hasPrefix(List<String> value, List<String> expected) {
  if (value.length < expected.length) return false;
  for (var index = 0; index < expected.length; index++) {
    if (value[index] != expected[index]) return false;
  }
  return true;
}

bool _samePrefix(List<String> left, List<String> right, int length) {
  if (left.length < length || right.length < length) return false;
  for (var index = 0; index < length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

({String prefix, String number})? _learnedCodeParts(String code) {
  final canonical = canonicalizeWorkCode(code);
  if (canonical == null) return null;
  final match = RegExp(r'^([A-Z][A-Z0-9]*)-(\d+)$').firstMatch(canonical);
  if (match == null) return null;
  return (prefix: match.group(1)!.toLowerCase(), number: match.group(2)!);
}
