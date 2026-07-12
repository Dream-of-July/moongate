import XCTest
@testable import MoongateCore

final class ReprocessPlannerTests: XCTestCase {
    private let sourceVersionID = UUID()

    func testSubtitleStyleOnlyPlansBurnForNewVersion() {
        let plan = ReprocessPlanner.plan(for: .init(
            sourceVersionID: sourceVersionID,
            changedFields: [.subtitleStyle],
            needsTranslation: true,
            needsBurn: true
        ))

        XCTAssertEqual(plan.steps, [.burn])
        XCTAssertNotEqual(plan.outputVersionID, sourceVersionID)
        XCTAssertTrue(plan.createsNewVersion)
    }

    func testTranslationLanguageOrModelPlansTranslationAndDownstreamBurn() {
        let languagePlan = ReprocessPlanner.plan(for: .init(
            sourceVersionID: sourceVersionID,
            changedFields: [.targetLanguage],
            needsTranslation: true,
            needsBurn: true
        ))
        let modelPlan = ReprocessPlanner.plan(for: .init(
            sourceVersionID: sourceVersionID,
            changedFields: [.translationModel],
            needsTranslation: true,
            needsBurn: true
        ))

        XCTAssertEqual(languagePlan.steps, [.translate, .burn])
        XCTAssertEqual(modelPlan.steps, [.translate, .burn])
    }

    func testNewTranslationAndSubtitleStyleUseEditedDraftForPlan() {
        let request = ReprocessRequest(
            sourceVersionID: sourceVersionID,
            changedFields: [.targetLanguage, .subtitleStyle],
            configuration: LibraryProcessingConfiguration(
                targetLanguage: "zh-Hans",
                subtitleStyle: "bilingual"
            )
        )

        XCTAssertTrue(request.needsTranslation)
        XCTAssertTrue(request.needsBurn)
        XCTAssertEqual(ReprocessPlanner.plan(for: request).steps, [.translate, .burn])
    }

    func testSRTOnlyModeDoesNotBurnWhenOnlySubtitleStyleChanges() {
        let request = ReprocessRequest(
            sourceVersionID: sourceVersionID,
            changedFields: [.subtitleStyle],
            configuration: LibraryProcessingConfiguration(
                subtitleMode: "srtOnly",
                subtitleStyle: "bilingual"
            )
        )

        XCTAssertFalse(request.needsBurn)
        XCTAssertEqual(ReprocessPlanner.plan(for: request).steps, [])
    }

    func testRemovingBurnedSubtitlesRefreshesVideoInsteadOfReusingRenderedOutput() {
        let request = ReprocessRequest(
            sourceVersionID: sourceVersionID,
            changedFields: [.subtitleMode],
            configuration: LibraryProcessingConfiguration(subtitleMode: "off"),
            previousConfiguration: LibraryProcessingConfiguration(subtitleMode: "burnIn")
        )

        XCTAssertEqual(ReprocessPlanner.plan(for: request).steps, [.refreshVideo])
    }

    func testASRModelPlansTranscriptionAndNecessaryDownstreamSteps() {
        let asrPlan = ReprocessPlanner.plan(for: .init(
            sourceVersionID: sourceVersionID,
            changedFields: [.transcriptionModel],
            needsTranslation: true,
            needsBurn: true
        ))

        XCTAssertEqual(asrPlan.steps, [.transcribe, .translate, .burn])
    }

    func testSubtitleSourceUsesASROnlyForASRSources() {
        let localASR = ReprocessPlanner.plan(for: .init(
            sourceVersionID: sourceVersionID,
            changedFields: [.subtitleSource],
            configuration: LibraryProcessingConfiguration(
                subtitleSource: SubtitleSourceKind.localASR.rawValue,
                targetLanguage: "zh-Hans"
            )
        ))
        let cloudASR = ReprocessPlanner.plan(for: .init(
            sourceVersionID: sourceVersionID,
            changedFields: [.subtitleSource],
            configuration: LibraryProcessingConfiguration(
                subtitleSource: SubtitleSourceKind.cloudASR.rawValue,
                targetLanguage: "zh-Hans"
            )
        ))
        let manual = ReprocessPlanner.plan(for: .init(
            sourceVersionID: sourceVersionID,
            changedFields: [.subtitleSource],
            configuration: LibraryProcessingConfiguration(
                subtitleSource: SubtitleSourceKind.manual.rawValue,
                targetLanguage: "zh-Hans"
            )
        ))

        XCTAssertEqual(localASR.steps, [.transcribe, .translate])
        XCTAssertEqual(cloudASR.steps, [.transcribe, .translate])
        XCTAssertEqual(manual.steps, [.translate])
    }

    func testOutputFormatUsesLocalTranscodeButOriginalRefreshesSource() {
        let formatPlan = ReprocessPlanner.plan(for: .init(
            sourceVersionID: sourceVersionID,
            changedFields: [.outputFormat],
            configuration: LibraryProcessingConfiguration(outputFormat: OutputFormat.mp4H264.rawValue)
        ))
        let originalPlan = ReprocessPlanner.plan(for: .init(
            sourceVersionID: sourceVersionID,
            changedFields: [.outputFormat],
            configuration: LibraryProcessingConfiguration(outputFormat: OutputFormat.original.rawValue)
        ))
        let qualityPlan = ReprocessPlanner.plan(for: .init(
            sourceVersionID: sourceVersionID,
            changedFields: [.quality],
            configuration: LibraryProcessingConfiguration(quality: "best")
        ))

        XCTAssertEqual(formatPlan.steps, [.transcode])
        XCTAssertEqual(originalPlan.steps, [.refreshVideo])
        XCTAssertEqual(qualityPlan.steps, [.refreshVideo])
    }

    func testDefaultOutputFormatRefreshesSourceInsteadOfCopyingAnOldTranscode() {
        let plan = ReprocessPlanner.plan(for: .init(
            sourceVersionID: sourceVersionID,
            changedFields: [.outputFormat],
            configuration: LibraryProcessingConfiguration(outputFormat: nil)
        ))

        XCTAssertEqual(plan.steps, [.refreshVideo])
    }

    func testQualityRefreshRetainsRequestedOutputConversion() {
        let plan = ReprocessPlanner.plan(for: .init(
            sourceVersionID: sourceVersionID,
            changedFields: [.quality],
            configuration: LibraryProcessingConfiguration(
                outputFormat: OutputFormat.mp4H264.rawValue,
                quality: "best"
            )
        ))

        XCTAssertEqual(plan.steps, [.refreshVideo, .transcode])
    }

    func testPlanKeepsExplicitOutputVersionIdentity() {
        let outputVersionID = UUID()
        let plan = ReprocessPlan(
            sourceVersionID: sourceVersionID,
            outputVersionID: outputVersionID,
            steps: [.transcode]
        )

        XCTAssertEqual(plan.outputVersionID, outputVersionID)
    }
}
