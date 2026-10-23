import 'minnano_html_parser.dart';
import 'minnano_models.dart';
import 'minnano_transport.dart';

final class MinnanoClient {
  MinnanoClient({
    required MinnanoTransport transport,
    MinnanoHtmlParser? parser,
    Uri? baseUri,
    this.maxPages = 100,
  }) : _transport = transport,
       _parser = parser ?? MinnanoHtmlParser(),
       _baseUri = baseUri ?? Uri.parse('https://www.minnano-av.com/') {
    if (maxPages < 1) {
      throw ArgumentError.value(maxPages, 'maxPages', 'Must be positive.');
    }
    _validateNavigationUri(_baseUri);
  }

  final MinnanoTransport _transport;
  final MinnanoHtmlParser _parser;
  final Uri _baseUri;
  final int maxPages;

  Future<void> checkConnection() async {
    await _transport.get(_baseUri);
  }

  Future<List<ScrapeSearchResult>> searchActresses(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return const [];
    }
    final uri = _baseUri.replace(
      path: '/search_result.php',
      queryParameters: {
        'search_scope': 'actress',
        'search_word': trimmed,
        'search': ' Go ',
      },
    );
    final source = await _transport.get(uri);
    return _parser.parseActressSearchResults(source, pageUri: uri);
  }

  Future<MinnanoActressPage> fetchActressPage(Uri uri) async {
    _validateNavigationUri(uri);
    final source = await _transport.get(uri);
    return _parser.parseActressPage(source, pageUri: uri);
  }

  Future<MinnanoWorkDetails> fetchWorkDetails(Uri uri) async {
    _validateNavigationUri(uri);
    final source = await _transport.get(uri);
    return _parser.parseWorkPage(source, pageUri: uri);
  }

  Future<List<MinnanoWorkSummary>> fetchAllActressWorks(
    Uri actressUri, {
    required MinnanoActressPage firstPage,
    bool Function()? isCancelled,
  }) async {
    _validateNavigationUri(actressUri);
    if (isCancelled?.call() ?? false) {
      return const [];
    }
    if (firstPage.pageCount > maxPages) {
      throw MinnanoPageLimitException(firstPage.pageCount, maxPages);
    }
    final result = <MinnanoWorkSummary>[];
    final seenUris = <String>{};

    void append(Iterable<MinnanoWorkSummary> works) {
      for (final work in works) {
        if (seenUris.add(work.detailUri.toString())) {
          result.add(work);
        }
      }
    }

    append(firstPage.works);
    for (var page = 2; page <= firstPage.pageCount; page++) {
      if (isCancelled?.call() ?? false) {
        break;
      }
      final pageUri = _pageUri(actressUri, page);
      final parsed = await fetchActressPage(pageUri);
      append(parsed.works);
    }
    return List.unmodifiable(result);
  }

  bool acceptsImageUri(Uri uri) {
    final port = uri.hasPort ? uri.port : 443;
    final path = uri.path.toLowerCase();
    return uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        uri.host.toLowerCase() == _baseUri.host.toLowerCase() &&
        port == 443 &&
        path.startsWith('/p_actress_125_125/');
  }

  void close() {
    final transport = _transport;
    if (transport is HttpMinnanoTransport) {
      transport.close();
    }
  }

  Uri _pageUri(Uri actressUri, int page) {
    final actressId = RegExp(
      r'actress(\d+)\.html',
      caseSensitive: false,
    ).firstMatch(actressUri.path)?.group(1);
    if (actressId != null) {
      return _baseUri.replace(
        path: '/actress.php',
        queryParameters: {'actress_id': actressId, 'page': '$page'},
      );
    }
    final path = actressUri.path.replaceFirst(RegExp(r'/$'), '');
    return actressUri.replace(path: '$path/$page', query: null, fragment: null);
  }

  void _validateNavigationUri(Uri uri) {
    final expectedPort = _baseUri.hasPort ? _baseUri.port : 443;
    final actualPort = uri.hasPort ? uri.port : 443;
    if (_baseUri.scheme != 'https' ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.host.toLowerCase() != _baseUri.host.toLowerCase() ||
        actualPort != expectedPort) {
      throw const MinnanoUnsafeUriException();
    }
  }
}

final class MinnanoPageLimitException implements Exception {
  const MinnanoPageLimitException(this.actual, this.maximum);

  final int actual;
  final int maximum;

  @override
  String toString() => 'Minnano page count $actual exceeds limit $maximum.';
}

final class MinnanoUnsafeUriException implements Exception {
  const MinnanoUnsafeUriException();

  @override
  String toString() => 'Minnano navigation URI is not allowed.';
}
