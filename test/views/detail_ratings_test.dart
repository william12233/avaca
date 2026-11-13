import 'package:avaca/core/config.dart';
import 'package:avaca/core/database.dart';
import 'package:avaca/l10n/app_localizations.dart';
import 'package:avaca/views/detail_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RatingDatabase extends AppDatabase {
  int? face = 4;
  int? chest;
  int? body;
  int? charm;

  @override
  Future<int> getWorkCountForActress(int actressId) async => 0;

  @override
  Future<Map<String, Object?>?> getActressById(int actressId) async {
    return {
      'id': actressId,
      'name': '評分測試',
      'img_path': '',
      'main_type': '',
      'memo': '',
      'height': '',
      'weight': '',
      'bwh': '',
      'cup': '',
      'birth_date': null,
      'rating_face': face,
      'rating_chest': chest,
      'rating_body': body,
      'rating_charm': charm,
    };
  }

  @override
  Future<bool> updateActressRatings({
    required int actressId,
    required int? face,
    required int? chest,
    required int? body,
    required int? charm,
  }) async {
    this.face = face;
    this.chest = chest;
    this.body = body;
    this.charm = charm;
    return true;
  }
}

void main() {
  testWidgets(
    'rating sliders are discrete and keep clear/save/cancel behavior',
    (tester) async {
      final database = _RatingDatabase();
      await tester.pumpWidget(_detailApp(database));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('detail-rating-button')));
      await tester.pumpAndSettle();

      final faceRow = find.byKey(const Key('detail-rating-face'));
      final faceSlider = find.descendant(
        of: faceRow,
        matching: find.byType(Slider),
      );
      expect(faceSlider, findsOneWidget);
      final slider = tester.widget<Slider>(faceSlider);
      expect(slider.min, 1);
      expect(slider.max, 10);
      expect(slider.divisions, 9);
      expect(find.text('4'), findsOneWidget);

      await _tapSliderEndpoint(tester, faceSlider, maximum: true);
      expect(
        find.descendant(of: faceRow, matching: find.text('10')),
        findsOneWidget,
      );
      expect(database.face, 4);

      await tester.tap(
        find.descendant(of: faceRow, matching: find.byTooltip('清除')),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: faceRow, matching: find.text('未評')),
        findsOneWidget,
      );
      expect(database.face, 4);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(database.face, 4);

      await tester.tap(find.byKey(const Key('detail-rating-button')));
      await tester.pumpAndSettle();
      final reopenedFaceSlider = find.descendant(
        of: find.byKey(const Key('detail-rating-face')),
        matching: find.byType(Slider),
      );
      await _tapSliderEndpoint(tester, reopenedFaceSlider, maximum: false);
      expect(
        find.descendant(
          of: find.byKey(const Key('detail-rating-face')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('儲存評價'));
      await tester.pumpAndSettle();
      expect(database.face, 1);
    },
  );
}

Future<void> _tapSliderEndpoint(
  WidgetTester tester,
  Finder slider, {
  required bool maximum,
}) async {
  final rect = tester.getRect(slider);
  await tester.tapAt(
    Offset(maximum ? rect.right - 12 : rect.left + 12, rect.center.dy),
  );
  await tester.pumpAndSettle();
}

Widget _detailApp(AppDatabase database) {
  return MaterialApp(
    theme: AppTheme.fromPalette(AppPalettes.light),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh', 'TW'),
    home: DetailView(db: database, actressId: 1),
  );
}
