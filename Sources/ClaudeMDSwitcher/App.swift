import SwiftUI
import AppKit
import ServiceManagement
import ClaudeMDSwitcherCore

@main
struct ClaudeMDSwitcherApp: App {
    @StateObject private var store = ProfileStore()
    @StateObject private var loginItem = LoginItemController()
    @StateObject private var updater = UpdaterController()

    var body: some Scene {
        MenuBarExtra {
            menuContent
        } label: {
            Image(systemName: "square.stack.3d.up")
        }
        .menuBarExtraStyle(.menu)
    }

    @ViewBuilder private var menuContent: some View {
        Menu("Target: \(store.selectedTarget.displayName)") {
            ForEach(ProfileTarget.allCases) { target in
                Button {
                    store.selectTarget(target)
                } label: {
                    Text(store.selectedTarget == target ? "✓ \(target.displayName)" : "   \(target.displayName)")
                }
            }
        }
        Divider()
        if store.codexOverrideTakesPrecedence {
            Text("AGENTS.override.md takes precedence")
                .disabled(true)
        }
        if store.profiles.isEmpty {
            Text("No \(store.selectedTarget.layout.profilePattern) profiles found")
                .disabled(true)
        } else {
            ForEach(store.profiles) { profile in
                // NSMenuItem (the AppKit backing for MenuBarExtra .menu style)
                // ignores .opacity() on child views, so the checkmark must be
                // conditionally present, not invisible. Prefix the active item
                // with a U+2713 in its display string instead of a child Image.
                Button {
                    store.activate(profile)
                } label: {
                    Text(store.isActive(profile) ? "✓ \(profile.displayName)" : "   \(profile.displayName)")
                }
            }
        }
        Divider()
        Button("Reveal in Finder") { store.revealSelectedDirectory() }
        Button("Refresh") { store.refresh() }
        Divider()
        // Same text-prefix pattern as profile rows — see [[NSMenuItem lesson]].
        // Recompute status on every body render (cheap enum read) so the
        // prefix reflects the live system state without manual refresh.
        Button {
            loginItem.toggle()
        } label: {
            let live = SMAppService.mainApp.status == .enabled
            Text(live ? "✓ Launch at Login" : "   Launch at Login")
        }
        if loginItem.needsApproval {
            Button("Open Login Items Settings…") {
                loginItem.openLoginItemsSettings()
            }
        }
        Divider()
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
        Divider()
        Button("Quit") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
