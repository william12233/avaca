import 'dart:async';
import 'dart:io';

import 'package:avaca/core/config.dart';
import 'package:avaca/core/database.dart';
import 'package:avaca/l10n/app_localizations.dart';
import 'package:avaca/views/home_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingHomeDatabase extends AppDatabase {
  final List<({String filter, String sort})> queries = [];
  Future<Map<String, Object?>?> Function()? randomWork;
  int randomWorkQueries = 0;

  @override
  Future<List<Map<String, Object?>>> getAllActresses({
    String searchKeyword = '',
    String filterType = '全部',
    String sortBy = '新增時間 (新到舊)',
  }) async {
    queries.add((filter: filterType, sort: sortBy));
    if (searchKeyword.isNotEmpty) return [];
    return const [
      {'id': 1, 'name': '測試女優', 'img_path': null},
    ];
  }

  @override
  Future<Map<String, Object?>?> getRandomWork() async {
    randomWorkQueries++;
    return randomWork?.call();
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
    final tile = tester.widget<ExpansionTile>(ratingGroup);
    expect(tile.shape, const Border());
    expect(tile.collapsedShape, const Border());
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

  testWidgets('AVACA draws from the catalog even with an empty gallery', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 520);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final database = _RecordingHomeDatabase();
    final thumbnail = FileImage(File('assets/icon.png').absolute);
    final longTitle = List.filled(30, '作品長標題').join(' ');
    database.randomWork = () async => {
      'code': 'TEST-001',
      'title': longTitle,
      'card_image_path': thumbnail.file.path,
    };
    await tester.pumpWidget(_homeApp(database));
    await tester.pumpAndSettle();
    final appTitle = find.text('AVACA');
    await tester.runAsync(
      () => precacheImage(thumbnail, tester.element(appTitle)),
    );

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.text('有碼'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('搜尋'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '無結果');
    await tester.pumpAndSettle();
    expect(find.text('測試女優'), findsNothing);
    expect(database.queries.last.filter, '有碼');
    expect(database.randomWorkQueries, 0);

    await tester.tap(appTitle);
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(find.text('隨機作品'), findsOneWidget);
    expect(find.text('TEST-001'), findsOneWidget);
    expect(find.text(longTitle), findsOneWidget);
    final image = find.descendant(of: dialog, matching: find.byType(Image));
    expect(tester.widget<Image>(image).image, thumbnail);
    final scrollable = find.descendant(
      of: dialog,
      matching: find.byType(Scrollable),
    );
    expect(
      tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
      greaterThan(0),
    );
    expect(database.randomWorkQueries, 1);

    await tester.tap(find.text('關閉'));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);

    database.randomWork = () async => {
      'code': 'TEST-002',
      'title': '沒有縮圖的作品',
      'card_image_path': '/missing-test-thumbnail.png',
    };
    await tester.tap(appTitle);
    await tester.pumpAndSettle();
    expect(find.text('TEST-002'), findsOneWidget);
    expect(find.text('沒有縮圖的作品'), findsOneWidget);
    expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    expect(database.randomWorkQueries, 2);
    expect(tester.takeException(), isNull);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
  });

  testWidgets('random work dialog handles an empty catalog and a load error', (
    tester,
  ) async {
    final database = _RecordingHomeDatabase();
    await tester.pumpWidget(_homeApp(database));
    await tester.pumpAndSettle();

    await tester.tap(find.text('AVACA'));
    await tester.pumpAndSettle();
    expect(find.text('尚無作品'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    final pendingWork = Completer<Map<String, Object?>?>();
    database.randomWork = () => pendingWork.future;
    await tester.tap(find.text('AVACA'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pendingWork.completeError(StateError('測試錯誤'));
    await tester.pumpAndSettle();
    expect(find.textContaining('載入失敗'), findsOneWidget);
    expect(find.textContaining('測試錯誤'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
