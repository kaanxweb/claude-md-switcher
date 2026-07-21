#!/usr/bin/env bash
# Production arm64 build. Requires Developer ID signing and notarization;
# no unsigned or ad-hoc release artifact is ever produced.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"

usage() {
    cat >&2 <<EOF
Usage: $0 --version X.Y.Z --build N --team-id TEAMID --notary-profile PROFILE [--signing-identity IDENTITY]
EOF
}

require_option_value() {
    if [[ $# -lt 2 ]]; then
        echo "ERROR: $1 requires a value." >&2
        usage
        exit 2
    fi
    if [[ -z "$2" || "$2" == --* ]]; then
        echo "ERROR: $1 requires a value." >&2
        usage
        exit 2
    fi
}

VERSION=""
BUILD=""
TEAM_ID=""
NOTARY_PROFILE=""
REQUESTED_IDENTITY=""
APP_NAME="ClaudeMDSwitcher.app"
EXECUTABLE_NAME="ClaudeMDSwitcher"
OUTPUTS_INITIALIZED=0
CURRENT_LOG_RETAINED=0
RELEASE_SUCCEEDED=0
WORK_DIR=""
PENDING_NOTARY_LOG=""

cleanup() {
    set +e
    if [[ -n "$WORK_DIR" ]]; then
        rm -rf -- "$WORK_DIR"
    fi
    if [[ "$OUTPUTS_INITIALIZED" -eq 1 ]]; then
        rm -f -- "$PENDING_NOTARY_LOG"
        if [[ "$RELEASE_SUCCEEDED" -ne 1 ]]; then
            rm -rf -- "$PUBLIC_APP"
            rm -f -- "$PUBLIC_RELEASE_ZIP" "$PUBLIC_CHECKSUM"
        fi
        if [[ "$CURRENT_LOG_RETAINED" -ne 1 ]]; then
            rm -f -- "$PUBLIC_NOTARY_LOG"
        fi
    fi
}

initialize_release_outputs() {
    RELEASE_ZIP_NAME="ClaudeMDSwitcher-v${VERSION}-arm64.zip"
    CHECKSUM_NAME="${RELEASE_ZIP_NAME}.sha256"
    NOTARY_LOG_NAME="ClaudeMDSwitcher-v${VERSION}-arm64.notarization-log.json"
    PUBLIC_APP="$ROOT/$APP_NAME"
    PUBLIC_RELEASE_ZIP="$ROOT/$RELEASE_ZIP_NAME"
    PUBLIC_CHECKSUM="$ROOT/$CHECKSUM_NAME"
    PUBLIC_NOTARY_LOG="$ROOT/$NOTARY_LOG_NAME"
    PENDING_NOTARY_LOG="$ROOT/.${NOTARY_LOG_NAME}.pending.$$"
    OUTPUTS_INITIALIZED=1
    trap cleanup EXIT

    # The strict version makes every deletion target fixed and narrow.
    rm -rf -- "$PUBLIC_APP"
    rm -f -- "$PUBLIC_RELEASE_ZIP" "$PUBLIC_CHECKSUM" "$PUBLIC_NOTARY_LOG" "$PENDING_NOTARY_LOG"

    WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/claude-md-release.XXXXXX")
    APP="$WORK_DIR/$APP_NAME"
}

discover_version() {
    local seen=0
    local candidate=""
    local missing_value=0

    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "--version" ]]; then
            seen=$((seen + 1))
            if [[ $# -lt 2 || -z "${2:-}" || "${2:-}" == --* ]]; then
                missing_value=1
                shift
                continue
            fi
            candidate="$2"
            shift 2
            continue
        fi
        shift
    done

    if [[ "$seen" -eq 0 ]]; then
        echo "ERROR: --version is required (strict X.Y.Z format)." >&2
        usage
        exit 2
    fi
    if [[ "$seen" -ne 1 ]]; then
        echo "ERROR: --version must be provided exactly once." >&2
        exit 2
    fi
    if [[ "$missing_value" -eq 1 ]]; then
        echo "ERROR: --version requires a value." >&2
        usage
        exit 2
    fi
    if [[ ! "$candidate" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
        echo "ERROR: Version must use strict X.Y.Z format (for example, 1.2.3)." >&2
        exit 2
    fi

    VERSION="$candidate"
    initialize_release_outputs
}

# Discover and validate the only value allowed to influence output filenames.
# Once it is safe, stale outputs are invalidated before parsing anything else.
discover_version "$@"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            require_option_value "$@"
            shift 2
            ;;
        --build)
            require_option_value "$@"
            BUILD="$2"
            shift 2
            ;;
        --team-id)
            require_option_value "$@"
            TEAM_ID="$2"
            shift 2
            ;;
        --notary-profile)
            require_option_value "$@"
            NOTARY_PROFILE="$2"
            shift 2
            ;;
        --signing-identity)
            require_option_value "$@"
            REQUESTED_IDENTITY="$2"
            shift 2
            ;;
        *)
            echo "ERROR: Unknown argument: $1" >&2
            usage
            exit 2
            ;;
    esac
done

if [[ -z "$BUILD" ]]; then
    echo "ERROR: --build is required (positive numeric build number)." >&2
    usage
    exit 2
fi
if [[ ! "$BUILD" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: Build number must be a positive integer." >&2
    exit 2
fi
if [[ -z "$TEAM_ID" ]]; then
    echo "ERROR: --team-id is required (10 uppercase alphanumeric characters)." >&2
    usage
    exit 2
fi
if [[ ! "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "ERROR: Team ID must contain exactly 10 uppercase alphanumeric characters." >&2
    exit 2
fi
if [[ -z "$NOTARY_PROFILE" ]]; then
    echo "ERROR: --notary-profile is required and must name a local notarytool Keychain profile." >&2
    usage
    exit 2
fi
if [[ "$REQUESTED_IDENTITY" =~ ^[0-9A-Fa-f]{40}$ ]]; then
    REQUESTED_IDENTITY=$(printf '%s' "$REQUESTED_IDENTITY" | tr '[:lower:]' '[:upper:]')
fi

for command in git swift codesign security xcrun spctl ditto shasum lipo; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "ERROR: Required command not found: $command" >&2
        exit 1
    fi
done

# Confirm the named local Keychain profile and its credentials before building.
if ! xcrun notarytool history \
    --keychain-profile "$NOTARY_PROFILE" \
    --output-format json >/dev/null; then
    echo "ERROR: Notary profile '$NOTARY_PROFILE' was not found in the local Keychain or its credentials are invalid." >&2
    exit 1
fi

# A production artifact must come from an exact, signed, clean release tag.
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
    echo "ERROR: Release provenance requires a clean Git working tree, including no untracked files." >&2
    exit 1
fi
EXPECTED_TAG="v${VERSION}"
if [[ "$(git cat-file -t "refs/tags/$EXPECTED_TAG" 2>/dev/null || true)" != "tag" ]]; then
    echo "ERROR: Release tag $EXPECTED_TAG must exist as an annotated, signed tag." >&2
    exit 1
fi
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse "refs/tags/$EXPECTED_TAG^{commit}" 2>/dev/null || true)" ]]; then
    echo "ERROR: HEAD must be exactly the commit tagged $EXPECTED_TAG." >&2
    exit 1
fi
if ! git tag -v "$EXPECTED_TAG"; then
    echo "ERROR: Signature verification failed for release tag $EXPECTED_TAG." >&2
    exit 1
fi

IDENTITY_MATCHES=$(security find-identity -v -p codesigning | awk -v team="$TEAM_ID" -v requested="$REQUESTED_IDENTITY" '
    $2 ~ /^[0-9A-Fa-f]+$/ && length($2) == 40 {
        first_quote = index($0, "\"")
        if (first_quote == 0) next
        rest = substr($0, first_quote + 1)
        second_quote = index(rest, "\"")
        if (second_quote == 0) next
        name = substr(rest, 1, second_quote - 1)
        suffix = "(" team ")"
        if (index(name, "Developer ID Application:") != 1) next
        if (length(name) < length(suffix) || substr(name, length(name) - length(suffix) + 1) != suffix) next
        if (requested != "" && requested != $2 && requested != name) next
        print toupper($2) "\t" name
    }
')

IDENTITY_COUNT=$(printf '%s\n' "$IDENTITY_MATCHES" | awk 'NF { count++ } END { print count + 0 }')
if [[ "$IDENTITY_COUNT" -eq 0 ]]; then
    if [[ -n "$REQUESTED_IDENTITY" ]]; then
        echo "ERROR: Signing identity '$REQUESTED_IDENTITY' is not a valid Developer ID Application identity for Team ID $TEAM_ID." >&2
    else
        echo "ERROR: No valid Developer ID Application identity found for Team ID $TEAM_ID." >&2
    fi
    exit 1
fi
if [[ "$IDENTITY_COUNT" -ne 1 ]]; then
    echo "ERROR: Multiple Developer ID Application identities found for Team ID $TEAM_ID; pass --signing-identity with the certificate fingerprint." >&2
    exit 1
fi

SIGNING_FINGERPRINT=$(printf '%s\n' "$IDENTITY_MATCHES" | awk 'NF { print $1 }')
SIGNING_NAME=$(printf '%s\n' "$IDENTITY_MATCHES" | cut -f2-)
echo "Signing identity: $SIGNING_NAME [$SIGNING_FINGERPRINT]"
echo "Apple Team ID: $TEAM_ID"

SWIFT_BUILD_DIR="$WORK_DIR/swift-build"
swift build -c release --arch arm64 --scratch-path "$SWIFT_BUILD_DIR"
BIN_DIR=$(swift build -c release --arch arm64 --scratch-path "$SWIFT_BUILD_DIR" --show-bin-path)
BIN="$BIN_DIR/$EXECUTABLE_NAME"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$EXECUTABLE_NAME"
cp "$ROOT/Sources/ClaudeMDSwitcher/Info.plist" "$APP/Contents/Info.plist"

PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"

# Generate AppIcon.icns inside the isolated production bundle.
if [[ -x "$ROOT/scripts/generate_icon.swift" ]]; then
    (cd "$WORK_DIR" && "$ROOT/scripts/generate_icon.swift")
elif [[ -f "$ROOT/scripts/generate_icon.swift" ]]; then
    (cd "$WORK_DIR" && swift "$ROOT/scripts/generate_icon.swift")
fi

verify_developer_id_app() {
    local target="$1"
    local label="$2"
    local metadata="$WORK_DIR/${label}.codesign.txt"
    local entitlements="$WORK_DIR/${label}.entitlements.plist"
    local plist="$target/Contents/Info.plist"
    local executable="$target/Contents/MacOS/$EXECUTABLE_NAME"
    local actual_identifier actual_version actual_build actual_archs

    codesign --verify --deep --strict --verbose=2 "$target"
    codesign --display --verbose=4 "$target" 2>"$metadata"

    if ! grep -q '^Authority=Developer ID Application:' "$metadata"; then
        echo "ERROR: $label is not signed by a Developer ID Application certificate." >&2
        exit 1
    fi
    if ! grep -q "^TeamIdentifier=${TEAM_ID}$" "$metadata"; then
        echo "ERROR: $label does not have the requested Team ID $TEAM_ID." >&2
        exit 1
    fi
    if ! grep -Eq '^flags=.*\(runtime\)' "$metadata"; then
        echo "ERROR: $label is missing the hardened runtime signature flag." >&2
        exit 1
    fi
    if ! grep -Eq '^Timestamp=.+$' "$metadata" || grep -q '^Timestamp=none$' "$metadata"; then
        echo "ERROR: $label is missing a secure signing timestamp." >&2
        exit 1
    fi

    if codesign --display --entitlements :- "$target" >"$entitlements" 2>/dev/null; then
        if [[ -s "$entitlements" ]] && \
            [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$entitlements" 2>/dev/null || true)" == "true" ]]; then
            echo "ERROR: $label enables the forbidden get-task-allow entitlement." >&2
            exit 1
        fi
    fi

    actual_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null || true)
    actual_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null || true)
    actual_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist" 2>/dev/null || true)
    if [[ "$actual_identifier" != "com.kaanxweb.claude-md-switcher" ]]; then
        echo "ERROR: $label has unexpected bundle identifier '${actual_identifier:-missing}'." >&2
        exit 1
    fi
    if [[ "$actual_version" != "$VERSION" ]]; then
        echo "ERROR: $label version '${actual_version:-missing}' does not match $VERSION." >&2
        exit 1
    fi
    if [[ "$actual_build" != "$BUILD" ]]; then
        echo "ERROR: $label build '${actual_build:-missing}' does not match $BUILD." >&2
        exit 1
    fi
    if [[ ! -x "$executable" ]]; then
        echo "ERROR: $label is missing executable $EXECUTABLE_NAME." >&2
        exit 1
    fi
    actual_archs=$(/usr/bin/lipo -archs "$executable" 2>/dev/null || true)
    if [[ "$actual_archs" != "arm64" ]]; then
        echo "ERROR: $label binary architecture is '${actual_archs:-missing}', expected arm64 only." >&2
        exit 1
    fi
}

echo "Signing with hardened runtime and secure timestamp..."
codesign --force --options runtime --timestamp --sign "$SIGNING_FINGERPRINT" "$APP"
verify_developer_id_app "$APP" "pre-notarization-app"

NOTARIZE_ZIP="$WORK_DIR/ClaudeMDSwitcher-notarize.zip"
SUBMISSION_JSON="$WORK_DIR/notary-submission.json"
/usr/bin/ditto -c -k --keepParent "$APP" "$NOTARIZE_ZIP"

echo "Submitting to notarytool (this can take several minutes)..."
set +e
xcrun notarytool submit "$NOTARIZE_ZIP" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait \
    --output-format json >"$SUBMISSION_JSON"
SUBMIT_RESULT=$?
set -e

SUBMISSION_ID=$(/usr/bin/plutil -extract id raw -o - "$SUBMISSION_JSON" 2>/dev/null || true)
NOTARY_STATUS=$(/usr/bin/plutil -extract status raw -o - "$SUBMISSION_JSON" 2>/dev/null || true)
if [[ -z "$SUBMISSION_ID" ]]; then
    echo "ERROR: notarytool did not return a submission ID; no final release artifact was created." >&2
    exit 1
fi

echo "Notarization submission ID: $SUBMISSION_ID"
WORK_NOTARY_LOG="$WORK_DIR/$NOTARY_LOG_NAME"
if ! xcrun notarytool log "$SUBMISSION_ID" "$WORK_NOTARY_LOG" \
    --keychain-profile "$NOTARY_PROFILE"; then
    echo "ERROR: Could not retrieve the notarization log for submission $SUBMISSION_ID." >&2
    exit 1
fi
if ! cp "$WORK_NOTARY_LOG" "$PENDING_NOTARY_LOG" || \
    ! mv "$PENDING_NOTARY_LOG" "$PUBLIC_NOTARY_LOG"; then
    echo "ERROR: Could not retain the notarization log for submission $SUBMISSION_ID." >&2
    exit 1
fi
CURRENT_LOG_RETAINED=1
echo "Retained notarization log for $SUBMISSION_ID: $PUBLIC_NOTARY_LOG"

if grep -Eiq '"severity"[[:space:]]*:[[:space:]]*"(warning|error)"' "$PUBLIC_NOTARY_LOG"; then
    echo "ERROR: The notarization log reports warning or error issues; inspect $PUBLIC_NOTARY_LOG." >&2
    exit 1
fi
if [[ "$SUBMIT_RESULT" -ne 0 ]]; then
    echo "ERROR: notarytool submission failed; inspect $PUBLIC_NOTARY_LOG." >&2
    exit 1
fi
if [[ "$NOTARY_STATUS" != "Accepted" ]]; then
    echo "ERROR: Notarization status is '${NOTARY_STATUS:-unknown}', not Accepted; inspect $PUBLIC_NOTARY_LOG." >&2
    exit 1
fi

echo "Stapling and validating notarization ticket..."
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
verify_developer_id_app "$APP" "stapled-app"
spctl --assess --type execute --verbose=4 "$APP"

FINAL_ZIP="$WORK_DIR/$RELEASE_ZIP_NAME"
/usr/bin/ditto -c -k --keepParent "$APP" "$FINAL_ZIP"

EXTRACT_DIR="$WORK_DIR/extracted"
mkdir -p "$EXTRACT_DIR"
/usr/bin/ditto -x -k "$FINAL_ZIP" "$EXTRACT_DIR"
PACKAGED_APP="$EXTRACT_DIR/$APP_NAME"
if [[ ! -d "$PACKAGED_APP" ]]; then
    echo "ERROR: Final ZIP does not contain the expected $APP_NAME bundle." >&2
    exit 1
fi
if [[ "$(find "$EXTRACT_DIR" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d ' ')" != "1" ]]; then
    echo "ERROR: Final ZIP contains unexpected top-level entries." >&2
    exit 1
fi

verify_developer_id_app "$PACKAGED_APP" "packaged-app"
xcrun stapler validate "$PACKAGED_APP"
spctl --assess --type execute --verbose=4 "$PACKAGED_APP"

(cd "$WORK_DIR" && /usr/bin/shasum -a 256 "$RELEASE_ZIP_NAME" >"$CHECKSUM_NAME")
(cd "$WORK_DIR" && /usr/bin/shasum -a 256 -c "$CHECKSUM_NAME")

# Promote only the fully verified bundle and its matching release files. If any
# move fails, the EXIT trap removes every partial public promotion.
mv "$APP" "$PUBLIC_APP"
mv "$FINAL_ZIP" "$PUBLIC_RELEASE_ZIP"
mv "$WORK_DIR/$CHECKSUM_NAME" "$PUBLIC_CHECKSUM"
(cd "$ROOT" && /usr/bin/shasum -a 256 -c "$CHECKSUM_NAME")
RELEASE_SUCCEEDED=1

echo "Built: $PUBLIC_RELEASE_ZIP (Developer ID signed + notarized + stapled)"
echo "Checksum: $PUBLIC_CHECKSUM"
