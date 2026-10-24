import 'package:avaca/core/shapes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps the shared UI shape contract stable', () {
    expect(AppShapeTokens.defaultCardRadius, 12);
    expect(AppShapeTokens.inputRadius, AppShapeTokens.defaultCardRadius);
    expect(AppShapeTokens.dialogRadius, 28);
  });
}
