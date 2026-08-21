# Changelog

## 0.9.4 - 2026-08-21

- Normalized V, T, and VT edition suffixes across JavBus and multi-source
  scraping so special editions collapse to the ordinary work identity and the
  ordinary detail page is fetched.
- Added deterministic leading-one DMM family hints for START and STARS work
  images, including numeric-prefix work codes.
- Broadened approved DMM evidence parsing for `pics.dmm.co.jp`, `pics`, and
  `pics_dig` route forms while canonicalizing learned downloads safely.

## 0.9.3 - 2026-08-21

- Fixed AvBase and combined JavBus/AvBase scrape progress so each source
  advances its detail counter instead of remaining at zero.
- Filtered AvBase navigation links from talent-page work collection so only
  actual work cards enter the scrape pipeline.
- Added regression coverage for source-local progress and AvBase work-link
  parsing.

## 0.9.2 - 2026-08-21

- Added AvBase as a guarded actress-details and works source, including
  pagination, metadata parsing, DMM avatar/image evidence, and deterministic
  merging with JavBus results.
- Extended learned work-image routing with evidence-derived descriptors,
  persisted candidate health, safe validation, and route-aware downloads.
- Refined source selection, scrape progress, responsive Settings and Works
  layouts, localization, and regression coverage for the new scrape and image
  flows.

## 0.9.1 - 2026-08-20

- Added learned Prefix-based work-image routing with automatic probing,
  per-Prefix persistence, manual family overrides, and safe import/export
  management from Settings.
- Hardened image probing and failure classification across supported DMM and
  MGStage families, including bounded concurrent downloads and validation that
  prevents invalid or placeholder images from being learned.
- Refined scrape progress, responsive dialogs, and localized scraping status
  text, with expanded coverage for routing, scraping, Settings, and Works UI.

## 0.9.0 - 2026-08-16

- Added related-performer metadata for works, including source links and
  local actress/alias resolution for navigation to local actress pages.
- Extended JavBus performer parsing and work persistence/merge handling while
  preserving source scope and avoiding duplicate performer records.
- Reworked Works scrape progress and result dialogs to separate actress
  details, work-source progress, and image-download outcomes with explicit
  partial-failure and completion states.
- Refined responsive Works and Work Detail layouts, related-actress
  navigation, Traditional Chinese/English/Japanese localization, and test
  coverage.

## 0.8.7 - 2026-08-15

- Made work-image routing metadata-only, added the Seikyouiku MGStage route,
  and expanded approved MGStage endpoint validation.
- Fixed scrape search-error handling when a later alias succeeds and reported
  streaming image/save progress with accurate totals and outcomes.
- Refined Detail and Works responsive layouts, including tappable private notes,
  full-row work/alias actions, and immediate alias persistence.
- Persisted scrape-prefix changes while editing settings and aligned the dialog
  controls with the current rounded visual style.

## 0.8.6 - 2026-08-15

- Changed the default JavBus detail-request interval to 600 milliseconds while
  keeping image downloads bounded and parallel with the next detail request.
- Made Minnano AV the default actress-details source and JavBus the works source;
  removed title-based and cross-source work merging rules.
- Routed approved DMM and MGStage work-image URLs from maker/publisher metadata
  and bounded page evidence without using JavBus covers or prefix-based guesses.

## 0.8.5 - 2026-08-14

- Updated scrape progress to show source names during collection and detail
  scraping, then show the work code only while downloading images.
- Started Minnano AV and JavBus work pipelines concurrently while keeping
  detail requests sequential within each source.
- Reworked work deduplication around exact titles, explicit `[特典版]` handling,
  scraped detail codes, and a Rebecca-specific shortest-code rule so
  `REBD-975` wins over `H_346REBD00975` without merging unrelated numeric codes.
- Added coverage for source overlap, title and code deduplication, progress
  phases, and image downloads receiving the resolved work code.

## 0.8.4 - 2026-08-14

- Generalized work-code canonicalization so numeric-leading aliases and differently formatted prefixes resolve to the same canonical `LETTERS-NUMBER` code without merging different numeric cores.
- Fixed Minnano AV actress scraping for direct profile pages such as 河北彩花 by resolving safe canonical actress links and preserving exact-name parsing.
- Replaced the portable Windows script updater with a native `avaca_update.exe` helper, verified archive extraction, path traversal protection, rollback, and startup validation while preserving the user's AVACA data directory.
- Added focused coverage for canonical work-code deduplication, Minnano direct profiles, and Windows update archive validation.

## 0.8.3 - 2026-08-13

- Parallelized all-source work scraping so Minnano AV and JavBus search in
  parallel, then merge results by canonical work code.
- Normalized equivalent work-code spellings such as `1start00408` and
  `start-408` to the same work while preserving deterministic Minnano AV ->
  JavBus field priority.
- Improved scrape cancellation, source failure reporting, image handling, and
  completion/result dialogs with explicit confirmation before dismissal.
- Added coverage for cross-source deduplication, cancellation cleanup, image
  source policy, verification dialogs, and responsive UI behavior.

## 0.8.2 - 2026-08-13

- Added Minnano AV (`https://www.minnano-av.com/`) as a scraping source for
  actress details and works.
- Added independent source selection: Minnano AV or JavBus for details, and a
  single source or canonical-code deduplicated aggregation for works.
- Hardened Unicode work-code normalization, source failure reporting, image
  host restrictions, cancellation, and cross-source detail-code validation.
- Verified the new settings flow on Android phone/tablet targets and retained
  the existing JavBus scraping behavior.

## 0.8.1 - 2026-08-13

- Raised the Android release build-number to 2026 so 0.8.1 can update
  manually built 0.7.10 packages that used build-number 2025.
- Improved scrape-source settings, DMM image fallback handling, and adaptive
  app-bar back-button behavior across detail pages.
- Kept versioned GitHub Release assets, SHA-256 verification, and portable
  Windows update packaging for the 0.8.1 release.

## 0.8.0 - 2026-08-13

- Added Settings > Other > Software update with current/latest version
  details, automatic checks, manual checks, and an update-now dialog.
- Added stable GitHub Release downloads with exact versioned asset names and
  SHA-256 verification for Android ARM64 and Windows x64 portable builds.
- Added Android system package installation and a Windows portable updater
  that replaces only the application bundle while preserving user data.
- Added post-update cache cleanup, rollback safeguards, Works code search, and
  responsive UI coverage for the updated settings and works flows.
- Added release checks for asset naming, checksums, and Android version
  metadata, with Android versionCode values starting at 30 and increasing per
  release.

## 0.7.10 - 2026-08-12

- Added tag-driven GitHub release packaging for versioned ARMv8-A Android APK
  and Windows x64 portable archives.
- Added a portable-folder updater command that replaces only the application
  bundle while preserving the existing %LOCALAPPDATA%\AVACA database and
  managed images.
- Standardized release asset names to include the application version, such
  as "avaca-0.7.10-arm64-v8a.apk" and "avaca-0.7.10.zip".

## 0.7.7 - 2026-08-10

- Added ZIP data export and import for actresses, works, details, and all
  managed images, with portable archive references and safe staging.
- Added duplicate-actress import resolution with work counts, avatar previews,
  and an in-app choice flow for keeping existing or imported details.
- Added the third Settings category for data transfer with localized,
  responsive controls consistent with the rest of the app.

## 0.7.5 - 2026-08-10

- Rebalanced responsive Detail and Edit layouts across compact and wide screens.
- Unified adaptive spacing and card geometry across Works, Work Detail,
  Settings, and Add while restoring the Home gallery's original card flow.
- Added CJK-aware adaptive UI Golden coverage and fixed the phone-landscape
  filter sheet overflow.
- Configured Android release signing and guarded plugin registration for
  current release builds.

## 0.7.3 - 2026-08-04

- Refined scrape settings into compact switch and count rows with consistent
  spacing, a collapsible excluded-prefix editor, and constrained-screen
  scrolling.
- Updated application text buttons to use the secondary text color while
  preserving emphasized button contrast colors.

## 0.7.2 - 2026-08-03

- Unified detail-page Edit and Delete actions under a localized overflow menu;
  edit mode now keeps only Save in the app bar, and Back cancels unsaved edits
  while restoring the persisted detail and photo state.
- Added theme-aware, content-sized Snackbar styling with configurable light,
  dark, and custom-palette backgrounds, and applied the shared presentation to
  detail and Works feedback.
- Hardened custom-theme preference loading against malformed JSON, unknown
  keys, and invalid color values.
- Aligned bundled-font tests with the current `w400` minimum application font
  weight.

## 0.7.0 - 2026-08-03

- Added actress alias management with multiple aliases per actress and
  case-insensitive alias normalization.
- Scraping now checks the canonical actress name and every saved alias,
  retries shared sources after transient failures, and deduplicates works by
  source and normalized work code.
- Added long-press multi-selection on the Works page and global work deletion
  with transactional actress-link removal and managed-image cleanup that
  preserves shared files.

## 0.6.10 - 2026-08-03

- Added JavBus scraping for actress profiles and works, including localized
  scrape controls, a configurable multi-actress threshold, and exact-name
  merging across duplicate actress pages.
- Added duplicate work-code filtering and normalization for trailing `-V`,
  `-T`, and `-VT` suffixes so variants such as STARS codes resolve correctly.
- Added safe work-image fallback attempts in the approved order: original,
  leading `1`, leading `1` with trailing `v`, and trailing `h2`, while
  rejecting placeholder images and unsafe URLs.
- Added actress avatar session/Referer handling, work detail image display,
  cleanup and database migration improvements, birthday persistence, and
  related UI/localization updates.
- Preserved the existing typography adjustments, including the manually
  selected `w400` minimum font weight.

## 0.5.7 - 2026-07-29

- Added compact, immediately applied filtering with created, modified, and
  actress-age sorting.
- Added birthday persistence, age display, and a three-wheel birthday picker
  to the detailed profile editor.
- Refined detail-page spacing, controls, tags, photo actions, and responsive
  layouts to match the rest of the app.
- Prevented the keyboard from unexpectedly reopening after physical back
  navigation.

## 0.5.2 - 2026-07-29

- Reworked settings into categorized, expandable pages with independent custom
  colors, dark-only AMOLED controls, and localized touch feedback.
- Improved responsive gallery spacing, profile layout, and Works navigation.
- Added bundled Traditional Chinese typography and broader widget coverage.
