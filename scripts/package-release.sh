#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

app="${PULSE_APP_PATH:-$PWD/build/Pulse.app}"
if [[ ! -x "$app/Contents/MacOS/Pulse" ]]; then
    echo "Build the app first with ./scripts/build-app.sh" >&2
    exit 1
fi
if [[ "$(lipo -archs "$app/Contents/MacOS/Pulse")" != "arm64" ]]; then
    echo "This release package requires an Apple silicon (arm64) build." >&2
    exit 1
fi
codesign --verify --deep --strict "$app"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
if [[ ! "$version" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    echo "Expected a numeric app version." >&2
    exit 1
fi

release_name="Pulse-$version-AppleSilicon-Preview"
signed=false
if codesign -dv --verbose=4 "$app" 2>&1 | /usr/bin/grep -q 'Authority=Developer ID Application:'; then
    signed=true
    xcrun stapler validate "$app"
    spctl --assess --type execute "$app"
    release_name="Pulse-$version-AppleSilicon"
fi
archive="$PWD/build/$release_name.zip"
staging="$(mktemp -d "$PWD/build/.pulse-package.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/$release_name"
staged_app="$staging/$release_name/Pulse.app"
# Copy only file contents, excluding Finder metadata and extended attributes.
ditto --norsrc --noextattr --noacl "$app" "$staged_app"
ditto --norsrc --noextattr --noacl scripts/Release-ReadMe.txt "$staging/$release_name/ReadMe.txt"
# Preserve Developer ID signatures and notarization tickets. Preview builds can
# be sanitized and re-signed; Developer ID builds are stripped before signing.
if [[ "$signed" == false ]]; then
    strip -S "$staged_app/Contents/MacOS/Pulse"
    codesign --force --sign - "$staged_app"
else
    xcrun stapler validate "$staged_app"
fi
codesign --verify --deep --strict "$staged_app"
if strings "$staged_app/Contents/MacOS/Pulse" | /usr/bin/grep -E '/Users/[^/]+/|/private/var/folders/' > /dev/null; then
    echo "Package rejected: executable contains absolute developer paths." >&2
    exit 1
fi
ditto --norsrc --noextattr --noacl -c -k --keepParent "$staging/$release_name" "$archive"
unzip -tq "$archive"
(
    cd build
    shasum -a 256 "$release_name.zip" > "$release_name.zip.sha256"
)
echo "Packaged $archive"
if [[ "$signed" == false ]]; then echo "Preview package: locally signed, not notarized."
else echo "Developer ID package: signature and stapled ticket verified."; fi
