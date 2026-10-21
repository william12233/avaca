import 'package:avaca/core/config.dart';
import 'package:avaca/core/database.dart';
import 'package:avaca/core/keyboard_dismiss_navigator_observer.dart';
import 'package:avaca/l10n/app_localizations.dart';
import 'package:avaca/views/detail_view.dart';
import 'package:avaca/views/home_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FocusDatabase extends AppDatabase {
  @override
  Future<int> getWorkCountForActress(int actressId) async => 0;

  @override
  Future<List<Map<String, Object?>>> getWorksForActress(int actressId) async =>
      const [];

  @override
  Future<List<Map<String, Object?>>> getAllActresses({
    String searchKeyword = '',
    String filterType = '全部',
    String sortBy = '新增時間 (新到舊)',
  }) async {
    return const [
      {'id': 1, 'name': '焦點測試', 'img_path': null},
    ];
  }

  @override
  Future<Map<String, Object?>?> getActressById(int actressId) async {
    return {
      'id': actressId,
      'name': '焦點測試',
      'img_path': '',
      'main_type': '',
      'memo': '',
      'height': '',
      'weight': '',
      'bwh': '',
      'cup': '',
      'birth_date': null,
    };
  }
}

void main() {
  testWidgets('physical pop does not restore Home search keyboard', (
    tester,
  ) async {
    final database = _FocusDatabase();
    await tester.pumpWidget(
      _app(
        home: HomeView(db: database),
        routes: {'/add': (_) => const Scaffold(body: Text('add route'))},
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('搜尋'));
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.byTooltip('新增'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(HomeView), findsOneWidget);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('physical pop of filter sheet does not restore search keyboard', (
    tester,
  ) async {
    await tester.pumpWidget(_app(home: HomeView(db: _FocusDatabase())));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('搜尋'));
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.byTooltip('篩選與排序'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('physical pop from Works does not restore Detail edit keyboard', (
    tester,
  ) async {
    final database = _FocusDatabase();
    await tester.pumpWidget(
      _app(
        home: DetailView(db: database, actressId: 1),
        routes: {'/works/1': (_) => const Scaffold(body: Text('works route'))},
      ),
    );
    await tester.pumpAndSettle();

    await _enterDetailEditMode(tester);
    await tester.tap(find.byKey(const Key('detail-name-field')));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.byKey(const Key('detail-works-button')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(DetailView), findsOneWidget);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets(
    'physical back cancels unsaved detail edits and retains the route',
    (tester) async {
      final database = _FocusDatabase();
      await tester.pumpWidget(
        _app(home: DetailView(db: database, actressId: 1)),
      );
      await tester.pumpAndSettle();

      await _enterDetailEditMode(tester);
      await tester.enterText(
        find.byKey(const Key('detail-name-field')),
        '未儲存焦點測試',
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(DetailView), findsOneWidget);
      expect(find.byKey(const Key('detail-name-field')), findsNothing);
      expect(find.text('焦點測試'), findsOneWidget);
      expect(find.byKey(const Key('detail-overflow-menu')), findsOneWidget);
    },
  );

  testWidgets('navigator observer clears focus without page-specific helpers', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [KeyboardDismissNavigatorObserver()],
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                const TextField(key: Key('observer-focus-field')),
                ElevatedButton(
                  key: const Key('observer-push-button'),
                  onPressed: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) =>
                            const Scaffold(body: Text('observer route')),
                      ),
                    );
                  },
                  child: const Text('push'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('observer-focus-field')));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.byKey(const Key('observer-push-button')));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('observer-focus-field')), findsOneWidget);
    expect(tester.testTextInput.isVisible, isFalse);
  });
}

Widget _app({
  required Widget home,
  Map<String, WidgetBuilder> routes = const {},
}) {
  return MaterialApp(
    theme: AppTheme.fromPalette(AppPalettes.light),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh', 'TW'),
    home: home,
    routes: routes,
  );
}

Future<void> _enterDetailEditMode(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('detail-overflow-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('detail-edit-menu-item')));
  await tester.pumpAndSettle();
}
