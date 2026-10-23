import 'dart:async';
import 'dart:convert';

import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

import '../http_safety.dart';

abstract interface class JavDbTransport {
  Future<String> get(Uri uri);
}

final class HttpJavDbTransport implements JavDbTransport {
  HttpJavDbTransport({
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
    this.maxAttempts = 2,
    this.retryDelay = const Duration(milliseconds: 300),
    Set<String> allowedHosts = const {'javdb.com', 'www.javdb.com'},
  }) : _fetcher = SafeHttpFetcher(
         client: client,
         allowedHosts: allowedHosts,
         timeout: timeout,
         maxBytes: 5 * 1024 * 1024,
         maxRedirects: 3,
       );

  final SafeHttpFetcher _fetcher;
  final Duration timeout;
  final int maxAttempts;
  final Duration retryDelay;

  @override
  Future<String> get(Uri uri) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await _fetcher.get(uri);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return utf8.decode(response.bodyBytes, allowMalformed: true);
        }
        if (!_isTransient(response.statusCode) || attempt == maxAttempts) {
          throw JavDbRequestException(uri, response.statusCode);
        }
      } on TimeoutException {
        if (attempt == maxAttempts) rethrow;
      } on http.ClientException {
        if (attempt == maxAttempts) rethrow;
      }
      if (retryDelay > Duration.zero) {
        await Future<void>.delayed(retryDelay);
      }
    }
    throw StateError('Unreachable JAVDB retry state.');
  }

  void close() => _fetcher.close();

  bool _isTransient(int statusCode) =>
      statusCode == 408 || statusCode == 429 || statusCode >= 500;
}

final class JavDbRequestException implements Exception {
  const JavDbRequestException(this.uri, this.statusCode);

  final Uri uri;
  final int statusCode;

  @override
  String toString() => 'JAVDB request failed ($statusCode): $uri';
}

final class JavDbActressResult {
  const JavDbActressResult({
    required this.name,
    required this.uri,
    this.imageUri,
  });

  final String name;
  final Uri uri;
  final Uri? imageUri;
}

final class JavDbActressDirectoryPage {
  const JavDbActressDirectoryPage({
    required this.items,
    required this.page,
    this.hasNext = false,
  });

  final List<JavDbActressResult> items;
  final int page;
  final bool hasNext;
}

final class JavDbClient {
  JavDbClient({required JavDbTransport transport, Uri? baseUri})
    : _transport = transport,
      _baseUri = baseUri ?? Uri.parse('https://javdb.com/') {
    _validate(_baseUri);
  }

  final JavDbTransport _transport;
  final Uri _baseUri;

  Future<void> checkConnection() async {
    await _transport.get(_baseUri);
  }

  Future<JavDbActressDirectoryPage> fetchActors({int page = 1}) async {
    final uri = _pageUri('/actors', page);
    final source = await _transport.get(uri);
    return _parse(source, pageUri: uri, page: page);
  }

  Future<JavDbActressDirectoryPage> searchActresses(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const JavDbActressDirectoryPage(items: [], page: 1);
    }
    final uri = _baseUri.replace(
      path: '/search',
      queryParameters: {'q': trimmed},
    );
    final source = await _transport.get(uri);
    return _parse(source, pageUri: uri, page: 1);
  }

  bool acceptsImageUri(Uri uri) {
    final port = uri.hasPort ? uri.port : 443;
    return uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        (uri.host.toLowerCase() == 'javdb.com' ||
            uri.host.toLowerCase() == 'www.javdb.com') &&
        port == 443;
  }

  void close() {
    final transport = _transport;
    if (transport is HttpJavDbTransport) transport.close();
  }

  JavDbActressDirectoryPage _parse(
    String source, {
    required Uri pageUri,
    required int page,
  }) {
    final document = html.parse(source);
    final result = <JavDbActressResult>[];
    final seen = <String>{};
    for (final anchor in document.querySelectorAll('a[href*="/actors/"]')) {
      final href = anchor.attributes['href'];
      final name = _clean(anchor.text);
      if (href == null || name == null) continue;
      final uri = pageUri.resolve(href);
      if (!_isSafe(uri) || !seen.add(uri.toString())) continue;
      final imageValue = _clean(
        anchor.querySelector('img')?.attributes['src'] ??
            anchor.querySelector('img')?.attributes['data-src'],
      );
      final image = imageValue == null ? null : pageUri.resolve(imageValue);
      result.add(
        JavDbActressResult(
          name: name,
          uri: uri,
          imageUri: image != null && acceptsImageUri(image) ? image : null,
        ),
      );
    }
    var maximum = page;
    for (final anchor in document.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'];
      if (href == null) continue;
      final value = int.tryParse(Uri.parse(href).queryParameters['page'] ?? '');
      if (value != null && value > maximum) maximum = value;
    }
    return JavDbActressDirectoryPage(
      items: List.unmodifiable(result),
      page: page,
      hasNext: maximum > page,
    );
  }

  Uri _pageUri(String path, int page) => _baseUri.replace(
    path: path,
    queryParameters: page == 1 ? null : {'page': '$page'},
  );

  bool _isSafe(Uri uri) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      uri.host.toLowerCase() == _baseUri.host.toLowerCase();

  void _validate(Uri uri) {
    if (!_isSafe(uri)) throw ArgumentError.value(uri, 'uri');
  }

  String? _clean(String? value) {
    final cleaned = value?.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }
}
