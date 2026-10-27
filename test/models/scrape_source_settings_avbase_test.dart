import 'package:avaca/models/scrape_source_settings.dart';
import 'package:avaca/services/scrape/scrape_source_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ordered work sources round-trip and resolve in user priority', () {
    const settings = ScrapeSourceSettings(
      actressDetailsSource: ScrapeSourceId.avbase,
      worksSources: [ScrapeSourceId.avbase, ScrapeSourceId.javbus],
    );

    expect(
      ScrapeSourceSettings.decode(settings.encode()).actressDetailsSource,
      ScrapeSourceId.avbase,
    );
    expect(ScrapeSourceSettings.decode(settings.encode()).worksSources, [
      ScrapeSourceId.avbase,
      ScrapeSourceId.javbus,
    ]);
    expect(ScrapeSourceRegistry.resolveWorksSources(settings.worksSources), [
      ScrapeSourceId.avbase,
      ScrapeSourceId.javbus,
    ]);
  });

  test('duplicate work sources are sanitized', () {
    expect(
      ScrapeSourceRegistry.resolveWorksSources(const [
        ScrapeSourceId.avwiki,
        ScrapeSourceId.avbase,
        ScrapeSourceId.avbase,
      ]),
      [ScrapeSourceId.avwiki, ScrapeSourceId.avbase],
    );
  });
}
