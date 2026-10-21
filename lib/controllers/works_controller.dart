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

  String get searchQuery => _searchQuery;
  WorkStorageFilter get storageFilter => _storageFilter;

  List<Map<String, Object?>> get visibleWorks {
    final rawQuery = _searchQuery.trim();

    final filteredWorks = switch (_storageFilter) {
      WorkStorageFilter.all => works,
      WorkStorageFilter.stored =>
        works
            .where((work) => WorkStorageRecord.fromDatabase(work).isStored)
            .toList(growable: false),
      WorkStorageFilter.notStored =>
        works
            .where((work) => !WorkStorageRecord.fromDatabase(work).isStored)
            .toList(growable: false),
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
          final code = work['code']?.toString() ?? '';
          return _canonicalizeWorkCode(code).contains(query);
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
    notifyListeners();
  }

  static String _canonicalizeWorkCode(String value) {
    // Ignore the separators commonly used in work codes, but keep every
    // other character so a CJK query remains a real query instead of turning
    // into an empty string and showing all works.
    return value.toUpperCase().replaceAll(RegExp(r'[\s\-_./]+'), '');
  }
}
