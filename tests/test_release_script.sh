#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/claude-md-switcher-release-test.XXXXXX")
KEY_SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/claude-md-switcher-release-keys.XXXXXX")
trap 'rm -rf "$SANDBOX" "$KEY_SANDBOX"' EXIT

cp "$ROOT/release.sh" "$SANDBOX/release.sh"
chmod +x "$SANDBOX/release.sh"
mkdir -p "$SANDBOX/home" "$SANDBOX/bin" "$SANDBOX/.github"
printf '# Release test fixture\n' >"$SANDBOX/.github/release-notes-1.0.1.md"
cp "$ROOT/.github/release-signers" "$SANDBOX/.github/release-signers"
printf '#!/bin/bash\nexit 1\n' >"$SANDBOX/bin/xcrun"
printf '#!/bin/bash\nprintf called >%q\nexit 99\n' \
    "$SANDBOX/swift-build-was-called" >"$SANDBOX/bin/swift"
chmod +x "$SANDBOX/bin/xcrun" "$SANDBOX/bin/swift"

pass_count=0

expect_failure() {
    local label=$1
    local diagnostic=$2
    shift 2

    local output status
    set +e
    output=$(env -i \
        HOME="$SANDBOX/home" \
        PATH="$SANDBOX/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
        /bin/bash "$SANDBOX/release.sh" "$@" 2>&1)
    status=$?
    set -e

    if [[ $status -eq 0 ]]; then
        printf 'FAIL: %s unexpectedly succeeded\n' "$label" >&2
        exit 1
    fi

    if ! grep -Eiq "$diagnostic" <<<"$output"; then
        printf 'FAIL: %s did not report a clear diagnostic matching /%s/\n' "$label" "$diagnostic" >&2
        printf '%s\n' "$output" >&2
        exit 1
    fi

    pass_count=$((pass_count + 1))
    printf 'ok %d - %s\n' "$pass_count" "$label"
}

valid=(
    --version 1.0.1
    --build 2
    --team-id TEAMID1234
    --notary-profile ClaudeMDSwitcher-notary
    --sparkle-key-account kaanxweb
)

seed_release_outputs() {
    local version=$1
    mkdir -p "$SANDBOX/ClaudeMDSwitcher.app"
    printf 'stale app\n' >"$SANDBOX/ClaudeMDSwitcher.app/sentinel"
    printf 'stale zip\n' >"$SANDBOX/ClaudeMDSwitcher-v${version}-arm64.zip"
    printf 'stale checksum\n' >"$SANDBOX/ClaudeMDSwitcher-v${version}-arm64.zip.sha256"
    printf 'stale log\n' >"$SANDBOX/ClaudeMDSwitcher-v${version}-arm64.notarization-log.json"
    printf 'stale appcast\n' >"$SANDBOX/appcast.xml"
}

assert_release_outputs_absent() {
    local version=$1
    local context=$2
    local output
    for output in \
        "$SANDBOX/ClaudeMDSwitcher.app" \
        "$SANDBOX/ClaudeMDSwitcher-v${version}-arm64.zip" \
        "$SANDBOX/ClaudeMDSwitcher-v${version}-arm64.zip.sha256" \
        "$SANDBOX/ClaudeMDSwitcher-v${version}-arm64.notarization-log.json" \
        "$SANDBOX/appcast.xml"; do
        if [[ -e "$output" ]]; then
            printf 'FAIL: %s preserved or created %s\n' "$context" "$output" >&2
            exit 1
        fi
    done
}

assert_release_outputs_present() {
    local version=$1
    local context=$2
    local output
    for output in \
        "$SANDBOX/ClaudeMDSwitcher.app" \
        "$SANDBOX/ClaudeMDSwitcher-v${version}-arm64.zip" \
        "$SANDBOX/ClaudeMDSwitcher-v${version}-arm64.zip.sha256" \
        "$SANDBOX/ClaudeMDSwitcher-v${version}-arm64.notarization-log.json" \
        "$SANDBOX/appcast.xml"; do
        if [[ ! -e "$output" ]]; then
            printf 'FAIL: %s unexpectedly removed %s\n' "$context" "$output" >&2
            exit 1
        fi
    done
}

expect_versioned_failure() {
    local label=$1
    local diagnostic=$2
    shift 2

    seed_release_outputs 1.0.1
    expect_failure "$label" "$diagnostic" "$@"
    assert_release_outputs_absent 1.0.1 "$label"
}

assert_swift_not_invoked() {
    local context=$1
    if [[ -e "$SANDBOX/swift-build-was-called" ]]; then
        printf 'FAIL: %s reached swift build\n' "$context" >&2
        exit 1
    fi
}

expect_failure "missing version" 'version|usage' \
    --build 2 --team-id TEAMID1234 --notary-profile ClaudeMDSwitcher-notary \
    --sparkle-key-account kaanxweb
expect_failure "version option without a value" 'version|usage' \
    --version --build 2 --team-id TEAMID1234 --notary-profile ClaudeMDSwitcher-notary \
    --sparkle-key-account kaanxweb
expect_failure "malformed version" 'version' \
    --version 1.0 --build 2 --team-id TEAMID1234 --notary-profile ClaudeMDSwitcher-notary \
    --sparkle-key-account kaanxweb
expect_failure "version with a leading v" 'version' \
    --version v1.0.1 --build 2 --team-id TEAMID1234 --notary-profile ClaudeMDSwitcher-notary \
    --sparkle-key-account kaanxweb

# Malformed version text must never be interpolated into deletion targets.
seed_release_outputs 9.9.9
printf 'unrelated root appcast sentinel\n' >"$SANDBOX/appcast.xml"
expect_failure "malformed version cannot delete unrelated outputs" 'version' \
    --version '../../9.9.9' --build 2 --team-id TEAMID1234 --notary-profile ClaudeMDSwitcher-notary \
    --sparkle-key-account kaanxweb
assert_release_outputs_present 9.9.9 "malformed version validation"
if ! grep -Fqx 'unrelated root appcast sentinel' "$SANDBOX/appcast.xml"; then
    printf 'FAIL: malformed version validation changed the root appcast sentinel\n' >&2
    exit 1
fi
rm -rf "$SANDBOX/ClaudeMDSwitcher.app"
rm -f \
    "$SANDBOX/ClaudeMDSwitcher-v9.9.9-arm64.zip" \
    "$SANDBOX/ClaudeMDSwitcher-v9.9.9-arm64.zip.sha256" \
    "$SANDBOX/ClaudeMDSwitcher-v9.9.9-arm64.notarization-log.json" \
    "$SANDBOX/appcast.xml"

expect_versioned_failure "missing build" 'build|usage' \
    --version 1.0.1 --team-id TEAMID1234 --notary-profile ClaudeMDSwitcher-notary \
    --sparkle-key-account kaanxweb
expect_versioned_failure "build option without a value" 'build|usage' \
    --version 1.0.1 --team-id TEAMID1234 --notary-profile ClaudeMDSwitcher-notary \
    --sparkle-key-account kaanxweb --build
expect_versioned_failure "zero build" 'build' \
    --version 1.0.1 --build 0 --team-id TEAMID1234 --notary-profile ClaudeMDSwitcher-notary \
    --sparkle-key-account kaanxweb
expect_versioned_failure "negative build" 'build' \
    --version 1.0.1 --build -1 --team-id TEAMID1234 --notary-profile ClaudeMDSwitcher-notary \
    --sparkle-key-account kaanxweb
expect_versioned_failure "non-numeric build" 'build' \
    --version 1.0.1 --build two --team-id TEAMID1234 --notary-profile ClaudeMDSwitcher-notary \
    --sparkle-key-account kaanxweb

expect_versioned_failure "missing team ID" 'team.?id|usage' \
    --version 1.0.1 --build 2 --notary-profile ClaudeMDSwitcher-notary \
    --sparkle-key-account kaanxweb
expect_versioned_failure "team ID option without a value" 'team.?id|usage' \
    --version 1.0.1 --build 2 --notary-profile ClaudeMDSwitcher-notary \
    --sparkle-key-account kaanxweb --team-id
expect_versioned_failure "malformed team ID" 'team.?id' \
    --version 1.0.1 --build 2 --team-id short --notary-profile ClaudeMDSwitcher-notary \
    --sparkle-key-account kaanxweb

expect_versioned_failure "missing notary profile" 'notary|profile|usage' \
    --version 1.0.1 --build 2 --team-id TEAMID1234 --sparkle-key-account kaanxweb
expect_versioned_failure "notary profile option without a value" 'notary|profile|usage' \
    --version 1.0.1 --build 2 --team-id TEAMID1234 \
    --sparkle-key-account kaanxweb --notary-profile
expect_versioned_failure "empty notary profile" 'notary|profile' \
    --version 1.0.1 --build 2 --team-id TEAMID1234 --notary-profile "" \
    --sparkle-key-account kaanxweb

expect_versioned_failure "missing Sparkle key account" 'sparkle|account|usage' \
    --version 1.0.1 --build 2 --team-id TEAMID1234 --notary-profile ClaudeMDSwitcher-notary
expect_versioned_failure "Sparkle key account option without a value" 'sparkle|account|usage' \
    --version 1.0.1 --build 2 --team-id TEAMID1234 \
    --notary-profile ClaudeMDSwitcher-notary --sparkle-key-account
expect_versioned_failure "empty Sparkle key account" 'sparkle|account|usage' \
    --version 1.0.1 --build 2 --team-id TEAMID1234 \
    --notary-profile ClaudeMDSwitcher-notary --sparkle-key-account ""

assert_swift_not_invoked "early argument validation"

# A failed credential preflight must invalidate every predictable same-version
# upload target, including stale artifacts left by an earlier release attempt.
seed_release_outputs 1.0.1

expect_failure "unavailable notary profile fails closed before building" 'notary|profile|credential' \
    --version 1.0.1 --build 2 --team-id TEAMID1234 \
    --notary-profile "codex-release-test-${SANDBOX##*.}-does-not-exist" \
    --sparkle-key-account kaanxweb

assert_release_outputs_absent 1.0.1 "credential preflight"
if compgen -G "$SANDBOX/ClaudeMDSwitcher-v*-arm64.zip" >/dev/null; then
    printf 'FAIL: credential preflight created an unexpected release ZIP\n' >&2
    exit 1
fi
assert_swift_not_invoked "credential preflight"

# With credential preflight stubbed successful, provenance failures must still
# stop before Swift. Use a clean temporary repository, then exercise both dirty
# working-tree and missing signed-tag rejection.
printf '#!/bin/bash\nexit 0\n' >"$SANDBOX/bin/xcrun"
git -C "$SANDBOX" init -q
git -C "$SANDBOX" config user.name 'Release Test'
git -C "$SANDBOX" config user.email 'release-test@example.invalid'
git -C "$SANDBOX" add release.sh bin/xcrun bin/swift .github/release-notes-1.0.1.md
git -C "$SANDBOX" add .github/release-signers
git -C "$SANDBOX" commit -qm 'test fixture'

printf 'dirty\n' >"$SANDBOX/untracked-sentinel"
seed_release_outputs 1.0.1
expect_failure "dirty working tree blocks release before building" 'clean|working tree|provenance' \
    "${valid[@]}"
assert_release_outputs_absent 1.0.1 "dirty working-tree preflight"
rm -f "$SANDBOX/untracked-sentinel"

seed_release_outputs 1.0.1
expect_failure "missing signed release tag blocks release before building" 'tag|signed|signature' \
    "${valid[@]}"
assert_release_outputs_absent 1.0.1 "signed-tag preflight"
assert_swift_not_invoked "provenance preflight"

ssh-keygen -q -t ed25519 -N '' -f "$KEY_SANDBOX/unauthorized-release-key"
git -C "$SANDBOX" \
    -c gpg.format=ssh \
    -c user.signingkey="$KEY_SANDBOX/unauthorized-release-key" \
    tag -s v1.0.1 -m 'unauthorized release signer fixture'
seed_release_outputs 1.0.1
expect_failure "unauthorized signed release tag blocks release before building" 'authorized|signature|signer' \
    "${valid[@]}"
assert_release_outputs_absent 1.0.1 "unauthorized signer preflight"
assert_swift_not_invoked "unauthorized signer preflight"

seed_release_outputs 1.0.1
expect_failure "unknown option" 'unknown|usage' "${valid[@]}" --unexpected
assert_release_outputs_absent 1.0.1 "unknown-option validation"
assert_swift_not_invoked "unknown-option validation"

printf 'PASS: %d release preflight checks\n' "$pass_count"
