import 'package:avaca/controllers/works_controller.dart';
import 'package:avaca/core/database.dart';
import 'package:avaca/models/work_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _WorksControllerDatabase extends AppDatabase {
  @override
  Future<Map<String, Object?>?> getActressById(int actressId) async {
    return {'id': actressId, 'name': '測試女優', 'aliases': const <String>[]};
  }

  @override
  Future<List<Map<String, Object?>>> getWorksForActress(int actressId) async {
    return const [
      {'id': 1, 'code': 'SONE409', 'title': '符合作品'},
      {'id': 2, 'code': 'ABF-367', 'title': '其他作品'},
      {'id': 3, 'code': '國產01', 'title': '中文番號作品'},
    ];
  }
}

void main() {
  test('work code search canonicalizes case and separators', () async {
    final controller = WorksController(
      db: _WorksControllerDatabase(),
      actressId: 7,
    );

    await controller.init();

    final originalWorks = controller.works;

    for (final query in ['SONE-409', 'sone-409', 'SONE409', 'sone409']) {
      controller.changeSearch(query);

      expect(controller.visibleWorks, hasLength(1));
      expect(controller.visibleWorks.single['id'], 1);
      expect(controller.works, same(originalWorks));
    }

    controller.changeSearch('missing');
    expect(controller.visibleWorks, isEmpty);

    controller.changeSearch('中文');
    expect(controller.visibleWorks, isEmpty);

    controller.changeSearch('國產');
    expect(controller.visibleWorks, hasLength(1));
    expect(controller.visibleWorks.single['id'], 3);

    controller.changeSearch('');
    expect(controller.visibleWorks, same(originalWorks));

    controller.dispose();
  });

  test('filters works by storage state before applying search', () async {
    final controller = WorksController(
      db: _StorageWorksControllerDatabase(),
      actressId: 7,
    );

    await controller.init();

    controller.changeStorageFilter(WorkStorageFilter.stored);
    expect(controller.visibleWorks.map((work) => work['id']), [1]);

    controller.changeStorageFilter(WorkStorageFilter.notStored);
    expect(controller.visibleWorks.map((work) => work['id']), [2]);

    controller.changeSearch('ABF-002');
    expect(controller.visibleWorks.map((work) => work['id']), [2]);

    controller.changeStorageFilter(WorkStorageFilter.all);
    expect(controller.visibleWorks.map((work) => work['id']), [2]);

    controller.dispose();
  });
}

class _StorageWorksControllerDatabase extends _WorksControllerDatabase {
  @override
  Future<List<Map<String, Object?>>> getWorksForActress(int actressId) async {
    return [
      {'id': 1, 'code': 'SONE-001', 'title': '已儲存作品', 'is_stored': 1},
      {'id': 2, 'code': 'ABF-002', 'title': '未儲存作品', 'is_stored': 0},
    ];
  }
}
