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
        .toList(growable: false);
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
        results.add(ScrapeSearchResult(name: name, uri: uri));
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
    );
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

final class ScrapeSearchResult {
  const ScrapeSearchResult({required this.name, required this.uri});

  final String name;
  final Uri uri;
}
