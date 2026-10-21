import 'dart:convert';

import 'package:avaca/models/scrape_exclusion_policy.dart';
import 'package:avaca/models/work_scrape_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trips active scrape settings and exact provenance rules', () {
    const options = WorkScrapeOptions(
      syncDetails: false,
      replaceActressImage: true,
      fillMissingOnly: false,
      scrapeAliases: true,
      autoExcludeDerivedWorks: false,
      exactAllows: [ScrapeExactAllowRule(code: 'OFJE-605')],
      exactDenies: [ScrapeExactDenyRule(code: 'FC2-001')],
    );

    final encoded = options.encode();
    final decoded = WorkScrapeOptions.decode(encoded);

    expect(decoded.scrapeAliases, isTrue);
    expect(decoded.exactAllows.single.normalizedCode, 'OFJE-605');
    expect(decoded.autoExcludeDerivedWorks, isFalse);
    expect(decoded.exactDenies.single.normalizedCode, 'FC2-001');
    expect(encoded, isNot(contains('excludedPrefixes')));
    expect(encoded, isNot(contains('managedFamilyModes')));
  });

  test('ignores legacy exclusion fields when reading persisted settings', () {
    final options = WorkScrapeOptions.decode(
      jsonEncode({
        'excludedPrefixes': ['FC2', 'OFJE'],
        'managedFamilyModes': {'OFJE': 'excludeAll'},
        'maxActressCount': 2,
        'exactAllows': [
          {'code': 'KEEP-001'},
        ],
      }),
    );

    expect(options.exactAllows.single.normalizedCode, 'KEEP-001');
    expect(options.encode(), isNot(contains('excludedPrefixes')));
    expect(options.encode(), isNot(contains('managedFamilyModes')));
    expect(options.encode(), isNot(contains('maxActressCount')));
  });

  test('uses safe defaults for malformed settings', () {
    final options = WorkScrapeOptions.decode('not-json');

    expect(options.syncDetails, isTrue);
    expect(options.replaceActressImage, isFalse);
    expect(options.fillMissingOnly, isTrue);
    expect(options.exactAllows, isEmpty);
    expect(options.exactDenies, isEmpty);
  });
}
