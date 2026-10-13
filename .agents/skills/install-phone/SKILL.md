---
name: install-phone
description: Build the Kidzy app and install it on Martial's iPhone over USB with devicectl. Use whenever Martial says "installe l'app", "mets-la sur le téléphone", "je veux tester sur l'iPhone", or after any change in ios/ that he should see.
---
# Install on the iPhone

1. Phone plugged in, unlocked, Developer Mode on (`xcrun devicectl list devices` shows it paired).
2. `ios/scripts/install-phone.sh` (Debug build, automatic signing with the local team file
   `ios/Kidzy/Config/Signing.local.xcconfig`, then `devicectl install` + `launch`).
3. If signing fails: open `ios/Kidzy/Kidzy.xcodeproj` once in Xcode so it registers the device
   and refreshes the profile, then rerun the script.
4. Logs from the phone: `xcrun devicectl device process launch --console --device <id> com.screenclub.kidzy`.
Regenerate the project after editing `project.yml`: `make xcodeproj`.
