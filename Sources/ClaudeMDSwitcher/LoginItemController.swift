import Foundation
import ServiceManagement
import AppKit

// WARNING: SMAppService.mainApp keys on CFBundleIdentifier. Changing the
// bundle identifier in Info.plist will ORPHAN any existing user
// registrations — they'll see a ghost entry in System Settings > General >
// Login Items pointing at the old bundle ID. If you ever rename the bundle,
// document a migration step for users who had Launch at Login enabled.
@MainActor
final class LoginItemController: ObservableObject {
    @Published var enabled: Bool = false
    @Published var needsApproval: Bool = false

    init() {
        refresh()
    }

    func refresh() {
        enabled = SMAppService.mainApp.status == .enabled
    }

    func toggle() {
        refresh()
        do {
            if enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
                needsApproval = false
            }
            refresh()
        } catch {
            FileHandle.standardError.write(Data("[ClaudeMDSwitcher] login toggle failed: \(error)\n".utf8))
            // The most common failure on first register is the user needing
            // to approve the app under Settings > General > Login Items.
            needsApproval = true
        }
    }

    func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
