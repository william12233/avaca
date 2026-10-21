import '../../models/scrape_source_settings.dart';

class ScrapeSourceRegistry {
  const ScrapeSourceRegistry._();

  static const List<ScrapeSourceId> aggregatePriority = [
    ScrapeSourceId.minnanoAv,
    ScrapeSourceId.javbus,
    ScrapeSourceId.avbase,
    ScrapeSourceId.avwiki,
  ];

  static const List<ScrapeSourceId> worksSources = [
    ScrapeSourceId.javbus,
    ScrapeSourceId.avbase,
    ScrapeSourceId.avwiki,
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
