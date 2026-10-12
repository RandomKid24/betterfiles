# Notarizing Butterlight and Butterfinder

Notarization is Apple scanning the apps and stamping them as safe. Once done, nobody sees the "Open Anyway"
warning. It needs a paid **Apple Developer Program** membership ($99 a year).

## One-time setup
1. Join the Apple Developer Program, then in Xcode (Settings → Accounts → Manage Certificates) create a
   **Developer ID Application** certificate.
2. Find its name: `security find-identity -v -p codesigning`. It looks like
   `Developer ID Application: Your Name (ABCDE12345)`.
3. Make an app-specific password at appleid.apple.com, then store credentials once:
   ```bash
   xcrun notarytool store-credentials "butter-notary" --apple-id you@example.com --team-id ABCDE12345
   ```

## Every release
```bash
SIGN_ID="Developer ID Application: Your Name (ABCDE12345)" NOTARY_PROFILE="butter-notary" ./notarize.sh 1.3.0
```
This builds universal apps signed with the hardened runtime, packs the DMG, submits it to Apple, waits for the
verdict and staples the ticket. Upload `dist/Butterlight-Butterfinder-1.3.0.dmg` to the GitHub release.

Then you can drop the "Open Anyway" instructions from the README and release notes.
