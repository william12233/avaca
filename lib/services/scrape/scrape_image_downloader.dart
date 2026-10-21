import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as image;

import '../safe_image.dart';
import '../javbus/work_image_downloader.dart';

abstract interface class ScrapeImageUriDownloader {
  Future<String> download({required Uri uri, required String targetPath});

  void close();
}

final class HttpScrapeImageUriDownloader implements ScrapeImageUriDownloader {
  HttpScrapeImageUriDownloader({
    required bool Function(Uri uri) isAllowed,
    BinaryTransport? transport,
  }) : _isAllowed = isAllowed,
       _transport = transport ?? HttpBinaryTransport();

  final bool Function(Uri uri) _isAllowed;
  final BinaryTransport _transport;

  @override
  Future<String> download({
    required Uri uri,
    required String targetPath,
  }) async {
    if (!_isAllowed(uri)) {
      throw ScrapeImageDownloadException(uri);
    }
    final response = await _transport.get(uri);
    if (!_isValid(response)) {
      throw ScrapeImageDownloadException(uri);
    }
    final file = File(targetPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(response.bodyBytes, flush: true);
    return targetPath;
  }

  @override
  void close() {
    final transport = _transport;
    if (transport is HttpBinaryTransport) {
      transport.close();
    }
  }

  bool _isValid(BinaryResponse response) {
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        response.bodyBytes.isEmpty) {
      return false;
    }
    final bytes = Uint8List.fromList(response.bodyBytes);
    if (!isSafeDecodableImage(bytes)) {
      return false;
    }
    final decoder = image.findDecoderForData(bytes);
    return decoder != null && decoder.startDecode(bytes) != null;
  }
}

final class ScrapeImageDownloadException implements Exception {
  const ScrapeImageDownloadException(this.uri);

  final Uri uri;

  @override
  String toString() => 'Could not download a valid scrape image: $uri';
}
