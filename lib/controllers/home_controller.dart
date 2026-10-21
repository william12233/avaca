import 'package:flutter/material.dart';
import '../models/actress_query.dart';
import '../core/database.dart';

final class HomeSearchState {
  const HomeSearchState({
    required this.isOpen,
    required this.searchValue,
    required this.refreshGallery,
  });

  final bool isOpen;
  final String searchValue;
  final bool refreshGallery;
}

/// 管理首頁的搜尋、篩選、排序與頁面導向狀態。
class HomeController {
  HomeController({required this.db});

  final AppDatabase db;

  String currentSearch = '';
  String currentFilter = 'all';
  String currentSort = 'created_desc';
  bool isSearchOpen = false;

  /// 取得首頁可用的篩選選項。
  List<String> getFilterOptions() {
    return ['all', 'censored', 'uncensored', 'western', 'fc2', 'domestic'];
  }

  /// 取得首頁可用的排序選項。
  List<String> getSortOptions() {
    return [
      'created_desc',
      'created_asc',
      'modified_desc',
      'modified_asc',
      'age_asc',
      'age_desc',
    ];
  }

  /// 切換搜尋列顯示狀態。
  ///
  /// 關閉搜尋列時會清空目前搜尋文字，並通知外部重新整理列表。
  HomeSearchState toggleSearch() {
    isSearchOpen = !isSearchOpen;
    var refreshGallery = false;

    if (!isSearchOpen) {
      currentSearch = '';
      refreshGallery = true;
    }

    return HomeSearchState(
      isOpen: isSearchOpen,
      searchValue: currentSearch,
      refreshGallery: refreshGallery,
    );
  }

  /// 更新目前搜尋文字。
  void changeSearch(String? searchValue) {
    currentSearch = searchValue ?? '';
  }

  /// 更新目前篩選條件。
  void selectFilter(String filterValue) {
    currentFilter = filterValue;
  }

  /// 更新目前排序條件。
  void changeSort(String sortValue) {
    currentSort = sortValue;
  }

  /// 使用目前搜尋、篩選與排序狀態取得首頁列表資料。
  Future<List<Map<String, Object?>>> getGalleryData() {
    return db.getAllActressesByQuery(
      ActressQuery(
        searchKeyword: currentSearch,
        filter: _filterFromKey(currentFilter),
        sort: _sortFromKey(currentSort),
      ),
    );
  }

  ActressFilter _filterFromKey(String filterValue) {
    return switch (filterValue) {
      'censored' => ActressFilter.censored,
      'uncensored' => ActressFilter.uncensored,
      'western' => ActressFilter.western,
      'fc2' => ActressFilter.fc2,
      'domestic' => ActressFilter.domestic,
      _ => ActressFilter.all,
    };
  }

  ActressSort _sortFromKey(String sortValue) {
    return switch (sortValue) {
      'created_asc' => ActressSort.createdAsc,
      'modified_desc' => ActressSort.modifiedDesc,
      'modified_asc' => ActressSort.modifiedAsc,
      'name_asc' => ActressSort.nameAsc,
      'name_desc' => ActressSort.nameDesc,
      'age_asc' => ActressSort.ageAsc,
      'age_desc' => ActressSort.ageDesc,
      _ => ActressSort.createdDesc,
    };
  }

  /// 前往詳細頁。
  Future<void> goDetail(BuildContext context, int actressId) async {
    await Navigator.of(context).pushNamed('/detail/$actressId');
  }

  /// 前往設定頁。
  Future<void> goSettings(BuildContext context) async {
    await Navigator.of(context).pushNamed('/settings');
  }

  /// 前往新增頁。
  Future<void> goAdd(BuildContext context) async {
    await Navigator.of(context).pushNamed('/add');
  }
}
