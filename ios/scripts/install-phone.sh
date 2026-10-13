#!/bin/sh
# Build a Debug Kidzy and install + launch it on Martial's iPhone (USB or Wi-Fi).
# The phone must be unlocked, paired, with Developer Mode on. KIDZY_DEVICE is the UDID.
set -eu
cd "$(dirname "$0")/.."
DEVICE="${KIDZY_DEVICE:-00008120-0002499C3492201E}"
DD="$PWD/build/dd"
STATE=$(xcrun devicectl list devices 2>/dev/null | grep -i "iPhone de Martial\|2E8FC42D-20FF-5F98-9EB0-B518E89EAA61" | grep -oE 'unavailable|available|connected' | head -1)
if [ -z "$STATE" ] || [ "$STATE" = "unavailable" ]; then
  echo "iPhone not reachable (state: ${STATE:-not listed}): plug it in with USB or wake it on the same Wi-Fi, unlock it, then retry." >&2
  exit 2
fi
xcodebuild -project Kidzy/Kidzy.xcodeproj -scheme Kidzy -configuration Debug \
  -destination "platform=iOS,id=$DEVICE" -derivedDataPath "$DD" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  build 2>&1 | grep -E 'error:|warning: .*(deprecated|unused)|BUILD (SUCCEEDED|FAILED)' || true
APP="$DD/Build/Products/Debug-iphoneos/Kidzy.app"
[ -d "$APP" ] || { echo "no app bundle at $APP" >&2; exit 1; }
xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --terminate-existing --device "$DEVICE" com.screenclub.kidzy
