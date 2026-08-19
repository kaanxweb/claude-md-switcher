import Foundation
import XCTest
@testable import ClaudeMDSwitcherCore

final class ProfileTargetTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("profile-target-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testClaudeConventionsRemainUnchanged() {
        XCTAssertEqual(ProfileTarget.claude.directoryName, ".claude")
        XCTAssertEqual(ProfileTarget.claude.layout.mainFileName, "CLAUDE.md")
        XCTAssertEqual(ProfileTarget.claude.layout.defaultBackupFileName, "CLAUDE.default.md")
        XCTAssertEqual(ProfileTarget.claude.layout.recoveryPrefix, "CLAUDE.recovered-")
        XCTAssertEqual(ProfileTarget.claude.layout.temporaryPrefix, ".CLAUDE.md.swap-")
        XCTAssertEqual(ProfileTarget.claude.layout.profilePattern, "CLAUDE.*.md")
    }

    func testCodexConventionsUseCanonicalDefaultFileAndReserveOverride() {
        XCTAssertEqual(ProfileTarget.codex.directoryName, ".codex")
        XCTAssertEqual(ProfileTarget.codex.layout.mainFileName, "AGENTS.md")
        XCTAssertEqual(ProfileTarget.codex.layout.defaultBackupFileName, "AGENTS.default.md")
        XCTAssertEqual(ProfileTarget.codex.layout.recoveryPrefix, "AGENTS.recovered-")
        XCTAssertEqual(ProfileTarget.codex.layout.temporaryPrefix, ".AGENTS.md.swap-")
        XCTAssertEqual(ProfileTarget.codex.layout.profilePattern, "AGENTS.*.md")
        XCTAssertFalse(ProfileTarget.codex.layout.isProfileFileName("AGENTS.override.md"))
    }

    func testMissingOrInvalidPersistedSelectionDefaultsToClaude() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(ProfileTarget.loadSelection(from: defaults), .claude)
            defaults.set("unknown", forKey: ProfileTarget.selectionDefaultsKey)
            XCTAssertEqual(ProfileTarget.loadSelection(from: defaults), .claude)
        }
    }

    func testCodexSelectionPersistsAcrossReconstruction() {
        withIsolatedDefaults { defaults in
            ProfileTarget.codex.persistSelection(to: defaults)
            XCTAssertEqual(ProfileTarget.loadSelection(from: defaults), .codex)

            let reconstructedDefaults = UserDefaults(suiteName: defaultsSuiteName(defaults))!
            XCTAssertEqual(ProfileTarget.loadSelection(from: reconstructedDefaults), .codex)
        }
    }

    func testCodexDiscoveryIsSortedAndExcludesCanonicalOverrideDirectoriesAndOtherTargets() throws {
        let included = [
            "AGENTS.work.md",
            "AGENTS.personal.md",
            "AGENTS.default.md",
            "AGENTS.recovered-safe.md"
        ]
        for name in included {
            try Data(name.utf8).write(to: directory.appendingPathComponent(name))
        }
        for name in ["AGENTS.md", "AGENTS.override.md", "CLAUDE.work.md", "NOTES.md"] {
            try Data(name.utf8).write(to: directory.appendingPathComponent(name))
        }
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("AGENTS.directory.md"),
            withIntermediateDirectories: false
        )

        let discovered = ProfileDiscovery.profileURLs(in: directory, layout: .codex)
            .map(\.lastPathComponent)

        XCTAssertEqual(
            discovered,
            [
                "AGENTS.default.md",
                "AGENTS.personal.md",
                "AGENTS.recovered-safe.md",
                "AGENTS.work.md"
            ]
        )
    }

    func testCodexDiscoveryExcludesCaseVariantOfReservedOverrideOnCaseInsensitiveVolumes() throws {
        let values = try directory.resourceValues(
            forKeys: [.volumeSupportsCaseSensitiveNamesKey]
        )
        guard values.volumeSupportsCaseSensitiveNames == false else {
            throw XCTSkip("Requires a case-insensitive volume")
        }

        try Data("override".utf8).write(
            to: directory.appendingPathComponent("AGENTS.Override.md")
        )

        XCTAssertTrue(
            ProfileDiscovery.profileURLs(in: directory, layout: .codex).isEmpty
        )
    }

    func testClaudeDiscoveryStillIncludesDefaultAndRecoveryProfiles() throws {
        for name in [
            "CLAUDE.md",
            "CLAUDE.default.md",
            "CLAUDE.recovered-safe.md",
            "CLAUDE.work.md",
            "AGENTS.work.md"
        ] {
            try Data(name.utf8).write(to: directory.appendingPathComponent(name))
        }

        let discovered = ProfileDiscovery.profileURLs(in: directory, layout: .claude)
            .map(\.lastPathComponent)

        XCTAssertEqual(
            discovered,
            ["CLAUDE.default.md", "CLAUDE.recovered-safe.md", "CLAUDE.work.md"]
        )
    }

    func testDisplayNamesFollowExistingClaudeCapitalizationForBothTargets() {
        XCTAssertEqual(
            ProfileLayout.claude.displayName(forProfileFileName: "CLAUDE.work.md"),
            "Work"
        )
        XCTAssertEqual(
            ProfileLayout.codex.displayName(forProfileFileName: "AGENTS.personal-client.md"),
            "Personal-client"
        )
    }

    func testActiveProfileResolutionAcceptsOnlyExistingSameTargetProfiles() throws {
        let profile = directory.appendingPathComponent("AGENTS.work.md")
        let main = directory.appendingPathComponent("AGENTS.md")
        try Data("profile".utf8).write(to: profile)
        try FileManager.default.createSymbolicLink(
            atPath: main.path,
            withDestinationPath: profile.path
        )

        let active = try XCTUnwrap(
            ProfileDiscovery.activeProfileURL(in: directory, layout: .codex)
        )
        XCTAssertEqual(active.lastPathComponent, profile.lastPathComponent)
        XCTAssertTrue(ProfileDiscovery.fileURLsAreEquivalent(active, profile))

        try FileManager.default.removeItem(at: main)
        let claudeDirectory = directory.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(
            at: claudeDirectory,
            withIntermediateDirectories: true
        )
        let claudeProfile = claudeDirectory.appendingPathComponent("CLAUDE.work.md")
        try Data("claude".utf8).write(to: claudeProfile)
        try FileManager.default.createSymbolicLink(
            atPath: main.path,
            withDestinationPath: claudeProfile.path
        )

        XCTAssertNil(ProfileDiscovery.activeProfileURL(in: directory, layout: .codex))
    }

    func testActiveProfileResolutionReturnsActualFilesystemSpelling() throws {
        let values = try directory.resourceValues(
            forKeys: [.volumeSupportsCaseSensitiveNamesKey]
        )
        guard values.volumeSupportsCaseSensitiveNames == false else {
            throw XCTSkip("Requires a case-insensitive volume")
        }

        let profile = directory.appendingPathComponent("AGENTS.Work.md")
        let main = directory.appendingPathComponent("AGENTS.md")
        try Data("profile".utf8).write(to: profile)
        try FileManager.default.createSymbolicLink(
            atPath: main.path,
            withDestinationPath: "AGENTS.work.md"
        )

        let active = try XCTUnwrap(
            ProfileDiscovery.activeProfileURL(in: directory, layout: .codex)
        )
        XCTAssertEqual(active.lastPathComponent, profile.lastPathComponent)
        XCTAssertTrue(ProfileDiscovery.fileURLsAreEquivalent(active, profile))

        let composedDirectory = directory.appendingPathComponent("Caf\u{00E9}", isDirectory: true)
        let decomposedDirectory = directory.appendingPathComponent(
            "Cafe\u{0301}",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: composedDirectory,
            withIntermediateDirectories: false
        )
        let unicodeProfile = composedDirectory.appendingPathComponent("AGENTS.Work.md")
        let unicodeMain = composedDirectory.appendingPathComponent("AGENTS.md")
        try Data("unicode profile".utf8).write(to: unicodeProfile)
        try FileManager.default.createSymbolicLink(
            atPath: unicodeMain.path,
            withDestinationPath:
                decomposedDirectory.appendingPathComponent("AGENTS.work.md").path
        )

        let unicodeActive = try XCTUnwrap(
            ProfileDiscovery.activeProfileURL(in: composedDirectory, layout: .codex)
        )
        XCTAssertEqual(
            unicodeActive.lastPathComponent,
            unicodeProfile.lastPathComponent
        )
        XCTAssertTrue(
            ProfileDiscovery.fileURLsAreEquivalent(unicodeActive, unicodeProfile)
        )
    }

    func testDiscoveryRejectsUnusableProfilesAndKeepsReadableSymlinks() throws {
        let source = directory.appendingPathComponent("profile-source.md")
        let readableLink = directory.appendingPathComponent("AGENTS.linked.md")
        let danglingLink = directory.appendingPathComponent("AGENTS.dangling.md")
        let directoryLink = directory.appendingPathComponent("AGENTS.directory-link.md")
        let unreadable = directory.appendingPathComponent("AGENTS.unreadable.md")
        let linkedDirectory = directory.appendingPathComponent("linked-directory", isDirectory: true)
        let canonicalAlias = directory.appendingPathComponent("canonical-alias.md")
        let canonicalChain = directory.appendingPathComponent("AGENTS.canonical-chain.md")
        let selfCycle = directory.appendingPathComponent("AGENTS.self-cycle.md")
        let main = directory.appendingPathComponent("AGENTS.md")

        try Data("linked profile".utf8).write(to: source)
        try FileManager.default.createSymbolicLink(
            atPath: readableLink.path,
            withDestinationPath: source.lastPathComponent
        )
        try FileManager.default.createSymbolicLink(
            atPath: danglingLink.path,
            withDestinationPath: "missing.md"
        )
        try FileManager.default.createDirectory(
            at: linkedDirectory,
            withIntermediateDirectories: false
        )
        try FileManager.default.createSymbolicLink(
            atPath: directoryLink.path,
            withDestinationPath: linkedDirectory.lastPathComponent
        )
        try Data("canonical".utf8).write(to: main)
        try FileManager.default.createSymbolicLink(
            atPath: canonicalAlias.path,
            withDestinationPath: main.lastPathComponent
        )
        try FileManager.default.createSymbolicLink(
            atPath: canonicalChain.path,
            withDestinationPath: canonicalAlias.lastPathComponent
        )
        try FileManager.default.createSymbolicLink(
            atPath: selfCycle.path,
            withDestinationPath: selfCycle.lastPathComponent
        )
        try Data("unreadable".utf8).write(to: unreadable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0],
            ofItemAtPath: unreadable.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: unreadable.path
            )
        }

        XCTAssertEqual(
            ProfileDiscovery.profileURLs(in: directory, layout: .codex)
                .map(\.lastPathComponent),
            ["AGENTS.linked.md"]
        )

        try FileManager.default.removeItem(at: main)
        try FileManager.default.createSymbolicLink(
            atPath: main.path,
            withDestinationPath: danglingLink.lastPathComponent
        )
        XCTAssertNil(ProfileDiscovery.activeProfileURL(in: directory, layout: .codex))
    }

    private func withIsolatedDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "ProfileTargetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(suiteName, forKey: "testSuiteName")
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults)
    }

    private func defaultsSuiteName(_ defaults: UserDefaults) -> String {
        defaults.string(forKey: "testSuiteName")!
    }
}
