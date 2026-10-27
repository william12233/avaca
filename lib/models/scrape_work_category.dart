enum ScrapeWorkCategory {
  single('single'),
  multi('multi'),
  photo('photo'),
  retrospective('retrospective'),
  vr('vr');

  const ScrapeWorkCategory(this.storageValue);

  final String storageValue;

  static ScrapeWorkCategory? fromStorage(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    for (final category in values) {
      if (category.storageValue == normalized) return category;
    }
    return null;
  }
}

extension ScrapeWorkCategoryListCodec on Iterable<ScrapeWorkCategory> {
  List<String> get storageValues =>
      map((category) => category.storageValue).toList(growable: false);
}
