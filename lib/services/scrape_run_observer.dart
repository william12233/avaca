import '../models/scrape_source_settings.dart';
import '../models/scrape_job.dart';
import 'scrape/scrape_models.dart';
import 'works_scrape_service.dart';

enum ScrapeWorkOutcomeState { saved, review, excluded, failed, cancelled }

/// A persistence-facing observer for a single scrape session. Implementations
/// must be cheap and must not make the scrape dependent on journal storage.
abstract class ScrapeRunObserver {
  void onProgress(WorksScrapeProgress progress) {}

  void onWorkDiscovered({
    required String canonicalCode,
    String? rawCode,
    required ScrapeSourceId source,
  }) {}

  void onWorkAttemptStarted({
    required String code,
    required ScrapeSourceId source,
  }) {}

  void onWorkCompleted({
    required String code,
    required ScrapeSourceId source,
    required String state,
    Object? error,
  }) {}

  void onWorkOutcome({
    required String code,
    required ScrapeSourceId source,
    required ScrapeWorkOutcomeState outcome,
    Object? error,
    String? reason,
    Iterable<String> imageFailureVariants = const <String>[],
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {}

  void onSourceResult(ScrapeSourceRunResult result) {}

  void onError({required String stage, Object? error, String? code}) {}
}

extension ScrapeWorkDetailsProvenance on ScrapeWorkDetails {
  List<WorkFieldProvenance> provenanceFor(int workId) {
    final result = <WorkFieldProvenance>[];
    for (final entry in fieldSources.entries) {
      result.add(
        WorkFieldProvenance(
          workId: workId,
          field: entry.key,
          source: entry.value.source,
          sourceUri: entry.value.sourceUri,
          observedAt: DateTime.now().toUtc(),
        ),
      );
    }
    return result;
  }
}
