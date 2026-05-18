import 'package:flutter/material.dart';
import '../core/database.dart';

/// 管理首頁的搜尋、篩選、排序與頁面導向狀態。
class HomeController {
  HomeController({
    required this.db,
  });

  final AppDatabase db;

  String currentSearch = '';
  String currentFilter = 'all';
  String currentSort = 'created_desc';
  bool isSearchOpen = false;

  /// 取得首頁可用的篩選選項。
  List<String> getFilterOptions() {
    return [
      'all',
      'censored',
      'uncensored',
      'western',
      'fc2',
      'domestic',
    ];
  }

  /// 切換搜尋列顯示狀態。
  ///
  /// 關閉搜尋列時會清空目前搜尋文字，並通知外部重新整理列表。
  Map<String, Object> toggleSearch() {
    isSearchOpen = !isSearchOpen;
    var refreshGallery = false;

    if (!isSearchOpen) {
      currentSearch = '';
      refreshGallery = true;
    }

    return {
      'is_open': isSearchOpen,
      'search_value': currentSearch,
      'refresh_gallery': refreshGallery,
    };
  }

  /// 更新目前搜尋文字。
  void changeSearch(String? searchValue) {
    currentSearch = searchValue ?? '';
  }

  /// 更新目前篩選條件。
  Map<String, Object> selectFilter(String filterValue) {
    currentFilter = filterValue;

    return {
      'current_filter': currentFilter,
    };
  }

  /// 更新目前排序條件。
  void changeSort(String sortValue) {
    currentSort = sortValue;
  }

  /// 通知外部開啟篩選面板。
  Map<String, bool> openFilterSheet() {
    return {
      'open': true,
    };
  }

  /// 通知外部關閉篩選面板。
  Map<String, bool> applyFilterSheet() {
    return {
      'open': false,
    };
  }

  /// 使用目前搜尋、篩選與排序狀態取得首頁列表資料。
  Future<List<Map<String, Object?>>> getGalleryData() {
    return db.getAllActresses(
      searchKeyword: currentSearch,
      filterType: _filterValueForDatabase(currentFilter),
      sortBy: _sortValueForDatabase(currentSort),
    );
  }

  String _filterValueForDatabase(String filterValue) {
    return switch (filterValue) {
      'all' => '全部',
      'censored' => '有碼',
      'uncensored' => '無碼',
      'western' => '歐美',
      'fc2' => 'FC2',
      'domestic' => '國產',
      _ => filterValue,
    };
  }

  String _sortValueForDatabase(String sortValue) {
    return switch (sortValue) {
      'created_desc' => '新增時間 (新到舊)',
      'created_asc' => '新增時間 (舊到新)',
      'modified_desc' => '修改時間 (新到舊)',
      'modified_asc' => '修改時間 (舊到新)',
      'name_asc' => '名稱 (A-Z)',
      'name_desc' => '名稱 (Z-A)',
      _ => sortValue,
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