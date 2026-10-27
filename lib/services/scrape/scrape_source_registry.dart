import '../../models/scrape_source_settings.dart';

class ScrapeSourceRegistry {
  const ScrapeSourceRegistry._();

  static const List<ScrapeSourceId> aggregatePriority = [
    ScrapeSourceId.avwiki,
    ScrapeSourceId.avbase,
    ScrapeSourceId.javbus,
  ];

  static const List<ScrapeSourceId> worksSources = [
    ScrapeSourceId.javbus,
    ScrapeSourceId.avbase,
    ScrapeSourceId.avwiki,
  ];

  /// Sources that can answer one work code and expose category evidence.
  ///
  /// Keep this ordered so automatic evidence lookups are deterministic. The
  /// catalog-oriented sources are preferred before the detail-only source.
  static const List<ScrapeSourceId> categoryEvidenceSources = [
    ScrapeSourceId.avbase,
    ScrapeSourceId.avwiki,
    ScrapeSourceId.javbus,
  ];

  static List<ScrapeSourceId> resolveWorksSources(
    Iterable<ScrapeSourceId> selected,
  ) {
    final resolved = <ScrapeSourceId>[];
    for (final source in selected) {
      if (worksSources.contains(source) && !resolved.contains(source)) {
        resolved.add(source);
      }
    }
    return resolved.isEmpty
        ? const [ScrapeSourceId.javbus]
        : List.unmodifiable(resolved);
  }
}
