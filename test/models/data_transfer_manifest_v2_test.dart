import 'package:flutter_test/flutter_test.dart';

import 'package:avaca/models/data_transfer_manifest.dart';

void main() {
  test('v1 manifest remains importable without provenance', () {
    final manifest = DataTransferManifest.fromJson({
      'format': 'avaca-data',
      'version': 1,
      'exportedAt': '2026-08-23T00:00:00Z',
      'actresses': [],
      'works': [
        {
          'id': 'w000001',
          'code': 'ABC-123',
          'title': 'Title',
          'releaseDate': null,
          'durationMinutes': null,
          'studio': null,
          'publisher': null,
          'series': null,
          'cardImageAssetId': null,
          'detailImageAssetId': null,
          'createdAt': null,
          'modifiedAt': null,
        },
      ],
      'relations': [],
      'assets': [],
    });

    expect(manifest.works.single.provenance, isEmpty);
  });

  test('v3 manifest round trip preserves storage options and provenance', () {
    final manifest = DataTransferManifest(
      exportedAt: '2026-08-23T00:00:00Z',
      actresses: const [],
      works: const [
        DataTransferWork(
          id: 'w000001',
          code: 'ABC-123',
          title: 'Title',
          releaseDate: null,
          durationMinutes: null,
          studio: null,
          publisher: null,
          series: null,
          cardImageAssetId: null,
          detailImageAssetId: null,
          createdAt: null,
          modifiedAt: null,
          storageOptions: ['cracked', 'subtitles'],
          storageQuality: '4K',
          storageFrameRate: 60,
          provenance: [
            DataTransferProvenance(field: 'title', source: 'javbus'),
          ],
        ),
      ],
      relations: const [],
      assets: const [],
    );

    final decoded = DataTransferManifest.fromJson(manifest.toJson());

    expect(decoded.works.single.provenance.single.source, 'javbus');
    expect(decoded.works.single.storageOptions, ['cracked', 'subtitles']);
    expect(decoded.works.single.storageQuality, '4K');
    expect(decoded.works.single.storageFrameRate, 60);
    expect(decoded.toJson()['version'], 3);
  });

  test('legacy isStored does not recreate storage without an option', () {
    final manifest = DataTransferManifest.fromJson({
      'format': 'avaca-data',
      'version': 2,
      'exportedAt': '2026-08-23T00:00:00Z',
      'actresses': [],
      'works': [
        {
          'id': 'w000001',
          'code': 'ABC-124',
          'title': 'Legacy storage',
          'releaseDate': null,
          'durationMinutes': null,
          'studio': null,
          'publisher': null,
          'series': null,
          'cardImageAssetId': null,
          'detailImageAssetId': null,
          'createdAt': null,
          'modifiedAt': null,
          'isStored': true,
          'storageQuality': '1080',
          'storageFrameRate': 60,
        },
      ],
      'relations': [],
      'assets': [],
    });

    expect(manifest.works.single.storageOptions, isEmpty);
  });
}
