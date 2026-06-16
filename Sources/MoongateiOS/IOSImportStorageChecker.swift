import Foundation

public protocol IOSImportStorageChecking: Sendable {
    func hasEnoughSpaceToImport(
        sourceURL: URL,
        storageDirectoryURL: URL
    ) -> Bool
}

public struct IOSImportStorageChecker: IOSImportStorageChecking {
    public init() {}

    public func hasEnoughSpaceToImport(
        sourceURL: URL,
        storageDirectoryURL: URL
    ) -> Bool {
        guard let sourceByteCount = regularFileByteCount(at: sourceURL) else {
            return true
        }
        guard let availableByteCount = availableStorageByteCount(at: storageDirectoryURL) else {
            return true
        }
        return availableByteCount > sourceByteCount
    }

    private func regularFileByteCount(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let fileSize = values.fileSize else {
            return nil
        }
        return Int64(fileSize)
    }

    private func availableStorageByteCount(at url: URL) -> Int64? {
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let capacity = values.volumeAvailableCapacityForImportantUsage {
            return capacity
        }
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
           let capacity = values.volumeAvailableCapacity {
            return Int64(capacity)
        }
        return nil
    }
}
