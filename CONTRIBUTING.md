# Contributing

Thanks for your interest in ClaudeMDSwitcher.

## Build

```bash
./build.sh         # fast dev build (ad-hoc signed)
open ClaudeMDSwitcher.app
```

## Test

```bash
swift test
bash tests/test_release_script.sh
bash tests/test_bundle_packaging.sh
```

The Swift test exercises the symlink-swap logic in a sandboxed temp directory; it does not touch your real `~/.claude/`. The release shell test exercises fail-closed argument, credential, stale-artifact, and signed-tag/provenance preflight behavior in a temporary copy; it does not build, sign, or modify release artifacts. The bundle shell test runs the real development build, then verifies the arm64 app's Sparkle framework, metadata, linkage, symlinks, and signatures without launching the app or contacting its update feed.

## Style

- Swift 5.9+ syntax, `@MainActor` annotations where state mutates from menu callbacks.
- Avoid view modifiers on SwiftUI views inside a `.menuBarExtraStyle(.menu)` MenuBarExtra — they're stripped by NSMenuItem. Encode state in `Text` content. See `tasks/lessons.md` for the full lesson.

## PRs

- One concern per PR.
- Run `swift test` before opening.
- Describe the user-visible change in the PR body, even if small.
- Treat `SUPublicEDKey`, `.github/release-signers`, the stable appcast URL, fail-closed signed-feed validation (`SUSignedFeedFailureExpirationInterval=0`), and user-approved installation (`SUAutomaticallyUpdate=false`, `SUAllowsAutomaticUpdates=false`) as release security boundaries. Follow the [maintainer release process](README.md#maintainer-release-process) for tag, feed, and artifact verification; never commit a private key or hand-edit a signed appcast.

## License

By contributing, you agree your changes are licensed under the project's MIT [LICENSE](LICENSE).
