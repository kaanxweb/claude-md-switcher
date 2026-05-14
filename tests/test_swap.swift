#!/usr/bin/env swift
import Foundation

// MARK: - Swap logic (mirrors ProfileStore.activate, parameterized on dir)
//
// Kept in lockstep with Sources/ClaudeMDSwitcher/ProfileStore.swift:activate(_:).
// If the production logic changes, update this copy too.
//
// TODO (next test class to add): isActive() correctness against various
// symlink states — dangling symlink, absolute-target symlink, regular
// CLAUDE.md (not a symlink), missing CLAUDE.md, and a symlink whose
// destination doesn't match any listed profile. Bug #4 ("all checkmarks
// visible") was a NSMenuItem rendering issue, not an isActive bug, but
// isActive has enough URL-equality subtleties (standardizedFileURL,
// relative vs absolute symlink destinations) that it deserves its own
// coverage so this bug class can't sneak back in.

func activate(profileURL: URL, in claudeDir: URL) throws {
    let fm = FileManager.default
    let mainFile = claudeDir.appendingPathComponent("CLAUDE.md")
    let defaultBackup = claudeDir.appendingPathComponent("CLAUDE.default.md")

    // Step 1: if CLAUDE.md exists and is a regular file (not a symlink), back it up.
    if fm.fileExists(atPath: mainFile.path) {
        let attrs = try fm.attributesOfItem(atPath: mainFile.path)
        let type = attrs[.type] as? FileAttributeType
        if type != .typeSymbolicLink {
            if !fm.fileExists(atPath: defaultBackup.path) {
                try fm.moveItem(at: mainFile, to: defaultBackup)
            } else {
                try fm.removeItem(at: mainFile)
            }
        }
    }

    // Step 2: atomic symlink swap via temp + rename(2).
    let tempName = ".CLAUDE.md.swap-\(UUID().uuidString)"
    let tempURL = claudeDir.appendingPathComponent(tempName)
    try fm.createSymbolicLink(atPath: tempURL.path, withDestinationPath: profileURL.lastPathComponent)

    if rename(tempURL.path, mainFile.path) != 0 {
        let err = String(cString: strerror(errno))
        try? fm.removeItem(at: tempURL)
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "rename failed: \(err)"])
    }
}

// MARK: - Tiny assertion helpers

var failures = 0
var passes = 0

func assertEq<T: Equatable>(_ actual: T, _ expected: T, _ msg: String) {
    if actual == expected {
        passes += 1
        print("  PASS: \(msg)")
    } else {
        failures += 1
        print("  FAIL: \(msg) — expected \(expected), got \(actual)")
    }
}

func assertTrue(_ cond: Bool, _ msg: String) {
    if cond {
        passes += 1
        print("  PASS: \(msg)")
    } else {
        failures += 1
        print("  FAIL: \(msg)")
    }
}

func symlinkTarget(_ url: URL) -> String? {
    try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)
}

func isSymlink(_ url: URL) -> Bool {
    let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
    return (attrs?[.type] as? FileAttributeType) == .typeSymbolicLink
}

func readFile(_ url: URL) -> String? {
    try? String(contentsOf: url, encoding: .utf8)
}

// MARK: - Test harness

let fm = FileManager.default
let tempBase = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
let tempDir = tempBase.appendingPathComponent("claude-md-switcher-test-\(UUID().uuidString)", isDirectory: true)
try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: tempDir) }

print("Test dir: \(tempDir.path)")

let mainFile = tempDir.appendingPathComponent("CLAUDE.md")
let defaultBackup = tempDir.appendingPathComponent("CLAUDE.default.md")
let workProfile = tempDir.appendingPathComponent("CLAUDE.work.md")
let personalProfile = tempDir.appendingPathComponent("CLAUDE.personal.md")

let originalContent = "original content"
try originalContent.write(to: mainFile, atomically: true, encoding: .utf8)
try "work profile body".write(to: workProfile, atomically: true, encoding: .utf8)
try "personal profile body".write(to: personalProfile, atomically: true, encoding: .utf8)

// --- Step 4 from brief: activate(work) on first run ---
print("\n[Step 1] activate(CLAUDE.work.md) — first run, backup expected")
try activate(profileURL: workProfile, in: tempDir)

assertTrue(isSymlink(mainFile), "CLAUDE.md is now a symlink")
assertEq(symlinkTarget(mainFile), "CLAUDE.work.md", "CLAUDE.md → CLAUDE.work.md")
assertTrue(fm.fileExists(atPath: defaultBackup.path), "CLAUDE.default.md was created")
assertEq(readFile(defaultBackup), originalContent, "backup preserves original content")
assertEq(readFile(mainFile), "work profile body", "reading through symlink yields work body")

// --- Step 5 from brief: activate(personal) — backup must NOT be overwritten ---
print("\n[Step 2] activate(CLAUDE.personal.md) — backup must be untouched")
let backupContentBefore = readFile(defaultBackup)
try activate(profileURL: personalProfile, in: tempDir)

assertTrue(isSymlink(mainFile), "CLAUDE.md is still a symlink")
assertEq(symlinkTarget(mainFile), "CLAUDE.personal.md", "CLAUDE.md → CLAUDE.personal.md")
assertEq(readFile(defaultBackup), backupContentBefore, "backup unchanged after second activation")
assertEq(readFile(defaultBackup), originalContent, "backup still has original content")
assertEq(readFile(mainFile), "personal profile body", "reading through symlink yields personal body")

// --- Bonus: regression guard — if user overwrites CLAUDE.md with a regular file later,
// re-activating must NOT clobber the existing backup ---
print("\n[Step 3] regression guard: regular CLAUDE.md re-introduced — backup still protected")
try fm.removeItem(at: mainFile)
try "user-edited content that should be discarded".write(to: mainFile, atomically: true, encoding: .utf8)
try activate(profileURL: workProfile, in: tempDir)

assertTrue(isSymlink(mainFile), "CLAUDE.md is a symlink again")
assertEq(symlinkTarget(mainFile), "CLAUDE.work.md", "CLAUDE.md → CLAUDE.work.md")
assertEq(readFile(defaultBackup), originalContent, "backup STILL holds the very first original content")

// --- Report ---
print("\n----")
print("Passed: \(passes), Failed: \(failures)")
if failures > 0 {
    exit(1)
} else {
    print("OK")
    exit(0)
}
