import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:avaca/models/software_update_models.dart';
import 'package:avaca/services/app_version_provider.dart';
import 'package:avaca/services/software_update_service.dart';

class _FakeVersionProvider implements AppVersionProvider {
  _FakeVersionProvider(this.value);

  final AppVersionInfo value;

  @override
  Future<AppVersionInfo> load() async => value;
}

void main() {
  group('SemanticVersion', () {
    test('compares release tags numerically', () {
      expect(
        SemanticVersion.parse(
          'v0.7.10',
        ).compareTo(SemanticVersion.parse('0.7.9')),
        greaterThan(0),
      );
      expect(SemanticVersion.parse('0.7.10'), SemanticVersion.parse('v0.7.10'));
      expect(
        () => SemanticVersion.parse('v0.7.10-beta'),
        throwsFormatException,
      );
    });
  });

  group('SoftwareUpdateService', () {
    test(
      'selects the exact Android asset and verifies its streamed digest',
      () async {
        final bytes = Uint8List.fromList(
          List<int>.generate(128, (index) => index),
        );
        final checksum = sha256.convert(bytes).toString();
        final tempRoot = await Directory.systemTemp.createTemp(
          'avaca-service-test-',
        );
        addTearDown(() => tempRoot.delete(recursive: true));
        final client = MockClient((request) async {
          if (request.url.path.endsWith('/releases/latest')) {
            return http.Response(
              jsonEncode(_releaseJson(checksum: null, size: bytes.length)),
              200,
            );
          }
          if (request.url.path.endsWith('.apk')) {
            return http.Response.bytes(
              bytes,
              200,
              headers: {'content-length': '${bytes.length}'},
            );
          }
          return http.Response('$checksum  avaca-0.8.2-arm64-v8a.apk\n', 200);
        });

        final service = SoftwareUpdateService(
          client: client,
          versionProvider: _FakeVersionProvider(_androidVersion('0.8.1')),
          platformOverride: SoftwareUpdatePlatform.android,
          architectureOverride: 'arm64-v8a',
          temporaryDirectoryProvider: () async => tempRoot,
        );
        addTearDown(service.dispose);

        final result = await service.checkForUpdates();
        expect(result.status, UpdateStatus.updateAvailable);
        expect(result.asset?.name, 'avaca-0.8.2-arm64-v8a.apk');

        final progress = <DownloadProgress>[];
        final downloaded = await service.download(
          result,
          onProgress: progress.add,
        );
        expect(progress.first.receivedBytes, 0);
        expect(progress.first.totalBytes, bytes.length);
        expect(progress.last.receivedBytes, bytes.length);
        expect(progress.last.percentage, 100);
        expect(await downloaded.file.readAsBytes(), bytes);
        expect(await downloaded.file.exists(), isTrue);
      },
    );

    test(
      'fails closed without a compatible asset or source archive fallback',
      () async {
        final client = MockClient((request) async {
          return http.Response(
            jsonEncode(
              _releaseJson(
                checksum: '0' * 64,
                size: 4,
                assets: [
                  _asset('source-code.zip', 4),
                  _asset('avaca-0.8.2-x86_64.apk', 4),
                ],
              ),
            ),
            200,
          );
        });
        final service = SoftwareUpdateService(
          client: client,
          versionProvider: _FakeVersionProvider(_androidVersion('0.8.1')),
          platformOverride: SoftwareUpdatePlatform.android,
          architectureOverride: 'arm64-v8a',
        );
        addTearDown(service.dispose);

        final result = await service.checkForUpdates();
        expect(result.status, UpdateStatus.unavailable);
        expect(result.asset, isNull);
      },
    );

    test('removes a partial download after digest mismatch', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final tempRoot = await Directory.systemTemp.createTemp(
        'avaca-service-test-',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/releases/latest')) {
          return http.Response(
            jsonEncode(_releaseJson(checksum: null, size: bytes.length)),
            200,
          );
        }
        if (request.url.path.endsWith('.apk')) {
          return http.Response.bytes(bytes, 200);
        }
        return http.Response('${'0' * 64}  package.apk\n', 200);
      });
      final service = SoftwareUpdateService(
        client: client,
        versionProvider: _FakeVersionProvider(_androidVersion('0.8.1')),
        platformOverride: SoftwareUpdatePlatform.android,
        architectureOverride: 'arm64-v8a',
        temporaryDirectoryProvider: () async => tempRoot,
      );
      addTearDown(service.dispose);
      final result = await service.checkForUpdates();

      await expectLater(
        service.download(result),
        throwsA(isA<SoftwareUpdateException>()),
      );
      final remaining = await tempRoot.list().toList();
      expect(remaining, isEmpty);
    });

    test(
      'prepares a verified Windows portable archive for the native helper',
      () async {
        final archive = Archive()
          ..addFile(ArchiveFile.bytes('avaca.exe', [1, 2, 3]))
          ..addFile(ArchiveFile.bytes('avaca_update.exe', [4, 5, 6]))
          ..addFile(ArchiveFile.bytes('version.txt', utf8.encode('0.8.2')));
        final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
        final checksum = sha256.convert(bytes).toString();
        final tempRoot = await Directory.systemTemp.createTemp(
          'avaca-windows-update-test-',
        );
        addTearDown(() => tempRoot.delete(recursive: true));
        final client = MockClient((request) async {
          if (request.url.path.endsWith('/releases/latest')) {
            return http.Response(
              jsonEncode(_windowsReleaseJson(checksum, bytes.length)),
              200,
            );
          }
          return http.Response.bytes(
            bytes,
            200,
            headers: {'content-length': '${bytes.length}'},
          );
        });

        final service = SoftwareUpdateService(
          client: client,
          versionProvider: _FakeVersionProvider(_windowsVersion('0.8.1')),
          platformOverride: SoftwareUpdatePlatform.windows,
          architectureOverride: 'x64',
          temporaryDirectoryProvider: () async => tempRoot,
        );
        addTearDown(service.dispose);

        final result = await service.checkForUpdates();
        final downloaded = await service.download(result);
        final extracted = downloaded.extractedDirectory;
        expect(extracted, isNotNull);
        expect(await File('${extracted!.path}/avaca.exe').exists(), isTrue);
        expect(
          await File('${extracted.path}/avaca_update.exe').exists(),
          isTrue,
        );
        expect(
          await File('${extracted.path}/version.txt').readAsString(),
          '0.8.2',
        );
      },
    );

    test('rejects traversal paths in a Windows update archive', () async {
      final archive = Archive()
        ..addFile(ArchiveFile.bytes('../avaca.exe', [1, 2, 3]));
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
      final checksum = sha256.convert(bytes).toString();
      final tempRoot = await Directory.systemTemp.createTemp(
        'avaca-windows-unsafe-update-test-',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/releases/latest')) {
          return http.Response(
            jsonEncode(_windowsReleaseJson(checksum, bytes.length)),
            200,
          );
        }
        return http.Response.bytes(bytes, 200);
      });
      final service = SoftwareUpdateService(
        client: client,
        versionProvider: _FakeVersionProvider(_windowsVersion('0.8.1')),
        platformOverride: SoftwareUpdatePlatform.windows,
        architectureOverride: 'x64',
        temporaryDirectoryProvider: () async => tempRoot,
      );
      addTearDown(service.dispose);

      final result = await service.checkForUpdates();
      await expectLater(
        service.download(result),
        throwsA(isA<SoftwareUpdateException>()),
      );
      expect(await tempRoot.list().toList(), isEmpty);
    });
  });
}

AppVersionInfo _androidVersion(String version) {
  return AppVersionInfo(
    version: version,
    buildNumber: '1',
    platform: SoftwareUpdatePlatform.android,
    architecture: 'arm64-v8a',
  );
}

AppVersionInfo _windowsVersion(String version) {
  return AppVersionInfo(
    version: version,
    buildNumber: '1',
    platform: SoftwareUpdatePlatform.windows,
    architecture: 'x64',
  );
}

Map<String, dynamic> _windowsReleaseJson(String checksum, int size) {
  return {
    'tag_name': 'v0.8.2',
    'draft': false,
    'prerelease': false,
    'assets': [_asset('avaca-0.8.2.zip', size, digest: checksum)],
  };
}

Map<String, dynamic> _releaseJson({
  required String? checksum,
  required int size,
  List<Map<String, dynamic>>? assets,
}) {
  final releaseAssets =
      assets ??
      [
        _asset('avaca-0.8.2-arm64-v8a.apk', size, digest: checksum),
        _asset('avaca-0.8.2-arm64-v8a.apk.sha256', 70),
      ];
  return {
    'tag_name': 'v0.8.2',
    'draft': false,
    'prerelease': false,
    'assets': releaseAssets,
  };
}

Map<String, dynamic> _asset(String name, int size, {String? digest}) {
  return {
    'name': name,
    'browser_download_url':
        'https://github.com/william12233/avaca/releases/download/v0.8.2/$name',
    'size': size,
    'digest': digest == null ? null : 'sha256:$digest',
  };
}
