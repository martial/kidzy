---
name: release-testflight
description: Archive Kidzy and upload it to TestFlight with the App Store Connect API key, then what to check. Use whenever Martial says "envoie sur TestFlight", "nouvelle version", "release", "publie l'app", or asks why a build is not visible in TestFlight.
---
# Release to TestFlight

Prerequisites (Martial only, once): paid Apple Developer membership; the app record "Kidzy"
(`com.screenclub.kidzy`) in App Store Connect; an API key with role App Manager saved as
`~/.config/kidzy/AuthKey_<ID>.p8` and `~/.config/kidzy/asc.env` with `ASC_KEY_ID`,
`ASC_ISSUER_ID`, `ASC_KEY_PATH`. Never print or copy the key.

1. Bump `MARKETING_VERSION` in `ios/Kidzy/Config/App.xcconfig` if the version changes; the build
   number is `git rev-list --count HEAD`, so commit first.
2. `ios/scripts/archive-upload.sh` (or `archive-upload.sh sketches` for « Sketches for kids! ») → ends with "Upload succeeded".
3. App Store Connect → TestFlight: the build appears after processing (5-15 min). First time:
   fill "Beta App Information" and add Martial to an internal group; internal testing needs no review.
4. Common failures: missing 1024 px icon (no alpha); "Missing Compliance" (the Info.plist sets
   `ITSAppUsesNonExemptEncryption = false`, so it should not happen); build number already used
   (commit something and rerun); "Personal Team" errors mean the membership is not paid.
