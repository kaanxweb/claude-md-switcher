import Darwin
import Foundation

public enum ProfileActivation {
    public static func activate(profileURL: URL, in claudeDirectory: URL) throws {
        try activate(
            profileURL: profileURL,
            in: claudeDirectory,
            uniqueIdentifier: { UUID().uuidString },
            renameItem: { Darwin.rename($0, $1) }
        )
    }

    static func activate(
        profileURL: URL,
        in claudeDirectory: URL,
        uniqueIdentifier: () -> String,
        renameItem: (String, String) -> Int32 = { Darwin.rename($0, $1) }
    ) throws {
        let fileManager = FileManager.default
        let mainFile = claudeDirectory.appendingPathComponent("CLAUDE.md")
        let defaultBackup = claudeDirectory.appendingPathComponent("CLAUDE.default.md")

        if fileManager.fileExists(atPath: mainFile.path) {
            let attributes = try fileManager.attributesOfItem(atPath: mainFile.path)
            let type = attributes[.type] as? FileAttributeType

            if type != .typeSymbolicLink {
                if !fileManager.fileExists(atPath: defaultBackup.path) {
                    try fileManager.moveItem(at: mainFile, to: defaultBackup)
                } else {
                    let recoveryURL = nextAvailableURL(
                        in: claudeDirectory,
                        prefix: "CLAUDE.recovered-",
                        suffix: ".md",
                        fileManager: fileManager,
                        uniqueIdentifier: uniqueIdentifier
                    )
                    try fileManager.moveItem(at: mainFile, to: recoveryURL)
                }
            }
        }

        let temporaryURL = nextAvailableURL(
            in: claudeDirectory,
            prefix: ".CLAUDE.md.swap-",
            suffix: "",
            fileManager: fileManager,
            uniqueIdentifier: uniqueIdentifier
        )
        try fileManager.createSymbolicLink(
            atPath: temporaryURL.path,
            withDestinationPath: profileURL.lastPathComponent
        )

        if renameItem(temporaryURL.path, mainFile.path) != 0 {
            let renameError = errno
            try? fileManager.removeItem(at: temporaryURL)
            let message = String(cString: strerror(renameError))
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(renameError),
                userInfo: [NSLocalizedDescriptionKey: "rename failed: \(message)"]
            )
        }
    }

    private static func nextAvailableURL(
        in directory: URL,
        prefix: String,
        suffix: String,
        fileManager: FileManager,
        uniqueIdentifier: () -> String
    ) -> URL {
        while true {
            let filename = "\(prefix)\(uniqueIdentifier())\(suffix)"
            let candidate = directory.appendingPathComponent(filename)
            if (try? fileManager.attributesOfItem(atPath: candidate.path)) == nil {
                return candidate
            }
        }
    }
}
