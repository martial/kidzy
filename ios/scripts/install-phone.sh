#!/bin/sh
# Build a Debug Kidzy and install + launch it on Martial's iPhone over USB.
# The phone must be unlocked, paired, with Developer Mode on.
set -eu
cd "$(dirname "$0")/.."
DEVICE="${KIDZY_DEVICE:-2E8FC42D-20FF-5F98-9EB0-B518E89EAA61}"
DD="$PWD/build/dd"
xcodebuild -project Kidzy/Kidzy.xcodeproj -scheme Kidzy -configuration Debug \
  -destination "platform=iOS,id=$DEVICE" -derivedDataPath "$DD" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  build 2>&1 | grep -E 'error:|warning: .*(deprecated|unused)|BUILD (SUCCEEDED|FAILED)' || true
APP="$DD/Build/Products/Debug-iphoneos/Kidzy.app"
[ -d "$APP" ] || { echo "no app bundle at $APP" >&2; exit 1; }
xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --device "$DEVICE" com.screenclub.kidzy
