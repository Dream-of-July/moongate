@testable import MoongateMobileCore
@testable import MoongateiOS
import Foundation
import XCTest

final class IOSMobileSubtitleProcessorTests: XCTestCase {
    func testWritesTranslatedSRTArtifactIntoAppStorage() async throws {
        let directory = temporaryDirectory()
        let sourceURL = directory.appendingPathComponent("source.en.srt")
        try """
        1
        00:00:00,000 --> 00:00:01,500
        Hello

        2
        00:00:01,500 --> 00:00:03,000
        world.

        """.write(to: sourceURL, atomically: true, encoding: .utf8)
        let processor = IOSMobileSubtitleProcessor(storageDirectoryURL: directory)
        let progress = SubtitleProgressRecorder()

        let artifact = try await processor.process(
            MobileSubtitleProcessingRequest(
                sourceSubtitle: MobileTaskArtifact(
                    id: "source-subtitle",
                    kind: .transcript,
                    displayName: "source.en.srt",
                    storageIdentifier: "source.en.srt"
                ),
                translation: MobileTranslationResult(segments: [
                    MobileTranslationSegment(id: "1", startTime: "", endTime: "", text: "你好"),
                    MobileTranslationSegment(id: "2", startTime: "", endTime: "", text: "世界。")
                ]),
                exportProfile: MobileExportProfile(subtitleMode: .translatedSubtitleFile)
            ),
            progress: { progress.record($0) }
        )

        XCTAssertEqual(artifact.kind, .translatedSubtitleFile)
        XCTAssertEqual(artifact.displayName, "source.en.zh.srt")
        XCTAssertEqual(artifact.storageIdentifier, "Subtitles/source.en.zh.srt")
        let outputURL = directory.appendingPathComponent("Subtitles/source.en.zh.srt")
        XCTAssertEqual(try String(contentsOf: outputURL, encoding: .utf8), """
        1
        00:00:00,000 --> 00:00:01,500
        你好

        2
        00:00:01,500 --> 00:00:03,000
        世界。

        """)
        XCTAssertEqual(progress.snapshots().last, MobileTaskProgress(phase: .translating, completedUnitCount: 2, totalUnitCount: 2))
    }

    func testWritesSoftSubtitlePackageWithManifestIntoAppStorage() async throws {
        let directory = temporaryDirectory()
        let sourceURL = directory.appendingPathComponent("source.en.srt")
        try """
        1
        00:00:00,000 --> 00:00:01,500
        Hello

        """.write(to: sourceURL, atomically: true, encoding: .utf8)
        let processor = IOSMobileSubtitleProcessor(storageDirectoryURL: directory)
        let progress = SubtitleProgressRecorder()

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
                exportProfile: MobileExportProfile(subtitleMode: .softSubtitle)
            ),
            progress: { progress.record($0) }
        )

        XCTAssertEqual(artifact.kind, .softSubtitle)
        XCTAssertEqual(artifact.displayName, "source.en.soft-subtitles")
        XCTAssertEqual(artifact.storageIdentifier, "SoftSubtitles/source.en.soft-subtitles")

        let packageURL = directory.appendingPathComponent(artifact.storageIdentifier, isDirectory: true)
        var isDirectory = ObjCBool(false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertEqual(try String(contentsOf: packageURL.appendingPathComponent("subtitles.zh-Hans.srt"), encoding: .utf8), """
        1
        00:00:00,000 --> 00:00:01,500
        你好

        """)
        let manifest = try String(contentsOf: packageURL.appendingPathComponent("manifest.json"), encoding: .utf8)
        XCTAssertTrue(manifest.contains("\"kind\":\"softSubtitle\""))
        XCTAssertTrue(manifest.contains("\"subtitle\":\"subtitles.zh-Hans.srt\""))
        XCTAssertEqual(progress.snapshots().last, MobileTaskProgress(phase: .translating, completedUnitCount: 1, totalUnitCount: 1))
    }

    func testReadsSourceSubtitleFromAppOwnedSubdirectoryIdentifier() async throws {
        let directory = temporaryDirectory()
        let subtitleDirectory = directory.appendingPathComponent("Subtitles", isDirectory: true)
        try FileManager.default.createDirectory(at: subtitleDirectory, withIntermediateDirectories: true)
        try """
        1
        00:00:00,000 --> 00:00:01,000
        Hello from a sidecar.

        """.write(
            to: subtitleDirectory.appendingPathComponent("source.en.srt", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let processor = IOSMobileSubtitleProcessor(storageDirectoryURL: directory)

        let artifact = try await processor.process(
            MobileSubtitleProcessingRequest(
                sourceSubtitle: MobileTaskArtifact(
                    id: "source-subtitle",
                    kind: .transcript,
                    displayName: "source.en.srt",
                    storageIdentifier: "Subtitles/source.en.srt"
                ),
                translation: MobileTranslationResult(segments: [
                    MobileTranslationSegment(id: "1", startTime: "", endTime: "", text: "来自本地字幕。")
                ]),
                exportProfile: MobileExportProfile(subtitleMode: .translatedSubtitleFile)
            ),
            progress: { _ in }
        )

        XCTAssertEqual(artifact.storageIdentifier, "Subtitles/source.en.zh.srt")
        let outputURL = directory.appendingPathComponent(artifact.storageIdentifier)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testWritesCleanedRollingSubtitleTranslationTimelineAndAvoidsNameCollision() async throws {
        let directory = temporaryDirectory()
        let sourceURL = directory.appendingPathComponent("rolling.en.srt")
        try """
        1
        00:00:00,000 --> 00:00:02,000
        Hello

        2
        00:00:01,500 --> 00:00:03,000
        Hello
        world.

        3
        00:00:03,000 --> 00:00:04,000
        Next

        4
        00:00:04,000 --> 00:00:05,000
        Next
        line.

        """.write(to: sourceURL, atomically: true, encoding: .utf8)
        let existingOutput = directory
            .appendingPathComponent("Subtitles", isDirectory: true)
            .appendingPathComponent("rolling.en.zh.srt", isDirectory: false)
        try FileManager.default.createDirectory(at: existingOutput.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "existing".write(to: existingOutput, atomically: true, encoding: .utf8)
        let processor = IOSMobileSubtitleProcessor(storageDirectoryURL: directory)

        let artifact = try await processor.process(
            MobileSubtitleProcessingRequest(
                sourceSubtitle: MobileTaskArtifact(
                    id: "rolling-subtitle",
                    kind: .transcript,
                    displayName: "rolling.en.srt",
                    storageIdentifier: "rolling.en.srt"
                ),
                translation: MobileTranslationResult(segments: [
                    MobileTranslationSegment(id: "1", startTime: "", endTime: "", text: "你好，世界。"),
                    MobileTranslationSegment(id: "2", startTime: "", endTime: "", text: "下一句。")
                ]),
                exportProfile: MobileExportProfile(subtitleMode: .translatedSubtitleFile)
            ),
            progress: { _ in }
        )

        XCTAssertEqual(artifact.displayName, "rolling.en-1.zh.srt")
        XCTAssertEqual(try String(contentsOf: existingOutput, encoding: .utf8), "existing")
        let outputURL = directory.appendingPathComponent(artifact.storageIdentifier)
        XCTAssertEqual(try String(contentsOf: outputURL, encoding: .utf8), """
        1
        00:00:00,000 --> 00:00:03,000
        你好，世界。

        2
        00:00:03,000 --> 00:00:05,000
        下一句。

        """)
    }

    func testRejectsSubtitleStorageIdentifierEscapingAppStorage() async throws {
        let directory = temporaryDirectory()
        let processor = IOSMobileSubtitleProcessor(storageDirectoryURL: directory)

        do {
            _ = try await processor.process(
                MobileSubtitleProcessingRequest(
                    sourceSubtitle: MobileTaskArtifact(
                        id: "source-subtitle",
                        kind: .transcript,
                        displayName: "source.en.srt",
                        storageIdentifier: "../source.en.srt"
                    ),
                    translation: MobileTranslationResult(segments: []),
                    exportProfile: MobileExportProfile(subtitleMode: .translatedSubtitleFile)
                ),
                progress: { _ in }
            )
            XCTFail("Escaping storage identifiers must not be accepted.")
        } catch let error as IOSMobileSubtitleProcessor.SubtitleProcessingError {
            XCTAssertEqual(error, .unsafeStorageIdentifier)
        }
    }

    func testRejectsSourceReferenceIdentifierEvenWhenMatchingFileExists() async throws {
        let directory = temporaryDirectory()
        try """
        1
        00:00:00,000 --> 00:00:01,000
        Do not read this source reference.

        """.write(
            to: directory.appendingPathComponent("source:stored-source", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let processor = IOSMobileSubtitleProcessor(storageDirectoryURL: directory)

        do {
            _ = try await processor.process(
                MobileSubtitleProcessingRequest(
                    sourceSubtitle: MobileTaskArtifact(
                        id: "source-subtitle",
                        kind: .transcript,
                        displayName: "source.en.srt",
                        storageIdentifier: "source:stored-source"
                    ),
                    translation: MobileTranslationResult(segments: [
                        MobileTranslationSegment(id: "1", startTime: "", endTime: "", text: "不应生成")
                    ]),
                    exportProfile: MobileExportProfile(subtitleMode: .translatedSubtitleFile)
                ),
                progress: { _ in }
            )
            XCTFail("Source-reference storage identifiers must not be read as app-owned subtitle files.")
        } catch let error as IOSMobileSubtitleProcessor.SubtitleProcessingError {
            XCTAssertEqual(error, .unsafeStorageIdentifier)
        }
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("moongate-ios-subtitle-processor-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private final class SubtitleProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [MobileTaskProgress] = []

    func record(_ progress: MobileTaskProgress) {
        lock.lock()
        values.append(progress)
        lock.unlock()
    }

    func snapshots() -> [MobileTaskProgress] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}
