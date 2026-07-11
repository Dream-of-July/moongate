import XCTest
@testable import MoongateCore

final class LibraryStoreTests: XCTestCase {
    func testRoundTripPersistsEnvelopeWithOwnerOnlyPermissions() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = LibraryStore(directory: directory)
        let original = try makeEnvelope(title: "Mate 80", state: .completed)

        try await store.save(original)
        let loaded = try await store.load()

        XCTAssertEqual(loaded, original)
        #if !os(Windows)
        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        let permissions = try XCTUnwrap(attributes[FileAttributeKey.posixPermissions] as? NSNumber).intValue
        XCTAssertEqual(permissions & 0o777, 0o600)
        #endif
    }

    func testMissingSchemaMigratesToCurrentVersion() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("library.json")
        try Data("{\"tags\":[],\"items\":[]}".utf8).write(to: fileURL)

        let store = LibraryStore(directory: directory)
        let loaded = try await store.load()

        XCTAssertEqual(loaded.schemaVersion, LibraryEnvelope.currentSchemaVersion)
        XCTAssertTrue(loaded.items.isEmpty)
    }

    func testCorruptDataIsBackedUpInsteadOfOverwritten() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("library.json")
        let corruptData = Data("not valid json".utf8)
        try corruptData.write(to: fileURL)

        let store = LibraryStore(directory: directory)
        let loaded = try await store.load()
        let backupURLs = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("library.corrupt-") }

        XCTAssertEqual(loaded, LibraryEnvelope())
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(backupURLs.count, 1)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(backupURLs.first)), corruptData)
    }

    func testFailedWriteLeavesPreviousLibraryIntact() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = LibraryStore(directory: directory)
        let original = try makeEnvelope(title: "Original", state: .completed)
        try await store.save(original)

        let failingStore = LibraryStore(directory: directory) { _, _ in
            throw WriteFailure.injected
        }
        do {
            try await failingStore.save(try makeEnvelope(title: "Replacement", state: .completed))
            XCTFail("Expected the injected writer to fail")
        } catch WriteFailure.injected {
            // Expected: atomic writing must not replace the previous file.
        }

        let restored = try await store.load()
        XCTAssertEqual(restored, original)
    }

    func testConcurrentUpsertsDoNotLoseItems() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = LibraryStore(directory: directory)
        let items = try (0 ..< 20).map { index in
            try makeItem(title: "Video \(index)", state: .queued)
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for item in items {
                group.addTask {
                    try await store.upsert(item)
                }
            }
            try await group.waitForAll()
        }

        let loaded = try await store.load()
        XCTAssertEqual(Set(loaded.items.map(\.id)), Set(items.map(\.id)))
    }

    func testActiveItemsAreMarkedInterruptedAfterRestart() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let active = try makeItem(title: "Downloading", state: .downloading)
        let completed = try makeItem(title: "Completed", state: .completed)
        let store = LibraryStore(directory: directory)
        try await store.save(LibraryEnvelope(items: [active, completed]))

        let interruptedCount = try await store.markActiveItemsInterrupted()
        XCTAssertEqual(interruptedCount, 1)
        let loaded = try await store.load()

        XCTAssertEqual(loaded.items.first(where: { $0.id == active.id })?.latestVersion?.processing.state, .interrupted)
        XCTAssertEqual(loaded.items.first(where: { $0.id == completed.id })?.latestVersion?.processing.state, .completed)
    }

    func testLegacyDiscoveryIsReadOnlyAndImportIsIdempotent() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let legacyDirectory = directory.appendingPathComponent("Legacy", isDirectory: true)
        let nestedDirectory = legacyDirectory.appendingPathComponent("Tech", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        try Data("movie".utf8).write(to: nestedDirectory.appendingPathComponent("Mate 80.mp4"))
        try Data("movie".utf8).write(to: legacyDirectory.appendingPathComponent("clip.webm"))
        try Data("not a video".utf8).write(to: legacyDirectory.appendingPathComponent("notes.txt"))

        let store = LibraryStore(directory: directory.appendingPathComponent("Support", isDirectory: true))
        let candidates = try await store.discoverLegacyDownloads(at: legacyDirectory)

        XCTAssertEqual(candidates.map(\.relativePath), ["Tech/Mate 80.mp4", "clip.webm"])
        let beforeImport = try await store.load()
        let firstImportCount = try await store.importRecovered(candidates)
        let secondImportCount = try await store.importRecovered(candidates)
        XCTAssertTrue(beforeImport.items.isEmpty)
        XCTAssertEqual(firstImportCount, 2)
        XCTAssertEqual(secondImportCount, 0)

        let loaded = try await store.load()
        XCTAssertEqual(loaded.items.count, 2)
        XCTAssertTrue(loaded.tags.contains(where: { $0.name == "已恢复" }))
        XCTAssertTrue(loaded.items.allSatisfy { $0.source == nil })
        XCTAssertTrue(loaded.items.allSatisfy { $0.latestVersion?.processing.state == .completed })
        XCTAssertTrue(loaded.items.allSatisfy { $0.latestVersion?.processing.actualModels == .init() })
    }

    private func makeEnvelope(title: String, state: LibraryItemState) throws -> LibraryEnvelope {
        LibraryEnvelope(items: [try makeItem(title: title, state: state)])
    }

    private func makeItem(title: String, state: LibraryItemState) throws -> MoongateCore.LibraryItem {
        let processing = ProcessingSummary(
            state: state,
            stage: state == .completed ? .complete : .download,
            progress: state == .completed ? 1 : 0.5,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        return LibraryItem(
            title: title,
            versions: [LibraryVersion(number: 1, processing: processing, createdAt: Date(timeIntervalSince1970: 100))],
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MoongateLibraryStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private enum WriteFailure: Error {
        case injected
    }
}
