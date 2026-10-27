import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class SafeHttpResponse {
  const SafeHttpResponse({
    required this.statusCode,
    required this.bodyBytes,
    required this.finalUri,
    this.headers = const {},
  });

  final int statusCode;
  final Uint8List bodyBytes;
  final Uri finalUri;
  final Map<String, String> headers;
}

class UnsafeHttpUriException implements Exception {
  const UnsafeHttpUriException(this.uri);

  final Uri uri;

  @override
  String toString() => 'HTTP URI is not allowed: $uri';
}

class HttpBodyTooLargeException implements Exception {
  const HttpBodyTooLargeException(this.uri, this.maxBytes);

  final Uri uri;
  final int maxBytes;

  @override
  String toString() => 'HTTP body exceeds $maxBytes bytes: $uri';
}

class SafeHttpFetcher {
  SafeHttpFetcher({
    http.Client? client,
    required Set<String> allowedHosts,
    this.timeout = const Duration(seconds: 20),
    this.maxBytes = 5 * 1024 * 1024,
    this.maxRedirects = 3,
    Map<String, String> defaultHeaders = const {},
    String? initialCookieHeader,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _allowedHosts = allowedHosts
           .map((host) => host.trim().toLowerCase())
           .toSet() {
    _defaultHeaders.addAll(defaultHeaders);
    _importCookies(initialCookieHeader);
  }

  final http.Client _client;
  final bool _ownsClient;
  final Set<String> _allowedHosts;
  final Map<String, String> _defaultHeaders = {};
  final Map<String, String> _cookies = {};
  final Duration timeout;
  final int maxBytes;
  final int maxRedirects;

  String get cookieHeader =>
      _cookies.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');

  Future<SafeHttpResponse> get(Uri uri, {Uri? referer}) =>
      _request('GET', uri, referer: referer);

  Future<SafeHttpResponse> postForm(Uri uri, Map<String, String> fields) =>
      _request('POST', uri, fields: fields);

  Future<SafeHttpResponse> _request(
    String initialMethod,
    Uri uri, {
    Map<String, String>? fields,
    Uri? referer,
  }) async {
    final stopwatch = Stopwatch()..start();
    var current = uri;
    var method = initialMethod;
    var currentFields = fields;
    for (var redirects = 0; redirects <= maxRedirects; redirects++) {
      _validate(current);
      final request = http.Request(method, current)..followRedirects = false;
      if (_defaultHeaders.isNotEmpty) {
        request.headers.addAll(_defaultHeaders);
      }
      if (referer != null) {
        _validate(referer);
        request.headers['referer'] = referer.toString();
      }
      if (_cookies.isNotEmpty) {
        request.headers['cookie'] = cookieHeader;
      }
      if (method == 'POST' && currentFields != null) {
        request.bodyFields = currentFields;
      }
      final response = await _client
          .send(request)
          .timeout(_remaining(stopwatch));
      _captureCookies(response);

      if (_isRedirect(response.statusCode)) {
        final subscription = response.stream.listen((_) {});
        await subscription.cancel();
        final location = response.headers['location'];
        if (location == null || redirects == maxRedirects) {
          throw UnsafeHttpUriException(current);
        }
        current = current.resolve(location);
        _validate(current);
        if (response.statusCode == 301 ||
            response.statusCode == 302 ||
            response.statusCode == 303) {
          method = 'GET';
          currentFields = null;
        }
        continue;
      }

      final declaredLength = response.contentLength;
      if (declaredLength != null && declaredLength > maxBytes) {
        throw HttpBodyTooLargeException(current, maxBytes);
      }

      final builder = BytesBuilder(copy: false);
      var received = 0;
      final iterator = StreamIterator<List<int>>(response.stream);
      try {
        while (await iterator.moveNext().timeout(_remaining(stopwatch))) {
          final chunk = iterator.current;
          received += chunk.length;
          if (received > maxBytes) {
            throw HttpBodyTooLargeException(current, maxBytes);
          }
          builder.add(chunk);
        }
      } finally {
        await iterator.cancel();
      }
      return SafeHttpResponse(
        statusCode: response.statusCode,
        bodyBytes: builder.takeBytes(),
        finalUri: current,
        headers: Map.unmodifiable(response.headers),
      );
    }
    throw UnsafeHttpUriException(current);
  }

  void _captureCookies(http.StreamedResponse response) {
    final values = response.headersSplitValues['set-cookie'] ?? const [];
    for (final value in values) {
      final pair = value.split(';').first.trim();
      final separator = pair.indexOf('=');
      if (separator <= 0) {
        continue;
      }
      final name = pair.substring(0, separator).trim();
      final cookieValue = pair.substring(separator + 1).trim();
      if (cookieValue.isEmpty) {
        _cookies.remove(name);
      } else {
        _cookies[name] = cookieValue;
      }
    }
  }

  void _importCookies(String? header) {
    if (header == null) {
      return;
    }
    for (final value in header.split(';')) {
      final pair = value.trim();
      final separator = pair.indexOf('=');
      if (separator > 0) {
        _cookies[pair.substring(0, separator).trim()] = pair
            .substring(separator + 1)
            .trim();
      }
    }
  }

  Duration _remaining(Stopwatch stopwatch) {
    final remaining = timeout - stopwatch.elapsed;
    if (remaining <= Duration.zero) {
      throw TimeoutException('HTTP request exceeded $timeout.');
    }
    return remaining;
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }

  void _validate(Uri uri) {
    final host = uri.host.toLowerCase();
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443) ||
        !_allowedHosts.contains(host)) {
      throw UnsafeHttpUriException(uri);
    }
  }

  bool _isRedirect(int statusCode) {
    return statusCode == 301 ||
        statusCode == 302 ||
        statusCode == 303 ||
        statusCode == 307 ||
        statusCode == 308;
  }
}
