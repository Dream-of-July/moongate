import Foundation
import MoongateMobileCore

public enum IOSArtifactStoreError: Error, Equatable {
    case unsafeStorageIdentifier
}

public struct IOSArtifactStore: Sendable {
    public var storageDirectoryURL: URL

    public init(storageDirectoryURL: URL) {
        self.storageDirectoryURL = storageDirectoryURL
    }

    public func fileURL(for artifact: MobileTaskArtifact) throws -> URL {
        try fileURL(forStorageIdentifier: artifact.storageIdentifier)
    }

    public func fileURL(forStorageIdentifier storageIdentifier: String) throws -> URL {
        let identifier = storageIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isSafeRelativeIdentifier(identifier) else {
            throw IOSArtifactStoreError.unsafeStorageIdentifier
        }

        let normalizedIdentifier = Self.normalizedDirectoryCasing(identifier)
        let root = storageDirectoryURL.standardizedFileURL
        let resolved = root.appendingPathComponent(normalizedIdentifier, isDirectory: false).standardizedFileURL
        guard resolved.path == root.path || resolved.path.hasPrefix(root.path + "/") else {
            throw IOSArtifactStoreError.unsafeStorageIdentifier
        }
        return resolved
    }

    private static func isSafeRelativeIdentifier(_ identifier: String) -> Bool {
        guard !identifier.isEmpty else { return false }

        let lowercased = identifier.lowercased()
        if lowercased.hasPrefix("source:") ||
            lowercased.hasPrefix("http://") ||
            lowercased.hasPrefix("https://") ||
            lowercased.hasPrefix("file://") ||
            identifier.hasPrefix("/") ||
            identifier.hasPrefix("~") {
            return false
        }

        let unsafeMarkers = [
            "access_token",
            "authorization",
            "bearer ",
            "cookie",
            "x-amz-signature",
            "secret_token"
        ]
        guard !unsafeMarkers.contains(where: { lowercased.contains($0) }) else {
            return false
        }

        return !identifier
            .split(separator: "/", omittingEmptySubsequences: false)
            .contains { component in
                component == "." || component == ".." || component.isEmpty
            }
    }

    private static func normalizedDirectoryCasing(_ identifier: String) -> String {
        var components = identifier.split(separator: "/").map(String.init)
        guard let first = components.first?.lowercased() else { return identifier }
        switch first {
        case "downloads":
            components[0] = "Downloads"
        case "subtitles":
            components[0] = "Subtitles"
        default:
            break
        }
        return components.joined(separator: "/")
    }
}
