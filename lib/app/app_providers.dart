import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/data_transfer_controller.dart';
import '../controllers/settings_controller.dart';
import '../controllers/software_update_controller.dart';
import '../core/database.dart';
import '../services/actress_discovery/actress_discovery_cache.dart';
import '../services/actress_discovery/actress_discovery_registry.dart';
import '../services/actress_discovery/actress_discovery_service.dart';
import '../services/actress_import_service.dart';
import '../services/data_transfer_service.dart';
import '../services/scrape_job_coordinator.dart';
import '../services/software_update_installer.dart';
import '../services/software_update_preferences.dart';
import '../services/software_update_service.dart';
import '../services/update_cache_service.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw StateError('appDatabaseProvider must be overridden at the app root.');
});

final softwareUpdateServiceProvider = Provider<SoftwareUpdateService>((ref) {
  final service = SoftwareUpdateService();
  ref.onDispose(service.dispose);
  return service;
});

final softwareUpdateInstallerProvider = Provider<SoftwareUpdateInstaller>((
  ref,
) {
  return SoftwareUpdateInstaller.forCurrentPlatform(
    onBeforeWindowsUpdate: ref.read(appDatabaseProvider).close,
  );
});

final softwareUpdatePreferencesProvider = Provider<SoftwareUpdatePreferences>(
  (ref) => SoftwareUpdatePreferences(),
);

final softwareUpdateControllerProvider = Provider<SoftwareUpdateController>((
  ref,
) {
  final controller = SoftwareUpdateController(
    service: ref.read(softwareUpdateServiceProvider),
    installer: ref.read(softwareUpdateInstallerProvider),
    preferences: ref.read(softwareUpdatePreferencesProvider),
    disposeService: false,
  );
  ref.onDispose(controller.dispose);
  return controller;
});

final dataTransferServiceProvider = Provider<DataTransferService>((ref) {
  return DataTransferService(db: ref.read(appDatabaseProvider));
});

final dataTransferControllerProvider = Provider<DataTransferController>((ref) {
  final controller = DataTransferController(
    service: ref.read(dataTransferServiceProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

final settingsControllerProvider = Provider<SettingsController>((ref) {
  final controller = SettingsController(db: ref.read(appDatabaseProvider));
  ref.onDispose(controller.dispose);
  return controller;
});

final updateCacheServiceProvider = Provider<UpdateCacheService>(
  (ref) => UpdateCacheService(
    preferences: ref.read(softwareUpdatePreferencesProvider),
  ),
);

final scrapeJobCoordinatorProvider = Provider<ScrapeJobCoordinator>((ref) {
  final coordinator = ScrapeJobCoordinator(db: ref.read(appDatabaseProvider));
  ref.onDispose(() {
    coordinator.rulesRepository.close();
    coordinator.dispose();
  });
  return coordinator;
});

final actressDiscoveryRegistryProvider = Provider<ActressDiscoveryRegistry>((
  ref,
) {
  final registry = ActressDiscoveryRegistry(
    verificationHandler: ref
        .read(scrapeJobCoordinatorProvider)
        .verificationHandler,
  );
  ref.onDispose(registry.close);
  return registry;
});

final actressDiscoveryCacheProvider = Provider<ActressDiscoveryCache>(
  (ref) => ActressDiscoveryCache(),
);

final actressDiscoveryServiceProvider = Provider<ActressDiscoveryService>(
  (ref) => ActressDiscoveryService(
    db: ref.read(appDatabaseProvider),
    registry: ref.read(actressDiscoveryRegistryProvider),
    cache: ref.read(actressDiscoveryCacheProvider),
  ),
);

final actressImportServiceProvider = Provider<ActressImportService>(
  (ref) => ActressImportService(
    db: ref.read(appDatabaseProvider),
    verificationHandler: ref
        .read(scrapeJobCoordinatorProvider)
        .verificationHandler,
  ),
);
