import 'dart:convert';

/// Converts transport/parser failures into bounded, non-sensitive journal data.
/// The journal is intentionally not a raw debug log: cookies, tokens, HTML,
/// filesystem paths, and query strings are removed before persistence.
class ScrapeEventSanitizer {
  const ScrapeEventSanitizer._();

  static const maxMessageBytes = 1200;
  static const maxMetadataBytes = 4096;

  static String message(Object? value, {String fallback = '刮削操作失敗'}) {
    var text = value?.toString().trim() ?? '';
    if (text.isEmpty) text = fallback;
    if (text.contains('<') || text.contains('>')) {
      text = '遠端回應無法解析';
    }
    text = text
        .replaceAllMapped(
          _sensitiveValue,
          (match) => '${match.group(1)}[REDACTED]',
        )
        .replaceAllMapped(RegExp(r'https?://[^\s)]+'), (match) {
          final uri = Uri.tryParse(match.group(0)!);
          if (uri == null) return '[URL]';
          return '${uri.scheme}://${uri.host}${uri.path}';
        })
        .replaceAll(RegExp(r'([A-Za-z]:[\\/]|/)[^\s,;]+'), '[PATH]')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return _limit(text, maxMessageBytes);
  }

  static Map<String, Object?> metadata(Map<String, Object?> input) {
    final sanitized = <String, Object?>{};
    for (final entry in input.entries) {
      final key = entry.key.trim();
      if (key.isEmpty || _sensitiveKey.hasMatch(key)) continue;
      sanitized[key] = _value(entry.value);
    }
    final encoded = jsonEncode(sanitized);
    if (utf8.encode(encoded).length <= maxMetadataBytes) return sanitized;
    return {
      'truncated': true,
      'keys': sanitized.keys.take(24).toList(growable: false),
    };
  }

  static Object? _value(Object? value) {
    if (value is Map) {
      return metadata(Map<String, Object?>.from(value));
    }
    if (value is Iterable) {
      return value.map(_value).take(32).toList(growable: false);
    }
    if (value is Uri) return '${value.scheme}://${value.host}${value.path}';
    if (value is String) return message(value, fallback: '');
    if (value is num || value is bool || value == null) return value;
    return message(value, fallback: '');
  }

  static String _limit(String value, int maxBytes) {
    if (utf8.encode(value).length <= maxBytes) return value;
    var result = value;
    while (result.isNotEmpty && utf8.encode('$result…').length > maxBytes) {
      result = result.substring(0, result.length - 1);
    }
    return '$result…';
  }

  static final _sensitiveValue = RegExp(
    r'((?:cookie|set-cookie|authorization|bearer|token|session|csrf)[^\s,;]*\s*[:=]\s*)(?:bearer\s+)?[^\s,;]+',
    caseSensitive: false,
  );
  static final _sensitiveKey = RegExp(
    r'(cookie|set-cookie|authorization|bearer|token|secret|password|session|csrf|html|body|path|query)',
    caseSensitive: false,
  );
}
