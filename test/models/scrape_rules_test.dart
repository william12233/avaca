import 'package:flutter_test/flutter_test.dart';

import 'package:avaca/models/scrape_rules.dart';
import 'package:avaca/services/scrape_rules_repository.dart';

void main() {
  test('rules parser accepts bounded data-only fields', () {
    final rules = ScrapeRules.fromJson({
      'schemaVersion': 1,
      'rulesVersion': 'remote-4',
      'updatedAt': '2026-08-23T00:00:00Z',
      'aliases': {'ABC': 'ABC-123'},
      'imageFamilyPrefixHints': {
        'ABC': ['1abc'],
      },
      'excludedSuffixes': ['-V'],
      'managedFamilyRecommendations': {'OFJE': 'excludeAll'},
      'cookie': 'must not be accepted as a rule',
    });

    expect(rules.rulesVersion, 'remote-4');
    expect(rules.aliases['ABC'], 'ABC-123');
    expect(rules.imageFamilyPrefixHints['ABC'], ['1abc']);
    expect(rules.toJson().containsKey('cookie'), isFalse);
    expect(rules.toJson().containsKey('managedFamilyRecommendations'), isFalse);
  });

  test('remote endpoint is fixed to the allowlisted data file', () {
    expect(
      ScrapeRulesRepository.remoteUri.toString(),
      'https://raw.githubusercontent.com/william12233/avaca/main/release/scrape-rules.json',
    );
  });
}
