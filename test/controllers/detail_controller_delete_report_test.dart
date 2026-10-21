import 'package:avaca/controllers/detail_controller.dart';
import 'package:avaca/core/database.dart';
import 'package:avaca/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('successful deletion shows a compact cleanup summary', (
    tester,
  ) async {
    final database = _DeleteReportDatabase();
    const actressId = 1;
    final controller = DetailController(db: database, actressId: actressId);
    Future<void>? deletion;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () {
                deletion = controller.executeDelete(context);
              },
              child: const Text('delete'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('delete'));
    await tester.pump();
    await deletion;
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('已刪除 0 個圖片檔，共釋放 0.00 MB'), findsOneWidget);
  });
}

class _DeleteReportDatabase extends AppDatabase {
  @override
  Future<ActressDeletionReport> deleteActressWithReport(int actressId) async {
    return ActressDeletionReport(
      databaseCommitted: true,
      beforeTableCounts: const {
        'actresses': 1,
        'works': 0,
        'actress_works': 0,
        'pending_file_deletions': 0,
      },
      afterTableCounts: const {
        'actresses': 0,
        'works': 0,
        'actress_works': 0,
        'pending_file_deletions': 0,
      },
      beforeManagedImageStats: const ManagedImageStats(
        fileCount: 0,
        totalBytes: 0,
      ),
      afterManagedImageStats: const ManagedImageStats(
        fileCount: 0,
        totalBytes: 0,
      ),
      fileCleanup: const ManagedFileCleanupReport(),
      maintenance: const DatabaseMaintenanceReport(
        walCheckpointAttempted: false,
        vacuumAttempted: false,
        vacuumCompleted: false,
      ),
      cacheEvictionPaths: const [],
      actressId: actressId,
    );
  }
}
