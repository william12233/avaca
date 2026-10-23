import 'dart:io';

enum SoftwareUpdatePlatform { android, windows, unsupported }

/// A deliberately small SemVer implementation for release tags.
///
/// GitHub release tags are an input boundary, so prerelease/build metadata is
/// rejected instead of being silently compared as a different version.
class SemanticVersion implements Comparable<SemanticVersion> {
  const SemanticVersion(this.major, this.minor, this.patch);

  factory SemanticVersion.parse(String value) {
    final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$').firstMatch(value.trim());
    if (match == null) {
      throw FormatException('Unsupported semantic version: $value');
    }
    return SemanticVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  final int major;
  final int minor;
  final int patch;

  @override
  int compareTo(SemanticVersion other) {
    final majorResult = major.compareTo(other.major);
    if (majorResult != 0) return majorResult;
    final minorResult = minor.compareTo(other.minor);
    if (minorResult != 0) return minorResult;
    return patch.compareTo(other.patch);
  }

  @override
  bool operator ==(Object other) {
    return other is SemanticVersion && compareTo(other) == 0;
  }

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

class AppVersionInfo {
  const AppVersionInfo({
    required this.version,
    required this.buildNumber,
    required this.platform,
    required this.architecture,
  });

  final String version;
  final String buildNumber;
  final SoftwareUpdatePlatform platform;
  final String architecture;

  SemanticVersion get semanticVersion => SemanticVersion.parse(version);

  String get displayVersion {
    if (buildNumber.isEmpty || buildNumber == '0') return version;
    return '$version+$buildNumber';
  }
}

class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
    required this.digest,
    this.checksumAsset,
  });

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final downloadUrl = json['browser_download_url'];
    final size = json['size'];
    final digest = json['digest'];
    if (name is! String || downloadUrl is! String || size is! int) {
      throw const FormatException('Malformed GitHub release asset.');
    }

    return ReleaseAsset(
      name: name,
      downloadUrl: Uri.tryParse(downloadUrl),
      size: size,
      digest: digest is String ? digest : null,
    );
  }

  final String name;
  final Uri? downloadUrl;
  final int size;
  final String? digest;
  final ReleaseAsset? checksumAsset;

  String? get sha256 {
    final value = digest?.trim().toLowerCase();
    if (value == null || value.isEmpty) return null;
    final normalized = value.startsWith('sha256:')
        ? value.substring('sha256:'.length)
        : value;
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized) ? normalized : null;
  }
}

class SoftwareRelease {
  const SoftwareRelease({
    required this.tagName,
    required this.version,
    required this.assets,
  });

  factory SoftwareRelease.fromJson(Map<String, dynamic> json) {
    final tagName = json['tag_name'];
    final assetsJson = json['assets'];
    if (tagName is! String || assetsJson is! List) {
      throw const FormatException('Malformed GitHub release.');
    }

    final version = SemanticVersion.parse(tagName);
    final assets = <ReleaseAsset>[];
    for (final value in assetsJson) {
      if (value is Map<String, dynamic>) {
        assets.add(ReleaseAsset.fromJson(value));
      } else if (value is Map) {
        assets.add(ReleaseAsset.fromJson(Map<String, dynamic>.from(value)));
      }
    }

    final draft = json['draft'] == true;
    final prerelease = json['prerelease'] == true;
    if (draft || prerelease) {
      throw const SoftwareUpdateException(
        UpdateFailureReason.releaseUnavailable,
        'Release is not a stable published release.',
      );
    }

    return SoftwareRelease(
      tagName: tagName,
      version: version,
      assets: List.unmodifiable(assets),
    );
  }

  final String tagName;
  final SemanticVersion version;
  final List<ReleaseAsset> assets;
}

enum UpdateStatus {
  idle,
  checking,
  upToDate,
  updateAvailable,
  unavailable,
  downloading,
  verifying,
  handingOff,
  failed,
  notSupported,
}

enum UpdateFailureReason {
  network,
  releaseUnavailable,
  assetUnavailable,
  invalidMetadata,
  download,
  integrity,
  installer,
  notSupported,
}

class DownloadProgress {
  const DownloadProgress({required this.receivedBytes, this.totalBytes});

  final int receivedBytes;
  final int? totalBytes;

  bool get hasTotal => totalBytes != null && totalBytes! > 0;

  double? get fraction {
    if (!hasTotal) return null;
    return (receivedBytes / totalBytes!).clamp(0, 1).toDouble();
  }

  int? get percentage => fraction == null ? null : (fraction! * 100).round();
}

class SoftwareUpdateException implements Exception {
  const SoftwareUpdateException(this.reason, this.message);

  final UpdateFailureReason reason;
  final String message;

  @override
  String toString() => 'SoftwareUpdateException($reason): $message';
}

class SoftwareUpdateResult {
  const SoftwareUpdateResult({
    required this.status,
    required this.current,
    this.release,
    this.asset,
    this.error,
  });

  final UpdateStatus status;
  final AppVersionInfo current;
  final SoftwareRelease? release;
  final ReleaseAsset? asset;
  final SoftwareUpdateException? error;

  bool get hasUpdate => status == UpdateStatus.updateAvailable;
}

class DownloadedUpdate {
  const DownloadedUpdate({
    required this.file,
    required this.stagingDirectory,
    required this.release,
    required this.asset,
    this.extractedDirectory,
  });

  final File file;
  final Directory stagingDirectory;
  final SoftwareRelease release;
  final ReleaseAsset asset;
  final Directory? extractedDirectory;
}

class SoftwareInstallResult {
  const SoftwareInstallResult({
    required this.started,
    this.requiresUserAction = false,
    this.message,
  });

  final bool started;
  final bool requiresUserAction;
  final String? message;
}
