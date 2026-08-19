# ClaudeMDSwitcher 1.1.0

This release adds first-class Codex Markdown profile switching alongside the existing Claude workflow. Users on v1.0.1 can install it through the signed **Check for Updates…** flow.

- Added isolated Codex profiles using `~/.codex/AGENTS.<name>.md`, activated through `~/.codex/AGENTS.md`.
- Added a persistent Claude/Codex target selector with isolated discovery and active-state handling.
- Added an `AGENTS.override.md` precedence warning; override files are excluded and never modified.
- Hardened profile activation with atomic exchange/exclusive renames so concurrent files and unmanaged symlinks are preserved.
- Added cross-target, reserved-name, and self-referential-link validation.

v1.1.0 uses build number 3 and is Developer ID-signed, notarized, stapled, and distributed through the signed Sparkle update feed.
