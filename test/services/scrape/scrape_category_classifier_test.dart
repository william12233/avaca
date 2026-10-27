import 'package:avaca/models/scrape_source_settings.dart';
import 'package:avaca/models/scrape_exclusion_policy.dart';
import 'package:avaca/models/scrape_work_category.dart';
import 'package:avaca/services/scrape/scrape_category_classifier.dart';
import 'package:avaca/services/scrape/scrape_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps source-declared catalog tags to stable categories', () {
    final classification = ScrapeCategoryClassifier.classify(
      catalogEvidence: [
        const ScrapeCatalogWorkEvidence(
          source: ScrapeSourceId.avwiki,
          tags: ['VR専用'],
          series: '通常作品',
        ),
      ],
    );

    expect(classification.categories, contains(ScrapeWorkCategory.vr));
    expect(classification.sources, contains(ScrapeSourceId.avwiki));
  });

  test('uses detail genres and provenance tags as category evidence', () {
    final classification = ScrapeCategoryClassifier.classify(
      details: [
        const ScrapeWorkDetails(
          source: ScrapeSourceId.javbus,
          code: 'TEST-001',
          title: 'A title that does not define a category',
          genres: ['寫真'],
          provenanceFacts: ScrapeWorkProvenanceFacts(tags: ['3P']),
        ),
      ],
    );

    expect(
      classification.categories,
      containsAll([ScrapeWorkCategory.photo, ScrapeWorkCategory.multi]),
    );
  });

  test('selected categories use OR matching', () {
    final classification = ScrapeCategoryClassifier.classify(
      details: [
        const ScrapeWorkDetails(
          source: ScrapeSourceId.javbus,
          code: 'TEST-001',
          title: 'Photo work',
          genres: ['写真'],
        ),
      ],
    );

    final decision = ScrapeCategoryClassifier.decide(
      selectedCategories: const [
        ScrapeWorkCategory.single,
        ScrapeWorkCategory.photo,
      ],
      classification: classification,
    );

    expect(decision.finalAction, ScrapeFinalAction.keep);
    expect(decision.reason, 'category_match');
    expect(decision.reviewRequired, isFalse);
  });

  test('known non-selected categories are excluded', () {
    final classification = ScrapeCategoryClassifier.classify(
      details: [
        const ScrapeWorkDetails(
          source: ScrapeSourceId.javbus,
          code: 'TEST-001',
          title: 'Multi-performer work',
          genres: ['多人'],
        ),
      ],
    );

    final decision = ScrapeCategoryClassifier.decide(
      selectedCategories: const [ScrapeWorkCategory.single],
      classification: classification,
    );

    expect(decision.finalAction, ScrapeFinalAction.exclude);
    expect(decision.reason, 'category_not_selected');
  });

  test(
    'unknown works are kept for review and are not inferred from code or count',
    () {
      final classification = ScrapeCategoryClassifier.classify(
        details: [
          const ScrapeWorkDetails(
            source: ScrapeSourceId.javbus,
            code: 'VR-001',
            title: 'VR title',
            performerCount: 2,
          ),
        ],
      );

      final decision = ScrapeCategoryClassifier.decide(
        selectedCategories: const [ScrapeWorkCategory.vr],
        classification: classification,
      );

      expect(classification.categories, isEmpty);
      expect(decision.finalAction, ScrapeFinalAction.keepReview);
      expect(decision.reason, 'category_unresolved');
      expect(decision.toMetadata()['categoryPolicyVersion'], 'category-v1');
    },
  );

  test('no selected category disables the whitelist', () {
    final classification = ScrapeCategoryClassifier.classify(
      details: [
        const ScrapeWorkDetails(
          source: ScrapeSourceId.javbus,
          code: 'TEST-001',
          title: 'Unclassified work',
        ),
      ],
    );

    final decision = ScrapeCategoryClassifier.decide(
      selectedCategories: const [],
      classification: classification,
    );

    expect(decision.finalAction, ScrapeFinalAction.keep);
    expect(decision.reason, 'category_filter_disabled');
  });
}
