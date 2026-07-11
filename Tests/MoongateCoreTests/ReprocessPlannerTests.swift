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

    func testASROrSubtitleSourcePlansTranscriptionAndNecessaryDownstreamSteps() {
        let asrPlan = ReprocessPlanner.plan(for: .init(
            sourceVersionID: sourceVersionID,
            changedFields: [.transcriptionModel],
            needsTranslation: true,
            needsBurn: true
        ))
        let sourcePlan = ReprocessPlanner.plan(for: .init(
            sourceVersionID: sourceVersionID,
            changedFields: [.subtitleSource],
            needsTranslation: true,
            needsBurn: true
        ))

        XCTAssertEqual(asrPlan.steps, [.transcribe, .translate, .burn])
        XCTAssertEqual(sourcePlan.steps, [.transcribe, .translate, .burn])
    }

    func testFormatOrQualityPlansTranscodeThenBurn() {
        let formatPlan = ReprocessPlanner.plan(for: .init(
            sourceVersionID: sourceVersionID,
            changedFields: [.outputFormat],
            needsTranslation: false,
            needsBurn: true
        ))
        let qualityPlan = ReprocessPlanner.plan(for: .init(
            sourceVersionID: sourceVersionID,
            changedFields: [.quality],
            needsTranslation: false,
            needsBurn: true
        ))

        XCTAssertEqual(formatPlan.steps, [.transcode, .burn])
        XCTAssertEqual(qualityPlan.steps, [.transcode, .burn])
    }
}
