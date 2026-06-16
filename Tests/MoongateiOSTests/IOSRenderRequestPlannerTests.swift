@testable import MoongateMobileCore
@testable import MoongateiOS
import XCTest

final class IOSRenderRequestPlannerTests: XCTestCase {
    func testTranslatedSubtitleFileUsesSubtitleProcessorWithoutRender() {
        let planner = IOSRenderRequestPlanner(
            capabilities: MobileProcessingCapabilities(
                platform: .iOS,
                supportedCapabilities: [.translation, .subtitleExport]
            )
        )

        let plan = planner.plan(renderRequest(subtitleMode: .translatedSubtitleFile))

        XCTAssertEqual(plan.kind, .subtitleFileOnly)
        XCTAssertEqual(plan.outputArtifactKind, .translatedSubtitleFile)
        XCTAssertFalse(plan.requiresRenderExporter)
        XCTAssertEqual(plan.backgroundPolicy.execution, .foregroundRequired)
        XCTAssertTrue(plan.backgroundPolicy.limits.contains(.foregroundRequired))
        XCTAssertNil(plan.blockedReason)
    }

    func testTranslatedSubtitleFileWithoutSubtitleCapabilitiesIsBlocked() {
        let planner = IOSRenderRequestPlanner(
            capabilities: MobileProcessingCapabilities(
                platform: .iOS,
                supportedCapabilities: [.download]
            )
        )

        let plan = planner.plan(renderRequest(subtitleMode: .translatedSubtitleFile))

        XCTAssertEqual(plan.kind, .subtitleFileOnly)
        XCTAssertEqual(plan.backgroundPolicy.execution, .foregroundRequired)
        XCTAssertEqual(plan.backgroundPolicy.resumability, .nonResumable)
        XCTAssertEqual(plan.blockedReason, .capabilityUnavailable)
    }

    func testSoftSubtitleCreatesForegroundPackagePlan() {
        let planner = IOSRenderRequestPlanner(
            capabilities: MobileProcessingCapabilities(
                platform: .iOS,
                supportedCapabilities: [.subtitleExport]
            )
        )

        let plan = planner.plan(renderRequest(subtitleMode: .softSubtitle))

        XCTAssertEqual(plan.kind, .softSubtitlePackage)
        XCTAssertEqual(plan.outputArtifactKind, .softSubtitle)
        XCTAssertFalse(plan.requiresRenderExporter)
        XCTAssertEqual(plan.backgroundPolicy.execution, .foregroundRequired)
        XCTAssertEqual(plan.backgroundPolicy.resumability, .resumable)
        XCTAssertTrue(plan.backgroundPolicy.limits.contains(.foregroundRequired))
        XCTAssertFalse(plan.backgroundPolicy.limits.contains(.notResumable))
        XCTAssertFalse(plan.backgroundPolicy.allowsUnboundedBackgroundExecution)
        XCTAssertNil(plan.blockedReason)
    }

    func testSoftSubtitleWithoutSubtitleExportCapabilityIsBlockedBeforePackaging() {
        let planner = IOSRenderRequestPlanner(
            capabilities: MobileProcessingCapabilities(
                platform: .iOS,
                supportedCapabilities: [.download]
            )
        )

        let plan = planner.plan(renderRequest(subtitleMode: .softSubtitle))

        XCTAssertEqual(plan.kind, .softSubtitlePackage)
        XCTAssertEqual(plan.backgroundPolicy.execution, .foregroundRequired)
        XCTAssertEqual(plan.backgroundPolicy.resumability, .nonResumable)
        XCTAssertEqual(plan.blockedReason, .capabilityUnavailable)
    }

    func testBurnedInSubtitleWithoutRendererNeedsForegroundAndReportsMissingCapability() {
        let planner = IOSRenderRequestPlanner(
            capabilities: MobileProcessingCapabilities(
                platform: .iOS,
                supportedCapabilities: [.subtitleExport]
            )
        )

        let plan = planner.plan(renderRequest(subtitleMode: .burnedInSubtitle))

        XCTAssertEqual(plan.kind, .burnedInRender)
        XCTAssertEqual(plan.outputArtifactKind, .renderedVideo)
        XCTAssertTrue(plan.requiresRenderExporter)
        XCTAssertEqual(plan.backgroundPolicy.execution, .foregroundRequired)
        XCTAssertEqual(plan.backgroundPolicy.resumability, .nonResumable)
        XCTAssertTrue(plan.backgroundPolicy.limits.contains(.foregroundRequired))
        XCTAssertTrue(plan.backgroundPolicy.limits.contains(.notResumable))
        XCTAssertEqual(plan.blockedReason, .rendererUnavailable)
    }

    func testBurnedInSubtitleUsesContinuedProcessingWhenRuntimeAndCheckpointingAreAvailable() {
        let planner = IOSRenderRequestPlanner(
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
        )

        let plan = planner.plan(renderRequest(subtitleMode: .burnedInSubtitle, maxRenderHeight: 720))

        XCTAssertEqual(plan.kind, .burnedInRender)
        XCTAssertEqual(plan.outputArtifactKind, .renderedVideo)
        XCTAssertTrue(plan.requiresRenderExporter)
        XCTAssertEqual(plan.backgroundPolicy.execution, .continuedProcessing)
        XCTAssertEqual(plan.backgroundPolicy.resumability, .resumable)
        XCTAssertEqual(plan.backgroundPolicy.systemTimeLimitSeconds, 600)
        XCTAssertTrue(plan.backgroundPolicy.limits.contains(.systemTimeLimit))
        XCTAssertTrue(plan.backgroundPolicy.limits.contains(.userVisibleNotificationRequired))
        XCTAssertFalse(plan.backgroundPolicy.allowsUnboundedBackgroundExecution)
        XCTAssertNil(plan.blockedReason)
    }

    func testBurnedInSubtitleFallsBackToForegroundWhenRuntimeContinuedProcessingIsUnavailable() {
        let planner = IOSRenderRequestPlanner(
            capabilities: MobileProcessingCapabilities(
                platform: .iOS,
                supportedCapabilities: [.subtitleExport, .videoRender, .backgroundRender],
                maxRenderHeight: 1080
            ),
            runtime: IOSRenderRuntimeCapabilities(
                supportsContinuedProcessing: false,
                supportsCheckpointedRender: true,
                continuedProcessingTimeLimitSeconds: 600
            )
        )

        let plan = planner.plan(renderRequest(subtitleMode: .burnedInSubtitle, maxRenderHeight: 720))

        XCTAssertEqual(plan.kind, .burnedInRender)
        XCTAssertEqual(plan.backgroundPolicy.execution, .foregroundRequired)
        XCTAssertEqual(plan.backgroundPolicy.resumability, .nonResumable)
        XCTAssertTrue(plan.backgroundPolicy.limits.contains(.foregroundRequired))
        XCTAssertTrue(plan.backgroundPolicy.limits.contains(.notResumable))
        XCTAssertNil(plan.blockedReason)
    }

    func testBurnedInSubtitleContinuedProcessingWithoutCheckpointingIsNonResumable() {
        let planner = IOSRenderRequestPlanner(
            capabilities: MobileProcessingCapabilities(
                platform: .iOS,
                supportedCapabilities: [.subtitleExport, .videoRender, .backgroundRender],
                maxRenderHeight: 1080
            ),
            runtime: IOSRenderRuntimeCapabilities(
                supportsContinuedProcessing: true,
                supportsCheckpointedRender: false,
                continuedProcessingTimeLimitSeconds: 600
            )
        )

        let plan = planner.plan(renderRequest(subtitleMode: .burnedInSubtitle, maxRenderHeight: 720))

        XCTAssertEqual(plan.backgroundPolicy.execution, .continuedProcessing)
        XCTAssertEqual(plan.backgroundPolicy.resumability, .nonResumable)
        XCTAssertTrue(plan.backgroundPolicy.limits.contains(.systemTimeLimit))
        XCTAssertTrue(plan.backgroundPolicy.limits.contains(.userVisibleNotificationRequired))
        XCTAssertTrue(plan.backgroundPolicy.limits.contains(.notResumable))
    }

    func testBurnedInSubtitleAboveDeviceHeightIsBlockedBeforePlanningBackgroundWork() {
        let planner = IOSRenderRequestPlanner(
            capabilities: MobileProcessingCapabilities(
                platform: .iOS,
                supportedCapabilities: [.videoRender, .backgroundRender],
                maxRenderHeight: 720
            ),
            runtime: IOSRenderRuntimeCapabilities(
                supportsContinuedProcessing: true,
                supportsCheckpointedRender: true,
                continuedProcessingTimeLimitSeconds: 600
            )
        )

        let plan = planner.plan(renderRequest(subtitleMode: .burnedInSubtitle, maxRenderHeight: 1080))

        XCTAssertEqual(plan.kind, .burnedInRender)
        XCTAssertEqual(plan.backgroundPolicy.execution, .foregroundRequired)
        XCTAssertEqual(plan.backgroundPolicy.resumability, .nonResumable)
        XCTAssertEqual(plan.blockedReason, .renderHeightUnsupported)
    }

    private func renderRequest(
        subtitleMode: MobileExportProfile.SubtitleMode,
        maxRenderHeight: Int? = 1080
    ) -> MobileRenderRequest {
        MobileRenderRequest(
            sourceMedia: MobileTaskArtifact(
                id: "source-video",
                kind: .originalMedia,
                displayName: "source.mp4",
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
            exportProfile: MobileExportProfile(
                subtitleMode: subtitleMode,
                maxRenderHeight: maxRenderHeight
            )
        )
    }
}
