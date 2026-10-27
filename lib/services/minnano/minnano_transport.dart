import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../http_safety.dart';

abstract interface class MinnanoTransport {
  Future<String> get(Uri uri);
}

enum MinnanoFailureKind {
  blocked,
  rateLimited,
  timeout,
  transport,
  notFound,
  parserInvalid,
  cancelled,
  transientTransport,
}

final class HttpMinnanoTransport implements MinnanoTransport {
  HttpMinnanoTransport({
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
    this.maxAttempts = 2,
    this.retryDelay = const Duration(milliseconds: 300),
    this.requestDelay = const Duration(milliseconds: 250),
    String? initialCookieHeader,
  }) : assert(maxAttempts > 0),
       _fetcher = SafeHttpFetcher(
         client: client,
         allowedHosts: const {'www.minnano-av.com'},
         timeout: timeout,
         maxBytes: 5 * 1024 * 1024,
         defaultHeaders: const {
           'user-agent':
               'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 '
               '(KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36',
           'accept':
               'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
           'accept-language': 'ja,en-US;q=0.9,en;q=0.8',
         },
         initialCookieHeader: initialCookieHeader,
       );

  final SafeHttpFetcher _fetcher;
  final Duration timeout;
  final int maxAttempts;
  final Duration retryDelay;
  final Duration requestDelay;
  Future<void> _requestTail = Future<void>.value();
  DateTime? _lastRequestAt;

  @override
  Future<String> get(Uri uri) {
    final completer = Completer<String>();
    _requestTail = _requestTail.then<void>((_) async {
      try {
        final response = await _getResponse(uri);
        completer.complete(
          utf8.decode(response.bodyBytes, allowMalformed: true),
        );
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<SafeHttpResponse> _getResponse(Uri uri) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      var attemptDelay = retryDelay;
      try {
        await _waitForRequestSlot();
        final response = await _fetcher.get(uri);
        if (_looksBlocked(response)) {
          throw MinnanoRequestException(
            uri,
            response.statusCode,
            kind: MinnanoFailureKind.blocked,
          );
        }
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response;
        }
        if (!_isTransient(response.statusCode) || attempt == maxAttempts) {
          throw MinnanoRequestException(
            uri,
            response.statusCode,
            kind: _kindForStatus(response.statusCode),
          );
        }
        attemptDelay = _retryDelayFor(response);
      } on MinnanoRequestException catch (error) {
        if (error.kind == MinnanoFailureKind.blocked ||
            error.kind == MinnanoFailureKind.notFound ||
            error.kind == MinnanoFailureKind.parserInvalid ||
            attempt == maxAttempts) {
          rethrow;
        }
      } on TimeoutException {
        if (attempt == maxAttempts) {
          throw MinnanoRequestException(
            uri,
            null,
            kind: MinnanoFailureKind.timeout,
          );
        }
      } on http.ClientException {
        if (attempt == maxAttempts) {
          throw MinnanoRequestException(
            uri,
            null,
            kind: MinnanoFailureKind.transport,
          );
        }
      } on OSError {
        if (attempt == maxAttempts) {
          throw MinnanoRequestException(
            uri,
            null,
            kind: MinnanoFailureKind.transport,
          );
        }
      } on UnsafeHttpUriException {
        rethrow;
      } on HttpBodyTooLargeException {
        throw MinnanoRequestException(
          uri,
          null,
          kind: MinnanoFailureKind.parserInvalid,
        );
      }
      if (attemptDelay > Duration.zero) {
        await Future<void>.delayed(attemptDelay);
      }
    }
    throw StateError('Unreachable Minnano retry state.');
  }

  void close() => _fetcher.close();

  Future<void> _waitForRequestSlot() async {
    final last = _lastRequestAt;
    if (last != null && requestDelay > Duration.zero) {
      final remaining = requestDelay - DateTime.now().difference(last);
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }
    }
    _lastRequestAt = DateTime.now();
  }

  bool _isTransient(int statusCode) {
    return statusCode == 408 || statusCode == 429 || statusCode >= 500;
  }

  Duration _retryDelayFor(SafeHttpResponse response) {
    final raw = response.headers['retry-after']?.trim();
    final seconds = raw == null ? null : double.tryParse(raw);
    if (seconds == null || seconds.isNegative) return retryDelay;
    final serverDelay = Duration(milliseconds: (seconds * 1000).ceil());
    return serverDelay > retryDelay ? serverDelay : retryDelay;
  }

  MinnanoFailureKind _kindForStatus(int statusCode) {
    if (statusCode == 404) return MinnanoFailureKind.notFound;
    if (statusCode == 408 || statusCode >= 500) {
      return MinnanoFailureKind.transientTransport;
    }
    if (statusCode == 429) return MinnanoFailureKind.rateLimited;
    if (statusCode == 403) return MinnanoFailureKind.blocked;
    return MinnanoFailureKind.transport;
  }

  bool _looksBlocked(SafeHttpResponse response) {
    if (response.statusCode == 403) return true;
    final body = utf8
        .decode(response.bodyBytes, allowMalformed: true)
        .toLowerCase();
    return body.contains('access denied') ||
        body.contains('just a moment') ||
        body.contains('cf-chl-') ||
        body.contains('cloudflare ray id');
  }
}

final class MinnanoRequestException implements Exception {
  const MinnanoRequestException(
    this.uri,
    this.statusCode, {
    this.kind = MinnanoFailureKind.transport,
  });

  final Uri uri;
  final int? statusCode;
  final MinnanoFailureKind kind;

  @override
  String toString() {
    final label = switch (kind) {
      MinnanoFailureKind.blocked => 'blocked',
      MinnanoFailureKind.rateLimited => 'rate limited',
      MinnanoFailureKind.timeout => 'timed out',
      MinnanoFailureKind.notFound => 'not found',
      MinnanoFailureKind.parserInvalid => 'invalid response',
      MinnanoFailureKind.transientTransport => 'temporarily unavailable',
      MinnanoFailureKind.cancelled => 'cancelled',
      MinnanoFailureKind.transport => 'failed',
    };
    final status = statusCode == null ? '' : ' ($statusCode)';
    return 'Minnano request $label$status: $uri';
  }
}
