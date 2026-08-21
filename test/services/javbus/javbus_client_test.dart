import 'dart:convert';

import 'package:avaca/services/javbus/javbus_client.dart';
import 'package:avaca/services/javbus/javbus_models.dart';
import 'package:avaca/services/javbus/prefix_exclusion.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'fetches every actress page, excludes prefixes and deduplicates codes',
    () async {
      final transport = _FakeTransport({
        'https://www.javbus.com/star/uly': _page(
          pageCount: 2,
          works: const [('ABF-183', 'first'), ('fc2-123', 'excluded')],
        ),
        'https://www.javbus.com/star/uly/2': _page(
          pageCount: 2,
          works: const [('abf-183', 'duplicate'), ('SONE-833', 'second')],
        ),
      });
      final client = JavBusClient(transport: transport);

      final works = await client.fetchAllActressWorks(
        Uri.parse('https://www.javbus.com/star/uly'),
        exclusions: PrefixExclusion(['FC2']),
      );

      expect(works.map((work) => work.code), ['ABF-183', 'SONE-833']);
      expect(transport.requested, [
        'https://www.javbus.com/star/uly',
        'https://www.javbus.com/star/uly/2',
      ]);
    },
  );

  test(
    'reuses a supplied first actress page while fetching pagination',
    () async {
      final transport = _FakeTransport({
        'https://www.javbus.com/star/uly': _page(
          pageCount: 2,
          works: const [('ABF-183', 'first')],
        ),
        'https://www.javbus.com/star/uly/2': _page(
          pageCount: 2,
          works: const [('SONE-833', 'second')],
        ),
      });
      final client = JavBusClient(transport: transport);
      final firstPage = await client.fetchActressPage(
        Uri.parse('https://www.javbus.com/star/uly'),
      );

      final works = await client.fetchAllActressWorks(
        Uri.parse('https://www.javbus.com/star/uly'),
        firstPage: firstPage,
      );

      expect(works.map((work) => work.code), ['ABF-183', 'SONE-833']);
      expect(transport.requested, [
        'https://www.javbus.com/star/uly',
        'https://www.javbus.com/star/uly/2',
      ]);
    },
  );

  test('deduplicates edition suffixes against their base work codes', () async {
    final transport = _FakeTransport({
      'https://www.javbus.com/star/zen': _page(
        pageCount: 2,
        works: const [
          ('STARS-859-T', 'video edition'),
          ('STARS-757-T', 'special edition'),
          ('STARS-715-VT', 'video special edition'),
          ('START-276V', 'video edition without separator'),
        ],
      ),
      'https://www.javbus.com/star/zen/2': _page(
        pageCount: 2,
        works: const [
          ('STARS-859', 'base'),
          ('STARS-757', 'base'),
          ('STARS-715', 'base'),
          ('START-276', 'base'),
        ],
      ),
    });

    final works = await JavBusClient(
      transport: transport,
    ).fetchAllActressWorks(Uri.parse('https://www.javbus.com/star/zen'));

    expect(works.map((work) => work.code), [
      'STARS-859',
      'STARS-757',
      'STARS-715',
      'START-276',
    ]);
    expect(works.map((work) => work.detailUri.toString()), [
      'https://www.javbus.com/STARS-859',
      'https://www.javbus.com/STARS-757',
      'https://www.javbus.com/STARS-715',
      'https://www.javbus.com/START-276',
    ]);
  });

  test('searches actresses and fetches selected work details', () async {
    final transport = _FakeTransport({
      'https://www.javbus.com/searchstar/remu': '''
        <a class="avatar-box text-center" href="/star/uly">
          <div class="photo-info"><span class="mleft">涼森れむ<button>有碼</button></span></div>
        </a>
      ''',
      'https://www.javbus.com/ABF-183': '''
        <h3>作品</h3><div class="info">
          <p><span class="header">識別碼:</span> ABF-183</p>
          <p><span class="header">長度:</span> 100分鐘</p>
        </div>
      ''',
    });
    final client = JavBusClient(transport: transport);

    final actresses = await client.searchActresses('remu');
    final work = await client.fetchWorkDetails(
      Uri.parse('https://www.javbus.com/ABF-183'),
    );

    expect(actresses.single.name, '涼森れむ');
    expect(work.durationMinutes, 100);
    expect(work.toWork().code, 'ABF-183');
  });

  test('HTTP transport decodes UTF-8 and rejects non-success status', () async {
    final successful = HttpJavBusTransport(
      client: MockClient(
        (_) async => http.Response.bytes(utf8.encode('涼森れむ'), 200),
      ),
    );
    expect(
      await successful.get(Uri.parse('https://www.javbus.com/ok')),
      '涼森れむ',
    );

    final failing = HttpJavBusTransport(
      client: MockClient((_) async => http.Response('', 503)),
    );
    await expectLater(
      failing.get(Uri.parse('https://www.javbus.com/fail')),
      throwsA(isA<JavBusRequestException>()),
    );
  });

  test('connection check requests the JavBus homepage', () async {
    final transport = _FakeTransport({
      'https://www.javbus.com/': '<html><body>ok</body></html>',
    });
    final client = JavBusClient(transport: transport);

    await client.checkConnection();

    expect(transport.requested, ['https://www.javbus.com/']);
  });

  test(
    'HTTP transport retries a bounded number of transient failures',
    () async {
      var attempts = 0;
      final transport = HttpJavBusTransport(
        maxAttempts: 2,
        retryDelay: Duration.zero,
        client: MockClient((_) async {
          attempts++;
          return attempts == 1
              ? http.Response('', 503)
              : http.Response.bytes(utf8.encode('ok'), 200);
        }),
      );

      expect(
        await transport.get(Uri.parse('https://www.javbus.com/transient')),
        'ok',
      );
      expect(attempts, 2);
    },
  );

  test('completes driver verification in the same cookie session', () async {
    var requestNumber = 0;
    final transport = HttpJavBusTransport(
      retryDelay: Duration.zero,
      verificationHandler: (challenge) async {
        expect(challenge.questions.single.prompt, '你是否了解交通規則？');
        expect(challenge.questions.single.options.map((item) => item.label), [
          'A. 是',
          'B. 否',
        ]);
        expect(challenge.submitFields, {'submit': 'question'});
        return {'userAnswers[4]': 'A'};
      },
      client: MockClient((request) async {
        requestNumber++;
        switch (requestNumber) {
          case 1:
            return http.Response(
              '',
              302,
              headers: {
                'location':
                    '/doc/driver-verify?referer=https%3A%2F%2Fwww.javbus.com%2Fsearchstar%2Fremu',
                'set-cookie': 'PHPSESSID=session123; path=/',
              },
            );
          case 2:
            expect(request.headers['cookie'], contains('PHPSESSID=session123'));
            return http.Response.bytes(
              utf8.encode(_driverVerificationHtml),
              200,
            );
          case 3:
            expect(request.method, 'POST');
            expect(request.headers['cookie'], contains('PHPSESSID=session123'));
            expect(request.body, contains('userAnswers%5B4%5D=A'));
            expect(request.body, contains('submit=question'));
            return http.Response(
              '',
              302,
              headers: {
                'location': '/searchstar/remu',
                'set-cookie': 'driver=verified; path=/',
              },
            );
          default:
            expect(request.headers['cookie'], contains('driver=verified'));
            return http.Response('<html>works</html>', 200);
        }
      }),
    );

    final source = await transport.get(
      Uri.parse('https://www.javbus.com/searchstar/remu'),
    );

    expect(source, '<html>works</html>');
    expect(transport.cookieHeader, contains('driver=verified'));
  });

  test(
    'binary requests reuse cookies from the verified JavBus session',
    () async {
      var requestNumber = 0;
      final transport = HttpJavBusTransport(
        client: MockClient((request) async {
          requestNumber++;
          if (requestNumber == 1) {
            return http.Response(
              '<html>works</html>',
              200,
              headers: {'set-cookie': 'driver=verified; path=/'},
            );
          }
          expect(request.url.path, '/pics/actress/zh5_a.jpg');
          expect(request.headers['cookie'], contains('driver=verified'));
          expect(request.headers['referer'], 'https://www.javbus.com/');
          return http.Response.bytes(const [1, 2, 3], 200);
        }),
      );

      await transport.get(Uri.parse('https://www.javbus.com/star/zh5'));
      final image = await transport.getBinary(
        Uri.parse('https://www.javbus.com/pics/actress/zh5_a.jpg'),
      );

      expect(image.statusCode, 200);
      expect(image.bodyBytes, [1, 2, 3]);
    },
  );

  test('completes the current JavBus age confirmation form', () async {
    var requestNumber = 0;
    final transport = HttpJavBusTransport(
      retryDelay: Duration.zero,
      verificationHandler: (challenge) async {
        expect(challenge.questions, isEmpty);
        expect(challenge.submitFields, {'Submit': '確認'});
        return const {};
      },
      client: MockClient((request) async {
        requestNumber++;
        switch (requestNumber) {
          case 1:
            return http.Response(
              '',
              302,
              headers: {
                'location':
                    '/doc/driver-verify?referer=https%3A%2F%2Fwww.javbus.com%2Fsearchstar%2Fremu',
                'set-cookie': 'PHPSESSID=session123; path=/',
              },
            );
          case 2:
            return http.Response.bytes(utf8.encode(_ageConfirmationHtml), 200);
          case 3:
            expect(request.method, 'POST');
            expect(request.headers['cookie'], contains('PHPSESSID=session123'));
            expect(request.body, contains('Submit=%E7%A2%BA%E8%AA%8D'));
            return http.Response(
              '',
              302,
              headers: {
                'location': '/searchstar/remu',
                'set-cookie': 'over18=yes; path=/',
              },
            );
          default:
            expect(request.headers['cookie'], contains('over18=yes'));
            return http.Response('<html>works</html>', 200);
        }
      }),
    );

    expect(
      await transport.get(Uri.parse('https://www.javbus.com/searchstar/remu')),
      '<html>works</html>',
    );
  });

  test(
    'rejects parsed navigation outside the configured JavBus origin',
    () async {
      final transport = _FakeTransport({});
      final client = JavBusClient(transport: transport);

      await expectLater(
        client.fetchWorkDetails(Uri.parse('https://example.com/ABF-183')),
        throwsA(isA<Exception>()),
      );
      expect(transport.requested, isEmpty);
    },
  );

  test(
    'rejects an unbounded pagination count before requesting page two',
    () async {
      final transport = _FakeTransport({
        'https://www.javbus.com/star/uly': _page(
          pageCount: 101,
          works: const [('ABF-183', 'first')],
        ),
      });
      final client = JavBusClient(transport: transport, maxPages: 100);

      await expectLater(
        client.fetchAllActressWorks(
          Uri.parse('https://www.javbus.com/star/uly'),
        ),
        throwsA(isA<JavBusPageLimitException>()),
      );
      expect(transport.requested, ['https://www.javbus.com/star/uly']);
    },
  );

  test('cancellation stops pagination before another page request', () async {
    var cancelled = false;
    final transport = _CallbackTransport({
      'https://www.javbus.com/star/uly': _page(
        pageCount: 3,
        works: const [('ABF-183', 'first')],
      ),
    }, afterGet: () => cancelled = true);
    final client = JavBusClient(transport: transport);

    final works = await client.fetchAllActressWorks(
      Uri.parse('https://www.javbus.com/star/uly'),
      isCancelled: () => cancelled,
    );

    expect(works.map((work) => work.code), ['ABF-183']);
    expect(transport.requested, ['https://www.javbus.com/star/uly']);
  });
  test('keeps successful pages when a later pagination page fails', () async {
    final transport = _FakeTransport({
      'https://www.javbus.com/star/partial': _page(
        pageCount: 2,
        works: const [('SSIS-875', 'first page')],
      ),
    });
    final result = await JavBusClient(transport: transport)
        .fetchAllActressWorksResult(
          Uri.parse('https://www.javbus.com/star/partial'),
        );

    expect(result.works.map((work) => work.code), ['SSIS-875']);
    expect(result.issues, hasLength(1));
    expect(result.issues.single.uri.toString(), endsWith('/star/partial/2'));
    expect(result.issues.single.kind, JavBusPageIssueKind.parserInvalid);
  });

  test(
    'classifies Cloudflare access denial instead of calling it missing',
    () async {
      final transport = HttpJavBusTransport(
        retryDelay: Duration.zero,
        client: MockClient(
          (_) async => http.Response('Access denied | Cloudflare', 403),
        ),
      );

      await expectLater(
        transport.get(Uri.parse('https://www.javbus.com/star/blocked')),
        throwsA(
          isA<JavBusRequestException>().having(
            (error) => error.kind,
            'kind',
            JavBusFailureKind.blocked,
          ),
        ),
      );
    },
  );
}

const _driverVerificationHtml = '''
<html><body>
  <form method="POST" action="driver-verify.php?referer=/searchstar/remu">
    <input type="hidden" name="token" value="abc">
    <ul><li><label>
      你是否了解交通規則？<br>
      <input type="radio" name="userAnswers[4]" value="A"> A. 是<br>
      <input type="radio" name="userAnswers[4]" value="B"> B. 否<br>
    </label></li></ul>
    <button type="submit" name="submit" value="question">送出答案</button>
  </form>
</body></html>
''';

const _ageConfirmationHtml = '''
<html><body>
  <form class="form1" method="post" action="" id="form1">
    <label><input type="checkbox" value="">我已經成年</label>
    <input id="submit" value="確認" type="submit" name="Submit">
  </form>
</body></html>
''';

class _FakeTransport implements JavBusTransport {
  _FakeTransport(this.responses);

  final Map<String, String> responses;
  final List<String> requested = [];

  @override
  Future<String> get(Uri uri) async {
    requested.add(uri.toString());
    final response = responses[uri.toString()];
    if (response == null) {
      throw StateError('Unexpected URI: $uri');
    }
    return response;
  }
}

class _CallbackTransport extends _FakeTransport {
  _CallbackTransport(super.responses, {required this.afterGet});

  final void Function() afterGet;

  @override
  Future<String> get(Uri uri) async {
    final value = await super.get(uri);
    afterGet();
    return value;
  }
}

String _page({required int pageCount, required List<(String, String)> works}) {
  final cards = works
      .map(
        (work) =>
            '''
        <a class="movie-box" href="/${work.$1}">
          <div class="photo-info">
            <span>${work.$2}</span><date>${work.$1}</date><date>2024-01-01</date>
          </div>
        </a>
        ''',
      )
      .join();
  return '''
    <html><body>
      <div class="avatar-box"><div class="photo-info"><span>涼森れむ</span></div></div>
      $cards
      <ul class="pagination"><li><a>$pageCount</a></li></ul>
    </body></html>
  ''';
}
