import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../http_safety.dart';
import 'javbus_html_parser.dart';
import 'javbus_models.dart';
import 'javbus_verification.dart';
import 'prefix_exclusion.dart';
import 'work_code.dart';
import 'work_image_downloader.dart';

abstract interface class JavBusTransport {
  Future<String> get(Uri uri);
}

abstract interface class JavBusBinarySession {
  Future<BinaryResponse> getBinary(Uri uri);
}

enum JavBusFailureKind {
  verificationRequired,
  blocked,
  rateLimited,
  timeout,
  transport,
  notFound,
  parserInvalid,
  cancelled,
  transientTransport,
}

class HttpJavBusTransport implements JavBusTransport, JavBusBinarySession {
  HttpJavBusTransport({
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
    this.maxAttempts = 2,
    this.retryDelay = const Duration(milliseconds: 300),
    Set<String> allowedHosts = const {'www.javbus.com'},
    String? initialCookieHeader,
    this.verificationHandler,
  }) : assert(maxAttempts > 0),
       _fetcher = SafeHttpFetcher(
         client: client,
         allowedHosts: allowedHosts,
         timeout: timeout,
         maxBytes: 5 * 1024 * 1024,
         initialCookieHeader: initialCookieHeader,
       );

  final SafeHttpFetcher _fetcher;
  final Duration timeout;
  final int maxAttempts;
  final Duration retryDelay;
  final JavBusVerificationHandler? verificationHandler;

  String get cookieHeader => _fetcher.cookieHeader;

  @override
  Future<String> get(Uri uri) async {
    final response = await _getResponse(uri);
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  @override
  Future<BinaryResponse> getBinary(Uri uri) async {
    final response = await _getResponse(
      uri,
      referer: uri.replace(path: '/', query: null, fragment: null),
    );
    return BinaryResponse(
      statusCode: response.statusCode,
      bodyBytes: response.bodyBytes,
    );
  }

  Future<SafeHttpResponse> _getResponse(Uri uri, {Uri? referer}) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      var attemptDelay = retryDelay;
      try {
        var response = await _fetcher.get(uri, referer: referer);
        for (
          var verificationRound = 0;
          _isVerificationPage(response.finalUri) && verificationRound < 3;
          verificationRound++
        ) {
          final source = utf8.decode(response.bodyBytes, allowMalformed: true);
          final challenge = JavBusVerificationChallenge.parse(
            source,
            pageUri: response.finalUri,
          );
          final handler = verificationHandler;
          if (challenge == null || handler == null) {
            throw JavBusVerificationRequiredException(uri);
          }
          final answers = await handler(challenge);
          if (answers == null) {
            throw const JavBusVerificationCancelledException();
          }
          await _fetcher.postForm(challenge.submitUri, {
            ...challenge.hiddenFields,
            ...challenge.submitFields,
            ...answers,
          });
          response = await _fetcher.get(uri, referer: referer);
        }
        if (_isVerificationPage(response.finalUri)) {
          throw JavBusVerificationRequiredException(uri);
        }
        if (_looksBlocked(response)) {
          throw JavBusRequestException(
            uri,
            response.statusCode,
            kind: JavBusFailureKind.blocked,
          );
        }
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response;
        }
        if (!_isTransient(response.statusCode) || attempt == maxAttempts) {
          throw JavBusRequestException(
            uri,
            response.statusCode,
            kind: _kindForStatus(response.statusCode),
          );
        }
        attemptDelay = _retryDelayFor(response);
      } on TimeoutException {
        if (attempt == maxAttempts) {
          throw JavBusRequestException(
            uri,
            null,
            kind: JavBusFailureKind.timeout,
          );
        }
      } on http.ClientException {
        if (attempt == maxAttempts) {
          throw JavBusRequestException(
            uri,
            null,
            kind: JavBusFailureKind.transport,
          );
        }
      }
      if (attemptDelay > Duration.zero) {
        await Future<void>.delayed(attemptDelay);
      }
    }
    throw StateError('Unreachable JavBus retry state.');
  }

  void close() {
    _fetcher.close();
  }

  bool _isTransient(int statusCode) {
    return statusCode == 408 || statusCode == 429 || statusCode >= 500;
  }

  Duration _retryDelayFor(SafeHttpResponse response) {
    final raw = response.headers['retry-after']?.trim();
    final seconds = raw == null ? null : double.tryParse(raw);
    if (seconds == null || seconds.isNegative) {
      return retryDelay;
    }
    final serverDelay = Duration(milliseconds: (seconds * 1000).ceil());
    return serverDelay > retryDelay ? serverDelay : retryDelay;
  }

  JavBusFailureKind _kindForStatus(int statusCode) {
    if (statusCode == 404) {
      return JavBusFailureKind.notFound;
    }
    if (statusCode == 408 || statusCode >= 500) {
      return JavBusFailureKind.transientTransport;
    }
    if (statusCode == 429) {
      return JavBusFailureKind.rateLimited;
    }
    if (statusCode == 403) {
      return JavBusFailureKind.blocked;
    }
    return JavBusFailureKind.transport;
  }

  bool _looksBlocked(SafeHttpResponse response) {
    if (response.statusCode == 403) {
      return true;
    }
    final body = utf8
        .decode(response.bodyBytes, allowMalformed: true)
        .toLowerCase();
    return body.contains('access denied') ||
        body.contains('used cloudflare to restrict access') ||
        body.contains('just a moment') ||
        body.contains('cf-chl-');
  }

  bool _isVerificationPage(Uri uri) {
    return uri.path.contains('/doc/driver-verify');
  }
}

class JavBusRequestException implements Exception {
  const JavBusRequestException(
    this.uri,
    this.statusCode, {
    this.kind = JavBusFailureKind.transport,
  });

  final Uri uri;
  final int? statusCode;
  final JavBusFailureKind kind;

  @override
  String toString() =>
      'JavBus request failed (' +
      (statusCode ?? kind.name).toString() +
      '): ' +
      uri.toString();
}

class JavBusVerificationRequiredException implements Exception {
  const JavBusVerificationRequiredException(this.uri);

  final Uri uri;

  @override
  String toString() => 'JavBus verification is required: $uri';
}

class JavBusClient {
  JavBusClient({
    required JavBusTransport transport,
    JavBusHtmlParser? parser,
    Uri? baseUri,
    this.maxPages = 100,
  }) : _transport = transport,
       _parser = parser ?? JavBusHtmlParser(),
       _baseUri = baseUri ?? Uri.parse('https://www.javbus.com/') {
    if (maxPages < 1) {
      throw ArgumentError.value(maxPages, 'maxPages', 'Must be positive.');
    }
    _validateNavigationUri(_baseUri);
  }

  final JavBusTransport _transport;
  final JavBusHtmlParser _parser;
  final Uri _baseUri;
  final int maxPages;
  List<JavBusPageIssue> _lastWorkCollectionIssues = const [];

  List<JavBusPageIssue> get lastWorkCollectionIssues =>
      List.unmodifiable(_lastWorkCollectionIssues);

  Future<void> checkConnection() async {
    await _transport.get(_baseUri);
  }

  Future<List<JavBusActressSearchResult>> searchActresses(String name) async {
    final uri = _baseUri.replace(
      pathSegments: [
        ..._baseUri.pathSegments.where((part) => part.isNotEmpty),
        'searchstar',
        name.trim(),
      ],
    );
    final source = await _transport.get(uri);
    return _parser.parseActressSearchResults(source, pageUri: uri);
  }

  Future<JavBusActressPage> fetchActressPage(Uri uri) async {
    _validateNavigationUri(uri);
    final source = await _transport.get(uri);
    return _parser.parseActressPage(source, pageUri: uri);
  }

  Future<JavBusWorkDetails> fetchWorkDetails(Uri uri) async {
    _validateNavigationUri(uri);
    final source = await _transport.get(uri);
    return _parser.parseWorkPage(source, pageUri: uri);
  }

  Future<List<JavBusWorkSummary>> fetchAllActressWorks(
    Uri actressUri, {
    PrefixExclusion? exclusions,
    bool Function()? isCancelled,
    JavBusActressPage? firstPage,
  }) async {
    return (await fetchAllActressWorksResult(
      actressUri,
      exclusions: exclusions,
      isCancelled: isCancelled,
      firstPage: firstPage,
    )).works;
  }

  Future<JavBusWorkCollectionResult> fetchAllActressWorksResult(
    Uri actressUri, {
    PrefixExclusion? exclusions,
    bool Function()? isCancelled,
    JavBusActressPage? firstPage,
  }) async {
    _lastWorkCollectionIssues = const [];
    _validateNavigationUri(actressUri);
    if (isCancelled?.call() ?? false) {
      return const JavBusWorkCollectionResult(works: []);
    }
    final resolvedFirstPage = firstPage ?? await fetchActressPage(actressUri);
    if (resolvedFirstPage.pageCount > maxPages) {
      throw JavBusPageLimitException(resolvedFirstPage.pageCount, maxPages);
    }
    final result = <JavBusWorkSummary>[];
    final issues = <JavBusPageIssue>[];
    final codeIndexes = <String, int>{};

    void append(Iterable<JavBusWorkSummary> works) {
      for (final work in works) {
        final normalizedCode = work.code.trim().toUpperCase();
        if (exclusions?.matches(normalizedCode) ?? false) {
          continue;
        }
        final existingIndex = codeIndexes[normalizedCode];
        if (existingIndex == null) {
          codeIndexes[normalizedCode] = result.length;
          result.add(work);
          continue;
        }
        final existing = result[existingIndex];
        if (isJavBusSpecialEditionCode(existing.rawCode) &&
            !isJavBusSpecialEditionCode(work.rawCode)) {
          // Keep the ordinary detail page when a special-edition page was
          // encountered earlier in pagination.
          result[existingIndex] = work;
        }
      }
    }

    append(resolvedFirstPage.works);
    for (var page = 2; page <= resolvedFirstPage.pageCount; page++) {
      if (isCancelled?.call() ?? false) {
        break;
      }
      final pageUri = Uri.parse(
        '${actressUri.toString().replaceFirst(RegExp(r'/$'), '')}/$page',
      );
      try {
        append((await fetchActressPage(pageUri)).works);
      } catch (error) {
        issues.add(
          JavBusPageIssue(
            uri: pageUri,
            kind: _pageIssueKind(error),
            error: error,
          ),
        );
      }
    }
    final collection = JavBusWorkCollectionResult(
      works: List.unmodifiable(result),
      issues: List.unmodifiable(issues),
    );
    _lastWorkCollectionIssues = collection.issues;
    return collection;
  }

  JavBusPageIssueKind _pageIssueKind(Object error) {
    if (error is JavBusVerificationRequiredException) {
      return JavBusPageIssueKind.verificationRequired;
    }
    if (error is JavBusVerificationCancelledException) {
      return JavBusPageIssueKind.cancelled;
    }
    if (error is JavBusRequestException) {
      return switch (error.kind) {
        JavBusFailureKind.verificationRequired =>
          JavBusPageIssueKind.verificationRequired,
        JavBusFailureKind.blocked => JavBusPageIssueKind.blocked,
        JavBusFailureKind.rateLimited => JavBusPageIssueKind.rateLimited,
        JavBusFailureKind.timeout => JavBusPageIssueKind.timeout,
        JavBusFailureKind.notFound => JavBusPageIssueKind.notFound,
        JavBusFailureKind.parserInvalid => JavBusPageIssueKind.parserInvalid,
        JavBusFailureKind.cancelled => JavBusPageIssueKind.cancelled,
        JavBusFailureKind.transport ||
        JavBusFailureKind.transientTransport => JavBusPageIssueKind.transport,
      };
    }
    return JavBusPageIssueKind.parserInvalid;
  }

  void close() {
    final transport = _transport;
    if (transport is HttpJavBusTransport) {
      transport.close();
    }
  }

  void _validateNavigationUri(Uri uri) {
    final expectedPort = _baseUri.hasPort ? _baseUri.port : 443;
    final actualPort = uri.hasPort ? uri.port : 443;
    if (_baseUri.scheme != 'https' ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.host.toLowerCase() != _baseUri.host.toLowerCase() ||
        actualPort != expectedPort) {
      throw UnsafeHttpUriException(uri);
    }
  }
}

class JavBusPageLimitException implements Exception {
  const JavBusPageLimitException(this.actual, this.maximum);

  final int actual;
  final int maximum;

  @override
  String toString() => 'JavBus page count $actual exceeds limit $maximum.';
}
