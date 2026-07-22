#!/usr/bin/env bash
# Production arm64 build. Requires Developer ID signing and notarization;
# no unsigned or ad-hoc release artifact is ever produced.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"

usage() {
    cat >&2 <<EOF
Usage: $0 --version X.Y.Z --build N --team-id TEAMID --notary-profile PROFILE --sparkle-key-account ACCOUNT [--signing-identity IDENTITY]
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
SPARKLE_KEY_ACCOUNT=""
SPARKLE_KEY_ACCOUNT_SEEN=0
APP_NAME="ClaudeMDSwitcher.app"
EXECUTABLE_NAME="ClaudeMDSwitcher"
RELEASE_SIGNERS_FILE="$ROOT/.github/release-signers"
AUTHORIZED_TAG_SIGNER_FINGERPRINT="SHA256:PAF5hWTFuJzAFzhrjE0AgmsEl+5DHOTsyixO2zD1PLg"
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
            rm -f -- "$PUBLIC_RELEASE_ZIP" "$PUBLIC_CHECKSUM" "$PUBLIC_APPCAST"
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
    PUBLIC_APPCAST="$ROOT/appcast.xml"
    PENDING_NOTARY_LOG="$ROOT/.${NOTARY_LOG_NAME}.pending.$$"
    OUTPUTS_INITIALIZED=1
    trap cleanup EXIT

    # The strict version makes every deletion target fixed and narrow.
    rm -rf -- "$PUBLIC_APP"
    rm -f -- "$PUBLIC_RELEASE_ZIP" "$PUBLIC_CHECKSUM" "$PUBLIC_NOTARY_LOG" "$PENDING_NOTARY_LOG" "$PUBLIC_APPCAST"

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
        --sparkle-key-account)
            require_option_value "$@"
            SPARKLE_KEY_ACCOUNT_SEEN=$((SPARKLE_KEY_ACCOUNT_SEEN + 1))
            SPARKLE_KEY_ACCOUNT="$2"
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
if [[ "$SPARKLE_KEY_ACCOUNT_SEEN" -ne 1 ]]; then
    echo "ERROR: --sparkle-key-account must be provided exactly once." >&2
    usage
    exit 2
fi
if [[ ! "$SPARKLE_KEY_ACCOUNT" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "ERROR: Sparkle key account may contain only letters, numbers, dots, underscores, and hyphens." >&2
    exit 2
fi
RELEASE_NOTES_SOURCE="$ROOT/.github/release-notes-${VERSION}.md"
if [[ ! -s "$RELEASE_NOTES_SOURCE" ]]; then
    echo "ERROR: Matching release notes not found or empty: $RELEASE_NOTES_SOURCE" >&2
    exit 1
fi
if [[ "$REQUESTED_IDENTITY" =~ ^[0-9A-Fa-f]{40}$ ]]; then
    REQUESTED_IDENTITY=$(printf '%s' "$REQUESTED_IDENTITY" | tr '[:lower:]' '[:upper:]')
fi

for command in git swift codesign security xcrun spctl ditto shasum lipo otool xmllint readlink stat; do
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
if [[ ! -s "$RELEASE_SIGNERS_FILE" ]]; then
    echo "ERROR: Authorized release signer allowlist is missing or empty: $RELEASE_SIGNERS_FILE" >&2
    exit 1
fi
TAG_VERIFY_STATUS="$WORK_DIR/tag-verifier-status.txt"
if ! LC_ALL=C git \
    -c gpg.format=ssh \
    -c gpg.ssh.allowedSignersFile="$RELEASE_SIGNERS_FILE" \
    verify-tag --raw "$EXPECTED_TAG" >/dev/null 2>"$TAG_VERIFY_STATUS"; then
    cat "$TAG_VERIFY_STATUS" >&2
    echo "ERROR: Signature verification failed for release tag $EXPECTED_TAG." >&2
    exit 1
fi
cat "$TAG_VERIFY_STATUS"
VERIFIED_TAG_SIGNER_FINGERPRINT=$(sed -nE \
    's/^Good "git" signature for .+ with ED25519 key (SHA256:[A-Za-z0-9+\/=]+)$/\1/p' \
    "$TAG_VERIFY_STATUS")
VERIFIED_TAG_SIGNER_COUNT=$(printf '%s\n' "$VERIFIED_TAG_SIGNER_FINGERPRINT" | awk 'NF { count++ } END { print count + 0 }')
if [[ "$VERIFIED_TAG_SIGNER_COUNT" -ne 1 ]]; then
    echo "ERROR: Git did not report exactly one verified ED25519 release-tag signer fingerprint." >&2
    exit 1
fi
if [[ "$VERIFIED_TAG_SIGNER_FINGERPRINT" != "$AUTHORIZED_TAG_SIGNER_FINGERPRINT" ]]; then
    echo "ERROR: Release tag $EXPECTED_TAG was not signed by the authorized maintainer key $AUTHORIZED_TAG_SIGNER_FINGERPRINT." >&2
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

if ! git ls-files --error-unmatch Package.resolved >/dev/null 2>&1; then
    echo "ERROR: Package.resolved must be tracked for reproducible release builds." >&2
    exit 1
fi

SWIFT_BUILD_DIR="$WORK_DIR/swift-build"
swift build --disable-automatic-resolution -c release --arch arm64 --scratch-path "$SWIFT_BUILD_DIR"
BIN_DIR=$(swift build --disable-automatic-resolution -c release --arch arm64 --scratch-path "$SWIFT_BUILD_DIR" --show-bin-path)
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
    echo "ERROR: Dependency resolution or the release build changed the clean source checkout." >&2
    exit 1
fi
BIN="$BIN_DIR/$EXECUTABLE_NAME"
SPARKLE_TOOLS_DIR="$SWIFT_BUILD_DIR/artifacts/sparkle/Sparkle/bin"
GENERATE_KEYS="$SPARKLE_TOOLS_DIR/generate_keys"
GENERATE_APPCAST="$SPARKLE_TOOLS_DIR/generate_appcast"
SIGN_UPDATE="$SPARKLE_TOOLS_DIR/sign_update"
SOURCE_SPARKLE_FRAMEWORK="$BIN_DIR/Sparkle.framework"

if [[ ! -x "$BIN" ]]; then
    echo "ERROR: Built executable not found: $BIN" >&2
    exit 1
fi
if [[ ! -d "$SOURCE_SPARKLE_FRAMEWORK" ]]; then
    echo "ERROR: Sparkle framework not found: $SOURCE_SPARKLE_FRAMEWORK" >&2
    exit 1
fi
SPARKLE_FRAMEWORK_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SOURCE_SPARKLE_FRAMEWORK/Resources/Info.plist" 2>/dev/null || true)
if [[ "$SPARKLE_FRAMEWORK_VERSION" != "2.9.4" ]]; then
    echo "ERROR: Sparkle framework version is '${SPARKLE_FRAMEWORK_VERSION:-missing}', expected 2.9.4." >&2
    exit 1
fi
for sparkle_tool in "$GENERATE_KEYS" "$GENERATE_APPCAST" "$SIGN_UPDATE"; do
    if [[ ! -x "$sparkle_tool" ]]; then
        echo "ERROR: Required Sparkle tool not found or not executable: $sparkle_tool" >&2
        exit 1
    fi
done

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/$EXECUTABLE_NAME"
cp "$ROOT/Sources/ClaudeMDSwitcher/Info.plist" "$APP/Contents/Info.plist"
/usr/bin/ditto "$SOURCE_SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"

PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"

# Generate AppIcon.icns inside the isolated production bundle.
if [[ -x "$ROOT/scripts/generate_icon.swift" ]]; then
    (cd "$WORK_DIR" && "$ROOT/scripts/generate_icon.swift")
elif [[ -f "$ROOT/scripts/generate_icon.swift" ]]; then
    (cd "$WORK_DIR" && swift "$ROOT/scripts/generate_icon.swift")
fi

SOURCE_PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$ROOT/Sources/ClaudeMDSwitcher/Info.plist" 2>/dev/null || true)
BUILT_PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$PLIST" 2>/dev/null || true)
if [[ -z "$SOURCE_PUBLIC_KEY" || "$SOURCE_PUBLIC_KEY" == "__SPARKLE_PUBLIC_KEY__" ]]; then
    echo "ERROR: Source Info.plist has a missing or placeholder SUPublicEDKey." >&2
    exit 1
fi
if [[ -z "$BUILT_PUBLIC_KEY" || "$BUILT_PUBLIC_KEY" == "__SPARKLE_PUBLIC_KEY__" ]]; then
    echo "ERROR: Built Info.plist has a missing or placeholder SUPublicEDKey." >&2
    exit 1
fi
if [[ "$BUILT_PUBLIC_KEY" != "$SOURCE_PUBLIC_KEY" ]]; then
    echo "ERROR: Built SUPublicEDKey does not exactly match the source Info.plist." >&2
    exit 1
fi
if ! KEYCHAIN_PUBLIC_KEY=$("$GENERATE_KEYS" --account "$SPARKLE_KEY_ACCOUNT" -p); then
    echo "ERROR: Could not read the Sparkle public key for account '$SPARKLE_KEY_ACCOUNT'." >&2
    exit 1
fi
if [[ "$KEYCHAIN_PUBLIC_KEY" != "$SOURCE_PUBLIC_KEY" ]]; then
    echo "ERROR: Sparkle key account '$SPARKLE_KEY_ACCOUNT' does not match SUPublicEDKey." >&2
    exit 1
fi

verify_symlink() {
    local link_path="$1"
    local expected_target="$2"
    local label="$3"
    local actual_target

    if [[ ! -L "$link_path" ]]; then
        echo "ERROR: $label is missing required symlink: $link_path" >&2
        exit 1
    fi
    actual_target=$(/usr/bin/readlink "$link_path")
    if [[ "$actual_target" != "$expected_target" ]]; then
        echo "ERROR: $label symlink $link_path points to '$actual_target', expected '$expected_target'." >&2
        exit 1
    fi
    if [[ ! -e "$link_path" ]]; then
        echo "ERROR: $label symlink is broken: $link_path" >&2
        exit 1
    fi
}

verify_sparkle_symlinks() {
    local app_path="$1"
    local label="$2"
    local framework="$app_path/Contents/Frameworks/Sparkle.framework"

    if [[ ! -d "$framework/Versions/B" ]]; then
        echo "ERROR: $label is missing Sparkle.framework/Versions/B." >&2
        exit 1
    fi
    verify_symlink "$framework/Versions/Current" "B" "$label"
    verify_symlink "$framework/Sparkle" "Versions/Current/Sparkle" "$label"
    verify_symlink "$framework/Resources" "Versions/Current/Resources" "$label"
    verify_symlink "$framework/Headers" "Versions/Current/Headers" "$label"
    verify_symlink "$framework/Modules" "Versions/Current/Modules" "$label"
    verify_symlink "$framework/PrivateHeaders" "Versions/Current/PrivateHeaders" "$label"
    verify_symlink "$framework/Autoupdate" "Versions/Current/Autoupdate" "$label"
    verify_symlink "$framework/Updater.app" "Versions/Current/Updater.app" "$label"
    verify_symlink "$framework/XPCServices" "Versions/Current/XPCServices" "$label"
}

verify_executable_linkage() {
    local app_path="$1"
    local label="$2"
    local executable="$app_path/Contents/MacOS/$EXECUTABLE_NAME"
    local linkage linkage_paths load_commands rpaths sparkle_link_count sparkle_reference_count expected_rpath_count
    local expected_sparkle="@rpath/Sparkle.framework/Versions/B/Sparkle"

    linkage=$(/usr/bin/otool -L "$executable")
    linkage_paths=$(printf '%s\n' "$linkage" | /usr/bin/awk 'NR > 1 { print $1 }')
    load_commands=$(/usr/bin/otool -l "$executable")
    sparkle_link_count=$(printf '%s\n' "$linkage_paths" | /usr/bin/awk -v expected="$expected_sparkle" '$1 == expected { count++ } END { print count + 0 }')
    sparkle_reference_count=$(printf '%s\n' "$linkage_paths" | /usr/bin/awk '$1 ~ /Sparkle[.]framework\/.*\/Sparkle$/ { count++ } END { print count + 0 }')
    if [[ "$sparkle_link_count" -ne 1 || "$sparkle_reference_count" -ne 1 ]]; then
        echo "ERROR: $label must link exactly once to $expected_sparkle." >&2
        exit 1
    fi

    rpaths=$(printf '%s\n' "$load_commands" | /usr/bin/awk '
        $1 == "cmd" && $2 == "LC_RPATH" { want_path = 1; next }
        want_path && $1 == "path" { print $2; want_path = 0 }
    ')
    expected_rpath_count=$(printf '%s\n' "$rpaths" | /usr/bin/awk '$1 == "@executable_path/../Frameworks" { count++ } END { print count + 0 }')
    if [[ "$expected_rpath_count" -ne 1 ]]; then
        echo "ERROR: $label must contain exactly one LC_RPATH @executable_path/../Frameworks." >&2
        exit 1
    fi
    if printf '%s\n%s\n' "$linkage_paths" "$rpaths" | /usr/bin/grep -Eq '(^|[[:space:]])/[^[:space:]]*(/swift-build/|/[.]build/|/claude-md-release[.])'; then
        echo "ERROR: $label contains an absolute scratch/build path in its linkage or rpaths." >&2
        exit 1
    fi
}

verify_signed_target() {
    local target="$1"
    local label="$2"
    local metadata="$WORK_DIR/${label}.codesign.txt"
    local entitlements="$WORK_DIR/${label}.entitlements.plist"
    local actual_authority

    codesign --verify --strict --verbose=2 "$target"
    codesign --display --verbose=4 "$target" 2>"$metadata"

    actual_authority=$(/usr/bin/awk -F= '$1 == "Authority" { print substr($0, index($0, "=") + 1); exit }' "$metadata")
    if [[ "$actual_authority" != "$SIGNING_NAME" ]]; then
        echo "ERROR: $label has signing authority '${actual_authority:-missing}', expected '$SIGNING_NAME'." >&2
        exit 1
    fi
    if ! /usr/bin/grep -Fqx "TeamIdentifier=$TEAM_ID" "$metadata"; then
        echo "ERROR: $label does not have the requested Team ID $TEAM_ID." >&2
        exit 1
    fi
    if ! /usr/bin/grep -Eq '^flags=.*[(]runtime[)]' "$metadata" || \
        ! /usr/bin/grep -Eq '^Runtime Version=.+$' "$metadata"; then
        echo "ERROR: $label is missing the hardened runtime signature." >&2
        exit 1
    fi
    if ! /usr/bin/grep -Eq '^Timestamp=.+$' "$metadata" || /usr/bin/grep -Fqx 'Timestamp=none' "$metadata"; then
        echo "ERROR: $label is missing a secure signing timestamp." >&2
        exit 1
    fi

    if ! codesign --display --entitlements :- "$target" >"$entitlements" 2>/dev/null; then
        echo "ERROR: Could not inspect $label entitlements." >&2
        exit 1
    fi
    if [[ -s "$entitlements" ]] && ! /usr/bin/plutil -lint "$entitlements" >/dev/null; then
        echo "ERROR: $label has malformed entitlements." >&2
        exit 1
    fi
    if [[ -s "$entitlements" ]] && \
        [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$entitlements" 2>/dev/null || true)" == "true" ]]; then
        echo "ERROR: $label enables the forbidden get-task-allow entitlement." >&2
        exit 1
    fi
}

verify_embedded_sparkle_signatures() {
    local app_path="$1"
    local label_prefix="$2"
    local version_dir="$app_path/Contents/Frameworks/Sparkle.framework/Versions/B"

    verify_signed_target "$version_dir/XPCServices/Installer.xpc" "${label_prefix}-installer-xpc"
    verify_signed_target "$version_dir/XPCServices/Downloader.xpc" "${label_prefix}-downloader-xpc"
    verify_signed_target "$version_dir/Autoupdate" "${label_prefix}-autoupdate"
    verify_signed_target "$version_dir/Updater.app" "${label_prefix}-updater-app"
    verify_signed_target "$app_path/Contents/Frameworks/Sparkle.framework" "${label_prefix}-sparkle-framework"
}

verify_developer_id_app() {
    local target="$1"
    local label="$2"
    local plist="$target/Contents/Info.plist"
    local executable="$target/Contents/MacOS/$EXECUTABLE_NAME"
    local actual_identifier actual_version actual_build actual_archs
    local actual_feed_url actual_public_key automatic_checks automatically_update
    local allows_automatic_updates verify_before_extraction require_signed_feed
    local signed_feed_failure_expiration_interval

    verify_signed_target "$target" "$label"
    codesign --verify --deep --strict --verbose=2 "$target"

    actual_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null || true)
    actual_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null || true)
    actual_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist" 2>/dev/null || true)
    actual_feed_url=$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$plist" 2>/dev/null || true)
    actual_public_key=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist" 2>/dev/null || true)
    automatic_checks=$(/usr/libexec/PlistBuddy -c 'Print :SUEnableAutomaticChecks' "$plist" 2>/dev/null || true)
    automatically_update=$(/usr/libexec/PlistBuddy -c 'Print :SUAutomaticallyUpdate' "$plist" 2>/dev/null || true)
    allows_automatic_updates=$(/usr/libexec/PlistBuddy -c 'Print :SUAllowsAutomaticUpdates' "$plist" 2>/dev/null || true)
    verify_before_extraction=$(/usr/libexec/PlistBuddy -c 'Print :SUVerifyUpdateBeforeExtraction' "$plist" 2>/dev/null || true)
    require_signed_feed=$(/usr/libexec/PlistBuddy -c 'Print :SURequireSignedFeed' "$plist" 2>/dev/null || true)
    signed_feed_failure_expiration_interval=$(/usr/libexec/PlistBuddy -c 'Print :SUSignedFeedFailureExpirationInterval' "$plist" 2>/dev/null || true)
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
    if [[ "$actual_feed_url" != "https://github.com/kaanxweb/claude-md-switcher/releases/latest/download/appcast.xml" || \
          "$actual_public_key" != "$SOURCE_PUBLIC_KEY" || \
          "$automatic_checks" != "true" || \
          "$automatically_update" != "false" || \
          "$allows_automatic_updates" != "false" || \
          "$verify_before_extraction" != "true" || \
          "$require_signed_feed" != "true" || \
          "$signed_feed_failure_expiration_interval" != "0" ]]; then
        echo "ERROR: $label does not preserve the required Sparkle update trust and consent policy." >&2
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

    verify_executable_linkage "$target" "$label"
}

echo "Signing with hardened runtime and secure timestamp..."
SPARKLE_FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
SPARKLE_VERSION_DIR="$SPARKLE_FRAMEWORK/Versions/B"
SPARKLE_INSTALLER="$SPARKLE_VERSION_DIR/XPCServices/Installer.xpc"
SPARKLE_DOWNLOADER="$SPARKLE_VERSION_DIR/XPCServices/Downloader.xpc"
SPARKLE_AUTOUPDATE="$SPARKLE_VERSION_DIR/Autoupdate"
SPARKLE_UPDATER="$SPARKLE_VERSION_DIR/Updater.app"

for sparkle_component in "$SPARKLE_INSTALLER" "$SPARKLE_DOWNLOADER" "$SPARKLE_AUTOUPDATE" "$SPARKLE_UPDATER" "$SPARKLE_FRAMEWORK"; do
    if [[ ! -e "$sparkle_component" ]]; then
        echo "ERROR: Required embedded Sparkle component is missing: $sparkle_component" >&2
        exit 1
    fi
done

verify_sparkle_symlinks "$APP" "pre-notarization-app"
verify_executable_linkage "$APP" "pre-notarization-app"

codesign --force --options runtime --timestamp --sign "$SIGNING_FINGERPRINT" "$SPARKLE_INSTALLER"
codesign --force --options runtime --timestamp --preserve-metadata=entitlements --sign "$SIGNING_FINGERPRINT" "$SPARKLE_DOWNLOADER"
codesign --force --options runtime --timestamp --sign "$SIGNING_FINGERPRINT" "$SPARKLE_AUTOUPDATE"
codesign --force --options runtime --timestamp --sign "$SIGNING_FINGERPRINT" "$SPARKLE_UPDATER"
codesign --force --options runtime --timestamp --sign "$SIGNING_FINGERPRINT" "$SPARKLE_FRAMEWORK"
codesign --force --options runtime --timestamp --sign "$SIGNING_FINGERPRINT" "$APP"

verify_embedded_sparkle_signatures "$APP" "pre-notarization"
verify_developer_id_app "$APP" "pre-notarization-app"

NOTARIZE_ZIP="$WORK_DIR/ClaudeMDSwitcher-notarize.zip"
SUBMISSION_JSON="$WORK_DIR/notary-submission.json"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$NOTARIZE_ZIP"

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
verify_sparkle_symlinks "$APP" "stapled-app"
verify_embedded_sparkle_signatures "$APP" "stapled"
verify_developer_id_app "$APP" "stapled-app"
spctl --assess --type execute --verbose=4 "$APP"

FINAL_ZIP="$WORK_DIR/$RELEASE_ZIP_NAME"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$FINAL_ZIP"

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

verify_sparkle_symlinks "$PACKAGED_APP" "packaged-app"
verify_embedded_sparkle_signatures "$PACKAGED_APP" "packaged"
verify_developer_id_app "$PACKAGED_APP" "packaged-app"
xcrun stapler validate "$PACKAGED_APP"
spctl --assess --type execute --verbose=4 "$PACKAGED_APP"

(cd "$WORK_DIR" && /usr/bin/shasum -a 256 "$RELEASE_ZIP_NAME" >"$CHECKSUM_NAME")
(cd "$WORK_DIR" && /usr/bin/shasum -a 256 -c "$CHECKSUM_NAME")
FINAL_ZIP_SHA=$(/usr/bin/shasum -a 256 "$FINAL_ZIP" | /usr/bin/awk '{ print $1 }')

APPCAST_STAGE="$WORK_DIR/appcast-stage"
mkdir -p "$APPCAST_STAGE"
STAGED_ZIP="$APPCAST_STAGE/$RELEASE_ZIP_NAME"
STAGED_RELEASE_NOTES="$APPCAST_STAGE/${RELEASE_ZIP_NAME%.zip}.md"
WORK_APPCAST="$APPCAST_STAGE/appcast.xml"
DOWNLOAD_URL_PREFIX="https://github.com/kaanxweb/claude-md-switcher/releases/download/v${VERSION}/"
EXPECTED_DOWNLOAD_URL="${DOWNLOAD_URL_PREFIX}${RELEASE_ZIP_NAME}"

/usr/bin/ditto "$FINAL_ZIP" "$STAGED_ZIP"
/usr/bin/ditto "$RELEASE_NOTES_SOURCE" "$STAGED_RELEASE_NOTES"
if [[ "$(/usr/bin/shasum -a 256 "$STAGED_ZIP" | /usr/bin/awk '{ print $1 }')" != "$FINAL_ZIP_SHA" ]]; then
    echo "ERROR: Staging changed the final release ZIP checksum." >&2
    exit 1
fi

"$GENERATE_APPCAST" \
    --account "$SPARKLE_KEY_ACCOUNT" \
    --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
    --embed-release-notes \
    --maximum-deltas 0 \
    --maximum-versions 1 \
    --versions "$BUILD" \
    -o "$WORK_APPCAST" \
    "$APPCAST_STAGE"

if [[ "$(/usr/bin/shasum -a 256 "$FINAL_ZIP" | /usr/bin/awk '{ print $1 }')" != "$FINAL_ZIP_SHA" || \
      "$(/usr/bin/shasum -a 256 "$STAGED_ZIP" | /usr/bin/awk '{ print $1 }')" != "$FINAL_ZIP_SHA" ]]; then
    echo "ERROR: Appcast generation changed the final release ZIP checksum." >&2
    exit 1
fi
if [[ ! -s "$WORK_APPCAST" ]]; then
    echo "ERROR: Sparkle did not generate a non-empty appcast.xml." >&2
    exit 1
fi
if ! /usr/bin/xmllint --noout "$WORK_APPCAST"; then
    echo "ERROR: Generated appcast.xml is not valid XML." >&2
    exit 1
fi

APPCAST_ITEM_COUNT=$(/usr/bin/xmllint --xpath 'count(//*[local-name()="item"])' "$WORK_APPCAST")
if [[ "$APPCAST_ITEM_COUNT" != "1" ]]; then
    echo "ERROR: Generated appcast.xml must contain exactly one item." >&2
    exit 1
fi
APPCAST_ITEM='/*[local-name()="rss"]/*[local-name()="channel"]/*[local-name()="item"]'
APPCAST_BUILD=$(/usr/bin/xmllint --xpath "string(${APPCAST_ITEM}/*[local-name()='version'])" "$WORK_APPCAST")
APPCAST_SHORT_VERSION=$(/usr/bin/xmllint --xpath "string(${APPCAST_ITEM}/*[local-name()='shortVersionString'])" "$WORK_APPCAST")
if [[ "$APPCAST_BUILD" != "$BUILD" || "$APPCAST_SHORT_VERSION" != "$VERSION" ]]; then
    echo "ERROR: Generated appcast version/build does not match $VERSION ($BUILD)." >&2
    exit 1
fi

APPCAST_ENCLOSURE_COUNT=$(/usr/bin/xmllint --xpath "count(${APPCAST_ITEM}/*[local-name()='enclosure'])" "$WORK_APPCAST")
if [[ "$APPCAST_ENCLOSURE_COUNT" != "1" ]]; then
    echo "ERROR: Generated appcast item must contain exactly one enclosure." >&2
    exit 1
fi
APPCAST_ENCLOSURE="${APPCAST_ITEM}/*[local-name()='enclosure']"
APPCAST_URL=$(/usr/bin/xmllint --xpath "string(${APPCAST_ENCLOSURE}/@url)" "$WORK_APPCAST")
APPCAST_LENGTH=$(/usr/bin/xmllint --xpath "string(${APPCAST_ENCLOSURE}/@length)" "$WORK_APPCAST")
APPCAST_SIGNATURE=$(/usr/bin/xmllint --xpath "string(${APPCAST_ENCLOSURE}/@*[local-name()='edSignature'])" "$WORK_APPCAST")
ARCHIVE_LENGTH=$(/usr/bin/stat -f '%z' "$STAGED_ZIP")
if [[ "$APPCAST_URL" != "$EXPECTED_DOWNLOAD_URL" || "${APPCAST_URL##*/}" != "$RELEASE_ZIP_NAME" ]]; then
    echo "ERROR: Appcast enclosure URL is not the immutable tag-specific archive URL." >&2
    exit 1
fi
if [[ "$APPCAST_LENGTH" != "$ARCHIVE_LENGTH" ]]; then
    echo "ERROR: Appcast enclosure length does not match $RELEASE_ZIP_NAME." >&2
    exit 1
fi
if [[ -z "$APPCAST_SIGNATURE" ]]; then
    echo "ERROR: Appcast enclosure is missing its EdDSA signature." >&2
    exit 1
fi

MINIMUM_SYSTEM_COUNT=$(/usr/bin/xmllint --xpath "count(${APPCAST_ITEM}/*[local-name()='minimumSystemVersion'])" "$WORK_APPCAST")
MINIMUM_SYSTEM_VERSION=$(/usr/bin/xmllint --xpath "string(${APPCAST_ITEM}/*[local-name()='minimumSystemVersion'])" "$WORK_APPCAST")
if [[ "$MINIMUM_SYSTEM_COUNT" != "1" || "$MINIMUM_SYSTEM_VERSION" != "14.0" ]]; then
    echo "ERROR: Appcast must require exactly macOS 14.0 or later." >&2
    exit 1
fi
HARDWARE_REQUIREMENTS_COUNT=$(/usr/bin/xmllint --xpath "count(${APPCAST_ITEM}/*[local-name()='hardwareRequirements'])" "$WORK_APPCAST")
HARDWARE_REQUIREMENTS=$(/usr/bin/xmllint --xpath "string(${APPCAST_ITEM}/*[local-name()='hardwareRequirements'])" "$WORK_APPCAST")
if [[ "$HARDWARE_REQUIREMENTS_COUNT" != "1" || "$HARDWARE_REQUIREMENTS" != "arm64" ]]; then
    echo "ERROR: Generated appcast must contain exactly one arm64 hardware requirement." >&2
    exit 1
fi

APPCAST_DESCRIPTION_COUNT=$(/usr/bin/xmllint --xpath "count(${APPCAST_ITEM}/*[local-name()='description'])" "$WORK_APPCAST")
APPCAST_RELEASE_NOTES_LINK_COUNT=$(/usr/bin/xmllint --xpath "count(${APPCAST_ITEM}/*[local-name()='releaseNotesLink'])" "$WORK_APPCAST")
APPCAST_NOTES_FORMAT=$(/usr/bin/xmllint --xpath "string(${APPCAST_ITEM}/*[local-name()='description']/@*[local-name()='format'])" "$WORK_APPCAST")
APPCAST_NOTES=$(/usr/bin/xmllint --xpath "string(${APPCAST_ITEM}/*[local-name()='description'])" "$WORK_APPCAST")
EXPECTED_NOTES=$(/bin/cat "$RELEASE_NOTES_SOURCE")
if [[ "$APPCAST_DESCRIPTION_COUNT" != "1" || "$APPCAST_RELEASE_NOTES_LINK_COUNT" != "0" || \
      "$APPCAST_NOTES_FORMAT" != "markdown" || -z "$APPCAST_NOTES" || "$APPCAST_NOTES" != "$EXPECTED_NOTES" ]]; then
    echo "ERROR: Appcast does not contain the exact embedded Markdown release notes." >&2
    exit 1
fi
APPCAST_DELTAS_COUNT=$(/usr/bin/xmllint --xpath "count(${APPCAST_ITEM}/*[local-name()='deltas'])" "$WORK_APPCAST")
if [[ "$APPCAST_DELTAS_COUNT" != "0" ]]; then
    echo "ERROR: Generated appcast unexpectedly contains delta updates." >&2
    exit 1
fi

SIGNED_FEED_BLOCK_COUNT=$(/usr/bin/grep -c '^<!-- sparkle-signatures:$' "$WORK_APPCAST" || true)
if [[ "$SIGNED_FEED_BLOCK_COUNT" != "1" ]] || \
    ! /usr/bin/grep -Eq '^edSignature: [A-Za-z0-9+/]{86}==$' "$WORK_APPCAST" || \
    ! /usr/bin/grep -Eq '^length: [1-9][0-9]*$' "$WORK_APPCAST"; then
    echo "ERROR: Generated appcast is missing a valid embedded signed-feed block." >&2
    exit 1
fi

if ! "$SIGN_UPDATE" --account "$SPARKLE_KEY_ACCOUNT" --verify "$WORK_APPCAST"; then
    echo "ERROR: Sparkle signed-feed verification failed for appcast.xml." >&2
    exit 1
fi
if ! "$SIGN_UPDATE" --account "$SPARKLE_KEY_ACCOUNT" --verify "$STAGED_ZIP" "$APPCAST_SIGNATURE"; then
    echo "ERROR: Sparkle archive signature verification failed for $RELEASE_ZIP_NAME." >&2
    exit 1
fi

# Promote only the fully verified bundle and its matching release files. If any
# move fails, the EXIT trap removes every partial public promotion.
mv "$APP" "$PUBLIC_APP"
mv "$FINAL_ZIP" "$PUBLIC_RELEASE_ZIP"
mv "$WORK_DIR/$CHECKSUM_NAME" "$PUBLIC_CHECKSUM"
mv "$WORK_APPCAST" "$PUBLIC_APPCAST"
(cd "$ROOT" && /usr/bin/shasum -a 256 -c "$CHECKSUM_NAME")
if [[ "$(/usr/bin/shasum -a 256 "$PUBLIC_RELEASE_ZIP" | /usr/bin/awk '{ print $1 }')" != "$FINAL_ZIP_SHA" ]]; then
    echo "ERROR: Promoted release ZIP checksum changed unexpectedly." >&2
    exit 1
fi
RELEASE_SUCCEEDED=1

echo "Built: $PUBLIC_RELEASE_ZIP (Developer ID signed + notarized + stapled)"
echo "Checksum: $PUBLIC_CHECKSUM"
echo "Appcast: $PUBLIC_APPCAST (EdDSA signed)"
