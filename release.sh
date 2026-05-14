#!/usr/bin/env bash
# Production build. If APPLE_TEAM_ID, APPLE_ID, APPLE_APP_PASSWORD are all set
# in the environment, perform Developer ID signing, notarytool submission, and
# staple. Otherwise fall back to ad-hoc and emit a clear warning. Always emits
# ClaudeMDSwitcher-v<VERSION>-arm64.zip as the final release artifact.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=""
BUILD=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --build)
            BUILD="$2"
            shift 2
            ;;
        *)
            echo "Unknown arg: $1" >&2
            echo "Usage: $0 [--version X.Y.Z] [--build N]" >&2
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
if [[ -n "$VERSION" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
fi
if [[ -n "$BUILD" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"
fi

# Determine version for artifact naming. Prefer the --version arg; otherwise
# read whatever ended up in the bundled plist so the artifact name still has
# a sensible value.
if [[ -z "$VERSION" ]]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
fi

# Generate the AppIcon.icns (task #9). The script is idempotent and fast.
if [[ -x scripts/generate_icon.swift ]]; then
    ./scripts/generate_icon.swift
elif [[ -f scripts/generate_icon.swift ]]; then
    swift scripts/generate_icon.swift
fi

RELEASE_ZIP="ClaudeMDSwitcher-v${VERSION}-arm64.zip"
rm -f "$RELEASE_ZIP"

if [[ -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
    # Pick the Developer ID Application identity. If DEVELOPER_NAME is set,
    # use the explicit form "Developer ID Application: <NAME> (<TEAM_ID>)";
    # otherwise auto-pick the one in the keychain matching APPLE_TEAM_ID.
    if [[ -n "${DEVELOPER_NAME:-}" ]]; then
        IDENTITY="Developer ID Application: ${DEVELOPER_NAME} (${APPLE_TEAM_ID})"
    else
        MATCH=$(security find-identity -v -p codesigning | awk -v t="$APPLE_TEAM_ID" '$0 ~ "Developer ID Application" && $0 ~ t {print; exit}')
        if [[ -z "$MATCH" ]]; then
            echo "ERROR: No Developer ID Application identity found for APPLE_TEAM_ID=$APPLE_TEAM_ID in keychain." >&2
            exit 1
        fi
        IDENTITY=$(printf "%s" "$MATCH" | sed -E 's/.*"(Developer ID Application:[^"]+)".*/\1/')
    fi
    echo "Signing with: $IDENTITY"
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"

    NOTARIZE_ZIP="ClaudeMDSwitcher-notarize.zip"
    rm -f "$NOTARIZE_ZIP"
    /usr/bin/ditto -c -k --keepParent "$APP" "$NOTARIZE_ZIP"

    echo "Submitting to notarytool (this can take several minutes)..."
    xcrun notarytool submit "$NOTARIZE_ZIP" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --wait

    echo "Stapling..."
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"

    rm -f "$NOTARIZE_ZIP"
    /usr/bin/ditto -c -k --keepParent "$APP" "$RELEASE_ZIP"
    echo "Built: $(pwd)/$RELEASE_ZIP (Developer ID signed + notarized + stapled)"
else
    # ANSI yellow for the warning so it's hard to miss in CI logs.
    Y='\033[33m'; R='\033[0m'
    printf "${Y}⚠ Ad-hoc signing — Gatekeeper will warn users on first launch.${R}\n" >&2
    printf "${Y}⚠ Set APPLE_TEAM_ID/APPLE_ID/APPLE_APP_PASSWORD to enable notarization.${R}\n" >&2
    codesign --force --deep --sign - "$APP"
    /usr/bin/ditto -c -k --keepParent "$APP" "$RELEASE_ZIP"
    echo "Built: $(pwd)/$RELEASE_ZIP (ad-hoc signed — NOT notarized)"
fi
