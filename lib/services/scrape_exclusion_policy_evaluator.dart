import '../models/scrape_exclusion_policy.dart';
import '../models/scrape_source_settings.dart';
import 'scrape/scrape_models.dart';
import 'scrape/provenance_semantics.dart';
import 'scrape/scrape_classification_context.dart';
import 'scrape/scrape_product_family_registry.dart';

class ScrapeEvidenceAtom {
  const ScrapeEvidenceAtom({
    required this.id,
    required this.surfaceId,
    required this.source,
    required this.field,
    required this.kind,
    required this.strength,
    required this.polarity,
    required this.ruleId,
    required this.observedText,
  });

  final String id;
  final String surfaceId;
  final ScrapeSourceId source;
  final String field;
  final ScrapeEvidenceKind kind;
  final ScrapeEvidenceStrength strength;
  final ScrapeEvidencePolarity polarity;
  final String ruleId;
  final String observedText;

  Map<String, Object?> toJson() => {
    'id': id,
    'surfaceId': surfaceId,
    'source': source.storageValue,
    'field': field,
    'kind': kind.name,
    'strength': strength.name,
    'polarity': polarity.name,
    'ruleId': ruleId,
    'observedText': observedText,
  };
}

class ScrapePolicyMatch {
  const ScrapePolicyMatch({
    required this.id,
    required this.type,
    required this.ruleId,
    required this.origin,
    this.matchedValue,
  });

  final String id;
  final String type;
  final String ruleId;
  final ScrapePolicyOrigin origin;
  final String? matchedValue;

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type,
    'ruleId': ruleId,
    'origin': origin.storageValue,
    if (matchedValue != null) 'matchedValue': matchedValue,
  };
}

class ScrapePolicyDecision {
  const ScrapePolicyDecision({
    required this.finalAction,
    required this.resolutionState,
    required this.provenanceClass,
    required this.evidenceLevel,
    required this.reasonCodes,
    required this.evidence,
    required this.policyMatches,
    required this.hasConflict,
    required this.snapshotDigest,
  });

  final ScrapeFinalAction finalAction;
  final ScrapeResolutionState resolutionState;
  final ScrapeProvenanceClass provenanceClass;
  final ScrapeEvidenceLevel evidenceLevel;
  final List<String> reasonCodes;
  final List<ScrapeEvidenceAtom> evidence;
  final List<ScrapePolicyMatch> policyMatches;
  final bool hasConflict;
  final String snapshotDigest;

  bool get reviewRequired =>
      resolutionState == ScrapeResolutionState.finalReview;

  ScrapeProvenanceVerdict get verdict => switch (finalAction) {
    ScrapeFinalAction.keep => ScrapeProvenanceVerdict.keep,
    ScrapeFinalAction.exclude => ScrapeProvenanceVerdict.exclude,
    ScrapeFinalAction.keepReview => ScrapeProvenanceVerdict.keepUncertain,
  };

  String get reason => reasonCodes.join(',');

  Map<String, Object?> toJson() => {
    'finalAction': finalAction.name,
    'resolutionState': resolutionState.name,
    'provenanceClass': provenanceClass.name,
    'evidenceLevel': evidenceLevel.name,
    'reasonCodes': reasonCodes,
    'evidence': evidence.map((item) => item.toJson()).toList(),
    'policyMatches': policyMatches.map((item) => item.toJson()).toList(),
    'hasConflict': hasConflict,
    'snapshotDigest': snapshotDigest,
    'reviewRequired': reviewRequired,
  };
}

/// Classifies work provenance from concrete lineage and production facts.
///
/// Prefixes and performer counts are intentionally not part of the automatic
/// decision. Suspicion-only facts remain provisional while another enabled
/// source can still provide evidence; only exhausted unresolved suspicion is
/// surfaced as [ScrapeFinalAction.keepReview].
class ScrapeExclusionPolicyEvaluator {
  ScrapeExclusionPolicyEvaluator(this.snapshot);

  final ScrapePolicySnapshot snapshot;

  ScrapePolicyDecision evaluate({
    required String code,
    required List<ScrapeWorkDetails> details,
    ScrapeClassificationContext? classificationContext,
    bool evidenceExhausted = true,
  }) {
    final surfaces = details.isEmpty
        ? <_PolicySurface>[
            _PolicySurface(
              id: 'unknown:$code',
              source: ScrapeSourceId.javbus,
              code: code,
              details: null,
            ),
          ]
        : [
            for (var index = 0; index < details.length; index++) ...[
              _PolicySurface.fromDetails(details[index], index),
              for (
                var evidenceIndex = 0;
                evidenceIndex < details[index].catalogEvidence.length;
                evidenceIndex++
              )
                _PolicySurface.fromCatalogEvidence(
                  details[index].catalogEvidence[evidenceIndex],
                  code: details[index].rawCode ?? details[index].code,
                  title: details[index].title,
                  index: index,
                  evidenceIndex: evidenceIndex,
                ),
            ],
          ];
    final evidence = <ScrapeEvidenceAtom>[];
    final policyMatches = <ScrapePolicyMatch>[];
    var evidenceOrdinal = 0;

    void addEvidence({
      required _PolicySurface surface,
      required String field,
      required ScrapeEvidenceKind kind,
      required ScrapeEvidenceStrength strength,
      required ScrapeEvidencePolarity polarity,
      required String ruleId,
      required String observedText,
    }) {
      evidence.add(
        ScrapeEvidenceAtom(
          id: 'e${evidenceOrdinal++}',
          surfaceId: surface.id,
          source: surface.source,
          field: field,
          kind: kind,
          strength: strength,
          polarity: polarity,
          ruleId: ruleId,
          observedText: _excerpt(observedText),
        ),
      );
    }

    for (final surface in surfaces) {
      _classifySurface(
        surface,
        addEvidence,
        classificationContext: classificationContext,
      );
    }

    final strongCompilation = evidence.any(
      (item) =>
          item.strength == ScrapeEvidenceStrength.strong &&
          item.polarity == ScrapeEvidencePolarity.supportsCompilation,
    );
    final strongOriginal = evidence.any(
      (item) =>
          item.strength == ScrapeEvidenceStrength.strong &&
          item.polarity == ScrapeEvidencePolarity.supportsOriginalWork,
    );
    final hasReviewEvidence = evidence.any(
      (item) => item.strength != ScrapeEvidenceStrength.weak,
    );
    final hasConflict = strongCompilation && strongOriginal;
    final automaticClass = _classForEvidence(evidence, surfaces);

    var automaticAction = ScrapeFinalAction.keep;
    var automaticState = ScrapeResolutionState.decisiveKeep;
    var automaticReasons = <String>['no_reuse_signal'];
    var automaticLevel = ScrapeEvidenceLevel.none;
    if (hasConflict) {
      automaticAction = evidenceExhausted
          ? ScrapeFinalAction.keepReview
          : ScrapeFinalAction.keep;
      automaticState = evidenceExhausted
          ? ScrapeResolutionState.finalReview
          : ScrapeResolutionState.conflict;
      automaticReasons = ['source_provenance_conflict'];
      automaticLevel = ScrapeEvidenceLevel.strong;
    } else if (strongCompilation) {
      automaticAction = snapshot.autoExcludeDerivedWorks
          ? ScrapeFinalAction.exclude
          : ScrapeFinalAction.keepReview;
      automaticState = snapshot.autoExcludeDerivedWorks
          ? ScrapeResolutionState.decisiveExclude
          : ScrapeResolutionState.finalReview;
      automaticReasons = [
        if (snapshot.autoExcludeDerivedWorks)
          'strong_compilation_evidence'
        else
          'derived_work_filter_disabled',
      ];
      automaticLevel = ScrapeEvidenceLevel.strong;
    } else if (strongOriginal) {
      automaticAction = ScrapeFinalAction.keep;
      automaticState = ScrapeResolutionState.decisiveKeep;
      automaticReasons = const ['explicit_original_work'];
      automaticLevel = ScrapeEvidenceLevel.strong;
    } else if (evidence.any(
      (item) => item.kind == ScrapeEvidenceKind.viewpointSelection,
    )) {
      automaticAction = ScrapeFinalAction.keep;
      automaticState = ScrapeResolutionState.decisiveKeep;
      automaticReasons = const ['safe_presentation_context'];
      automaticLevel = ScrapeEvidenceLevel.none;
    } else if (hasReviewEvidence) {
      automaticAction = evidenceExhausted
          ? ScrapeFinalAction.keepReview
          : ScrapeFinalAction.keep;
      automaticState = evidenceExhausted
          ? ScrapeResolutionState.finalReview
          : ScrapeResolutionState.needsEvidence;
      automaticReasons = [_unresolvedReason(evidence)];
      automaticLevel = ScrapeEvidenceLevel.review;
    }

    final exactAllows = _exactAllowsFor(surfaces);
    final exactDenies = _exactDeniesFor(surfaces);
    for (final exactRule in exactAllows) {
      policyMatches.add(
        ScrapePolicyMatch(
          id: 'm${policyMatches.length}',
          type: 'exactAllow',
          ruleId: 'exact_allow',
          origin: ScrapePolicyOrigin.user,
          matchedValue: exactRule.code,
        ),
      );
    }
    for (final exactRule in exactDenies) {
      policyMatches.add(
        ScrapePolicyMatch(
          id: 'm${policyMatches.length}',
          type: 'exactDeny',
          ruleId: 'exact_deny',
          origin: ScrapePolicyOrigin.user,
          matchedValue: exactRule.code,
        ),
      );
    }

    // Explicit manual rules are deliberately applied after automatic
    // classification. Conflicting manual rules fail open to review.
    final allSurfacesAllowed =
        exactAllows.isNotEmpty &&
        surfaces.every(
          (surface) => exactAllows.any(
            (rule) => rule.matches(
              surface.code,
              sourceId: surface.source.storageValue,
            ),
          ),
        );
    final allSurfacesDenied =
        exactDenies.isNotEmpty &&
        surfaces.every(
          (surface) => exactDenies.any(
            (rule) => rule.matches(
              surface.code,
              sourceId: surface.source.storageValue,
            ),
          ),
        );
    if (allSurfacesAllowed && allSurfacesDenied) {
      return _decision(
        action: ScrapeFinalAction.keepReview,
        resolutionState: ScrapeResolutionState.finalReview,
        classValue: ScrapeProvenanceClass.unknown,
        level: ScrapeEvidenceLevel.strong,
        reasons: const ['manual_override_conflict'],
        evidence: evidence,
        matches: policyMatches,
        hasConflict: true,
      );
    }
    if (allSurfacesAllowed) {
      return _decision(
        action: ScrapeFinalAction.keep,
        resolutionState: ScrapeResolutionState.decisiveKeep,
        classValue: automaticClass,
        level: automaticLevel,
        reasons: const ['exact_allow'],
        evidence: evidence,
        matches: policyMatches,
      );
    }
    if (allSurfacesDenied) {
      return _decision(
        action: ScrapeFinalAction.exclude,
        resolutionState: ScrapeResolutionState.decisiveExclude,
        classValue: automaticClass,
        level: automaticLevel,
        reasons: const ['exact_deny'],
        evidence: evidence,
        matches: policyMatches,
      );
    }
    if (exactAllows.isNotEmpty || exactDenies.isNotEmpty) {
      automaticAction = ScrapeFinalAction.keepReview;
      automaticState = ScrapeResolutionState.finalReview;
      automaticReasons = const ['manual_rule_scope_uncertain'];
      automaticLevel = ScrapeEvidenceLevel.review;
    }

    return _decision(
      action: automaticAction,
      resolutionState: automaticState,
      classValue: automaticClass,
      level: automaticLevel,
      reasons: automaticReasons,
      evidence: evidence,
      matches: policyMatches,
      hasConflict: hasConflict,
    );
  }

  ScrapePolicyDecision _decision({
    required ScrapeFinalAction action,
    required ScrapeResolutionState resolutionState,
    required ScrapeProvenanceClass classValue,
    required ScrapeEvidenceLevel level,
    required List<String> reasons,
    required List<ScrapeEvidenceAtom> evidence,
    required List<ScrapePolicyMatch> matches,
    bool hasConflict = false,
  }) {
    return ScrapePolicyDecision(
      finalAction: action,
      resolutionState: resolutionState,
      provenanceClass: classValue,
      evidenceLevel: level,
      reasonCodes: List.unmodifiable(reasons),
      evidence: List.unmodifiable(evidence),
      policyMatches: List.unmodifiable(matches),
      hasConflict: hasConflict,
      snapshotDigest: snapshot.snapshotDigest,
    );
  }

  String _unresolvedReason(List<ScrapeEvidenceAtom> evidence) {
    if (evidence.any(
      (item) => item.kind == ScrapeEvidenceKind.productFamilySuspicion,
    )) {
      return 'reuse_family_unresolved';
    }
    if (evidence.any(
      (item) => item.kind == ScrapeEvidenceKind.highVolumePresentation,
    )) {
      return 'lineage_incomplete';
    }
    return 'reuse_signal_unresolved';
  }

  List<ScrapeExactAllowRule> _exactAllowsFor(List<_PolicySurface> surfaces) {
    return snapshot.exactAllows
        .where(
          (rule) => surfaces.any(
            (surface) => rule.matches(
              surface.code,
              sourceId: surface.source.storageValue,
            ),
          ),
        )
        .toList(growable: false);
  }

  List<ScrapeExactDenyRule> _exactDeniesFor(List<_PolicySurface> surfaces) {
    return snapshot.exactDenies
        .where(
          (rule) => surfaces.any(
            (surface) => rule.matches(
              surface.code,
              sourceId: surface.source.storageValue,
            ),
          ),
        )
        .toList(growable: false);
  }

  void _classifySurface(
    _PolicySurface surface,
    void Function({
      required _PolicySurface surface,
      required String field,
      required ScrapeEvidenceKind kind,
      required ScrapeEvidenceStrength strength,
      required ScrapeEvidencePolarity polarity,
      required String ruleId,
      required String observedText,
    })
    addEvidence, {
    ScrapeClassificationContext? classificationContext,
  }) {
    final details = surface.details;
    final catalog = surface.catalogEvidence;
    if (details == null && catalog == null) return;
    final facts = details?.provenanceFacts ?? const ScrapeWorkProvenanceFacts();
    final includedWorks = [
      ...?details?.includedWorks,
      ...facts.includedWorks,
      ...?catalog?.includedCodes,
    ].where((value) => value.trim().isNotEmpty).toSet();
    final parentWorks = [
      ...?details?.parentWorks,
      ...facts.parentWorks,
      ...?catalog?.parentCodes,
    ].where((value) => value.trim().isNotEmpty).toSet();
    final genres = [
      ...?details?.genres,
      ...facts.genres,
      ...facts.tags,
      ...?catalog?.tags,
    ];
    final title = details?.title ?? catalog?.title ?? '';
    final series = details?.series ?? catalog?.series;
    final description = details?.description ?? catalog?.description;
    final text = [
      title,
      series ?? '',
      description ?? '',
      facts.description ?? '',
      ...genres,
      ...?catalog?.provenanceHints,
    ].join(' ').trim();
    var hasStrongDerivedSurfaceEvidence = false;

    void strong({
      required ScrapeEvidenceKind kind,
      required ScrapeEvidencePolarity polarity,
      required String ruleId,
      required String observedText,
      String field = 'provenance',
    }) {
      if (polarity == ScrapeEvidencePolarity.supportsCompilation) {
        hasStrongDerivedSurfaceEvidence = true;
      }
      addEvidence(
        surface: surface,
        field: field,
        kind: kind,
        strength: ScrapeEvidenceStrength.strong,
        polarity: polarity,
        ruleId: ruleId,
        observedText: observedText,
      );
    }

    if (includedWorks.isNotEmpty || facts.containsPriorWorks == true) {
      strong(
        kind: ScrapeEvidenceKind.includedPriorWorks,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: 'lineage_includes_prior_works',
        observedText: includedWorks.isEmpty
            ? 'source says prior works are included'
            : includedWorks.join(', '),
      );
    }
    if (parentWorks.isNotEmpty || facts.extractedFromPriorWork == true) {
      strong(
        kind: ScrapeEvidenceKind.extractedFromPriorWork,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: 'lineage_parent_work',
        observedText: parentWorks.isEmpty
            ? 'source says extracted from a parent work'
            : parentWorks.join(', '),
      );
    }
    if (facts.splitFromPriorWork == true) {
      strong(
        kind: ScrapeEvidenceKind.splitFromPriorWork,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: 'lineage_split_from_prior_work',
        observedText: 'split or individual-performer edition',
      );
    }
    if (facts.splitFromPriorWork != true &&
        ScrapeProvenanceSemantics.containsStrongSplitEvidence(text)) {
      strong(
        kind: ScrapeEvidenceKind.splitFromPriorWork,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: 'semantic_split_from_prior_work',
        observedText: 'source wording identifies a split or individual edition',
        field: 'title_or_metadata',
      );
    }
    if (facts.packageOfPriorWorks == true) {
      strong(
        kind: ScrapeEvidenceKind.packageEdition,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: 'lineage_prior_work_package',
        observedText: 'prior works packaged together',
      );
    }
    if (facts.reusedIndependentSegments == true) {
      strong(
        kind: ScrapeEvidenceKind.includedPriorWorks,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: 'lineage_reused_independent_segments',
        observedText: 'independent segments reuse prior works',
      );
    }
    if (facts.oldMaterialWithNewBonus == true) {
      strong(
        kind: ScrapeEvidenceKind.mixedOldNew,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: 'lineage_old_material_bonus',
        observedText: 'old material with new bonus footage',
      );
    }
    if (facts.reissue == true) {
      strong(
        kind: ScrapeEvidenceKind.reissue,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: 'lineage_reissue',
        observedText: 'reissue or revival of an existing work',
      );
    }
    if (facts.remaster == true) {
      strong(
        kind: ScrapeEvidenceKind.remaster,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: 'lineage_remaster',
        observedText: 'remaster of an existing work',
      );
    }
    if (facts.reedited == true) {
      strong(
        kind: ScrapeEvidenceKind.reedit,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: 'lineage_reedit',
        observedText: 're-edit of an existing work',
      );
    }
    if (facts.coPerformance == ScrapeCoPerformance.independentSegments ||
        details?.coPerformance == ScrapeCoPerformance.independentSegments) {
      // Multiple independent segments are not the same as reusing prior
      // works. Keep the fact as neutral context for diagnostics, but never
      // promote it to compilation evidence on its own.
      addEvidence(
        surface: surface,
        field: 'production',
        kind: ScrapeEvidenceKind.independentSegments,
        strength: ScrapeEvidenceStrength.weak,
        polarity: ScrapeEvidencePolarity.neutral,
        ruleId: 'production_independent_segments',
        observedText: 'independent performer segments',
      );
    }

    final compilation = ScrapeProvenanceSemantics.explicitCompilationLabel(
      text,
    );
    if (compilation != null) {
      strong(
        kind: compilation.contains('オムニバス')
            ? ScrapeEvidenceKind.omnibus
            : ScrapeEvidenceKind.explicitCompilation,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: 'semantic_compilation_label',
        observedText: compilation,
        field: 'title_or_metadata',
      );
    }

    final reuseProposition = ScrapeProvenanceSemantics.strongReuseProposition([
      text,
      ...facts.tags,
    ]);
    if (reuseProposition != null) {
      strong(
        kind:
            reuseProposition.ruleId == 'semantic_best_collection' ||
                reuseProposition.observedText.toLowerCase().contains(
                  'complete',
                ) ||
                reuseProposition.observedText.contains('コンプリート')
            ? ScrapeEvidenceKind.completePriorWorks
            : ScrapeEvidenceKind.bestOfPriorWorks,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: reuseProposition.ruleId,
        observedText: reuseProposition.observedText,
        field: 'title_or_metadata',
      );
    }
    if (reuseProposition == null &&
        ScrapeProvenanceSemantics.containsExplicitPriorWorkStatement(text)) {
      strong(
        kind: ScrapeEvidenceKind.completePriorWorks,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: 'semantic_explicit_prior_work_statement',
        observedText: 'explicit prior-work collection statement',
        field: 'title_or_metadata',
      );
    }

    final targetActressBest = classificationContext == null
        ? null
        : ScrapeProvenanceSemantics.targetActressBestProposition(
            text,
            classificationContext.normalizedTargetNames,
          );
    if (targetActressBest != null) {
      strong(
        kind: ScrapeEvidenceKind.bestOfPriorWorks,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: targetActressBest.ruleId,
        observedText: targetActressBest.observedText,
        field: 'title_or_metadata',
      );
    }

    final semanticReedit = facts.reedited == true
        ? null
        : ScrapeProvenanceSemantics.strongReeditProposition(text);
    if (semanticReedit != null) {
      strong(
        kind: ScrapeEvidenceKind.reedit,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: semanticReedit.ruleId,
        observedText: semanticReedit.observedText,
        field: 'title_or_metadata',
      );
    }

    final semanticReissue = facts.reissue == true
        ? null
        : ScrapeProvenanceSemantics.strongReissueProposition(text);
    if (semanticReissue != null) {
      strong(
        kind: ScrapeEvidenceKind.reissue,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: semanticReissue.ruleId,
        observedText: semanticReissue.observedText,
        field: 'title_or_metadata',
      );
    }

    final premiumRepackage =
        ScrapeProvenanceSemantics.premiumRepackageProposition(text);
    if (premiumRepackage != null &&
        facts.reissue != true &&
        facts.reedited != true) {
      strong(
        kind: ScrapeEvidenceKind.reissue,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: premiumRepackage.ruleId,
        observedText: premiumRepackage.observedText,
        field: 'title_or_metadata',
      );
    }

    final remaster = RegExp(
      r'リマスター|remaster',
      caseSensitive: false,
    ).firstMatch(text);
    if (remaster != null && facts.remaster != true) {
      strong(
        kind: ScrapeEvidenceKind.remaster,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: 'semantic_remaster',
        observedText: remaster.group(0)!,
        field: 'title_or_metadata',
      );
    }

    final oldBonus = ScrapeProvenanceSemantics.containsOldMaterialWithNewBonus(
      text,
    );
    if (oldBonus) {
      strong(
        kind: ScrapeEvidenceKind.mixedOldNew,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: 'semantic_old_material_bonus',
        observedText: 'old material plus bonus footage',
        field: 'title_or_metadata',
      );
    }

    if (facts.explicitOriginalProduction == true) {
      strong(
        kind: ScrapeEvidenceKind.explicitOriginalWork,
        polarity: ScrapeEvidencePolarity.supportsOriginalWork,
        ruleId: 'source_explicit_original_production',
        observedText: 'source says this is a new production',
      );
    }

    final manufacturer = details?.studio ?? catalog?.manufacturer;
    final label = details?.publisher ?? catalog?.label;
    final sourceDeclaredDerived =
        ScrapeProvenanceSemantics.sourceDeclaredDerivedProductLine(
          manufacturer: manufacturer,
          label: label,
          series: series,
          tags: genres,
          description: description,
          title: title,
        );
    if (sourceDeclaredDerived != null) {
      strong(
        field: 'catalog_metadata',
        kind: ScrapeEvidenceKind.verifiedDerivedFamily,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: sourceDeclaredDerived.ruleId,
        observedText: sourceDeclaredDerived.observedText,
      );
    }

    final productFamily = ScrapeProductFamilyRegistry.match(
      code: surface.code,
      manufacturer: manufacturer,
      label: label,
      series: series,
      title: title,
    );
    if (productFamily != null) {
      final verified =
          productFamily.disposition ==
          ScrapeProductFamilyDisposition.verifiedDerivedOnly;
      if (verified) {
        strong(
          field: 'product_identity',
          kind: ScrapeEvidenceKind.verifiedDerivedFamily,
          polarity: ScrapeEvidencePolarity.supportsCompilation,
          ruleId: productFamily.ruleId,
          observedText: productFamily.observedText,
        );
      } else if (productFamily.disposition ==
          ScrapeProductFamilyDisposition.suspicionOnly) {
        addEvidence(
          surface: surface,
          field: 'product_identity',
          kind: ScrapeEvidenceKind.productFamilySuspicion,
          strength: ScrapeEvidenceStrength.medium,
          polarity: ScrapeEvidencePolarity.supportsCompilation,
          ruleId: productFamily.ruleId,
          observedText: productFamily.observedText,
        );
      }
    }
    if (ScrapeProvenanceSemantics.containsCollectionStructureSuspicion(text)) {
      addEvidence(
        surface: surface,
        field: 'title_or_metadata',
        kind: ScrapeEvidenceKind.highVolumePresentation,
        strength: ScrapeEvidenceStrength.medium,
        polarity: ScrapeEvidencePolarity.supportsCompilation,
        ruleId: 'semantic_collection_structure_suspicion',
        observedText: 'large cast, long runtime, and collection structure',
      );
    }
    final newMaterialScope = ScrapeProvenanceSemantics.newMaterialScope(text);
    if (newMaterialScope == ScrapeNewMaterialScope.wholeProduction) {
      strong(
        kind: ScrapeEvidenceKind.explicitOriginalWork,
        polarity: ScrapeEvidencePolarity.supportsOriginalWork,
        ruleId: 'semantic_original_production',
        observedText: 'whole production is described as newly filmed',
        field: 'title_or_metadata',
      );
    } else if (newMaterialScope == ScrapeNewMaterialScope.bonusOnly) {
      addEvidence(
        surface: surface,
        field: 'title_or_metadata',
        kind: ScrapeEvidenceKind.bonusNewMaterial,
        strength: ScrapeEvidenceStrength.weak,
        polarity: ScrapeEvidencePolarity.neutral,
        ruleId: 'semantic_bonus_new_material',
        observedText:
            'newly filmed or unreleased material is described as a bonus',
      );
    }
    if (!hasStrongDerivedSurfaceEvidence &&
        (facts.coPerformance == ScrapeCoPerformance.sharedProduction ||
            details?.coPerformance == ScrapeCoPerformance.sharedProduction)) {
      strong(
        kind: ScrapeEvidenceKind.genuineCoPerformance,
        polarity: ScrapeEvidencePolarity.supportsOriginalWork,
        ruleId: 'production_verified_shared',
        observedText: 'performers participate in one shared production',
      );
    }
    if (facts.coPerformance == ScrapeCoPerformance.possibleSharedProduction ||
        details?.coPerformance ==
            ScrapeCoPerformance.possibleSharedProduction) {
      addEvidence(
        surface: surface,
        field: 'title_or_metadata',
        kind: ScrapeEvidenceKind.possibleCoPerformance,
        strength: ScrapeEvidenceStrength.weak,
        polarity: ScrapeEvidencePolarity.neutral,
        ruleId: 'production_shared_hint',
        observedText:
            'source wording suggests co-performance without proving one production',
      );
    }

    // Unsafe words are recorded as context only; they never independently
    // cause EXCLUDE.
    final neutral = RegExp(
      r'編集|マルチアングル|完全版|COMPLETE|4K|8K|ノーカット|未公開|周年|スペシャル|復活|コレクション',
      caseSensitive: false,
    ).firstMatch(text);
    final viewpoint = RegExp(
      r'選択型|視点選択|同時多発.*視点',
      caseSensitive: false,
    ).firstMatch(text);
    if (viewpoint != null) {
      addEvidence(
        surface: surface,
        field: 'title_or_metadata',
        kind: ScrapeEvidenceKind.viewpointSelection,
        strength: ScrapeEvidenceStrength.weak,
        polarity: ScrapeEvidencePolarity.neutral,
        ruleId: 'semantic_safe_viewpoint_context',
        observedText: viewpoint.group(0)!,
      );
    }
    if (neutral != null) {
      addEvidence(
        surface: surface,
        field: 'title_or_metadata',
        kind: ScrapeEvidenceKind.editedPresentation,
        strength: ScrapeEvidenceStrength.weak,
        polarity: ScrapeEvidencePolarity.neutral,
        ruleId: 'semantic_unsafe_standalone_context',
        observedText: neutral.group(0)!,
      );
    }
  }

  ScrapeProvenanceClass _classForEvidence(
    List<ScrapeEvidenceAtom> evidence,
    List<_PolicySurface> surfaces,
  ) {
    final kinds = evidence
        .where(
          (item) =>
              item.polarity == ScrapeEvidencePolarity.supportsCompilation &&
              item.strength == ScrapeEvidenceStrength.strong,
        )
        .map((item) => item.kind)
        .toSet();
    if (kinds.contains(ScrapeEvidenceKind.splitFromPriorWork)) {
      return ScrapeProvenanceClass.derivedSplit;
    }
    if (kinds.contains(ScrapeEvidenceKind.extractedFromPriorWork)) {
      return ScrapeProvenanceClass.derivedExtract;
    }
    if (kinds.contains(ScrapeEvidenceKind.reissue)) {
      return ScrapeProvenanceClass.derivedReissue;
    }
    if (kinds.contains(ScrapeEvidenceKind.remaster)) {
      return ScrapeProvenanceClass.derivedRemaster;
    }
    if (kinds.contains(ScrapeEvidenceKind.reedit)) {
      return ScrapeProvenanceClass.derivedReedit;
    }
    if (kinds.contains(ScrapeEvidenceKind.mixedOldNew)) {
      return ScrapeProvenanceClass.mixedOldNew;
    }
    if (kinds.isNotEmpty) {
      return ScrapeProvenanceClass.derivedOmnibus;
    }
    final hasOriginal = evidence.any(
      (item) => item.polarity == ScrapeEvidencePolarity.supportsOriginalWork,
    );
    final hasCoPerformance = evidence.any(
      (item) => item.kind == ScrapeEvidenceKind.genuineCoPerformance,
    );
    if (hasOriginal) {
      final multi =
          surfaces.any(
            (surface) => (surface.details?.performers?.length ?? 0) > 1,
          ) ||
          hasCoPerformance;
      return multi
          ? ScrapeProvenanceClass.originalCostar
          : ScrapeProvenanceClass.originalSolo;
    }
    return ScrapeProvenanceClass.unknown;
  }
}

class _PolicySurface {
  const _PolicySurface({
    required this.id,
    required this.source,
    required this.code,
    required this.details,
    this.catalogEvidence,
  });

  final String id;
  final ScrapeSourceId source;
  final String code;
  final ScrapeWorkDetails? details;
  final ScrapeCatalogWorkEvidence? catalogEvidence;

  factory _PolicySurface.fromDetails(
    ScrapeWorkDetails details,
    int index,
  ) => _PolicySurface(
    id: '${details.source.storageValue}:$index:${details.sourceUri ?? details.code}',
    source: details.source,
    code: details.rawCode ?? details.code,
    details: details,
  );

  factory _PolicySurface.fromCatalogEvidence(
    ScrapeCatalogWorkEvidence evidence, {
    required String code,
    required String title,
    required int index,
    required int evidenceIndex,
  }) => _PolicySurface(
    id: '${evidence.source.storageValue}:$index:catalog:$evidenceIndex:${evidence.code ?? code}',
    source: evidence.source,
    code: evidence.rawCode ?? evidence.code ?? code,
    details: null,
    catalogEvidence: evidence.title == null
        ? ScrapeCatalogWorkEvidence(
            source: evidence.source,
            code: evidence.code ?? code,
            rawCode: evidence.rawCode ?? code,
            title: title,
            manufacturer: evidence.manufacturer,
            label: evidence.label,
            series: evidence.series,
            tags: evidence.tags,
            provenanceHints: evidence.provenanceHints,
            parentCodes: evidence.parentCodes,
            includedCodes: evidence.includedCodes,
            description: evidence.description,
          )
        : evidence,
  );
}

String _excerpt(String value) {
  final normalized = value.trim();
  return normalized.length <= 120 ? normalized : normalized.substring(0, 120);
}
