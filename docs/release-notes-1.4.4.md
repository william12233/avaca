# AVACA 1.4.4

AVACA 1.4.4 hardens source access and category filtering so scrape jobs can
finish with clearer diagnostics and fewer unresolved works.

## Highlights

- Added browser-like Minnano request headers, session-cookie handling, polite
  pacing, retry behavior, and explicit 403/429/timeout classification.
- Added exact-code AVBase, AV-Wiki, and JavBus evidence lookups for unresolved
  category filters without collecting another full actress catalog.
- Optional JavBus verification during category evidence checks no longer
  interrupts the scrape; unresolved works remain available for review.

## Release assets

- `avaca-1.4.4-arm64-v8a.apk`
- `avaca-1.4.4-arm64-v8a.apk.sha256`
- `avaca-1.4.4.zip`
- `avaca-1.4.4.zip.sha256`
