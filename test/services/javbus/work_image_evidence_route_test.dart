import 'package:avaca/services/javbus/prefix_route_repository.dart';
import 'package:avaca/services/javbus/work_image_downloader.dart';
import 'package:avaca/services/javbus/work_image_learned_route.dart';
import 'package:avaca/services/javbus/work_image_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  const parser = WorkImageEvidenceRouteParser();

  test('parses the NAAC DMM evidence into a safe ps/pl descriptor', () {
    final descriptor = parser.parse(
      evidenceUri: Uri.parse(
        'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
        'h_706naac00043b/h_706naac00043bjp-1.jpg',
      ),
      code: 'NAAC-043',
    );

    expect(descriptor, isNotNull);
    final urls = const WorkImagePolicy().urlsForLearnedDescriptor(
      code: 'NAAC-043',
      descriptor: descriptor!,
    );
    expect(
      urls.card.toString(),
      'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
      'h_706naac00043b/h_706naac00043bps.jpg',
    );
    expect(
      urls.detail.toString(),
      'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
      'h_706naac00043b/h_706naac00043bpl.jpg',
    );
    expect(
      isApprovedGeneratedLearnedWorkImageUri(
        uri: urls.card,
        code: 'NAAC-043',
        descriptor: descriptor,
        variant: WorkImageVariant.card,
      ),
      isTrue,
    );
  });

  test('accepts a second work with the same proven template', () {
    final first = parser.parse(
      evidenceUri: Uri.parse(
        'https://pics.dmm.co.jp/digital/video/'
        'h_706naac00043b/h_706naac00043bjp-1.jpg',
      ),
      code: 'NAAC-043',
    );
    final second = parser.parse(
      evidenceUri: Uri.parse(
        'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
        'h_706naac00042b/h_706naac00042bjp-1.jpg',
      ),
      code: 'NAAC-042',
    );
    expect(first?.canonicalKey, second?.canonicalKey);
  });

  test('normalizes DMM pics and pics_dig evidence to the approved route', () {
    const expectedCard =
        'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
        'h_706naac00043b/h_706naac00043bps.jpg';
    const expectedDetail =
        'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
        'h_706naac00043b/h_706naac00043bpl.jpg';
    final evidenceUris = [
      Uri.parse(
        'https://pics.dmm.co.jp/digital/video/'
        'h_706naac00043b/h_706naac00043bjp-1.jpg',
      ),
      Uri.parse(
        'https://awsimgsrc.dmm.co.jp/pics/digital/video/'
        'h_706naac00043b/h_706naac00043bjp-1.jpg',
      ),
      Uri.parse(
        'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
        'h_706naac00043b/h_706naac00043bjp-1.jpg',
      ),
    ];

    for (final evidenceUri in evidenceUris) {
      final descriptor = parser.parse(
        evidenceUri: evidenceUri,
        code: 'NAAC-043',
      );
      expect(descriptor, isNotNull, reason: evidenceUri.toString());
      final urls = const WorkImagePolicy().urlsForLearnedDescriptor(
        code: 'NAAC-043',
        descriptor: descriptor!,
      );
      expect(urls.card.toString(), expectedCard);
      expect(urls.detail.toString(), expectedDetail);
    }
  });

  test('preserves source tokens whose visible code has a numeric prefix', () {
    final descriptor = parser.parse(
      evidenceUri: Uri.parse(
        'https://pics.dmm.co.jp/digital/video/'
        '55t2800621/55t2800621jp-1.jpg',
      ),
      code: 'T28-621',
    );

    expect(descriptor, isNotNull);
    final urls = const WorkImagePolicy().urlsForLearnedDescriptor(
      code: 'T28-621',
      descriptor: descriptor!,
    );
    expect(
      urls.card.toString(),
      'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
      '55t2800621/55t2800621ps.jpg',
    );
    expect(
      urls.detail.toString(),
      'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
      '55t2800621/55t2800621pl.jpg',
    );
  });

  test('parses paired MGStage pf/pb evidence', () {
    final descriptor = parser.parse(
      evidenceUri: Uri.parse(
        'https://image.mgstage.com/images/prestige/abf/183/'
        'pf_e_abf-183.jpg',
      ),
      code: 'ABF-183',
    );
    expect(descriptor?.variantMode, WorkImageLearnedVariantMode.mgstagePfPb);
    final urls = const WorkImagePolicy().urlsForLearnedDescriptor(
      code: 'ABF-183',
      descriptor: descriptor!,
    );
    expect(urls.card.toString(), contains('/pf_e_abf-183.jpg'));
    expect(urls.detail.toString(), contains('/pb_e_abf-183.jpg'));
  });

  test('rejects unsafe or unproven evidence', () {
    final cases = <Uri>[
      Uri.parse(
        'http://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
        'h_706naac00043b/h_706naac00043bjp-1.jpg',
      ),
      Uri.parse(
        'https://evil.example/pics_dig/digital/video/'
        'h_706naac00043b/h_706naac00043bjp-1.jpg',
      ),
      Uri.parse(
        'https://awsimgsrc.dmm.co.jp:8443/pics_dig/digital/video/'
        'h_706naac00043b/h_706naac00043bjp-1.jpg',
      ),
      Uri.parse(
        'https://pics.dmm.co.jp/pics_dig/digital/video/'
        'h_706naac00043b/h_706naac00043bjp-1.jpg',
      ),
      Uri.parse(
        'https://awsimgsrc.dmm.co.jp/digital/video/'
        'h_706naac00043b/h_706naac00043bjp-1.jpg',
      ),
      Uri.parse(
        'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
        'h_706naac00043b/other00043jp-1.jpg',
      ),
      Uri.parse(
        'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
        'h_706naac00043b/h_706naac00043bps.jpg?x=1',
      ),
      Uri.parse('https://www.javbus.com/images/naac-043.jpg'),
    ];
    for (final uri in cases) {
      expect(
        parser.parse(evidenceUri: uri, code: 'NAAC-043'),
        isNull,
        reason: uri.toString(),
      );
    }
  });

  test('learns an evidence route and reuses it for the next work', () async {
    final bytes = image.encodePng(image.Image(width: 300, height: 450));
    final repository = PrefixRouteRepository.inMemory();
    final firstTransport = _FakeBinaryTransport([
      BinaryResponse(statusCode: 200, bodyBytes: bytes),
    ]);
    await WorkImageDownloader(
      transport: firstTransport,
      routeRepository: repository,
    ).fetch(
      code: 'NAAC-043',
      originalImageEvidenceUris: [
        Uri.parse(
          'https://pics.dmm.co.jp/digital/video/'
          'h_706naac00043b/h_706naac00043bjp-1.jpg',
        ),
      ],
      variant: WorkImageVariant.card,
    );
    expect(firstTransport.requested.single.path, contains('h_706naac00043bps'));
    expect(repository.learnedRuleFor('naac'), isNotNull);
    expect(
      repository.learnedRuleFor('naac')!.candidates.single.successCount,
      1,
    );

    final secondTransport = _FakeBinaryTransport([
      BinaryResponse(statusCode: 200, bodyBytes: bytes),
    ]);
    await WorkImageDownloader(
      transport: secondTransport,
      routeRepository: repository,
    ).fetch(code: 'NAAC-042', variant: WorkImageVariant.detail);
    expect(secondTransport.requested.single.path, contains('h_706naac00042b'));
    expect(secondTransport.requested.single.path, endsWith('bpl.jpg'));
  });

  test(
    'persists learned descriptors separately from legacy Prefix rules',
    () async {
      final descriptor = parser.parse(
        evidenceUri: Uri.parse(
          'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
          'h_706naac00043b/h_706naac00043bjp-1.jpg',
        ),
        code: 'NAAC-043',
      )!;
      final repository = PrefixRouteRepository.inMemory();
      await repository.recordLearnedSuccess(
        prefix: 'NAAC',
        descriptor: descriptor,
        workCode: 'NAAC-043',
        evidenceUri: Uri.parse(
          'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
          'h_706naac00043b/h_706naac00043bjp-1.jpg',
        ),
      );
      final reloaded = PrefixRouteRepository.inMemory(
        initialJson: await repository.exportJson(),
        initialLearnedJson: await repository.exportLearnedJson(),
      );
      await reloaded.ensureLoaded();
      expect(reloaded.ruleFor('naac'), isNull);
      expect(reloaded.learnedRuleFor('naac'), isNotNull);
      expect(
        reloaded
            .learnedRuleFor('naac')!
            .candidates
            .single
            .descriptor
            .canonicalKey,
        descriptor.canonicalKey,
      );
    },
  );

  test(
    'promotes only after two distinct works and ignores stale completions',
    () async {
      final descriptor = parser.parse(
        evidenceUri: Uri.parse(
          'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
          'h_706naac00043b/h_706naac00043bjp-1.jpg',
        ),
        code: 'NAAC-043',
      )!;
      final repository = PrefixRouteRepository.inMemory();
      await repository.recordLearnedSuccess(
        prefix: 'NAAC',
        descriptor: descriptor,
        workCode: 'NAAC-043',
      );
      await repository.recordLearnedSuccess(
        prefix: 'NAAC',
        descriptor: descriptor,
        workCode: 'NAAC-043',
      );
      expect(
        repository.learnedRuleFor('naac')!.candidates.single.status,
        WorkImageLearnedCandidateStatus.provisional,
      );
      await repository.recordLearnedSuccess(
        prefix: 'NAAC',
        descriptor: descriptor,
        workCode: 'NAAC-042',
      );
      expect(
        repository.learnedRuleFor('naac')!.candidates.single.status,
        WorkImageLearnedCandidateStatus.verified,
      );

      final staleToken = repository.revisionTokenFor('naac');
      await repository.forget('naac');
      await repository.recordLearnedSuccess(
        prefix: 'NAAC',
        descriptor: descriptor,
        workCode: 'NAAC-041',
        expectedRevisionToken: staleToken,
      );
      expect(repository.learnedRuleFor('naac'), isNull);

      await repository.recordLearnedSuccess(
        prefix: 'NAAC',
        descriptor: descriptor,
        workCode: 'NAAC-043',
      );
      final clearToken = repository.revisionTokenFor('naac');
      await repository.clearAutomaticLearning();
      await repository.recordLearnedSuccess(
        prefix: 'NAAC',
        descriptor: descriptor,
        workCode: 'NAAC-040',
        expectedRevisionToken: clearToken,
      );
      expect(repository.learnedRuleFor('naac'), isNull);
    },
  );
}

final class _FakeBinaryTransport implements BinaryTransport {
  _FakeBinaryTransport(this.responses);

  final List<BinaryResponse> responses;
  final List<Uri> requested = [];

  @override
  Future<BinaryResponse> get(Uri uri) async {
    requested.add(uri);
    return responses[requested.length - 1];
  }
}
