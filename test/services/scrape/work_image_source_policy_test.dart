import 'package:avaca/services/javbus/javbus_client.dart';
import 'package:avaca/services/javbus/javbus_scrape_source.dart';
import 'package:avaca/services/minnano/minnano_client.dart';
import 'package:avaca/services/minnano/minnano_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Minnano accepts actress avatars but rejects work images', () {
    final client = MinnanoClient(transport: _NoopMinnanoTransport());

    expect(
      client.acceptsImageUri(
        Uri.parse(
          'https://www.minnano-av.com/p_actress_125_125/actress_123.jpg',
        ),
      ),
      isTrue,
    );
    expect(
      client.acceptsImageUri(
        Uri.parse('https://www.minnano-av.com/p_package/2605/195939.jpg'),
      ),
      isFalse,
    );
  });

  test('JavBus accepts actress avatars but rejects work images', () {
    final source = JavBusScrapeSource(
      JavBusClient(transport: _NoopJavBusTransport()),
    );

    expect(
      source.acceptsImageUri(
        Uri.parse('https://www.javbus.com/pics/actress/zh5_a.jpg'),
      ),
      isTrue,
    );
    expect(
      source.acceptsImageUri(
        Uri.parse('https://www.javbus.com/pics/cover/start00408.jpg'),
      ),
      isFalse,
    );
    expect(
      source.acceptsImageUri(
        Uri.parse('https://www.javbus.com/pics/actress/nowprinting.gif'),
      ),
      isFalse,
    );
  });
}

final class _NoopMinnanoTransport implements MinnanoTransport {
  @override
  Future<String> get(Uri uri) async => '';
}

final class _NoopJavBusTransport implements JavBusTransport {
  @override
  Future<String> get(Uri uri) async => '';
}
