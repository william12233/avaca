import 'dart:io';

import 'package:avaca/services/javbus/work_image_downloader.dart';
import 'package:avaca/services/javbus/work_image_policy.dart';
import 'package:avaca/services/javbus/prefix_route_repository.dart';
import 'package:avaca/services/javbus/work_image_route_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  group('image URL policy', () {
    const policy = WorkImagePolicy();

    test('keeps the six approved endpoint forms allowlisted', () {
      expect(
        approvedWorkImageEndpointExamples
            .map(Uri.parse)
            .every(isApprovedWorkImageUri),
        isTrue,
      );
      expect(
        isApprovedWorkImageUri(
          Uri.parse('https://www.javbus.com/pics/cover/ssis00875.jpg'),
        ),
        isFalse,
      );
      expect(
        isApprovedWorkImageUri(
          Uri.parse(
            'https://awsimgsrc.dmm.co.jp/p_package/ssis00875/ssis00875ps.jpg',
          ),
        ),
        isFalse,
      );
    });

    test('maps representative code families to one deterministic token', () {
      const cases = {
        'SONE-833': 'sone00833',
        'SSIS-875': 'ssis00875',
        'SSNI-190': 'ssni00190',
        'SIVR-303': 'sivr00303',
        'IPX-100': 'ipx00100',
        'MIAA-001': 'miaa00001',
        'STARS-859': 'stars00859',
        'START-618': '1start00618',
        'START00023': '1start00023',
        'SDJS-380': '1sdjs00380',
        'DEVR-039': 'h_1711devr00039',
        'REBD-975': 'h_346rebd00975',
      };

      for (final entry in cases.entries) {
        final normalizedCode = entry.key.toUpperCase();
        final studio =
            normalizedCode.startsWith('START') ||
                normalizedCode.startsWith('SDJS')
            ? 'SOD Create'
            : normalizedCode.startsWith('DEVR')
            ? 'Document'
            : normalizedCode.startsWith('REBD')
            ? 'Rebecca'
            : 'S1';
        final urls = policy.urlsFor(code: entry.key, studio: studio);
        final path = urls.card.pathSegments;
        expect(path[path.length - 2], entry.value);
        expect(path.last, entry.value + 'ps.jpg');
        expect(isApprovedWorkImageUri(urls.card), isTrue);
        expect(isApprovedWorkImageUri(urls.detail), isTrue);
      }
    });

    test('normalizes separatorless SSIS and START forms without aliases', () {
      expect(
        policy.urlsFor(code: 'SSIS875', studio: 'S1').card,
        policy.urlsFor(code: 'SSIS-875', studio: 'S1').card,
      );
      expect(
        policy.urlsFor(code: 'START00023', studio: 'SOD Create').card,
        policy.urlsFor(code: 'START-023', studio: 'SOD Create').card,
      );
      expect(
        policy.urlsFor(code: 'SIVR00303', studio: 'S1').card,
        policy.urlsFor(code: 'SIVR-00303', studio: 'S1').card,
      );
    });

    test('builds the exact Prestige endpoints without number padding', () {
      final urls = policy.urlsFor(code: 'ABF-183', studio: 'プレステージ');

      expect(
        urls.card.toString(),
        'https://image.mgstage.com/images/prestige/abf/183/'
        'pf_e_abf-183.jpg',
      );
      expect(
        urls.detail.toString(),
        'https://image.mgstage.com/images/prestige/abf/183/'
        'pb_e_abf-183.jpg',
      );
      expect(urls.source, WorkImageSource.mgstage);
    });

    test('applies the Seikyouiku publisher rule for MGStage', () {
      final urls = policy.urlsFor(code: 'SEI-007', studio: 'セイキョウイク');

      expect(
        urls.card.toString(),
        'https://image.mgstage.com/images/seikyouiku/502sei/007/'
        'pf_e_502sei-007.jpg',
      );
      expect(
        urls.detail.toString(),
        'https://image.mgstage.com/images/seikyouiku/502sei/007/'
        'pb_e_502sei-007.jpg',
      );
      expect(isApprovedWorkImageUri(urls.card), isTrue);
      expect(isApprovedWorkImageUri(urls.detail), isTrue);
    });

    test('refuses to guess when maker and publisher metadata are missing', () {
      expect(
        () => policy.urlsFor(code: 'ABF-183'),
        throwsA(isA<WorkImageRouteException>()),
      );
    });

    test('does not infer a route from image evidence', () {
      expect(
        () => policy.urlsFor(
          code: 'SNOS-320',
          evidenceUris: [
            Uri.parse(
              'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
              'snos00320/snos00320ps.jpg',
            ),
          ],
        ),
        throwsA(isA<WorkImageRouteException>()),
      );
    });

    test('recognizes the leading-one DMM family from publisher rules', () {
      final urls = policy.urlsFor(code: 'START-023', studio: 'SOD Create');

      expect(
        urls.card.pathSegments[urls.card.pathSegments.length - 2],
        '1start00023',
      );
    });

    test('refuses an unregistered publisher prefix instead of guessing', () {
      expect(
        () => policy.urlsFor(code: 'ZZZZ-001'),
        throwsA(isA<WorkImageRouteException>()),
      );
    });

    test('uses visible work code for local filenames, not network token', () {
      expect(
        policy.fileNameFor(code: 'START-489', variant: WorkImageVariant.card),
        'start00489ps.jpg',
      );
      expect(
        policy.fileNameFor(code: 'REBD-975', variant: WorkImageVariant.detail),
        'rebd00975pl.jpg',
      );
    });

    test('formats every supported family without metadata', () {
      final standard = policy.urlsForFamily(
        code: 'SONE-833',
        family: WorkImageNormalizationFamily.dmmStandard,
      );
      expect(standard.card.pathSegments, contains('sone00833'));

      final leading = policy.urlsForFamily(
        code: 'START00023',
        family: WorkImageNormalizationFamily.dmmLeadingOne,
      );
      expect(leading.card.pathSegments, contains('1start00023'));

      final h1711 = policy.urlsForFamily(
        code: 'DEVR-039',
        family: WorkImageNormalizationFamily.dmmH1711,
      );
      expect(h1711.card.pathSegments, contains('h_1711devr00039'));

      final rebecca = policy.urlsForFamily(
        code: 'REBD-975',
        family: WorkImageNormalizationFamily.dmmRebeccaH346,
      );
      expect(rebecca.detail.pathSegments, contains('h_346rebd00975'));

      final prestige = policy.urlsForFamily(
        code: 'ABF-183',
        family: WorkImageNormalizationFamily.mgstagePrestige,
      );
      expect(
        prestige.card.toString(),
        'https://image.mgstage.com/images/prestige/abf/183/'
        'pf_e_abf-183.jpg',
      );

      final seikyouiku = policy.urlsForFamily(
        code: 'SEI-007',
        family: WorkImageNormalizationFamily.mgstageSeikyouiku,
      );
      expect(
        seikyouiku.detail.toString(),
        'https://image.mgstage.com/images/seikyouiku/502sei/007/'
        'pb_e_502sei-007.jpg',
      );
    });
  });

  test(
    'downloads only the selected approved URL and has no fallback',
    () async {
      final valid = image.encodePng(image.Image(width: 300, height: 450));
      final transport = _FakeBinaryTransport([
        BinaryResponse(statusCode: 200, bodyBytes: valid),
      ]);

      final result = await WorkImageDownloader(
        transport: transport,
      ).fetch(code: 'SSIS-875', variant: WorkImageVariant.detail);

      expect(result.bytes, valid);
      expect(transport.requested, hasLength(1));
      expect(
        transport.requested.single.toString(),
        'https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/'
        'ssis00875/ssis00875pl.jpg',
      );
    },
  );

  test(
    'reports one failed approved URL without trying another family',
    () async {
      final transport = _FakeBinaryTransport([
        const BinaryResponse(statusCode: 404, bodyBytes: []),
      ]);

      await expectLater(
        WorkImageDownloader(transport: transport).fetch(
          code: 'REBD-975',
          route: const WorkImageRouteResolution.resolved(
            platform: WorkImagePlatform.dmm,
            family: WorkImageNormalizationFamily.dmmRebeccaH346,
          ),
          variant: WorkImageVariant.card,
        ),
        throwsA(isA<WorkImageDownloadException>()),
      );
      expect(transport.requested, hasLength(1));
      expect(transport.requested.single.toString(), contains('h_346rebd00975'));
    },
  );

  test('rejects placeholder dimensions instead of learning a route', () async {
    final placeholder = image.encodePng(image.Image(width: 90, height: 122));
    final transport = _FakeBinaryTransport([
      for (var index = 0; index < 6; index++)
        BinaryResponse(statusCode: 200, bodyBytes: placeholder),
    ]);

    await expectLater(
      WorkImageDownloader(transport: transport).fetch(
        code: 'START-196',
        studio: 'SOD Create',
        variant: WorkImageVariant.card,
      ),
      throwsA(isA<WorkImageDownloadException>()),
    );
    expect(transport.requested, hasLength(5));
    expect(transport.requested.first.toString(), contains('1start00196'));
  });

  test(
    'uses leading-one tokens for START and STARS without prior rules',
    () async {
      final startTransport = _FakeBinaryTransport([
        BinaryResponse(
          statusCode: 200,
          bodyBytes: image.encodePng(image.Image(width: 300, height: 450)),
        ),
      ]);
      await WorkImageDownloader(
        transport: startTransport,
      ).fetch(code: 'START-053', variant: WorkImageVariant.card);
      expect(startTransport.requested.single.path, contains('1start00053'));

      final starsTransport = _FakeBinaryTransport([
        BinaryResponse(
          statusCode: 200,
          bodyBytes: image.encodePng(image.Image(width: 300, height: 450)),
        ),
      ]);
      await WorkImageDownloader(
        transport: starsTransport,
      ).fetch(code: 'STARS-715', variant: WorkImageVariant.detail);
      expect(starsTransport.requested.single.path, contains('1stars00715'));
    },
  );

  group('verified 0.8.7 DMM-standard metadata routes', () {
    const resolver = WorkImageRouteResolver();
    const publisherAliases = <String>[
      'オーロラプロジェクト・アネックス',
      'バビロン/妄想族',
      'ビビアン',
      'WANZ',
      'kawaii',
      'ピーターズ',
      'CRYSTAL VR',
      'ダスッ！',
      'DOC DREAM',
      'アリスJAPAN',
      'flavors',
      'DEEP’S',
      'E-BODY',
      'FALENO star',
      'ふぇちぽいんと',
      'FOCUS',
      'ULTIMA',
      '本中',
      'h.m.p DORAMA',
      '初代渋谷特別特攻本部',
      'IENF',
      'IENE',
      'IESP',
      'Fitch',
      'Madonna',
      'かぐや姫Pt',
      'K-Tribe',
      '黒髪美少女',
      'ルナティックス',
      'マゾマン',
      '宇宙企画',
      '溜池ゴロー',
      'みんなのキカタン',
      'MOODYZ Best',
      'million（ミリオン）',
      'ミコン',
      'IRIS',
      'MCP',
      '無垢',
      'M’s video Group',
      'MAXING',
      '七狗留',
      'ONEZ',
      'ONETIME',
      'GLORY QUEST',
      'パコパコ団とゆかいな仲間たち/妄想族',
      'OPPAI',
      'S-Cute',
      '羞恥娘',
      'TMA',
      '円光タダまん',
      'LEO',
      'UMANAMI',
      'まるっと！',
      'ゾクゾク娘',
    ];
    const studioAliases = <String>[
      'オーロラプロジェクト・アネックス',
      'バビロン/妄想族',
      'ビビアン',
      'ワンズファクトリー',
      'kawaii',
      'ピーターズ',
      'CRYSTAL VR',
      'ダスッ！',
      'DOC',
      'アリスJAPAN',
      'ディープス',
      'E-BODY',
      'エロタイム',
      'FALENO',
      'ABC/妄想族',
      'VENUS',
      '本中',
      'h.m.p DORAMA',
      'マーキュリー',
      'アイエナジー',
      'Fitch',
      'マドンナ',
      'かぐや姫Pt/妄想族',
      'ケー・トライブ',
      'メディアアーツ',
      'LUNATICS',
      '宇宙企画',
      '溜池ゴロー',
      'ムーディーズ',
      'ケイ・エム・プロデュース',
      'MARRION',
      '無垢',
      'エムズビデオグループ',
      'MAXING',
      'プラネットプラス',
      'ONEMORE',
      'ONETIME',
      'グローリークエスト',
      'パコパコ団とゆかいな仲間たち/妄想族',
      'OPPAI',
      'S-Cute',
      '素人CLOVER',
      'サディスティックヴィレッジ',
      'TMA',
      'First Star',
      'LEO',
      'ゾクゾク娘/妄想族',
      'サディヴィレナウ！',
    ];

    test('maps every verified publisher alias to dmmStandard', () {
      expect(publisherAliases, hasLength(55));
      for (final alias in publisherAliases) {
        final resolution = resolver.resolve(publisher: alias);
        expect(
          resolution.family,
          WorkImageNormalizationFamily.dmmStandard,
          reason: 'publisher alias: $alias',
        );
      }
    });

    test('maps every verified studio alias independently to dmmStandard', () {
      expect(studioAliases, hasLength(48));
      for (final alias in studioAliases) {
        final resolution = resolver.resolve(studio: alias);
        expect(
          resolution.family,
          WorkImageNormalizationFamily.dmmStandard,
          reason: 'studio alias: $alias',
        );
      }
    });

    test('uses either metadata source and keeps conflict semantics', () {
      expect(
        resolver.resolve(studio: '素人CLOVER').family,
        WorkImageNormalizationFamily.dmmStandard,
      );
      expect(
        resolver.resolve(studio: 'unknown studio', publisher: 'WANZ').family,
        WorkImageNormalizationFamily.dmmStandard,
      );
      expect(
        resolver
            .resolve(studio: 'CRYSTAL VR', publisher: 'unknown publisher')
            .family,
        WorkImageNormalizationFamily.dmmStandard,
      );
      expect(
        resolver.resolve(studio: 'E-BODY', publisher: 'WANZ').family,
        WorkImageNormalizationFamily.dmmStandard,
      );
      expect(
        resolver.resolve(studio: 'SOD Create', publisher: 'S1').failureReason,
        WorkImageRouteFailureReason.metadataConflict,
      );
      expect(
        resolver
            .resolve(studio: 'unknown studio', publisher: 'unknown publisher')
            .failureReason,
        WorkImageRouteFailureReason.metadataUnmapped,
      );
    });

    test(
      'formats blank-publisher routes with the existing DMM token policy',
      () {
        const policy = WorkImagePolicy();
        const cases = <String, List<String>>{
          'エロタイム': ['ETQR-408', 'etqr00408'],
          '素人CLOVER': ['STCV-122', 'stcv00122'],
          'サディヴィレナウ！': ['ZOZO-148', 'zozo00148'],
        };
        for (final entry in cases.entries) {
          final urls = policy.urlsFor(code: entry.value[0], studio: entry.key);
          expect(
            urls.card.pathSegments[urls.card.pathSegments.length - 2],
            entry.value[1],
          );
          expect(
            urls.detail.pathSegments[urls.detail.pathSegments.length - 1],
            '${entry.value[1]}pl.jpg',
          );
        }
      },
    );
  });

  test('writes a downloaded image to the requested local file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'avaca_image_download_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final bytes = image.encodePng(image.Image(width: 300, height: 450));
    final target =
        directory.path +
        Platform.pathSeparator +
        'nested' +
        Platform.pathSeparator +
        'card.png';

    await WorkImageDownloader(
      transport: _FakeBinaryTransport([
        BinaryResponse(statusCode: 200, bodyBytes: bytes),
      ]),
    ).downloadToFile(
      code: 'SONE-833',
      studio: 'S1',
      variant: WorkImageVariant.card,
      targetPath: target,
    );

    expect(await File(target).readAsBytes(), bytes);
  });

  test('automatically learns the Rebecca H346 family', () async {
    final valid = image.encodePng(image.Image(width: 300, height: 450));
    final transport = _FakeBinaryTransport([
      const BinaryResponse(statusCode: 404, bodyBytes: []),
      const BinaryResponse(statusCode: 404, bodyBytes: []),
      const BinaryResponse(statusCode: 404, bodyBytes: []),
      BinaryResponse(statusCode: 200, bodyBytes: valid),
    ]);
    final repository = PrefixRouteRepository.inMemory();

    await WorkImageDownloader(
      transport: transport,
      routeRepository: repository,
    ).fetch(code: 'REBD-975', variant: WorkImageVariant.detail);

    expect(transport.requested, hasLength(4));
    expect(transport.requested.last.path, contains('h_346rebd00975'));
    expect(
      repository.ruleFor('rebd')?.preferredFamily,
      WorkImageNormalizationFamily.dmmRebeccaH346,
    );
  });

  test('automatically learns MGStage Prestige and Seikyouiku forms', () async {
    final valid = image.encodePng(image.Image(width: 300, height: 450));

    final prestigeTransport = _FakeBinaryTransport([
      const BinaryResponse(statusCode: 404, bodyBytes: []),
      const BinaryResponse(statusCode: 404, bodyBytes: []),
      const BinaryResponse(statusCode: 404, bodyBytes: []),
      BinaryResponse(statusCode: 200, bodyBytes: valid),
    ]);
    final prestigeRepository = PrefixRouteRepository.inMemory();
    await WorkImageDownloader(
      transport: prestigeTransport,
      routeRepository: prestigeRepository,
    ).fetch(code: 'ABF-183', variant: WorkImageVariant.card);
    expect(prestigeTransport.requested.last.host, 'image.mgstage.com');
    expect(prestigeTransport.requested.last.path, contains('pf_e_abf-183.jpg'));
    expect(
      prestigeRepository.ruleFor('abf')?.preferredFamily,
      WorkImageNormalizationFamily.mgstagePrestige,
    );

    final seikyouikuTransport = _FakeBinaryTransport([
      const BinaryResponse(statusCode: 404, bodyBytes: []),
      const BinaryResponse(statusCode: 404, bodyBytes: []),
      const BinaryResponse(statusCode: 404, bodyBytes: []),
      const BinaryResponse(statusCode: 404, bodyBytes: []),
      BinaryResponse(statusCode: 200, bodyBytes: valid),
    ]);
    final seikyouikuRepository = PrefixRouteRepository.inMemory();
    await WorkImageDownloader(
      transport: seikyouikuTransport,
      routeRepository: seikyouikuRepository,
    ).fetch(code: 'SEI-007', variant: WorkImageVariant.detail);
    expect(seikyouikuTransport.requested.last.host, 'image.mgstage.com');
    expect(
      seikyouikuTransport.requested.last.path,
      contains('pb_e_502sei-007.jpg'),
    );
    expect(
      seikyouikuRepository.ruleFor('sei')?.preferredFamily,
      WorkImageNormalizationFamily.mgstageSeikyouiku,
    );
  });
}

class _FakeBinaryTransport implements BinaryTransport {
  _FakeBinaryTransport(this.responses);

  final List<BinaryResponse> responses;
  final List<Uri> requested = [];

  @override
  Future<BinaryResponse> get(Uri uri) async {
    requested.add(uri);
    return responses[requested.length - 1];
  }
}
