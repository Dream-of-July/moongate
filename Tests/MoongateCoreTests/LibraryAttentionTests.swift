import XCTest
@testable import MoongateCore

final class LibraryAttentionTests: XCTestCase {
    func testSchemaV1MigrationKeepsNeedsAttentionState() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let processing = ProcessingSummary(
            state: .needsAttention,
            stage: .recovery,
            progress: 0.4,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let item = LibraryItem(
            title: "Legacy item",
            versions: [LibraryVersion(number: 1, processing: processing)],
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let legacyEnvelope = LibraryEnvelope(schemaVersion: 1, items: [item])
        let fileURL = directory.appendingPathComponent("library.json")
        try JSONEncoder().encode(legacyEnvelope).write(to: fileURL)

        let loaded = try await LibraryStore(directory: directory).load()

        XCTAssertEqual(loaded.schemaVersion, 2)
        XCTAssertEqual(loaded.items.first?.latestVersion?.processing.state, .needsAttention)
        XCTAssertEqual(loaded.items.first?.latestVersion?.processing.attention?.kind, .needsReview)
        XCTAssertEqual(loaded.items.first?.latestVersion?.processing.attention?.primaryAction, .review,
                       "v1 records keep their state, but must receive an explicit non-invented recovery action.")
    }

    func testAttentionRoundTripDropsUnsafeStatusDetails() throws {
        let date = Date(timeIntervalSince1970: 100)
        let attention = ProcessingAttention(
            kind: .processingFailed,
            summary: "HTTP 401 Authorization: Bearer sk-live-secret /Users/july/private.mov",
            primaryAction: .retry,
            stage: .download,
            occurredAt: date
        )

        let data = try JSONEncoder().encode(attention)
        let decoded = try JSONDecoder().decode(ProcessingAttention.self, from: data)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8)).lowercased()

        XCTAssertEqual(decoded, attention)
        XCTAssertEqual(attention.title, "处理失败")
        XCTAssertEqual(attention.summary, "处理未完成，可重试。")
        XCTAssertFalse(json.contains("bearer"))
        XCTAssertFalse(json.contains("sk-live-secret"))
        XCTAssertFalse(json.contains("/users/july"))
        XCTAssertFalse(json.contains("http 401"))

        let hyphenatedKey = ProcessingAttention(
            kind: .processingFailed,
            summary: "X-API-Key: abc123 ~/Library/Moongate",
            primaryAction: .retry,
            stage: .download,
            occurredAt: date
        )
        let hyphenatedJSON = try XCTUnwrap(String(data: JSONEncoder().encode(hyphenatedKey), encoding: .utf8)).lowercased()
        XCTAssertEqual(hyphenatedKey.summary, "处理未完成，可重试。")
        XCTAssertFalse(hyphenatedJSON.contains("x-api-key"))
        XCTAssertFalse(hyphenatedJSON.contains("abc123"))
        XCTAssertFalse(hyphenatedJSON.contains("~/library"))
    }

    func testClassifierMapsKnownQueueRecoveryStates() {
        let date = Date(timeIntervalSince1970: 100)

        let login = ProcessingAttentionClassifier.classify(
            state: .failed,
            stage: .recovery,
            statusText: "Request failed: HTTP 403",
            loginSite: "www.youtube.com",
            isDeferredDraft: false,
            usesLocalRecognition: false,
            usesCloudRecognition: false,
            occurredAt: date
        )
        XCTAssertEqual(login?.kind, .loginRequired)
        XCTAssertEqual(login?.primaryAction, .login)
        XCTAssertEqual(login?.summary, "请登录 youtube.com 后重试。")

        let localRecognition = ProcessingAttentionClassifier.classify(
            state: .failed,
            stage: .download,
            statusText: "所选的本地转录模型尚未准备好。",
            loginSite: nil,
            isDeferredDraft: false,
            usesLocalRecognition: true,
            usesCloudRecognition: false,
            occurredAt: date
        )
        XCTAssertEqual(localRecognition?.kind, .capabilityUnavailable)
        XCTAssertEqual(localRecognition?.primaryAction, .prepareLocalRecognition)

        let deferredDraft = ProcessingAttentionClassifier.classify(
            state: .queued,
            stage: .download,
            statusText: "所选的本地转录模型尚未准备好。",
            loginSite: nil,
            isDeferredDraft: true,
            usesLocalRecognition: true,
            usesCloudRecognition: false,
            occurredAt: date
        )
        XCTAssertNil(deferredDraft,
                     "待开始任务必须保留为可编辑草稿；本地识别能力在用户点击开始时按需准备。")

        let cloudRecognition = ProcessingAttentionClassifier.classify(
            state: .failed,
            stage: .download,
            statusText: "Cloud recognition needs setup.",
            loginSite: nil,
            isDeferredDraft: false,
            usesLocalRecognition: false,
            usesCloudRecognition: true,
            occurredAt: date
        )
        XCTAssertEqual(cloudRecognition?.kind, .capabilityUnavailable)
        XCTAssertEqual(cloudRecognition?.primaryAction, .configureCloudRecognition)

        let configuredCloudRecognition = ProcessingAttentionClassifier.classify(
            state: .failed,
            stage: .transcribe,
            statusText: "Configure cloud recognition before retrying.",
            loginSite: nil,
            isDeferredDraft: false,
            usesLocalRecognition: false,
            usesCloudRecognition: true,
            occurredAt: date
        )
        XCTAssertEqual(configuredCloudRecognition?.kind, .capabilityUnavailable)
        XCTAssertEqual(configuredCloudRecognition?.primaryAction, .configureCloudRecognition)

        let interrupted = ProcessingAttentionClassifier.classify(
            state: .interrupted,
            stage: .recovery,
            statusText: nil,
            loginSite: nil,
            isDeferredDraft: false,
            usesLocalRecognition: false,
            usesCloudRecognition: false,
            occurredAt: date
        )
        XCTAssertEqual(interrupted?.kind, .interrupted)
        XCTAssertEqual(interrupted?.primaryAction, .restart)

        let missingFile = ProcessingAttentionClassifier.classify(
            state: .failed,
            stage: .recovery,
            statusText: "File not found",
            loginSite: nil,
            isDeferredDraft: false,
            usesLocalRecognition: false,
            usesCloudRecognition: false,
            occurredAt: date
        )
        XCTAssertEqual(missingFile?.kind, .fileMissing)
        XCTAssertEqual(missingFile?.primaryAction, .locateFile)
    }

    func testStoreMarksActiveItemInterruptedWithRestartAttention() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = Date(timeIntervalSince1970: 100)
        let item = LibraryItem(
            title: "Interrupted item",
            versions: [LibraryVersion(
                number: 1,
                processing: ProcessingSummary(state: .downloading, stage: .download, progress: 0.4, updatedAt: date)
            )],
            createdAt: date,
            updatedAt: date
        )
        let store = LibraryStore(directory: directory)
        try await store.save(LibraryEnvelope(items: [item]))

        _ = try await store.markActiveItemsInterrupted(now: date)
        let attention = try await store.load().items.first?.latestVersion?.processing.attention

        XCTAssertEqual(attention?.kind, .interrupted)
        XCTAssertEqual(attention?.primaryAction, .restart)
        XCTAssertEqual(attention?.stage, .recovery)
        XCTAssertEqual(attention?.occurredAt, date)
    }

    func testStoreLeavesQueuedDraftPendingAfterRestart() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = Date(timeIntervalSince1970: 100)
        let queued = LibraryItem(
            title: "Queued draft",
            versions: [LibraryVersion(
                number: 1,
                processing: ProcessingSummary(state: .queued, stage: .download, progress: 0, updatedAt: date)
            )],
            createdAt: date,
            updatedAt: date
        )
        let store = LibraryStore(directory: directory)
        try await store.save(LibraryEnvelope(items: [queued]))

        let interruptedCount = try await store.markActiveItemsInterrupted(now: date)
        let processing = try await store.load().items.first?.latestVersion?.processing

        XCTAssertEqual(interruptedCount, 0)
        XCTAssertEqual(processing?.state, .queued)
        XCTAssertNil(processing?.attention)
    }

    func testQueueSnapshotUsesTypedAttentionClassifier() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources/Moongate/LibraryWorkspaceModel.swift"))

        XCTAssertTrue(source.contains("ProcessingAttentionClassifier.classify("),
                      "Queue snapshots must map runtime failures to a durable, typed attention record.")
        XCTAssertTrue(source.contains("isDeferredDraft:"),
                      "Queued local/cloud readiness failures must be distinguishable from a task that has already started.")
        XCTAssertFalse(source.contains("if attention != nil, state == .queued"),
                       "A queued draft must not be reclassified as needs-attention before the person starts it.")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MoongateLibraryAttentionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
