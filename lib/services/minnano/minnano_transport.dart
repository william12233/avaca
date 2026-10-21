import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../http_safety.dart';

abstract interface class MinnanoTransport {
  Future<String> get(Uri uri);
}

final class HttpMinnanoTransport implements MinnanoTransport {
  HttpMinnanoTransport({
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
    this.maxAttempts = 2,
    this.retryDelay = const Duration(milliseconds: 300),
  }) : assert(maxAttempts > 0),
       _fetcher = SafeHttpFetcher(
         client: client,
         allowedHosts: const {'www.minnano-av.com'},
         timeout: timeout,
         maxBytes: 5 * 1024 * 1024,
       );

  final SafeHttpFetcher _fetcher;
  final Duration timeout;
  final int maxAttempts;
  final Duration retryDelay;

  @override
  Future<String> get(Uri uri) async {
    final response = await _getResponse(uri);
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  Future<SafeHttpResponse> _getResponse(Uri uri) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await _fetcher.get(uri);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response;
        }
        if (!_isTransient(response.statusCode) || attempt == maxAttempts) {
          throw MinnanoRequestException(uri, response.statusCode);
        }
      } on TimeoutException {
        if (attempt == maxAttempts) {
          rethrow;
        }
      } on http.ClientException {
        if (attempt == maxAttempts) {
          rethrow;
        }
      }
      if (retryDelay > Duration.zero) {
        await Future<void>.delayed(retryDelay);
      }
    }
    throw StateError('Unreachable Minnano retry state.');
  }

  void close() => _fetcher.close();

  bool _isTransient(int statusCode) {
    return statusCode == 408 || statusCode == 429 || statusCode >= 500;
  }
}

final class MinnanoRequestException implements Exception {
  const MinnanoRequestException(this.uri, this.statusCode);

  final Uri uri;
  final int statusCode;

  @override
  String toString() => 'Minnano request failed ($statusCode): $uri';
}
