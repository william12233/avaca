import 'dart:convert';

import 'package:avaca/models/scrape_work_category.dart';
import 'package:avaca/models/work_scrape_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trips active scrape settings and category whitelist', () {
    const options = WorkScrapeOptions(
      syncDetails: false,
      replaceActressImage: true,
      fillMissingOnly: false,
      scrapeAliases: true,
      selectedCategories: [ScrapeWorkCategory.single, ScrapeWorkCategory.vr],
    );

    final encoded = options.encode();
    final decoded = WorkScrapeOptions.decode(encoded);

    expect(decoded.scrapeAliases, isTrue);
    expect(decoded.selectedCategories, [
      ScrapeWorkCategory.single,
      ScrapeWorkCategory.vr,
    ]);
    expect(decoded.autoExcludeDerivedWorks, isTrue);
    expect(decoded.exactAllows, isEmpty);
    expect(decoded.exactDenies, isEmpty);
    expect(encoded, contains('"categoryWhitelist":["single","vr"]'));
    expect(encoded, isNot(contains('autoExcludeDerivedWorks')));
    expect(encoded, isNot(contains('exactAllows')));
    expect(encoded, isNot(contains('exactDenies')));
    expect(encoded, isNot(contains('excludedPrefixes')));
    expect(encoded, isNot(contains('managedFamilyModes')));
  });

  test('keeps legacy exclusion fields readable without writing them back', () {
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
    expect(options.selectedCategories, isEmpty);
    expect(options.encode(), isNot(contains('excludedPrefixes')));
    expect(options.encode(), isNot(contains('managedFamilyModes')));
    expect(options.encode(), isNot(contains('maxActressCount')));
    expect(options.encode(), isNot(contains('exactAllows')));
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
