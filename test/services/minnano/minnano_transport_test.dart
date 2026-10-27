import 'dart:convert';

import 'package:avaca/services/minnano/minnano_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('sends browser headers and carries cookies across requests', () async {
    final client = _QueueClient([
      const _ResponseSpec(
        statusCode: 200,
        body: '<html>home</html>',
        headers: {'set-cookie': 'PHPSESSID=test-session; path=/'},
      ),
      const _ResponseSpec(statusCode: 200, body: '<html>work</html>'),
    ]);
    final transport = HttpMinnanoTransport(
      client: client,
      requestDelay: Duration.zero,
    );
    addTearDown(transport.close);

    await transport.get(Uri.parse('https://www.minnano-av.com/'));
    await transport.get(Uri.parse('https://www.minnano-av.com/av1.html'));

    expect(client.requests, hasLength(2));
    expect(
      client.requests.first.headers['user-agent'],
      startsWith('Mozilla/5.0'),
    );
    expect(client.requests.first.headers['accept'], contains('text/html'));
    expect(
      client.requests[1].headers['cookie'],
      contains('PHPSESSID=test-session'),
    );
  });

  test('classifies a 403 response as blocked', () async {
    final client = _QueueClient([
      const _ResponseSpec(statusCode: 403, body: 'access denied'),
    ]);
    final transport = HttpMinnanoTransport(
      client: client,
      requestDelay: Duration.zero,
    );
    addTearDown(transport.close);

    await expectLater(
      transport.get(Uri.parse('https://www.minnano-av.com/av1.html')),
      throwsA(
        isA<MinnanoRequestException>()
            .having((error) => error.kind, 'kind', MinnanoFailureKind.blocked)
            .having((error) => error.statusCode, 'statusCode', 403),
      ),
    );
  });

  test('retries a rate-limited response using the retry policy', () async {
    final client = _QueueClient([
      const _ResponseSpec(
        statusCode: 429,
        body: 'slow down',
        headers: {'retry-after': '0'},
      ),
      const _ResponseSpec(statusCode: 200, body: '<html>ok</html>'),
    ]);
    final transport = HttpMinnanoTransport(
      client: client,
      requestDelay: Duration.zero,
      retryDelay: Duration.zero,
    );
    addTearDown(transport.close);

    await transport.get(Uri.parse('https://www.minnano-av.com/av1.html'));

    expect(client.requests, hasLength(2));
  });
}

final class _ResponseSpec {
  const _ResponseSpec({
    required this.statusCode,
    required this.body,
    this.headers = const {},
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;
}

final class _QueueClient extends http.BaseClient {
  _QueueClient(Iterable<_ResponseSpec> responses)
    : responses = responses.toList(growable: true);

  final List<_ResponseSpec> responses;
  final requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    if (responses.isEmpty) {
      throw StateError('No response queued for ${request.url}.');
    }
    final response = responses.removeAt(0);
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(response.body)),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}
