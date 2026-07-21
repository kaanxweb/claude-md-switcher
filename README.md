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
3. Open the app according to the downloaded version:
   - **v1.0.0 (the current release):** it is ad-hoc signed, so on first launch right-click `ClaudeMDSwitcher.app`, choose **Open**, then confirm **Open**. Do not remove its quarantine metadata.
   - **v1.0.1 and later, once published:** these builds are intended to be Developer ID-signed and notarized. Double-click `ClaudeMDSwitcher.app` normally.
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

Production releases require Developer ID signing and notarization. Maintainers should follow [Maintainer release process](#maintainer-release-process); `release.sh` intentionally has no ad-hoc production fallback.

## Maintainer release process

The planned v1.0.1 (build 2) is the first Developer ID-signed, notarized, and stapled release. This section describes how to prepare it; it does not mean v1.0.1 has already been published.

### 1. Prepare signing and notarization locally

Install the repository maintainer's **Developer ID Application** certificate and its private key in the local login Keychain. Create an app-specific password for the Apple ID, then store it in a local `notarytool` Keychain profile:

```bash
xcrun notarytool store-credentials "ClaudeMDSwitcher-notary" \
  --apple-id "maintainer@example.com" \
  --team-id "TEAMID1234"
```

Enter the app-specific password only at the interactive prompt. Do not put it on the command line, in an environment variable, or in a repository file.

Do not provision this repository's GitHub Actions by exporting or uploading the Developer ID private key, or by storing a raw Apple password or app-specific password there. The release is signed and notarized on the trusted maintainer Mac; GitHub receives only the finished artifact.

### 2. Create and verify the local signed, annotated release tag

Start from the exact release commit with no tracked or untracked changes. The status command must print nothing:

```bash
git fetch origin
git status --porcelain --untracked-files=all
git tag -s v1.0.1 -m "ClaudeMDSwitcher 1.0.1"
git tag -v v1.0.1
test "$(git rev-parse HEAD)" = "$(git rev-list -n 1 v1.0.1)"
```

Keep the signed tag local for now. Do not push it until the artifact built from this exact commit has passed verification and the hardened workflow is present on the default branch.

### 3. Build and verify the tagged source

Check out the local tag directly, confirm the checkout is still clean, then build:

```bash
git checkout --detach v1.0.1
test -z "$(git status --porcelain --untracked-files=all)"
test "$(git describe --exact-match --tags HEAD)" = "v1.0.1"

./release.sh \
  --version 1.0.1 \
  --build 2 \
  --team-id TEAMID1234 \
  --notary-profile ClaudeMDSwitcher-notary

codesign --verify --deep --strict --verbose=2 ClaudeMDSwitcher.app
codesign -dv --verbose=4 ClaudeMDSwitcher.app 2>&1
xcrun stapler validate ClaudeMDSwitcher.app
spctl --assess --type execute --verbose=4 ClaudeMDSwitcher.app
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' ClaudeMDSwitcher.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' ClaudeMDSwitcher.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' ClaudeMDSwitcher.app/Contents/Info.plist
lipo -archs ClaudeMDSwitcher.app/Contents/MacOS/ClaudeMDSwitcher
shasum -a 256 -c ClaudeMDSwitcher-v1.0.1-arm64.zip.sha256
```

`release.sh` fails unless the working tree is clean and `HEAD` is exactly the signed, annotated `v1.0.1` tag. It also verifies the packaged app's bundle identifier, version, build number, and arm64-only architecture. Confirm the commands above report the Developer ID Application authority, expected Team ID, `com.kaanxweb.claude-md-switcher`, `1.0.1`, `2`, and `arm64`. The bundle identifier stays unchanged because macOS and `SMAppService.mainApp` use it as the app and login-item identity.

### 4. Push the verified tag and create a draft release

> **Do not push a release tag while the old tag-triggered workflow can automatically publish it.** First merge and verify a hardened workflow that cannot rebuild, replace, or publish the locally verified artifact.

Fetch the default branch again. Confirm the tagged commit is contained in it, and inspect its workflow before pushing:

```bash
git fetch origin main
git merge-base --is-ancestor "$(git rev-list -n 1 v1.0.1)" origin/main
git show origin/main:.github/workflows/release.yml
```

Only after confirming that the default-branch workflow has no tag-triggered publishing path, push the already-built and verified tag:

```bash
git push origin v1.0.1
```

Upload the already verified local zip to a **draft** GitHub release:

```bash
gh release create v1.0.1 \
  ClaudeMDSwitcher-v1.0.1-arm64.zip \
  ClaudeMDSwitcher-v1.0.1-arm64.zip.sha256 \
  --draft \
  --verify-tag \
  --title "ClaudeMDSwitcher 1.0.1" \
  --notes-file .github/release-notes-1.0.1.md
```

### 5. Re-download, verify, then publish

Record the local checksum, download the draft asset to a fresh temporary directory, and require an exact match before publishing:

```bash
local_sha=$(shasum -a 256 ClaudeMDSwitcher-v1.0.1-arm64.zip | awk '{print $1}')
verify_dir=$(mktemp -d)
gh release download v1.0.1 \
  --pattern 'ClaudeMDSwitcher-v1.0.1-arm64.zip' \
  --dir "$verify_dir"
gh release download v1.0.1 \
  --pattern 'ClaudeMDSwitcher-v1.0.1-arm64.zip.sha256' \
  --dir "$verify_dir"
download_sha=$(shasum -a 256 "$verify_dir/ClaudeMDSwitcher-v1.0.1-arm64.zip" | awk '{print $1}')
published_sha=$(awk '{print $1}' "$verify_dir/ClaudeMDSwitcher-v1.0.1-arm64.zip.sha256")
test "$local_sha" = "$download_sha"
test "$local_sha" = "$published_sha"

mkdir "$verify_dir/extracted"
/usr/bin/ditto -x -k \
  "$verify_dir/ClaudeMDSwitcher-v1.0.1-arm64.zip" \
  "$verify_dir/extracted"
downloaded_app="$verify_dir/extracted/ClaudeMDSwitcher.app"
codesign --verify --deep --strict --verbose=2 "$downloaded_app"
xcrun stapler validate "$downloaded_app"
spctl --assess --type execute --verbose=4 "$downloaded_app"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$downloaded_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$downloaded_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$downloaded_app/Contents/Info.plist"
lipo -archs "$downloaded_app/Contents/MacOS/ClaudeMDSwitcher"
```

Require the same expected bundle metadata and `arm64` output as the local artifact. If any checksum or verification differs, keep the release as a draft and investigate. If everything matches, publish the draft:

```bash
gh release edit v1.0.1 --draft=false
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| No icon appears in menu bar after launch | Check `pgrep -x ClaudeMDSwitcher`. If running but invisible, your menu bar may be full — try Bartender, or kill some other status item. |
| "App is damaged and can't be opened" | Delete that copy and download it again from the official release. For v1.0.1+, verify the published SHA-256 checksum. Do not strip quarantine metadata or bypass an unexpected Gatekeeper warning; v1.0.0's supported first-open step is documented under [Install](#install). |
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
