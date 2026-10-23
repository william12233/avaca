import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../../models/scraped_actress_details.dart';
import '../../models/work.dart';
import '../../models/scrape_source_settings.dart';
import '../scrape/scrape_models.dart';
import '../scrape/provenance_semantics.dart';
import 'avbase_models.dart';

final class AvBaseHtmlParser {
  AvBaseActressPage parseActressPage(String source, {required Uri pageUri}) {
    final document = html.parse(source);
    final name = _clean(document.querySelector('h1')?.text);
    final aliases = _profileAliases(document, name);
    final fields = _profileFields(document);
    final size = _parseSize(fields['サイズ'] ?? '');
    final avatar = _findAvatar(document, pageUri, name);
    final works = document
        .querySelectorAll('a[data-slot="button"][href]')
        .map((element) => _parseWorkSummary(element, pageUri))
        .whereType<AvBaseWorkSummary>()
        .toList(growable: false);

    return AvBaseActressPage(
      details: ScrapedActressDetails(
        name: name,
        avatarUrl: avatar,
        birthDate: _normalizeDate(fields['生年月日']),
        height: _digits(fields['身長']),
        cup: size.cup,
        bust: size.bust,
        waist: size.waist,
        hip: size.hip,
      ),
      aliases: aliases,
      works: works,
      pageCount: _pageCount(document),
    );
  }

  AvBaseWorkDetails parseWorkPage(String source, {required Uri pageUri}) {
    final document = html.parse(source);
    final fields = _detailFields(document);
    final rawCode = _codeFromUri(pageUri);
    final title = _clean(document.querySelector('h1')?.text) ?? '';
    final strippedTitle = _stripCode(title, rawCode);
    final performers = _performers(document, pageUri);
    final releaseDate = _normalizeDate(_field(fields, const ['発売日', '発売日']));
    final durationMinutes = _digitsAsInt(
      _field(fields, const ['収録分数', '収録時間']),
    );
    final studio = _field(fields, const ['メーカー', '製作メーカー']);
    final publisher = _field(fields, const ['レーベル', '発売元']);
    final series = _field(fields, const ['シリーズ']);
    final provenanceFacts = _provenanceFacts(
      document,
      fields,
      strippedTitle,
      pageUri,
    );

    return AvBaseWorkDetails(
      code: rawCode,
      title: strippedTitle,
      releaseDate: releaseDate,
      durationMinutes: durationMinutes,
      studio: studio,
      publisher: publisher,
      series: series,
      performerCount: performers?.length,
      performers: performers,
      provenanceFacts: provenanceFacts,
      catalogEvidence: [
        ScrapeCatalogWorkEvidence.fromDetails(
          source: ScrapeSourceId.avbase,
          code: rawCode,
          title: strippedTitle,
          manufacturer: studio,
          label: publisher,
          series: series,
          provenanceFacts: provenanceFacts,
        ),
      ],
      originalImageEvidenceUris: _originalImageEvidenceUris(
        document,
        pageUri,
        rawCode,
      ),
    );
  }

  ScrapeWorkProvenanceFacts _provenanceFacts(
    Document document,
    Map<String, String> fields,
    String title,
    Uri pageUri,
  ) {
    final tags = _sectionTags(document);
    final description =
        _sectionDescription(document) ??
        _clean(
          document
                  .querySelector('meta[name="description"]')
                  ?.attributes['content'] ??
              _field(fields, const ['説明', '概要', '内容']),
        );
    final includedWorks = <String>{
      ..._sectionWorkCodes(document, pageUri, const ['収録作品']),
      ..._fieldValues(fields, const ['収録作品', '収録タイトル', '収録内容', '収録作品名']),
    }.toList(growable: false);
    final parentWorks = <String>{
      ..._sectionWorkCodes(document, pageUri, const [
        '元作品',
        '親作品',
        '収録元',
        '原作品',
      ]),
      ..._fieldValues(fields, const ['元作品', '親作品', '収録元', '原作品']),
    }.toList(growable: false);
    final genres = _fieldValues(fields, const ['ジャンル', '類別', '類型']);
    final text = [
      title,
      description ?? '',
      ...fields.values,
      ...genres,
      ...tags,
    ].join(' ');
    final hasPriorMarker =
        includedWorks.isNotEmpty ||
        parentWorks.isNotEmpty ||
        ScrapeProvenanceSemantics.containsExplicitPriorWorkStatement(text);
    final isSplit = ScrapeProvenanceSemantics.containsStrongSplitEvidence(text);
    final isExtract = RegExp(
      r'抜粋|切り出し|extract',
      caseSensitive: false,
    ).hasMatch(text);
    final isPackage = RegExp(
      r'オムニバス|アンソロジー|作品集|bundle|package',
      caseSensitive: false,
    ).hasMatch(text);
    final isOldWithBonus =
        ScrapeProvenanceSemantics.containsOldMaterialWithNewBonus(text);
    final provenShared =
        ScrapeProvenanceSemantics.containsProvenSharedProduction(text);
    final sharedHint = ScrapeProvenanceSemantics.containsSharedProductionHint(
      text,
    );
    final independent = ScrapeProvenanceSemantics.containsIndependentSegments(
      text,
    );
    return ScrapeWorkProvenanceFacts(
      includedWorks: includedWorks,
      parentWorks: parentWorks,
      genres: genres,
      tags: tags,
      description: description,
      containsPriorWorks: hasPriorMarker ? true : null,
      extractedFromPriorWork: isExtract ? true : null,
      splitFromPriorWork: isSplit ? true : null,
      packageOfIndependentWorks: isPackage ? true : null,
      packageOfPriorWorks: isPackage && hasPriorMarker ? true : null,
      reusedIndependentSegments: independent && hasPriorMarker ? true : null,
      oldMaterialWithNewBonus: isOldWithBonus ? true : null,
      reissue:
          ScrapeProvenanceSemantics.containsStrongReissueEvidence(text) ||
              ScrapeProvenanceSemantics.containsPremiumRepackageEvidence(text)
          ? true
          : null,
      remaster: RegExp(r'リマスター|remaster', caseSensitive: false).hasMatch(text)
          ? true
          : null,
      reedited: ScrapeProvenanceSemantics.containsStrongReeditEvidence(text)
          ? true
          : null,
      explicitOriginalProduction:
          ScrapeProvenanceSemantics.containsReliableOriginal(text)
          ? true
          : null,
      coPerformance: independent
          ? ScrapeCoPerformance.independentSegments
          : provenShared
          ? ScrapeCoPerformance.sharedProduction
          : sharedHint
          ? ScrapeCoPerformance.possibleSharedProduction
          : ScrapeCoPerformance.unknown,
    );
  }

  List<String> _fieldValues(Map<String, String> fields, List<String> labels) {
    final values = <String>[];
    for (final label in labels) {
      final value = _clean(fields[label]);
      if (value != null && !values.contains(value)) values.add(value);
    }
    return List.unmodifiable(values);
  }

  List<String> _sectionTags(Document document) {
    final section = _sectionForHeading(document, const ['タグ・説明文']);
    if (section == null) return const [];
    final values = <String>[];
    final seen = <String>{};
    for (final anchor in section.querySelectorAll('a[href*="/tags/"]')) {
      final value = _clean(anchor.text);
      if (value != null && seen.add(value)) values.add(value);
    }
    return List.unmodifiable(values);
  }

  String? _sectionDescription(Document document) {
    final section = _sectionForHeading(document, const ['紹介文']);
    final fallback = _sectionForHeading(document, const ['タグ・説明文']);
    return _descriptionFromSection(section) ??
        _descriptionFromSection(fallback);
  }

  String? _descriptionFromSection(Element? section) {
    if (section == null) return null;
    for (final element in section.querySelectorAll(
      'p, article, [data-description], .prose, [class*="prose"]',
    )) {
      final value = _clean(element.text);
      if (value == null || value.length < 8) continue;
      final links = element.querySelectorAll('a');
      if (links.isNotEmpty &&
          element.querySelectorAll('a[href*="/tags/"]').length ==
              links.length) {
        continue;
      }
      return value;
    }
    for (final element in section.children.skip(1)) {
      if (element.querySelectorAll('a').isNotEmpty) continue;
      final value = _clean(element.text);
      if (value != null && value.length >= 8) return value;
    }
    return null;
  }

  List<String> _sectionWorkCodes(
    Document document,
    Uri pageUri,
    List<String> headings,
  ) {
    final section = _sectionForHeading(document, headings);
    if (section == null) return const [];
    final values = <String>[];
    final seen = <String>{};
    for (final anchor in section.querySelectorAll('a[href*="/works/"]')) {
      final href = _clean(anchor.attributes['href']);
      if (href == null) continue;
      final code = _codeFromUri(pageUri.resolve(href));
      if (code.isNotEmpty && seen.add(code)) values.add(code);
    }
    return List.unmodifiable(values);
  }

  Element? _sectionForHeading(Document document, List<String> headings) {
    for (final heading in document.querySelectorAll('h2, h3')) {
      final headingText = _clean(heading.text) ?? '';
      if (!headings.any(headingText.contains)) continue;
      Element? current = heading;
      while (current != null) {
        if (current.localName == 'section') return current;
        final parent = current.parent;
        current = parent is Element ? parent : null;
      }
      final parent = heading.parent;
      if (parent is Element &&
          parent.querySelectorAll('h2, h3').length == 1 &&
          _isControlledHeadingContainer(parent)) {
        return parent;
      }
      final ancestor = parent is Element ? parent.parent : null;
      if (ancestor is Element &&
          ancestor.querySelectorAll('h2, h3').length == 1 &&
          (ancestor.localName == 'article' ||
              ancestor.localName == 'div' &&
                  (ancestor.attributes.containsKey('data-slot') ||
                      ancestor.classes.any(
                        (value) => value.toLowerCase().contains('card'),
                      )))) {
        return ancestor;
      }
    }
    return null;
  }

  bool _isControlledHeadingContainer(Element element) {
    if (element.localName != 'div' && element.localName != 'article') {
      return false;
    }
    if (element.children.length > 12) return false;
    return element.querySelector('nav, footer, header, main, aside') == null;
  }

  ScrapeActressSearchResult? parseActressSearchResult(
    String source, {
    required Uri pageUri,
    required String query,
  }) {
    final document = html.parse(source);
    final name = _clean(document.querySelector('h1')?.text);
    if (name == null) {
      return null;
    }
    return ScrapeActressSearchResult(
      source: ScrapeSourceId.avbase,
      name: name,
      uri: pageUri,
    );
  }

  Uri? findWorkUriByCode(
    String source, {
    required Uri pageUri,
    required String code,
  }) {
    final expected = code.trim().toUpperCase();
    if (expected.isEmpty) return null;
    final document = html.parse(source);
    for (final anchor in document.querySelectorAll('a[href*="/works/"]')) {
      final href = _clean(anchor.attributes['href']);
      if (href == null) continue;
      final uri = pageUri.resolve(href);
      if (_codeFromUri(uri) == expected) return uri;
    }
    return null;
  }

  Map<String, String> _profileFields(Document document) {
    final fields = <String, String>{};
    for (final row in document.querySelectorAll(
      'div.flex.justify-between.items-start',
    )) {
      if (row.children.length < 2) {
        continue;
      }
      final label = _normalizeLabel(row.children.first.text);
      final value = _clean(row.children[1].text);
      if (label != null && value != null) {
        fields[label] = value;
      }
    }
    return fields;
  }

  List<String> _profileAliases(Document document, String? canonicalName) {
    final heading = document.querySelector('h1');
    if (heading == null) {
      return const [];
    }
    final canonicalKey = _aliasKey(canonicalName);
    final aliases = <String>[];
    final seen = <String>{};

    void add(String? raw) {
      final value = _clean(raw)?.replaceAll(RegExp(r'\s+'), ' ');
      final key = _aliasKey(value);
      if (value == null ||
          key == null ||
          key == canonicalKey ||
          !seen.add(key)) {
        return;
      }
      aliases.add(value);
    }

    Element? ancestor = heading.parent;
    for (var level = 0; ancestor != null && level < 2; level++) {
      for (final element in ancestor.querySelectorAll(
        'a[href*="/talents/"], p',
      )) {
        if (element == heading || element.querySelector('h1') != null) {
          continue;
        }
        final isTalentLink =
            element.localName == 'a' &&
            (element.attributes['href'] ?? '').contains('/talents/');
        final isSimpleParagraph =
            element.localName == 'p' &&
            element.parent == ancestor &&
            element.children.length <= 1;
        if (isTalentLink || isSimpleParagraph) {
          add(element.text);
        }
      }
      if (aliases.isNotEmpty) {
        break;
      }
      final parent = ancestor.parent;
      ancestor = parent is Element ? parent : null;
    }
    return List.unmodifiable(aliases);
  }

  String? _aliasKey(String? value) {
    final cleaned = value?.trim().toLowerCase();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }

  Map<String, String> _detailFields(Document document) {
    final fields = <String, String>{};
    for (final term in document.querySelectorAll('dt')) {
      final parent = term.parent;
      if (parent is! Element) {
        continue;
      }
      final index = parent.children.indexOf(term);
      if (index < 0 || index + 1 >= parent.children.length) {
        continue;
      }
      final label = _normalizeLabel(term.text);
      final value = _clean(parent.children[index + 1].text);
      if (label != null && value != null) {
        fields[label] = value;
      }
    }
    return fields;
  }

  Uri? _findAvatar(Document document, Uri pageUri, String? name) {
    final nameSelector = name == null
        ? null
        : document.querySelector('img[alt="${_escapeAttribute(name)}"]');
    final image =
        nameSelector ?? document.querySelector('img[src*="/mono/actjpgs/"]');
    final raw = _clean(
      image?.attributes['src'] ??
          image?.attributes['data-src'] ??
          image?.attributes['data-original'],
    );
    if (raw == null) {
      return null;
    }
    final uri = pageUri.resolve(raw);
    return _isAllowedAvatarUri(uri) ? uri : null;
  }

  AvBaseWorkSummary? _parseWorkSummary(Element anchor, Uri pageUri) {
    final href = _clean(anchor.attributes['href']);
    if (href == null) {
      return null;
    }
    final detailUri = pageUri.resolve(href);
    if (!detailUri.pathSegments.contains('works')) {
      return null;
    }
    final code = _codeFromUri(detailUri);
    if (code.isEmpty) {
      return null;
    }
    final card = _workCard(anchor);
    if (card == null) {
      return null;
    }
    final releaseDate = _clean(
      card.querySelector('a[href*="/works/date/"]')?.text,
    );
    final title = _clean(anchor.text) ?? '';
    return AvBaseWorkSummary(
      code: code,
      title: title,
      detailUri: detailUri,
      releaseDate: _normalizeDate(releaseDate),
      catalogEvidence: [
        _catalogEvidenceFromCard(card, code: code, title: title),
      ],
    );
  }

  ScrapeCatalogWorkEvidence _catalogEvidenceFromCard(
    Element card, {
    required String code,
    required String title,
  }) {
    String? firstText(List<String> selectors) {
      for (final selector in selectors) {
        final value = _clean(card.querySelector(selector)?.text);
        if (value != null) return value;
      }
      return null;
    }

    List<String> texts(String selector) {
      final values = <String>[];
      final seen = <String>{};
      for (final element in card.querySelectorAll(selector)) {
        final value = _clean(element.text);
        if (value != null && seen.add(value)) values.add(value);
      }
      return List.unmodifiable(values);
    }

    final tags = texts('a[href*="/tags/"]');
    return ScrapeCatalogWorkEvidence(
      source: ScrapeSourceId.avbase,
      code: code,
      rawCode: code,
      title: title,
      manufacturer: firstText(const [
        'a[href*="/maker/"]',
        'a[href*="/makers/"]',
        'a[href*="/manufacturer/"]',
      ]),
      label: firstText(const [
        'a[href*="/label/"]',
        'a[href*="/labels/"]',
        'a[href*="/publisher/"]',
      ]),
      series: firstText(const ['a[href*="/series/"]']),
      tags: tags,
      provenanceHints: tags,
    );
  }

  Element? _workCard(Element anchor) {
    Element? current = anchor;
    while (current != null) {
      if (current.classes.contains('bg-background') &&
          current.classes.contains('border-light') &&
          current.classes.contains('rounded-lg')) {
        return current;
      }
      final parent = current.parent;
      current = parent is Element ? parent : null;
    }
    return null;
  }

  List<WorkPerformer>? _performers(Document document, Uri pageUri) {
    Element? section;
    for (final heading in document.querySelectorAll('h2')) {
      final text = _clean(heading.text) ?? '';
      if (!text.contains('出演者')) {
        continue;
      }
      Element? current = heading;
      while (current != null) {
        if (current.localName == 'section') {
          section = current;
          break;
        }
        final parent = current.parent;
        current = parent is Element ? parent : null;
      }
      if (section != null) {
        break;
      }
    }
    if (section == null) {
      return null;
    }
    final result = <WorkPerformer>[];
    final seen = <String>{};
    for (final anchor in section.querySelectorAll('a[href*="/talents/"]')) {
      final name = _clean(anchor.text);
      final href = _clean(anchor.attributes['href']);
      if (name == null || href == null || !seen.add(name.toLowerCase())) {
        continue;
      }
      result.add(WorkPerformer(name: name, sourceUri: pageUri.resolve(href)));
    }
    return result.isEmpty ? null : List.unmodifiable(result);
  }

  List<Uri> _originalImageEvidenceUris(
    Document document,
    Uri pageUri,
    String code,
  ) {
    final result = <Uri>[];
    final seen = <String>{};
    for (final element in document.querySelectorAll('img, a')) {
      for (final attribute in const [
        'src',
        'data-src',
        'data-original',
        'href',
      ]) {
        final raw = _clean(element.attributes[attribute]);
        if (raw == null) {
          continue;
        }
        final uri = pageUri.resolve(raw);
        if (!_isImageEvidenceUri(uri) || !_evidenceMatchesCode(uri, code)) {
          continue;
        }
        if (seen.add(uri.toString())) {
          result.add(uri);
        }
      }
    }
    return List.unmodifiable(result);
  }

  bool _isAllowedAvatarUri(Uri uri) {
    final path = uri.path.toLowerCase();
    final port = uri.hasPort ? uri.port : 443;
    return uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        uri.host.toLowerCase() == 'pics.dmm.co.jp' &&
        port == 443 &&
        path.startsWith('/mono/actjpgs/') &&
        path.endsWith('.jpg');
  }

  bool _isImageEvidenceUri(Uri uri) {
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    return uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        path.endsWith('.jpg') &&
        (((host == 'awsimgsrc.dmm.co.jp' || host == 'pics.dmm.co.jp') &&
                path.contains('/digital/video/')) ||
            (host == 'image.mgstage.com' && path.contains('/images/')));
  }

  bool _evidenceMatchesCode(Uri uri, String code) {
    final match = RegExp(r'^([A-Za-z0-9]+)-(\d+)$').firstMatch(code);
    if (match == null) {
      return false;
    }
    final prefix = match.group(1)!.toLowerCase();
    final digits = match.group(2)!;
    final compact = uri.toString().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '',
    );
    return compact.contains(prefix) &&
        (compact.contains(digits) || compact.contains(digits.padLeft(5, '0')));
  }

  int _pageCount(Document document) {
    var maximum = 0;
    var minimum = 1 << 30;
    for (final anchor in document.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'];
      if (href == null) {
        continue;
      }
      final page = int.tryParse(Uri.parse(href).queryParameters['page'] ?? '');
      if (page == null) {
        continue;
      }
      if (page > maximum) {
        maximum = page;
      }
      if (page < minimum) {
        minimum = page;
      }
    }
    if (maximum == 0 && minimum == 1 << 30) {
      return 1;
    }
    return minimum == 0 ? maximum + 1 : maximum.clamp(1, 1 << 30).toInt();
  }

  ({String? cup, String? bust, String? waist, String? hip}) _parseSize(
    String value,
  ) {
    final match = RegExp(
      r'B\s*(\d+)\s*(?:\(([^)]+)\))?\s*W\s*(\d+)\s*H\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) {
      return (cup: null, bust: null, waist: null, hip: null);
    }
    return (
      cup: _clean(match.group(2)),
      bust: match.group(1),
      waist: match.group(3),
      hip: match.group(4),
    );
  }

  String? _field(Map<String, String> fields, List<String> labels) {
    for (final label in labels) {
      final value = _clean(fields[label]);
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  int? _digitsAsInt(String? value) => int.tryParse(_digits(value) ?? '');

  String? _digits(String? value) {
    return RegExp(r'\d+').firstMatch(value ?? '')?.group(0);
  }

  String? _normalizeDate(String? value) {
    final cleaned = _clean(value);
    if (cleaned == null) {
      return null;
    }
    final match = RegExp(
      r'^(\d{4})[./年-](\d{1,2})[./月-](\d{1,2})',
    ).firstMatch(cleaned);
    if (match == null) {
      return cleaned;
    }
    return '${match.group(1)}-${match.group(2)!.padLeft(2, '0')}-${match.group(3)!.padLeft(2, '0')}';
  }

  String _codeFromUri(Uri uri) {
    if (uri.pathSegments.isEmpty) {
      return '';
    }
    final segment = Uri.decodeComponent(uri.pathSegments.last).trim();
    final separator = segment.lastIndexOf(':');
    return (separator < 0 ? segment : segment.substring(separator + 1))
        .trim()
        .toUpperCase();
  }

  String _stripCode(String title, String code) {
    if (code.isEmpty) {
      return title;
    }
    return title
        .replaceFirst(
          RegExp('^${RegExp.escape(code)}\\s*', caseSensitive: false),
          '',
        )
        .trim();
  }

  String? _normalizeLabel(String value) {
    final cleaned = _clean(value);
    return cleaned?.replaceAll(RegExp(r'[：:]'), '').trim();
  }

  String? _clean(String? value) {
    final cleaned = value?.replaceAll('\u00a0', ' ').trim();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }

  String _escapeAttribute(String value) => value.replaceAll('"', '\\"');
}
