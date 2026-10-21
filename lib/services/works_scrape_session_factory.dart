import '../core/database.dart';
import '../models/scrape_job.dart';
import '../models/scrape_exclusion_policy.dart';
import '../models/scrape_source_settings.dart';
import '../models/work_scrape_options.dart';
import 'avbase/avbase_client.dart';
import 'avbase/avbase_scrape_source.dart';
import 'avbase/avbase_transport.dart';
import 'avwiki/avwiki_client.dart';
import 'avwiki/avwiki_scrape_source.dart';
import 'avwiki/avwiki_transport.dart';
import 'javbus/javbus_client.dart';
import 'javbus/javbus_scrape_source.dart';
import 'javbus/javbus_verification.dart';
import 'javbus/work_image_downloader.dart';
import 'minnano/minnano_client.dart';
import 'minnano/minnano_scrape_source.dart';
import 'minnano/minnano_transport.dart';
import 'scrape/scrape_image_downloader.dart';
import 'scrape/scrape_source.dart';
import 'scrape/scrape_source_registry.dart';
import 'works_scrape_service.dart';

class WorksScrapeSession {
  WorksScrapeSession({
    required this.service,
    required this.javBusTransport,
    required this.policySnapshot,
  });

  final WorksScrapeService service;
  final HttpJavBusTransport? javBusTransport;
  final ScrapePolicySnapshot policySnapshot;
}

class WorksScrapeSessionFactory {
  WorksScrapeSessionFactory({required this.db});

  final AppDatabase db;

  Future<WorksScrapeSession> create(
    ScrapeJob job, {
    JavBusVerificationHandler? verificationHandler,
  }) async {
    final sourceSettings = ScrapeSourceSettings.decode(
      job.sourceSettingsSnapshot,
    );
    final options = WorkScrapeOptions.decode(job.optionsSnapshot);
    final policySnapshot = ScrapePolicySnapshot.fromEncoded(
      encoded: job.rulesSnapshot,
      exactAllows: options.exactAllows,
      autoExcludeDerivedWorks: options.autoExcludeDerivedWorks,
      exactDenies: options.exactDenies,
    );
    final requestedSourceIds = <ScrapeSourceId>{
      sourceSettings.actressDetailsSource,
      ...ScrapeSourceRegistry.resolveWorksSources(sourceSettings.worksSources),
    };
    if (options.scrapeAliases) {
      requestedSourceIds.add(sourceSettings.aliasSource);
    }
    final configuredSources = <ScrapeSourceId, ScrapeSource>{};
    HttpJavBusTransport? javBusTransport;
    HttpMinnanoTransport? minnanoTransport;
    MinnanoClient? minnanoClient;
    HttpBinaryTransport? minnanoAvatarTransport;
    HttpAvBaseTransport? avbaseTransport;
    AvBaseClient? avbaseClient;
    HttpBinaryTransport? avbaseAvatarTransport;
    HttpScrapeImageUriDownloader? imageUriDownloader;

    if (requestedSourceIds.contains(ScrapeSourceId.javbus)) {
      javBusTransport = HttpJavBusTransport(
        initialCookieHeader: await db.getSetting('javbus_cookies'),
        verificationHandler: verificationHandler,
      );
      configuredSources[ScrapeSourceId.javbus] = JavBusScrapeSource(
        JavBusClient(transport: javBusTransport),
      );
    }
    if (requestedSourceIds.contains(ScrapeSourceId.minnanoAv)) {
      minnanoTransport = HttpMinnanoTransport();
      minnanoClient = MinnanoClient(transport: minnanoTransport);
      configuredSources[ScrapeSourceId.minnanoAv] = MinnanoScrapeSource(
        minnanoClient,
      );
      minnanoAvatarTransport = HttpBinaryTransport(
        allowedHosts: const {'www.minnano-av.com'},
        maxBytes: 5 * 1024 * 1024,
      );
      imageUriDownloader = HttpScrapeImageUriDownloader(
        isAllowed: minnanoClient.acceptsImageUri,
        transport: HttpBinaryTransport(
          allowedHosts: const {'www.minnano-av.com'},
          maxBytes: 15 * 1024 * 1024,
        ),
      );
    }
    if (requestedSourceIds.contains(ScrapeSourceId.avbase)) {
      avbaseTransport = HttpAvBaseTransport();
      avbaseClient = AvBaseClient(transport: avbaseTransport);
      configuredSources[ScrapeSourceId.avbase] = AvBaseScrapeSource(
        avbaseClient,
      );
      avbaseAvatarTransport = HttpBinaryTransport(
        allowedHosts: const {'pics.dmm.co.jp'},
        maxBytes: 5 * 1024 * 1024,
      );
    }
    if (requestedSourceIds.contains(ScrapeSourceId.avwiki)) {
      final transport = HttpAvWikiTransport();
      final client = AvWikiClient(transport: transport);
      configuredSources[ScrapeSourceId.avwiki] = AvWikiScrapeSource(client);
    }

    final detailsImageDownloader =
        switch (sourceSettings.actressDetailsSource) {
          ScrapeSourceId.minnanoAv => HttpActressImageDownloader(
            transport: minnanoAvatarTransport,
          ),
          ScrapeSourceId.avbase => HttpActressImageDownloader(
            transport: avbaseAvatarTransport,
          ),
          ScrapeSourceId.javbus => HttpActressImageDownloader(
            authenticatedTransport: javBusTransport,
          ),
          ScrapeSourceId.avwiki => HttpActressImageDownloader(
            transport: HttpBinaryTransport(
              allowedHosts: const {'av-wiki.net', 'www.av-wiki.net'},
              maxBytes: 5 * 1024 * 1024,
            ),
          ),
        };
    final service = WorksScrapeService(
      db: db,
      sources: configuredSources,
      actressImageDownloader: detailsImageDownloader,
      imageUriDownloader: imageUriDownloader,
    );
    return WorksScrapeSession(
      service: service,
      javBusTransport: javBusTransport,
      policySnapshot: policySnapshot,
    );
  }

  Future<List<String>> aliasesFor(int actressId) async {
    final database = await db.database;
    final rows = await database.query(
      'actress_aliases',
      columns: const ['alias'],
      where: 'actress_id = ?',
      whereArgs: [actressId],
      orderBy: 'alias COLLATE NOCASE ASC',
    );
    return rows
        .map((row) => row['alias']?.toString().trim() ?? '')
        .where((alias) => alias.isNotEmpty)
        .toList(growable: false);
  }

  Future<String> actressNameFor(int actressId) async {
    final database = await db.database;
    final rows = await database.query(
      'actresses',
      columns: const ['name'],
      where: 'id = ?',
      whereArgs: [actressId],
      limit: 1,
    );
    return rows.firstOrNull?['name']?.toString().trim() ?? '';
  }
}
