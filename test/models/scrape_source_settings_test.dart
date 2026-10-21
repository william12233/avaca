import 'package:avaca/models/scrape_source_settings.dart';
import 'package:avaca/services/scrape/scrape_source_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults to Minnano details and JavBus works source', () {
    const settings = ScrapeSourceSettings();

    expect(settings.actressDetailsSource, ScrapeSourceId.minnanoAv);
    expect(settings.worksSources, [ScrapeSourceId.javbus]);
    expect(settings.aliasSource, ScrapeSourceId.avbase);
  });

  test('round trips selections and tolerates malformed values', () {
    const settings = ScrapeSourceSettings(
      actressDetailsSource: ScrapeSourceId.javbus,
      worksSources: [ScrapeSourceId.avbase, ScrapeSourceId.javbus],
      aliasSource: ScrapeSourceId.avbase,
    );

    expect(
      ScrapeSourceSettings.decode(settings.encode()).actressDetailsSource,
      ScrapeSourceId.javbus,
    );
    expect(ScrapeSourceSettings.decode(settings.encode()).worksSources, [
      ScrapeSourceId.avbase,
      ScrapeSourceId.javbus,
    ]);
    expect(
      ScrapeSourceSettings.decode(settings.encode()).aliasSource,
      ScrapeSourceId.avbase,
    );
    expect(
      ScrapeSourceSettings.decode('{"worksSource":"unknown"}').worksSources,
      [ScrapeSourceId.javbus],
    );
    expect(
      ScrapeSourceSettings.decode('not-json').actressDetailsSource,
      ScrapeSourceId.minnanoAv,
    );
  });

  test('round trips AV-Wiki in the ordered works catalog', () {
    const settings = ScrapeSourceSettings(
      worksSources: [ScrapeSourceId.avwiki, ScrapeSourceId.javbus],
    );

    expect(ScrapeSourceSettings.decode(settings.encode()).worksSources, [
      ScrapeSourceId.avwiki,
      ScrapeSourceId.javbus,
    ]);
    expect(ScrapeSourceRegistry.worksSources, contains(ScrapeSourceId.avwiki));
    expect(
      ScrapeSourceSettings.decode(
        '{"worksSources":["javbus","avwiki","javbus"]}',
      ).worksSources,
      [ScrapeSourceId.javbus, ScrapeSourceId.avwiki],
    );
  });
}
