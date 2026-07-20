# Notarizing Marmot (maintainer guide)

Notarization removes the "Open Anyway" dance for every new user — the single biggest install friction. It requires the Apple Developer Program ($99/year). Marmot stays free for users either way.

## One-time setup

1. **Enroll**: https://developer.apple.com/programs/enroll/ (personal account is fine).
2. **Create a Developer ID Application certificate** (no Xcode needed):
   - Keychain Access → Certificate Assistant → Request a Certificate From a Certificate Authority → save to disk.
   - developer.apple.com → Certificates → **+** → *Developer ID Application* → upload the request → download the `.cer` → double-click to install in your Keychain.
   - Find your identity string: `security find-identity -v -p codesigning` → looks like `Developer ID Application: Your Name (TEAMID)`.
3. **App-specific password** for notarytool: appleid.apple.com → Sign-In and Security → App-Specific Passwords.
4. **Store credentials once**:

   ```sh
   xcrun notarytool store-credentials marmot-notary \
     --apple-id you@example.com --team-id TEAMID \
     --password xxxx-xxxx-xxxx-xxxx
   ```

## Per-release flow

Replace the ad-hoc signing step with Developer ID + hardened runtime, then notarize the zip and staple the app:

```sh
# 1. Build the bundle as usual (Makefile), but sign for real:
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  Marmot.app/Contents/Frameworks/Sparkle.framework
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: Your Name (TEAMID)" Marmot.app

# 2. Zip and submit (usually completes in a few minutes):
ditto -c -k --keepParent Marmot.app Marmot-x.y.z.zip
xcrun notarytool submit Marmot-x.y.z.zip --keychain-profile marmot-notary --wait

# 3. Staple the ticket to the app, then build the FINAL zip:
xcrun stapler staple Marmot.app
rm Marmot-x.y.z.zip
ditto -c -k --keepParent Marmot.app Marmot-x.y.z.zip
```

The final zip (post-staple) is what gets the Sparkle EdDSA signature, the GitHub release attachment, and the cask SHA — same ritual as today from that point on.

## After the first notarized release

- Remove the "Open Anyway" section from the README and the cask caveats.
- Sparkle is unaffected: EdDSA signing is independent, and Sparkle 2 works fine under the hardened runtime.
- The Makefile can automate all of this behind a `SIGN_ID` variable — ad-hoc when unset (contributors), Developer ID when set (releases). Ask Claude to wire it up when you've enrolled.

## Troubleshooting

- `notarytool` and `stapler` ship with the Command Line Tools — no full Xcode needed.
- If submission is rejected, `xcrun notarytool log <submission-id> --keychain-profile marmot-notary` shows the exact reasons (almost always a nested binary that wasn't signed with `--options runtime`).
