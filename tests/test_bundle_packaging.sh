#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
APP="$ROOT/ClaudeMDSwitcher.app"
PLIST="$APP/Contents/Info.plist"
EXECUTABLE="$APP/Contents/MacOS/ClaudeMDSwitcher"
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
VERSION_DIR="$FRAMEWORK/Versions/B"
EXPECTED_SPARKLE_LINK='@rpath/Sparkle.framework/Versions/B/Sparkle'
EXPECTED_FEED_URL='https://github.com/kaanxweb/claude-md-switcher/releases/latest/download/appcast.xml'
pass_count=0

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

pass() {
    pass_count=$((pass_count + 1))
    printf 'ok %d - %s\n' "$pass_count" "$1"
}

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null || true
}

assert_plist_value() {
    local key=$1
    local expected=$2
    local label=$3
    local actual

    actual=$(plist_value "$key")
    if [[ "$actual" != "$expected" ]]; then
        fail "$label is '${actual:-missing}', expected '$expected'"
    fi
    pass "$label"
}

assert_symlink() {
    local path=$1
    local expected_target=$2
    local label=$3
    local actual_target

    if [[ ! -L "$path" ]]; then
        fail "$label is not a symlink"
    fi
    actual_target=$(/usr/bin/readlink "$path")
    if [[ "$actual_target" != "$expected_target" ]]; then
        fail "$label points to '$actual_target', expected '$expected_target'"
    fi
    if [[ ! -e "$path" ]]; then
        fail "$label is broken"
    fi
    pass "$label is intact"
}

cd "$ROOT"
./build.sh --version 1.0.1 --build 2
pass "real arm64 bundle build completed"

if ! /usr/bin/plutil -lint "$PLIST" >/dev/null; then
    fail "built Info.plist failed plutil lint"
fi
pass "built Info.plist passes plutil lint"

assert_plist_value CFBundleIdentifier com.kaanxweb.claude-md-switcher "bundle identifier"
assert_plist_value CFBundleShortVersionString 1.0.1 "bundle version"
assert_plist_value CFBundleVersion 2 "bundle build"
assert_plist_value SUFeedURL "$EXPECTED_FEED_URL" "Sparkle feed URL"
assert_plist_value SUEnableAutomaticChecks true "automatic update checks flag"
assert_plist_value SUAutomaticallyUpdate false "automatic installation flag"
assert_plist_value SUAllowsAutomaticUpdates false "automatic installation policy"
assert_plist_value SUVerifyUpdateBeforeExtraction true "pre-extraction verification flag"
assert_plist_value SURequireSignedFeed true "signed-feed requirement flag"
assert_plist_value SUSignedFeedFailureExpirationInterval 0 "signed-feed fail-closed interval"

public_key=$(plist_value SUPublicEDKey)
if [[ -z "$public_key" || "$public_key" == "__SPARKLE_PUBLIC_KEY__" || \
      ! "$public_key" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
    fail "SUPublicEDKey is missing, malformed, or still a placeholder"
fi
pass "Sparkle public key is non-placeholder Ed25519 material"

if [[ ! -d "$FRAMEWORK" ]]; then
    fail "Sparkle.framework is missing from Contents/Frameworks"
fi
pass "Sparkle.framework is embedded"

assert_symlink "$FRAMEWORK/Versions/Current" B "Sparkle Versions/Current"
assert_symlink "$FRAMEWORK/Sparkle" Versions/Current/Sparkle "Sparkle binary"
assert_symlink "$FRAMEWORK/Resources" Versions/Current/Resources "Sparkle Resources"
assert_symlink "$FRAMEWORK/Headers" Versions/Current/Headers "Sparkle Headers"
assert_symlink "$FRAMEWORK/Modules" Versions/Current/Modules "Sparkle Modules"
assert_symlink "$FRAMEWORK/PrivateHeaders" Versions/Current/PrivateHeaders "Sparkle PrivateHeaders"
assert_symlink "$FRAMEWORK/Autoupdate" Versions/Current/Autoupdate "Sparkle Autoupdate"
assert_symlink "$FRAMEWORK/Updater.app" Versions/Current/Updater.app "Sparkle Updater.app"
assert_symlink "$FRAMEWORK/XPCServices" Versions/Current/XPCServices "Sparkle XPCServices"

if ! /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP" >/dev/null 2>&1; then
    fail "deep strict code-signature verification failed"
fi
pass "deep strict code-signature verification passes"

architectures=$(/usr/bin/lipo -archs "$EXECUTABLE")
if [[ "$architectures" != "arm64" ]]; then
    fail "main executable architectures are '$architectures', expected arm64"
fi
pass "main executable is arm64 only"

linkage=$(/usr/bin/otool -L "$EXECUTABLE")
linkage_paths=$(printf '%s\n' "$linkage" | /usr/bin/awk 'NR > 1 { print $1 }')
sparkle_link_count=$(printf '%s\n' "$linkage" | /usr/bin/awk -v expected="$EXPECTED_SPARKLE_LINK" \
    '$1 == expected { count++ } END { print count + 0 }')
sparkle_reference_count=$(printf '%s\n' "$linkage" | /usr/bin/awk \
    '$1 ~ /Sparkle[.]framework\/.*\/Sparkle$/ { count++ } END { print count + 0 }')
if [[ "$sparkle_link_count" -ne 1 || "$sparkle_reference_count" -ne 1 ]]; then
    fail "main executable does not link exactly once to $EXPECTED_SPARKLE_LINK"
fi
pass "main executable has the exact Sparkle framework linkage"

load_commands=$(/usr/bin/otool -l "$EXECUTABLE")
rpaths=$(printf '%s\n' "$load_commands" | /usr/bin/awk '
    $1 == "cmd" && $2 == "LC_RPATH" { want_path = 1; next }
    want_path && $1 == "path" { print $2; want_path = 0 }
')
expected_rpath_count=$(printf '%s\n' "$rpaths" | /usr/bin/awk \
    '$1 == "@executable_path/../Frameworks" { count++ } END { print count + 0 }')
if [[ "$expected_rpath_count" -ne 1 ]]; then
    fail "LC_RPATH does not contain exactly one @executable_path/../Frameworks entry"
fi
pass "LC_RPATH resolves embedded frameworks"

if printf '%s\n%s\n' "$linkage_paths" "$rpaths" | /usr/bin/grep -Fq "$ROOT" || \
   printf '%s\n%s\n' "$linkage_paths" "$rpaths" | /usr/bin/grep -Eq '^/.*(/[.]build)(/|$)'; then
    fail "Mach-O linkage contains a workspace or .build absolute path"
fi
pass "Mach-O linkage contains no workspace or .build absolute path"

framework_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$FRAMEWORK/Resources/Info.plist" 2>/dev/null || true)
if [[ "$framework_version" != "2.9.4" ]]; then
    fail "embedded Sparkle version is '${framework_version:-missing}', expected 2.9.4"
fi
pass "embedded framework reports Sparkle 2.9.4"

for component in \
    "$VERSION_DIR/Sparkle" \
    "$VERSION_DIR/Autoupdate" \
    "$VERSION_DIR/Updater.app/Contents/MacOS/Updater" \
    "$VERSION_DIR/XPCServices/Installer.xpc/Contents/MacOS/Installer" \
    "$VERSION_DIR/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"; do
    if [[ ! -x "$component" ]]; then
        fail "required nested Sparkle component is missing or not executable: $component"
    fi
done
pass "all required nested Sparkle executables are present"

printf 'PASS: %d bundle packaging checks\n' "$pass_count"
