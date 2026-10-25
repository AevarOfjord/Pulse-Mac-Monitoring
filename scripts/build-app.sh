#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
swift build -c release --arch arm64 --disable-sandbox --cache-path "$PWD/.build/cache" --product Pulse
bin_dir="$(swift build -c release --arch arm64 --disable-sandbox --cache-path "$PWD/.build/cache" --show-bin-path)"
app="${PULSE_APP_PATH:-$PWD/build/Pulse.app}"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/Pulse" "$app/Contents/MacOS/Pulse"
if [[ "$(lipo -archs "$app/Contents/MacOS/Pulse")" != "arm64" ]]; then
    echo "Expected an Apple silicon (arm64) executable." >&2
    exit 1
fi
cp scripts/Info.plist "$app/Contents/Info.plist"
swift scripts/make-icon.swift "$app/Contents/Resources/AppIcon.icns"
# Remove debug symbol records containing the developer's absolute build paths.
strip -S "$app/Contents/MacOS/Pulse"
if [[ -n "${PULSE_SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$PULSE_SIGN_IDENTITY" "$app"
else
    codesign --force --sign - "$app"
fi
codesign --verify --deep --strict "$app"
echo "Built $app"
if [[ "${1:-}" == "--open" ]]; then open "$app"; fi
