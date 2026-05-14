# Contributing

Thanks for your interest in ClaudeMDSwitcher.

## Build

```bash
./build.sh         # fast dev build (ad-hoc signed)
open ClaudeMDSwitcher.app
```

## Test

```bash
swift tests/test_swap.swift
```

The test exercises the symlink-swap logic in a sandboxed temp directory; it does not touch your real `~/.claude/`.

## Style

- Swift 5.9+ syntax, `@MainActor` annotations where state mutates from menu callbacks.
- Avoid view modifiers on SwiftUI views inside a `.menuBarExtraStyle(.menu)` MenuBarExtra — they're stripped by NSMenuItem. Encode state in `Text` content. See `tasks/lessons.md` for the full lesson.

## PRs

- One concern per PR.
- Run `swift tests/test_swap.swift` before opening.
- Describe the user-visible change in the PR body, even if small.

## License

By contributing, you agree your changes are licensed under the project's MIT [LICENSE](LICENSE).
