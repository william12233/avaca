import 'dart:io';

import 'package:path/path.dart' as path;

import '../core/database.dart';
import '../models/scrape_source_settings.dart';
import '../models/scraped_actress_details.dart';
import 'avbase/avbase_client.dart';
import 'avbase/avbase_scrape_source.dart';
import 'avbase/avbase_transport.dart';
import 'avwiki/avwiki_client.dart';
import 'avwiki/avwiki_scrape_source.dart';
import 'avwiki/avwiki_transport.dart';
import 'javbus/javbus_client.dart';
import 'javbus/javbus_scrape_source.dart';
import 'javbus/javbus_verification.dart';
import 'minnano/minnano_client.dart';
import 'minnano/minnano_scrape_source.dart';
import 'minnano/minnano_transport.dart';
import 'scrape/scrape_source.dart';
import 'scrape/scrape_models.dart';
import 'works_scrape_service.dart';
import 'javbus/work_image_downloader.dart';
import 'actress_discovery/actress_discovery_models.dart';

enum ActressImportStatus { added, addedIncomplete, skipped, failed }

final class ActressImportResult {
  const ActressImportResult({
    required this.item,
    required this.status,
    this.actressId,
    this.error,
  });

  final ActressDiscoveryItem item;
  final ActressImportStatus status;
  final int? actressId;
  final Object? error;
}

final class ActressImportBatchResult {
  const ActressImportBatchResult(this.results);

  final List<ActressImportResult> results;

  int get addedCount => results
      .where(
        (result) =>
            result.status == ActressImportStatus.added ||
            result.status == ActressImportStatus.addedIncomplete,
      )
      .length;

  int get incompleteCount => results
      .where((result) => result.status == ActressImportStatus.addedIncomplete)
      .length;

  int get skippedCount => results
      .where((result) => result.status == ActressImportStatus.skipped)
      .length;

  int get failedCount => results
      .where((result) => result.status == ActressImportStatus.failed)
      .length;

  List<int> get addedActressIds => results
      .where(
        (result) =>
            result.actressId != null &&
            (result.status == ActressImportStatus.added ||
                result.status == ActressImportStatus.addedIncomplete),
      )
      .map((result) => result.actressId!)
      .toList(growable: false);
}

/// Imports selected discovery candidates through the user's configured
/// actress-detail source.  Discovery source URLs are never persisted as the
/// detail source or as a new setting.
final class ActressImportService {
  ActressImportService({required this.db, this.verificationHandler});

  final AppDatabase db;
  final JavBusVerificationHandler? verificationHandler;

  Future<ActressImportBatchResult> importItems({
    required Iterable<ActressDiscoveryItem> items,
    required ScrapeSourceId detailsSource,
  }) async {
    final selected = items.toList(growable: false);
    if (selected.isEmpty) return const ActressImportBatchResult([]);

    await db.database;
    _ActressDetailsSession? createdSession;
    Object? sessionError;
    try {
      createdSession = await _createDetailsSession(detailsSource);
    } on Object catch (error) {
      sessionError = error;
    }
    if (createdSession == null) {
      final results = <ActressImportResult>[];
      for (final item in selected) {
        results.add(await _saveNameOnly(item, sessionError));
      }
      return ActressImportBatchResult(List.unmodifiable(results));
    }
    final session = createdSession;
    final results = <ActressImportResult>[];
    try {
      for (final item in selected) {
        results.add(await _importOne(item, session));
      }
      final cookies = session.javBusTransport?.cookieHeader.trim();
      if (cookies != null && cookies.isNotEmpty) {
        await db.setSetting('javbus_cookies', cookies);
      }
    } finally {
      session.close();
    }
    return ActressImportBatchResult(List.unmodifiable(results));
  }

  Future<ActressImportResult> _importOne(
    ActressDiscoveryItem item,
    _ActressDetailsSession session,
  ) async {
    final existingId = await db.findActressIdByName(item.name);
    if (existingId != null) {
      return ActressImportResult(
        item: item.copyWith(alreadyCollected: true),
        status: ActressImportStatus.skipped,
        actressId: existingId,
      );
    }

    ScrapeActressPage? page;
    Object? detailError;
    try {
      final matches = await session.source.searchActresses(item.name);
      final match = _bestMatch(item.name, matches);
      if (match != null) {
        page = await session.source.fetchActressPage(match);
      } else {
        detailError = StateError('No exact actress match for ${item.name}.');
      }
    } on Object catch (error) {
      detailError = error;
    }

    String? imagePath;
    Object? imageError;
    final details = page?.details;
    final avatar = details?.avatarUrl;
    if (details != null &&
        avatar != null &&
        session.source.acceptsImageUri(avatar) &&
        session.imageDownloader != null) {
      final targetPath = path.join(
        db.imgDir,
        'actresses',
        'actress_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      try {
        imagePath = await session.imageDownloader!.download(avatar, targetPath);
      } on Object catch (error) {
        imageError = error;
      }
    }

    final id = await db.addActressAndGetId(
      name: item.name,
      imgPath: imagePath,
      birthDate: _validDate(details?.birthDate),
    );
    if (id == null) {
      if (imagePath != null) await _deleteIfExists(imagePath);
      final racedId = await db.findActressIdByName(item.name);
      if (racedId != null) {
        return ActressImportResult(
          item: item.copyWith(alreadyCollected: true),
          status: ActressImportStatus.skipped,
          actressId: racedId,
        );
      }
      return ActressImportResult(
        item: item,
        status: ActressImportStatus.failed,
        error: StateError('Could not save ${item.name}.'),
      );
    }

    var incomplete =
        detailError != null ||
        imageError != null ||
        details == null ||
        details.avatarUrl == null ||
        imagePath == null;
    if (details != null) {
      final synced = await db.syncActressDetails(
        actressId: id,
        details: ScrapedActressDetails(
          name: details.name ?? item.name,
          imagePath: imagePath,
          avatarUrl: details.avatarUrl,
          birthDate: details.birthDate,
          height: details.height,
          cup: details.cup,
          bust: details.bust,
          waist: details.waist,
          hip: details.hip,
        ),
        missingOnly: true,
        replaceImage: imagePath != null,
      );
      incomplete = incomplete || !synced;
      final aliases = page?.aliases ?? const <String>[];
      if (aliases.isNotEmpty) {
        try {
          await db.replaceActressAliases(actressId: id, aliases: aliases);
        } on Object {
          incomplete = true;
        }
      }
    } else {
      incomplete = true;
    }

    return ActressImportResult(
      item: item,
      status: incomplete
          ? ActressImportStatus.addedIncomplete
          : ActressImportStatus.added,
      actressId: id,
      error: detailError ?? imageError,
    );
  }

  Future<ActressImportResult> _saveNameOnly(
    ActressDiscoveryItem item,
    Object? error,
  ) async {
    final existingId = await db.findActressIdByName(item.name);
    if (existingId != null) {
      return ActressImportResult(
        item: item.copyWith(alreadyCollected: true),
        status: ActressImportStatus.skipped,
        actressId: existingId,
      );
    }
    final id = await db.addActressAndGetId(name: item.name);
    if (id == null) {
      final racedId = await db.findActressIdByName(item.name);
      if (racedId != null) {
        return ActressImportResult(
          item: item.copyWith(alreadyCollected: true),
          status: ActressImportStatus.skipped,
          actressId: racedId,
        );
      }
      return ActressImportResult(
        item: item,
        status: ActressImportStatus.failed,
        error: error ?? StateError('Could not save ${item.name}.'),
      );
    }
    return ActressImportResult(
      item: item,
      status: ActressImportStatus.addedIncomplete,
      actressId: id,
      error: error,
    );
  }

  ScrapeActressSearchResult? _bestMatch(
    String requested,
    List<ScrapeActressSearchResult> matches,
  ) {
    final key = requested.trim().toLowerCase();
    for (final match in matches) {
      if (match.name.trim().toLowerCase() == key) return match;
    }
    return null;
  }

  String? _validDate(String? value) {
    final trimmed = value?.trim();
    return trimmed != null && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(trimmed)
        ? trimmed
        : null;
  }

  Future<_ActressDetailsSession> _createDetailsSession(
    ScrapeSourceId sourceId,
  ) async {
    switch (sourceId) {
      case ScrapeSourceId.minnanoAv:
        final transport = HttpMinnanoTransport();
        final client = MinnanoClient(transport: transport);
        return _ActressDetailsSession(
          source: MinnanoScrapeSource(client),
          imageDownloader: HttpActressImageDownloader(
            transport: HttpBinaryTransport(
              allowedHosts: const {'www.minnano-av.com'},
              maxBytes: 5 * 1024 * 1024,
            ),
          ),
        );
      case ScrapeSourceId.javbus:
        final transport = HttpJavBusTransport(
          initialCookieHeader: await db.getSetting('javbus_cookies'),
          verificationHandler: verificationHandler,
        );
        return _ActressDetailsSession(
          source: JavBusScrapeSource(JavBusClient(transport: transport)),
          imageDownloader: HttpActressImageDownloader(
            authenticatedTransport: transport,
          ),
          javBusTransport: transport,
        );
      case ScrapeSourceId.avbase:
        final transport = HttpAvBaseTransport();
        final client = AvBaseClient(transport: transport);
        return _ActressDetailsSession(
          source: AvBaseScrapeSource(client),
          imageDownloader: HttpActressImageDownloader(
            transport: HttpBinaryTransport(
              allowedHosts: const {'pics.dmm.co.jp'},
              maxBytes: 5 * 1024 * 1024,
            ),
          ),
        );
      case ScrapeSourceId.avwiki:
        final source = AvWikiScrapeSource(
          AvWikiClient(transport: HttpAvWikiTransport()),
        );
        return _ActressDetailsSession(source: source);
      case ScrapeSourceId.javdb:
        throw StateError('JAVDB cannot be used as the actress detail source.');
    }
  }

  Future<void> _deleteIfExists(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) await file.delete();
    } on Object {
      // A failed cleanup must not hide the database/import result.
    }
  }
}

final class _ActressDetailsSession {
  _ActressDetailsSession({
    required this.source,
    this.imageDownloader,
    this.javBusTransport,
  });

  final ScrapeSource source;
  final ActressImageDownloader? imageDownloader;
  final HttpJavBusTransport? javBusTransport;

  void close() {
    source.close();
    final downloader = imageDownloader;
    if (downloader is HttpActressImageDownloader) downloader.close();
  }
}
