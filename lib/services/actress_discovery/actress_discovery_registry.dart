import '../../models/scrape_source_settings.dart';
import '../avbase/avbase_client.dart';
import '../avbase/avbase_transport.dart';
import '../avwiki/avwiki_client.dart';
import '../avwiki/avwiki_transport.dart';
import '../javbus/javbus_client.dart';
import '../javbus/javbus_verification.dart';
import '../javdb/javdb_client.dart';
import '../minnano/minnano_client.dart';
import '../minnano/minnano_transport.dart';
import 'actress_discovery_source.dart';
import 'avbase_actress_discovery_source.dart';
import 'avwiki_actress_discovery_source.dart';
import 'javbus_actress_discovery_source.dart';
import 'javdb_actress_discovery_source.dart';
import 'minnano_actress_discovery_source.dart';

/// Creates the source-native actress catalog adapters.
final class ActressDiscoveryRegistry {
  ActressDiscoveryRegistry({JavBusVerificationHandler? verificationHandler})
    : _sources = _createSources(verificationHandler);

  final List<ActressDiscoverySource> _sources;

  List<ActressDiscoverySource> get sources => List.unmodifiable(_sources);

  ActressDiscoverySource? byId(ScrapeSourceId id) {
    for (final source in _sources) {
      if (source.id == id) return source;
    }
    return null;
  }

  void close() {
    for (final source in _sources) {
      source.close();
    }
  }

  static List<ActressDiscoverySource> _createSources(
    JavBusVerificationHandler? verificationHandler,
  ) {
    final javBusTransport = HttpJavBusTransport(
      verificationHandler: verificationHandler,
    );
    return [
      MinnanoActressDiscoverySource(
        client: MinnanoClient(transport: HttpMinnanoTransport()),
      ),
      JavBusActressDiscoverySource(
        client: JavBusClient(transport: javBusTransport),
      ),
      AvBaseActressDiscoverySource(
        client: AvBaseClient(transport: HttpAvBaseTransport()),
      ),
      AvWikiActressDiscoverySource(
        client: AvWikiClient(transport: HttpAvWikiTransport()),
      ),
      JavDbActressDiscoverySource(
        client: JavDbClient(transport: HttpJavDbTransport()),
      ),
    ];
  }
}
