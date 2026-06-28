import XCTest
@testable import MoongateCore

final class SubtitleSourceDecisionTests: XCTestCase {
    func testMKBHDMetadataChoosesManualEnglishAndNeverRunsASR() {
        let report = SubtitleSourceDecision.decide(
            videoTitle: "Top 5 Android 17 Features: I Swear It's New!",
            detectedLanguageCode: "en",
            targetLanguageCode: "zh-Hans",
            preferredSourceLanguageCode: nil,
            sourcePolicy: .autoBest,
            choices: [
                auto("en"),
                auto("en-orig", variant: "orig"),
                manual("en"),
                manual("ja"),
                local("en"),
            ],
            localASRAvailable: true,
            cloudASRAvailable: false
        )

        XCTAssertEqual(report.selectedTrack?.sourceKind, .manual)
        XCTAssertEqual(report.selectedTrack?.languageCode, "en")
        XCTAssertEqual(report.asrTrigger, .never)
        XCTAssertEqual(report.userFacingReason, .manualMatchesVideoLanguage)
        XCTAssertTrue(report.candidateReports.contains {
            $0.sourceKind == .platformAuto && $0.status == .backup
        })
        XCTAssertTrue(report.candidateReports.contains {
            $0.sourceKind == .localASR && $0.status == .backup
        })
    }

    func testForeignManualSubtitleDoesNotBeatDetectedEnglishPlatformSubtitle() {
        let report = SubtitleSourceDecision.decide(
            videoTitle: "The Weird Future Of User Interfaces",
            detectedLanguageCode: "en",
            targetLanguageCode: "zh-Hans",
            preferredSourceLanguageCode: nil,
            sourcePolicy: .autoBest,
            choices: [
                manual("tlh"),
                auto("en"),
                auto("en-orig", variant: "orig"),
                local("en"),
            ],
            localASRAvailable: true,
            cloudASRAvailable: false
        )

        XCTAssertEqual(report.selectedTrack?.sourceKind, .platformAuto)
        XCTAssertEqual(report.selectedTrack?.languageCode, "en-orig")
        XCTAssertEqual(report.asrTrigger, .fallbackOnly)
        XCTAssertEqual(report.userFacingReason, .platformAutoMatchesVideoLanguage)
        XCTAssertTrue(report.candidateReports.contains {
            $0.languageCode == "tlh" && $0.status == .notUsed && $0.reason == .manualLanguageMismatch
        })
    }

    func testTargetLanguageManualSubtitleDoesNotBecomeTranslationSource() {
        let report = SubtitleSourceDecision.decide(
            videoTitle: "日本語インタビュー",
            detectedLanguageCode: "ja",
            targetLanguageCode: "zh-Hans",
            preferredSourceLanguageCode: nil,
            sourcePolicy: .autoBest,
            choices: [
                manual("zh-Hans"),
                auto("ja"),
                local("ja"),
            ],
            localASRAvailable: true,
            cloudASRAvailable: false
        )

        XCTAssertEqual(report.selectedTrack?.sourceKind, .platformAuto)
        XCTAssertEqual(report.selectedTrack?.languageCode, "ja")
        XCTAssertEqual(report.asrTrigger, .fallbackOnly)
        XCTAssertTrue(report.candidateReports.contains {
            $0.languageCode == "zh-Hans"
                && $0.status == .notUsed
                && $0.reason == .targetLanguageSubtitleNotSource
        })
    }

    func testMissingMetadataFallsBackToTitleScriptWithoutHighConfidence() {
        let report = SubtitleSourceDecision.decide(
            videoTitle: "日本語インタビュー",
            detectedLanguageCode: nil,
            targetLanguageCode: "zh-Hans",
            preferredSourceLanguageCode: nil,
            sourcePolicy: .autoBest,
            choices: [
                auto("ja"),
                auto("en"),
                local("ja"),
            ],
            localASRAvailable: true,
            cloudASRAvailable: false
        )

        XCTAssertEqual(report.selectedTrack?.languageCode, "ja")
        XCTAssertEqual(report.sourceLanguageCode, "ja")
        XCTAssertEqual(report.sourceLanguageEvidence, .titleScript)
        XCTAssertEqual(report.sourceLanguageConfidence, .low)
    }

    func testExplicitCompareRunsLocalRecognitionOnlyForComparison() {
        let report = SubtitleSourceDecision.decide(
            videoTitle: "How transformers actually work",
            detectedLanguageCode: "en",
            targetLanguageCode: "zh-Hans",
            preferredSourceLanguageCode: nil,
            sourcePolicy: .compareLocalASR,
            choices: [
                auto("en"),
                local("en"),
            ],
            localASRAvailable: true,
            cloudASRAvailable: false
        )

        XCTAssertEqual(report.selectedTrack?.sourceKind, .platformAuto)
        XCTAssertEqual(report.asrTrigger, .explicitCompare)
        XCTAssertEqual(report.userFacingReason, .compareRequested)
    }

    func testExplicitForceLocalRecognitionSelectsLocalRecognition() {
        let report = SubtitleSourceDecision.decide(
            videoTitle: "How transformers actually work",
            detectedLanguageCode: "en",
            targetLanguageCode: "zh-Hans",
            preferredSourceLanguageCode: nil,
            sourcePolicy: .forceLocalASR,
            choices: [
                manual("en"),
                local("en"),
            ],
            localASRAvailable: true,
            cloudASRAvailable: false
        )

        XCTAssertEqual(report.selectedTrack?.sourceKind, .localASR)
        XCTAssertEqual(report.asrTrigger, .explicitForce)
        XCTAssertEqual(report.userFacingReason, .localRecognitionForced)
    }

    private func manual(_ code: String) -> SubtitleChoice {
        SubtitleChoice(languageCode: code, label: code, sourceKind: .manual)
    }

    private func auto(_ code: String, variant: String? = nil) -> SubtitleChoice {
        SubtitleChoice(languageCode: code, label: code, sourceKind: .platformAuto, variant: variant)
    }

    private func local(_ code: String) -> SubtitleChoice {
        SubtitleChoice(
            languageCode: code,
            label: code,
            sourceKind: .localASR,
            provider: "whisper.cpp",
            variant: "local"
        )
    }
}
