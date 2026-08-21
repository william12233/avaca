enum WorkImagePlatform { dmm, mgstage }

enum WorkImageNormalizationFamily {
  dmmStandard,
  dmmLeadingOne,
  dmmH1711,
  dmmRebeccaH346,
  mgstagePrestige,
  mgstageSeikyouiku,
}

/// Stable, metadata-independent order used for the first probe of an unknown
/// Prefix.  Keep this list centralized so downloader, import/export, and
/// Settings do not accidentally develop different family orders.
const workImageDefaultProbeOrder = <WorkImageNormalizationFamily>[
  WorkImageNormalizationFamily.dmmStandard,
  WorkImageNormalizationFamily.dmmLeadingOne,
  WorkImageNormalizationFamily.dmmH1711,
  WorkImageNormalizationFamily.dmmRebeccaH346,
  WorkImageNormalizationFamily.mgstagePrestige,
  WorkImageNormalizationFamily.mgstageSeikyouiku,
];

/// Prefixes whose DMM digital-video token is known from the product family,
/// even before a per-prefix route has been learned. Keeping these hints ahead
/// of the generic probe order prevents a valid-looking generic route from
/// winning before the family-specific token is tried.
const workImagePrefixFamilyHints = <String, WorkImageNormalizationFamily>{
  'START': WorkImageNormalizationFamily.dmmLeadingOne,
  'STARS': WorkImageNormalizationFamily.dmmLeadingOne,
};

String workImageNormalizationFamilyName(WorkImageNormalizationFamily family) =>
    family.name;

WorkImageNormalizationFamily? workImageNormalizationFamilyFromName(
  String? value,
) {
  for (final family in WorkImageNormalizationFamily.values) {
    if (family.name == value) {
      return family;
    }
  }
  return null;
}

enum WorkImageRouteFailureReason {
  metadataMissing,
  metadataUnmapped,
  metadataAmbiguous,
  metadataConflict,
}

final class WorkImageRouteResolution {
  const WorkImageRouteResolution.resolved({
    required this.platform,
    required this.family,
  }) : failureReason = null;

  const WorkImageRouteResolution.unclassified(this.failureReason)
    : platform = null,
      family = null;

  final WorkImagePlatform? platform;
  final WorkImageNormalizationFamily? family;
  final WorkImageRouteFailureReason? failureReason;

  bool get isResolved => platform != null && family != null;
}

final class WorkImageRouteException implements Exception {
  const WorkImageRouteException(this.code, this.reason);

  final String code;
  final WorkImageRouteFailureReason reason;

  @override
  String toString() =>
      'Work image route is unclassified for $code: ${reason.name}';
}

/// Resolves the image platform from verified producer/label identity.
///
/// A work-code prefix is deliberately absent from this decision. It is only
/// used later by WorkImagePolicy to format the token after a route is known.
final class WorkImageRouteResolver {
  const WorkImageRouteResolver();

  WorkImageRouteResolution resolve({String? studio, String? publisher}) {
    final makerCandidates = _candidatesFor(studio, publisher: false);
    final publisherCandidates = _candidatesFor(publisher, publisher: true);
    Set<_RouteCandidate> candidates;
    if (makerCandidates.isNotEmpty && publisherCandidates.isNotEmpty) {
      candidates = makerCandidates.intersection(publisherCandidates);
      if (candidates.isEmpty) {
        return const WorkImageRouteResolution.unclassified(
          WorkImageRouteFailureReason.metadataConflict,
        );
      }
    } else if (makerCandidates.isNotEmpty) {
      candidates = makerCandidates;
    } else if (publisherCandidates.isNotEmpty) {
      candidates = publisherCandidates;
    } else if (_hasIdentity(studio) || _hasIdentity(publisher)) {
      return const WorkImageRouteResolution.unclassified(
        WorkImageRouteFailureReason.metadataUnmapped,
      );
    } else {
      return const WorkImageRouteResolution.unclassified(
        WorkImageRouteFailureReason.metadataMissing,
      );
    }

    if (candidates.length != 1) {
      return const WorkImageRouteResolution.unclassified(
        WorkImageRouteFailureReason.metadataAmbiguous,
      );
    }

    final selected = candidates.single;
    return WorkImageRouteResolution.resolved(
      platform: selected.platform,
      family: selected.family,
    );
  }

  Set<_RouteCandidate> _candidatesFor(
    String? value, {
    required bool publisher,
  }) {
    final normalized = _normalize(value);
    if (normalized.isEmpty) {
      return <_RouteCandidate>{};
    }

    if (_s1Aliases.contains(normalized) ||
        _standardDmmAliases.contains(normalized)) {
      return {_RouteCandidate.dmmStandard};
    }
    if (_leadingOneAliases.contains(normalized)) {
      return {_RouteCandidate.dmmLeadingOne};
    }
    if (_seikyouikuAliases.contains(normalized)) {
      return {_RouteCandidate.mgstageSeikyouiku};
    }
    if (_prestigeAliases.contains(normalized)) {
      return {_RouteCandidate.mgstagePrestige};
    }
    if (_rebeccaAliases.contains(normalized)) {
      return {_RouteCandidate.dmmRebeccaH346};
    }
    if (_h1711Aliases.contains(normalized)) {
      return {_RouteCandidate.dmmH1711};
    }

    // JavBus is a commonly observed publisher but is intentionally not a
    // route rule: it spans DMM and MGStage families.
    if (publisher && normalized == 'javbus') {
      return <_RouteCandidate>{};
    }
    return <_RouteCandidate>{};
  }

  bool _hasIdentity(String? value) => _normalize(value).isNotEmpty;

  String _normalize(String? value) {
    return (value ?? '').trim().toLowerCase().replaceAll(
      RegExp(r'[\s\-_.／/（）(),，、&]+'),
      '',
    );
  }
}

final class _RouteCandidate {
  const _RouteCandidate(this.platform, this.family);

  static const dmmStandard = _RouteCandidate(
    WorkImagePlatform.dmm,
    WorkImageNormalizationFamily.dmmStandard,
  );
  static const dmmH1711 = _RouteCandidate(
    WorkImagePlatform.dmm,
    WorkImageNormalizationFamily.dmmH1711,
  );
  static const dmmLeadingOne = _RouteCandidate(
    WorkImagePlatform.dmm,
    WorkImageNormalizationFamily.dmmLeadingOne,
  );
  static const dmmRebeccaH346 = _RouteCandidate(
    WorkImagePlatform.dmm,
    WorkImageNormalizationFamily.dmmRebeccaH346,
  );
  static const mgstagePrestige = _RouteCandidate(
    WorkImagePlatform.mgstage,
    WorkImageNormalizationFamily.mgstagePrestige,
  );
  static const mgstageSeikyouiku = _RouteCandidate(
    WorkImagePlatform.mgstage,
    WorkImageNormalizationFamily.mgstageSeikyouiku,
  );

  final WorkImagePlatform platform;
  final WorkImageNormalizationFamily family;

  @override
  bool operator ==(Object other) =>
      other is _RouteCandidate &&
      other.platform == platform &&
      other.family == family;

  @override
  int get hashCode => Object.hash(platform, family);
}

const _s1Aliases = <String>{'s1', 's1no1style', 'エスワン', 'エスワンナンバーワンスタイル'};

const _leadingOneAliases = <String>{'sod', 'sodcreate', 'sodstar', 'sodクリエイト'};

const _seikyouikuAliases = <String>{'seikyouiku', 'セイキョウイク'};

const _prestigeAliases = <String>{'prestige', 'プレステージ'};

const _rebeccaAliases = <String>{'rebecca', 'レベッカ', 'rebeccapremium'};

const _h1711Aliases = <String>{'document', 'ドキュメント', 'documentary'};

const _standardDmmAliases = <String>{
  'ideaポケット',
  'ideapocket',
  'アイデアポケット',
  'aircontrol',
  'エアコントロール',
  'crystal',
  'クリスタル映像',
  'crystalnext',
  'eキス',
  'ekiss',
  'million',
  'ミリオン',
  'ケイエムプロデュース',
  'bazooka',
  'バズーカ',
  'royal',
  'ロイヤル',
  'hhhグループ',
  'アタッカーズ',
  '大人のドラマ',
  'realworks',
  'レアルワークス',
  'real',
  'sodクリエイト',

  // Verified 0.8.7 publisher identities. Values in this set are stored in
  // the same normalized form produced by _normalize above.
  'オーロラプロジェクト・アネックス',
  'バビロン妄想族',
  'ビビアン',
  'wanz',
  'kawaii',
  'ピーターズ',
  'crystalvr',
  'ダスッ！',
  'docdream',
  'アリスjapan',
  'flavors',
  'deep’s',
  'ebody',
  'falenostar',
  'ふぇちぽいんと',
  'focus',
  'ultima',
  '本中',
  'hmpdorama',
  '初代渋谷特別特攻本部',
  'ienf',
  'iene',
  'iesp',
  'fitch',
  'madonna',
  'かぐや姫pt',
  'ktribe',
  '黒髪美少女',
  'ルナティックス',
  'マゾマン',
  '宇宙企画',
  '溜池ゴロー',
  'みんなのキカタン',
  'moodyzbest',
  'millionミリオン',
  'ミコン',
  'iris',
  'mcp',
  '無垢',
  'm’svideogroup',
  'maxing',
  '七狗留',
  'onez',
  'onetime',
  'gloryquest',
  'パコパコ団とゆかいな仲間たち妄想族',
  'oppai',
  'scute',
  '羞恥娘',
  'tma',
  '円光タダまん',
  'leo',
  'umanami',
  'まるっと！',
  'ゾクゾク娘',

  // The same DMM-standard route is also selected from the verified studio
  // identities, including all three blank-publisher works.
  'ワンズファクトリー',
  'doc',
  'ディープス',
  'エロタイム',
  'faleno',
  'abc妄想族',
  'venus',
  'マーキュリー',
  'アイエナジー',
  'マドンナ',
  'かぐや姫pt妄想族',
  'ケー・トライブ',
  'メディアアーツ',
  'lunatics',
  'ムーディーズ',
  'ケイ・エム・プロデュース',
  'marrion',
  'エムズビデオグループ',
  'プラネットプラス',
  'onemore',
  'グローリークエスト',
  '素人clover',
  'サディスティックヴィレッジ',
  'firststar',
  'ゾクゾク娘妄想族',
  'サディヴィレナウ！',
};
