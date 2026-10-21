import 'package:avaca/core/database.dart';
import 'package:avaca/l10n/app_localizations.dart';
import 'package:avaca/models/work_storage.dart';
import 'package:avaca/views/work_detail_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'shows other performers, resolves local pages, and excludes current actress',
    (tester) async {
      final requestedRoutes = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          onGenerateRoute: (settings) {
            if (settings.name != null) {
              requestedRoutes.add(settings.name!);
            }
            return MaterialPageRoute<void>(
              builder: (_) => const SizedBox.shrink(),
            );
          },
          home: WorkDetailView(
            db: _WorkDetailDatabase(),
            workId: 7,
            currentActressId: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('related-actresses-section')),
        findsOneWidget,
      );
      expect(find.text('當前女優'), findsNothing);
      expect(find.text('本地女優'), findsOneWidget);
      expect(find.text('別名女優'), findsOneWidget);
      expect(find.text('未建立頁面'), findsOneWidget);
      expect(find.byKey(const ValueKey('related-actress-2')), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('related-actress-未建立頁面')),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const ValueKey('related-actress-2')));
      await tester.pumpAndSettle();
      expect(requestedRoutes, ['/detail/2']);
    },
  );

  testWidgets('edits and shows the work storage record', (tester) async {
    final database = _WorkDetailDatabase();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: WorkDetailView(db: database, workId: 7),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('work-storage-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('work-storage-dialog')), findsOneWidget);

    await tester.tap(find.byKey(const Key('work-storage-saved-switch')));
    await tester.tap(find.byKey(const Key('work-storage-quality-2K')));
    await tester.tap(find.byKey(const Key('work-storage-frame-rate-30')));
    await tester.tap(find.byKey(const Key('work-storage-save')));
    await tester.pumpAndSettle();

    expect(
      database.savedStorage,
      const WorkStorageRecord(isStored: true, quality: '2K', frameRate: 30),
    );
    expect(find.text('2K/30'), findsOneWidget);
  });
}

class _WorkDetailDatabase extends AppDatabase {
  WorkStorageRecord? savedStorage;

  @override
  Future<void> updateWorkStorage({
    required int workId,
    required WorkStorageRecord record,
  }) async {
    savedStorage = record;
  }

  @override
  Future<Map<String, Object?>?> getWorkById(
    int workId, {
    int? currentActressId,
  }) async {
    return {
      'id': workId,
      'code': 'MULTI-007',
      'title': '多人作品',
      'release_date': '2026-01-01',
      'duration_minutes': 120,
      'studio': '工作室',
      'publisher': '發行商',
      'series': '系列',
      'detail_image_path': '',
      'is_stored': 0,
      'storage_quality': null,
      'storage_frame_rate': null,
      'related_performers': [
        {'name': '當前女優', 'actress_id': 1, 'source': 'javbus'},
        {'name': '本地女優', 'actress_id': 2, 'source': 'javbus'},
        {'name': '別名女優', 'actress_id': 3, 'source': 'javbus'},
        {'name': '未建立頁面', 'actress_id': null, 'source': 'javbus'},
      ],
    };
  }
}
