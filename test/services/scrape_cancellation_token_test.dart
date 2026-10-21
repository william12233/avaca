import 'package:flutter_test/flutter_test.dart';

import 'package:avaca/services/works_scrape_service.dart';

void main() {
  test('pause requests a cooperative stop without becoming cancellation', () {
    final token = WorksScrapeCancellationToken();

    token.pause();

    expect(token.isPauseRequested, isTrue);
    expect(token.isCancelRequested, isFalse);
    expect(token.shouldStop, isTrue);

    token.resume();

    expect(token.isPauseRequested, isFalse);
    expect(token.isCancelRequested, isFalse);
    expect(token.shouldStop, isFalse);
  });

  test('cancel supersedes a previous pause request', () {
    final token = WorksScrapeCancellationToken();

    token.pause();
    token.cancel();

    expect(token.isPauseRequested, isFalse);
    expect(token.isCancelRequested, isTrue);
    expect(token.shouldStop, isTrue);
  });
}
