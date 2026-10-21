import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/software_update_models.dart';
import 'app_version_provider.dart';

typedef UpdateProgressCallback = void Function(int received, int total);

/// GitHub Release client for the two self-update targets supported by AVACA.
///
/// Metadata is read into memory because it is small and bounded. Binary
/// assets are always streamed to a private temporary directory and hashed as
/// they arrive.
class SoftwareUpdateService {
  SoftwareUpdateService({
    http.Client? client,
    AppVersionProvider? versionProvider,
    SoftwareUpdatePlatform? platformOverride,
    String? architectureOverride,
    Future<Directory> Function()? temporaryDirectoryProvider,
    Future<DownloadedUpdate> Function(
      SoftwareUpdateResult result, {
      UpdateProgressCallback? onProgress,
    })?
    downloadOverride,
    this.timeout = const Duration(seconds: 30),
    this.maxRedirects = 4,
    this.maxDownloadBytes = 1024 * 1024 * 1024,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _versionProvider = versionProvider ?? PackageInfoAppVersionProvider(),
       _platformOverride = platformOverride,
       _architectureOverride = architectureOverride,
       _temporaryDirectoryProvider = temporaryDirectoryProvider,
       _downloadOverride = downloadOverride;

  static const repository = 'william12233/avaca';
  static const _apiHost = 'api.github.com';
  static const _downloadHosts = <String>{
    'github.com',
    'objects.githubusercontent.com',
    'release-assets.githubusercontent.com',
  };
  static const _metadataLimit = 2 * 1024 * 1024;
  static const _windowsMaxArchiveEntries = 4096;
  static const _windowsMaxSingleEntryBytes = 512 * 1024 * 1024;
  static const _windowsMaxTotalUncompressedBytes = 2 * 1024 * 1024 * 1024;

  final http.Client _client;
  final bool _ownsClient;
  final AppVersionProvider _versionProvider;
  final SoftwareUpdatePlatform? _platformOverride;
  final String? _architectureOverride;
  final Future<Directory> Function()? _temporaryDirectoryProvider;
  final Future<DownloadedUpdate> Function(
    SoftwareUpdateResult result, {
    UpdateProgressCallback? onProgress,
  })?
  _downloadOverride;
  final Duration timeout;
  final int maxRedirects;
  final int maxDownloadBytes;

  Future<AppVersionInfo> currentVersion() => _versionProvider.load();

  Future<SoftwareUpdateResult> checkForUpdates() async {
    final current = await currentVersion();
    final platform = _platformOverride ?? current.platform;
    if (platform == SoftwareUpdatePlatform.unsupported) {
      return SoftwareUpdateResult(
        status: UpdateStatus.notSupported,
        current: current,
        error: const SoftwareUpdateException(
          UpdateFailureReason.notSupported,
          'This platform does not have a self-update target.',
        ),
      );
    }

    final release = await _fetchLatestRelease();
    if (release.version.compareTo(current.semanticVersion) <= 0) {
      return SoftwareUpdateResult(
        status: UpdateStatus.upToDate,
        current: current,
        release: release,
      );
    }

    final asset = _selectAsset(
      release,
      platform,
      _architectureOverride ?? current.architecture,
    );
    return SoftwareUpdateResult(
      status: asset == null
          ? UpdateStatus.unavailable
          : UpdateStatus.updateAvailable,
      current: current,
      release: release,
      asset: asset,
      error: asset == null
          ? const SoftwareUpdateException(
              UpdateFailureReason.assetUnavailable,
              'No compatible release asset was found.',
            )
          : null,
    );
  }

  Future<DownloadedUpdate> download(
    SoftwareUpdateResult result, {
    UpdateProgressCallback? onProgress,
  }) async {
    final override = _downloadOverride;
    if (override != null) {
      return override(result, onProgress: onProgress);
    }
    final release = result.release;
    final asset = result.asset;
    if (!result.hasUpdate || release == null || asset == null) {
      throw const SoftwareUpdateException(
        UpdateFailureReason.assetUnavailable,
        'There is no compatible update to download.',
      );
    }
    final downloadUri = asset.downloadUrl;
    if (downloadUri == null || asset.size <= 0) {
      throw const SoftwareUpdateException(
        UpdateFailureReason.invalidMetadata,
        'The release asset metadata is incomplete.',
      );
    }

    final tempDirectory = _temporaryDirectoryProvider == null
        ? await getTemporaryDirectory()
        : await _temporaryDirectoryProvider();
    final stagingDirectory = Directory(
      path.join(
        tempDirectory.path,
        'avaca-update-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await stagingDirectory.create(recursive: true);
    final outputFile = File(path.join(stagingDirectory.path, asset.name));

    try {
      final response = await _send(downloadUri);
      if (response.statusCode != HttpStatus.ok) {
        await response.stream.drain();
        throw SoftwareUpdateException(
          UpdateFailureReason.download,
          'GitHub returned HTTP ${response.statusCode}.',
        );
      }

      final contentLength = response.contentLength;
      if (contentLength != null && contentLength != asset.size) {
        await response.stream.drain();
        throw const SoftwareUpdateException(
          UpdateFailureReason.integrity,
          'The downloaded size does not match the release metadata.',
        );
      }
      if (contentLength != null && contentLength > maxDownloadBytes) {
        await response.stream.drain();
        throw const SoftwareUpdateException(
          UpdateFailureReason.download,
          'The update asset is too large.',
        );
      }

      final digestSink = _DigestSink();
      final digestInput = sha256.startChunkedConversion(digestSink);
      final output = outputFile.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream) {
          received += chunk.length;
          if (received > maxDownloadBytes || received > asset.size) {
            throw const SoftwareUpdateException(
              UpdateFailureReason.download,
              'The update asset exceeded its declared size.',
            );
          }
          digestInput.add(chunk);
          output.add(chunk);
          onProgress?.call(received, asset.size);
        }
      } finally {
        digestInput.close();
        await output.close();
      }

      if (received != asset.size) {
        throw const SoftwareUpdateException(
          UpdateFailureReason.integrity,
          'The downloaded asset is truncated.',
        );
      }

      final expectedHash = await _expectedHash(asset);
      final actualHash = digestSink.value.toString().toLowerCase();
      if (actualHash != expectedHash) {
        throw const SoftwareUpdateException(
          UpdateFailureReason.integrity,
          'The update SHA-256 digest does not match.',
        );
      }

      final extractedDirectory =
          result.current.platform == SoftwareUpdatePlatform.windows
          ? await _prepareWindowsPortableArchive(
              outputFile,
              stagingDirectory,
              release.version,
            )
          : null;

      return DownloadedUpdate(
        file: outputFile,
        stagingDirectory: stagingDirectory,
        release: release,
        asset: asset,
        extractedDirectory: extractedDirectory,
      );
    } catch (error) {
      if (await stagingDirectory.exists()) {
        await stagingDirectory.delete(recursive: true);
      }
      if (error is SoftwareUpdateException) rethrow;
      throw SoftwareUpdateException(
        UpdateFailureReason.download,
        error.toString(),
      );
    }
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }

  Future<Directory> _prepareWindowsPortableArchive(
    File archiveFile,
    Directory stagingDirectory,
    SemanticVersion expectedVersion,
  ) async {
    InputFileStream? input;
    try {
      final decoder = ZipDecoder();
      input = InputFileStream(archiveFile.path);
      final archive = decoder.decodeStream(input, verify: true);
      final headers = decoder.directory.fileHeaders;
      if (headers.length > _windowsMaxArchiveEntries) {
        throw const SoftwareUpdateException(
          UpdateFailureReason.integrity,
          'The Windows update ZIP contains too many entries.',
        );
      }

      var totalUncompressedBytes = 0;
      for (final header in headers) {
        if (header.uncompressedSize > _windowsMaxSingleEntryBytes) {
          throw const SoftwareUpdateException(
            UpdateFailureReason.integrity,
            'A Windows update ZIP entry is too large.',
          );
        }
        totalUncompressedBytes += header.uncompressedSize;
        if (totalUncompressedBytes > _windowsMaxTotalUncompressedBytes) {
          throw const SoftwareUpdateException(
            UpdateFailureReason.integrity,
            'The Windows update ZIP expands beyond the supported size.',
          );
        }
        if (header.uncompressedSize > 0 &&
            (header.compressedSize <= 0 ||
                header.uncompressedSize > header.compressedSize * 200)) {
          throw const SoftwareUpdateException(
            UpdateFailureReason.integrity,
            'The Windows update ZIP compression ratio is unsafe.',
          );
        }
      }

      final extractRoot = Directory(
        path.join(stagingDirectory.path, 'portable'),
      );
      await extractRoot.create(recursive: true);
      final names = <String>{};

      for (final entry in archive.files) {
        final rawName = entry.name;
        final isDirectory = entry.isDirectory || rawName.endsWith('/');
        final name = _validateWindowsArchivePath(
          isDirectory ? rawName.substring(0, rawName.length - 1) : rawName,
        );
        if (!names.add(name)) {
          throw const SoftwareUpdateException(
            UpdateFailureReason.integrity,
            'The Windows update ZIP contains duplicate entries.',
          );
        }
        if (isDirectory) continue;
        if (entry.isSymbolicLink) {
          throw const SoftwareUpdateException(
            UpdateFailureReason.integrity,
            'The Windows update ZIP contains a symbolic link.',
          );
        }

        final target = File(
          path.joinAll(<String>[extractRoot.path, ...name.split('/')]),
        );
        await target.parent.create(recursive: true);
        final extractedBytes = await _extractArchiveEntry(entry, target);
        if (extractedBytes != entry.size) {
          throw const SoftwareUpdateException(
            UpdateFailureReason.integrity,
            'The Windows update ZIP contains a corrupt entry.',
          );
        }
      }

      final executable = File(path.join(extractRoot.path, 'avaca.exe'));
      final updater = File(path.join(extractRoot.path, 'avaca_update.exe'));
      final versionFile = File(path.join(extractRoot.path, 'version.txt'));
      if (!await executable.exists() ||
          !await updater.exists() ||
          !await versionFile.exists()) {
        throw const SoftwareUpdateException(
          UpdateFailureReason.integrity,
          'The Windows update ZIP is missing required portable files.',
        );
      }
      final actualVersion = (await versionFile.readAsString()).trim();
      if (actualVersion != expectedVersion.toString()) {
        throw SoftwareUpdateException(
          UpdateFailureReason.integrity,
          'The Windows update version $actualVersion does not match '
          '${expectedVersion.toString()}.',
        );
      }
      return extractRoot;
    } on SoftwareUpdateException {
      rethrow;
    } on Object catch (error) {
      throw SoftwareUpdateException(
        UpdateFailureReason.integrity,
        'The Windows update ZIP could not be prepared: $error',
      );
    } finally {
      await input?.close();
    }
  }

  Future<int> _extractArchiveEntry(ArchiveFile entry, File target) async {
    final content = entry.getContent();
    if (content == null) return -1;
    final output = target.openWrite();
    var written = 0;
    try {
      while (!content.isEOS) {
        final chunkSize = content.length.clamp(1, 1024 * 1024);
        final chunk = content.readBytes(chunkSize).toUint8List();
        if (chunk.isEmpty) break;
        output.add(chunk);
        written += chunk.length;
      }
    } finally {
      await output.close();
    }
    return written;
  }

  String _validateWindowsArchivePath(String value) {
    if (value.isEmpty ||
        value.contains('\\') ||
        value.contains('\u0000') ||
        value.startsWith('/') ||
        value.startsWith('//') ||
        RegExp(r'^[A-Za-z]:').hasMatch(value)) {
      throw const SoftwareUpdateException(
        UpdateFailureReason.integrity,
        'The Windows update ZIP contains an unsafe path.',
      );
    }
    final segments = value.split('/');
    if (segments.any(
      (segment) => segment.isEmpty || segment == '.' || segment == '..',
    )) {
      throw const SoftwareUpdateException(
        UpdateFailureReason.integrity,
        'The Windows update ZIP contains a traversal path.',
      );
    }
    return value;
  }

  Future<SoftwareRelease> _fetchLatestRelease() async {
    final response = await _send(
      Uri.parse('https://$_apiHost/repos/$repository/releases/latest'),
    );
    if (response.statusCode != HttpStatus.ok) {
      await response.stream.drain();
      throw SoftwareUpdateException(
        UpdateFailureReason.network,
        'GitHub returned HTTP ${response.statusCode}.',
      );
    }

    final body = await _readBounded(response.stream, _metadataLimit);
    try {
      final decoded = jsonDecode(utf8.decode(body));
      if (decoded is! Map) {
        throw const FormatException('GitHub metadata is not an object.');
      }
      return SoftwareRelease.fromJson(Map<String, dynamic>.from(decoded));
    } on SoftwareUpdateException {
      rethrow;
    } on FormatException catch (error) {
      throw SoftwareUpdateException(
        UpdateFailureReason.invalidMetadata,
        error.message,
      );
    } on Object catch (error) {
      throw SoftwareUpdateException(
        UpdateFailureReason.invalidMetadata,
        error.toString(),
      );
    }
  }

  ReleaseAsset? _selectAsset(
    SoftwareRelease release,
    SoftwareUpdatePlatform platform,
    String architecture,
  ) {
    final expectedName = switch (platform) {
      SoftwareUpdatePlatform.android when architecture == 'arm64-v8a' =>
        'avaca-${release.version}-arm64-v8a.apk',
      SoftwareUpdatePlatform.windows when architecture == 'x64' =>
        'avaca-${release.version}.zip',
      _ => null,
    };
    if (expectedName == null) return null;

    final matches = release.assets
        .where((asset) => asset.name == expectedName)
        .toList(growable: false);
    if (matches.length != 1) return null;
    final asset = matches.single;
    final checksumMatches = release.assets
        .where((candidate) => candidate.name == '$expectedName.sha256')
        .toList(growable: false);
    if (asset.sha256 == null && checksumMatches.length != 1) return null;
    return ReleaseAsset(
      name: asset.name,
      downloadUrl: asset.downloadUrl,
      size: asset.size,
      digest: asset.digest,
      checksumAsset: checksumMatches.length == 1
          ? checksumMatches.single
          : null,
    );
  }

  Future<String> _expectedHash(ReleaseAsset asset) async {
    final embedded = asset.sha256;
    if (embedded != null) return embedded;
    final checksumAsset = asset.checksumAsset;
    if (checksumAsset == null || checksumAsset.downloadUrl == null) {
      throw const SoftwareUpdateException(
        UpdateFailureReason.integrity,
        'The release does not provide a SHA-256 digest.',
      );
    }
    final response = await _send(checksumAsset.downloadUrl!);
    if (response.statusCode != HttpStatus.ok) {
      await response.stream.drain();
      throw const SoftwareUpdateException(
        UpdateFailureReason.integrity,
        'The release checksum could not be downloaded.',
      );
    }
    final bytes = await _readBounded(response.stream, 4096);
    final text = utf8.decode(bytes);
    final match = RegExp(
      r'(?<![0-9a-f])([0-9a-f]{64})(?![0-9a-f])',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) {
      throw const SoftwareUpdateException(
        UpdateFailureReason.integrity,
        'The release checksum is malformed.',
      );
    }
    return match.group(1)!.toLowerCase();
  }

  Future<http.StreamedResponse> _send(Uri uri) async {
    var current = uri;
    for (var redirect = 0; redirect <= maxRedirects; redirect++) {
      _validateUri(current);
      final request = http.Request('GET', current)
        ..followRedirects = false
        ..headers['Accept'] = 'application/vnd.github+json'
        ..headers['User-Agent'] = 'avaca-software-updater';
      final response = await _client.send(request).timeout(timeout);
      if (!_isRedirect(response.statusCode)) return response;

      await response.stream.drain();
      final location = response.headers['location'];
      if (location == null || redirect == maxRedirects) {
        throw const SoftwareUpdateException(
          UpdateFailureReason.network,
          'The GitHub download redirect is invalid.',
        );
      }
      current = current.resolve(location);
    }
    throw const SoftwareUpdateException(
      UpdateFailureReason.network,
      'Too many GitHub download redirects.',
    );
  }

  Future<Uint8List> _readBounded(Stream<List<int>> stream, int maxBytes) async {
    final builder = BytesBuilder(copy: false);
    var received = 0;
    await for (final chunk in stream) {
      received += chunk.length;
      if (received > maxBytes) {
        throw SoftwareUpdateException(
          UpdateFailureReason.network,
          'The GitHub response exceeded $maxBytes bytes.',
        );
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  void _validateUri(Uri uri) {
    final allowedHost =
        uri.host.toLowerCase() == _apiHost ||
        _downloadHosts.contains(uri.host.toLowerCase());
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443) ||
        !allowedHost) {
      throw SoftwareUpdateException(
        UpdateFailureReason.network,
        'The GitHub URI is not allowed: $uri',
      );
    }
  }

  bool _isRedirect(int statusCode) {
    return statusCode == HttpStatus.movedPermanently ||
        statusCode == HttpStatus.found ||
        statusCode == HttpStatus.seeOther ||
        statusCode == HttpStatus.temporaryRedirect ||
        statusCode == HttpStatus.permanentRedirect;
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? _digest;

  Digest get value => _digest!;

  @override
  void add(Digest value) {
    _digest = value;
  }

  @override
  void close() {}
}
