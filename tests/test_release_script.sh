#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/claude-md-switcher-release-test.XXXXXX")
trap 'rm -rf "$SANDBOX"' EXIT

cp "$ROOT/release.sh" "$SANDBOX/release.sh"
chmod +x "$SANDBOX/release.sh"
mkdir -p "$SANDBOX/home" "$SANDBOX/bin"
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
)

seed_release_outputs() {
    local version=$1
    mkdir -p "$SANDBOX/ClaudeMDSwitcher.app"
    printf 'stale app\n' >"$SANDBOX/ClaudeMDSwitcher.app/sentinel"
    printf 'stale zip\n' >"$SANDBOX/ClaudeMDSwitcher-v${version}-arm64.zip"
    printf 'stale checksum\n' >"$SANDBOX/ClaudeMDSwitcher-v${version}-arm64.zip.sha256"
    printf 'stale log\n' >"$SANDBOX/ClaudeMDSwitcher-v${version}-arm64.notarization-log.json"
}

assert_release_outputs_absent() {
    local version=$1
    local context=$2
    local output
    for output in \
        "$SANDBOX/ClaudeMDSwitcher.app" \
        "$SANDBOX/ClaudeMDSwitcher-v${version}-arm64.zip" \
        "$SANDBOX/ClaudeMDSwitcher-v${version}-arm64.zip.sha256" \
        "$SANDBOX/ClaudeMDSwitcher-v${version}-arm64.notarization-log.json"; do
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
        "$SANDBOX/ClaudeMDSwitcher-v${version}-arm64.notarization-log.json"; do
        if [[ ! -e "$output" ]]; then
            printf 'FAIL: %s unexpectedly removed %s\n' "$context" "$output" >&2
            exit 1
        fi
    done
}

expect_failure "missing version" 'version|usage' \
    --build 2 --team-id TEAMID1234 --notary-profile ClaudeMDSwitcher-notary
expect_failure "version option without a value" 'version|usage' --version
expect_failure "malformed version" 'version' \
    --version 1.0 --build 2 --team-id TEAMID1234 --notary-profile ClaudeMDSwitcher-notary
expect_failure "version with a leading v" 'version' \
    --version v1.0.1 --build 2 --team-id TEAMID1234 --notary-profile ClaudeMDSwitcher-notary

# Malformed version text must never be interpolated into deletion targets.
seed_release_outputs 9.9.9
expect_failure "malformed version cannot delete unrelated outputs" 'version' \
    --version '../../9.9.9' --build 2 --team-id TEAMID1234 --notary-profile ClaudeMDSwitcher-notary
assert_release_outputs_present 9.9.9 "malformed version validation"
rm -rf "$SANDBOX/ClaudeMDSwitcher.app"
rm -f \
    "$SANDBOX/ClaudeMDSwitcher-v9.9.9-arm64.zip" \
    "$SANDBOX/ClaudeMDSwitcher-v9.9.9-arm64.zip.sha256" \
    "$SANDBOX/ClaudeMDSwitcher-v9.9.9-arm64.notarization-log.json"

expect_failure "missing build" 'build|usage' \
    --version 1.0.1 --team-id TEAMID1234 --notary-profile ClaudeMDSwitcher-notary
expect_failure "build option without a value" 'build|usage' \
    --version 1.0.1 --build
expect_failure "zero build" 'build' \
    --version 1.0.1 --build 0 --team-id TEAMID1234 --notary-profile ClaudeMDSwitcher-notary
expect_failure "negative build" 'build' \
    --version 1.0.1 --build -1 --team-id TEAMID1234 --notary-profile ClaudeMDSwitcher-notary
expect_failure "non-numeric build" 'build' \
    --version 1.0.1 --build two --team-id TEAMID1234 --notary-profile ClaudeMDSwitcher-notary

expect_failure "missing team ID" 'team.?id|usage' \
    --version 1.0.1 --build 2 --notary-profile ClaudeMDSwitcher-notary
expect_failure "team ID option without a value" 'team.?id|usage' \
    --version 1.0.1 --build 2 --team-id
expect_failure "malformed team ID" 'team.?id' \
    --version 1.0.1 --build 2 --team-id short --notary-profile ClaudeMDSwitcher-notary

expect_failure "missing notary profile" 'notary|profile|usage' \
    --version 1.0.1 --build 2 --team-id TEAMID1234
expect_failure "notary profile option without a value" 'notary|profile|usage' \
    --version 1.0.1 --build 2 --team-id TEAMID1234 --notary-profile
expect_failure "empty notary profile" 'notary|profile' \
    --version 1.0.1 --build 2 --team-id TEAMID1234 --notary-profile ""

# Once a strict version is known, all later parser/validation failures must
# invalidate that version's predictable outputs before returning.
seed_release_outputs 1.0.1
expect_failure "missing build invalidates stale outputs" 'build|usage' \
    --version 1.0.1 --team-id TEAMID1234 --notary-profile ClaudeMDSwitcher-notary
assert_release_outputs_absent 1.0.1 "missing build validation"

seed_release_outputs 1.0.1
expect_failure "malformed team ID invalidates stale outputs" 'team.?id' \
    --version 1.0.1 --build 2 --team-id short --notary-profile ClaudeMDSwitcher-notary
assert_release_outputs_absent 1.0.1 "team ID validation"

seed_release_outputs 1.0.1
expect_failure "empty notary profile invalidates stale outputs" 'notary|profile' \
    --version 1.0.1 --build 2 --team-id TEAMID1234 --notary-profile ""
assert_release_outputs_absent 1.0.1 "notary profile validation"

# A failed credential preflight must invalidate every predictable same-version
# upload target, including stale artifacts left by an earlier release attempt.
seed_release_outputs 1.0.1

expect_failure "unavailable notary profile fails closed before building" 'notary|profile|credential' \
    --version 1.0.1 --build 2 --team-id TEAMID1234 \
    --notary-profile "codex-release-test-${SANDBOX##*.}-does-not-exist"

assert_release_outputs_absent 1.0.1 "credential preflight"
if compgen -G "$SANDBOX/ClaudeMDSwitcher-v*-arm64.zip" >/dev/null; then
    printf 'FAIL: credential preflight created an unexpected release ZIP\n' >&2
    exit 1
fi
if [[ -e "$SANDBOX/swift-build-was-called" ]]; then
    printf 'FAIL: credential preflight reached swift build\n' >&2
    exit 1
fi

# With credential preflight stubbed successful, provenance failures must still
# stop before Swift. Use a clean temporary repository, then exercise both dirty
# working-tree and missing signed-tag rejection.
printf '#!/bin/bash\nexit 0\n' >"$SANDBOX/bin/xcrun"
git -C "$SANDBOX" init -q
git -C "$SANDBOX" config user.name 'Release Test'
git -C "$SANDBOX" config user.email 'release-test@example.invalid'
git -C "$SANDBOX" add release.sh bin/xcrun bin/swift
git -C "$SANDBOX" commit -qm 'test fixture'

printf 'dirty\n' >"$SANDBOX/untracked-sentinel"
expect_failure "dirty working tree blocks release before building" 'clean|working tree|provenance' \
    "${valid[@]}"
rm -f "$SANDBOX/untracked-sentinel"

expect_failure "missing signed release tag blocks release before building" 'tag|signed|signature' \
    "${valid[@]}"
if [[ -e "$SANDBOX/swift-build-was-called" ]]; then
    printf 'FAIL: provenance preflight reached swift build\n' >&2
    exit 1
fi

seed_release_outputs 1.0.1
expect_failure "unknown option" 'unknown|usage' "${valid[@]}" --unexpected
assert_release_outputs_absent 1.0.1 "unknown-option validation"
if [[ -e "$SANDBOX/swift-build-was-called" ]]; then
    printf 'FAIL: early argument validation reached swift build\n' >&2
    exit 1
fi

printf 'PASS: %d release preflight checks\n' "$pass_count"
