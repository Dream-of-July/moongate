@testable import MoongateMobileCore
@testable import MoongateiOS
import XCTest

final class IOSContinuedProcessingRenderSchedulerTests: XCTestCase {
    func testBuildsUserVisibleContinuedProcessingRequestOnlyForEligibleRenderPlan() throws {
        let scheduler = IOSContinuedProcessingRenderScheduler(bundleIdentifier: "com.local.videodownloader.ios")
        let plan = IOSRenderRequestPlanner(
            capabilities: MobileProcessingCapabilities(
                platform: .iOS,
                supportedCapabilities: [.subtitleExport, .videoRender, .backgroundRender],
                maxRenderHeight: 1080
            ),
            runtime: IOSRenderRuntimeCapabilities(
                supportsContinuedProcessing: true,
                supportsCheckpointedRender: true,
                continuedProcessingTimeLimitSeconds: 600
            )
        ).plan(renderRequest(displayName: "Launch Clip.mp4"))

        let request = try scheduler.makeRequestDescriptor(for: plan, taskID: "task-123")

        XCTAssertEqual(request.identifier, "com.local.videodownloader.ios.render.task-123")
        XCTAssertEqual(request.title, "导出视频")
        XCTAssertEqual(request.subtitle, "Launch Clip.mp4")
        XCTAssertEqual(request.strategy, .queue)
        XCTAssertEqual(request.requiredResources, .default)
        XCTAssertEqual(request.backgroundPolicy.execution, .continuedProcessing)
        XCTAssertTrue(request.backgroundPolicy.limits.contains(.userVisibleNotificationRequired))
        XCTAssertFalse(request.backgroundPolicy.allowsUnboundedBackgroundExecution)
    }

    func testRejectsForegroundRenderPlanBeforeCreatingContinuedProcessingRequest() throws {
        let scheduler = IOSContinuedProcessingRenderScheduler(bundleIdentifier: "com.local.videodownloader.ios")
        let plan = IOSRenderRequestPlanner(
            capabilities: MobileProcessingCapabilities(
                platform: .iOS,
                supportedCapabilities: [.subtitleExport, .videoRender],
                maxRenderHeight: 1080
            ),
            runtime: IOSRenderRuntimeCapabilities(
                supportsContinuedProcessing: false,
                supportsCheckpointedRender: true
            )
        ).plan(renderRequest(displayName: "Foreground Clip.mp4"))

        XCTAssertThrowsError(try scheduler.makeRequestDescriptor(for: plan, taskID: "task-foreground")) { error in
            XCTAssertEqual(error as? IOSContinuedProcessingRenderScheduler.ScheduleError, .continuedProcessingUnavailable)
        }
    }

    func testEncodesUnsafeTaskIDReversiblyForSchedulerIdentifier() throws {
        let scheduler = IOSContinuedProcessingRenderScheduler(bundleIdentifier: "com.local.videodownloader.ios")
        let plan = IOSRenderRequestPlanner(
            capabilities: MobileProcessingCapabilities(
                platform: .iOS,
                supportedCapabilities: [.subtitleExport, .videoRender, .backgroundRender],
                maxRenderHeight: 1080
            ),
            runtime: IOSRenderRuntimeCapabilities(
                supportsContinuedProcessing: true,
                supportsCheckpointedRender: false,
                continuedProcessingTimeLimitSeconds: 300
            )
        ).plan(renderRequest(displayName: "Unsafe ID.mp4"))

        let request = try scheduler.makeRequestDescriptor(for: plan, taskID: "../task with spaces")

        XCTAssertEqual(request.identifier, "com.local.videodownloader.ios.render.encoded-hex-2e2e2f7461736b207769746820737061636573")
        XCTAssertEqual(request.backgroundPolicy.resumability, .nonResumable)
        XCTAssertTrue(request.backgroundPolicy.limits.contains(.notResumable))
    }

    private func renderRequest(displayName: String) -> MobileRenderRequest {
        MobileRenderRequest(
            sourceMedia: MobileTaskArtifact(
                id: "source-video",
                kind: .originalMedia,
                displayName: displayName,
                storageIdentifier: "Downloads/source.mp4"
            ),
            subtitles: [
                MobileTaskArtifact(
                    id: "subtitle",
                    kind: .translatedSubtitleFile,
                    displayName: "source.zh.srt",
                    storageIdentifier: "Subtitles/source.zh.srt"
                )
            ],
            exportProfile: MobileExportProfile(subtitleMode: .burnedInSubtitle, maxRenderHeight: 720)
        )
    }
}
