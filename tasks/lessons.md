# Lessons

## NSMenuItem inside MenuBarExtra strips SwiftUI view modifiers

**Rule:** When using `MenuBarExtra { ... }.menuBarExtraStyle(.menu)`, SwiftUI renders
the menu contents as native `NSMenuItem`s. NSMenuItem ignores most SwiftUI modifiers
on child views — including `.opacity()`, `.padding()`, custom backgrounds, and most
layout modifiers. Distinguish menu states via `Text` content, not view modifiers.

**Symptom:** `Image("checkmark").opacity(active ? 1 : 0)` renders the image visible
on every row, regardless of `active`. The data layer is correct; the UI is wrong.

**Root cause:** `.menu` style uses AppKit's NSMenuItem rendering path, which only
honors a small set of SwiftUI features (`Text`, `Image` as standalone item icon,
`Button` action, `keyboardShortcut`, `Divider`). View modifiers on subviews are
silently dropped.

**Fix:** Encode menu state into the `Text` content itself. e.g. `"✓ Foo"` when
active, `"   Foo"` (matching whitespace) when not. NSMenuItem renders text
verbatim, so this path can't degrade.

**Detection:** Unit tests on the data layer pass; code review reads correct. ONLY
visual testing of the running app catches this. Treat any MenuBarExtra/.menu UI
change as needing a manual click-through.
