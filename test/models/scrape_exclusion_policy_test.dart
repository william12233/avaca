import 'dart:convert';

import 'package:avaca/models/scrape_exclusion_policy.dart';
import 'package:avaca/models/scrape_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('matches complete work codes and safe work-code prefixes', () {
    for (final code in const ['KCKC-212', 'KCKC-211']) {
      expect(manualRuleMatches('KCKC', code), isTrue, reason: code);
    }
    for (final code in const [
      'TSC-028',
      'TSC-027',
      'TSC-026',
      'TSC-025',
      'TSC-016',
      'TSC-015',
    ]) {
      expect(manualRuleMatches('TSC', code), isTrue, reason: code);
    }

    expect(manualRuleMatches('KCKC-212', 'KCKC-212'), isTrue);
    expect(manualRuleMatches('kckc', 'KCKC-212'), isTrue);
    expect(manualRuleMatches('KCKC', 'ABC-KCKC-212'), isFalse);
    expect(manualRuleMatches('KCKC', 'KCKCC-001'), isFalse);
  });

  test('round-trips a current provenance policy snapshot', () {
    final original = ScrapePolicySnapshot.current(
      rules: ScrapeRules.builtin,
      exactAllows: const [ScrapeExactAllowRule(code: 'OFJE-605')],
      autoExcludeDerivedWorks: false,
      exactDenies: const [ScrapeExactDenyRule(code: 'FC2-001')],
    );

    final decoded = ScrapePolicySnapshot.fromEncoded(
      encoded: original.encode(),
      exactAllows: const [],
    );

    expect(decoded.snapshotDigest, original.snapshotDigest);
    expect(decoded.exactAllows.single.normalizedCode, 'OFJE-605');
    expect(decoded.autoExcludeDerivedWorks, isFalse);
    expect(decoded.exactDenies.single.normalizedCode, 'FC2-001');
    expect(decoded.toJson().containsKey('excludedPrefixes'), isFalse);
    expect(decoded.toJson().containsKey('managedFamilies'), isFalse);
  });

  test(
    'legacy snapshot fields are accepted but never become active policy',
    () {
      final legacy = {
        'schemaVersion': 3,
        'policyVersion': 'provenance-v3',
        'excludedPrefixes': ['FC2'],
        'managedFamilies': [
          {'family': 'OFJE', 'mode': 'excludeAll', 'origin': 'user'},
        ],
        'exactAllows': [
          {'code': 'KEEP-001'},
        ],
      };

      final recovered = ScrapePolicySnapshot.fromEncoded(
        encoded: jsonEncode(legacy),
        exactAllows: const [ScrapeExactAllowRule(code: 'FALLBACK-001')],
      );

      expect(recovered.exactAllows.single.normalizedCode, 'FALLBACK-001');
      expect(recovered.toJson().containsKey('excludedPrefixes'), isFalse);
      expect(recovered.toJson().containsKey('managedFamilies'), isFalse);
    },
  );

  test('legacy fields cannot alter a current snapshot digest or policy', () {
    final original = ScrapePolicySnapshot.current(
      rules: ScrapeRules.builtin,
      exactAllows: const [ScrapeExactAllowRule(code: 'KEEP-001')],
    );
    final payload = jsonDecode(original.encode()) as Map<String, dynamic>;
    payload['excludedPrefixes'] = ['CHANGED'];
    payload['managedFamilies'] = [
      {'family': 'OFJE', 'mode': 'excludeAll', 'origin': 'user'},
    ];

    final decoded = ScrapePolicySnapshot.fromEncoded(
      encoded: jsonEncode(payload),
      exactAllows: const [],
    );

    expect(decoded.snapshotDigest, original.snapshotDigest);
    expect(decoded.exactAllows.single.normalizedCode, 'KEEP-001');
  });

  test('obsolete classifier snapshots fall back to current options', () {
    final snapshot = ScrapePolicySnapshot.current(
      rules: ScrapeRules.builtin,
      exactAllows: const [ScrapeExactAllowRule(code: 'OLD-001')],
    );
    final payload = jsonDecode(snapshot.encode()) as Map<String, dynamic>;
    payload['classifierVersion'] = 'semantic-0';

    final recovered = ScrapePolicySnapshot.fromEncoded(
      encoded: jsonEncode(payload),
      exactAllows: const [ScrapeExactAllowRule(code: 'FALLBACK-001')],
    );

    expect(recovered.exactAllows.single.normalizedCode, 'FALLBACK-001');
    expect(recovered.snapshotDigest, isNot(snapshot.snapshotDigest));
  });

  test('pre-semantic classifier snapshots are not reused', () {
    final snapshot = ScrapePolicySnapshot.current(
      rules: ScrapeRules.builtin,
      exactAllows: const [ScrapeExactAllowRule(code: 'OLD-002')],
    );
    final payload = jsonDecode(snapshot.encode()) as Map<String, dynamic>;
    payload['classifierVersion'] = 'provenance-1';

    final recovered = ScrapePolicySnapshot.fromEncoded(
      encoded: jsonEncode(payload),
      exactAllows: const [ScrapeExactAllowRule(code: 'FALLBACK-002')],
    );

    expect(recovered.exactAllows.single.normalizedCode, 'FALLBACK-002');
    expect(recovered.snapshotDigest, isNot(snapshot.snapshotDigest));
  });
}
