import '../../models/scraped_actress_details.dart';
import '../../models/work.dart';
import '../scrape/scrape_models.dart';

class JavBusActressPage {
  const JavBusActressPage({
    required this.details,
    required this.works,
    required this.pageCount,
  });

  final ScrapedActressDetails details;
  final List<JavBusWorkSummary> works;
  final int pageCount;
}

class JavBusActressSearchResult {
  const JavBusActressSearchResult({required this.name, required this.uri});

  final String name;
  final Uri uri;
}

class JavBusWorkSummary {
  const JavBusWorkSummary({
    required this.code,
    required this.title,
    required this.detailUri,
    this.releaseDate,
    this.rawCode,
    this.catalogEvidence = const [],
  });

  final String code;
  final String? rawCode;
  final String title;
  final String? releaseDate;
  final Uri detailUri;
  final List<ScrapeCatalogWorkEvidence> catalogEvidence;
}

class JavBusWorkDetails {
  const JavBusWorkDetails({
    required this.code,
    required this.title,
    this.rawCode,
    this.releaseDate,
    this.durationMinutes,
    this.studio,
    this.publisher,
    this.series,
    this.performers,
    this.provenanceFacts = const ScrapeWorkProvenanceFacts(),
    this.actressUris = const [],
    this.originalImageEvidenceUris = const [],
    this.catalogEvidence = const [],
  });

  final String code;
  final String? rawCode;
  final String title;
  final String? releaseDate;
  final int? durationMinutes;
  final String? studio;
  final String? publisher;
  final String? series;
  final List<WorkPerformer>? performers;
  final ScrapeWorkProvenanceFacts provenanceFacts;
  final List<Uri> actressUris;
  final List<Uri> originalImageEvidenceUris;
  final List<ScrapeCatalogWorkEvidence> catalogEvidence;

  Work toWork({String? cardImagePath, String? detailImagePath}) {
    return Work(
      code: code,
      title: title,
      releaseDate: releaseDate,
      durationMinutes: durationMinutes,
      studio: studio,
      publisher: publisher,
      series: series,
      cardImagePath: cardImagePath,
      detailImagePath: detailImagePath,
    );
  }
}

enum JavBusPageIssueKind {
  verificationRequired,
  blocked,
  rateLimited,
  timeout,
  transport,
  notFound,
  parserInvalid,
  cancelled,
}

final class JavBusPageIssue {
  const JavBusPageIssue({
    required this.uri,
    required this.kind,
    required this.error,
  });

  final Uri uri;
  final JavBusPageIssueKind kind;
  final Object error;

  @override
  String toString() => 'JavBus ${kind.name}: $uri ($error)';
}

final class JavBusWorkCollectionResult {
  const JavBusWorkCollectionResult({
    required this.works,
    this.issues = const [],
  });

  final List<JavBusWorkSummary> works;
  final List<JavBusPageIssue> issues;
}
