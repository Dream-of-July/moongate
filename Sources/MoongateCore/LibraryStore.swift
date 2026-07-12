import Foundation

public enum LibraryStoreError: LocalizedError, Sendable, Equatable {
    case unsupportedSchemaVersion(Int)
    case corruptBackupFailed(String)
    case missingLibraryItem(UUID)
    case missingLibraryVersion(UUID)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "This library was created by a newer version of Moongate (schema \(version))."
        case .corruptBackupFailed(let reason):
            return "Moongate could not back up the corrupt library file: \(reason)"
        case .missingLibraryItem:
            return "The selected video is no longer in the library."
        case .missingLibraryVersion:
            return "The selected output version is no longer in the library."
        }
    }
}

public struct LibraryRecoveredCandidate: Sendable, Equatable, Identifiable {
    public var id: String { relativePath }
    public let title: String
    public let relativePath: String
    public let size: Int64?
    public let modifiedAt: Date?

    public init(title: String, relativePath: String, size: Int64?, modifiedAt: Date?) {
        self.title = title
        self.relativePath = relativePath
        self.size = size
        self.modifiedAt = modifiedAt
    }
}

/// The serial owner of `Application Support/月之门/library.json`. The actor
/// keeps concurrent queue callbacks from racing one another, while writes use
/// a same-directory temporary file and replacement so an interrupted write
/// cannot silently destroy the previous library.
public actor LibraryStore {
    public typealias DataWriter = @Sendable (_ data: Data, _ destination: URL) throws -> Void

    public nonisolated let fileURL: URL
    private let directory: URL
    private let injectedDataWriter: DataWriter?

    public init(
        directory: URL = LibraryStore.defaultDirectory,
        fileName: String = "library.json",
        dataWriter: DataWriter? = nil
    ) {
        self.directory = directory
        self.fileURL = directory.appendingPathComponent(fileName)
        self.injectedDataWriter = dataWriter
    }

    public nonisolated static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("月之门", isDirectory: true)
    }

    public func load() throws -> LibraryEnvelope {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return LibraryEnvelope()
        }

        let data = try Data(contentsOf: fileURL)
        do {
            var envelope = try JSONDecoder().decode(LibraryEnvelope.self, from: data)
            try migrate(&envelope)
            return envelope
        } catch let error as LibraryStoreError {
            throw error
        } catch {
            try backupCorruptLibrary()
            return LibraryEnvelope()
        }
    }

    public func save(_ envelope: LibraryEnvelope) throws {
        var persisted = envelope
        persisted.schemaVersion = LibraryEnvelope.currentSchemaVersion

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(persisted)
        try writeAtomically(data)
    }

    /// Inserts or replaces an item by stable library id. It is the only
    /// mutation used by queue callbacks, so repeated callbacks never create
    /// duplicate records.
    public func upsert(_ item: LibraryItem) throws {
        var envelope = try load()
        if let index = envelope.items.firstIndex(where: { $0.id == item.id }) {
            envelope.items[index] = item
        } else {
            envelope.items.append(item)
        }
        try save(envelope)
    }

    /// Removing an index record intentionally does not touch media files. The
    /// caller can retain the returned value and restore it with `upsert` for an
    /// undo action; moving a file to the Trash is a separate UI flow.
    @discardableResult
    public func remove(itemID: UUID) throws -> LibraryItem? {
        var envelope = try load()
        guard let index = envelope.items.firstIndex(where: { $0.id == itemID }) else {
            return nil
        }
        let removed = envelope.items.remove(at: index)
        try save(envelope)
        return removed
    }

    /// Applies a runtime update to the selected version without serialising a
    /// QueueItem or its AppSettings snapshot.
    public func updateProcessing(
        itemID: UUID,
        versionID: UUID,
        processing: ProcessingSummary
    ) throws {
        var envelope = try load()
        guard let itemIndex = envelope.items.firstIndex(where: { $0.id == itemID }) else {
            throw LibraryStoreError.missingLibraryItem(itemID)
        }
        guard let versionIndex = envelope.items[itemIndex].versions.firstIndex(where: { $0.id == versionID }) else {
            throw LibraryStoreError.missingLibraryVersion(versionID)
        }

        envelope.items[itemIndex].versions[versionIndex].processing = processing
        envelope.items[itemIndex].updatedAt = processing.updatedAt
        try save(envelope)
    }

    /// A task cannot be safely continued after process termination because its
    /// downloader/ASR state is in memory. Mark it honestly as interrupted and
    /// let the user explicitly restart it.
    @discardableResult
    public func markActiveItemsInterrupted(now: Date = Date()) throws -> Int {
        var envelope = try load()
        var changedCount = 0

        for itemIndex in envelope.items.indices {
            guard let versionIndex = latestVersionIndex(in: envelope.items[itemIndex]),
                  envelope.items[itemIndex].versions[versionIndex].processing.state.isRunning else {
                continue
            }

            envelope.items[itemIndex].versions[versionIndex].processing.state = .interrupted
            envelope.items[itemIndex].versions[versionIndex].processing.stage = .recovery
            envelope.items[itemIndex].versions[versionIndex].processing.attention = ProcessingAttention(
                kind: .interrupted,
                primaryAction: .restart,
                stage: .recovery,
                occurredAt: now
            )
            envelope.items[itemIndex].versions[versionIndex].processing.updatedAt = now
            envelope.items[itemIndex].updatedAt = now
            changedCount += 1
        }

        if changedCount > 0 {
            try save(envelope)
        }
        return changedCount
    }

    /// Reads a former downloads directory without moving any files or creating
    /// library records. The UI can show this count first and ask the user to
    /// confirm import.
    public func discoverLegacyDownloads(at rootURL: URL) throws -> [LibraryRecoveredCandidate] {
        let root = rootURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }

        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "mkv", "webm", "avi", "flv", "ts"]
        var candidates: [LibraryRecoveredCandidate] = []
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"

        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true,
                  values?.isSymbolicLink != true,
                  videoExtensions.contains(fileURL.pathExtension.lowercased()),
                  fileURL.standardizedFileURL.path.hasPrefix(rootPrefix) else {
                continue
            }

            let relativePath = String(fileURL.standardizedFileURL.path.dropFirst(rootPrefix.count))
            guard (try? LibraryArtifact(role: .video, relativePath: relativePath)) != nil else {
                continue
            }
            candidates.append(
                LibraryRecoveredCandidate(
                    title: fileURL.deletingPathExtension().lastPathComponent,
                    relativePath: relativePath,
                    size: values?.fileSize.map(Int64.init),
                    modifiedAt: values?.contentModificationDate
                )
            )
        }

        return candidates.sorted {
            $0.relativePath.compare($1.relativePath, options: [.literal]) == .orderedAscending
        }
    }

    /// Creates stable recovered records only after the user has confirmed the
    /// candidates. Re-importing the same list is idempotent by artifact path.
    @discardableResult
    public func importRecovered(_ candidates: [LibraryRecoveredCandidate], now: Date = Date()) throws -> Int {
        var envelope = try load()
        var knownPaths = Set(
            envelope.items.flatMap { item in
                item.versions.flatMap(\.artifacts).map(\.relativePath)
            }
        )
        var importedCount = 0

        for candidate in candidates where knownPaths.insert(candidate.relativePath).inserted {
            let artifact = try LibraryArtifact(
                role: .video,
                relativePath: candidate.relativePath,
                size: candidate.size,
                modifiedAt: candidate.modifiedAt
            )
            let timestamp = candidate.modifiedAt ?? now
            let processing = ProcessingSummary(
                state: .completed,
                stage: .recovery,
                progress: 1,
                updatedAt: timestamp
            )
            let version = LibraryVersion(
                number: 1,
                processing: processing,
                artifacts: [artifact],
                createdAt: timestamp
            )
            envelope.items.append(
                LibraryItem(
                    title: candidate.title,
                    tags: ["已恢复"],
                    versions: [version],
                    createdAt: timestamp,
                    updatedAt: timestamp
                )
            )
            importedCount += 1
        }

        if importedCount > 0 {
            if !envelope.tags.contains(where: { $0.name == "已恢复" }) {
                envelope.tags.append(LibraryTag(name: "已恢复"))
            }
            try save(envelope)
        }
        return importedCount
    }

    private func migrate(_ envelope: inout LibraryEnvelope) throws {
        guard envelope.schemaVersion <= LibraryEnvelope.currentSchemaVersion else {
            throw LibraryStoreError.unsupportedSchemaVersion(envelope.schemaVersion)
        }
        guard envelope.schemaVersion < LibraryEnvelope.currentSchemaVersion else { return }

        // v1 did not persist raw queue error strings. Preserve its state but
        // give old attention records a deliberately generic, actionable next
        // step rather than inventing a failure cause.
        while envelope.schemaVersion < LibraryEnvelope.currentSchemaVersion {
            switch envelope.schemaVersion {
            case 0:
                envelope.schemaVersion = 1
            case 1:
                for itemIndex in envelope.items.indices {
                    for versionIndex in envelope.items[itemIndex].versions.indices {
                        let processing = envelope.items[itemIndex].versions[versionIndex].processing
                        guard processing.state == .needsAttention,
                              processing.attention == nil else {
                            continue
                        }
                        envelope.items[itemIndex].versions[versionIndex].processing.attention = ProcessingAttention(
                            kind: .needsReview,
                            primaryAction: .review,
                            stage: processing.stage,
                            occurredAt: processing.updatedAt
                        )
                    }
                }
                envelope.schemaVersion = 2
            default:
                throw LibraryStoreError.unsupportedSchemaVersion(envelope.schemaVersion)
            }
        }
        try save(envelope)
    }

    private func writeAtomically(_ data: Data) throws {
        if let injectedDataWriter {
            try injectedDataWriter(data, fileURL)
            return
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporaryURL = directory.appendingPathComponent(".library-\(UUID().uuidString).tmp")
        #if os(Windows)
        let attributes: [FileAttributeKey: Any]? = nil
        #else
        let attributes: [FileAttributeKey: Any]? = [.posixPermissions: 0o600]
        #endif
        guard fileManager.createFile(atPath: temporaryURL.path, contents: data, attributes: attributes) else {
            throw CocoaError(.fileWriteUnknown)
        }

        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: fileURL)
            }
            #if !os(Windows)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            #endif
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func backupCorruptLibrary() throws {
        let fileManager = FileManager.default
        let backupURL = directory.appendingPathComponent(
            "library.corrupt-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString).json"
        )
        do {
            try fileManager.moveItem(at: fileURL, to: backupURL)
            #if !os(Windows)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
            #endif
        } catch {
            throw LibraryStoreError.corruptBackupFailed(error.localizedDescription)
        }
    }

    private func latestVersionIndex(in item: LibraryItem) -> Int? {
        item.versions.indices.max { lhs, rhs in
            let left = item.versions[lhs]
            let right = item.versions[rhs]
            return left.number == right.number ? left.createdAt < right.createdAt : left.number < right.number
        }
    }
}
