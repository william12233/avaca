# AVACA 1.4.0

AVACA 1.4.0 adds Android background scraping with a foreground-service
notification and a resumable verification flow.

## Highlights

- Continue scrape jobs while AVACA is minimized or the Android screen is locked.
- Show localized ongoing notifications with phase-aware determinate or
  indeterminate progress, then remove them when the job finishes.
- Notify the user when source verification is required and open the related job
  detail when the notification is tapped.
- Keep Android 13+ notification permission handling and the existing persistent
  scrape-job recovery flow integrated with the new service.

## Release assets

- `avaca-1.4.0-arm64-v8a.apk`
- `avaca-1.4.0-arm64-v8a.apk.sha256`
- `avaca-1.4.0.zip`
- `avaca-1.4.0.zip.sha256`
