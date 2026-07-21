# Changelog

All notable changes to ClaudeMDSwitcher are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] — Unreleased

### Added
- Added secure automatic update checks through Sparkle 2.9.4 and a **Check for Updates…** menu command. Downloads and installations remain user-approved (`SUAutomaticallyUpdate=false`).

### Security
- Hardened the distribution process to require Developer ID Application signing, Apple notarization, and ticket stapling; release builds now fail closed instead of falling back to ad-hoc signing.
- Moved notarization credentials to a local Keychain profile and required a clean checkout at the exact signed, annotated version tag before building.
- Added packaged bundle-identifier, version, build-number, arm64 architecture, checksum, and draft-release verification gates before publication.
- Added a signed Sparkle appcast and embedded public key, making v1.0.1 the update trust-root release.

### Fixed
- Preserved a later regular `~/.claude/CLAUDE.md` as a uniquely named recovery profile when `CLAUDE.default.md` already exists, avoiding content loss during profile switching.

v1.0.0 cannot self-update, so users must manually replace it with v1.0.1 once. Profiles in `~/.claude/` are unaffected. v1.0.1 uses build number 2 and is intended to be the first Developer ID-signed and notarized release.

## [1.0.0] — 2026-05-14

### Added
- Initial release.
- Auto-discovery of `~/.claude/CLAUDE.*.md` profile files.
- Atomic symlink swap of `~/.claude/CLAUDE.md` to the chosen profile (`rename(2)`-based).
- First-run backup of existing regular `CLAUDE.md` to `CLAUDE.default.md`.
- Menu items: profile list with active-state checkmark, Reveal in Finder, Refresh, Launch at Login toggle, Quit.
- Live re-scan on `~/.claude/` directory changes via `DispatchSource.makeFileSystemObjectSource`.
- Launch at Login via `SMAppService.mainApp`, with graceful fallback to "Open Login Items Settings…" when approval is required.
- Custom AppIcon derived from the `square.stack.3d.up` SF Symbol.
- GitHub Actions workflow that builds and publishes a release `.zip` on every `v*.*.*` tag.
- Standalone integration test (`tests/test_swap.swift`) verifying the four critical swap-logic code paths.
