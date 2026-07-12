import XCTest
@testable import Moongate
@testable import MoongateCore

final class QueuedProcessingConfigurationTests: XCTestCase {
    func testExplicitDraftOverridesApplyOnlyToItsTaskSettings() {
        var defaults = AppSettings()
        defaults.translationModel = "default-translation"
        defaults.translationFollowsDefault = true
        defaults.aiModel = "default-ai"
        defaults.translationTargetLanguage = "zh-Hans"
        defaults.localASRModelID = "base"
        defaults.subtitleStyle = .bilingual
        defaults.lastSubtitleMode = ChineseSubtitleMode.off.rawValue
        defaults.lastOutputFormat = .original
        let configuration = QueuedProcessingConfiguration(
            quality: "bv*[height<=720]+ba/b[height<=720]",
            outputFormat: .mp4H264,
            subtitleMode: .burnIn,
            subtitleSourcePolicy: .forceLocalASR,
            targetLanguage: "en",
            transcriptionModel: "large-v3",
            translationModel: "task-translation",
            subtitleStyle: .chineseOnly
        )

        let applied = configuration.applying(to: defaults)

        XCTAssertEqual(applied.translationTargetLanguage, "en")
        XCTAssertEqual(applied.localASRModelID, "large-v3")
        XCTAssertEqual(applied.translationModel, "task-translation")
        XCTAssertFalse(applied.translationFollowsDefault)
        XCTAssertEqual(applied.subtitleStyle, .chineseOnly)
        XCTAssertEqual(defaults.translationTargetLanguage, "zh-Hans")
        XCTAssertEqual(defaults.localASRModelID, "base")
        XCTAssertTrue(defaults.translationFollowsDefault)
    }

    func testDefaultsAndLibraryProjectionRetainTheQueuedConfiguration() {
        var settings = AppSettings()
        settings.translationModel = "translator"
        settings.translationFollowsDefault = false
        settings.translationTargetLanguage = "zh-Hant"
        settings.localASRModelID = "small"
        settings.subtitleStyle = .bilingual
        settings.lastSubtitleMode = ChineseSubtitleMode.srtOnly.rawValue
        settings.lastOutputFormat = .mkv

        let configuration = QueuedProcessingConfiguration.defaults(from: settings)

        XCTAssertEqual(configuration.outputFormat, .mkv)
        XCTAssertEqual(configuration.subtitleMode, .srtOnly)
        XCTAssertEqual(configuration.targetLanguage, "zh-Hant")
        XCTAssertEqual(configuration.translationModel, "translator")
        XCTAssertEqual(configuration.libraryConfiguration.outputFormat, OutputFormat.mkv.rawValue)
        XCTAssertEqual(configuration.libraryConfiguration.subtitleStyle, SubtitleStyle.bilingual.rawValue)

        let draft = DownloadDraft(sourceURL: "https://example.com/video", configuration: configuration)
        XCTAssertEqual(draft.sourceURL, "https://example.com/video")
        XCTAssertEqual(draft.configuration, configuration)
    }
}
