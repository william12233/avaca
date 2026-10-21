import 'dart:convert';

const String scrapeSourceSettingsKey = 'scrape_source_settings';

enum ScrapeSourceId {
  javbus('javbus'),
  minnanoAv('minnanoAv'),
  avbase('avbase'),
  avwiki('avwiki');

  const ScrapeSourceId(this.storageValue);

  final String storageValue;

  static ScrapeSourceId? fromStorage(String? value) {
    for (final source in values) {
      if (source.storageValue == value) {
        return source;
      }
    }
    return null;
  }
}

final class ScrapeSourceSettings {
  const ScrapeSourceSettings({
    this.actressDetailsSource = ScrapeSourceId.minnanoAv,
    this.worksSources = const [ScrapeSourceId.javbus],
    this.aliasSource = ScrapeSourceId.avbase,
  });

  final ScrapeSourceId actressDetailsSource;
  final List<ScrapeSourceId> worksSources;
  final ScrapeSourceId aliasSource;

  String encode() {
    return jsonEncode({
      'actressDetailsSource': actressDetailsSource.storageValue,
      'worksSources': worksSources
          .map((source) => source.storageValue)
          .toList(growable: false),
      'aliasSource': aliasSource.storageValue,
    });
  }

  ScrapeSourceSettings copyWith({
    ScrapeSourceId? actressDetailsSource,
    List<ScrapeSourceId>? worksSources,
    ScrapeSourceId? aliasSource,
  }) {
    return ScrapeSourceSettings(
      actressDetailsSource: actressDetailsSource ?? this.actressDetailsSource,
      worksSources: List.unmodifiable(worksSources ?? this.worksSources),
      aliasSource: aliasSource ?? this.aliasSource,
    );
  }

  static ScrapeSourceSettings decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const ScrapeSourceSettings();
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const ScrapeSourceSettings();
      }
      final decodedDetails = ScrapeSourceId.fromStorage(
        decoded['actressDetailsSource']?.toString(),
      );
      final details = _isDetailsSource(decodedDetails) ? decodedDetails : null;
      final works = _decodeWorksSources(decoded);
      final decodedAliases = ScrapeSourceId.fromStorage(
        decoded['aliasSource']?.toString(),
      );
      final aliases = _isAliasSource(decodedAliases) ? decodedAliases : null;
      return ScrapeSourceSettings(
        actressDetailsSource: details ?? ScrapeSourceId.minnanoAv,
        worksSources: works,
        aliasSource: aliases ?? ScrapeSourceId.avbase,
      );
    } on Object {
      return const ScrapeSourceSettings();
    }
  }

  static List<ScrapeSourceId> _decodeWorksSources(Map<dynamic, dynamic> json) {
    final decoded = <ScrapeSourceId>[];
    final rawSources = json['worksSources'];
    if (rawSources is Iterable) {
      for (final raw in rawSources) {
        final source = ScrapeSourceId.fromStorage(raw?.toString());
        if (_isWorksSource(source) && !decoded.contains(source)) {
          decoded.add(source!);
        }
      }
    }
    if (decoded.isNotEmpty) return List.unmodifiable(decoded);

    // One compact migration for 0.9.7 snapshots. New writes only use the
    // ordered worksSources list above.
    return switch (json['worksSource']?.toString()) {
      'all' => const [ScrapeSourceId.javbus, ScrapeSourceId.avbase],
      'avbase' => const [ScrapeSourceId.avbase],
      _ => const [ScrapeSourceId.javbus],
    };
  }

  static bool _isWorksSource(ScrapeSourceId? source) =>
      source == ScrapeSourceId.javbus ||
      source == ScrapeSourceId.avbase ||
      source == ScrapeSourceId.avwiki;

  static bool _isDetailsSource(ScrapeSourceId? source) =>
      source == ScrapeSourceId.minnanoAv ||
      source == ScrapeSourceId.javbus ||
      source == ScrapeSourceId.avbase;

  static bool _isAliasSource(ScrapeSourceId? source) =>
      source == ScrapeSourceId.avbase;
}
