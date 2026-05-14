# ClaudeMDSwitcher

> Switch your `~/.claude/CLAUDE.md` profile from a macOS menu bar icon.

[![Build](https://github.com/kaanxweb/claude-md-switcher/actions/workflows/release.yml/badge.svg)](https://github.com/kaanxweb/claude-md-switcher/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)](https://www.apple.com/macos/)
[![Version](https://img.shields.io/github/v/release/kaanxweb/claude-md-switcher?label=version)](https://github.com/kaanxweb/claude-md-switcher/releases/latest)

## What it does

ClaudeMDSwitcher lets you keep multiple `CLAUDE.md` profiles side-by-side — one for work, one for personal projects, one per client — and swap between them with a single menu bar click. Under the hood it replaces `~/.claude/CLAUDE.md` with a symbolic link that points at the profile you picked, so every tool that reads `CLAUDE.md` (Claude Code, the Claude API, your own scripts) transparently sees the active profile.

## Demo

![demo gif](docs/demo.gif)
_(GIF placeholder — will be added in a future release.)_

## Install

### Option A — Download the prebuilt .app (recommended)

1. Grab the latest `ClaudeMDSwitcher-vX.Y.Z-arm64.zip` from [Releases](https://github.com/kaanxweb/claude-md-switcher/releases/latest).
2. Unzip, drag `ClaudeMDSwitcher.app` into `/Applications`.
3. Right-click → **Open** the first time (Gatekeeper warning is expected for ad-hoc signed builds — see [Why right-click → Open?](#why-right-click--open)).
4. The stacked-cubes icon should appear in your menu bar.

### Option B — Build from source

See [Building from source](#building-from-source).

## First-time setup

Create at least two profile files alongside your `~/.claude/CLAUDE.md`:

```bash
echo "# Work profile\nUse formal tone." > ~/.claude/CLAUDE.work.md
echo "# Personal profile\nUse casual tone." > ~/.claude/CLAUDE.personal.md
```

Click the menu bar icon. You should see **Work** and **Personal** listed. Click one — that's now your active profile.

> 📦 **What happens on first switch:** your original `~/.claude/CLAUDE.md` (a regular file) is renamed to `~/.claude/CLAUDE.default.md` for safekeeping, then `~/.claude/CLAUDE.md` becomes a symlink to the profile you picked. You'll see a third menu item, **Default**, that lets you switch back to your original content anytime.

## Usage

- **Click a profile** → switches `~/.claude/CLAUDE.md` to point at it. Checkmark (✓) marks the active one.
- **Reveal in Finder** → opens `~/.claude/` in Finder.
- **Refresh** → re-scans `~/.claude/` for profile files. The app already auto-refreshes when files are added or removed, but this is a manual fallback.
- **Launch at Login** → toggles whether the app starts automatically when you log in. On first enable, macOS may ask you to approve in **System Settings → General → Login Items**; an "Open Login Items Settings…" item appears in the menu if approval is needed.
- **Quit** (⌘Q) → exits the app.

## How it works (brief)

`~/.claude/CLAUDE.md` is replaced with a symbolic link pointing to the chosen `CLAUDE.<name>.md` file. The original is preserved as `CLAUDE.default.md`. Claude Code, Claude API tools, and any other tooling that reads `CLAUDE.md` will transparently follow the symlink.

## Building from source

Requirements: macOS 14+, Xcode Command Line Tools, Swift 5.9+.

```bash
git clone https://github.com/kaanxweb/claude-md-switcher.git
cd claude-md-switcher
./build.sh
open ClaudeMDSwitcher.app
```

For a versioned release build (used by CI):

```bash
./release.sh --version 1.0.0
```

## Future: Developer ID signing + notarization

v1 ships with ad-hoc signing — Gatekeeper warns on first launch. To produce notarized builds (no warning):

1. Get an Apple Developer ID Application certificate ($99/year).
2. Generate an app-specific password at [appleid.apple.com](https://appleid.apple.com).
3. Set three environment variables (or GitHub Actions secrets for CI):
   - `APPLE_TEAM_ID`
   - `APPLE_ID`
   - `APPLE_APP_PASSWORD`
4. Re-run `./release.sh --version X.Y.Z` — `notarytool` handles the rest.

The GitHub Actions release workflow already reads these as secrets; setting them in repo Settings → Secrets and variables → Actions is enough to enable notarization for future tagged releases.

## Why right-click → Open?

The v1 release uses ad-hoc code signing because I don't yet have an Apple Developer ID. macOS Gatekeeper treats ad-hoc-signed downloads as untrusted on first launch. Right-click → **Open** bypasses this check once — subsequent launches work normally. Future releases will be notarized.

## Troubleshooting

| Symptom | Fix |
|---|---|
| No icon appears in menu bar after launch | Check `pgrep -x ClaudeMDSwitcher`. If running but invisible, your menu bar may be full — try Bartender, or kill some other status item. |
| "App is damaged and can't be opened" | macOS quarantine. Run `xattr -dr com.apple.quarantine /Applications/ClaudeMDSwitcher.app`. |
| All profiles show ✓ | You're on a pre-v1.0 build. Re-download the latest release. |
| Menu is empty | No `CLAUDE.*.md` files in `~/.claude/`. Create at least one. |
| Launch at Login does nothing | First time, macOS may require approval — click **Open Login Items Settings…** (appears in the menu after the toggle is clicked) and enable the app there. |

## Uninstall

1. Quit the app (menu → Quit).
2. Drag `ClaudeMDSwitcher.app` to the Trash.
3. Optional: restore your original CLAUDE.md from the backup:
   ```bash
   rm ~/.claude/CLAUDE.md
   mv ~/.claude/CLAUDE.default.md ~/.claude/CLAUDE.md
   ```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE) © 2026 kaanxweb.
