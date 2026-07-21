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

    func testFirstActivationPreservesOriginalAsDefaultAndActivatesProfile() throws {
        let original = Data("original content\n".utf8)
        let profile = Data("work profile body\n".utf8)
        try original.write(to: mainFile)
        try profile.write(to: workProfile)

        try ProfileActivation.activate(profileURL: workProfile, in: directory)

        XCTAssertEqual(try Data(contentsOf: defaultBackup), original)
        XCTAssertEqual(try symlinkTarget(at: mainFile), "CLAUDE.work.md")
        XCTAssertEqual(try Data(contentsOf: mainFile), profile)
    }

    func testLaterRegularFileBecomesRecoveryProfileWithoutChangingDefault() throws {
        let original = Data("first original\n".utf8)
        let later = Data("later user content\nwith another line\n".utf8)
        let profile = Data("work profile body\n".utf8)
        try establishDefault(original: original, profile: profile)

        try FileManager.default.removeItem(at: mainFile)
        try later.write(to: mainFile)
        try ProfileActivation.activate(profileURL: workProfile, in: directory)

        let recoveries = try recoveryProfiles()
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
        try establishDefault(original: original, profile: Data("work profile".utf8))

        try FileManager.default.removeItem(at: mainFile)
        try later.write(to: mainFile)
        let collisionURL = directory.appendingPathComponent("CLAUDE.recovered-collision.md")
        try existingRecovery.write(to: collisionURL)

        var identifiers = ["collision", "available", "swap"].makeIterator()
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

    func testFailureAfterRecoveryMovePreservesBothRegularFiles() throws {
        let original = Data("first original".utf8)
        let later = Data("later content that must survive".utf8)
        try establishDefault(original: original, profile: Data("work profile".utf8))

        try FileManager.default.removeItem(at: mainFile)
        try later.write(to: mainFile)

        var identifiers = ["saved-before-failure", "swap-before-failure"].makeIterator()
        XCTAssertThrowsError(
            try ProfileActivation.activate(
                profileURL: workProfile,
                in: directory,
                uniqueIdentifier: { identifiers.next()! },
                renameItem: { _, _ in
                    errno = EIO
                    return -1
                }
            )
        )

        XCTAssertEqual(try Data(contentsOf: defaultBackup), original)
        XCTAssertEqual(
            try Data(contentsOf: directory.appendingPathComponent("CLAUDE.recovered-saved-before-failure.md")),
            later
        )
        XCTAssertNil(
            try? FileManager.default.attributesOfItem(
                atPath: directory.appendingPathComponent(".CLAUDE.md.swap-swap-before-failure").path
            )
        )
    }

    private func establishDefault(original: Data, profile: Data) throws {
        try original.write(to: mainFile)
        try profile.write(to: workProfile)
        try ProfileActivation.activate(profileURL: workProfile, in: directory)
    }

    private func recoveryProfiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter {
                $0.lastPathComponent.hasPrefix("CLAUDE.recovered-") &&
                    $0.lastPathComponent.hasSuffix(".md")
            }
    }

    private func symlinkTarget(at url: URL) throws -> String {
        try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
    }
}
