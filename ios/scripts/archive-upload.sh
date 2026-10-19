#!/bin/sh
# Archive a Release build and upload it to App Store Connect (TestFlight).
# Usage: [BETA=1] archive-upload.sh [kidzy|sketches]   (default kidzy)
# Signs in with ~/.config/kidzy/asc.env (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH = the .p8) when it
# exists, otherwise with the Apple Account Xcode is signed in to (Xcode → Settings → Accounts).
# BETA=1 compiles the BETA condition: a TestFlight-only build with every toy open (Store.swift).
# Never submit a BETA build for review.
set -eu
cd "$(dirname "$0")/.."
case "${1:-kidzy}" in
  kidzy) SCHEME=Kidzy ;;
  sketches) SCHEME=SketchesForKids ;;
  *) echo "usage: $0 [kidzy|sketches]" >&2; exit 2 ;;
esac
AUTH=""
ENV="${HOME}/.config/kidzy/asc.env"
if [ -f "$ENV" ]; then
  # shellcheck disable=SC1090
  . "$ENV"
  : "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}" "${ASC_KEY_PATH:?}"
  [ -f "$ASC_KEY_PATH" ] || { echo "missing key file $ASC_KEY_PATH" >&2; exit 1; }
  AUTH="-authenticationKeyPath $ASC_KEY_PATH -authenticationKeyID $ASC_KEY_ID -authenticationKeyIssuerID $ASC_ISSUER_ID"
else
  echo "no $ENV: using the Apple Account signed in to Xcode"
fi
BUILD="$(git rev-list --count HEAD)"
ARCHIVE="$PWD/build/$SCHEME.xcarchive"
rm -rf "$ARCHIVE" "$PWD/build/export"
if [ "${BETA:-0}" = 1 ]; then
  echo "archiving beta build $BUILD (TestFlight only)"
  set -- 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) BETA'
else
  echo "archiving build $BUILD"
  set --
fi
# shellcheck disable=SC2086
xcodebuild archive -project Kidzy.xcodeproj -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$BUILD" "$@" \
  -allowProvisioningUpdates $AUTH \
  2>&1 | grep -E 'error:|ARCHIVE (SUCCEEDED|FAILED)'
[ -d "$ARCHIVE" ] || { echo "archive failed" >&2; exit 1; }
echo "uploading"
# shellcheck disable=SC2086
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist ExportOptions.plist \
  -exportPath "$PWD/build/export" \
  -allowProvisioningUpdates $AUTH \
  2>&1 | grep -E 'error:|Upload succeeded|EXPORT (SUCCEEDED|FAILED)'
