#!/bin/bash
# build.sh
# Builds "Desktop Stickman.app" in this folder from the sources in Sources/.
#
#   bash build.sh              for this Mac
#   bash build.sh universal    for both Apple silicon and Intel Macs
#
# Needs Apple's command line developer tools (the Swift compiler). If they are
# missing, macOS offers to install them; run this script again afterwards.

set -euo pipefail
cd "$(dirname "$0")"

APP="Desktop Stickman.app"
EXE="Stick figure"          # the name Activity Monitor shows for him
MIN="13.0"                  # oldest macOS he runs on

if ! xcrun --find swiftc >/dev/null 2>&1; then
    echo "The Swift compiler is not installed."
    echo "Install Apple's command line tools (a window should pop up), then run this script again."
    xcode-select --install 2>/dev/null || true
    exit 1
fi

archs=("$(uname -m)")
if [ "${1:-}" = "universal" ]; then archs=(arm64 x86_64); fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

for a in "${archs[@]}"; do
    echo "Compiling for $a..."
    xcrun swiftc -O -swift-version 5 -target "$a-apple-macos$MIN" -o "$tmp/$a" Sources/*.swift
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [ "${#archs[@]}" -gt 1 ]; then
    lipo -create -output "$APP/Contents/MacOS/$EXE" "${archs[@]/#/$tmp/}"
else
    cp "$tmp/${archs[0]}" "$APP/Contents/MacOS/$EXE"
fi
cp -X Info.plist "$APP/Contents/Info.plist"
cp -X stickman.icns "$APP/Contents/Resources/stickman.icns"

# built here, so nothing about it came from the internet, and signed for this
# Mac only (Apple silicon will not run a program with no signature at all)
xattr -cr "$APP" 2>/dev/null || true
codesign --force --sign - "$APP"

echo
echo "Built $APP"
echo "Start him by double-clicking it, or:  open \"$APP\""
