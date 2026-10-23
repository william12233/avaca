import '../../models/scraped_actress_details.dart';
import '../../models/work.dart';
import '../scrape/scrape_models.dart';

final class AvBaseActressPage {
  const AvBaseActressPage({
    required this.details,
    this.aliases = const [],
    this.works = const [],
    this.pageCount = 1,
  });

  final ScrapedActressDetails details;
  final List<String> aliases;
  final List<AvBaseWorkSummary> works;
  final int pageCount;
}

final class AvBaseWorkSummary {
  const AvBaseWorkSummary({
    required this.code,
    required this.title,
    required this.detailUri,
    this.releaseDate,
    this.catalogEvidence = const [],
  });

  final String? code;
  final String title;
  final Uri detailUri;
  final String? releaseDate;
  final List<ScrapeCatalogWorkEvidence> catalogEvidence;
}

final class AvBaseWorkDetails {
  const AvBaseWorkDetails({
    required this.code,
    required this.title,
    this.releaseDate,
    this.durationMinutes,
    this.studio,
    this.publisher,
    this.series,
    this.performerCount,
    this.performers,
    this.provenanceFacts = const ScrapeWorkProvenanceFacts(),
    this.originalImageEvidenceUris = const [],
    this.catalogEvidence = const [],
  });

  final String code;
  final String title;
  final String? releaseDate;
  final int? durationMinutes;
  final String? studio;
  final String? publisher;
  final String? series;
  final int? performerCount;
  final List<WorkPerformer>? performers;
  final ScrapeWorkProvenanceFacts provenanceFacts;
  final List<Uri> originalImageEvidenceUris;
  final List<ScrapeCatalogWorkEvidence> catalogEvidence;
}

enum AvBaseFailureKind {
  blocked,
  rateLimited,
  timeout,
  transport,
  notFound,
  parserInvalid,
  cancelled,
  transientTransport,
}

final class AvBaseRequestException implements Exception {
  const AvBaseRequestException(
    this.uri,
    this.statusCode, {
    this.kind = AvBaseFailureKind.transport,
  });

  final Uri uri;
  final int? statusCode;
  final AvBaseFailureKind kind;

  @override
  String toString() =>
      'AvBase request failed (${statusCode ?? kind.name}): $uri';
}

final class AvBasePageLimitException implements Exception {
  const AvBasePageLimitException(this.actual, this.maximum);

  final int actual;
  final int maximum;

  @override
  String toString() => 'AvBase page count $actual exceeds limit $maximum.';
}

final class AvBasePageIssue {
  const AvBasePageIssue({
    required this.uri,
    required this.kind,
    required this.error,
  });

  final Uri uri;
  final AvBaseFailureKind kind;
  final Object error;

  @override
  String toString() => 'AvBase ${kind.name}: $uri ($error)';
}

final class AvBaseWorkCollectionResult {
  const AvBaseWorkCollectionResult({
    required this.works,
    this.issues = const [],
  });

  final List<AvBaseWorkSummary> works;
  final List<AvBasePageIssue> issues;
}
