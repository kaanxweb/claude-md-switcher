import Foundation
import AppKit
import Combine

struct Profile: Identifiable, Equatable {
    let url: URL
    let displayName: String

    var id: String { url.path }

    init(url: URL) {
        self.url = url
        let filename = url.lastPathComponent
        // CLAUDE.<name>.md -> <name> -> Titlecased
        var name = filename
        if name.hasPrefix("CLAUDE.") { name.removeFirst("CLAUDE.".count) }
        if name.hasSuffix(".md") { name.removeLast(".md".count) }
        if name.isEmpty {
            self.displayName = filename
        } else {
            self.displayName = name.prefix(1).uppercased() + name.dropFirst()
        }
    }
}

@MainActor
final class ProfileStore: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var activePath: URL?

    let claudeDir: URL
    private let mainFile: URL
    private let defaultBackup: URL
    private let watcher = DirectoryWatcher()
    private var debounceItem: DispatchWorkItem?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.claudeDir = home.appendingPathComponent(".claude", isDirectory: true)
        self.mainFile = claudeDir.appendingPathComponent("CLAUDE.md")
        self.defaultBackup = claudeDir.appendingPathComponent("CLAUDE.default.md")

        rescan()

        watcher.start(at: claudeDir) { [weak self] in
            Task { @MainActor in
                self?.scheduleRescan()
            }
        }
    }

    deinit {
        watcher.stop()
    }

    func isActive(_ profile: Profile) -> Bool {
        guard let active = activePath else { return false }
        return active.standardizedFileURL.path == profile.url.standardizedFileURL.path
    }

    func rescan() {
        let fm = FileManager.default
        var found: [Profile] = []

        if let entries = try? fm.contentsOfDirectory(at: claudeDir, includingPropertiesForKeys: nil) {
            for entry in entries {
                let name = entry.lastPathComponent
                guard name.hasPrefix("CLAUDE."), name.hasSuffix(".md"), name != "CLAUDE.md" else { continue }
                found.append(Profile(url: entry))
            }
        }

        found.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        self.profiles = found
        self.activePath = resolveActivePath()
    }

    private func resolveActivePath() -> URL? {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: mainFile.path),
              let type = attrs[.type] as? FileAttributeType,
              type == .typeSymbolicLink else {
            return nil
        }
        guard let dest = try? fm.destinationOfSymbolicLink(atPath: mainFile.path) else {
            return nil
        }
        let destURL: URL
        if (dest as NSString).isAbsolutePath {
            destURL = URL(fileURLWithPath: dest)
        } else {
            destURL = claudeDir.appendingPathComponent(dest)
        }
        return destURL.standardizedFileURL
    }

    func activate(_ profile: Profile) {
        let fm = FileManager.default

        do {
            // Step 1: if CLAUDE.md exists and is a regular file (not a symlink), back it up.
            if fm.fileExists(atPath: mainFile.path) {
                let attrs = try fm.attributesOfItem(atPath: mainFile.path)
                let type = attrs[.type] as? FileAttributeType
                if type != .typeSymbolicLink {
                    if !fm.fileExists(atPath: defaultBackup.path) {
                        try fm.moveItem(at: mainFile, to: defaultBackup)
                    } else {
                        // Backup already exists — discard the current regular file.
                        try fm.removeItem(at: mainFile)
                    }
                }
            }

            // Step 2: atomic symlink swap via temp + rename(2).
            // FileManager.replaceItemAt fails when the original is a symlink
            // (NSCocoaErrorDomain 4), so use POSIX rename which atomically
            // overwrites any existing entry — symlink or regular file.
            let tempName = ".CLAUDE.md.swap-\(UUID().uuidString)"
            let tempURL = claudeDir.appendingPathComponent(tempName)
            // Use relative target so the link is portable within ~/.claude/
            try fm.createSymbolicLink(atPath: tempURL.path, withDestinationPath: profile.url.lastPathComponent)

            if rename(tempURL.path, mainFile.path) != 0 {
                let err = String(cString: strerror(errno))
                try? fm.removeItem(at: tempURL)
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "rename failed: \(err)"])
            }

            self.activePath = profile.url.standardizedFileURL
        } catch {
            FileHandle.standardError.write(Data("[ClaudeMDSwitcher] activate failed: \(error)\n".utf8))
        }
    }

    func revealClaudeDir() {
        NSWorkspace.shared.activateFileViewerSelecting([claudeDir])
    }

    private func scheduleRescan() {
        debounceItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.rescan()
        }
        debounceItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300), execute: item)
    }
}
