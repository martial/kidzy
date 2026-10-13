#!/bin/sh
# Build a Debug app and install + launch it on Martial's iPhone (USB or Wi-Fi).
# Usage: install-phone.sh [kidzy|sketches]   (default kidzy)
# The phone must be unlocked, paired, with Developer Mode on. KIDZY_DEVICE is the UDID.
set -eu
cd "$(dirname "$0")/.."
case "${1:-kidzy}" in
  kidzy) SCHEME=Kidzy; BUNDLE=com.screenclub.kidzy ;;
  sketches) SCHEME=SketchesForKids; BUNDLE=com.screenclub.sketchesforkids ;;
  *) echo "usage: $0 [kidzy|sketches]" >&2; exit 2 ;;
esac
DEVICE="${KIDZY_DEVICE:-00008120-0002499C3492201E}"
DD="$PWD/build/dd"
STATE=$(xcrun devicectl list devices 2>/dev/null | grep -i "iPhone de Martial\|2E8FC42D-20FF-5F98-9EB0-B518E89EAA61" | grep -oE 'unavailable|available|connected' | head -1)
if [ -z "$STATE" ] || [ "$STATE" = "unavailable" ]; then
  echo "iPhone not reachable (state: ${STATE:-not listed}): plug it in with USB or wake it on the same Wi-Fi, unlock it, then retry." >&2
  exit 2
fi
xcodebuild -project Kidzy.xcodeproj -scheme "$SCHEME" -configuration Debug \
  -destination "platform=iOS,id=$DEVICE" -derivedDataPath "$DD" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  build 2>&1 | grep -E 'error:|warning: .*(deprecated|unused)|BUILD (SUCCEEDED|FAILED)' || true
APP="$DD/Build/Products/Debug-iphoneos/$SCHEME.app"
[ -d "$APP" ] || { echo "no app bundle at $APP" >&2; exit 1; }
xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --terminate-existing --device "$DEVICE" "$BUNDLE"
