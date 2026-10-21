import 'package:avaca/services/scrape/work_identity.dart';
import 'package:avaca/services/scrape/scrape_models.dart';
import 'package:avaca/models/scrape_source_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('title identity only removes explicit 特典版 markers', () {
    final ordinary = scrapeTitleIdentity('  普通作品  名稱 ');
    final special = scrapeTitleIdentity('【特典版】 普通作品 名稱');
    final asciiSpecial = scrapeTitleIdentity('[特典版] 普通作品 名稱');

    expect(ordinary.key, '普通作品 名稱');
    expect(ordinary.isSpecialEdition, isFalse);
    expect(special.key, ordinary.key);
    expect(special.isSpecialEdition, isTrue);
    expect(asciiSpecial.key, ordinary.key);
    expect(scrapeTitleIdentity('普通作品 (別名)').key, '普通作品 (別名)');
    expect(scrapeTitleIdentity('作品 A－B').key, isNot('作品 A-B'));
  });

  test('work code surface normalization does not infer aliases', () {
    expect(normalizeScrapeWorkCodeSurface(' start－489 '), 'START-489');
    expect(normalizeScrapeWorkCodeSurface('H_346REBD00975'), isNot('REBD-975'));
    expect(
      normalizeScrapeWorkCodeSurface('1STZY00017'),
      isNot(normalizeScrapeWorkCodeSurface('STZY-017')),
    );
    expect(normalizeScrapeWorkCodeSurface('   '), isNull);
  });

  test('matches safe separatorless forms and preserves unsafe forms', () {
    expect(scrapeWorkCodesEqual('SSIS875', 'SSIS-875'), isTrue);
    expect(preferredScrapeWorkCode(['SSIS875', 'SSIS-875']), 'SSIS-875');
    expect(scrapeWorkCodesEqual('START00023', 'START-023'), isTrue);
    expect(preferredScrapeWorkCode(['START00023', 'START-023']), 'START-023');

    expect(scrapeWorkCodesEqual('SIVR00303', 'SIVR-303'), isFalse);
    expect(scrapeWorkCodesEqual('1STZY00017', 'STZY-017'), isFalse);
    expect(scrapeWorkCodesEqual('3DSVR-1947', 'DSVR-1947'), isFalse);
    expect(scrapeWorkCodesEqual('H_346REBD00975', 'REBD-975'), isFalse);
  });

  test(
    'scopes SOD edition collapse and canonicalizes trusted bridge aliases',
    () {
      final sodEvidence = const ScrapeWorkIdentityEvidence(
        manufacturer: 'SODクリエイト',
        label: 'SOD create',
      );
      for (final code in const [
        'STARS-859',
        'STARS-859-V',
        'STARS-859-VT',
        'STARS-859-VT-EC',
        'STARS-859-VT2-EC',
        'STARSBD-859',
      ]) {
        final identity = parseScrapeWorkCodeIdentity(
          code,
          evidence: sodEvidence,
        );
        expect(identity?.key, 'stars859', reason: code);
        expect(identity?.displayCode, 'STARS-859', reason: code);
      }

      expect(
        parseScrapeWorkCodeIdentity('STARSBD-859')?.key,
        isNot('stars859'),
      );
      expect(scrapeWorkCodesEqual('FOO-123-EC', 'FOO-123'), isFalse);

      final bridge = const ScrapeExternalWorkIdentity(
        canonicalCode: 'START-164',
        makerCode: '107START-164',
        aliases: ['1start00164'],
        platformIds: {'fanza': 'START-164'},
      );
      final summary = ScrapeWorkSummary(
        source: ScrapeSourceId.avwiki,
        code: '1start00164',
        rawCode: '1start00164',
        title: 'cross-platform identity',
        detailUri: Uri.parse('https://av-wiki.net/start-164/'),
        externalIdentity: bridge,
      );
      expect(scrapeWorkIdentityKeyForSummary(summary), 'code:start164');
      expect(
        scrapeWorkCanonicalStorageCode('1start00164', externalIdentity: bridge),
        'START-164',
      );
    },
  );

  test('pads trusted SOD STARS identities without global zero trimming', () {
    const sodEvidence = ScrapeWorkIdentityEvidence(manufacturer: 'SODクリエイト');
    for (final code in const [
      'STARS-087',
      'STARS-87',
      'STARS-087-V',
      'STARS-087-VT',
      'STARS-087-VT2-EC',
      'STARSBD-087',
    ]) {
      final identity = parseScrapeWorkCodeIdentity(code, evidence: sodEvidence);
      expect(identity?.key, 'stars87', reason: code);
      expect(identity?.displayCode, 'STARS-087', reason: code);
    }
    expect(
      scrapeWorkCodesEqual('STARS-87', 'STARS-087', evidence: sodEvidence),
      isTrue,
    );
    expect(scrapeWorkCodesEqual('STARS-87', 'STARS-087'), isFalse);
    expect(
      scrapeWorkCodesEqual('SIVR00303', 'SIVR-303', evidence: sodEvidence),
      isFalse,
    );
  });

  test('uses only same-source catalog metadata for scoped identity', () {
    final contextual = ScrapeWorkSummary(
      source: ScrapeSourceId.avbase,
      code: 'STARS-087-V',
      rawCode: 'STARS-087-V',
      title: 'SOD catalog entry',
      detailUri: Uri.parse('https://www.avbase.net/works/STARS-087-V'),
      catalogEvidence: const [
        ScrapeCatalogWorkEvidence(
          source: ScrapeSourceId.avbase,
          code: 'STARS-087-V',
          manufacturer: 'SODクリエイト',
        ),
      ],
    );
    final unscoped = ScrapeWorkSummary(
      source: ScrapeSourceId.avbase,
      code: 'STARS-087',
      rawCode: 'STARS-087',
      title: 'Unscoped entry',
      detailUri: Uri.parse('https://www.avbase.net/works/STARS-087'),
    );
    final foreign = ScrapeWorkSummary(
      source: ScrapeSourceId.avbase,
      code: 'STARS-087-V',
      rawCode: 'STARS-087-V',
      title: 'Foreign catalog metadata',
      detailUri: Uri.parse('https://www.avbase.net/works/STARS-087-V-foreign'),
      catalogEvidence: const [
        ScrapeCatalogWorkEvidence(
          source: ScrapeSourceId.javbus,
          code: 'STARS-087-V',
          manufacturer: 'SODクリエイト',
        ),
      ],
    );

    expect(scrapeWorkIdentityKeyForSummary(contextual), 'code:stars87');
    expect(scrapeWorkIdentityKeyForSummary(unscoped), 'code:stars087');
    expect(scrapeWorkIdentityKeyForSummary(foreign), 'code:opaque:stars-087-v');
    expect(scrapeWorkIdentityKeyForSummary(contextual), isNot('code:stars087'));
  });

  test(
    'treats V, T, and VT edition suffixes as the ordinary work identity',
    () {
      const specialCodes = {
        'START-276V': 'START-276',
        'STARS-859-T': 'STARS-859',
        'STARS-757-T': 'STARS-757',
        'START-053-VT': 'START-053',
        'START-053VT': 'START-053',
      };
      for (final entry in specialCodes.entries) {
        const sodEvidence = ScrapeWorkIdentityEvidence(
          manufacturer: 'SODクリエイト',
        );
        final special = parseScrapeWorkCodeIdentity(
          entry.key,
          evidence: sodEvidence,
        );
        final ordinary = parseScrapeWorkCodeIdentity(
          entry.value,
          evidence: sodEvidence,
        );
        expect(special?.key, ordinary?.key);
        expect(special?.displayCode, entry.value);
        expect(special?.isSpecialEdition, isTrue);
        expect(
          scrapeWorkCodesEqual(entry.key, entry.value, evidence: sodEvidence),
          isTrue,
        );
      }

      const sodEvidence = ScrapeWorkIdentityEvidence(manufacturer: 'SODクリエイト');
      final hyphenated = parseScrapeWorkCodeIdentity(
        'START-053-V',
        evidence: sodEvidence,
      );
      expect(hyphenated?.key, 'start53');
      expect(hyphenated?.displayCode, 'START-053');
      expect(hyphenated?.isSpecialEdition, isTrue);
      expect(
        scrapeWorkCodesEqual('START-053-V', 'START-053', evidence: sodEvidence),
        isTrue,
      );

      for (final suffix in ['V', 'T', 'VT']) {
        final special = parseScrapeWorkCodeIdentity(
          'START-053-$suffix',
          evidence: sodEvidence,
        );
        expect(special?.key, 'start53');
        expect(special?.displayCode, 'START-053');
        expect(special?.isSpecialEdition, isTrue);
        expect(
          scrapeWorkCodesEqual(
            'START-053-$suffix',
            'START-053',
            evidence: sodEvidence,
          ),
          isTrue,
        );
      }

      expect(
        preferredScrapeWorkCode([
          'START-053-VT',
          'START-053-T',
          'START-053',
        ], evidence: sodEvidence),
        'START-053',
      );
      expect(scrapeWorkCodesEqual('START-053-VR', 'START-053'), isFalse);
      expect(scrapeWorkCodesEqual('START-053-V', 'START-053'), isFalse);
    },
  );

  test('requires title plus independent metadata when a code is missing', () {
    const common = '同一作品標題';
    expect(
      scrapeWorkMetadataLikelySame(
        firstTitle: common,
        firstReleaseDate: '2025-10-01',
        firstPublisher: null,
        firstStudio: null,
        secondTitle: common,
        secondReleaseDate: '2025-10-01',
        secondPublisher: null,
        secondStudio: null,
      ),
      isTrue,
    );
    expect(
      scrapeWorkMetadataLikelySame(
        firstTitle: common,
        firstReleaseDate: null,
        firstPublisher: null,
        firstStudio: null,
        secondTitle: common,
        secondReleaseDate: null,
        secondPublisher: null,
        secondStudio: null,
      ),
      isFalse,
    );
  });

  test('Rebecca classification is publisher based and exact', () {
    expect(isRebeccaPublisher(' Rebecca '), isTrue);
    expect(isRebeccaPublisher('REBECCA'), isTrue);
    expect(isRebeccaPublisher('Rebecca / Rebecca'), isTrue);
    expect(isRebeccaPublisher('REBD'), isFalse);
    expect(isRebeccaPublisher('H_346REBD00975'), isFalse);
    expect(isRebeccaPublisher('Rebecca Studio'), isFalse);
  });
}
