import XCTest
@testable import MoongateiOS
import MoongateMobileCore

final class IOSPhotoLibraryExporterTests: XCTestCase {
    func testPhotoSaveHandlerResolvesAppOwnedVideoAndUpdatesStatus() async throws {
        let storageDirectory = temporaryDirectory()
        let downloadsDirectory = storageDirectory.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        let videoURL = downloadsDirectory.appendingPathComponent("clip.mp4", isDirectory: false)
        try Data("video".utf8).write(to: videoURL)
        let artifact = MobileTaskArtifact(
            id: "video",
            kind: .renderedVideo,
            displayName: "clip.mp4",
            storageIdentifier: "downloads/clip.mp4"
        )
        let command = IOSLibraryActionCommand(
            id: "photos-command",
            intent: .saveToPhotos,
            presentation: .photoLibraryExporter,
            itemID: "item-1",
            itemTitle: "Clip",
            artifacts: [artifact],
            systemMessage: "需要授权保存到照片"
        )
        let exporter = RecordingPhotoLibraryExporter(result: .saved)
        let handler = IOSPhotoLibrarySaveHandler(
            artifactStore: IOSArtifactStore(storageDirectoryURL: storageDirectory),
            exporter: exporter
        )

        let status = await handler.save(command)

        let savedURLs = await exporter.savedURLs()
        XCTAssertEqual(savedURLs, [videoURL.standardizedFileURL])
        XCTAssertEqual(status, "已存到照片 clip.mp4")
    }

    func testPhotoSaveHandlerReportsPermissionAndUnsafeReferencesWithoutLeakingPaths() async {
        let storageDirectory = URL(fileURLWithPath: "/tmp/moongate-mobile-store", isDirectory: true)
        let unsafeArtifact = MobileTaskArtifact(
            id: "unsafe",
            kind: .originalMedia,
            displayName: "signed.mp4",
            storageIdentifier: "source:https://media.example.test/video.mp4?access_token=SECRET_TOKEN"
        )
        let deniedCommand = IOSLibraryActionCommand(
            id: "denied",
            intent: .saveToPhotos,
            presentation: .photoLibraryExporter,
            itemID: "item-1",
            itemTitle: "Signed",
            artifacts: [unsafeArtifact],
            systemMessage: "需要授权保存到照片"
        )
        let deniedHandler = IOSPhotoLibrarySaveHandler(
            artifactStore: IOSArtifactStore(storageDirectoryURL: storageDirectory),
            exporter: RecordingPhotoLibraryExporter(result: .permissionDenied)
        )

        let unsafeStatus = await deniedHandler.save(deniedCommand)

        XCTAssertEqual(unsafeStatus, "文件引用不安全，无法存到照片")
        XCTAssertFalse(unsafeStatus.contains("SECRET_TOKEN"))

        let safeArtifact = MobileTaskArtifact(
            id: "video",
            kind: .originalMedia,
            displayName: "clip.mp4",
            storageIdentifier: "downloads/clip.mp4"
        )
        let safeCommand = IOSLibraryActionCommand(
            id: "safe",
            intent: .saveToPhotos,
            presentation: .photoLibraryExporter,
            itemID: "item-2",
            itemTitle: "Clip",
            artifacts: [safeArtifact],
            systemMessage: "需要授权保存到照片"
        )
        let permissionDeniedHandler = IOSPhotoLibrarySaveHandler(
            artifactStore: IOSArtifactStore(storageDirectoryURL: storageDirectory),
            exporter: RecordingPhotoLibraryExporter(result: .permissionDenied)
        )

        let deniedStatus = await permissionDeniedHandler.save(safeCommand)

        XCTAssertEqual(deniedStatus, "没有照片写入权限，请在系统设置中允许访问照片。")
    }

    func testPhotoSaveHandlerReportsSaveFailureWithoutLeakingFilePath() async {
        let storageDirectory = URL(fileURLWithPath: "/tmp/moongate-mobile-store", isDirectory: true)
        let artifact = MobileTaskArtifact(
            id: "video",
            kind: .renderedVideo,
            displayName: "clip.mp4",
            storageIdentifier: "downloads/clip.mp4"
        )
        let command = IOSLibraryActionCommand(
            id: "failed",
            intent: .saveToPhotos,
            presentation: .photoLibraryExporter,
            itemID: "item-1",
            itemTitle: "Clip",
            artifacts: [artifact],
            systemMessage: "需要授权保存到照片"
        )
        let handler = IOSPhotoLibrarySaveHandler(
            artifactStore: IOSArtifactStore(storageDirectoryURL: storageDirectory),
            exporter: RecordingPhotoLibraryExporter(result: .failed)
        )

        let status = await handler.save(command)

        XCTAssertEqual(status, "存到照片失败，请稍后重试。")
        XCTAssertFalse(status.contains(storageDirectory.path))
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}

private actor RecordingPhotoLibraryExporter: IOSPhotoLibraryExporting {
    private let result: IOSPhotoLibrarySaveResult
    private var urls: [URL] = []

    init(result: IOSPhotoLibrarySaveResult) {
        self.result = result
    }

    func saveVideo(at fileURL: URL) async -> IOSPhotoLibrarySaveResult {
        urls.append(fileURL.standardizedFileURL)
        return result
    }

    func savedURLs() -> [URL] {
        urls
    }
}
