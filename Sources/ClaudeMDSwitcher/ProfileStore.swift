import Foundation
import AppKit
import Combine
import ClaudeMDSwitcherCore

struct Profile: Identifiable, Equatable {
    let url: URL
    let displayName: String
    let target: ProfileTarget

    var id: String { url.path }

    init(url: URL, target: ProfileTarget) {
        self.url = url
        self.target = target
        self.displayName = target.layout.displayName(
            forProfileFileName: url.lastPathComponent
        )
    }
}

@MainActor
final class ProfileStore: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var activePath: URL?
    @Published private(set) var selectedTarget: ProfileTarget
    @Published private(set) var codexOverrideTakesPrecedence = false

    private let homeDirectory: URL
    private let defaults: UserDefaults
    private let watcher = DirectoryWatcher()
    private let overrideWatcher = DirectoryWatcher()
    private var debounceItem: DispatchWorkItem?

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        defaults: UserDefaults = .standard
    ) {
        self.homeDirectory = homeDirectory
        self.defaults = defaults
        self.selectedTarget = ProfileTarget.loadSelection(from: defaults)

        rescan()
        startWatchingSelectedDirectory()
    }

    private var selectedDirectory: URL {
        homeDirectory.appendingPathComponent(selectedTarget.directoryName, isDirectory: true)
    }

    deinit {
        watcher.stop()
        overrideWatcher.stop()
    }

    func isActive(_ profile: Profile) -> Bool {
        guard let active = activePath else { return false }
        return ProfileDiscovery.fileURLsAreEquivalent(active, profile.url)
    }

    func selectTarget(_ target: ProfileTarget) {
        guard target != selectedTarget else { return }

        debounceItem?.cancel()
        watcher.stop()
        overrideWatcher.stop()
        selectedTarget = target
        target.persistSelection(to: defaults)
        rescan()
        startWatchingSelectedDirectory()
    }

    func rescan() {
        let target = selectedTarget
        let directory = selectedDirectory
        self.profiles = ProfileDiscovery.profileURLs(in: directory, layout: target.layout)
            .map { Profile(url: $0, target: target) }
        self.activePath = ProfileDiscovery.activeProfileURL(in: directory, layout: target.layout)
        self.codexOverrideTakesPrecedence =
            target == .codex && hasNonEmptyCodexOverride(in: directory)
    }

    func refresh() {
        rescan()
        startWatchingSelectedDirectory()
    }

    func activate(_ profile: Profile) {
        guard profile.target == selectedTarget else { return }

        do {
            try ProfileActivation.activate(
                profileURL: profile.url,
                in: selectedDirectory,
                layout: selectedTarget.layout
            )
        } catch {
            FileHandle.standardError.write(Data("[ClaudeMDSwitcher] activate failed: \(error)\n".utf8))
        }
        rescan()
    }

    func revealSelectedDirectory() {
        NSWorkspace.shared.activateFileViewerSelecting([selectedDirectory])
    }

    private func startWatchingSelectedDirectory() {
        let watchedTarget = selectedTarget
        watcher.start(at: selectedDirectory) { [weak self] in
            Task { @MainActor in
                guard self?.selectedTarget == watchedTarget else { return }
                self?.scheduleRescan()
            }
        }
        startWatchingCodexOverride()
    }

    private func startWatchingCodexOverride() {
        overrideWatcher.stop()
        guard selectedTarget == .codex else { return }

        let override = selectedDirectory.appendingPathComponent("AGENTS.override.md")
        guard (try? FileManager.default.attributesOfItem(atPath: override.path)) != nil else {
            return
        }
        overrideWatcher.start(at: override) { [weak self] in
            Task { @MainActor in
                guard self?.selectedTarget == .codex else { return }
                self?.overrideWatcher.stop()
                self?.scheduleRescan()
            }
        }
    }

    private func hasNonEmptyCodexOverride(in directory: URL) -> Bool {
        let override = directory.appendingPathComponent("AGENTS.override.md")
        do {
            let handle = try FileHandle(forReadingFrom: override)
            defer { try? handle.close() }
            return try handle.read(upToCount: 1)?.isEmpty == false
        } catch {
            return false
        }
    }

    private func scheduleRescan() {
        debounceItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.rescan()
            self?.startWatchingCodexOverride()
        }
        debounceItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300), execute: item)
    }
}
