import 'dart:async';

import 'package:avaca/core/database.dart';
import 'package:avaca/services/javbus/prefix_route_repository.dart';
import 'package:avaca/services/javbus/work_image_downloader.dart';
import 'package:avaca/services/javbus/work_image_policy.dart';
import 'package:avaca/services/javbus/work_image_route_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  late List<int> validImage;

  setUp(() {
    validImage = image.encodePng(image.Image(width: 300, height: 450));
  });

  test('prioritizes known leading-one families for START and STARS', () async {
    final repository = PrefixRouteRepository.inMemory();
    await repository.ensureLoaded();

    expect(
      repository.orderedFamiliesFor('START').first,
      WorkImageNormalizationFamily.dmmLeadingOne,
    );
    expect(
      repository.orderedFamiliesFor('STARS').first,
      WorkImageNormalizationFamily.dmmLeadingOne,
    );
  });

  test(
    'unknown Prefix probes deterministically and learns the first success',
    () async {
      final repository = PrefixRouteRepository.inMemory();
      final transport = _SequenceBinaryTransport([
        const BinaryResponse(statusCode: 404, bodyBytes: []),
        const BinaryResponse(statusCode: 404, bodyBytes: []),
        BinaryResponse(statusCode: 200, bodyBytes: validImage),
      ]);
      final downloader = WorkImageDownloader(
        transport: transport,
        routeRepository: repository,
      );

      await downloader.fetch(code: 'ABC-123', variant: WorkImageVariant.card);

      expect(transport.requested, hasLength(3));
      expect(transport.requested[0].path, contains('abc00123'));
      expect(transport.requested[1].path, contains('1abc00123'));
      expect(transport.requested[2].path, contains('h_1711abc00123'));
      final rule = repository.ruleFor('abc')!;
      expect(rule.preferredFamily, WorkImageNormalizationFamily.dmmH1711);
      expect(
        rule
            .candidateFor(WorkImageNormalizationFamily.dmmStandard)!
            .failureCount,
        1,
      );
      expect(
        rule
            .candidateFor(WorkImageNormalizationFamily.dmmLeadingOne)!
            .failureCount,
        1,
      );
      expect(
        rule.candidateFor(WorkImageNormalizationFamily.dmmH1711)!.successCount,
        1,
      );
    },
  );

  test('learned Prefix uses one family on the next work', () async {
    final repository = PrefixRouteRepository.inMemory();
    final firstTransport = _SequenceBinaryTransport([
      const BinaryResponse(statusCode: 404, bodyBytes: []),
      BinaryResponse(statusCode: 200, bodyBytes: validImage),
    ]);
    final firstDownloader = WorkImageDownloader(
      transport: firstTransport,
      routeRepository: repository,
    );
    await firstDownloader.fetch(
      code: 'ABC-123',
      variant: WorkImageVariant.card,
    );

    final secondTransport = _SequenceBinaryTransport([
      BinaryResponse(statusCode: 200, bodyBytes: validImage),
    ]);
    final secondDownloader = WorkImageDownloader(
      transport: secondTransport,
      routeRepository: repository,
    );
    await secondDownloader.fetch(
      code: 'abc-124',
      variant: WorkImageVariant.detail,
    );

    expect(secondTransport.requested, hasLength(1));
    expect(secondTransport.requested.single.path, contains('1abc00124'));
  });

  test(
    'known route failure falls back without discarding old history',
    () async {
      final repository = PrefixRouteRepository.inMemory();
      await repository.recordSuccess(
        prefix: 'SONE',
        family: WorkImageNormalizationFamily.dmmStandard,
      );
      await repository.recordSuccess(
        prefix: 'SONE',
        family: WorkImageNormalizationFamily.dmmStandard,
      );

      final transport = _SequenceBinaryTransport([
        const BinaryResponse(statusCode: 404, bodyBytes: []),
        BinaryResponse(statusCode: 200, bodyBytes: validImage),
      ]);
      await WorkImageDownloader(
        transport: transport,
        routeRepository: repository,
      ).fetch(code: 'sone-834', variant: WorkImageVariant.card);

      final rule = repository.ruleFor('sone')!;
      expect(rule.preferredFamily, WorkImageNormalizationFamily.dmmLeadingOne);
      expect(
        rule
            .candidateFor(WorkImageNormalizationFamily.dmmStandard)!
            .successCount,
        2,
      );
      expect(
        rule
            .candidateFor(WorkImageNormalizationFamily.dmmStandard)!
            .failureCount,
        1,
      );
      expect(
        rule
            .candidateFor(WorkImageNormalizationFamily.dmmLeadingOne)!
            .successCount,
        1,
      );
    },
  );

  test('HTTP 200 invalid image and placeholder are never learned', () async {
    final placeholder = image.encodePng(image.Image(width: 90, height: 122));
    final repository = PrefixRouteRepository.inMemory();
    final transport = _SequenceBinaryTransport([
      for (var index = 0; index < 6; index++)
        BinaryResponse(statusCode: 200, bodyBytes: placeholder),
    ]);

    await expectLater(
      WorkImageDownloader(
        transport: transport,
        routeRepository: repository,
      ).fetch(code: 'PLACE-001', variant: WorkImageVariant.card),
      throwsA(isA<WorkImageDownloadException>()),
    );
    expect(repository.ruleFor('place'), isNull);

    final invalidRepository = PrefixRouteRepository.inMemory();
    final invalidTransport = _SequenceBinaryTransport([
      for (var index = 0; index < 6; index++)
        const BinaryResponse(statusCode: 200, bodyBytes: [1, 2, 3]),
    ]);
    await expectLater(
      WorkImageDownloader(
        transport: invalidTransport,
        routeRepository: invalidRepository,
      ).fetch(code: 'BAD-001', variant: WorkImageVariant.card),
      throwsA(isA<WorkImageDownloadException>()),
    );
    expect(invalidRepository.ruleFor('bad'), isNull);
  });

  test(
    'temporary network failure stops probing and does not update stats',
    () async {
      final repository = PrefixRouteRepository.inMemory();
      await repository.recordSuccess(
        prefix: 'TEMP',
        family: WorkImageNormalizationFamily.dmmStandard,
      );
      final before = repository.ruleFor('TEMP')!;
      final transport = _SequenceBinaryTransport([
        TimeoutException('test timeout'),
      ]);

      final error = await captureException(
        () => WorkImageDownloader(
          transport: transport,
          routeRepository: repository,
        ).fetch(code: 'temp-002', variant: WorkImageVariant.card),
      );

      expect(error, isA<WorkImageDownloadException>());
      expect(
        (error! as WorkImageDownloadException).kind,
        WorkImageDownloadFailureKind.transientNetwork,
      );
      expect(transport.requested, hasLength(1));
      final after = repository.ruleFor('temp')!;
      expect(
        after
            .candidateFor(WorkImageNormalizationFamily.dmmStandard)!
            .failureCount,
        before
            .candidateFor(WorkImageNormalizationFamily.dmmStandard)!
            .failureCount,
      );
    },
  );

  test(
    'manual override wins and clearing it keeps learned statistics',
    () async {
      final repository = PrefixRouteRepository.inMemory();
      await repository.recordSuccess(
        prefix: 'MAN',
        family: WorkImageNormalizationFamily.dmmStandard,
      );
      await repository.setManualOverride(
        prefix: 'man',
        family: WorkImageNormalizationFamily.mgstagePrestige,
      );

      final transport = _SequenceBinaryTransport([
        BinaryResponse(statusCode: 200, bodyBytes: validImage),
      ]);
      await WorkImageDownloader(
        transport: transport,
        routeRepository: repository,
      ).fetch(code: 'MAN-001', variant: WorkImageVariant.card);
      expect(transport.requested.single.host, 'image.mgstage.com');
      expect(
        transport.requested.single.path,
        contains('/images/prestige/man/001/'),
      );

      await repository.clearManualOverride('MAN');
      final rule = repository.ruleFor('man')!;
      expect(rule.manualOverride, isNull);
      expect(
        rule
            .candidateFor(WorkImageNormalizationFamily.dmmStandard)!
            .successCount,
        1,
      );
      expect(
        rule.candidateFor(WorkImageNormalizationFamily.mgstagePrestige),
        isNotNull,
      );
    },
  );

  test('Prefix normalization shares one rule', () async {
    final repository = PrefixRouteRepository.inMemory();
    await repository.recordSuccess(
      prefix: 'sone',
      family: WorkImageNormalizationFamily.dmmStandard,
    );
    expect(repository.ruleFor('Sone')?.prefix, 'SONE');
    expect(repository.rules, hasLength(1));
  });

  test(
    'rules-only export has schema and imports without unrelated data',
    () async {
      final repository = PrefixRouteRepository.inMemory();
      await repository.recordSuccess(
        prefix: 'EXP',
        family: WorkImageNormalizationFamily.dmmStandard,
      );
      final exported = await repository.exportJson();
      expect(exported, contains('"schemaVersion": 1'));
      expect(exported, contains('"exportMode": "rulesOnly"'));
      expect(exported, isNot(contains('successCount')));
      expect(exported, isNot(contains('createdAt')));
      expect(exported, isNot(contains('updatedAt')));

      final imported = PrefixRouteRepository.inMemory();
      final result = await imported.importJson(exported);
      expect(result.importedRuleCount, 1);
      expect(
        imported.ruleFor('exp')?.preferredFamily,
        WorkImageNormalizationFamily.dmmStandard,
      );
      expect(
        imported
            .ruleFor('exp')!
            .candidateFor(WorkImageNormalizationFamily.dmmStandard)!
            .successCount,
        0,
      );
    },
  );

  test('full route document reload keeps learned statistics', () async {
    final repository = PrefixRouteRepository.inMemory();
    final at = DateTime.utc(2026, 8, 20, 12, 34, 56);
    await repository.recordSuccess(
      prefix: 'RELOAD',
      family: WorkImageNormalizationFamily.dmmStandard,
      at: at,
    );

    final reloaded = PrefixRouteRepository.inMemory(
      initialJson: await repository.exportJson(includeStatistics: true),
    );
    await reloaded.ensureLoaded();
    final candidate = reloaded
        .ruleFor('reload')!
        .candidateFor(WorkImageNormalizationFamily.dmmStandard)!;
    expect(candidate.successCount, 1);
    expect(candidate.lastSuccessAt, at);
  });

  test(
    'database-backed repository survives a new repository instance',
    () async {
      final settings = <String, String>{};
      final firstDatabase = _PrefixRouteDatabase(settings);
      final first = PrefixRouteRepository.forDatabase(firstDatabase);
      await first.recordSuccess(
        prefix: 'PERSIST',
        family: WorkImageNormalizationFamily.mgstagePrestige,
      );

      final secondDatabase = _PrefixRouteDatabase(settings);
      final reloaded = PrefixRouteRepository.forDatabase(secondDatabase);
      await reloaded.ensureLoaded();

      expect(
        reloaded.ruleFor('persist')?.preferredFamily,
        WorkImageNormalizationFamily.mgstagePrestige,
      );
    },
  );

  test('invalid import leaves the existing rule unchanged', () async {
    final repository = PrefixRouteRepository.inMemory();
    await repository.recordSuccess(
      prefix: 'SAFE',
      family: WorkImageNormalizationFamily.dmmStandard,
    );
    await expectLater(
      repository.importJson('{not json'),
      throwsA(isA<PrefixRouteRepositoryException>()),
    );
    expect(
      repository
          .ruleFor('safe')!
          .candidateFor(WorkImageNormalizationFamily.dmmStandard)!
          .successCount,
      1,
    );

    await expectLater(
      repository.importJson(
        '{"schemaVersion":1,"routes":{"SAFE":["notARealFamily"]}}',
      ),
      throwsA(isA<PrefixRouteRepositoryException>()),
    );
    expect(
      repository
          .ruleFor('safe')!
          .candidateFor(WorkImageNormalizationFamily.dmmStandard)!
          .successCount,
      1,
    );
  });

  test('merge preserves local stats and manual override on conflict', () async {
    final local = PrefixRouteRepository.inMemory();
    await local.recordSuccess(
      prefix: 'MERGE',
      family: WorkImageNormalizationFamily.dmmStandard,
    );
    await local.recordSuccess(
      prefix: 'MERGE',
      family: WorkImageNormalizationFamily.dmmStandard,
    );
    await local.setManualOverride(
      prefix: 'MERGE',
      family: WorkImageNormalizationFamily.dmmStandard,
    );

    final external = PrefixRouteRepository.inMemory();
    await external.recordSuccess(
      prefix: 'merge',
      family: WorkImageNormalizationFamily.dmmStandard,
    );
    await external.recordSuccess(
      prefix: 'merge',
      family: WorkImageNormalizationFamily.mgstagePrestige,
    );
    await external.setManualOverride(
      prefix: 'merge',
      family: WorkImageNormalizationFamily.mgstagePrestige,
    );

    final result = await local.importJson(
      await external.exportJson(includeStatistics: true),
    );
    expect(result.manualConflictCount, 1);
    final rule = local.ruleFor('merge')!;
    expect(rule.manualOverride, WorkImageNormalizationFamily.dmmStandard);
    expect(
      rule.candidateFor(WorkImageNormalizationFamily.dmmStandard)!.successCount,
      2,
    );
    expect(
      rule
          .candidateFor(WorkImageNormalizationFamily.mgstagePrestige)!
          .successCount,
      1,
    );
  });

  test(
    'same Prefix concurrent downloads share route discovery, not image bytes',
    () async {
      final repository = PrefixRouteRepository.inMemory();
      final transport = _GateBinaryTransport(validImage);
      final downloader = WorkImageDownloader(
        transport: transport,
        routeRepository: repository,
      );
      final first = downloader.fetch(
        code: 'CON-001',
        variant: WorkImageVariant.card,
      );
      await transport.firstRequest.future;
      final second = downloader.fetch(
        code: 'con-002',
        variant: WorkImageVariant.card,
      );
      await Future<void>.delayed(Duration.zero);
      expect(transport.requested, hasLength(1));
      transport.release();
      await Future.wait([first, second]);
      expect(transport.requested, hasLength(2));
      expect(transport.requested[0].path, contains('con00001'));
      expect(transport.requested[1].path, contains('con00002'));
    },
  );

  test(
    'card and detail share the learned family, not a variant-specific rule',
    () async {
      final repository = PrefixRouteRepository.inMemory();
      final transport = _GateBinaryTransport(validImage);
      final downloader = WorkImageDownloader(
        transport: transport,
        routeRepository: repository,
      );
      final card = downloader.fetch(
        code: 'VAR-001',
        variant: WorkImageVariant.card,
      );
      await transport.firstRequest.future;
      final detail = downloader.fetch(
        code: 'VAR-001',
        variant: WorkImageVariant.detail,
      );
      transport.release();
      await Future.wait([card, detail]);

      expect(transport.requested, hasLength(2));
      expect(transport.requested[0].path, contains('var00001'));
      expect(transport.requested[0].path, endsWith('ps.jpg'));
      expect(transport.requested[1].path, contains('var00001'));
      expect(transport.requested[1].path, endsWith('pl.jpg'));
      expect(repository.rules, hasLength(1));
      expect(repository.ruleFor('var')!.candidates, hasLength(1));
    },
  );

  test('different Prefixes can probe concurrently', () async {
    final repository = PrefixRouteRepository.inMemory();
    final transport = _ParallelGateBinaryTransport(validImage);
    final downloader = WorkImageDownloader(
      transport: transport,
      routeRepository: repository,
    );
    final first = downloader.fetch(
      code: 'AAA-001',
      variant: WorkImageVariant.card,
    );
    final second = downloader.fetch(
      code: 'BBB-001',
      variant: WorkImageVariant.card,
    );
    await transport.twoRequests.future;
    expect(transport.maxActive, greaterThanOrEqualTo(2));
    transport.release();
    await Future.wait([first, second]);
  });
}

Future<Object?> captureException(Future<void> Function() operation) async {
  try {
    await operation();
  } on Object catch (error) {
    return error;
  }
  return null;
}

class _SequenceBinaryTransport implements BinaryTransport {
  _SequenceBinaryTransport(this.outcomes);

  final List<Object> outcomes;
  final List<Uri> requested = [];

  @override
  Future<BinaryResponse> get(Uri uri) async {
    requested.add(uri);
    final outcome = outcomes[requested.length - 1];
    if (outcome is BinaryResponse) {
      return outcome;
    }
    throw outcome;
  }
}

class _GateBinaryTransport implements BinaryTransport {
  _GateBinaryTransport(this.bytes);

  final List<int> bytes;
  final firstRequest = Completer<void>();
  final _release = Completer<void>();
  final List<Uri> requested = [];

  void release() {
    if (!_release.isCompleted) {
      _release.complete();
    }
  }

  @override
  Future<BinaryResponse> get(Uri uri) async {
    requested.add(uri);
    if (!firstRequest.isCompleted) {
      firstRequest.complete();
    }
    await _release.future;
    return BinaryResponse(statusCode: 200, bodyBytes: bytes);
  }
}

class _ParallelGateBinaryTransport implements BinaryTransport {
  _ParallelGateBinaryTransport(this.bytes);

  final List<int> bytes;
  final twoRequests = Completer<void>();
  final _release = Completer<void>();
  final List<Uri> requested = [];
  var active = 0;
  var maxActive = 0;

  void release() {
    if (!_release.isCompleted) {
      _release.complete();
    }
  }

  @override
  Future<BinaryResponse> get(Uri uri) async {
    requested.add(uri);
    active++;
    if (active > maxActive) {
      maxActive = active;
    }
    if (requested.length >= 2 && !twoRequests.isCompleted) {
      twoRequests.complete();
    }
    await _release.future;
    active--;
    return BinaryResponse(statusCode: 200, bodyBytes: bytes);
  }
}

class _PrefixRouteDatabase extends AppDatabase {
  _PrefixRouteDatabase(this.settings);

  final Map<String, String> settings;

  @override
  Future<String?> getSetting(String key) async => settings[key];

  @override
  Future<void> setSetting(String key, String value) async {
    settings[key] = value;
  }

  @override
  Future<void> removeSetting(String key) async {
    settings.remove(key);
  }
}
