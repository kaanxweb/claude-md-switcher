import Foundation
import XCTest
@testable import ClaudeMDSwitcher
@testable import ClaudeMDSwitcherCore

@MainActor
final class ProfileStoreTests: XCTestCase {
    func testDefaultClaudeSelectionAndPersistedCodexReconstruction() async throws {
        try await withIsolatedEnvironment { home, defaults in
            let claudeDirectory = home.appendingPathComponent(".claude", isDirectory: true)
            let codexDirectory = home.appendingPathComponent(".codex", isDirectory: true)
            try FileManager.default.createDirectory(
                at: claudeDirectory,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: codexDirectory,
                withIntermediateDirectories: true
            )
            try Data("claude".utf8).write(
                to: claudeDirectory.appendingPathComponent("CLAUDE.work.md")
            )
            try Data("codex".utf8).write(
                to: codexDirectory.appendingPathComponent("AGENTS.personal.md")
            )

            var store: ProfileStore? = ProfileStore(homeDirectory: home, defaults: defaults)
            XCTAssertEqual(store?.selectedTarget, .claude)
            XCTAssertEqual(store?.profiles.map(\.displayName), ["Work"])

            store?.selectTarget(.codex)
            XCTAssertEqual(store?.profiles.map(\.displayName), ["Personal"])
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: claudeDirectory.appendingPathComponent("CLAUDE.md").path
                )
            )
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: codexDirectory.appendingPathComponent("AGENTS.md").path
                )
            )
            store = nil

            store = ProfileStore(homeDirectory: home, defaults: defaults)
            XCTAssertEqual(store?.selectedTarget, .codex)
            XCTAssertEqual(store?.profiles.map(\.displayName), ["Personal"])
            store = nil
        }
    }

    func testRefreshRecoversAfterSelectedDirectoryIsCreated() async throws {
        try await withIsolatedEnvironment { home, defaults in
            var store: ProfileStore? = ProfileStore(homeDirectory: home, defaults: defaults)
            store?.selectTarget(.codex)
            XCTAssertTrue(store?.profiles.isEmpty == true)

            let codexDirectory = home.appendingPathComponent(".codex", isDirectory: true)
            try FileManager.default.createDirectory(
                at: codexDirectory,
                withIntermediateDirectories: true
            )
            try Data("work".utf8).write(
                to: codexDirectory.appendingPathComponent("AGENTS.work.md")
            )

            store?.refresh()
            XCTAssertEqual(store?.profiles.map(\.displayName), ["Work"])
            store = nil
        }
    }

    func testActiveCheckmarkUsesFilesystemEquivalentProfileSpelling() async throws {
        try await withIsolatedEnvironment { home, defaults in
            let codexDirectory = home.appendingPathComponent(".codex", isDirectory: true)
            try FileManager.default.createDirectory(
                at: codexDirectory,
                withIntermediateDirectories: true
            )
            let values = try codexDirectory.resourceValues(
                forKeys: [.volumeSupportsCaseSensitiveNamesKey]
            )
            guard values.volumeSupportsCaseSensitiveNames == false else {
                throw XCTSkip("Requires a case-insensitive volume")
            }

            let profile = codexDirectory.appendingPathComponent("AGENTS.Work.md")
            try Data("work".utf8).write(to: profile)
            try FileManager.default.createSymbolicLink(
                atPath: codexDirectory.appendingPathComponent("AGENTS.md").path,
                withDestinationPath: "AGENTS.work.md"
            )
            ProfileTarget.codex.persistSelection(to: defaults)

            let store = ProfileStore(homeDirectory: home, defaults: defaults)
            let discovered = try XCTUnwrap(store.profiles.first)
            XCTAssertEqual(discovered.url.lastPathComponent, profile.lastPathComponent)
            XCTAssertTrue(
                ProfileDiscovery.fileURLsAreEquivalent(discovered.url, profile)
            )
            XCTAssertTrue(store.isActive(discovered))
        }
    }

    func testCodexOverrideWarningTracksInPlaceFileChanges() async throws {
        try await withIsolatedEnvironment { home, defaults in
            try FileManager.default.createDirectory(
                at: home.appendingPathComponent(".claude", isDirectory: true),
                withIntermediateDirectories: true
            )
            let codexDirectory = home.appendingPathComponent(".codex", isDirectory: true)
            try FileManager.default.createDirectory(
                at: codexDirectory,
                withIntermediateDirectories: true
            )
            let override = codexDirectory.appendingPathComponent("AGENTS.override.md")
            try Data().write(to: override)

            var store: ProfileStore? = ProfileStore(homeDirectory: home, defaults: defaults)
            store?.selectTarget(.codex)
            XCTAssertFalse(store?.codexOverrideTakesPrecedence == true)

            try Data("override".utf8).write(to: override)
            try await Task.sleep(nanoseconds: 700_000_000)
            XCTAssertTrue(store?.codexOverrideTakesPrecedence == true)

            try Data().write(to: override)
            try await Task.sleep(nanoseconds: 700_000_000)
            XCTAssertFalse(store?.codexOverrideTakesPrecedence == true)
            store = nil
        }
    }

    private func withIsolatedEnvironment(
        _ body: (URL, UserDefaults) async throws -> Void
    ) async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("profile-store-test-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "ProfileStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defaults.removePersistentDomain(forName: suiteName)

        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: home)
        }
        try await body(home, defaults)
    }
}
