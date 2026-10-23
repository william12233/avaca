import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../../models/scraped_actress_details.dart';
import 'minnano_models.dart';

final class MinnanoHtmlParser {
  List<MinnanoWorkSummary> parseActressWorks(
    String source, {
    required Uri pageUri,
  }) {
    final document = html.parse(source);
    return document
        .querySelectorAll('table.tbllist.av tr')
        .map((row) => _parseWorkSummary(row, pageUri))
        .whereType<MinnanoWorkSummary>()
        .toList();
  }

  /// Parses Minnano's source-native ranking order.
  ///
  /// The JSON-LD ItemList is authoritative for rank and the visible table is
  /// used to recover the source-provided avatar URL.  Keeping these two
  /// inputs separate makes the parser resilient to display-only markup
  /// changes while preserving the order users see on Minnano.
  List<MinnanoActressRankingItem> parseActressRanking(
    String source, {
    required Uri pageUri,
  }) {
    final document = html.parse(source);
    final visible = <String, _RankingMarkup>{};
    for (final row in document.querySelectorAll('table.tbllist tr')) {
      final anchor = row.querySelector('a[href]');
      final href = _clean(anchor?.attributes['href']);
      if (href == null) continue;
      final uri = pageUri.resolve(href);
      if (!_isMinnanoActressUri(uri)) continue;
      final name = _beforeParenthesis(_clean(anchor?.text));
      if (name == null || name.isEmpty) continue;
      final image = _imageUri(
        pageUri,
        row.querySelector('img'),
        allowedPathPrefix: '/p_actress_125_125/',
      );
      final rank = _rankFromRow(row);
      visible[uri.toString()] = _RankingMarkup(
        name: name,
        imageUri: image,
        rank: rank,
      );
    }

    final jsonItems = _rankingItemsFromJsonLd(document, pageUri);
    final result = <MinnanoActressRankingItem>[];
    for (var index = 0; index < jsonItems.length; index++) {
      final item = jsonItems[index];
      final markup = visible[item.uri.toString()];
      result.add(
        MinnanoActressRankingItem(
          rank: item.rank > 0 ? item.rank : index + 1,
          name: item.name,
          uri: item.uri,
          imageUri: markup?.imageUri,
        ),
      );
    }
    if (result.isNotEmpty) return List.unmodifiable(result);

    final fallback = visible.entries
        .map(
          (entry) => MinnanoActressRankingItem(
            rank: entry.value.rank ?? 0,
            name: entry.value.name,
            uri: Uri.parse(entry.key),
            imageUri: entry.value.imageUri,
          ),
        )
        .toList(growable: true);
    fallback.sort((a, b) {
      if (a.rank == 0 && b.rank == 0) return 0;
      if (a.rank == 0) return 1;
      if (b.rank == 0) return -1;
      return a.rank.compareTo(b.rank);
    });
    return List.unmodifiable(fallback);
  }

  /// Parses the native actress tag directory. This is intentionally separate
  /// from the weekly ranking endpoint: tag membership is the source's actual
  /// catalog navigation and remains useful even when the ranking changes.
  List<MinnanoActressTag> parseActressTags(
    String source, {
    required Uri pageUri,
  }) {
    final document = html.parse(source);
    final result = <MinnanoActressTag>[];
    final seen = <String>{};

    void addTag(String key, String label, Uri uri, int? count) {
      final cleanKey = key.trim();
      final cleanLabel = _beforeParenthesis(label) ?? _clean(label);
      if (cleanKey.isEmpty || cleanLabel == null || cleanLabel.isEmpty) return;
      if (!seen.add(cleanKey)) return;
      result.add(
        MinnanoActressTag(
          key: cleanKey,
          label: cleanLabel,
          uri: uri,
          count: count,
        ),
      );
    }

    for (final anchor in document.querySelectorAll(
      'a[href*="actress_list.php"]',
    )) {
      final href = _clean(anchor.attributes['href']);
      if (href == null) continue;
      final uri = pageUri.resolve(href);
      if (!_isMinnanoPageUri(uri) || uri.path != '/actress_list.php') continue;
      final key = uri.queryParameters['tag_a_id'];
      if (key == null || key.trim().isEmpty) continue;
      final rawLabel = _clean(anchor.text);
      if (rawLabel == null) continue;
      final count = int.tryParse(
        RegExp(r'[（(]\s*(\d+)\s*[名人]?\s*[）)]').firstMatch(rawLabel)?.group(1) ??
            '',
      );
      addTag(key, rawLabel, uri, count);
    }

    // The current tag page can be sparse, so also derive its own tag from the
    // title/meta description when no matching navigation link is present.
    final currentId = pageUri.queryParameters['tag_a_id'];
    if (currentId != null && currentId.trim().isNotEmpty) {
      final title = _clean(document.querySelector('title')?.text);
      final description = _clean(
        document
            .querySelector('meta[name="description"]')
            ?.attributes['content'],
      );
      final label = _tagName(title) ?? _tagName(description);
      if (label != null) {
        final count = _countFromText(title) ?? _countFromText(description);
        final existing = result.indexWhere((tag) => tag.key == currentId);
        if (existing >= 0 && count != null) {
          final previous = result[existing];
          result[existing] = MinnanoActressTag(
            key: previous.key,
            label: previous.label,
            uri: previous.uri,
            count: count,
          );
        } else {
          addTag(currentId, label, pageUri, count);
        }
      }
    }

    result.sort((a, b) => a.label.compareTo(b.label));
    return List.unmodifiable(result);
  }

  List<MinnanoActressListItem> parseActressList(
    String source, {
    required Uri pageUri,
  }) {
    final document = html.parse(source);
    final result = <MinnanoActressListItem>[];
    final seen = <String>{};

    void addItem({
      required String name,
      required Uri uri,
      Uri? imageUri,
      List<String> tags = const [],
    }) {
      if (!seen.add(uri.toString())) return;
      result.add(
        MinnanoActressListItem(
          name: name,
          uri: uri,
          imageUri: imageUri,
          tags: List.unmodifiable(tags),
        ),
      );
    }

    for (final row in document.querySelectorAll('table.tbllist tr')) {
      final anchor = row.querySelector('a[href]');
      final href = _clean(anchor?.attributes['href']);
      if (href == null) continue;
      final uri = pageUri.resolve(href);
      if (!_isMinnanoActressUri(uri)) continue;
      final name = _beforeParenthesis(
        _clean(row.querySelector('h2')?.text ?? anchor?.text),
      );
      if (name == null || name.isEmpty) continue;
      final image = _imageUri(
        pageUri,
        row.querySelector('img'),
        allowedPathPrefix: '/p_actress_125_125/',
      );
      final tags = row
          .querySelectorAll('a[href*="actress_list.php"]')
          .map((tag) => _clean(tag.text))
          .whereType<String>()
          .toList(growable: false);
      addItem(name: name, uri: uri, imageUri: image, tags: tags);
    }

    // Some list variants expose Person records only through JSON-LD.
    for (final script in document.querySelectorAll(
      'script[type="application/ld+json"]',
    )) {
      final raw = _clean(script.text);
      if (raw == null) continue;
      try {
        final decoded = jsonDecode(raw);
        _appendPersons(decoded, pageUri, addItem);
      } on FormatException {
        // A malformed optional JSON-LD block must not hide the HTML list.
      }
    }
    return List.unmodifiable(result);
  }

  MinnanoActressPage parseActressPage(String source, {required Uri pageUri}) {
    final document = html.parse(source);
    final profile = _profileTable(document);
    final heading = _clean(
      document.querySelector('h2')?.text ?? document.querySelector('h1')?.text,
    );
    final name = _beforeParenthesis(heading);
    final aliases = _aliases(profile, name);
    final birthDate = _date(_field(profile, const ['生年月日']));
    final size = _field(profile, const ['サイズ']);
    final avatar = _imageUri(
      pageUri,
      document
          .querySelectorAll('img')
          .firstWhere(
            (image) =>
                _imageValue(image)?.contains('/p_actress_125_125/') ?? false,
            orElse: () => Element.tag('img'),
          ),
      allowedPathPrefix: '/p_actress_125_125/',
    );

    return MinnanoActressPage(
      details: ScrapedActressDetails(
        name: name,
        avatarUrl: avatar,
        birthDate: birthDate,
        height: _digits(
          RegExp(r'T\s*(\d{2,3})').firstMatch(size ?? '')?.group(1),
        ),
        cup: _cup(size),
        bust: _digits(
          RegExp(r'B\s*(\d{2,3})').firstMatch(size ?? '')?.group(1),
        ),
        waist: _digits(
          RegExp(r'W\s*(\d{2,3})').firstMatch(size ?? '')?.group(1),
        ),
        hip: _digits(RegExp(r'H\s*(\d{2,3})').firstMatch(size ?? '')?.group(1)),
      ),
      aliases: aliases,
      works: parseActressWorks(source, pageUri: pageUri),
      pageCount: _pageCount(document),
    );
  }

  List<ScrapeSearchResult> parseActressSearchResults(
    String source, {
    required Uri pageUri,
  }) {
    final document = html.parse(source);
    final seen = <String>{};
    final results = <ScrapeSearchResult>[];
    for (final anchor in document.querySelectorAll('a[href]')) {
      final href = _clean(anchor.attributes['href']);
      if (href == null || !_isActressPath(Uri.parse(href).path)) {
        continue;
      }
      final uri = pageUri.resolve(href);
      if (!_isMinnanoActressUri(uri)) {
        continue;
      }
      final name = _beforeParenthesis(_clean(anchor.text));
      if (name != null && name.isNotEmpty && seen.add(uri.toString())) {
        results.add(
          ScrapeSearchResult(
            name: name,
            uri: uri,
            imageUri: _imageUri(
              pageUri,
              anchor.querySelector('img'),
              allowedPathPrefix: '/p_actress_125_125/',
            ),
          ),
        );
      }
    }

    final canonicalHref = _clean(
      document.querySelector('link[rel="canonical"]')?.attributes['href'],
    );
    if (canonicalHref != null) {
      final canonicalUri = pageUri.resolve(canonicalHref);
      if (_isMinnanoActressUri(canonicalUri)) {
        final name = _beforeParenthesis(
          _clean(
            document.querySelector('h2')?.text ??
                document.querySelector('h1')?.text,
          ),
        );
        if (name != null &&
            name.isNotEmpty &&
            seen.add(canonicalUri.toString())) {
          results.add(ScrapeSearchResult(name: name, uri: canonicalUri));
        }
      }
    }
    return List.unmodifiable(results);
  }

  MinnanoWorkDetails parseWorkPage(String source, {required Uri pageUri}) {
    final document = html.parse(source);
    final fields = <String, Element>{};
    for (final row in document.querySelectorAll('table.prof-table tr')) {
      final label = _clean(
        row.querySelector('th')?.text ?? row.children.firstOrNull?.text,
      );
      if (label == null) {
        continue;
      }
      final value = row.children.length > 1 ? row.children[1] : row;
      fields[_fieldKey(label)] = value;
    }

    final titleElement = fields['作品名']?.querySelector('h2');
    final title = _clean(titleElement?.text ?? fields['作品名']?.text) ?? '';
    final code = _clean(
      fields['品番']?.querySelector('[data-code]')?.attributes['data-code'] ??
          fields['品番']?.text,
    );
    final makerValues = _linksOrText(fields['メーカー/レーベル']);
    final performerCount = _performerCount(fields['出演者']);
    final jacket = document.querySelector('img.jacket-image');
    final imageUri = _imageUri(
      pageUri,
      jacket,
      allowedPathPrefix: '/p_package/',
    );

    return MinnanoWorkDetails(
      code: code,
      title: title,
      releaseDate: _date(fields['発売日']?.text),
      studio: makerValues.elementAtOrNull(0),
      publisher: makerValues.elementAtOrNull(1),
      performerCount: performerCount,
      imageUris: imageUri == null ? const [] : [imageUri],
    );
  }

  Element? _profileTable(Document document) {
    for (final table in document.querySelectorAll('table')) {
      final labels = table.querySelectorAll('tr').map(_rowLabel).toSet();
      if (labels.any(const {'別名', '生年月日', 'サイズ'}.contains)) {
        return table;
      }
    }
    return null;
  }

  String? _field(Element? table, List<String> labels) {
    if (table == null) {
      return null;
    }
    for (final row in table.querySelectorAll('tr')) {
      final label = _rowLabel(row);
      if (label != null && labels.contains(label)) {
        final paragraphs = row.querySelectorAll('p');
        return _clean(
          paragraphs.isEmpty
              ? row.text.replaceFirst(label, '')
              : paragraphs.first.text,
        );
      }
    }
    return null;
  }

  List<String> _aliases(Element? table, String? canonicalName) {
    if (table == null) {
      return const [];
    }
    final result = <String>[];
    for (final row in table.querySelectorAll('tr')) {
      if (_rowLabel(row) != '別名') {
        continue;
      }
      final values = row.querySelectorAll('p');
      for (final value in values.isEmpty ? [row] : values) {
        final cleaned = _stripMetadata(_clean(value.text));
        if (cleaned != null &&
            cleaned.isNotEmpty &&
            cleaned != canonicalName &&
            !result.contains(cleaned)) {
          result.add(cleaned);
        }
      }
    }
    return List.unmodifiable(result);
  }

  MinnanoWorkSummary? _parseWorkSummary(Element row, Uri pageUri) {
    final anchor = row.querySelector('a[href]');
    final href = _clean(anchor?.attributes['href']);
    if (href == null ||
        !RegExp(
          r'^/?av[^/]*\.html$',
          caseSensitive: false,
        ).hasMatch(Uri.parse(href).path)) {
      return null;
    }
    final detailUri = pageUri.resolve(href);
    if (!_isMinnanoPageUri(detailUri)) {
      return null;
    }
    final image = row.querySelector('img');
    return MinnanoWorkSummary(
      code: _clean(
        row.attributes['data-code'] ?? image?.attributes['data-code'],
      ),
      title: _clean(row.querySelector('h3.ttl')?.text ?? anchor?.text) ?? '',
      detailUri: detailUri,
      releaseDate: _date(_releaseText(row)),
      imageUri: _imageUri(pageUri, image, allowedPathPrefix: '/p_package/'),
      publisher: _workListPublisher(row),
    );
  }

  String? _workListPublisher(Element row) {
    final labels = row.querySelectorAll('p.cast');
    for (final label in labels.reversed) {
      if (label.querySelector('a') != null) continue;
      final value = _clean(label.text);
      if (value != null) return value;
    }
    return null;
  }

  int? _rankFromRow(Element row) {
    for (final cell in row.querySelectorAll('td, th')) {
      final value = int.tryParse(cell.text.trim());
      if (value != null && value > 0 && value <= 1000) return value;
    }
    return null;
  }

  List<_RankingJsonItem> _rankingItemsFromJsonLd(
    Document document,
    Uri pageUri,
  ) {
    final result = <_RankingJsonItem>[];
    for (final script in document.querySelectorAll(
      'script[type="application/ld+json"]',
    )) {
      final raw = script.text.trim();
      if (raw.isEmpty) continue;
      Object? decoded;
      try {
        decoded = jsonDecode(raw);
      } on FormatException {
        continue;
      }
      final lists = <Map<dynamic, dynamic>>[];
      void collect(Object? value) {
        if (value is Map) {
          if (value['@type'] == 'ItemList') {
            lists.add(value);
          }
          final graph = value['@graph'];
          if (graph is Iterable) {
            for (final item in graph) {
              collect(item);
            }
          }
        } else if (value is Iterable) {
          for (final item in value) {
            collect(item);
          }
        }
      }

      collect(decoded);
      for (final list in lists) {
        final entries = list['itemListElement'];
        if (entries is! Iterable) continue;
        for (final entry in entries) {
          if (entry is! Map) continue;
          final href = _clean(entry['url']?.toString());
          final name = _beforeParenthesis(_clean(entry['name']?.toString()));
          if (href == null || name == null || name.isEmpty) continue;
          final uri = pageUri.resolve(href);
          if (!_isMinnanoActressUri(uri)) continue;
          final rank = int.tryParse(entry['position']?.toString() ?? '') ?? 0;
          result.add(_RankingJsonItem(rank: rank, name: name, uri: uri));
        }
      }
    }
    result.sort((a, b) {
      if (a.rank == 0 && b.rank == 0) return 0;
      if (a.rank == 0) return 1;
      if (b.rank == 0) return -1;
      return a.rank.compareTo(b.rank);
    });
    final seen = <String>{};
    return result.where((item) => seen.add(item.uri.toString())).toList();
  }

  String? _rowLabel(Element row) {
    final label =
        row.querySelector('th')?.text ?? row.querySelector('span')?.text;
    return label == null ? null : _fieldKey(label);
  }

  String _fieldKey(String value) => value.replaceAll(RegExp(r'[\s:：]'), '');

  List<String> _linksOrText(Element? element) {
    if (element == null) {
      return const [];
    }
    final links = element
        .querySelectorAll('a')
        .map((anchor) => _clean(anchor.text))
        .whereType<String>()
        .toList(growable: false);
    if (links.isNotEmpty) {
      return links;
    }
    return element.text
        .split(RegExp(r'[/／]'))
        .map(_clean)
        .whereType<String>()
        .toList(growable: false);
  }

  int? _performerCount(Element? element) {
    if (element == null) {
      return null;
    }
    final links = element.querySelectorAll('a[href*="actress"]');
    if (links.isNotEmpty) {
      return links.length;
    }
    return null;
  }

  Uri? _imageUri(
    Uri pageUri,
    Element? image, {
    required String allowedPathPrefix,
  }) {
    final value = _imageValue(image);
    if (value == null) {
      return null;
    }
    final uri = pageUri.resolve(value);
    if (!_isMinnanoPageUri(uri) || !uri.path.startsWith(allowedPathPrefix)) {
      return null;
    }
    return uri;
  }

  String? _imageValue(Element? image) {
    return _clean(image?.attributes['data-src'] ?? image?.attributes['src']);
  }

  void _appendPersons(
    Object? value,
    Uri pageUri,
    void Function({
      required String name,
      required Uri uri,
      Uri? imageUri,
      List<String> tags,
    })
    add,
  ) {
    if (value is List) {
      for (final child in value) {
        _appendPersons(child, pageUri, add);
      }
      return;
    }
    if (value is! Map) return;
    final type = value['@type']?.toString().toLowerCase();
    if (type == 'person') {
      final name = _clean(value['name']?.toString());
      final rawUrl = _clean(value['url']?.toString());
      if (name != null && rawUrl != null) {
        final uri = pageUri.resolve(rawUrl);
        if (_isMinnanoActressUri(uri)) {
          final rawImage = _clean(value['image']?.toString());
          final image = rawImage == null
              ? null
              : _imageUri(
                  pageUri,
                  Element.tag('img')..attributes['src'] = rawImage,
                  allowedPathPrefix: '/p_actress_125_125/',
                );
          add(name: name, uri: uri, imageUri: image);
        }
      }
    }
    for (final child in value.values) {
      if (child is Map || child is List) _appendPersons(child, pageUri, add);
    }
  }

  String? _tagName(String? raw) {
    final value = _clean(raw);
    if (value == null) return null;
    final match = RegExp(r'[「『]\s*([^」』]+?)\s*[」』]').firstMatch(value);
    return _clean(match?.group(1));
  }

  int? _countFromText(String? raw) {
    final match = RegExp(r'(\d+)\s*名').firstMatch(raw ?? '');
    return int.tryParse(match?.group(1) ?? '');
  }

  String? _releaseText(Element row) {
    for (final cell in row.querySelectorAll('td')) {
      final text = _clean(cell.text);
      if (text != null &&
          RegExp(r'\d{4}(?:年|[/-])\s*\d{1,2}(?:月|[/-])').hasMatch(text)) {
        return text;
      }
    }
    return null;
  }

  int _pageCount(Document document) {
    var maximum = 1;
    for (final anchor in document.querySelectorAll('a[href]')) {
      final label = int.tryParse(anchor.text.trim());
      if (label != null && label > maximum) {
        maximum = label;
      }
      final href = anchor.attributes['href'];
      if (href == null) {
        continue;
      }
      final match = RegExp(
        r'(?:page|p)[=/]?(\d+)',
        caseSensitive: false,
      ).firstMatch(href);
      final page = int.tryParse(match?.group(1) ?? '');
      if (page != null && page > maximum) {
        maximum = page;
      }
    }
    return maximum;
  }

  String? _date(String? value) {
    final match = RegExp(
      r'(\d{4})年\s*(\d{1,2})月\s*(\d{1,2})日',
    ).firstMatch(value ?? '');
    if (match == null) {
      final slashMatch = RegExp(
        r'(\d{4})\s*[/-]\s*(\d{1,2})\s*[/-]\s*(\d{1,2})',
      ).firstMatch(value ?? '');
      if (slashMatch == null) {
        return _clean(value);
      }
      return '${slashMatch.group(1)}-${slashMatch.group(2)!.padLeft(2, '0')}-'
          '${slashMatch.group(3)!.padLeft(2, '0')}';
    }
    return '${match.group(1)}-${match.group(2)!.padLeft(2, '0')}-'
        '${match.group(3)!.padLeft(2, '0')}';
  }

  String? _cup(String? size) {
    final value = RegExp(
      r'B\s*\d{2,3}\s*\(([^)]+)\)',
    ).firstMatch(size ?? '')?.group(1);
    return _clean(value)?.replaceAll('カップ', '').trim();
  }

  String? _digits(String? value) {
    final match = RegExp(r'\d+').firstMatch(value ?? '');
    return match?.group(0);
  }

  String? _beforeParenthesis(String? value) {
    final cleaned = _clean(value);
    if (cleaned == null) {
      return null;
    }
    return _clean(cleaned.split(RegExp(r'[（(]')).first);
  }

  String? _stripMetadata(String? value) {
    final cleaned = _beforeParenthesis(value);
    if (cleaned == null) {
      return null;
    }
    return _clean(cleaned.replaceAll(RegExp(r'【[^】]*】'), '').trim());
  }

  String? _clean(String? value) {
    final cleaned = value?.replaceAll('\u00a0', ' ').trim();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }

  bool _isMinnanoPageUri(Uri uri) {
    final port = uri.hasPort ? uri.port : 443;
    return uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        uri.host.toLowerCase() == 'www.minnano-av.com' &&
        port == 443;
  }

  bool _isMinnanoActressUri(Uri uri) {
    return _isMinnanoPageUri(uri) && _isActressPath(uri.path);
  }

  bool _isActressPath(String path) {
    return RegExp(
      r'^/?actress[^/]*\.html$',
      caseSensitive: false,
    ).hasMatch(path);
  }
}

final class _RankingMarkup {
  const _RankingMarkup({required this.name, this.imageUri, this.rank});

  final String name;
  final Uri? imageUri;
  final int? rank;
}

final class _RankingJsonItem {
  const _RankingJsonItem({
    required this.rank,
    required this.name,
    required this.uri,
  });

  final int rank;
  final String name;
  final Uri uri;
}

final class ScrapeSearchResult {
  const ScrapeSearchResult({
    required this.name,
    required this.uri,
    this.imageUri,
  });

  final String name;
  final Uri uri;
  final Uri? imageUri;
}
