import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as image;

import '../http_safety.dart';
import '../safe_image.dart';
import '../scrape/work_code_canonicalizer.dart';
import 'prefix_route_repository.dart';
import 'work_image_learned_route.dart';
import 'work_image_policy.dart';
import 'work_image_prefix_router.dart';
import 'work_image_route_resolver.dart';

class BinaryResponse {
  const BinaryResponse({required this.statusCode, required this.bodyBytes});

  final int statusCode;
  final List<int> bodyBytes;

  Uint8List get bytes {
    return bodyBytes is Uint8List
        ? bodyBytes as Uint8List
        : Uint8List.fromList(bodyBytes);
  }
}

abstract interface class BinaryTransport {
  Future<BinaryResponse> get(Uri uri);
}

class HttpBinaryTransport implements BinaryTransport {
  HttpBinaryTransport({
    http.Client? client,
    Set<String> allowedHosts = const {
      'awsimgsrc.dmm.co.jp',
      'image.mgstage.com',
    },
    Duration timeout = const Duration(seconds: 20),
    int maxBytes = 15 * 1024 * 1024,
  }) : _fetcher = SafeHttpFetcher(
         client: client,
         allowedHosts: allowedHosts,
         timeout: timeout,
         maxBytes: maxBytes,
       );

  final SafeHttpFetcher _fetcher;

  @override
  Future<BinaryResponse> get(Uri uri) async {
    final response = await _fetcher.get(uri);
    return BinaryResponse(
      statusCode: response.statusCode,
      bodyBytes: response.bodyBytes,
    );
  }

  void close() {
    _fetcher.close();
  }
}

class DownloadedWorkImage {
  const DownloadedWorkImage({required this.bytes, required this.sourceUri});

  final Uint8List bytes;
  final Uri sourceUri;
}

enum WorkImageDownloadFailureKind {
  definitiveRouteMiss,
  transientNetwork,
  policyViolation,
}

class WorkImageDownloadException implements Exception {
  const WorkImageDownloadException(
    this.uri, {
    this.kind = WorkImageDownloadFailureKind.definitiveRouteMiss,
    this.statusCode,
    this.cause,
  });

  final Uri uri;
  final WorkImageDownloadFailureKind kind;
  final int? statusCode;
  final Object? cause;

  @override
  String toString() => 'Could not download a valid work image: $uri';
}

class WorkImageDownloader {
  WorkImageDownloader({
    BinaryTransport? transport,
    WorkImagePolicy policy = const WorkImagePolicy(),
    PrefixRouteRepository? routeRepository,
    WorkImagePrefixRouter? routeRouter,
    this.evidenceRouteLearningEnabled = true,
  }) : _transport = transport ?? HttpBinaryTransport(),
       _policy = policy {
    final repository = routeRepository ?? PrefixRouteRepository.inMemory();
    if (routeRouter != null && routeRouter.repository != repository) {
      throw ArgumentError(
        'routeRouter and routeRepository must use the same repository.',
      );
    }
    _routeRouter = routeRouter ?? WorkImagePrefixRouter(repository: repository);
  }

  final BinaryTransport _transport;
  final WorkImagePolicy _policy;
  final bool evidenceRouteLearningEnabled;
  late final WorkImagePrefixRouter _routeRouter;
  final WorkImageEvidenceRouteParser _evidenceParser =
      const WorkImageEvidenceRouteParser();

  String fileNameFor({
    required String code,
    required WorkImageVariant variant,
  }) {
    return _policy.fileNameFor(code: code, variant: variant);
  }

  void close() {
    final transport = _transport;
    if (transport is HttpBinaryTransport) {
      transport.close();
    }
  }

  Future<DownloadedWorkImage> fetch({
    required String code,
    String? studio,
    String? publisher,
    List<Uri> originalImageEvidenceUris = const [],
    WorkImageRouteResolution? route,
    required WorkImageVariant variant,
  }) async {
    if (route != null) {
      final family = route.family;
      if (family == null) {
        throw WorkImageDownloadException(
          _diagnosticUri,
          kind: WorkImageDownloadFailureKind.policyViolation,
        );
      }
      try {
        final result = await _probeFamily(
          code: code,
          family: family,
          variant: variant,
        );
        return _downloaded(result);
      } on WorkImageRouteProbeException catch (error) {
        throw _downloadException(error);
      }
    }

    final prefix = canonicalWorkCodePrefix(code);
    if (prefix == null) {
      throw WorkImageDownloadException(
        _diagnosticUri,
        kind: WorkImageDownloadFailureKind.policyViolation,
      );
    }

    final canonicalCode =
        canonicalizeWorkCode(code) ?? code.trim().toUpperCase();
    final repository = _routeRouter.repository;
    await repository.ensureLoaded();
    final legacyRuleAtStart = repository.ruleFor(prefix);

    if (evidenceRouteLearningEnabled &&
        legacyRuleAtStart?.manualOverride == null) {
      final learned = await _tryLearnedCandidates(
        code: canonicalCode,
        prefix: prefix,
        variant: variant,
      );
      if (learned != null) return learned;
    }

    // An unknown Prefix has no trustworthy legacy route ordering.  When the
    // source page supplied official image evidence, use that evidence before
    // trying the six historical guessed families.
    if (evidenceRouteLearningEnabled &&
        legacyRuleAtStart == null &&
        originalImageEvidenceUris.isNotEmpty) {
      final evidenceResult = await _tryEvidenceRoutes(
        code: canonicalCode,
        prefix: prefix,
        variant: variant,
        evidenceUris: originalImageEvidenceUris,
      );
      if (evidenceResult != null) return evidenceResult;
    }

    try {
      final decision = await _routeRouter.resolve(
        prefix: prefix,
        variant: variant,
        probeWorkCode: canonicalCode,
        probe: (family) =>
            _probeFamily(code: code, family: family, variant: variant),
      );
      final probeResult = decision.probeResult;
      if (probeResult != null &&
          decision.probeVariant == variant &&
          decision.probeWorkCode == canonicalCode) {
        return _downloaded(probeResult);
      }
      try {
        return _downloaded(
          await _probeFamily(
            code: code,
            family: decision.family,
            variant: variant,
          ),
        );
      } on WorkImageRouteProbeException catch (error) {
        if (error.kind != WorkImageRouteProbeFailureKind.definitiveMiss) {
          rethrow;
        }
        // A shared resolution can prove the family with the other variant,
        // but this work/variant may still be a genuine miss. Re-enter the
        // per-prefix router so it records the miss and probes fallback
        // families instead of treating the shared family as infallible.
        final fallback = await _routeRouter.resolve(
          prefix: prefix,
          variant: variant,
          probeWorkCode: canonicalCode,
          probe: (family) =>
              _probeFamily(code: code, family: family, variant: variant),
        );
        final fallbackResult = fallback.probeResult;
        if (fallbackResult != null &&
            fallback.probeVariant == variant &&
            fallback.probeWorkCode == canonicalCode) {
          return _downloaded(fallbackResult);
        }
        return _downloaded(
          await _probeFamily(
            code: code,
            family: fallback.family,
            variant: variant,
          ),
        );
      }
    } on WorkImageRouteProbeException catch (error) {
      throw _downloadException(error);
    } on WorkImageRouteResolutionException catch (error) {
      if (evidenceRouteLearningEnabled &&
          originalImageEvidenceUris.isNotEmpty &&
          legacyRuleAtStart?.manualOverride == null) {
        final evidenceResult = await _tryEvidenceRoutes(
          code: canonicalCode,
          prefix: prefix,
          variant: variant,
          evidenceUris: originalImageEvidenceUris,
        );
        if (evidenceResult != null) return evidenceResult;
      }
      throw WorkImageDownloadException(
        error.lastUri ?? _diagnosticUri,
        kind: WorkImageDownloadFailureKind.definitiveRouteMiss,
      );
    }
  }

  Future<DownloadedWorkImage?> _tryLearnedCandidates({
    required String code,
    required String prefix,
    required WorkImageVariant variant,
  }) async {
    final candidates = _routeRouter.repository
        .orderedLearnedCandidatesFor(prefix)
        .where((candidate) => candidate.isUsable)
        .toList(growable: false);
    for (final candidate in candidates) {
      final revisionToken = _routeRouter.repository.revisionTokenFor(prefix);
      try {
        final result = await _probeLearnedDescriptor(
          code: code,
          descriptor: candidate.descriptor,
          variant: variant,
        );
        await _routeRouter.repository.recordLearnedSuccess(
          prefix: prefix,
          descriptor: candidate.descriptor,
          workCode: code,
          evidenceUri: result.sourceUri,
          expectedRevisionToken: revisionToken,
        );
        return _downloaded(result);
      } on WorkImageRouteProbeException catch (error) {
        if (error.kind != WorkImageRouteProbeFailureKind.definitiveMiss) {
          throw _downloadException(error);
        }
        await _routeRouter.repository.recordLearnedDefinitiveFailure(
          prefix: prefix,
          descriptor: candidate.descriptor,
          workCode: code,
          expectedRevisionToken: revisionToken,
        );
      }
    }
    return null;
  }

  Future<DownloadedWorkImage?> _tryEvidenceRoutes({
    required String code,
    required String prefix,
    required WorkImageVariant variant,
    required List<Uri> evidenceUris,
  }) async {
    final descriptors = <String, _EvidenceDescriptor>{};
    for (final evidenceUri in evidenceUris) {
      final descriptor = _evidenceParser.parse(
        evidenceUri: evidenceUri,
        code: code,
      );
      if (descriptor == null) continue;
      final key = descriptor.canonicalKey;
      final existing = descriptors[key];
      if (existing == null ||
          evidenceUri.toString().compareTo(existing.evidenceUri.toString()) <
              0) {
        descriptors[key] = _EvidenceDescriptor(
          descriptor: descriptor,
          evidenceUri: evidenceUri,
        );
      }
    }
    final ordered = descriptors.values.toList()
      ..sort(
        (left, right) => left.descriptor.canonicalKey.compareTo(
          right.descriptor.canonicalKey,
        ),
      );
    for (final item in ordered) {
      final revisionToken = _routeRouter.repository.revisionTokenFor(prefix);
      try {
        final result = await _probeLearnedDescriptor(
          code: code,
          descriptor: item.descriptor,
          variant: variant,
        );
        await _routeRouter.repository.recordLearnedSuccess(
          prefix: prefix,
          descriptor: item.descriptor,
          workCode: code,
          evidenceUri: item.evidenceUri,
          expectedRevisionToken: revisionToken,
        );
        return _downloaded(result);
      } on WorkImageRouteProbeException catch (error) {
        if (error.kind != WorkImageRouteProbeFailureKind.definitiveMiss) {
          throw _downloadException(error);
        }
        // Evidence is authoritative for route shape only; a definitive miss
        // still allows the next independently proven descriptor or the legacy
        // family fallback to run.
      }
    }
    return null;
  }

  Future<DownloadedWorkImage> downloadToFile({
    required String code,
    String? studio,
    String? publisher,
    List<Uri> originalImageEvidenceUris = const [],
    WorkImageRouteResolution? route,
    required WorkImageVariant variant,
    required String targetPath,
  }) async {
    final downloaded = await fetch(
      code: code,
      studio: studio,
      publisher: publisher,
      originalImageEvidenceUris: originalImageEvidenceUris,
      route: route,
      variant: variant,
    );
    final file = File(targetPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(downloaded.bytes, flush: true);
    return downloaded;
  }

  Future<WorkImageRouteProbeResult> _probeFamily({
    required String code,
    required WorkImageNormalizationFamily family,
    required WorkImageVariant variant,
  }) async {
    late final Uri uri;
    try {
      final urls = _policy.urlsForFamily(code: code, family: family);
      uri = urls.forVariant(variant);
    } on FormatException catch (error) {
      throw WorkImageRouteProbeException(
        uri: _diagnosticUri,
        kind: WorkImageRouteProbeFailureKind.definitiveMiss,
        cause: error,
        recordFailure: false,
      );
    } on Object catch (error) {
      throw WorkImageRouteProbeException(
        uri: _diagnosticUri,
        kind: WorkImageRouteProbeFailureKind.policyViolation,
        cause: error,
      );
    }
    if (!isApprovedWorkImageUri(uri)) {
      throw WorkImageRouteProbeException(
        uri: uri,
        kind: WorkImageRouteProbeFailureKind.policyViolation,
      );
    }

    return _probeUri(uri);
  }

  Future<WorkImageRouteProbeResult> _probeLearnedDescriptor({
    required String code,
    required WorkImageLearnedRouteDescriptor descriptor,
    required WorkImageVariant variant,
  }) async {
    late final Uri uri;
    try {
      final urls = _policy.urlsForLearnedDescriptor(
        code: code,
        descriptor: descriptor,
      );
      uri = urls.forVariant(variant);
    } on Object catch (error) {
      throw WorkImageRouteProbeException(
        uri: _diagnosticUri,
        kind: WorkImageRouteProbeFailureKind.policyViolation,
        cause: error,
      );
    }
    if (!isApprovedGeneratedLearnedWorkImageUri(
      uri: uri,
      code: code,
      descriptor: descriptor,
      variant: variant,
    )) {
      throw WorkImageRouteProbeException(
        uri: uri,
        kind: WorkImageRouteProbeFailureKind.policyViolation,
      );
    }
    return _probeUri(uri);
  }

  Future<WorkImageRouteProbeResult> _probeUri(Uri uri) async {
    late final BinaryResponse response;
    try {
      response = await _transport.get(uri);
    } on Object catch (error) {
      throw WorkImageRouteProbeException(
        uri: uri,
        kind: _isTransientTransportError(error)
            ? WorkImageRouteProbeFailureKind.transientNetwork
            : WorkImageRouteProbeFailureKind.policyViolation,
        cause: error,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WorkImageRouteProbeException(
        uri: uri,
        kind: _failureKindForStatus(response.statusCode),
        statusCode: response.statusCode,
      );
    }
    if (!_isValid(response)) {
      throw WorkImageRouteProbeException(
        uri: uri,
        kind: WorkImageRouteProbeFailureKind.definitiveMiss,
        statusCode: response.statusCode,
      );
    }
    return WorkImageRouteProbeResult(bytes: response.bytes, sourceUri: uri);
  }

  DownloadedWorkImage _downloaded(WorkImageRouteProbeResult result) {
    return DownloadedWorkImage(
      bytes: result.bytes,
      sourceUri: result.sourceUri,
    );
  }

  WorkImageDownloadException _downloadException(
    WorkImageRouteProbeException error,
  ) {
    final kind = switch (error.kind) {
      WorkImageRouteProbeFailureKind.definitiveMiss =>
        WorkImageDownloadFailureKind.definitiveRouteMiss,
      WorkImageRouteProbeFailureKind.transientNetwork =>
        WorkImageDownloadFailureKind.transientNetwork,
      WorkImageRouteProbeFailureKind.policyViolation =>
        WorkImageDownloadFailureKind.policyViolation,
    };
    return WorkImageDownloadException(
      error.uri,
      kind: kind,
      statusCode: error.statusCode,
      cause: error.cause,
    );
  }

  WorkImageRouteProbeFailureKind _failureKindForStatus(int statusCode) {
    if (statusCode == 408 ||
        statusCode == 425 ||
        statusCode == 429 ||
        statusCode >= 500) {
      return WorkImageRouteProbeFailureKind.transientNetwork;
    }
    return WorkImageRouteProbeFailureKind.definitiveMiss;
  }

  bool _isTransientTransportError(Object error) {
    return error is TimeoutException ||
        error is SocketException ||
        error is HandshakeException ||
        error is HttpException ||
        error is http.ClientException;
  }

  bool _isValid(BinaryResponse response) {
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        response.bodyBytes.isEmpty) {
      return false;
    }
    try {
      final bytes = response.bytes;
      if (!isSafeDecodableImage(bytes)) {
        return false;
      }
      final decoder = image.findDecoderForData(bytes);
      if (decoder == null) {
        return false;
      }
      final info = decoder.startDecode(bytes);
      return info != null && (info.width != 90 || info.height != 122);
    } on Object {
      return false;
    }
  }

  static final Uri _diagnosticUri = Uri.parse(
    'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/',
  );
}

final class _EvidenceDescriptor {
  const _EvidenceDescriptor({
    required this.descriptor,
    required this.evidenceUri,
  });

  final WorkImageLearnedRouteDescriptor descriptor;
  final Uri evidenceUri;
}
