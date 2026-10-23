import '../../models/scraped_actress_details.dart';

final class MinnanoActressPage {
  const MinnanoActressPage({
    required this.details,
    this.aliases = const [],
    this.works = const [],
    this.pageCount = 1,
  });

  final ScrapedActressDetails details;
  final List<String> aliases;
  final List<MinnanoWorkSummary> works;
  final int pageCount;
}

final class MinnanoWorkSummary {
  const MinnanoWorkSummary({
    required this.code,
    required this.title,
    required this.detailUri,
    this.releaseDate,
    this.imageUri,
  });

  final String? code;
  final String title;
  final Uri detailUri;
  final String? releaseDate;
  final Uri? imageUri;
}

final class MinnanoWorkDetails {
  const MinnanoWorkDetails({
    required this.code,
    required this.title,
    this.releaseDate,
    this.studio,
    this.publisher,
    this.performerCount,
    this.imageUris = const [],
  });

  final String? code;
  final String title;
  final String? releaseDate;
  final String? studio;
  final String? publisher;
  final int? performerCount;
  final List<Uri> imageUris;
}
