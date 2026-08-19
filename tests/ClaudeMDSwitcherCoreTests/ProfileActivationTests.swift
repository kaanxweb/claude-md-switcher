import Darwin
import Foundation
import XCTest
@testable import ClaudeMDSwitcherCore

final class ProfileActivationTests: XCTestCase {
    private var directory: URL!
    private var mainFile: URL { directory.appendingPathComponent("CLAUDE.md") }
    private var defaultBackup: URL { directory.appendingPathComponent("CLAUDE.default.md") }
    private var workProfile: URL { directory.appendingPathComponent("CLAUDE.work.md") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-md-switcher-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testFirstClaudeActivationPreservesOriginalAsDefaultAndActivatesProfile() throws {
        let original = Data("original content\n".utf8)
        let profile = Data("work profile body\n".utf8)
        try original.write(to: mainFile)
        try profile.write(to: workProfile)

        try ProfileActivation.activate(profileURL: workProfile, in: directory)

        XCTAssertEqual(try Data(contentsOf: defaultBackup), original)
        XCTAssertEqual(try symlinkTarget(at: mainFile), "CLAUDE.work.md")
        XCTAssertEqual(try Data(contentsOf: mainFile), profile)
    }

    func testClaudeActivationWithoutExistingMainFileCreatesNoBackup() throws {
        let profile = Data("work profile body\n".utf8)
        try profile.write(to: workProfile)

        try ProfileActivation.activate(profileURL: workProfile, in: directory)

        XCTAssertEqual(try symlinkTarget(at: mainFile), "CLAUDE.work.md")
        XCTAssertFalse(itemExists(at: defaultBackup))
    }

    func testLaterRegularFileBecomesRecoveryProfileWithoutChangingDefault() throws {
        let original = Data("first original\n".utf8)
        let later = Data("later user content\nwith another line\n".utf8)
        let profile = Data("work profile body\n".utf8)
        try establishClaudeDefault(original: original, profile: profile)

        try FileManager.default.removeItem(at: mainFile)
        try later.write(to: mainFile)
        try ProfileActivation.activate(profileURL: workProfile, in: directory)

        let recoveries = try recoveryProfiles(layout: .claude)
        XCTAssertEqual(recoveries.count, 1)
        XCTAssertEqual(try Data(contentsOf: recoveries[0]), later)
        XCTAssertEqual(try Data(contentsOf: defaultBackup), original)
        XCTAssertEqual(try symlinkTarget(at: mainFile), "CLAUDE.work.md")
        XCTAssertEqual(try Data(contentsOf: mainFile), profile)
    }

    func testRecoveryNameCollisionDoesNotOverwriteExistingProfile() throws {
        let original = Data("first original".utf8)
        let later = Data("later content".utf8)
        let existingRecovery = Data("existing recovery".utf8)
        try establishClaudeDefault(original: original, profile: Data("work profile".utf8))

        try FileManager.default.removeItem(at: mainFile)
        try later.write(to: mainFile)
        let collisionURL = directory.appendingPathComponent("CLAUDE.recovered-collision.md")
        try existingRecovery.write(to: collisionURL)

        var identifiers = ["temporary", "collision", "available"].makeIterator()
        try ProfileActivation.activate(
            profileURL: workProfile,
            in: directory,
            uniqueIdentifier: { identifiers.next()! }
        )

        XCTAssertEqual(try Data(contentsOf: collisionURL), existingRecovery)
        XCTAssertEqual(
            try Data(contentsOf: directory.appendingPathComponent("CLAUDE.recovered-available.md")),
            later
        )
        XCTAssertEqual(try Data(contentsOf: defaultBackup), original)
    }

    func testTemporaryNameCollisionDoesNotOverwriteExistingItem() throws {
        let existing = Data("existing temporary collision".utf8)
        let collision = directory.appendingPathComponent(".AGENTS.md.swap-collision")
        let profile = directory.appendingPathComponent("AGENTS.work.md")
        let main = directory.appendingPathComponent("AGENTS.md")
        try existing.write(to: collision)
        try Data("profile".utf8).write(to: profile)

        var identifiers = ["collision", "available"].makeIterator()
        try ProfileActivation.activate(
            profileURL: profile,
            in: directory,
            layout: .codex,
            uniqueIdentifier: { identifiers.next()! }
        )

        XCTAssertEqual(try Data(contentsOf: collision), existing)
        XCTAssertEqual(try symlinkTarget(at: main), "AGENTS.work.md")
        XCTAssertFalse(itemExists(at: directory.appendingPathComponent(".AGENTS.md.swap-available")))
    }

    func testExchangeFailureLeavesCanonicalRegularFileUntouched() throws {
        let original = Data("first original".utf8)
        let later = Data("later content that must survive".utf8)
        try establishClaudeDefault(original: original, profile: Data("work profile".utf8))

        try FileManager.default.removeItem(at: mainFile)
        try later.write(to: mainFile)

        XCTAssertThrowsError(
            try ProfileActivation.activate(
                profileURL: workProfile,
                in: directory,
                uniqueIdentifier: { "swap-before-failure" },
                renameItem: { _, _, _ in
                    errno = EIO
                    return -1
                }
            )
        )

        XCTAssertEqual(try Data(contentsOf: defaultBackup), original)
        XCTAssertEqual(try Data(contentsOf: mainFile), later)
        XCTAssertTrue(try recoveryProfiles(layout: .claude).isEmpty)
        XCTAssertFalse(
            itemExists(at: directory.appendingPathComponent(".CLAUDE.md.swap-swap-before-failure"))
        )
    }

    func testPreservationFailureKeepsDisplacedItemAndReportsPartialCommit() throws {
        let original = Data("content that must remain canonical".utf8)
        try original.write(to: mainFile)
        try Data("profile".utf8).write(to: workProfile)

        var callCount = 0
        XCTAssertThrowsError(
            try ProfileActivation.activate(
                profileURL: workProfile,
                in: directory,
                uniqueIdentifier: { "rollback" },
                renameItem: { source, destination, operation in
                    callCount += 1
                    if callCount == 2 {
                        errno = EIO
                        return -1
                    }
                    return self.systemAtomicRename(source, destination, operation)
                }
            )
        ) { error in
            guard let partialFailure = error as? ProfileActivationPartialFailure else {
                return XCTFail("Expected ProfileActivationPartialFailure, got \(error)")
            }
            XCTAssertEqual(
                partialFailure.displacedItemURL,
                self.directory.appendingPathComponent(".CLAUDE.md.swap-rollback")
            )
        }

        XCTAssertEqual(try symlinkTarget(at: mainFile), "CLAUDE.work.md")
        XCTAssertFalse(itemExists(at: defaultBackup))
        XCTAssertEqual(
            try Data(
                contentsOf: directory.appendingPathComponent(".CLAUDE.md.swap-rollback")
            ),
            original
        )
    }

    func testPreservationFailureNeverDeletesConcurrentCanonicalReplacement() throws {
        let original = Data("original content".utf8)
        let concurrent = Data("concurrent replacement".utf8)
        try original.write(to: mainFile)
        try Data("profile".utf8).write(to: workProfile)

        var callCount = 0
        XCTAssertThrowsError(
            try ProfileActivation.activate(
                profileURL: workProfile,
                in: directory,
                uniqueIdentifier: { "concurrent-preservation-failure" },
                renameItem: { source, destination, operation in
                    callCount += 1
                    if callCount == 2 {
                        try! FileManager.default.removeItem(at: self.mainFile)
                        try! concurrent.write(to: self.mainFile)
                        errno = EIO
                        return -1
                    }
                    return self.systemAtomicRename(source, destination, operation)
                }
            )
        ) { error in
            XCTAssertTrue(error is ProfileActivationPartialFailure)
        }

        XCTAssertEqual(try Data(contentsOf: mainFile), concurrent)
        XCTAssertEqual(
            try Data(
                contentsOf: directory.appendingPathComponent(
                    ".CLAUDE.md.swap-concurrent-preservation-failure"
                )
            ),
            original
        )
    }

    func testConcurrentCanonicalCreationIsPreservedBeforeActivationCompletes() throws {
        let profile = directory.appendingPathComponent("AGENTS.work.md")
        let main = directory.appendingPathComponent("AGENTS.md")
        let defaultFile = directory.appendingPathComponent("AGENTS.default.md")
        let concurrentContent = Data("concurrent editor content".utf8)
        try Data("profile".utf8).write(to: profile)

        var injectedConcurrentWrite = false
        try ProfileActivation.activate(
            profileURL: profile,
            in: directory,
            layout: .codex,
            uniqueIdentifier: { "concurrent" },
            renameItem: { source, destination, operation in
                if !injectedConcurrentWrite && operation == .exclusive && destination == main.path {
                    try! concurrentContent.write(to: main)
                    injectedConcurrentWrite = true
                    errno = EEXIST
                    return -1
                }
                return self.systemAtomicRename(source, destination, operation)
            }
        )

        XCTAssertTrue(injectedConcurrentWrite)
        XCTAssertEqual(try Data(contentsOf: defaultFile), concurrentContent)
        XCTAssertEqual(try symlinkTarget(at: main), "AGENTS.work.md")
    }

    func testCodexFirstActivationAndSwitchingPreserveDefault() throws {
        let main = directory.appendingPathComponent("AGENTS.md")
        let defaultFile = directory.appendingPathComponent("AGENTS.default.md")
        let work = directory.appendingPathComponent("AGENTS.work.md")
        let personal = directory.appendingPathComponent("AGENTS.personal.md")
        let original = Data("codex original".utf8)
        try original.write(to: main)
        try Data("work".utf8).write(to: work)
        try Data("personal".utf8).write(to: personal)

        try ProfileActivation.activate(profileURL: work, in: directory, layout: .codex)
        try ProfileActivation.activate(profileURL: personal, in: directory, layout: .codex)

        XCTAssertEqual(try Data(contentsOf: defaultFile), original)
        XCTAssertEqual(try symlinkTarget(at: main), "AGENTS.personal.md")
        XCTAssertTrue(try recoveryProfiles(layout: .codex).isEmpty)
    }

    func testCodexSwitchingWithoutOriginalCanonicalCreatesNoBackup() throws {
        let main = directory.appendingPathComponent("AGENTS.md")
        let defaultFile = directory.appendingPathComponent("AGENTS.default.md")
        let work = directory.appendingPathComponent("AGENTS.work.md")
        let personal = directory.appendingPathComponent("AGENTS.personal.md")
        try Data("work".utf8).write(to: work)
        try Data("personal".utf8).write(to: personal)

        try ProfileActivation.activate(profileURL: work, in: directory, layout: .codex)
        try ProfileActivation.activate(profileURL: personal, in: directory, layout: .codex)

        XCTAssertEqual(try symlinkTarget(at: main), personal.lastPathComponent)
        XCTAssertFalse(itemExists(at: defaultFile))
        XCTAssertTrue(try recoveryProfiles(layout: .codex).isEmpty)
    }

    func testCodexRejectsFilesystemAliasesOfCanonicalAndReservedFilesBeforeMutation() throws {
        let values = try directory.resourceValues(
            forKeys: [.volumeSupportsCaseSensitiveNamesKey]
        )
        guard values.volumeSupportsCaseSensitiveNames == false else {
            throw XCTSkip("Requires a case-insensitive volume")
        }

        let main = directory.appendingPathComponent("AGENTS.md")
        let relativeAlias = directory.appendingPathComponent("AGENTS.relative.md")
        let absoluteAlias = directory.appendingPathComponent("AGENTS.absolute.md")
        let indirectAlias = directory.appendingPathComponent("AGENTS.indirect.md")
        let intermediateAlias = directory.appendingPathComponent("canonical-alias.md")
        let reservedAlias = directory.appendingPathComponent("AGENTS.Override.md")
        let original = Data("canonical".utf8)
        try original.write(to: main)
        try FileManager.default.createSymbolicLink(
            atPath: relativeAlias.path,
            withDestinationPath: "agents.md"
        )
        try FileManager.default.createSymbolicLink(
            atPath: absoluteAlias.path,
            withDestinationPath: directory.appendingPathComponent("agents.md").path
        )
        try FileManager.default.createSymbolicLink(
            atPath: intermediateAlias.path,
            withDestinationPath: "agents.md"
        )
        try FileManager.default.createSymbolicLink(
            atPath: indirectAlias.path,
            withDestinationPath: intermediateAlias.lastPathComponent
        )
        try Data("override".utf8).write(to: reservedAlias)

        XCTAssertTrue(
            ProfileDiscovery.profileURLs(in: directory, layout: .codex).isEmpty
        )
        for profile in [relativeAlias, absoluteAlias, indirectAlias, reservedAlias] {
            XCTAssertThrowsError(
                try ProfileActivation.activate(
                    profileURL: profile,
                    in: directory,
                    layout: .codex
                )
            )
            XCTAssertEqual(try Data(contentsOf: main), original)
            XCTAssertFalse(
                itemExists(at: directory.appendingPathComponent("AGENTS.default.md"))
            )
        }
        XCTAssertTrue(
            try recoveryProfiles(layout: .codex).isEmpty
        )
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .filter { $0.hasPrefix(".AGENTS.md.swap-") }
                .isEmpty
        )
    }

    func testCodexRejectsCanonicalAliasThroughUnicodeEquivalentParentBeforeMutation() throws {
        let composedDirectory = directory.appendingPathComponent("Caf\u{00E9}", isDirectory: true)
        let decomposedDirectory = directory.appendingPathComponent(
            "Cafe\u{0301}",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: composedDirectory,
            withIntermediateDirectories: false
        )

        let main = composedDirectory.appendingPathComponent("AGENTS.md")
        let profile = composedDirectory.appendingPathComponent("AGENTS.unicode.md")
        let decomposedMain = decomposedDirectory.appendingPathComponent("AGENTS.md")
        let original = Data("canonical".utf8)
        try original.write(to: main)
        XCTAssertEqual(try Data(contentsOf: decomposedMain), original)
        try FileManager.default.createSymbolicLink(
            atPath: profile.path,
            withDestinationPath: decomposedMain.path
        )

        XCTAssertTrue(
            ProfileDiscovery.profileURLs(in: composedDirectory, layout: .codex).isEmpty
        )
        XCTAssertThrowsError(
            try ProfileActivation.activate(
                profileURL: profile,
                in: composedDirectory,
                layout: .codex
            )
        )
        XCTAssertEqual(try Data(contentsOf: main), original)
        XCTAssertFalse(
            itemExists(
                at: composedDirectory.appendingPathComponent("AGENTS.default.md")
            )
        )
    }

    func testCodexRegularFileRecoveryAndCollisionHandling() throws {
        let main = directory.appendingPathComponent("AGENTS.md")
        let defaultFile = directory.appendingPathComponent("AGENTS.default.md")
        let profile = directory.appendingPathComponent("AGENTS.work.md")
        let collision = directory.appendingPathComponent("AGENTS.recovered-collision.md")
        let original = Data("original".utf8)
        let later = Data("later".utf8)
        let collisionData = Data("existing recovery".utf8)
        try original.write(to: main)
        try Data("profile".utf8).write(to: profile)
        try ProfileActivation.activate(profileURL: profile, in: directory, layout: .codex)
        try FileManager.default.removeItem(at: main)
        try later.write(to: main)
        try collisionData.write(to: collision)

        var identifiers = ["temporary", "collision", "available"].makeIterator()
        try ProfileActivation.activate(
            profileURL: profile,
            in: directory,
            layout: .codex,
            uniqueIdentifier: { identifiers.next()! }
        )

        XCTAssertEqual(try Data(contentsOf: defaultFile), original)
        XCTAssertEqual(try Data(contentsOf: collision), collisionData)
        XCTAssertEqual(
            try Data(contentsOf: directory.appendingPathComponent("AGENTS.recovered-available.md")),
            later
        )
    }

    func testUnmanagedCanonicalSymlinkIsPreservedAsDefault() throws {
        let source = directory.appendingPathComponent("dotfiles-agents.md")
        let main = directory.appendingPathComponent("AGENTS.md")
        let defaultFile = directory.appendingPathComponent("AGENTS.default.md")
        let profile = directory.appendingPathComponent("AGENTS.work.md")
        try Data("dotfiles content".utf8).write(to: source)
        try Data("profile".utf8).write(to: profile)
        try FileManager.default.createSymbolicLink(
            atPath: main.path,
            withDestinationPath: source.lastPathComponent
        )

        try ProfileActivation.activate(profileURL: profile, in: directory, layout: .codex)

        XCTAssertEqual(try symlinkTarget(at: defaultFile), source.lastPathComponent)
        XCTAssertEqual(try Data(contentsOf: defaultFile), Data("dotfiles content".utf8))
        XCTAssertEqual(try symlinkTarget(at: main), "AGENTS.work.md")
    }

    func testManualProfileShapedCanonicalSymlinkIsPreservedAsDefault() throws {
        let main = directory.appendingPathComponent("AGENTS.md")
        let defaultFile = directory.appendingPathComponent("AGENTS.default.md")
        let team = directory.appendingPathComponent("AGENTS.team.md")
        let work = directory.appendingPathComponent("AGENTS.work.md")
        let personal = directory.appendingPathComponent("AGENTS.personal.md")
        try Data("team".utf8).write(to: team)
        try Data("work".utf8).write(to: work)
        try Data("personal".utf8).write(to: personal)
        try FileManager.default.createSymbolicLink(
            atPath: main.path,
            withDestinationPath: team.lastPathComponent
        )

        try ProfileActivation.activate(
            profileURL: work,
            in: directory,
            layout: .codex
        )

        XCTAssertEqual(try symlinkTarget(at: defaultFile), team.lastPathComponent)
        XCTAssertEqual(try Data(contentsOf: defaultFile), Data("team".utf8))
        XCTAssertEqual(try symlinkTarget(at: main), work.lastPathComponent)

        try ProfileActivation.activate(
            profileURL: personal,
            in: directory,
            layout: .codex
        )

        XCTAssertEqual(try symlinkTarget(at: defaultFile), team.lastPathComponent)
        XCTAssertEqual(try symlinkTarget(at: main), personal.lastPathComponent)
        XCTAssertTrue(try recoveryProfiles(layout: .codex).isEmpty)
    }

    func testManualProfileShapedCanonicalSymlinkUsesRecoveryWhenDefaultExists() throws {
        let main = directory.appendingPathComponent("AGENTS.md")
        let defaultFile = directory.appendingPathComponent("AGENTS.default.md")
        let recovery = directory.appendingPathComponent("AGENTS.recovered-manual.md")
        let team = directory.appendingPathComponent("AGENTS.team.md")
        let work = directory.appendingPathComponent("AGENTS.work.md")
        let originalDefault = Data("original default".utf8)
        try originalDefault.write(to: defaultFile)
        try Data("team".utf8).write(to: team)
        try Data("work".utf8).write(to: work)
        try FileManager.default.createSymbolicLink(
            atPath: main.path,
            withDestinationPath: team.lastPathComponent
        )

        var identifiers = ["temporary", "manual"].makeIterator()
        try ProfileActivation.activate(
            profileURL: work,
            in: directory,
            layout: .codex,
            uniqueIdentifier: { identifiers.next()! }
        )

        XCTAssertEqual(try Data(contentsOf: defaultFile), originalDefault)
        XCTAssertEqual(try symlinkTarget(at: recovery), team.lastPathComponent)
        XCTAssertEqual(try Data(contentsOf: recovery), Data("team".utf8))
        XCTAssertEqual(try symlinkTarget(at: main), work.lastPathComponent)
    }

    func testCodexMarkerFailureLeavesCanonicalFileUntouched() throws {
        let main = directory.appendingPathComponent("AGENTS.md")
        let defaultFile = directory.appendingPathComponent("AGENTS.default.md")
        let profile = directory.appendingPathComponent("AGENTS.work.md")
        let original = Data("original".utf8)
        try original.write(to: main)
        try Data("work".utf8).write(to: profile)

        XCTAssertThrowsError(
            try ProfileActivation.activate(
                profileURL: profile,
                in: directory,
                layout: .codex,
                uniqueIdentifier: { "marker-failure" },
                markManagedLink: { _ in
                    throw CocoaError(.fileWriteNoPermission)
                }
            )
        )

        XCTAssertEqual(try Data(contentsOf: main), original)
        XCTAssertFalse(itemExists(at: defaultFile))
        XCTAssertFalse(
            itemExists(
                at: directory.appendingPathComponent(".AGENTS.md.swap-marker-failure")
            )
        )
    }

    func testClaudeProfileShapedCanonicalSymlinkKeepsLegacySwitchingBehavior() throws {
        let personal = directory.appendingPathComponent("CLAUDE.personal.md")
        let originalDefault = Data("original default".utf8)
        try originalDefault.write(to: defaultBackup)
        try Data("work".utf8).write(to: workProfile)
        try Data("personal".utf8).write(to: personal)
        try FileManager.default.createSymbolicLink(
            atPath: mainFile.path,
            withDestinationPath: workProfile.lastPathComponent
        )

        try ProfileActivation.activate(
            profileURL: personal,
            in: directory,
            layout: .claude
        )

        XCTAssertEqual(try Data(contentsOf: defaultBackup), originalDefault)
        XCTAssertEqual(try symlinkTarget(at: mainFile), personal.lastPathComponent)
        XCTAssertTrue(try recoveryProfiles(layout: .claude).isEmpty)
    }

    func testCrossTargetProfileIsRejectedBeforeEitherTargetChanges() throws {
        let claudeDirectory = directory.appendingPathComponent(".claude", isDirectory: true)
        let codexDirectory = directory.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)

        let claudeProfile = claudeDirectory.appendingPathComponent("CLAUDE.work.md")
        let codexMain = codexDirectory.appendingPathComponent("AGENTS.md")
        let codexOriginal = Data("codex original".utf8)
        try Data("claude profile".utf8).write(to: claudeProfile)
        try codexOriginal.write(to: codexMain)

        XCTAssertThrowsError(
            try ProfileActivation.activate(
                profileURL: claudeProfile,
                in: codexDirectory,
                layout: .codex
            )
        )

        XCTAssertEqual(try Data(contentsOf: codexMain), codexOriginal)
        XCTAssertFalse(itemExists(at: codexDirectory.appendingPathComponent("AGENTS.default.md")))
        XCTAssertEqual(try Data(contentsOf: claudeProfile), Data("claude profile".utf8))
    }

    func testActivatingEachTargetLeavesTheOtherTargetUntouched() throws {
        let claudeDirectory = directory.appendingPathComponent(".claude", isDirectory: true)
        let codexDirectory = directory.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)

        let claudeMain = claudeDirectory.appendingPathComponent("CLAUDE.md")
        let claudeProfile = claudeDirectory.appendingPathComponent("CLAUDE.work.md")
        let codexMain = codexDirectory.appendingPathComponent("AGENTS.md")
        let codexProfile = codexDirectory.appendingPathComponent("AGENTS.work.md")
        let claudeOriginal = Data("claude original".utf8)
        let codexOriginal = Data("codex original".utf8)
        try claudeOriginal.write(to: claudeMain)
        try Data("claude profile".utf8).write(to: claudeProfile)
        try codexOriginal.write(to: codexMain)
        try Data("codex profile".utf8).write(to: codexProfile)

        try ProfileActivation.activate(
            profileURL: codexProfile,
            in: codexDirectory,
            layout: .codex
        )
        XCTAssertEqual(try Data(contentsOf: claudeMain), claudeOriginal)
        XCTAssertFalse(itemExists(at: claudeDirectory.appendingPathComponent("CLAUDE.default.md")))

        try ProfileActivation.activate(profileURL: claudeProfile, in: claudeDirectory)
        XCTAssertEqual(
            try Data(contentsOf: codexDirectory.appendingPathComponent("AGENTS.default.md")),
            codexOriginal
        )
        XCTAssertEqual(try symlinkTarget(at: codexMain), "AGENTS.work.md")
        XCTAssertEqual(try symlinkTarget(at: claudeMain), "CLAUDE.work.md")
    }

    func testCodexOverrideCannotBeActivatedOrModified() throws {
        let override = directory.appendingPathComponent("AGENTS.override.md")
        let main = directory.appendingPathComponent("AGENTS.md")
        let overrideContent = Data("temporary override".utf8)
        let mainContent = Data("main content".utf8)
        try overrideContent.write(to: override)
        try mainContent.write(to: main)

        XCTAssertThrowsError(
            try ProfileActivation.activate(profileURL: override, in: directory, layout: .codex)
        )

        XCTAssertEqual(try Data(contentsOf: override), overrideContent)
        XCTAssertEqual(try Data(contentsOf: main), mainContent)
    }

    func testCodexRejectsUnusableProfilesBeforeChangingCanonicalFile() throws {
        let main = directory.appendingPathComponent("AGENTS.md")
        let defaultFile = directory.appendingPathComponent("AGENTS.default.md")
        let dangling = directory.appendingPathComponent("AGENTS.dangling.md")
        let unreadable = directory.appendingPathComponent("AGENTS.unreadable.md")
        let canonicalLink = directory.appendingPathComponent("AGENTS.canonical-link.md")
        let selfCycle = directory.appendingPathComponent("AGENTS.self-cycle.md")
        let original = Data("original".utf8)

        try original.write(to: main)
        try FileManager.default.createSymbolicLink(
            atPath: canonicalLink.path,
            withDestinationPath: main.lastPathComponent
        )
        try FileManager.default.createSymbolicLink(
            atPath: dangling.path,
            withDestinationPath: "missing.md"
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

        XCTAssertThrowsError(
            try ProfileActivation.activate(
                profileURL: dangling,
                in: directory,
                layout: .codex
            )
        )
        XCTAssertThrowsError(
            try ProfileActivation.activate(
                profileURL: unreadable,
                in: directory,
                layout: .codex
            )
        )
        XCTAssertThrowsError(
            try ProfileActivation.activate(
                profileURL: canonicalLink,
                in: directory,
                layout: .codex
            )
        )
        XCTAssertThrowsError(
            try ProfileActivation.activate(
                profileURL: selfCycle,
                in: directory,
                layout: .codex
            )
        )

        XCTAssertEqual(try Data(contentsOf: main), original)
        XCTAssertFalse(itemExists(at: defaultFile))
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
            .allSatisfy { !$0.lastPathComponent.hasPrefix(".AGENTS.md.swap-") }
        )
    }

    func testCodexActivatesReadableProfileSymlink() throws {
        let source = directory.appendingPathComponent("profile-source.md")
        let profile = directory.appendingPathComponent("AGENTS.linked.md")
        let main = directory.appendingPathComponent("AGENTS.md")
        let content = Data("linked profile".utf8)

        try content.write(to: source)
        try FileManager.default.createSymbolicLink(
            atPath: profile.path,
            withDestinationPath: source.lastPathComponent
        )

        try ProfileActivation.activate(
            profileURL: profile,
            in: directory,
            layout: .codex
        )

        XCTAssertEqual(try symlinkTarget(at: main), profile.lastPathComponent)
        XCTAssertEqual(try Data(contentsOf: main), content)
    }

    func testActiveProfileResolutionSurvivesReconstruction() throws {
        let profile = directory.appendingPathComponent("AGENTS.work.md")
        try Data("profile".utf8).write(to: profile)
        try ProfileActivation.activate(profileURL: profile, in: directory, layout: .codex)

        let firstRead = try XCTUnwrap(
            ProfileDiscovery.activeProfileURL(in: directory, layout: .codex)
        )
        let secondRead = try XCTUnwrap(
            ProfileDiscovery.activeProfileURL(in: directory, layout: .codex)
        )

        XCTAssertTrue(ProfileDiscovery.fileURLsAreEquivalent(firstRead, profile))
        XCTAssertTrue(ProfileDiscovery.fileURLsAreEquivalent(secondRead, profile))
        XCTAssertTrue(ProfileDiscovery.fileURLsAreEquivalent(firstRead, secondRead))
    }

    private func establishClaudeDefault(original: Data, profile: Data) throws {
        try original.write(to: mainFile)
        try profile.write(to: workProfile)
        try ProfileActivation.activate(profileURL: workProfile, in: directory)
    }

    private func recoveryProfiles(layout: ProfileLayout) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter {
                $0.lastPathComponent.hasPrefix(layout.recoveryPrefix) &&
                    $0.lastPathComponent.hasSuffix(".md")
            }
    }

    private func symlinkTarget(at url: URL) throws -> String {
        try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
    }

    private func itemExists(at url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    private func systemAtomicRename(
        _ source: String,
        _ destination: String,
        _ operation: AtomicRenameOperation
    ) -> Int32 {
        let flags: UInt32
        switch operation {
        case .exchange:
            flags = UInt32(RENAME_SWAP)
        case .exclusive:
            flags = UInt32(RENAME_EXCL)
        }
        return Darwin.renameatx_np(AT_FDCWD, source, AT_FDCWD, destination, flags)
    }
}
