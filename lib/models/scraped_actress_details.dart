class ScrapedActressDetails {
  const ScrapedActressDetails({
    this.name,
    this.imagePath,
    this.avatarUrl,
    this.birthDate,
    this.height,
    this.cup,
    this.bust,
    this.waist,
    this.hip,
  });

  final String? name;
  final String? imagePath;
  final Uri? avatarUrl;
  final String? birthDate;
  final String? height;
  final String? cup;
  final String? bust;
  final String? waist;
  final String? hip;

  String? get bwh {
    final values = [bust, waist, hip].map(_clean).toList();
    if (values.every((value) => value == null)) {
      return null;
    }
    return 'B${values[0] ?? ''} / W${values[1] ?? ''} / H${values[2] ?? ''}';
  }

  static String? _clean(String? value) {
    final cleaned = value?.trim();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }
}
