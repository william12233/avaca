/// Stable, storage-facing filters for the actress gallery.
///
/// Keep these values independent from localized labels so the UI can change
/// locale without changing the database contract.
enum ActressFilter { all, censored, uncensored, western, fc2, domestic }

extension ActressFilterStorage on ActressFilter {
  String get storageValue => switch (this) {
    ActressFilter.all => '全部',
    ActressFilter.censored => '有碼',
    ActressFilter.uncensored => '無碼',
    ActressFilter.western => '歐美',
    ActressFilter.fc2 => 'FC2',
    ActressFilter.domestic => '國產',
  };
}

enum ActressSort {
  createdDesc,
  createdAsc,
  modifiedDesc,
  modifiedAsc,
  ageAsc,
  ageDesc,
  nameAsc,
  nameDesc,
}

extension ActressSortStorage on ActressSort {
  String get storageValue => switch (this) {
    ActressSort.createdDesc => '新增時間 (新到舊)',
    ActressSort.createdAsc => '新增時間 (舊到新)',
    ActressSort.modifiedDesc => '修改時間 (新到舊)',
    ActressSort.modifiedAsc => '修改時間 (舊到新)',
    ActressSort.ageAsc => '年齡 (低到高)',
    ActressSort.ageDesc => '年齡 (高到低)',
    ActressSort.nameAsc => '名稱 (A-Z)',
    ActressSort.nameDesc => '名稱 (Z-A)',
  };
}

class ActressQuery {
  const ActressQuery({
    this.searchKeyword = '',
    this.filter = ActressFilter.all,
    this.sort = ActressSort.createdDesc,
  });

  final String searchKeyword;
  final ActressFilter filter;
  final ActressSort sort;
}
