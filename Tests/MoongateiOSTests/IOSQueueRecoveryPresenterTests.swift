import XCTest
@testable import MoongateiOS
import MoongateMobileCore

final class IOSQueueRecoveryPresenterTests: XCTestCase {
    func testPresenterExplainsUserFixableFailureWithRecoveryAction() {
        let task = MobileTaskSnapshot(
            id: "network-task",
            platform: .iOS,
            state: .failed,
            result: MobileTaskResult(artifacts: [
                MobileTaskArtifact(
                    id: "original",
                    kind: .originalMedia,
                    displayName: "Launch Clip.mp4",
                    storageIdentifier: "Downloads/launch.mp4"
                )
            ], primaryArtifactID: "original"),
            error: .networkUnavailable
        )

        let recovery = IOSQueueRecoveryPresenter().presentation(for: task)

        XCTAssertEqual(recovery?.message, "网络不可用，下载没有完成。")
        XCTAssertEqual(recovery?.recoveryHint, "联网后点“重试”。")
        XCTAssertEqual(recovery?.accessibilityHint, "Launch Clip.mp4：网络不可用，下载没有完成。联网后点“重试”。")
        XCTAssertTrue(recovery?.isActionable == true)
    }

    func testPresenterSeparatesSystemBackgroundLimitFromGenericFailure() {
        let task = MobileTaskSnapshot(
            id: "render-task",
            platform: .iOS,
            state: .needsForegroundToContinue,
            progress: MobileTaskProgress(phase: .exporting, completedUnitCount: 1, totalUnitCount: 3),
            result: MobileTaskResult(artifacts: [
                MobileTaskArtifact(
                    id: "original",
                    kind: .originalMedia,
                    displayName: "Render Clip.mp4",
                    storageIdentifier: "Downloads/render.mp4"
                )
            ], primaryArtifactID: "original"),
            error: .systemBackgroundLimit
        )

        let recovery = IOSQueueRecoveryPresenter().presentation(for: task)

        XCTAssertEqual(recovery?.message, "iOS 已暂停后台处理。")
        XCTAssertEqual(recovery?.recoveryHint, "回到前台后重新开始这次导出。")
        XCTAssertEqual(recovery?.systemImage, "iphone")
        XCTAssertFalse(recovery?.isActionable == true)
    }

    func testPresenterExplainsMissingSourceAfterRelaunchWithoutCallingItUnsupported() {
        let task = MobileTaskSnapshot(
            id: "restored-task",
            platform: .iOS,
            state: .failed,
            result: MobileTaskResult(artifacts: [
                MobileTaskArtifact(
                    id: "pending",
                    kind: .metadata,
                    displayName: "Restored Clip",
                    storageIdentifier: "mobile-source:restored-task"
                )
            ], primaryArtifactID: "pending"),
            error: .sourceUnavailableAfterRelaunch
        )

        let recovery = IOSQueueRecoveryPresenter().presentation(for: task)

        XCTAssertEqual(recovery?.message, "出于隐私保护，原链接没有在重启后保留。")
        XCTAssertEqual(recovery?.recoveryHint, "重新添加原链接后再开始下载。")
        XCTAssertEqual(recovery?.systemImage, "link.badge.plus")
        XCTAssertFalse(recovery?.isActionable == true)
        XCTAssertEqual(recovery?.accessibilityHint, "Restored Clip：出于隐私保护，原链接没有在重启后保留。重新添加原链接后再开始下载。")
    }

    func testPresenterReturnsNilForHealthyActiveTask() {
        let task = MobileTaskSnapshot(
            id: "active",
            platform: .iOS,
            state: .downloading,
            progress: MobileTaskProgress(phase: .downloading, completedUnitCount: 1, totalUnitCount: 10)
        )

        XCTAssertNil(IOSQueueRecoveryPresenter().presentation(for: task))
    }
}
