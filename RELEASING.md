# Releasing Pulse

## Locally signed preview (available without a Developer account)

1. Quit the running local Pulse build.
2. Run `./scripts/test.sh` and `swift run --disable-sandbox PulseDiagnostics --smoke`.
3. Run `./scripts/build-app.sh`, then `./scripts/package-release.sh`.
4. Verify the ZIP and `.sha256` in `build/`. Test the packaged app, including first launch from a real download.
5. Publish only the source tracked by Git and the ZIP/checksum assets. Do not publish local exports, build caches, diagnostic logs, keychain files, or the entire working directory.

Label the release **preview, locally signed, not notarized**. Do not claim that ad-hoc signing is an Apple Developer ID signature. CI builds are previews too. Version and build numbers live in `scripts/Info.plist`.

For a separate candidate bundle, set `PULSE_APP_PATH` to an absolute `.app` path when running both `build-app.sh` and `package-release.sh`. The default remains `build/Pulse.app`. This allows packaging a candidate without replacing a running development app.

## Developer ID signing and notarization (requires membership)

This path is prepared for future use and has not been exercised by the current maintainer, who has no Developer ID identity. Follow [Apple's distribution documentation](https://developer.apple.com/macos/distribution/) to obtain a Developer ID Application certificate. Keep private keys and notarization credentials out of Git.

1. Install the Developer ID Application identity in your login keychain. Use `security find-identity -v -p codesigning` to confirm it exists.
2. Store notarization credentials using interactive `xcrun notarytool store-credentials` with a chosen keychain profile. Enter secrets interactively; do not put passwords in scripts, terminal commands saved to history, issue descriptions, or CI logs.
3. Build with the identity's name or fingerprint:

   ```sh
   PULSE_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' ./scripts/build-app.sh
   ```

   The script strips debug records before signing, enables the hardened runtime and timestamp, then verifies the signature. No entitlements or privileged helper are requested.

4. Submit using the saved profile:

   ```sh
   PULSE_NOTARY_PROFILE='pulse-notary' ./scripts/notarize.sh
   ```

   The script submits a temporary ZIP, requires Apple's `Accepted` status, staples and validates the ticket, and checks Gatekeeper assessment. Submission failure stops the script. If Apple rejects the submission, inspect the log with `xcrun notarytool log` and the returned submission ID.

5. Run `./scripts/package-release.sh`. Developer ID builds must pass stapler/Gatekeeper checks and retain their existing signature. They are packaged as `Pulse-2.0-AppleSilicon.zip`. The script never replaces a Developer ID signature with an ad-hoc one.
6. Verify the extracted copy on a second physical Mac before removing preview status. Test launch-at-login and notification permission there as well. Install from the final downloaded artifact, not just the local build.

Notarization and cross-device validation remain release gates for a standard public distribution. No Apple account or paid membership is required to use the preview or build it locally.
