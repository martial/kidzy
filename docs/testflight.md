# TestFlight

What Martial does once (only he can):

1. Confirm the paid Apple Developer Program at https://developer.apple.com/account.
2. App Store Connect → Apps → New App: iOS, name « Kidzy », primary language French, bundle id
   `com.screenclub.kidzy` (create it in Identifiers if offered), SKU `kidzy`.
3. Users and Access → Integrations → App Store Connect API → Team Keys → Generate API Key:
   name « kidzy », access **App Manager**. Download the `.p8` (possible once) to
   `~/.config/kidzy/AuthKey_<KEYID>.p8`, `chmod 600` it, and write
   `~/.config/kidzy/asc.env`:

   ```
   ASC_KEY_ID=<KEYID>
   ASC_ISSUER_ID=<issuer id shown at the top of the Integrations page>
   ASC_KEY_PATH=/Users/screen-club/.config/kidzy/AuthKey_<KEYID>.p8
   ```

Then every release is `ios/scripts/archive-upload.sh` (see the `release-testflight` skill).
After the first upload: TestFlight tab → fill « Beta App Information » (contact e-mail,
privacy policy URL can be « none » for internal testing) → Internal Testing → create a group
« Famille » with Martial's Apple ID. Internal builds need no review. Install the TestFlight app on
the phone, accept the invitation e-mail, install Kidzy.

Build numbers come from `git rev-list --count HEAD`, so commit before uploading.
