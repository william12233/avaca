import '../http_safety.dart';
import '../scrape/scrape_models.dart';
import 'avbase_html_parser.dart';
import 'avbase_models.dart';
import 'avbase_transport.dart';

final class AvBaseClient {
  AvBaseClient({
    required AvBaseTransport transport,
    AvBaseHtmlParser? parser,
    Uri? baseUri,
    this.maxPages = 100,
  }) : _transport = transport,
       _parser = parser ?? AvBaseHtmlParser(),
       _baseUri = baseUri ?? Uri.parse('https://www.avbase.net/') {
    if (maxPages < 1) {
      throw ArgumentError.value(maxPages, 'maxPages', 'Must be positive.');
    }
    _validateNavigationUri(_baseUri);
  }

  final AvBaseTransport _transport;
  final AvBaseHtmlParser _parser;
  final Uri _baseUri;
  final int maxPages;
  List<AvBasePageIssue> _lastWorkCollectionIssues = const [];

  List<AvBasePageIssue> get lastWorkCollectionIssues =>
      List.unmodifiable(_lastWorkCollectionIssues);

  Future<void> checkConnection() async {
    await _transport.get(_baseUri);
  }

  Future<List<ScrapeActressSearchResult>> searchActresses(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return const [];
    }
    final uri = _baseUri.replace(
      pathSegments: [
        ..._baseUri.pathSegments.where((part) => part.isNotEmpty),
        'talents',
        trimmed,
      ],
    );
    final source = await _transport.get(uri);
    final result = _parser.parseActressSearchResult(
      source,
      pageUri: uri,
      query: trimmed,
    );
    return result == null ? const [] : [result];
  }

  Future<AvBaseActressPage> fetchActressPage(Uri uri) async {
    _validateNavigationUri(uri);
    final source = await _transport.get(uri);
    final page = _parser.parseActressPage(source, pageUri: uri);
    if (page.details.name == null || page.details.name!.trim().isEmpty) {
      throw AvBaseRequestException(
        uri,
        null,
        kind: AvBaseFailureKind.parserInvalid,
      );
    }
    return page;
  }

  Future<AvBaseWorkDetails> fetchWorkDetails(Uri uri) async {
    _validateNavigationUri(uri);
    final source = await _transport.get(uri);
    final details = _parser.parseWorkPage(source, pageUri: uri);
    if (details.code.isEmpty) {
      throw AvBaseRequestException(
        uri,
        null,
        kind: AvBaseFailureKind.parserInvalid,
      );
    }
    return details;
  }

  Future<AvBaseWorkDetails> fetchWorkDetailsByCode(String code) {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(code, 'code', 'Must not be empty.');
    }
    final searchUri = _baseUri.replace(
      pathSegments: [
        ..._baseUri.pathSegments.where((part) => part.isNotEmpty),
        'works',
      ],
      queryParameters: {'q': trimmed},
    );
    return _fetchWorkDetailsBySearch(searchUri, trimmed);
  }

  Future<AvBaseWorkDetails> _fetchWorkDetailsBySearch(
    Uri searchUri,
    String code,
  ) async {
    final source = await _transport.get(searchUri);
    final uri = _parser.findWorkUriByCode(
      source,
      pageUri: searchUri,
      code: code,
    );
    if (uri == null) {
      throw AvBaseRequestException(
        searchUri,
        404,
        kind: AvBaseFailureKind.notFound,
      );
    }
    return fetchWorkDetails(uri);
  }

  Future<AvBaseWorkCollectionResult> fetchAllActressWorks(
    Uri actressUri, {
    required AvBaseActressPage firstPage,
    bool Function()? isCancelled,
    void Function(int currentPage, int totalPages, int discovered)? onProgress,
  }) async {
    _lastWorkCollectionIssues = const [];
    _validateNavigationUri(actressUri);
    if (isCancelled?.call() ?? false) {
      return const AvBaseWorkCollectionResult(works: []);
    }
    if (firstPage.pageCount > maxPages) {
      throw AvBasePageLimitException(firstPage.pageCount, maxPages);
    }

    final result = <AvBaseWorkSummary>[];
    final issues = <AvBasePageIssue>[];
    final seenUris = <String>{};

    void append(Iterable<AvBaseWorkSummary> works) {
      for (final work in works) {
        if (seenUris.add(work.detailUri.toString())) {
          result.add(work);
        }
      }
    }

    append(firstPage.works);
    onProgress?.call(1, firstPage.pageCount, result.length);
    for (var page = 1; page < firstPage.pageCount; page++) {
      if (isCancelled?.call() ?? false) {
        break;
      }
      final pageUri = _pageUri(actressUri, page);
      try {
        append((await fetchActressPage(pageUri)).works);
      } catch (error) {
        issues.add(
          AvBasePageIssue(
            uri: pageUri,
            kind: _pageIssueKind(error),
            error: error,
          ),
        );
      }
      onProgress?.call(page + 1, firstPage.pageCount, result.length);
    }
    final collection = AvBaseWorkCollectionResult(
      works: List.unmodifiable(result),
      issues: List.unmodifiable(issues),
    );
    _lastWorkCollectionIssues = collection.issues;
    return collection;
  }

  bool acceptsImageUri(Uri uri) {
    final port = uri.hasPort ? uri.port : 443;
    final path = uri.path.toLowerCase();
    return uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        uri.host.toLowerCase() == 'pics.dmm.co.jp' &&
        port == 443 &&
        path.startsWith('/mono/actjpgs/') &&
        path.endsWith('.jpg');
  }

  void close() {
    final transport = _transport;
    if (transport is HttpAvBaseTransport) {
      transport.close();
    }
  }

  Uri _pageUri(Uri actressUri, int page) {
    return actressUri.replace(
      queryParameters: {'q': '', 'page': '$page'},
      fragment: null,
    );
  }

  AvBaseFailureKind _pageIssueKind(Object error) {
    if (error is AvBaseRequestException) {
      return error.kind;
    }
    return AvBaseFailureKind.parserInvalid;
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
