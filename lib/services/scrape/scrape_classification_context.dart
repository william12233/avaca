import 'provenance_semantics.dart';

/// Identity supplied by the active actress scrape to provenance semantics.
///
/// Names are deliberately passed in by the scrape call chain rather than
/// guessed from arbitrary title text.
final class ScrapeClassificationContext {
  const ScrapeClassificationContext({
    required this.targetActressName,
    this.targetAliases = const [],
  });

  final String targetActressName;
  final List<String> targetAliases;

  List<String> get normalizedTargetNames {
    final seen = <String>{};
    final names = <String>[];
    for (final value in [targetActressName, ...targetAliases]) {
      final normalized = ScrapeProvenanceSemantics.normalize(value);
      if (normalized.isNotEmpty && seen.add(normalized)) names.add(normalized);
    }
    return List.unmodifiable(names);
  }
}
