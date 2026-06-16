import Foundation

public actor IOSSourceReferenceStore {
    public enum StoreError: Error, Equatable {
        case invalidFileName
    }

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.sortedKeys]
    }

    public init(directoryURL: URL, fileName: String = "mobile-source-references.json") throws {
        guard !fileName.contains("/") else {
            throw StoreError.invalidFileName
        }
        try IOSAppStoragePolicy.applyDirectoryPolicy(to: directoryURL)
        self.init(fileURL: directoryURL.appendingPathComponent(fileName, isDirectory: false))
    }

    public func loadSources() async throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return [:]
        }
        return try decoder.decode([String: String].self, from: data)
    }

    public func saveSource(_ sourceURL: String, forTaskID taskID: String) async throws {
        var sources = try await loadSources()
        if Self.isPersistableSourceURL(sourceURL) {
            sources[taskID] = sourceURL
        } else {
            sources.removeValue(forKey: taskID)
        }
        try write(sources)
    }

    public func removeSource(forTaskID taskID: String) async throws {
        var sources = try await loadSources()
        sources.removeValue(forKey: taskID)
        try write(sources)
    }

    private func write(_ sources: [String: String]) throws {
        try IOSAppStoragePolicy.applyDirectoryPolicy(to: fileURL.deletingLastPathComponent())
        let data = try encoder.encode(sources)
        try data.write(to: fileURL, options: [.atomic])
        try IOSAppStoragePolicy.applyFilePolicy(to: fileURL)
    }

    public static func isPersistableSourceURL(_ sourceURL: String) -> Bool {
        let trimmed = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed == sourceURL,
              let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              components.host?.isEmpty == false,
              components.query == nil,
              components.fragment == nil,
              let path = components.percentEncodedPath.removingPercentEncoding,
              isSupportedDirectMediaPath(path) else {
            return false
        }

        let lowercased = trimmed.lowercased()
        let unsafeMarkers = [
            "access_token",
            "authorization",
            "bearer",
            "cookie",
            "credential",
            "secret",
            "signature",
            "token",
            "x-amz"
        ]
        return !unsafeMarkers.contains { lowercased.contains($0) }
    }

    private static func isSupportedDirectMediaPath(_ path: String) -> Bool {
        let pathExtension = (path as NSString).pathExtension.lowercased()
        return ["m4v", "mov", "mp4", "webm"].contains(pathExtension)
    }
}
