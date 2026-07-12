import XCTest
@testable import Moongate
@testable import MoongateCore

final class DownloadOptionsDraftTests: XCTestCase {
    func testOriginalSubtitleOutcomeHidesTranslationAndRecognitionChoices() {
        var draft = DownloadOptionsDraft.defaults(from: AppSettings())
        draft.subtitleOutcome = .original

        XCTAssertFalse(draft.showsTranslationOptions)
        XCTAssertFalse(draft.showsRecognitionOptions)
        XCTAssertEqual(draft.queuedConfiguration().subtitleMode, .burnOriginal)
    }

    func testEmbeddedTranslationShowsOnlyResultRelevantChoicesByDefault() {
        var draft = DownloadOptionsDraft.defaults(from: AppSettings())
        draft.subtitleOutcome = .embeddedTranslation

        XCTAssertTrue(draft.showsTranslationOptions)
        XCTAssertFalse(draft.showsRecognitionOptions,
                       "自动选择字幕时不该先要求用户理解识别模型")
        XCTAssertEqual(draft.queuedConfiguration().subtitleMode, .burnIn)
    }

    func testCustomLocalRecognitionMapsToExistingDeferredConfiguration() {
        var draft = DownloadOptionsDraft.defaults(from: AppSettings())
        draft.subtitleOutcome = .translatedFile
        draft.recognitionChoice = .local
        draft.localModelID = "whisper.cpp:large-v3-turbo-q5_0"

        let configuration = draft.queuedConfiguration()
        XCTAssertTrue(draft.showsRecognitionOptions)
        XCTAssertEqual(configuration.subtitleSourcePolicy, .forceLocalASR)
        XCTAssertEqual(configuration.transcriptionModel, "whisper.cpp:large-v3-turbo-q5_0")
        XCTAssertEqual(configuration.subtitleMode, .srtOnly)
    }

    func testExistingConfigurationUsesHumanOutcomeWithoutChangingItsDefault() {
        var configuration = QueuedProcessingConfiguration.defaults(from: AppSettings())
        configuration.subtitleMode = .burnOriginal
        configuration.subtitleSourcePolicy = .preferPlatform

        let draft = DownloadOptionsDraft(configuration: configuration)

        XCTAssertEqual(draft.subtitleOutcome, .original)
        XCTAssertEqual(draft.recognitionChoice, .automatic)
        XCTAssertEqual(draft.queuedConfiguration().subtitleSourcePolicy, .preferPlatform)
    }

    func testExistingSubtitleSourcePoliciesRoundTripUntilThePersonChangesThem() {
        for policy in SubtitleSourcePolicy.allCases {
            var configuration = QueuedProcessingConfiguration.defaults(from: AppSettings())
            configuration.subtitleMode = .srtOnly
            configuration.subtitleSourcePolicy = policy

            let draft = DownloadOptionsDraft(configuration: configuration)

            XCTAssertEqual(
                draft.queuedConfiguration().subtitleSourcePolicy,
                policy,
                "未修改时不能把 \(policy.rawValue) 静默改成另一种字幕来源策略"
            )
        }
    }
}
