String canonicalizeJavBusWorkCode(String code) {
  final trimmed = code.trim();
  final match = RegExp(
    r'^([a-z0-9_]+-\d+)-?(?:VT|T|V)$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  return (match?.group(1) ?? trimmed).toUpperCase();
}

bool isJavBusSpecialEditionCode(String? code) {
  final trimmed = code?.trim();
  return trimmed != null &&
      RegExp(
        r'^[a-z0-9_]+-\d+-?(?:VT|T|V)$',
        caseSensitive: false,
      ).hasMatch(trimmed);
}
