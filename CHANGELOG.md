# Changelog

All notable changes to ClaudeMDSwitcher are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
