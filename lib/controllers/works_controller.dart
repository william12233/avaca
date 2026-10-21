import 'package:flutter/foundation.dart';

import '../core/database.dart';
import '../models/work_storage.dart';

enum WorksLoadStatus { loading, loaded, notFound, error }

class WorksController extends ChangeNotifier {
  WorksController({required this.db, required this.actressId});

  final AppDatabase db;
  final int actressId;

  String actressName = '';
  List<String> actressAliases = const [];
  List<Map<String, Object?>> works = const [];
  WorksLoadStatus status = WorksLoadStatus.loading;
  Object? loadError;
  String _searchQuery = '';
  WorkStorageFilter _storageFilter = WorkStorageFilter.all;
  final Map<int, String> _canonicalCodeByWorkId = <int, String>{};
  final Set<int> _storedWorkIds = <int>{};

  String get searchQuery => _searchQuery;
  WorkStorageFilter get storageFilter => _storageFilter;

  List<Map<String, Object?>> get visibleWorks {
    final rawQuery = _searchQuery.trim();

    final filteredWorks = switch (_storageFilter) {
      WorkStorageFilter.all => works,
      WorkStorageFilter.stored =>
        works.where(_isStored).toList(growable: false),
      WorkStorageFilter.notStored =>
        works.where((work) => !_isStored(work)).toList(growable: false),
    };

    if (rawQuery.isEmpty) {
      return filteredWorks;
    }

    final query = _canonicalizeWorkCode(rawQuery);

    if (query.isEmpty) {
      return const [];
    }

    return filteredWorks
        .where((work) {
          final id = _workId(work);
          final code = id == null
              ? _canonicalizeWorkCode(work['code']?.toString() ?? '')
              : (_canonicalCodeByWorkId[id] ?? '');
          return code.contains(query);
        })
        .toList(growable: false);
  }

  void changeStorageFilter(WorkStorageFilter value) {
    if (_storageFilter == value) {
      return;
    }

    _storageFilter = value;
    notifyListeners();
  }

  void changeSearch(String value) {
    if (_searchQuery == value) {
      return;
    }

    _searchQuery = value;
    notifyListeners();
  }

  Future<void> init() async {
    try {
      final actress = await db.getActressById(actressId);

      if (actress == null) {
        status = WorksLoadStatus.notFound;
      } else {
        actressName = actress['name']?.toString() ?? '';
        final aliases = actress['aliases'];
        actressAliases = aliases is Iterable
            ? aliases.map((alias) => alias.toString()).toList(growable: false)
            : const [];
        works = await db.getWorksForActress(actressId);
        _rebuildIndexes();
        status = WorksLoadStatus.loaded;
      }
    } catch (error) {
      loadError = error;
      status = WorksLoadStatus.error;
    }

    notifyListeners();
  }

  Future<void> reloadWorks() async {
    works = await db.getWorksForActress(actressId);
    _rebuildIndexes();
    notifyListeners();
  }

  bool _isStored(Map<String, Object?> work) {
    final id = _workId(work);
    if (id != null) return _storedWorkIds.contains(id);
    return WorkStorageRecord.fromDatabase(work).isStored;
  }

  int? _workId(Map<String, Object?> work) {
    final value = work['id'];
    return value is int ? value : int.tryParse(value?.toString() ?? '');
  }

  void _rebuildIndexes() {
    _canonicalCodeByWorkId.clear();
    _storedWorkIds.clear();
    for (final work in works) {
      final id = _workId(work);
      if (id == null) continue;
      _canonicalCodeByWorkId[id] = _canonicalizeWorkCode(
        work['code']?.toString() ?? '',
      );
      if (WorkStorageRecord.fromDatabase(work).isStored) {
        _storedWorkIds.add(id);
      }
    }
  }

  static String _canonicalizeWorkCode(String value) {
    // Ignore the separators commonly used in work codes, but keep every
    // other character so a CJK query remains a real query instead of turning
    // into an empty string and showing all works.
    return value.toUpperCase().replaceAll(RegExp(r'[\s\-_./]+'), '');
  }
}
