import 'package:avaca/services/scrape/work_identity.dart';
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
        final special = parseScrapeWorkCodeIdentity(entry.key);
        final ordinary = parseScrapeWorkCodeIdentity(entry.value);
        expect(special?.key, ordinary?.key);
        expect(special?.displayCode, entry.value);
        expect(special?.isSpecialEdition, isTrue);
        expect(scrapeWorkCodesEqual(entry.key, entry.value), isTrue);
      }

      final hyphenated = parseScrapeWorkCodeIdentity('START-053-V');
      expect(hyphenated?.key, 'start053');
      expect(hyphenated?.displayCode, 'START-053');
      expect(hyphenated?.isSpecialEdition, isTrue);
      expect(scrapeWorkCodesEqual('START-053-V', 'START-053'), isTrue);

      for (final suffix in ['V', 'T', 'VT']) {
        final special = parseScrapeWorkCodeIdentity('START-053-$suffix');
        expect(special?.key, 'start053');
        expect(special?.displayCode, 'START-053');
        expect(special?.isSpecialEdition, isTrue);
        expect(scrapeWorkCodesEqual('START-053-$suffix', 'START-053'), isTrue);
      }

      expect(
        preferredScrapeWorkCode(['START-053-VT', 'START-053-T', 'START-053']),
        'START-053',
      );
      expect(scrapeWorkCodesEqual('START-053-VR', 'START-053'), isFalse);
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
