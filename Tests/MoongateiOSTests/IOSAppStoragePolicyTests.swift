@testable import MoongateMobileCore
@testable import MoongateiOS
import Foundation
import XCTest

final class IOSAppStoragePolicyTests: XCTestCase {
    func testTaskRepositoryJSONIsExcludedFromBackup() async throws {
        let directory = temporaryDirectory()
        let repository = try FileTaskRepository(directoryURL: directory)

        try await repository.saveTask(MobileTaskSnapshot(id: "task-1", platform: .iOS))

        let fileURL = directory.appendingPathComponent("mobile-tasks.json")
        XCTAssertTrue(try isExcludedFromBackup(fileURL))
        XCTAssertTrue(try isExcludedFromBackup(directory))
    }

    func testTranslationConfigurationJSONIsExcludedFromBackup() throws {
        let directory = temporaryDirectory()
        let store = try IOSTranslationConfigurationStore(directoryURL: directory)

        try store.saveConfiguration(MobileTranslationConfiguration(engine: .openAICompatible))

        let fileURL = directory.appendingPathComponent("mobile-translation-configuration.json")
        XCTAssertTrue(try isExcludedFromBackup(fileURL))
        XCTAssertTrue(try isExcludedFromBackup(directory))
    }

    func testBackgroundTransferRegistryJSONIsExcludedFromBackup() async throws {
        let directory = temporaryDirectory()
        let registry = try BackgroundTransferRegistry(directoryURL: directory)

        try await registry.record(BackgroundTransferRecord(
            transferIdentifier: "ios.download.task-1",
            taskID: "task-1",
            platform: .iOS,
            backgroundPolicy: MobileBackgroundPolicy(execution: .backgroundTransfer, resumability: .resumable)
        ))

        let fileURL = directory.appendingPathComponent("background-transfers.json")
        XCTAssertTrue(try isExcludedFromBackup(fileURL))
        XCTAssertTrue(try isExcludedFromBackup(directory))
    }

    func testDownloadedMediaArtifactIsExcludedFromBackup() async throws {
        let directory = temporaryDirectory()
        let sourceURL = directory.appendingPathComponent("source.mp4")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("video".utf8).write(to: sourceURL)
        let registry = try BackgroundTransferRegistry(directoryURL: directory.appendingPathComponent("Registry", isDirectory: true))
        let engine = IOSMobileDownloadEngine(
            downloadDirectoryURL: directory.appendingPathComponent("Downloads", isDirectory: true),
            transferRegistry: registry,
            transport: StoragePolicyDownloadTransport(resultFileURL: sourceURL, byteCount: 5)
        )

        let result = try await engine.download(
            MobileDownloadRequest(
                id: "task-1",
                sourceURL: "https://cdn.example.com/video.mp4",
                candidateID: "candidate-1",
                videoID: "video-1",
                formatID: "mp4"
            ),
            progress: { _ in }
        )

        let artifact = try XCTUnwrap(result.primaryArtifact)
        let outputURL = directory.appendingPathComponent("Downloads").appendingPathComponent((artifact.storageIdentifier as NSString).lastPathComponent)

        XCTAssertTrue(try isExcludedFromBackup(directory))
        XCTAssertTrue(try isExcludedFromBackup(outputURL.deletingLastPathComponent()))
        XCTAssertTrue(try isExcludedFromBackup(outputURL))
    }

    func testTranslatedSubtitleArtifactIsExcludedFromBackup() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sourceURL = directory.appendingPathComponent("source.en.srt")
        try """
        1
        00:00:00,000 --> 00:00:01,000
        Hello

        """.write(to: sourceURL, atomically: true, encoding: .utf8)
        let processor = IOSMobileSubtitleProcessor(storageDirectoryURL: directory)

        let artifact = try await processor.process(
            MobileSubtitleProcessingRequest(
                sourceSubtitle: MobileTaskArtifact(
                    id: "source-subtitle",
                    kind: .transcript,
                    displayName: "source.en.srt",
                    storageIdentifier: "source.en.srt"
                ),
                translation: MobileTranslationResult(segments: [
                    MobileTranslationSegment(id: "1", startTime: "", endTime: "", text: "你好")
                ]),
                exportProfile: MobileExportProfile(subtitleMode: .translatedSubtitleFile)
            ),
            progress: { _ in }
        )

        let outputURL = directory.appendingPathComponent(artifact.storageIdentifier)
        XCTAssertTrue(try isExcludedFromBackup(directory))
        XCTAssertTrue(try isExcludedFromBackup(outputURL.deletingLastPathComponent()))
        XCTAssertTrue(try isExcludedFromBackup(outputURL))
    }

    func testRenderedVideoArtifactIsExcludedFromBackup() async throws {
        let directory = temporaryDirectory()
        let mediaURL = directory.appendingPathComponent("Downloads/source.mp4")
        let subtitleURL = directory.appendingPathComponent("Subtitles/source.zh.srt")
        try FileManager.default.createDirectory(at: mediaURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: subtitleURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("source-video".utf8).write(to: mediaURL)
        try "1\n00:00:00,000 --> 00:00:01,000\n你好\n".write(to: subtitleURL, atomically: true, encoding: .utf8)
        let exporter = IOSMobileRenderExporter(storageDirectoryURL: directory, renderer: StoragePolicyVideoRenderer())

        let result = try await exporter.export(
            MobileRenderRequest(
                sourceMedia: MobileTaskArtifact(
                    id: "source-video",
                    kind: .originalMedia,
                    displayName: "source.mp4",
                    storageIdentifier: "Downloads/source.mp4"
                ),
                subtitles: [
                    MobileTaskArtifact(
                        id: "source-subtitle",
                        kind: .translatedSubtitleFile,
                        displayName: "source.zh.srt",
                        storageIdentifier: "Subtitles/source.zh.srt"
                    )
                ],
                exportProfile: MobileExportProfile(subtitleMode: .burnedInSubtitle)
            ),
            progress: { _ in }
        )

        let artifact = try XCTUnwrap(result.primaryArtifact)
        let outputURL = directory.appendingPathComponent(artifact.storageIdentifier)
        XCTAssertTrue(try isExcludedFromBackup(directory))
        XCTAssertTrue(try isExcludedFromBackup(outputURL.deletingLastPathComponent()))
        XCTAssertTrue(try isExcludedFromBackup(outputURL))
    }

    private func isExcludedFromBackup(_ url: URL) throws -> Bool {
        try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("moongate-ios-storage-policy-\(UUID().uuidString)", isDirectory: true)
    }
}

private actor StoragePolicyDownloadTransport: IOSMobileDownloadTransport {
    private let resultFileURL: URL
    private let byteCount: Int?

    init(resultFileURL: URL, byteCount: Int?) {
        self.resultFileURL = resultFileURL
        self.byteCount = byteCount
    }

    func download(
        from url: URL,
        progress: @escaping @Sendable (MobileTaskProgress) -> Void
    ) async throws -> IOSMobileDownloadTransportResult {
        progress(MobileTaskProgress(phase: .downloading, completedUnitCount: byteCount ?? 0, totalUnitCount: byteCount))
        return IOSMobileDownloadTransportResult(temporaryFileURL: resultFileURL, byteCount: byteCount)
    }
}

private struct StoragePolicyVideoRenderer: IOSVideoRendering {
    func render(
        sourceURL: URL,
        subtitleURLs: [URL],
        outputURL: URL,
        maxRenderHeight: Int?,
        progress: @escaping @Sendable (MobileTaskProgress) -> Void
    ) async throws {
        progress(MobileTaskProgress(phase: .exporting, completedUnitCount: 1, totalUnitCount: 1))
        try Data("rendered-video".utf8).write(to: outputURL)
    }
}
