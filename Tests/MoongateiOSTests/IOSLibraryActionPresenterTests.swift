import XCTest
@testable import MoongateiOS
import MoongateMobileCore

final class IOSLibraryActionPresenterTests: XCTestCase {
    func testPresenterBuildsShareAndFileExportCommandsFromActionOutcomes() throws {
        let presenter = IOSLibraryActionPresenter()
        let video = MobileTaskArtifact(
            id: "video",
            kind: .renderedVideo,
            displayName: "Launch Clip.mp4",
            storageIdentifier: "Downloads/launch.mp4"
        )
        let subtitle = MobileTaskArtifact(
            id: "subtitle",
            kind: .translatedSubtitleFile,
            displayName: "Launch Clip.zh-Hans.srt",
            storageIdentifier: "Subtitles/launch.zh-Hans.srt"
        )

        let share = MobileLibraryActionOutcome(
            id: "share-outcome",
            action: .share,
            itemID: "item-1",
            itemTitle: "Launch Clip",
            artifacts: [video, subtitle],
            presentation: .shareSheet,
            status: .requiresSystemPresentation,
            statusMessage: "需要打开系统分享面板",
            requiresSystemUI: true
        )

        let command = try presenter.command(for: share)

        XCTAssertEqual(command.id, "share-outcome")
        XCTAssertEqual(command.presentation, .shareSheet)
        XCTAssertEqual(command.intent, .share)
        XCTAssertEqual(command.itemTitle, "Launch Clip")
        XCTAssertEqual(command.artifacts.map(\.storageIdentifier), ["Downloads/launch.mp4", "Subtitles/launch.zh-Hans.srt"])
        XCTAssertEqual(command.systemMessage, "需要打开系统分享面板")
    }

    func testPresenterRejectsUnavailableCompletedAndSecretBearingOutcomes() throws {
        let presenter = IOSLibraryActionPresenter()
        let unavailable = MobileLibraryActionOutcome(
            action: .share,
            itemID: "missing",
            itemTitle: "missing",
            presentation: .unavailable,
            status: .unavailable,
            statusMessage: "未找到记录",
            requiresSystemUI: false
        )
        let completed = MobileLibraryActionOutcome(
            action: .deleteRecord,
            itemID: "item-1",
            itemTitle: "Launch Clip",
            presentation: .confirmationOnly,
            status: .completed,
            statusMessage: "已删除记录 Launch Clip",
            requiresSystemUI: false,
            completedRecordMutation: true
        )
        let secretArtifact = MobileTaskArtifact(
            id: "secret",
            kind: .originalMedia,
            displayName: "signed.mp4",
            storageIdentifier: "source:https://media.example.test/video.mp4?access_token=SECRET_TOKEN"
        )
        let secretOutcome = MobileLibraryActionOutcome(
            action: .saveToFiles,
            itemID: "item-2",
            itemTitle: "Signed Clip",
            artifacts: [secretArtifact],
            presentation: .fileExporter,
            status: .requiresSystemPresentation,
            statusMessage: "需要选择保存位置",
            requiresSystemUI: true
        )

        XCTAssertThrowsError(try presenter.command(for: unavailable)) { error in
            XCTAssertEqual(error as? IOSLibraryActionPresenterError, .unavailable)
        }
        XCTAssertThrowsError(try presenter.command(for: completed)) { error in
            XCTAssertEqual(error as? IOSLibraryActionPresenterError, .noSystemPresentationRequired)
        }
        XCTAssertThrowsError(try presenter.command(for: secretOutcome)) { error in
            XCTAssertEqual(error as? IOSLibraryActionPresenterError, .unsafeArtifactReference)
        }
    }
}
