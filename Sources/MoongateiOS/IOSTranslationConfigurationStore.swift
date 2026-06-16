import Foundation
import MoongateMobileCore

public struct IOSTranslationConfigurationStore: Sendable {
    public enum StoreError: Error, Equatable {
        case invalidFileName
    }

    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public init(directoryURL: URL, fileName: String = "mobile-translation-configuration.json") throws {
        guard !fileName.contains("/") else {
            throw StoreError.invalidFileName
        }
        try IOSAppStoragePolicy.applyDirectoryPolicy(to: directoryURL)
        self.init(fileURL: directoryURL.appendingPathComponent(fileName, isDirectory: false))
    }

    public func loadConfiguration() throws -> MobileTranslationConfiguration? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return nil
        }
        let decoder = JSONDecoder()
        return try decoder.decode(MobileTranslationConfiguration.self, from: data)
    }

    public func saveConfiguration(_ configuration: MobileTranslationConfiguration) throws {
        try IOSAppStoragePolicy.applyDirectoryPolicy(to: fileURL.deletingLastPathComponent())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(configuration)
        try data.write(to: fileURL, options: [.atomic])
        try IOSAppStoragePolicy.applyFilePolicy(to: fileURL)
    }
}
