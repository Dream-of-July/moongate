import Foundation

public enum IOSAppStoragePolicy {
    public static func applyDirectoryPolicy(to directoryURL: URL) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try markExcludedFromBackup(directoryURL)
    }

    public static func applyFilePolicy(to fileURL: URL) throws {
        try applyDirectoryPolicy(to: fileURL.deletingLastPathComponent())
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try markExcludedFromBackup(fileURL)
        }
    }

    private static func markExcludedFromBackup(_ url: URL) throws {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableURL.setResourceValues(values)
    }
}
