import XCTest
@testable import Moongate
@testable import MoongateCore

@MainActor
final class DownloadFirstOnboardingPersistenceTests: XCTestCase {
    func testAcknowledgingOnboardingOnlyMarksCompletionAndPreservesCredentialsAndRecognition() throws {
        try withIsolatedSettings { fixture in
            let initial = fixture.makeSettings(
                onboardingCompleted: false,
                appLanguage: "en",
                subtitleMode: ChineseSubtitleMode.burnOriginal.rawValue,
                targetLanguage: "zh-Hant",
                translationEngine: .openAICompatible,
                translationFollowsDefault: false,
                recognitionMode: .alwaysLocal,
                localASREnabled: true
            )
            try fixture.save(initial)

            let acknowledged = ViewModel.acknowledgingOnboarding(fixture.load(readCredentials: true))
            try fixture.save(acknowledged)
            let persisted = fixture.load(readCredentials: true)

            XCTAssertTrue(persisted.onboardingCompleted)
            XCTAssertEqual(persisted.appLanguage, initial.appLanguage)
            XCTAssertEqual(persisted.lastSubtitleMode, initial.lastSubtitleMode)
            XCTAssertEqual(persisted.translationTargetLanguage, initial.translationTargetLanguage)
            XCTAssertEqual(persisted.translationEngine, initial.translationEngine)
            XCTAssertEqual(persisted.translationBaseURL, initial.translationBaseURL)
            XCTAssertEqual(persisted.translationModel, initial.translationModel)
            XCTAssertEqual(persisted.translationAuthToken, initial.translationAuthToken)
            XCTAssertEqual(persisted.aiBaseURL, initial.aiBaseURL)
            XCTAssertEqual(persisted.aiModel, initial.aiModel)
            XCTAssertEqual(persisted.aiAuthToken, initial.aiAuthToken)
            XCTAssertEqual(persisted.subtitleRecognitionMode, initial.subtitleRecognitionMode)
            XCTAssertEqual(persisted.localASREnabled, initial.localASREnabled)
            XCTAssertEqual(persisted.localASRModelID, initial.localASRModelID)
            XCTAssertEqual(fixture.credentialStore.get("translationAuthToken"), initial.translationAuthToken)
            XCTAssertEqual(fixture.credentialStore.get("aiAuthToken"), initial.aiAuthToken)
        }
    }

    func testOnboardingDefaultsLeaveTranslationSettingsUntouchedWhenNoTranslationChoiceWasShown() throws {
        try withIsolatedSettings { fixture in
            let initial = fixture.makeSettings(
                onboardingCompleted: false,
                appLanguage: "zh-Hant",
                subtitleMode: ChineseSubtitleMode.srtOnly.rawValue,
                targetLanguage: "en",
                translationEngine: .openAICompatible,
                translationFollowsDefault: false,
                recognitionMode: .alwaysLocal,
                localASREnabled: true
            )
            try fixture.save(initial)

            let updated = ViewModel.applyingOnboardingDefaults(
                to: fixture.load(readCredentials: true),
                appLanguage: .en,
                subtitleMode: .burnOriginal,
                translationTargetLanguage: nil,
                useSystemTranslation: nil
            )
            try fixture.save(updated)
            let persisted = fixture.load(readCredentials: true)

            XCTAssertTrue(persisted.onboardingCompleted)
            XCTAssertEqual(persisted.appLanguage, AppLanguage.en.rawValue)
            XCTAssertEqual(persisted.lastSubtitleMode, ChineseSubtitleMode.burnOriginal.rawValue)
            XCTAssertEqual(persisted.translationTargetLanguage, initial.translationTargetLanguage)
            XCTAssertEqual(persisted.translationEngine, initial.translationEngine)
            XCTAssertEqual(persisted.translationFollowsDefault, initial.translationFollowsDefault)
            XCTAssertEqual(persisted.translationBaseURL, initial.translationBaseURL)
            XCTAssertEqual(persisted.translationModel, initial.translationModel)
            XCTAssertEqual(persisted.translationAuthToken, initial.translationAuthToken)
            XCTAssertEqual(persisted.aiBaseURL, initial.aiBaseURL)
            XCTAssertEqual(persisted.aiModel, initial.aiModel)
            XCTAssertEqual(persisted.aiAuthToken, initial.aiAuthToken)
            XCTAssertEqual(persisted.subtitleRecognitionMode, initial.subtitleRecognitionMode)
            XCTAssertEqual(persisted.localASREnabled, initial.localASREnabled)
        }
    }

    func testOnboardingDefaultsOnlyChangeTheExplicitTranslationResultFields() throws {
        try withIsolatedSettings { fixture in
            let initial = fixture.makeSettings(
                onboardingCompleted: false,
                appLanguage: "auto",
                subtitleMode: nil,
                targetLanguage: "en",
                translationEngine: .openAICompatible,
                translationFollowsDefault: true,
                recognitionMode: .automatic,
                localASREnabled: false
            )
            try fixture.save(initial)

            let updated = ViewModel.applyingOnboardingDefaults(
                to: fixture.load(readCredentials: true),
                appLanguage: .zhHans,
                subtitleMode: .srtOnly,
                translationTargetLanguage: "zh-Hant",
                useSystemTranslation: true
            )
            try fixture.save(updated)
            let persisted = fixture.load(readCredentials: true)

            XCTAssertTrue(persisted.onboardingCompleted)
            XCTAssertEqual(persisted.appLanguage, AppLanguage.zhHans.rawValue)
            XCTAssertEqual(persisted.lastSubtitleMode, ChineseSubtitleMode.srtOnly.rawValue)
            XCTAssertEqual(persisted.translationTargetLanguage, "zh-Hant")
            XCTAssertEqual(persisted.translationEngine, .appleTranslationLowLatency)
            XCTAssertFalse(persisted.translationFollowsDefault)
            XCTAssertEqual(persisted.translationProvider, initial.translationProvider)
            XCTAssertEqual(persisted.translationBaseURL, initial.translationBaseURL)
            XCTAssertEqual(persisted.translationModel, initial.translationModel)
            XCTAssertEqual(persisted.translationAuthToken, initial.translationAuthToken)
            XCTAssertEqual(persisted.aiEngine, initial.aiEngine)
            XCTAssertEqual(persisted.aiBaseURL, initial.aiBaseURL)
            XCTAssertEqual(persisted.aiModel, initial.aiModel)
            XCTAssertEqual(persisted.aiAuthToken, initial.aiAuthToken)
            XCTAssertEqual(persisted.subtitleRecognitionMode, initial.subtitleRecognitionMode)
            XCTAssertEqual(persisted.localASREnabled, initial.localASREnabled)
        }
    }

    private func withIsolatedSettings(
        _ body: (IsolatedSettingsFixture) throws -> Void
    ) throws {
        let fixture = try IsolatedSettingsFixture()
        defer { fixture.restore() }
        try body(fixture)
    }
}

private final class IsolatedSettingsFixture {
    let root: URL
    let supportDirectory: URL
    let legacySupportDirectory: URL
    let settingsURL: URL
    let credentialStore = InMemoryCredentialStore()
    private let previousCredentialStore: any CredentialStore

    init() throws {
        previousCredentialStore = AppSettings.credentialStore
        AppSettings.credentialStore = credentialStore
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Moongate-DownloadFirstOnboarding-\(UUID().uuidString)", isDirectory: true)
        supportDirectory = root.appendingPathComponent("月之门", isDirectory: true)
        legacySupportDirectory = root.appendingPathComponent("视频下载器", isDirectory: true)
        settingsURL = supportDirectory.appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
    }

    func restore() {
        AppSettings.credentialStore = previousCredentialStore
        try? FileManager.default.removeItem(at: root)
    }

    func load(readCredentials: Bool) -> AppSettings {
        AppSettings.load(
            supportDirectory: supportDirectory,
            legacySupportDirectory: legacySupportDirectory,
            readCredentials: readCredentials
        )
    }

    func save(_ settings: AppSettings) throws {
        try settings.save(supportDirectory: supportDirectory, settingsFileURL: settingsURL)
    }

    func makeSettings(
        onboardingCompleted: Bool,
        appLanguage: String,
        subtitleMode: String?,
        targetLanguage: String,
        translationEngine: TranslationEngine,
        translationFollowsDefault: Bool,
        recognitionMode: SubtitleRecognitionMode,
        localASREnabled: Bool
    ) -> AppSettings {
        AppSettings(
            translationProvider: .openai,
            translationEngine: translationEngine,
            translationBaseURL: "https://translation.example.test",
            translationModel: "translation-model",
            translationAuthToken: "translation-token",
            aiEngine: .openAICompatible,
            aiBaseURL: "https://ai.example.test",
            aiModel: "ai-model",
            aiAuthToken: "ai-token",
            translationFollowsDefault: translationFollowsDefault,
            lastSubtitleMode: subtitleMode,
            appLanguage: appLanguage,
            translationTargetLanguage: targetLanguage,
            subtitleRecognitionMode: recognitionMode,
            onboardingCompleted: onboardingCompleted,
            localASREnabled: localASREnabled,
            localASRModelID: "whisper.cpp:fixture"
        )
    }
}
