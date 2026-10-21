import 'dart:convert';

class ScrapeRules {
  const ScrapeRules({
    required this.schemaVersion,
    required this.rulesVersion,
    required this.updatedAt,
    this.aliases = const {},
    this.imageFamilyPrefixHints = const {},
    this.excludedSuffixes = const [],
  });

  static const builtin = ScrapeRules(
    schemaVersion: 1,
    rulesVersion: 'builtin-1',
    updatedAt: '2026-08-23T00:00:00Z',
  );

  final int schemaVersion;
  final String rulesVersion;
  final String updatedAt;
  final Map<String, String> aliases;
  final Map<String, List<String>> imageFamilyPrefixHints;
  final List<String> excludedSuffixes;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'rulesVersion': rulesVersion,
    'updatedAt': updatedAt,
    'aliases': aliases,
    'imageFamilyPrefixHints': imageFamilyPrefixHints,
    'excludedSuffixes': excludedSuffixes,
  };

  String encode() => jsonEncode(toJson());

  factory ScrapeRules.fromJson(Object? source) {
    if (source is! Map) {
      throw const FormatException('Scrape rules must be an object.');
    }
    final map = Map<String, Object?>.from(source);
    final schema = _int(map['schemaVersion']);
    final version = _string(map['rulesVersion']);
    final updatedAt = _string(map['updatedAt']);
    if (schema != 1 || version == null || updatedAt == null) {
      throw const FormatException('Unsupported scrape rules schema.');
    }
    final aliases = <String, String>{};
    final rawAliases = map['aliases'];
    if (rawAliases is Map) {
      for (final entry in rawAliases.entries) {
        final from = entry.key.toString().trim();
        final to = entry.value?.toString().trim() ?? '';
        if (from.isNotEmpty &&
            to.isNotEmpty &&
            from.length <= 80 &&
            to.length <= 80) {
          aliases[from] = to;
        }
      }
    }
    final hints = <String, List<String>>{};
    final rawHints = map['imageFamilyPrefixHints'];
    if (rawHints is Map) {
      for (final entry in rawHints.entries) {
        final key = entry.key.toString().trim();
        final values = entry.value is List
            ? (entry.value as List)
                  .map((item) => item.toString().trim())
                  .where((item) => item.isNotEmpty && item.length <= 32)
                  .take(32)
                  .toList(growable: false)
            : const <String>[];
        if (key.isNotEmpty && values.isNotEmpty) hints[key] = values;
      }
    }
    final suffixes = map['excludedSuffixes'] is List
        ? (map['excludedSuffixes'] as List)
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty && item.length <= 32)
              .take(64)
              .toList(growable: false)
        : const <String>[];
    return ScrapeRules(
      schemaVersion: schema,
      rulesVersion: version,
      updatedAt: updatedAt,
      aliases: Map.unmodifiable(aliases),
      imageFamilyPrefixHints: Map.unmodifiable(hints),
      excludedSuffixes: List.unmodifiable(suffixes),
    );
  }
}

int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

String? _string(Object? value) {
  final result = value?.toString().trim();
  return result == null || result.isEmpty || result.length > 200
      ? null
      : result;
}
