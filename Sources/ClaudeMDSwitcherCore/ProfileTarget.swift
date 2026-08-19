import Darwin
import Foundation

public enum ProfileTarget: String, CaseIterable, Identifiable {
    case claude
    case codex

    public static let selectionDefaultsKey = "selectedProfileTarget"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    public var directoryName: String {
        switch self {
        case .claude: ".claude"
        case .codex: ".codex"
        }
    }

    public var layout: ProfileLayout {
        switch self {
        case .claude: .claude
        case .codex: .codex
        }
    }

    public static func loadSelection(from defaults: UserDefaults) -> ProfileTarget {
        guard let value = defaults.string(forKey: selectionDefaultsKey),
              let target = ProfileTarget(rawValue: value) else {
            return .claude
        }
        return target
    }

    public func persistSelection(to defaults: UserDefaults) {
        defaults.set(rawValue, forKey: Self.selectionDefaultsKey)
    }
}

public struct ProfileLayout: Equatable {
    public static let claude = ProfileLayout(baseName: "CLAUDE")
    public static let codex = ProfileLayout(
        baseName: "AGENTS",
        reservedFileNames: ["AGENTS.override.md"]
    )

    public let baseName: String
    public let reservedFileNames: Set<String>

    public init(baseName: String, reservedFileNames: Set<String> = []) {
        self.baseName = baseName
        self.reservedFileNames = reservedFileNames.union(["\(baseName).md"])
    }

    public var mainFileName: String { "\(baseName).md" }
    public var defaultBackupFileName: String { "\(baseName).default.md" }
    public var recoveryPrefix: String { "\(baseName).recovered-" }
    public var temporaryPrefix: String { ".\(baseName).md.swap-" }
    public var profilePattern: String { "\(baseName).*.md" }

    public func isProfileFileName(_ fileName: String) -> Bool {
        fileName.hasPrefix("\(baseName).") &&
            fileName.hasSuffix(".md") &&
            !reservedFileNames.contains(fileName)
    }

    func isProfileFileName(_ fileName: String, in directory: URL) -> Bool {
        fileName.hasPrefix("\(baseName).") &&
            fileName.hasSuffix(".md") &&
            !reservedFileNames.contains {
                ProfileFileValidation.fileNamesAreEquivalent(
                    fileName,
                    $0,
                    in: directory
                )
            }
    }

    public func displayName(forProfileFileName fileName: String) -> String {
        var name = fileName
        let prefix = "\(baseName)."
        if name.hasPrefix(prefix) { name.removeFirst(prefix.count) }
        if name.hasSuffix(".md") { name.removeLast(".md".count) }
        guard !name.isEmpty else { return fileName }
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}

enum ProfileFileValidation {
    static func fileNamesAreEquivalent(
        _ lhs: String,
        _ rhs: String,
        in directory: URL
    ) -> Bool {
        let normalizedLHS = lhs.precomposedStringWithCanonicalMapping
        let normalizedRHS = rhs.precomposedStringWithCanonicalMapping
        let isCaseSensitive = (
            try? directory.resourceValues(
                forKeys: [.volumeSupportsCaseSensitiveNamesKey]
            )
        )?.volumeSupportsCaseSensitiveNames

        if isCaseSensitive == true {
            return normalizedLHS == normalizedRHS
        }
        return normalizedLHS.compare(
            normalizedRHS,
            options: [.caseInsensitive, .literal],
            locale: Locale(identifier: "en_US_POSIX")
        ) == .orderedSame
    }

    static func isReadableRegularFile(
        at url: URL,
        avoiding canonicalURL: URL? = nil
    ) -> Bool {
        if let canonicalURL,
           symlinkChain(from: url, contains: canonicalURL) {
            return false
        }

        let resolvedURL = url.resolvingSymlinksInPath()
        guard let attributes = try? FileManager.default.attributesOfItem(
            atPath: resolvedURL.path
        ),
              attributes[.type] as? FileAttributeType == .typeRegular else {
            return false
        }
        return FileManager.default.isReadableFile(atPath: resolvedURL.path)
    }

    private static func symlinkChain(from url: URL, contains forbiddenURL: URL) -> Bool {
        let fileManager = FileManager.default
        var currentURL = normalizedWithoutResolvingFinal(url)
        var visitedPaths = Set<String>()

        while true {
            if referToSameDirectoryEntry(currentURL, forbiddenURL) {
                return true
            }
            guard visitedPaths.insert(currentURL.path).inserted,
                  let attributes = try? fileManager.attributesOfItem(
                    atPath: currentURL.path
                  ),
                  attributes[.type] as? FileAttributeType == .typeSymbolicLink,
                  let destination = try? fileManager.destinationOfSymbolicLink(
                    atPath: currentURL.path
                  ) else {
                return false
            }

            if (destination as NSString).isAbsolutePath {
                currentURL = normalizedWithoutResolvingFinal(
                    URL(fileURLWithPath: destination)
                )
            } else {
                currentURL = normalizedWithoutResolvingFinal(
                    currentURL.deletingLastPathComponent()
                        .appendingPathComponent(destination)
                )
            }
        }
    }

    static func referToSameDirectoryEntry(_ lhs: URL, _ rhs: URL) -> Bool {
        let normalizedLHS = normalizedWithoutResolvingFinal(lhs)
        let normalizedRHS = normalizedWithoutResolvingFinal(rhs)
        let lhsParent = normalizedLHS.deletingLastPathComponent()
        let rhsParent = normalizedRHS.deletingLastPathComponent()

        guard directoriesAreEquivalent(lhsParent, rhsParent) else {
            return false
        }
        return fileNamesAreEquivalent(
            normalizedLHS.lastPathComponent,
            normalizedRHS.lastPathComponent,
            in: lhsParent
        )
    }

    private static func directoriesAreEquivalent(_ lhs: URL, _ rhs: URL) -> Bool {
        var lhsInfo = stat()
        var rhsInfo = stat()
        let lhsStatus: Int32 = lhs.withUnsafeFileSystemRepresentation { path in
            guard let path else { return -1 }
            return Darwin.lstat(path, &lhsInfo)
        }
        let rhsStatus: Int32 = rhs.withUnsafeFileSystemRepresentation { path in
            guard let path else { return -1 }
            return Darwin.lstat(path, &rhsInfo)
        }

        if lhsStatus == 0, rhsStatus == 0 {
            return lhsInfo.st_dev == rhsInfo.st_dev &&
                lhsInfo.st_ino == rhsInfo.st_ino
        }
        return lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }

    private static func normalizedWithoutResolvingFinal(_ url: URL) -> URL {
        url.deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .appendingPathComponent(url.lastPathComponent)
            .standardizedFileURL
    }
}

public enum ProfileDiscovery {
    public static func fileURLsAreEquivalent(_ lhs: URL, _ rhs: URL) -> Bool {
        ProfileFileValidation.referToSameDirectoryEntry(lhs, rhs)
    }

    public static func profileURLs(in directory: URL, layout: ProfileLayout) -> [URL] {
        let mainFile = directory.appendingPathComponent(layout.mainFileName)
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []

        return entries
            .filter {
                guard layout.isProfileFileName($0.lastPathComponent, in: directory),
                      let attributes = try? FileManager.default.attributesOfItem(atPath: $0.path),
                      let type = attributes[.type] as? FileAttributeType else {
                    return false
                }
                return (type == .typeRegular || type == .typeSymbolicLink) &&
                    ProfileFileValidation.isReadableRegularFile(
                        at: $0,
                        avoiding: mainFile
                    )
            }
            .sorted {
                let lhs = layout.displayName(forProfileFileName: $0.lastPathComponent)
                let rhs = layout.displayName(forProfileFileName: $1.lastPathComponent)
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
    }

    public static func activeProfileURL(in directory: URL, layout: ProfileLayout) -> URL? {
        let mainFile = directory.appendingPathComponent(layout.mainFileName)
        let fileManager = FileManager.default

        guard let attributes = try? fileManager.attributesOfItem(atPath: mainFile.path),
              let type = attributes[.type] as? FileAttributeType,
              type == .typeSymbolicLink,
              let destination = try? fileManager.destinationOfSymbolicLink(atPath: mainFile.path)
        else {
            return nil
        }

        let destinationURL: URL
        if (destination as NSString).isAbsolutePath {
            destinationURL = URL(fileURLWithPath: destination).standardizedFileURL
        } else {
            destinationURL = directory.appendingPathComponent(destination).standardizedFileURL
        }

        return profileURLs(in: directory, layout: layout).first {
            fileURLsAreEquivalent($0, destinationURL)
        }
    }
}
