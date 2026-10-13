#!/bin/sh
# Archive a Release build and upload it to App Store Connect (TestFlight).
# Needs ~/.config/kidzy/asc.env with ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (the .p8).
set -eu
cd "$(dirname "$0")/.."
ENV="${HOME}/.config/kidzy/asc.env"
[ -f "$ENV" ] || { echo "missing $ENV (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH)" >&2; exit 1; }
# shellcheck disable=SC1090
. "$ENV"
: "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}" "${ASC_KEY_PATH:?}"
[ -f "$ASC_KEY_PATH" ] || { echo "missing key file $ASC_KEY_PATH" >&2; exit 1; }
BUILD="$(git rev-list --count HEAD)"
ARCHIVE="$PWD/build/Kidzy.xcarchive"
rm -rf "$ARCHIVE" "$PWD/build/export"
echo "archiving build $BUILD"
xcodebuild archive -project Kidzy/Kidzy.xcodeproj -scheme Kidzy -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  2>&1 | grep -E 'error:|ARCHIVE (SUCCEEDED|FAILED)'
echo "uploading"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist ExportOptions.plist \
  -exportPath "$PWD/build/export" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  2>&1 | grep -E 'error:|Upload succeeded|EXPORT (SUCCEEDED|FAILED)'
