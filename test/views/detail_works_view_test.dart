import 'dart:async';

import 'package:avaca/core/config.dart';
import 'package:avaca/core/database.dart';
import 'package:avaca/l10n/app_localizations.dart';
import 'package:avaca/main.dart';
import 'package:avaca/views/detail_view.dart';
import 'package:avaca/views/works_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAppDatabase extends AppDatabase {
  final String persistedName = '已儲存名稱';

  @override
  Future<int> getWorkCountForActress(int actressId) async => 0;

  @override
  Future<List<Map<String, Object?>>> getWorksForActress(int actressId) async =>
      const [];

  @override
  Future<Map<String, Object?>?> getActressById(int actressId) async {
    return {
      'id': actressId,
      'name': persistedName,
      'img_path': '',
      'main_type': '有碼,無碼',
      'memo': '',
      'height': '',
      'weight': '',
      'bwh': '',
      'cup': '',
    };
  }

  @override
  Future<List<Map<String, Object?>>> getAllActresses({
    String searchKeyword = '',
    String filterType = '全部',
    String sortBy = '新增時間 (新到舊)',
  }) async {
    return const [];
  }

  @override
  Future<String?> getSetting(String key) async => null;
}

class _PendingAppDatabase extends _FakeAppDatabase {
  final Completer<Map<String, Object?>?> result =
      Completer<Map<String, Object?>?>();

  @override
  Future<Map<String, Object?>?> getActressById(int actressId) => result.future;
}

class _NotFoundAppDatabase extends _FakeAppDatabase {
  @override
  Future<Map<String, Object?>?> getActressById(int actressId) async => null;
}

class _FailingAppDatabase extends _FakeAppDatabase {
  @override
  Future<Map<String, Object?>?> getActressById(int actressId) async {
    throw StateError('database unavailable');
  }
}

void main() {
  group('DetailView responsive profile layout', () {
    testWidgets('places the image left and keeps both actions as full rows', (
      tester,
    ) async {
      await _pumpDetail(tester, size: const Size(390, 844));

      final imageRect = tester.getRect(
        find.byKey(const Key('detail-profile-image')),
      );
      final worksRect = tester.getRect(
        find.byKey(const Key('detail-works-button')),
      );
      final countRect = tester.getRect(
        find.byKey(const Key('detail-works-count')),
      );
      final attributesRect = tester.getRect(
        find.byKey(const Key('detail-attributes')),
      );

      expect(imageRect.left, closeTo(16, 0.01));
      expect(worksRect.left, greaterThan(imageRect.right));
      expect(countRect.left, greaterThan(worksRect.left));
      expect(countRect.right, lessThanOrEqualTo(worksRect.right));
      expect(worksRect.top, closeTo(imageRect.top, 0.01));
      expect(attributesRect.top, greaterThan(worksRect.bottom));
      expect(worksRect.width, greaterThan(120));
      expect(tester.takeException(), isNull);
    });

    testWidgets('uses the localized detailed data section title', (
      tester,
    ) async {
      await _pumpDetail(tester, size: const Size(390, 844));

      expect(find.text('詳細資料'), findsOneWidget);
      expect(find.text('身體資料'), findsNothing);
    });

    testWidgets('private notes card opens the editor when tapped', (
      tester,
    ) async {
      await _pumpDetail(tester, size: const Size(390, 844));

      final notesCard = find.byKey(const Key('detail-notes-card'));
      expect(notesCard, findsOneWidget);
      expect(
        find.text(AppLocalizations.of(tester.element(notesCard)).noNotes),
        findsOneWidget,
      );

      await tester.tap(notesCard);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('detail-notes-field')), findsOneWidget);
      expect(find.byKey(const Key('detail-save-button')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'shows localized edit and destructive delete actions in overflow',
      (tester) async {
        await _pumpDetail(tester, size: const Size(390, 844));

        expect(find.byKey(const Key('detail-overflow-menu')), findsOneWidget);
        expect(find.byIcon(Icons.edit), findsNothing);
        expect(find.byIcon(Icons.delete_forever), findsNothing);

        await tester.tap(find.byKey(const Key('detail-overflow-menu')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('detail-edit-menu-item')), findsOneWidget);
        expect(
          find.byKey(const Key('detail-delete-menu-item')),
          findsOneWidget,
        );
        expect(find.text('編輯'), findsOneWidget);
        expect(find.text('刪除'), findsOneWidget);

        final deleteLabel = tester.widget<Text>(
          find.byKey(const Key('detail-delete-menu-label')),
        );
        expect(
          deleteLabel.style?.color,
          Theme.of(
            tester.element(find.byKey(const Key('detail-delete-menu-label'))),
          ).colorScheme.error,
        );
      },
    );

    testWidgets(
      'selecting overflow delete opens the existing confirmation dialog',
      (tester) async {
        await _pumpDetail(tester, size: const Size(390, 844));

        await tester.tap(find.byKey(const Key('detail-overflow-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('detail-delete-menu-item')));
        await tester.pumpAndSettle();

        expect(find.text('確認刪除？'), findsOneWidget);
        expect(find.text('刪除後將無法復原，連同照片檔案也會被清除。'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets('edit mode app bar exposes save without overflow or delete', (
      tester,
    ) async {
      await _pumpDetail(tester, size: const Size(390, 844));

      await _enterDetailEditMode(tester);

      expect(find.byKey(const Key('detail-save-button')), findsOneWidget);
      expect(find.byKey(const Key('detail-overflow-menu')), findsNothing);
      expect(find.byIcon(Icons.delete_forever), findsNothing);
    });

    testWidgets(
      'mirrors the profile layout in edit mode with compact title and chips',
      (tester) async {
        await _pumpDetail(tester, size: const Size(390, 844));

        await _enterDetailEditMode(tester);

        final imageRect = tester.getRect(
          find.byKey(const Key('detail-profile-image')),
        );
        final worksRect = tester.getRect(
          find.byKey(const Key('detail-works-button')),
        );
        final attributesRect = tester.getRect(
          find.byKey(const Key('detail-attributes')),
        );
        final nameFieldFinder = find.byKey(const Key('detail-name-field'));
        final nameField = tester.widget<TextField>(nameFieldFinder);
        final nameFieldRect = tester.getRect(nameFieldFinder);
        final firstChip = find.byType(FilterChip).first;
        final firstChipRect = tester.getRect(firstChip);
        final chip = tester.widget<FilterChip>(firstChip);

        expect(worksRect.left, greaterThan(imageRect.right));
        expect(worksRect.left - imageRect.right, closeTo(12, 0.01));
        expect(attributesRect.top, greaterThan(worksRect.bottom));
        expect(nameField.style?.fontSize, 18);
        expect(nameFieldRect.height, lessThanOrEqualTo(40));
        expect(firstChipRect.height, lessThanOrEqualTo(32));
        expect((chip.label as Text).style?.fontSize, 14);
        final colorScheme = Theme.of(tester.element(firstChip)).colorScheme;
        final chips = tester.widgetList<FilterChip>(find.byType(FilterChip));
        final selectedChip = chips.firstWhere((item) => item.selected);
        final unselectedChip = chips.firstWhere((item) => !item.selected);
        for (var index = 1; index < chips.length; index++) {
          expect(
            tester.getRect(find.byType(FilterChip).at(index)).top,
            closeTo(firstChipRect.top, 0.01),
          );
        }
        expect(selectedChip.showCheckmark, isFalse);
        expect(
          selectedChip.selectedColor,
          colorScheme.primary.withValues(alpha: 0.28),
        );
        expect(
          (selectedChip.label as Text).style?.color,
          colorScheme.onSurface,
        );
        expect(
          (unselectedChip.label as Text).style?.color,
          colorScheme.onSurfaceVariant,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('matches detail edit controls to their containing card', (
      tester,
    ) async {
      await _pumpDetail(tester, size: const Size(390, 844));
      await _enterDetailEditMode(tester);

      final worksButton = find.byKey(const Key('detail-works-button'));
      final birthDateButton = find.byKey(const Key('detail-birth-date-button'));
      final worksRadius = _outlinedButtonRadius(tester, worksButton);
      final birthDateRadius = _outlinedButtonRadius(tester, birthDateButton);
      expect(worksRadius, BorderRadius.circular(12));
      expect(birthDateRadius, BorderRadius.circular(12));

      for (final key in const [
        Key('detail-height-field'),
        Key('detail-cup-field'),
        Key('detail-measurements-field'),
      ]) {
        final fieldFinder = find.byKey(key);
        expect(fieldFinder, findsOneWidget);
        final decoration = tester.widget<TextField>(fieldFinder).decoration!;
        expect(_inputBorderRadius(decoration.border), birthDateRadius);
        expect(_inputBorderRadius(decoration.enabledBorder), birthDateRadius);
        expect(_inputBorderRadius(decoration.focusedBorder), birthDateRadius);
      }
    });

    testWidgets(
      'edit profile has no outer frame and compact right-column photo actions',
      (tester) async {
        await _pumpDetail(tester, size: const Size(390, 844));
        await _enterDetailEditMode(tester);

        final panel = find.byKey(const Key('detail-profile-panel'));
        final image = find.byKey(const Key('detail-profile-image'));
        final works = find.byKey(const Key('detail-works-button'));
        final count = find.byKey(const Key('detail-works-count'));
        final actions = find.byKey(const Key('detail-photo-actions'));
        final changePhoto = find.byKey(const Key('detail-change-photo-button'));
        final deletePhoto = find.byKey(const Key('detail-delete-photo-button'));
        expect(panel, findsOneWidget);
        expect(actions, findsOneWidget);
        expect(changePhoto, findsOneWidget);
        expect(deletePhoto, findsOneWidget);

        final panelRect = tester.getRect(panel);
        final imageRect = tester.getRect(image);
        final worksRect = tester.getRect(works);
        final countRect = tester.getRect(count);
        final actionsRect = tester.getRect(actions);
        final changeRect = tester.getRect(changePhoto);
        final deleteRect = tester.getRect(deletePhoto);

        expect(imageRect.left - panelRect.left, closeTo(0, 0.01));
        expect(imageRect.top - panelRect.top, closeTo(0, 0.01));
        expect(worksRect.top - panelRect.top, closeTo(0, 0.01));
        expect(countRect.left, greaterThan(worksRect.left));
        expect(countRect.right, lessThanOrEqualTo(worksRect.right));
        expect(imageRect.top, closeTo(worksRect.top, 0.01));
        expect(actionsRect.top, greaterThan(worksRect.bottom));
        expect(actionsRect.left, greaterThanOrEqualTo(worksRect.left));
        expect(actionsRect.right, lessThanOrEqualTo(panelRect.right));
        expect(changeRect.top, closeTo(deleteRect.top, 0.01));
        expect(changeRect.height, closeTo(deleteRect.height, 0.01));
        expect(changeRect.height, lessThanOrEqualTo(32));
        expect(changeRect.right, lessThanOrEqualTo(deleteRect.left));
        expect(
          _outlinedButtonRadius(tester, changePhoto),
          BorderRadius.circular(12),
        );
        expect(
          _outlinedButtonRadius(tester, deletePhoto),
          BorderRadius.circular(12),
        );
        final labelStyle = Theme.of(
          tester.element(changePhoto),
        ).textTheme.labelMedium;
        expect(labelStyle?.fontFamily, AppTheme.fontFamily);
        final changeTextStyle = tester
            .widget<OutlinedButton>(changePhoto)
            .style
            ?.textStyle
            ?.resolve(<WidgetState>{});
        final deleteTextStyle = tester
            .widget<OutlinedButton>(deletePhoto)
            .style
            ?.textStyle
            ?.resolve(<WidgetState>{});
        expect(changeTextStyle?.fontSize, 12);
        expect(deleteTextStyle?.fontSize, 12);
        expect(changeTextStyle?.fontFamily, labelStyle?.fontFamily);
        expect(deleteTextStyle?.fontFamily, labelStyle?.fontFamily);
        expect(find.text('更換照片'), findsOneWidget);
        expect(find.text('刪除照片'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'keeps edit body rows compact with labels left and controls right',
      (tester) async {
        await _pumpDetail(tester, size: const Size(390, 844));
        await _enterDetailEditMode(tester);

        final birthDate = find.byKey(const Key('detail-birth-date-button'));
        final height = find.byKey(const Key('detail-height-field'));
        final cup = find.byKey(const Key('detail-cup-field'));
        final measurements = find.byKey(const Key('detail-measurements-field'));
        final birthRect = tester.getRect(birthDate);
        final heightRect = tester.getRect(height);
        final cupRect = tester.getRect(cup);
        final measurementsRect = tester.getRect(measurements);

        for (final rect in [birthRect, heightRect, cupRect, measurementsRect]) {
          expect(rect.height, closeTo(40, 0.01));
        }
        expect(heightRect.top, greaterThan(birthRect.bottom));
        expect(cupRect.top, greaterThan(heightRect.bottom));
        expect(measurementsRect.top, greaterThan(cupRect.bottom));
        expect(heightRect.top - birthRect.bottom, closeTo(8, 0.01));
        expect(cupRect.top - heightRect.bottom, closeTo(8, 0.01));
        expect(measurementsRect.top - cupRect.bottom, closeTo(8, 0.01));
        expect(heightRect.left, closeTo(birthRect.left, 0.01));
        expect(cupRect.left, closeTo(birthRect.left, 0.01));
        expect(measurementsRect.left, closeTo(birthRect.left, 0.01));
        expect(heightRect.right, closeTo(birthRect.right, 0.01));
        expect(cupRect.right, closeTo(birthRect.right, 0.01));
        expect(measurementsRect.right, closeTo(birthRect.right, 0.01));

        final colorScheme = Theme.of(tester.element(height)).colorScheme;
        final l10n = AppLocalizations.of(tester.element(height));
        for (final entry in {
          l10n.birthDate: birthRect,
          l10n.heightCm: heightRect,
          l10n.cup: cupRect,
          l10n.measurements: measurementsRect,
        }.entries) {
          final labelRect = tester.getRect(find.text(entry.key));
          expect(labelRect.center.dy, closeTo(entry.value.center.dy, 0.01));
        }

        final birthButton = tester.widget<OutlinedButton>(birthDate);
        final birthText = (birthButton.child! as Align).child! as Text;
        expect(birthText.style?.fontSize, 14);
        expect(birthText.style?.color, colorScheme.onSurfaceVariant);

        final heightField = tester.widget<TextField>(height);
        expect(heightField.decoration?.labelText, isNull);
        expect(heightField.decoration?.isDense, isFalse);
        expect(heightField.style?.fontSize, 14);
        expect(heightField.style?.color, colorScheme.onSurfaceVariant);
        expect(heightField.textAlign, TextAlign.left);
        expect(heightField.textAlignVertical, TextAlignVertical.center);
        expect(
          heightField.decoration?.constraints,
          BoxConstraints.tightFor(height: 40),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('does not overflow at narrow or desktop widths', (
      tester,
    ) async {
      for (final size in const [Size(320, 700), Size(1280, 720)]) {
        await _pumpDetail(tester, size: size);
        expect(find.text('作品'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await _enterDetailEditMode(tester);
        expect(find.text('作品'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
      'keeps the compact Works button and count in the desktop right column',
      (tester) async {
        await _pumpDetail(tester, size: const Size(1280, 720));

        final imageRect = tester.getRect(
          find.byKey(const Key('detail-profile-image')),
        );
        final worksRect = tester.getRect(
          find.byKey(const Key('detail-works-button')),
        );
        final countRect = tester.getRect(
          find.byKey(const Key('detail-works-count')),
        );

        expect(worksRect.left, greaterThan(imageRect.right));
        expect(worksRect.width, greaterThan(100));
        expect(countRect.left, greaterThan(worksRect.left));
        expect(countRect.right, lessThanOrEqualTo(worksRect.right));
      },
    );

    testWidgets(
      'supports 125 percent text scaling in narrow view and edit layouts',
      (tester) async {
        await _pumpDetail(
          tester,
          size: const Size(320, 700),
          textScaler: TextScaler.linear(1.25),
        );

        expect(find.byKey(const Key('detail-profile-image')), findsOneWidget);
        expect(find.byKey(const Key('detail-works-button')), findsOneWidget);
        expect(tester.takeException(), isNull);

        await _enterDetailEditMode(tester);

        expect(find.byKey(const Key('detail-name-field')), findsOneWidget);
        expect(find.byType(FilterChip), findsWidgets);
        expect(find.byKey(const Key('detail-works-button')), findsOneWidget);
        final panel = find.byKey(const Key('detail-profile-panel'));
        final actions = find.byKey(const Key('detail-photo-actions'));
        final changePhoto = find.byKey(const Key('detail-change-photo-button'));
        final deletePhoto = find.byKey(const Key('detail-delete-photo-button'));
        expect(panel, findsOneWidget);
        expect(actions, findsOneWidget);
        expect(changePhoto, findsOneWidget);
        expect(deletePhoto, findsOneWidget);
        final actionsRect = tester.getRect(actions);
        final changeRect = tester.getRect(changePhoto);
        final deleteRect = tester.getRect(deletePhoto);
        expect(changeRect.top, closeTo(deleteRect.top, 0.01));
        expect(changeRect.height, closeTo(deleteRect.height, 0.01));
        expect(changeRect.left, greaterThanOrEqualTo(actionsRect.left));
        expect(deleteRect.right, lessThanOrEqualTo(actionsRect.right));
        expect(find.text('更換照片'), findsOneWidget);
        expect(find.text('刪除照片'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  testWidgets(
    'app-bar back cancels unsaved detail edits and retains the route',
    (tester) async {
      SharedPreferences.setMockInitialValues({'app_locale': 'zh_TW'});
      final db = _FakeAppDatabase();

      await tester.pumpWidget(AvacaApp(db: db));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(Navigator));
      Navigator.of(context).pushNamed('/detail/7');
      await tester.pumpAndSettle();

      await _enterDetailEditMode(tester);
      await tester.enterText(
        find.byKey(const Key('detail-name-field')),
        '尚未儲存名稱',
      );

      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();

      expect(find.byType(DetailView), findsOneWidget);
      expect(find.byKey(const Key('detail-name-field')), findsNothing);
      expect(find.text('已儲存名稱'), findsOneWidget);
      expect(find.byKey(const Key('detail-overflow-menu')), findsOneWidget);
    },
  );

  testWidgets('app-bar back leaves detail normally outside edit mode', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'app_locale': 'zh_TW'});
    final db = _FakeAppDatabase();

    await tester.pumpWidget(AvacaApp(db: db));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Navigator));
    Navigator.of(context).pushNamed('/detail/7');
    await tester.pumpAndSettle();

    expect(find.byType(DetailView), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    expect(find.byType(DetailView), findsNothing);
  });

  group('Works page navigation', () {
    testWidgets('keeps an accessible AppBar and title visible while loading', (
      tester,
    ) async {
      final db = _PendingAppDatabase();

      await _pumpWorks(tester, db: db);

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('作品'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.byTooltip('返回'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('distinguishes a load error from a missing actress', (
      tester,
    ) async {
      await _pumpWorks(tester, db: _FailingAppDatabase());
      await tester.pumpAndSettle();

      expect(find.text('載入失敗'), findsOneWidget);
      expect(find.textContaining('database unavailable'), findsNothing);
      expect(find.text('找不到資料'), findsNothing);

      await _pumpWorks(tester, db: _NotFoundAppDatabase());
      await tester.pumpAndSettle();

      expect(find.text('找不到資料'), findsOneWidget);
      expect(find.text('載入失敗'), findsNothing);
    });

    testWidgets(
      'opens Works from view mode and returns to the unchanged detail view',
      (tester) async {
        SharedPreferences.setMockInitialValues({'app_locale': 'zh_TW'});
        final db = _FakeAppDatabase();

        await tester.pumpWidget(AvacaApp(db: db));
        await tester.pumpAndSettle();

        final context = tester.element(find.byType(Navigator));
        Navigator.of(context).pushNamed('/detail/7');
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('detail-name-field')), findsNothing);
        await tester.tap(find.byKey(const Key('detail-works-button')));
        await tester.pumpAndSettle();

        expect(find.text('已儲存名稱演出的作品'), findsOneWidget);

        await tester.tap(find.byTooltip('返回'));
        await tester.pumpAndSettle();

        expect(find.byType(DetailView), findsOneWidget);
        expect(find.text('已儲存名稱'), findsOneWidget);
        expect(find.byKey(const Key('detail-name-field')), findsNothing);
        expect(find.byKey(const Key('detail-works-button')), findsOneWidget);
      },
    );

    testWidgets(
      'loads the persisted name and preserves an unsaved edit on back',
      (tester) async {
        SharedPreferences.setMockInitialValues({'app_locale': 'zh_TW'});
        final db = _FakeAppDatabase();

        await tester.pumpWidget(AvacaApp(db: db));
        await tester.pumpAndSettle();

        final context = tester.element(find.byType(Navigator));
        Navigator.of(context).pushNamed('/detail/7');
        await tester.pumpAndSettle();

        await _enterDetailEditMode(tester);
        await tester.enterText(
          find.byKey(const Key('detail-name-field')),
          '尚未儲存名稱',
        );

        await tester.tap(find.byKey(const Key('detail-works-button')));
        await tester.pumpAndSettle();

        expect(find.byType(WorksView), findsOneWidget);
        expect(find.text('已儲存名稱演出的作品'), findsOneWidget);
        expect(find.byIcon(Icons.arrow_back), findsOneWidget);
        expect(find.text('尚未儲存名稱演出的作品'), findsNothing);

        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();

        final nameField = tester.widget<TextField>(
          find.byKey(const Key('detail-name-field')),
        );
        expect(nameField.controller?.text, '尚未儲存名稱');
      },
    );
  });
}

Future<void> _pumpWorks(WidgetTester tester, {required AppDatabase db}) async {
  await tester.pumpWidget(const SizedBox.shrink());

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: WorksView(db: db, actressId: 7),
    ),
  );
  await tester.pump();
}

Future<void> _enterDetailEditMode(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('detail-overflow-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('detail-edit-menu-item')));
  await tester.pumpAndSettle();
}

BorderRadiusGeometry _outlinedButtonRadius(WidgetTester tester, Finder finder) {
  final button = tester.widget<OutlinedButton>(finder);
  final shape = button.style?.shape?.resolve(<WidgetState>{});
  expect(shape, isNotNull);
  expect(shape, isA<RoundedRectangleBorder>());
  return (shape! as RoundedRectangleBorder).borderRadius;
}

BorderRadiusGeometry _inputBorderRadius(InputBorder? border) {
  expect(border, isA<OutlineInputBorder>());
  return (border! as OutlineInputBorder).borderRadius;
}

Future<void> _pumpDetail(
  WidgetTester tester, {
  required Size size,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());

  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.fromPalette(AppPalettes.light),
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: textScaler),
        child: DetailView(db: _FakeAppDatabase(), actressId: 7),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
