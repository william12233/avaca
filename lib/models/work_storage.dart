enum WorkStorageFilter { all, stored, notStored }

enum WorkStorageOption {
  cracked('cracked'),
  original('original'),
  subtitles('subtitles');

  const WorkStorageOption(this.storageValue);

  final String storageValue;

  static WorkStorageOption? fromStorageValue(String value) {
    for (final option in values) {
      if (option.storageValue == value) {
        return option;
      }
    }
    return null;
  }
}

class WorkStorageRecord {
  static const Object _unset = Object();

  const WorkStorageRecord({
    this.storageOptions = const <WorkStorageOption>{},
    this.quality,
    this.frameRate,
  });

  static const qualities = <String>['4K', '2K', '1080', '720'];
  static const frameRates = <int>[30, 60];

  final Set<WorkStorageOption> storageOptions;
  final String? quality;
  final int? frameRate;

  bool get isStored => storageOptions.isNotEmpty;

  String get compactLabel {
    final values = <String>[];
    if (quality != null) values.add(quality!);
    if (frameRate != null) values.add('$frameRate');
    return values.join('/');
  }

  WorkStorageRecord copyWith({
    Object? storageOptions = _unset,
    Object? quality = _unset,
    Object? frameRate = _unset,
  }) {
    return WorkStorageRecord(
      storageOptions: identical(storageOptions, _unset)
          ? this.storageOptions
          : storageOptions as Set<WorkStorageOption>,
      quality: identical(quality, _unset) ? this.quality : quality as String?,
      frameRate: identical(frameRate, _unset)
          ? this.frameRate
          : frameRate as int?,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is WorkStorageRecord &&
        _sameOptions(other.storageOptions) &&
        other.quality == quality &&
        other.frameRate == frameRate;
  }

  bool _sameOptions(Set<WorkStorageOption> other) {
    return other.length == storageOptions.length &&
        other.containsAll(storageOptions);
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(
      WorkStorageOption.values
          .where(storageOptions.contains)
          .map((option) => option.index),
    ),
    quality,
    frameRate,
  );

  Map<String, Object?> toDatabaseMap() {
    final stored = isStored;
    return {
      'is_stored': stored ? 1 : 0,
      'storage_cracked': storageOptions.contains(WorkStorageOption.cracked)
          ? 1
          : 0,
      'storage_original': storageOptions.contains(WorkStorageOption.original)
          ? 1
          : 0,
      'storage_subtitles': storageOptions.contains(WorkStorageOption.subtitles)
          ? 1
          : 0,
      'storage_quality': stored ? quality : null,
      'storage_frame_rate': stored ? frameRate : null,
    };
  }

  static WorkStorageRecord fromDatabase(Map<String, Object?> data) {
    final storageOptions = <WorkStorageOption>{};
    if (_asBool(data['storage_cracked'])) {
      storageOptions.add(WorkStorageOption.cracked);
    }
    if (_asBool(data['storage_original'])) {
      storageOptions.add(WorkStorageOption.original);
    }
    if (_asBool(data['storage_subtitles'])) {
      storageOptions.add(WorkStorageOption.subtitles);
    }

    final rawQuality = data['storage_quality']?.toString();
    final quality = storageOptions.isNotEmpty && qualities.contains(rawQuality)
        ? rawQuality
        : null;
    final rawFrameRate = data['storage_frame_rate'];
    final frameRate =
        storageOptions.isNotEmpty &&
            rawFrameRate is num &&
            frameRates.contains(rawFrameRate)
        ? rawFrameRate.toInt()
        : null;
    return WorkStorageRecord(
      storageOptions: storageOptions,
      quality: quality,
      frameRate: frameRate,
    );
  }

  static bool _asBool(Object? value) {
    return switch (value) {
      true => true,
      num number => number != 0,
      String text => text == '1' || text.toLowerCase() == 'true',
      _ => false,
    };
  }
}
