import '../../models/scraped_actress_details.dart';
import '../../models/work.dart';
import '../scrape/scrape_models.dart';

final class AvWikiActressPage {
  const AvWikiActressPage({
    required this.details,
    this.aliases = const [],
    this.works = const [],
    this.pageCount = 1,
  });

  final ScrapedActressDetails details;
  final List<String> aliases;
  final List<AvWikiWorkSummary> works;
  final int pageCount;
}

final class AvWikiWorkSummary {
  const AvWikiWorkSummary({
    required this.code,
    this.rawCode,
    required this.title,
    required this.detailUri,
    this.releaseDate,
    this.externalIdentity,
    this.catalogEvidence = const [],
  });

  final String? code;
  final String? rawCode;
  final String title;
  final Uri detailUri;
  final String? releaseDate;
  final ScrapeExternalWorkIdentity? externalIdentity;
  final List<ScrapeCatalogWorkEvidence> catalogEvidence;
}

final class AvWikiWorkDetails {
  const AvWikiWorkDetails({
    required this.code,
    this.rawCode,
    required this.title,
    this.releaseDate,
    this.studio,
    this.publisher,
    this.series,
    this.performerCount,
    this.performers,
    this.description,
    this.genres = const [],
    this.provenanceFacts = const ScrapeWorkProvenanceFacts(),
    this.externalIdentity,
    this.catalogEvidence = const [],
  });

  final String code;
  final String? rawCode;
  final String title;
  final String? releaseDate;
  final String? studio;
  final String? publisher;
  final String? series;
  final int? performerCount;
  final List<WorkPerformer>? performers;
  final String? description;
  final List<String> genres;
  final ScrapeWorkProvenanceFacts provenanceFacts;
  final ScrapeExternalWorkIdentity? externalIdentity;
  final List<ScrapeCatalogWorkEvidence> catalogEvidence;
}

enum AvWikiFailureKind {
  blocked,
  rateLimited,
  timeout,
  transport,
  notFound,
  parserInvalid,
  cancelled,
  transientTransport,
}

final class AvWikiRequestException implements Exception {
  const AvWikiRequestException(
    this.uri,
    this.statusCode, {
    this.kind = AvWikiFailureKind.transport,
  });

  final Uri uri;
  final int? statusCode;
  final AvWikiFailureKind kind;

  @override
  String toString() =>
      'AV-Wiki request failed (${statusCode ?? kind.name}): $uri';
}

final class AvWikiPageLimitException implements Exception {
  const AvWikiPageLimitException(this.actual, this.maximum);

  final int actual;
  final int maximum;

  @override
  String toString() => 'AV-Wiki page count $actual exceeds limit $maximum.';
}

final class AvWikiPageIssue {
  const AvWikiPageIssue({
    required this.uri,
    required this.kind,
    required this.error,
  });

  final Uri uri;
  final AvWikiFailureKind kind;
  final Object error;

  @override
  String toString() => 'AV-Wiki ${kind.name}: $uri ($error)';
}

final class AvWikiWorkCollectionResult {
  const AvWikiWorkCollectionResult({
    required this.works,
    this.issues = const [],
  });

  final List<AvWikiWorkSummary> works;
  final List<AvWikiPageIssue> issues;
}
