#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

app="$PWD/build/Pulse.app"
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
archive="$PWD/build/$release_name.zip"
staging="$(mktemp -d "$PWD/build/.pulse-package.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/$release_name"
staged_app="$staging/$release_name/Pulse.app"
# Copy only file contents, excluding Finder metadata and extended attributes.
ditto --norsrc --noextattr --noacl "$app" "$staged_app"
ditto --norsrc --noextattr --noacl scripts/Release-ReadMe.txt "$staging/$release_name/ReadMe.txt"
# Also sanitize older local builds before signing this preview copy.
strip -S "$staged_app/Contents/MacOS/Pulse"
codesign --force --sign - "$staged_app"
codesign --verify --deep --strict "$staged_app"
ditto --norsrc --noextattr --noacl -c -k --keepParent "$staging/$release_name" "$archive"
unzip -tq "$archive"
(
    cd build
    shasum -a 256 "$release_name.zip" > "$release_name.zip.sha256"
)
echo "Packaged $archive"
echo "Preview package: locally signed, not notarized."
