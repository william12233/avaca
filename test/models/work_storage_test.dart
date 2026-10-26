import 'package:avaca/models/work_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts with no storage options or metadata selected', () {
    const record = WorkStorageRecord();

    expect(record.isStored, isFalse);
    expect(record.storageOptions, isEmpty);
    expect(record.quality, isNull);
    expect(record.frameRate, isNull);
    expect(WorkStorageRecord.qualities, contains('4K'));
  });

  test('derives stored state from multiple storage options', () {
    const record = WorkStorageRecord(
      storageOptions: {WorkStorageOption.cracked, WorkStorageOption.subtitles},
      quality: '4K',
      frameRate: 60,
    );

    expect(record.isStored, isTrue);
    expect(record.toDatabaseMap(), {
      'is_stored': 1,
      'storage_cracked': 1,
      'storage_original': 0,
      'storage_subtitles': 1,
      'storage_quality': '4K',
      'storage_frame_rate': 60,
    });
  });

  test('ignores legacy stored state and metadata without a storage option', () {
    final record = WorkStorageRecord.fromDatabase({
      'is_stored': 1,
      'storage_cracked': 0,
      'storage_original': 0,
      'storage_subtitles': 0,
      'storage_quality': '1080',
      'storage_frame_rate': 60,
    });

    expect(record.isStored, isFalse);
    expect(record.quality, isNull);
    expect(record.frameRate, isNull);
  });

  test('copyWith can clear nullable metadata', () {
    const record = WorkStorageRecord(
      storageOptions: {WorkStorageOption.original},
      quality: '2K',
      frameRate: 30,
    );

    expect(
      record.copyWith(quality: null, frameRate: null),
      const WorkStorageRecord(storageOptions: {WorkStorageOption.original}),
    );
  });
}
