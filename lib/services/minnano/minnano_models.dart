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
    this.publisher,
  });

  final String? code;
  final String title;
  final Uri detailUri;
  final String? releaseDate;
  final Uri? imageUri;

  /// The maker/label printed on the actress work list, when available.
  final String? publisher;
}

final class MinnanoActressTag {
  const MinnanoActressTag({
    required this.key,
    required this.label,
    required this.uri,
    this.count,
  });

  final String key;
  final String label;
  final Uri uri;
  final int? count;
}

final class MinnanoActressListItem {
  const MinnanoActressListItem({
    required this.name,
    required this.uri,
    this.imageUri,
    this.tags = const [],
  });

  final String name;
  final Uri uri;
  final Uri? imageUri;
  final List<String> tags;
}

/// One entry from Minnano's source-native actress ranking page.
final class MinnanoActressRankingItem {
  const MinnanoActressRankingItem({
    required this.rank,
    required this.name,
    required this.uri,
    this.imageUri,
  });

  final int rank;
  final String name;
  final Uri uri;
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
