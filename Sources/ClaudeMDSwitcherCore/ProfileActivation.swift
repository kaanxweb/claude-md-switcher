import Darwin
import Foundation

enum AtomicRenameOperation {
    case exchange
    case exclusive
}

public struct ProfileActivationPartialFailure: LocalizedError {
    public let displacedItemURL: URL
    public let underlyingError: Error

    public var errorDescription: String? {
        "The profile link was installed, but the displaced item could not be moved to its backup. " +
            "It remains at \(displacedItemURL.path): \(underlyingError.localizedDescription)"
    }
}

public enum ProfileActivation {
    private static let managedProfileLinkAttribute =
        "com.kaanxweb.claude-md-switcher.managed-profile-link"
    private static let managedProfileLinkAttributeValue: UInt8 = 1

    public static func activate(profileURL: URL, in claudeDirectory: URL) throws {
        try activate(
            profileURL: profileURL,
            in: claudeDirectory,
            layout: .claude,
            uniqueIdentifier: { UUID().uuidString },
            renameItem: atomicRename
        )
    }

    public static func activate(
        profileURL: URL,
        in directory: URL,
        layout: ProfileLayout
    ) throws {
        try activate(
            profileURL: profileURL,
            in: directory,
            layout: layout,
            uniqueIdentifier: { UUID().uuidString },
            renameItem: atomicRename
        )
    }

    static func activate(
        profileURL: URL,
        in claudeDirectory: URL,
        uniqueIdentifier: () -> String,
        renameItem: (String, String, AtomicRenameOperation) -> Int32 = atomicRename
    ) throws {
        try activate(
            profileURL: profileURL,
            in: claudeDirectory,
            layout: .claude,
            uniqueIdentifier: uniqueIdentifier,
            renameItem: renameItem
        )
    }

    static func activate(
        profileURL: URL,
        in directory: URL,
        layout: ProfileLayout,
        uniqueIdentifier: () -> String,
        renameItem: (String, String, AtomicRenameOperation) -> Int32 = atomicRename,
        markManagedLink: (URL) throws -> Void = markManagedProfileSymlink
    ) throws {
        let fileManager = FileManager.default
        let mainFile = directory.appendingPathComponent(layout.mainFileName)
        let defaultBackup = directory.appendingPathComponent(layout.defaultBackupFileName)

        try validate(profileURL: profileURL, in: directory, layout: layout, fileManager: fileManager)

        let temporaryURL = nextAvailableURL(
            in: directory,
            prefix: layout.temporaryPrefix,
            suffix: "",
            fileManager: fileManager,
            uniqueIdentifier: uniqueIdentifier
        )
        try fileManager.createSymbolicLink(
            atPath: temporaryURL.path,
            withDestinationPath: profileURL.lastPathComponent
        )
        if layout == .codex {
            do {
                try markManagedLink(temporaryURL)
            } catch {
                try? fileManager.removeItem(at: temporaryURL)
                throw error
            }
        }

        let mainExists = (try? fileManager.attributesOfItem(atPath: mainFile.path)) != nil
        if !mainExists {
            if renameItem(temporaryURL.path, mainFile.path, .exclusive) == 0 {
                return
            }

            let renameError = errno
            guard renameError == EEXIST else {
                try? fileManager.removeItem(at: temporaryURL)
                throw posixError(renameError, operation: "exclusive rename")
            }
        }

        if renameItem(temporaryURL.path, mainFile.path, .exchange) != 0 {
            let renameError = errno
            try? fileManager.removeItem(at: temporaryURL)
            throw posixError(renameError, operation: "atomic exchange")
        }

        do {
            if isManagedProfileSymlink(
                at: temporaryURL,
                in: directory,
                layout: layout,
                fileManager: fileManager
            ) {
                try fileManager.removeItem(at: temporaryURL)
            } else {
                try preserveDisplacedItem(
                    at: temporaryURL,
                    defaultBackup: defaultBackup,
                    in: directory,
                    layout: layout,
                    fileManager: fileManager,
                    uniqueIdentifier: uniqueIdentifier,
                    renameItem: renameItem
                )
            }
        } catch {
            throw ProfileActivationPartialFailure(
                displacedItemURL: temporaryURL,
                underlyingError: error
            )
        }
    }

    private static func validate(
        profileURL: URL,
        in directory: URL,
        layout: ProfileLayout,
        fileManager: FileManager
    ) throws {
        let expectedDirectory = directory.standardizedFileURL.path
        let actualDirectory = profileURL.deletingLastPathComponent().standardizedFileURL.path

        guard actualDirectory == expectedDirectory else {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: CocoaError.fileReadInvalidFileName.rawValue,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Profile must be inside \(directory.path)"
                ]
            )
        }
        guard layout.isProfileFileName(profileURL.lastPathComponent, in: directory) else {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: CocoaError.fileReadInvalidFileName.rawValue,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "\(profileURL.lastPathComponent) is not a selectable \(layout.profilePattern) profile"
                ]
            )
        }
        guard let attributes = try? fileManager.attributesOfItem(atPath: profileURL.path),
              let type = attributes[.type] as? FileAttributeType else {
            throw CocoaError(.fileNoSuchFile)
        }
        guard type == .typeRegular || type == .typeSymbolicLink else {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: CocoaError.fileReadUnsupportedScheme.rawValue,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "\(profileURL.lastPathComponent) must be a file or symbolic link"
                ]
            )
        }
        guard ProfileFileValidation.isReadableRegularFile(
            at: profileURL,
            avoiding: directory.appendingPathComponent(layout.mainFileName)
        ) else {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: CocoaError.fileReadNoPermission.rawValue,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "\(profileURL.lastPathComponent) must resolve to a readable regular file"
                ]
            )
        }
    }

    private static func isManagedProfileSymlink(
        at url: URL,
        in directory: URL,
        layout: ProfileLayout,
        fileManager: FileManager
    ) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let type = attributes[.type] as? FileAttributeType,
              type == .typeSymbolicLink,
              let destination = try? fileManager.destinationOfSymbolicLink(atPath: url.path),
              !(destination as NSString).isAbsolutePath
        else {
            return false
        }

        let destinationURL = directory.appendingPathComponent(destination).standardizedFileURL
        guard destinationURL.deletingLastPathComponent().path ==
                directory.standardizedFileURL.path,
              layout.isProfileFileName(destinationURL.lastPathComponent, in: directory) else {
            return false
        }
        return layout == .claude || hasManagedProfileSymlinkMarker(at: url)
    }

    private static func markManagedProfileSymlink(at url: URL) throws {
        var marker = managedProfileLinkAttributeValue
        let result: Int32 = url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                errno = EINVAL
                return -1
            }
            return managedProfileLinkAttribute.withCString { name in
                withUnsafeBytes(of: &marker) { bytes in
                    Darwin.setxattr(
                        path,
                        name,
                        bytes.baseAddress,
                        bytes.count,
                        0,
                        XATTR_NOFOLLOW
                    )
                }
            }
        }
        guard result == 0 else {
            throw posixError(errno, operation: "managed-link marker")
        }
    }

    private static func hasManagedProfileSymlinkMarker(at url: URL) -> Bool {
        var marker: UInt8 = 0
        let result: Int = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return -1 }
            return managedProfileLinkAttribute.withCString { name in
                withUnsafeMutableBytes(of: &marker) { bytes in
                    Darwin.getxattr(
                        path,
                        name,
                        bytes.baseAddress,
                        bytes.count,
                        0,
                        XATTR_NOFOLLOW
                    )
                }
            }
        }
        return result == 1 && marker == managedProfileLinkAttributeValue
    }

    private static func preserveDisplacedItem(
        at source: URL,
        defaultBackup: URL,
        in directory: URL,
        layout: ProfileLayout,
        fileManager: FileManager,
        uniqueIdentifier: () -> String,
        renameItem: (String, String, AtomicRenameOperation) -> Int32
    ) throws {
        var destination = defaultBackup

        while true {
            if (try? fileManager.attributesOfItem(atPath: destination.path)) != nil {
                destination = nextAvailableURL(
                    in: directory,
                    prefix: layout.recoveryPrefix,
                    suffix: ".md",
                    fileManager: fileManager,
                    uniqueIdentifier: uniqueIdentifier
                )
                continue
            }

            if renameItem(source.path, destination.path, .exclusive) == 0 {
                return
            }

            let renameError = errno
            if renameError == EEXIST {
                destination = nextAvailableURL(
                    in: directory,
                    prefix: layout.recoveryPrefix,
                    suffix: ".md",
                    fileManager: fileManager,
                    uniqueIdentifier: uniqueIdentifier
                )
                continue
            }
            throw posixError(renameError, operation: "recovery rename")
        }
    }

    private static func atomicRename(
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

    private static func posixError(_ code: Int32, operation: String) -> NSError {
        let message = String(cString: strerror(code))
        return NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(code),
            userInfo: [NSLocalizedDescriptionKey: "\(operation) failed: \(message)"]
        )
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
