#!/usr/bin/env bash
# Fast local dev build — ad-hoc signed, no notarization.
# Use ./release.sh for production builds with Developer ID + notarization.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=""
SHORT_VERSION=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            SHORT_VERSION="$2"
            shift 2
            ;;
        --build)
            VERSION="$2"
            shift 2
            ;;
        *)
            echo "Unknown arg: $1" >&2
            echo "Usage: $0 [--version 1.0.0] [--build 1]" >&2
            exit 2
            ;;
    esac
done

APP="ClaudeMDSwitcher.app"
BIN=".build/release/ClaudeMDSwitcher"

swift build -c release --arch arm64

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClaudeMDSwitcher"
cp Sources/ClaudeMDSwitcher/Info.plist "$APP/Contents/Info.plist"

PLIST="$APP/Contents/Info.plist"
if [[ -n "$SHORT_VERSION" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SHORT_VERSION" "$PLIST"
fi
if [[ -n "$VERSION" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$PLIST"
fi

# Generate the AppIcon.icns into Contents/Resources.
if [[ -f scripts/generate_icon.swift ]]; then
    swift scripts/generate_icon.swift
fi

codesign --force --deep --sign - "$APP"

echo "Built: $(pwd)/$APP (ad-hoc signed)"
