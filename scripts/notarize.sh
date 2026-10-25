#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="$PWD/build/Pulse.app"
: "${PULSE_NOTARY_PROFILE:?Set PULSE_NOTARY_PROFILE to a notarytool keychain profile.}"
if ! codesign -dv --verbose=4 "$app" 2>&1 | /usr/bin/grep -q 'Authority=Developer ID Application:'; then
    echo "Build with PULSE_SIGN_IDENTITY set to a Developer ID Application identity first." >&2
    exit 1
fi
codesign --verify --deep --strict "$app"
submission="$(mktemp -d "$PWD/build/.pulse-notary.XXXXXX")"
trap 'rm -rf "$submission"' EXIT
ditto --norsrc --noextattr --noacl -c -k --keepParent "$app" "$submission/Pulse.zip"
xcrun notarytool submit "$submission/Pulse.zip" --keychain-profile "$PULSE_NOTARY_PROFILE" --wait --output-format json > "$submission/result.json"
if [[ "$(plutil -extract status raw -o - "$submission/result.json")" != "Accepted" ]]; then
    echo "Apple did not accept this submission. Inspect the notarytool log using its submission ID." >&2
    cat "$submission/result.json"
    exit 1
fi
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
echo "Notarized and stapled. Run ./scripts/package-release.sh to package the verified app."
