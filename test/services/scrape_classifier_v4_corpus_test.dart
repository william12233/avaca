import 'dart:convert';
import 'dart:io';

import 'package:avaca/models/scrape_exclusion_policy.dart';
import 'package:avaca/models/scrape_rules.dart';
import 'package:avaca/models/scrape_source_settings.dart';
import 'package:avaca/services/scrape/scrape_classification_context.dart';
import 'package:avaca/services/scrape/scrape_models.dart';
import 'package:avaca/services/scrape_exclusion_policy_evaluator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('semantic-v4 corpus meets its decisive and review-rate gates', () {
    final corpus =
        jsonDecode(
              File(
                'test/fixtures/scrape_classifier_v4_corpus.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final cases = (corpus['cases'] as List).cast<Map<String, dynamic>>();
    final actresses = (corpus['actresses'] as List).cast<String>();
    final identityFamilies = (corpus['identityFamilies'] as List)
        .cast<String>();
    final expectedCounts = corpus['expectedCounts'] as Map<String, dynamic>;

    expect(corpus['classifierVersion'], 'semantic-v4');
    expect(actresses, hasLength(9));
    expect(identityFamilies.toSet(), hasLength(19));
    expect(cases, hasLength(163));

    final evaluator = ScrapeExclusionPolicyEvaluator(
      ScrapePolicySnapshot.current(
        rules: ScrapeRules.builtin,
        exactAllows: const [],
      ),
    );
    var decisive = 0;
    var correctDecisive = 0;
    var expectedKeep = 0;
    var expectedExclude = 0;
    var falseExclude = 0;
    var falseKeep = 0;
    var review = 0;

    for (final corpusCase in cases) {
      final expected = corpusCase['expected'] as String;
      final decision = evaluator.evaluate(
        code: corpusCase['code'] as String,
        details: (corpusCase['details'] as List)
            .cast<Map<String, dynamic>>()
            .map(_detailsFromJson)
            .toList(growable: false),
        classificationContext: ScrapeClassificationContext(
          targetActressName: corpusCase['actress'] as String,
        ),
      );
      final actual = switch (decision.finalAction) {
        ScrapeFinalAction.keep => 'keep',
        ScrapeFinalAction.exclude => 'exclude',
        ScrapeFinalAction.keepReview => 'review',
      };

      if (expected == 'review') {
        review++;
      } else {
        decisive++;
        if (expected == 'keep') {
          expectedKeep++;
          if (actual == 'exclude') falseExclude++;
        } else if (expected == 'exclude') {
          expectedExclude++;
          if (actual == 'keep') falseKeep++;
        }
        if (actual == expected) correctDecisive++;
      }
      expect(actual, expected, reason: corpusCase['id'] as String);
    }

    expect(decisive, expectedCounts['decisive']);
    expect(review, expectedCounts['ambiguous']);
    expect(expectedKeep, 81);
    expect(expectedExclude, 81);
    expect(correctDecisive / decisive, greaterThanOrEqualTo(0.99));
    expect(falseExclude / expectedKeep, lessThanOrEqualTo(0.0025));
    expect(falseKeep / expectedExclude, lessThanOrEqualTo(0.0075));
    expect(review / cases.length, lessThanOrEqualTo(0.01));
  });
}

ScrapeWorkDetails _detailsFromJson(Map<String, dynamic> value) {
  final source =
      ScrapeSourceId.fromStorage(value['source'] as String?) ??
      ScrapeSourceId.javbus;
  final factsJson =
      (value['facts'] as Map?)?.cast<String, dynamic>() ??
      const <String, dynamic>{};
  final coPerformance = ScrapeCoPerformance.values.firstWhere(
    (item) => item.name == factsJson['coPerformance'],
    orElse: () => ScrapeCoPerformance.unknown,
  );
  final facts = ScrapeWorkProvenanceFacts(
    includedWorks: _strings(factsJson['includedWorks']),
    parentWorks: _strings(factsJson['parentWorks']),
    packageOfPriorWorks: factsJson['packageOfPriorWorks'] as bool?,
    reusedIndependentSegments: factsJson['reusedIndependentSegments'] as bool?,
    coPerformance: coPerformance,
  );
  final code = value['code'] as String? ?? 'CORPUS-UNKNOWN';
  return ScrapeWorkDetails(
    source: source,
    code: code,
    rawCode: code,
    title: value['title'] as String? ?? '',
    releaseDate: null,
    performerCount: value['performerCount'] as int?,
    provenanceFacts: facts,
    coPerformance: coPerformance,
  );
}

List<String> _strings(Object? value) => value is Iterable
    ? value.map((item) => item.toString()).toList(growable: false)
    : const [];
