import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/database.dart';
import '../models/scrape_rules.dart';

class ScrapeRulesRepository {
  ScrapeRulesRepository({required this.db, http.Client? client})
    : _client = client ?? http.Client();

  static final Uri remoteUri = Uri.https(
    'raw.githubusercontent.com',
    '/william12233/avaca/main/release/scrape-rules.json',
  );
  static const maxBytes = 256 * 1024;
  static const cacheKey = 'scrape_rules_lkg';
  static const checkedKey = 'scrape_rules_last_checked_at';

  final AppDatabase db;
  final http.Client _client;
  ScrapeRules _current = ScrapeRules.builtin;
  String? lastError;

  ScrapeRules get current => _current;

  Future<ScrapeRules> load() async {
    final cached = await db.getSetting(cacheKey);
    if (cached != null && cached.isNotEmpty) {
      try {
        _current = ScrapeRules.fromJson(jsonDecode(cached));
      } on Object catch (error) {
        lastError = error.toString();
        _current = ScrapeRules.builtin;
      }
    }
    return _current;
  }

  Future<ScrapeRules> refreshIfDue({
    Duration interval = const Duration(days: 1),
  }) async {
    await load();
    final checked = DateTime.tryParse(await db.getSetting(checkedKey) ?? '');
    if (checked != null &&
        DateTime.now().toUtc().difference(checked) < interval) {
      return _current;
    }
    return refresh();
  }

  Future<ScrapeRules> refresh() async {
    if (!_isAllowedRemote(remoteUri)) {
      lastError = 'Remote rules endpoint is not allowlisted.';
      return _current;
    }
    try {
      final response = await _client
          .get(remoteUri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));
      await db.setSetting(checkedKey, DateTime.now().toUtc().toIso8601String());
      if (response.statusCode != 200 || response.bodyBytes.length > maxBytes) {
        throw StateError('Remote rules response was rejected.');
      }
      final parsed = ScrapeRules.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)),
      );
      _current = parsed;
      lastError = null;
      await db.setSetting(cacheKey, parsed.encode());
    } on Object catch (error) {
      lastError = error.toString();
      // Last-known-good or built-in rules remain active. A remote failure can
      // never block a job or replace a valid cached snapshot.
    }
    return _current;
  }

  void close() => _client.close();

  bool _isAllowedRemote(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host == 'raw.githubusercontent.com' &&
      uri.path == '/william12233/avaca/main/release/scrape-rules.json' &&
      uri.query.isEmpty &&
      uri.fragment.isEmpty;
}
