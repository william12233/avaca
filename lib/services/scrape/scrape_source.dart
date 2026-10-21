import '../../models/scrape_source_settings.dart';
import 'scrape_models.dart';

final class ScrapeCollectionProgress {
  const ScrapeCollectionProgress({
    required this.currentPage,
    required this.totalPages,
    required this.discovered,
  });

  final int currentPage;
  final int totalPages;
  final int discovered;
}

abstract interface class ScrapeSource {
  ScrapeSourceId get id;

  Future<List<ScrapeActressSearchResult>> searchActresses(String name);

  Future<ScrapeActressPage> fetchActressPage(ScrapeActressSearchResult actress);

  Future<List<ScrapeWorkSummary>> fetchActressWorks(
    ScrapeActressSearchResult actress, {
    required ScrapeActressPage firstPage,
    bool Function()? isCancelled,
    void Function(ScrapeCollectionProgress progress)? onProgress,
  });

  Future<ScrapeWorkDetails> fetchWorkDetails(ScrapeWorkSummary work);

  bool acceptsImageUri(Uri uri);

  void close();
}

/// Optional capability for conditional provenance escalation.  A source that
/// implements this interface can answer one exact canonical work code without
/// collecting the actress catalog again.
abstract interface class ScrapeSourceWorkCodeLookup {
  Future<ScrapeWorkDetails?> fetchWorkDetailsByCode(String canonicalCode);
}

/// Optional source-owned diagnostics for partial pagination or access
/// problems. Sources that do not need this remain compatible with the base
/// interface.
abstract interface class ScrapeSourceDiagnosticsProvider {
  ScrapeSourceRunDiagnostic? get lastRunDiagnostic;

  void resetRunDiagnostic();
}
