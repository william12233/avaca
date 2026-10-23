import '../../models/scrape_source_settings.dart';
import '../minnano/minnano_client.dart';
import '../minnano/minnano_transport.dart';
import 'actress_discovery_source.dart';
import 'minnano_actress_discovery_source.dart';

/// Builds only sources that satisfy discovery's complete capability contract.
/// The other existing scrape sources remain available to the connection test
/// and work/detail settings; they are not shown here until they expose both a
/// ranking and a direct publisher filter.
final class ActressDiscoveryRegistry {
  ActressDiscoveryRegistry() : _sources = _createSources();
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

  static List<ActressDiscoverySource> _createSources() {
    final client = MinnanoClient(transport: HttpMinnanoTransport());
    return [MinnanoActressDiscoverySource(client: client)];
  }
}
