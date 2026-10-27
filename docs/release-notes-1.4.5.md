# AVACA 1.4.5

AVACA 1.4.5 removes the unavailable Minnano source and makes the remaining
actress metadata sources explicit and migratable.

## Highlights

- Removed Minnano scraping, connection checks, image routing, localization, and
  source-specific tests.
- Made AV-Wiki the default source for actress details and aliases, while keeping
  AVBase as the selectable alternative.
- Kept JavBus for works, category evidence, and image verification workflows.
- Migrated legacy Minnano and JavBus actress-source settings and queued records
  to AV-Wiki without discarding existing data.
- Fixed fill-missing-only re-scrapes so complete existing works are skipped
  before detail requests.

## Release assets

- `avaca-1.4.5-arm64-v8a.apk`
- `avaca-1.4.5-arm64-v8a.apk.sha256`
- `avaca-1.4.5.zip`
- `avaca-1.4.5.zip.sha256`
