import 'package:avaca/core/config.dart';
import 'package:avaca/core/database.dart';
import 'package:avaca/l10n/app_localizations.dart';
import 'package:avaca/views/home_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingHomeDatabase extends AppDatabase {
  final List<({String filter, String sort})> queries = [];

  @override
  Future<List<Map<String, Object?>>> getAllActresses({
    String searchKeyword = '',
    String filterType = '全部',
    String sortBy = '新增時間 (新到舊)',
  }) async {
    queries.add((filter: filterType, sort: sortBy));
    return const [
      {'id': 1, 'name': '測試女優', 'img_path': null},
    ];
  }
}

void main() {
  testWidgets('filter and sort choices apply immediately and stay open', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final database = _RecordingHomeDatabase();
    await tester.pumpWidget(_homeApp(database));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();

    expect(find.byType(ChoiceChip), findsNWidgets(12));
    expect(
      tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .every((chip) => chip.showCheckmark == false),
      isTrue,
    );
    expect(find.text('套用設定'), findsNothing);

    final beforeFilter = database.queries.length;
    await tester.tap(find.text('有碼'));
    await tester.pumpAndSettle();
    expect(database.queries.length, beforeFilter + 1);
    expect(database.queries.last.filter, '有碼');
    expect(find.byType(BottomSheet), findsOneWidget);

    final beforeModifiedSort = database.queries.length;
    await tester.tap(find.text('修改時間（舊到新）'));
    await tester.pumpAndSettle();
    expect(database.queries.length, beforeModifiedSort + 1);
    expect(database.queries.last.sort, '修改時間 (舊到新)');
    expect(find.byType(BottomSheet), findsOneWidget);

    final beforeAgeSort = database.queries.length;
    await tester.tap(find.text('年齡（低到高）'));
    await tester.pumpAndSettle();
    expect(database.queries.length, beforeAgeSort + 1);
    expect(database.queries.last.sort, '年齡 (低到高)');
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('compact Chinese filter choices fit one portrait row', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_homeApp(_RecordingHomeDatabase()));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();

    final chips = find.byType(ChoiceChip);
    final filterTops = List.generate(
      6,
      (index) => tester.getTopLeft(chips.at(index)).dy,
    );
    expect(filterTops.toSet(), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('rating sorts live in a collapsed group with selected summary', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final database = _RecordingHomeDatabase();
    await tester.pumpWidget(_homeApp(database));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();

    final ratingGroup = find.byKey(
      const ValueKey('home-rating-sort-expansion'),
    );
    expect(ratingGroup, findsOneWidget);
    expect(find.byType(ChoiceChip), findsNWidgets(12));
    expect(find.text('臉部評價（高到低）'), findsNothing);

    await tester.tap(ratingGroup);
    await tester.pumpAndSettle();
    expect(find.byType(ChoiceChip), findsNWidgets(17));
    await tester.tap(find.text('臉部評價（高到低）'));
    await tester.pumpAndSettle();

    expect(database.queries.last.sort, 'rating_face_desc');
    await tester.tap(ratingGroup);
    await tester.pumpAndSettle();
    expect(find.text('臉部評價（高到低）'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNWidgets(12));
  });
}

Widget _homeApp(AppDatabase database) {
  return MaterialApp(
    theme: AppTheme.fromPalette(AppPalettes.light),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh', 'TW'),
    home: HomeView(db: database),
  );
}
