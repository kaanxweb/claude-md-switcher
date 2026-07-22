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
   - **v1.0.0:** it is ad-hoc signed, so on first launch right-click `ClaudeMDSwitcher.app`, choose **Open**, then confirm **Open**. Do not remove its quarantine metadata. v1.0.0 cannot update itself; manually download v1.0.1 and replace the app once.
   - **v1.0.1 and later, once published:** these builds are intended to be Developer ID-signed and notarized. Double-click `ClaudeMDSwitcher.app` normally.
4. The stacked-cubes icon should appear in your menu bar.

v1.0.1 is the Sparkle trust-root release. It automatically checks the signed stable update feed and adds **Check for Updates…** to the menu. Download and installation remain user-approved; updates are not installed silently (`SUAutomaticallyUpdate=false`, `SUAllowsAutomaticUpdates=false`). Replacing or updating the app does not modify profiles in `~/.claude/`.

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
- **Check for Updates…** → checks the signed stable feed and lets you approve an available download and installation. The app also checks automatically, but never installs an update silently.
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

### 1. Prepare signing, notarization, and Sparkle keys locally

Install the repository maintainer's **Developer ID Application** certificate and its private key in the local login Keychain. Create an app-specific password for the Apple ID, then store it in a local `notarytool` Keychain profile:

```bash
xcrun notarytool store-credentials "ClaudeMDSwitcher-notary" \
  --apple-id "maintainer@example.com" \
  --team-id "TEAMID1234"
```

Enter the app-specific password only at the interactive prompt. Do not put it on the command line, in an environment variable, or in a repository file.

Do not provision this repository's GitHub Actions by exporting or uploading the Developer ID private key, or by storing a raw Apple password or app-specific password there. The release is signed and notarized on the trusted maintainer Mac; GitHub receives only the finished artifact.

After resolving the Sparkle 2.9.4 package and building it locally, generate or retrieve the release feed key under the dedicated Keychain account:

```bash
swift package resolve
swift build
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account kaanxweb
```

Commit only the printed public key as `SUPublicEDKey`. The Sparkle private key remains in the maintainer's login Keychain. Immediately export a backup directly to a mounted encrypted offline volume, with owner-only access (replace the example volume name):

```bash
sparkle_backup_volume='/Volumes/Encrypted Release Keys'
sparkle_backup="$sparkle_backup_volume/claude-md-switcher-sparkle-private-key"
test -d "$sparkle_backup_volume"
(
  umask 077
  .build/artifacts/sparkle/Sparkle/bin/generate_keys \
    --account kaanxweb \
    -x "$sparkle_backup"
)
chmod -N "$sparkle_backup"
chmod 600 "$sparkle_backup"
test -s "$sparkle_backup"
test "$(stat -f '%Lp' "$sparkle_backup")" = '600'
test "$(stat -f '%Su' "$sparkle_backup")" = "$(id -un)"
diskutil unmount "$sparkle_backup_volume"
```

Mount the volume again and test recovery on a controlled Mac before proceeding. Never leave an exported copy on an unencrypted internal disk or put it in this repository, GitHub Actions, or a GitHub release asset. The command above is a required setup step; this documentation does not claim that the backup already exists.

The app sets `SUSignedFeedFailureExpirationInterval=0`, so a feed that fails signature validation never becomes eligible for Sparkle's recovery mode. This protects users from a compromised feed indefinitely. If every copy of the Sparkle private key is lost, automatic key rotation is intentionally unavailable: publish a recovery build on GitHub and direct users to manually install a Developer-ID-signed and notarized disk image. The current ZIP-only release pipeline is not a lost-key recovery path.

### 2. Create and verify the local signed, annotated release tag

Start from the exact release commit with no tracked or untracked changes. The status command must print nothing:

```bash
git fetch origin
git status --porcelain --untracked-files=all
ssh-add --apple-use-keychain ~/.ssh/claude_md_switcher_release_signing
git config --local gpg.format ssh
git config --local user.signingkey ~/.ssh/claude_md_switcher_release_signing.pub
git config --local gpg.ssh.allowedSignersFile .github/release-signers
git config --local tag.gpgSign true
git tag -s v1.0.1 -m "ClaudeMDSwitcher 1.0.1"
git tag -v v1.0.1
test "$(git rev-parse HEAD)" = "$(git rev-list -n 1 v1.0.1)"
```

The authorized release key is pinned in `.github/release-signers` with fingerprint `SHA256:PAF5hWTFuJzAFzhrjE0AgmsEl+5DHOTsyixO2zD1PLg`. `release.sh` rejects a cryptographically valid tag from any other key. Keep the signed tag local for now. Do not push it until the artifact built from this exact commit has passed verification and the hardened workflow is present on the default branch.

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
  --notary-profile ClaudeMDSwitcher-notary \
  --sparkle-key-account kaanxweb

codesign --verify --deep --strict --verbose=2 ClaudeMDSwitcher.app
codesign -dv --verbose=4 ClaudeMDSwitcher.app 2>&1
xcrun stapler validate ClaudeMDSwitcher.app
spctl --assess --type execute --verbose=4 ClaudeMDSwitcher.app
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' ClaudeMDSwitcher.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' ClaudeMDSwitcher.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' ClaudeMDSwitcher.app/Contents/Info.plist
lipo -archs ClaudeMDSwitcher.app/Contents/MacOS/ClaudeMDSwitcher
shasum -a 256 -c ClaudeMDSwitcher-v1.0.1-arm64.zip.sha256
.build/artifacts/sparkle/Sparkle/bin/sign_update \
  --account kaanxweb \
  --verify appcast.xml
```

`release.sh` emits `ClaudeMDSwitcher.app`, the release ZIP, its checksum, the retained notarization log, and `appcast.xml`. It fails unless the working tree is clean and `HEAD` is exactly the signed, annotated `v1.0.1` tag. It also verifies the packaged app's bundle identifier, version, build number, arm64-only architecture, and signed Sparkle feed, and fails on a public/private Sparkle key mismatch or an unsigned or malformed feed. Confirm the commands above report the Developer ID Application authority, expected Team ID, `com.kaanxweb.claude-md-switcher`, `1.0.1`, `2`, and `arm64`. The bundle identifier stays unchanged because macOS and `SMAppService.mainApp` use it as the app and login-item identity.

The appcast enclosure must use the immutable tag-specific ZIP URL, `https://github.com/kaanxweb/claude-md-switcher/releases/download/v1.0.1/ClaudeMDSwitcher-v1.0.1-arm64.zip`. Do not hand-edit `appcast.xml` after signing it; regenerate and re-sign it instead.

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

Before creating the trust-root release, enable **Settings → General → Releases → Enable release immutability** for the repository. Immutability applies only to releases published after it is enabled. Confirm the API reports `true`:

```bash
test "$(gh api \
  -H 'Accept: application/vnd.github+json' \
  -H 'X-GitHub-Api-Version: 2026-03-10' \
  repos/kaanxweb/claude-md-switcher/immutable-releases \
  --jq '.enabled')" = 'true'
```

Upload the already verified local ZIP, checksum, and signed appcast to a **draft** GitHub release:

```bash
gh release create v1.0.1 \
  ClaudeMDSwitcher-v1.0.1-arm64.zip \
  ClaudeMDSwitcher-v1.0.1-arm64.zip.sha256 \
  appcast.xml \
  --draft \
  --verify-tag \
  --title "ClaudeMDSwitcher 1.0.1" \
  --notes-file .github/release-notes-1.0.1.md
```

### 5. Re-download, verify, then publish

Record the local ZIP and appcast hashes, download all three draft assets to a fresh temporary directory, and require exact matches before publishing:

```bash
local_sha=$(shasum -a 256 ClaudeMDSwitcher-v1.0.1-arm64.zip | awk '{print $1}')
local_appcast_sha=$(shasum -a 256 appcast.xml | awk '{print $1}')
verify_dir=$(mktemp -d)
gh release download v1.0.1 \
  --pattern 'ClaudeMDSwitcher-v1.0.1-arm64.zip' \
  --pattern 'ClaudeMDSwitcher-v1.0.1-arm64.zip.sha256' \
  --pattern 'appcast.xml' \
  --dir "$verify_dir"
download_sha=$(shasum -a 256 "$verify_dir/ClaudeMDSwitcher-v1.0.1-arm64.zip" | awk '{print $1}')
published_sha=$(awk '{print $1}' "$verify_dir/ClaudeMDSwitcher-v1.0.1-arm64.zip.sha256")
downloaded_appcast_sha=$(shasum -a 256 "$verify_dir/appcast.xml" | awk '{print $1}')
test "$local_sha" = "$download_sha"
test "$local_sha" = "$published_sha"
test "$local_appcast_sha" = "$downloaded_appcast_sha"
.build/artifacts/sparkle/Sparkle/bin/sign_update \
  --account kaanxweb \
  --verify "$verify_dir/appcast.xml"

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

Require the same expected bundle metadata and `arm64` output as the local artifact. If any hash, signature, checksum, or bundle verification differs, keep the release as a draft and investigate. If everything matches, publish the draft and mark it latest:

```bash
gh release edit v1.0.1 --draft=false --latest
gh release verify v1.0.1
gh release verify-asset v1.0.1 "$verify_dir/ClaudeMDSwitcher-v1.0.1-arm64.zip"
gh release verify-asset v1.0.1 "$verify_dir/ClaudeMDSwitcher-v1.0.1-arm64.zip.sha256"
gh release verify-asset v1.0.1 "$verify_dir/appcast.xml"
```

Finally, fetch the exact feed URL used by installed apps, compare it to the local signed appcast, and verify its embedded signature again:

```bash
stable_feed_url='https://github.com/kaanxweb/claude-md-switcher/releases/latest/download/appcast.xml'
curl --fail --location --output "$verify_dir/stable-appcast.xml" "$stable_feed_url"
stable_appcast_sha=$(shasum -a 256 "$verify_dir/stable-appcast.xml" | awk '{print $1}')
test "$local_appcast_sha" = "$stable_appcast_sha"
.build/artifacts/sparkle/Sparkle/bin/sign_update \
  --account kaanxweb \
  --verify "$verify_dir/stable-appcast.xml"
```

Every future latest stable release must include a freshly generated, signed `appcast.xml` whose enclosure points to that release's immutable tag-specific ZIP URL. Never hand-edit an appcast after signing it.

After the published assets and retained notarization log have been copied to their long-term release records, remove the local generated app, ZIP, checksum, appcast, and notarization log before preparing the next release. These outputs are ignored by Git and are regenerated for each version.

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
