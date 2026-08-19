# Changelog

All notable changes to ClaudeMDSwitcher are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] — 2026-08-19

### Added
- Added first-class Codex Markdown profiles using the app convention `~/.codex/AGENTS.<name>.md`, activated through Codex's canonical `~/.codex/AGENTS.md`.
- Added a persistent Claude/Codex target selector, isolated discovery and active-state handling, and an `AGENTS.override.md` precedence warning.

### Security
- Replaced overwrite-style canonical-file renames with atomic exchange/exclusive renames, preserving concurrently created files and unmanaged symlinks instead of discarding them.
- Added validation that prevents a Claude profile from being activated into the Codex target or vice versa.
- Rejects profile links that resolve back to the canonical file and profile names that collide with reserved files under the volume's filename rules.

## [1.0.1] — 2026-07-24

### Added
- Added secure automatic update checks through Sparkle 2.9.4 and a **Check for Updates…** menu command. Downloads and installations remain user-approved (`SUAutomaticallyUpdate=false`).

### Security
- Hardened the distribution process to require Developer ID Application signing, Apple notarization, and ticket stapling; release builds now fail closed instead of falling back to ad-hoc signing.
- Moved notarization credentials to a local Keychain profile and required a clean checkout at the exact signed, annotated version tag before building.
- Added packaged bundle-identifier, version, build-number, arm64 architecture, checksum, and draft-release verification gates before publication.
- Added a signed Sparkle appcast and embedded public key, making v1.0.1 the update trust-root release.

### Fixed
- Preserved a later regular `~/.claude/CLAUDE.md` as a uniquely named recovery profile when `CLAUDE.default.md` already exists, avoiding content loss during profile switching.

v1.0.0 cannot self-update, so users must manually replace it with v1.0.1 once. Profiles in `~/.claude/` are unaffected. v1.0.1 uses build number 2 and is the first Developer ID-signed and notarized release.

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
