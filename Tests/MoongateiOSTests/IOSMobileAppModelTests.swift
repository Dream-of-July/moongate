@testable import MoongateMobileCore
@testable import MoongateiOS
import XCTest

@MainActor
final class IOSMobileAppModelTests: XCTestCase {
    func testTabOrderMatchesMobileInformationArchitecture() {
        let model = IOSMobileAppModel.preview()

        XCTAssertEqual(model.tabs, [.add, .queue, .library, .settings])
        XCTAssertEqual(model.tabs.map(\.title), ["添加", "队列", "资料库", "设置"])
    }

    func testLiveModelStartsWithoutPreviewQueueLibraryOrURLData() {
        let model = IOSMobileAppModel.live()

        XCTAssertEqual(model.addSession.state, .idle)
        XCTAssertNil(model.addSession.input)
        XCTAssertNil(model.addSession.videoInfo)
        XCTAssertTrue(model.queue.isEmpty)
        XCTAssertTrue(model.library.isEmpty)
    }

    func testLiveURLAnalysisDoesNotFabricateMockVideoDataBeforeParserIsImplemented() async {
        let model = IOSMobileAppModel.live()

        await model.analyzeURL("https://example.com/video.m3u8")

        XCTAssertEqual(model.addSession.state, .unsupported)
        XCTAssertEqual(model.addSession.input?.kind, .pastedURL)
        XCTAssertNil(model.addSession.videoInfo)
        XCTAssertTrue(model.addSession.candidates.allSatisfy { !$0.isSupportedOnMobile })
        XCTAssertTrue(model.queue.isEmpty)
    }

    func testLiveURLAnalysisAcceptsDirectHTTPSMediaFileWithoutDesktopParser() async {
        let model = IOSMobileAppModel.live()

        await model.analyzeURL("https://cdn.example.com/videos/launch-clip.mp4")

        XCTAssertEqual(model.addSession.state, .ready)
        XCTAssertEqual(model.addSession.input?.kind, .pastedURL)
        XCTAssertEqual(model.addSession.videoInfo?.candidate.kind, .directFile)
        XCTAssertEqual(model.addSession.videoInfo?.candidate.sourceURL, "https://cdn.example.com/videos/launch-clip.mp4")
        XCTAssertEqual(model.addSession.videoInfo?.recommendedFormat?.id, "mp4")
        XCTAssertTrue(model.queue.isEmpty)
    }

    func testLiveURLAnalysisRejectsCredentialedAndFragmentDirectMediaURLs() async {
        for value in [
            "https://viewer@cdn.example.com/videos/launch-clip.mp4",
            "https://cdn.example.com/videos/launch-clip.mp4#session"
        ] {
            let model = IOSMobileAppModel.live()

            await model.analyzeURL(value)

            XCTAssertEqual(model.addSession.state, .unsupported)
            XCTAssertEqual(model.addSession.error, .unsupportedOnMobile)
            XCTAssertNil(model.addSession.videoInfo)
            XCTAssertTrue(model.queue.isEmpty)
        }
    }

    func testURLAnalysisUsesInjectedMobileParserWhenAvailable() async {
        let model = IOSMobileAppModel(
            addSession: MobileAddSessionSnapshot(id: "empty"),
            queue: [],
            library: [],
            mobileParser: SuccessfulMobileParser()
        )

        await model.analyzeURL("https://cdn.example.com/video.mp4")

        XCTAssertEqual(model.addSession.state, .ready)
        XCTAssertEqual(model.addSession.input?.kind, .pastedURL)
        XCTAssertEqual(model.addSession.videoInfo?.title, "Injected video")
        XCTAssertEqual(model.addSession.videoInfo?.recommendedFormat?.id, "mobile-best")
        XCTAssertTrue(model.queue.isEmpty)
    }

    func testURLAnalysisWithMultipleSupportedCandidatesWaitsForUserSelection() async {
        let model = IOSMobileAppModel(
            addSession: MobileAddSessionSnapshot(id: "empty"),
            queue: [],
            library: [],
            mobileParser: MultipleCandidateMobileParser()
        )

        await model.analyzeURL("https://cdn.example.com/video.mp4")

        XCTAssertEqual(model.addSession.state, MobileAddSessionState.candidateSelection)
        XCTAssertEqual(model.addSession.candidates.map { $0.id }, ["main", "alternate"])
        XCTAssertEqual(model.addSession.selectedCandidateID, "main")
        XCTAssertNil(model.addSession.videoInfo)
        XCTAssertNil(model.selectedAddFormatID)

        await model.selectAddCandidate(id: "alternate")

        XCTAssertEqual(model.addSession.state, MobileAddSessionState.ready)
        XCTAssertEqual(model.addSession.selectedCandidateID, "alternate")
        XCTAssertEqual(model.addSession.videoInfo?.candidate.id, "alternate")
        XCTAssertEqual(model.addSession.videoInfo?.recommendedFormat?.id, "mobile-best")
        XCTAssertEqual(model.selectedAddFormatID, "mobile-best")
    }

    func testPreviewStateIncludesBackgroundInterruptedQueueWork() {
        let model = IOSMobileAppModel.preview()

        XCTAssertTrue(model.queue.contains { $0.state == .needsForegroundToContinue })
        XCTAssertFalse(model.foregroundRequiredTasks.isEmpty)
        XCTAssertTrue(model.foregroundRequiredTasks.allSatisfy { task in
            switch task.state {
            case .waiting, .analyzing, .ready, .downloading, .translating, .exporting, .needsForegroundToContinue:
                return true
            case .completed, .failed, .cancelled:
                return false
            }
        })
        XCTAssertTrue(model.queue.allSatisfy { !$0.backgroundPolicy.allowsUnboundedBackgroundExecution })
    }

    func testAppleIntelligenceRoutesCoverLocalCloudAndCloudProWithoutClaimingAvailability() {
        let model = IOSMobileAppModel.preview()

        XCTAssertEqual(model.appleIntelligenceStatuses.map(\.route), [.onDevice, .privateCloud, .privateCloudPro])
        XCTAssertTrue(model.appleIntelligenceStatuses.allSatisfy { !$0.isAvailable })
        XCTAssertTrue(model.appleIntelligenceStatuses.allSatisfy(\.supportsIOS26RuntimeChecks))
        XCTAssertTrue(model.appleIntelligenceStatuses.allSatisfy { !$0.supportsIOS27RuntimeChecks })
        XCTAssertFalse(model.appleIntelligenceStatuses.contains { $0.detail.contains("当前未实现") })
    }

    func testSelectingAppleIntelligenceRouteUpdatesTranslationEngineAndReadiness() {
        let model = IOSMobileAppModel.preview()

        model.selectAppleIntelligenceRoute(.onDevice)

        XCTAssertEqual(model.selectedAppleIntelligenceRoute, .onDevice)
        XCTAssertEqual(model.translationConfiguration.engine, .appleFoundationOnDevice)
        XCTAssertFalse(model.translationConfiguration.readiness.isReady)

        model.selectAppleIntelligenceRoute(.privateCloudPro)

        XCTAssertEqual(model.selectedAppleIntelligenceRoute, .privateCloudPro)
        XCTAssertEqual(model.translationConfiguration.engine, .appleFoundationCloudPro)
        XCTAssertFalse(model.translationConfiguration.readiness.isReady)
    }

    func testSelectingUnverifiedAppleIntelligenceRouteNeverClaimsReadyBeforeRefresh() {
        let model = IOSMobileAppModel(
            appleIntelligenceStatuses: [
                IOSAppleIntelligenceStatus(
                    route: .onDevice,
                    readiness: .ready,
                    detail: "Injected static status.",
                    isRuntimeVerified: false
                )
            ]
        )

        model.selectAppleIntelligenceRoute(.onDevice)

        XCTAssertFalse(model.translationConfiguration.readiness.isReady)
        XCTAssertFalse(model.appleIntelligenceStatuses[0].isAvailable)
        XCTAssertTrue(model.appleIntelligenceStatuses[0].detail.contains("需要在本设备检查"))
        XCTAssertFalse(model.appleIntelligenceStatuses[0].detail.contains("当前未实现"))
    }

    func testRuntimeVerifiedButUnimplementedAppleRouteShowsUnavailableLabel() {
        let status = IOSAppleIntelligenceStatus(
            route: .onDevice,
            readiness: TranslationReadiness(issues: [
                TranslationReadinessIssue(kind: .needsExecutionAdapter)
            ]),
            detail: "系统模型已通过检测，但暂不能用于字幕翻译。",
            isRuntimeVerified: true
        )

        XCTAssertFalse(status.isAvailable)
        XCTAssertEqual(status.availabilityLabel, "暂不可用")
    }

    func testRefreshingAppleIntelligenceStatusUsesInjectedRuntimeEvaluator() async {
        let evaluator = RecordingTranslationRuntimeReadinessEvaluator { request in
            XCTAssertEqual(request.engine, .appleFoundationOnDevice)
            XCTAssertEqual(request.context.targetLanguage, "zh-Hans")
            return .ready
        }
        let model = IOSMobileAppModel(runtimeReadinessEvaluator: evaluator)

        await model.refreshAppleIntelligenceStatus(for: .onDevice)

        XCTAssertEqual(model.selectedAppleIntelligenceRoute, .onDevice)
        XCTAssertEqual(model.translationConfiguration.engine, .appleFoundationOnDevice)
        XCTAssertFalse(model.translationConfiguration.readiness.isReady)
        XCTAssertEqual(model.translationConfiguration.readiness.issues.map(\.kind), [.needsExecutionAdapter])
        let status = model.appleIntelligenceStatuses.first { $0.route == .onDevice }
        XCTAssertEqual(status?.isRuntimeVerified, true)
        XCTAssertFalse(status?.isAvailable == true)
        XCTAssertTrue(status?.detail.contains("设备检测通过") == true)
        XCTAssertTrue(status?.detail.contains("暂不能用于字幕翻译") == true)
        let requests = await evaluator.requests()
        XCTAssertEqual(requests.map(\.engine), [.appleFoundationOnDevice])
    }

    func testRefreshingPCCRouteRemainsUnavailableWithoutIOS27RuntimeClaim() async throws {
        let evaluator = RecordingTranslationRuntimeReadinessEvaluator { _ in
            TranslationReadiness(issues: [
                TranslationReadinessIssue(kind: .pccUnavailable, message: "PCC 未开放。")
            ])
        }
        let model = IOSMobileAppModel(runtimeReadinessEvaluator: evaluator)

        await model.refreshAppleIntelligenceStatus(for: .privateCloudPro)

        let status = try XCTUnwrap(model.appleIntelligenceStatuses.first { $0.route == .privateCloudPro })
        XCTAssertFalse(status.isAvailable)
        XCTAssertFalse(status.supportsIOS27RuntimeChecks)
        XCTAssertEqual(model.translationConfiguration.engine, .appleFoundationCloudPro)
        XCTAssertEqual(model.translationConfiguration.readiness.issues.map(\.kind), [.pccUnavailable])
    }

    func testAppleIntelligenceRoutesMapCloudAndCloudProToDistinctSharedEngines() {
        XCTAssertEqual(IOSAppleIntelligenceRoute.privateCloud.translationEngine, .appleFoundationPCC)
        XCTAssertEqual(IOSAppleIntelligenceRoute.privateCloudPro.translationEngine, .appleFoundationCloudPro)
        XCTAssertFalse(IOSAppleIntelligenceRoute.privateCloud.translationEngine.requiresCloudConfiguration)
        XCTAssertFalse(IOSAppleIntelligenceRoute.privateCloudPro.translationEngine.requiresCloudConfiguration)
    }

    func testIOSRuntimeReadinessEvaluatorKeepsPCCUnavailable() async {
        let evaluator = IOSRuntimeReadinessEvaluator()

        for engine in [TranslationEngine.appleFoundationPCC, .appleFoundationCloudPro] {
            let readiness = await evaluator.readiness(for: TranslationRuntimeReadinessRequest(
                engine: engine,
                isCloudConfigurationComplete: true,
                fallbackReadiness: .ready
            ))

            XCTAssertEqual(readiness.issues.map(\.kind), [.pccUnavailable])
            XCTAssertFalse(readiness.isReady)
        }
    }

    func testIOSRuntimeReadinessEvaluatorUsesDistinctPCCAndCloudProMessages() async throws {
        let evaluator = IOSRuntimeReadinessEvaluator()
        let pccReadiness = await evaluator.readiness(for: TranslationRuntimeReadinessRequest(
            engine: .appleFoundationPCC,
            isCloudConfigurationComplete: true,
            fallbackReadiness: .ready
        ))
        let cloudProReadiness = await evaluator.readiness(for: TranslationRuntimeReadinessRequest(
            engine: .appleFoundationCloudPro,
            isCloudConfigurationComplete: true,
            fallbackReadiness: .ready
        ))
        let pccMessage = try XCTUnwrap(pccReadiness.issues.first?.message)
        let cloudProMessage = try XCTUnwrap(cloudProReadiness.issues.first?.message)

        XCTAssertEqual(pccReadiness.issues.map(\.kind), [.pccUnavailable])
        XCTAssertEqual(cloudProReadiness.issues.map(\.kind), [.pccUnavailable])
        XCTAssertTrue(pccMessage.contains("Private Cloud Compute") || pccMessage.contains("云端"))
        XCTAssertFalse(pccMessage.contains("Cloud Pro"))
        XCTAssertTrue(cloudProMessage.contains("Cloud Pro") || cloudProMessage.contains("云端 Pro"))
    }

    func testIOSRuntimeReadinessEvaluatorPreservesCloudProviderFallback() async {
        let fallback = TranslationReadiness(issues: [
            TranslationReadinessIssue(kind: .needsConfiguration, message: "需要模型和 API key。")
        ])
        let evaluator = IOSRuntimeReadinessEvaluator()

        let readiness = await evaluator.readiness(for: TranslationRuntimeReadinessRequest(
            engine: .openAICompatible,
            isCloudConfigurationComplete: false,
            fallbackReadiness: fallback
        ))

        XCTAssertEqual(readiness, fallback)
    }

    func testCloudProAPIKeyDraftDoesNotCreateCredentialSurface() async throws {
        let storageDirectory = temporaryDirectory()
        let store = RecordingCredentialStore()
        let model = IOSMobileAppModel(
            credentialStore: store,
            storageDirectoryURL: storageDirectory
        )

        model.selectAppleIntelligenceRoute(IOSAppleIntelligenceRoute.privateCloudPro)
        await model.saveAPIKeyDraft("TEST_SECRET_VALUE_DO_NOT_STORE")

        let savedSecrets = await store.savedSecrets()
        let savedReferences = await store.savedReferences()

        XCTAssertTrue(savedSecrets.isEmpty)
        XCTAssertTrue(savedReferences.isEmpty)
        XCTAssertNil(model.translationConfiguration.credential)
        XCTAssertEqual(model.translationConfiguration.readiness.issues.map(\.kind), [TranslationReadinessIssue.Kind.pccUnavailable])
        XCTAssertEqual(model.translationConfiguration.engine, TranslationEngine.appleFoundationCloudPro)

        let configurationURL = storageDirectory.appendingPathComponent(
            "mobile-translation-configuration.json",
            isDirectory: false
        )
        let encoded = try XCTUnwrap(try? String(contentsOf: configurationURL, encoding: .utf8))
        XCTAssertFalse(encoded.contains("TEST_SECRET_VALUE_DO_NOT_STORE"))
        XCTAssertFalse(encoded.contains("appleFoundationCloudPro."))
    }

    func testSelectingCloudProClearsExistingAPICompatibleCredentialReference() async {
        let store = RecordingCredentialStore()
        let model = IOSMobileAppModel(
            translationConfiguration: MobileTranslationConfiguration(
                engine: .openAICompatible,
                baseURL: "https://api.openai.com",
                model: "gpt-5-mini"
            ),
            credentialStore: store
        )

        await model.saveAPIKeyDraft("TEST_SECRET_VALUE_DO_NOT_STORE")
        XCTAssertTrue(model.hasConfiguredTranslationCredential)
        XCTAssertEqual(model.translationConfiguration.credential?.service, "translation.openAICompatible.api.openai.com")

        model.selectAppleIntelligenceRoute(.privateCloudPro)
        await model.waitForPendingCredentialCleanup()

        XCTAssertEqual(model.translationConfiguration.engine, .appleFoundationCloudPro)
        XCTAssertNil(model.translationConfiguration.credential)
        XCTAssertFalse(model.hasConfiguredTranslationCredential)
        XCTAssertEqual(model.translationConfiguration.readiness.issues.map(\.kind), [TranslationReadinessIssue.Kind.pccUnavailable])
        let deletedReferences = await store.deletedReferences()
        XCTAssertEqual(deletedReferences.map(\.service), ["translation.openAICompatible.api.openai.com"])
    }

    func testCloudProConnectionTestRejectsBeforeProviderOrCredentialWork() async {
        let store = RecordingCredentialStore()
        let transport = RecordingConnectionTestTransport(
            statusCode: 200,
            responseText: "{}"
        )
        let model = IOSMobileAppModel(
            credentialStore: store,
            translationConnectionTransport: transport
        )

        model.selectAppleIntelligenceRoute(IOSAppleIntelligenceRoute.privateCloudPro)
        await model.testCloudTranslationConnection()

        XCTAssertEqual(model.cloudTranslationConnectionStatus.state, .failed)
        let message = model.cloudTranslationConnectionStatus.message
        let recordedRequest = await transport.firstRecordedRequest()
        let savedSecrets = await store.savedSecrets()

        XCTAssertTrue(message.contains("Cloud Pro") || message.contains("云端 Pro"))
        XCTAssertFalse(message.contains("API key"))
        XCTAssertFalse(message.contains("服务地址"))
        XCTAssertFalse(message.contains("模型"))
        XCTAssertFalse(message.contains("协议"))
        XCTAssertNil(recordedRequest)
        XCTAssertTrue(savedSecrets.isEmpty)
        XCTAssertNil(model.translationConfiguration.credential)
        XCTAssertEqual(model.translationConfiguration.readiness.issues.map(\.kind), [TranslationReadinessIssue.Kind.pccUnavailable])
    }

    func testCloudProStaticReadinessMessageUsesCloudProCopy() throws {
        let model = IOSMobileAppModel.preview()
        let status = try XCTUnwrap(model.appleIntelligenceStatuses.first { $0.route == .privateCloudPro })
        let message = try XCTUnwrap(status.readiness.issues.first { $0.kind == .pccUnavailable }?.message)

        XCTAssertTrue(message.contains("Cloud Pro") || message.contains("云端 Pro"))
        XCTAssertFalse(message.contains("Private Cloud Compute"))
    }

    func testAPIKeyDraftSavesThroughCredentialStoreAndSerializesOnlyReference() async throws {
        let store = RecordingCredentialStore()
        let model = IOSMobileAppModel(credentialStore: store)

        await model.saveAPIKeyDraft("TEST_SECRET_VALUE_DO_NOT_STORE")

        XCTAssertTrue(model.hasConfiguredTranslationCredential)
        XCTAssertTrue(model.translationConfiguration.readiness.isReady)
        let savedSecrets = await store.savedSecrets()
        let savedReferences = await store.savedReferences()
        XCTAssertEqual(savedSecrets, ["TEST_SECRET_VALUE_DO_NOT_STORE"])
        XCTAssertEqual(savedReferences.map(\.service), ["translation.openAICompatible.api.openai.com"])
        let data = try JSONEncoder().encode(model.translationConfiguration)
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(encoded.contains("TEST_SECRET_VALUE_DO_NOT_STORE"))
        XCTAssertFalse(encoded.contains("apiKey"))
        XCTAssertTrue(encoded.contains("translation.openAICompatible.api.openai.com"))
    }

    func testLiveModelPersistsNonSecretCloudTranslationConfigurationAcrossLaunches() async throws {
        let storageDirectory = temporaryDirectory()
        let store = RecordingCredentialStore()
        let model = IOSMobileAppModel.live(
            storageDirectoryURL: storageDirectory,
            credentialStore: store
        )

        model.updateCloudTranslationEngine(.anthropicCompatible)
        model.updateCloudTranslationEndpoint(" https://gateway.example.com/v1 ")
        model.updateCloudTranslationModel(" deepseek-chat ")
        await model.saveAPIKeyDraft("TEST_SECRET_VALUE_DO_NOT_STORE")

        let relaunched = IOSMobileAppModel.live(
            storageDirectoryURL: storageDirectory,
            credentialStore: store
        )

        XCTAssertEqual(relaunched.translationConfiguration.engine, .anthropicCompatible)
        XCTAssertEqual(relaunched.translationConfiguration.baseURL, "https://gateway.example.com/v1")
        XCTAssertEqual(relaunched.translationConfiguration.model, "deepseek-chat")
        XCTAssertEqual(relaunched.translationConfiguration.credential?.service, "translation.anthropicCompatible.gateway.example.com")
        XCTAssertFalse(relaunched.translationConfiguration.readiness.isReady)
        XCTAssertEqual(relaunched.translationConfiguration.readiness.issues.map(\.kind), [.needsConfiguration])

        await relaunched.refreshCloudTranslationCredentialReadiness()

        XCTAssertTrue(relaunched.translationConfiguration.readiness.isReady)

        let configurationURL = storageDirectory.appendingPathComponent(
            "mobile-translation-configuration.json",
            isDirectory: false
        )
        let encoded = try String(contentsOf: configurationURL, encoding: .utf8)
        XCTAssertFalse(encoded.contains("TEST_SECRET_VALUE_DO_NOT_STORE"))
        XCTAssertFalse(encoded.contains("apiKey"))
        XCTAssertTrue(encoded.contains("translation.anthropicCompatible.gateway.example.com"))
    }

    func testLiveModelDoesNotMarkRestoredCloudTranslationReadyWhenCredentialIsMissing() async throws {
        let storageDirectory = temporaryDirectory()
        let savingStore = RecordingCredentialStore()
        let model = IOSMobileAppModel.live(
            storageDirectoryURL: storageDirectory,
            credentialStore: savingStore
        )
        model.updateCloudTranslationEndpoint("https://api.openai.com")
        model.updateCloudTranslationModel("gpt-5-mini")
        await model.saveAPIKeyDraft("TEST_SECRET_VALUE_DO_NOT_STORE")

        let missingStore = RecordingCredentialStore()
        let relaunched = IOSMobileAppModel.live(
            storageDirectoryURL: storageDirectory,
            credentialStore: missingStore
        )

        XCTAssertNotNil(relaunched.translationConfiguration.credential)
        XCTAssertFalse(relaunched.translationConfiguration.readiness.isReady)

        await relaunched.refreshCloudTranslationCredentialReadiness()

        XCTAssertFalse(relaunched.translationConfiguration.readiness.isReady)
        XCTAssertEqual(relaunched.translationConfiguration.readiness.issues.map(\.kind), [.needsConfiguration])
    }

    func testSavedAPIKeyDoesNotMarkCloudTranslationReadyWhenEndpointOrModelIsMissing() async {
        let store = RecordingCredentialStore()
        let model = IOSMobileAppModel(
            translationConfiguration: MobileTranslationConfiguration(
                engine: .openAICompatible,
                baseURL: "",
                model: nil
            ),
            credentialStore: store
        )

        await model.saveAPIKeyDraft("TEST_SECRET_VALUE_DO_NOT_STORE")

        XCTAssertTrue(model.hasConfiguredTranslationCredential)
        XCTAssertFalse(model.translationConfiguration.readiness.isReady)
        XCTAssertEqual(model.translationConfiguration.readiness.issues.map(\.kind), [.needsConfiguration])
    }

    func testUpdatingCloudTranslationConfigurationRefreshesReadinessWithoutCredential() {
        let model = IOSMobileAppModel(
            translationConfiguration: MobileTranslationConfiguration(
                engine: .openAICompatible,
                baseURL: nil,
                model: nil
            )
        )

        model.updateCloudTranslationEngine(.anthropicCompatible)
        model.updateCloudTranslationEndpoint(" https://gateway.example.com/v1 ")
        model.updateCloudTranslationModel(" deepseek-chat ")

        XCTAssertEqual(model.translationConfiguration.engine, .anthropicCompatible)
        XCTAssertEqual(model.translationConfiguration.baseURL, "https://gateway.example.com/v1")
        XCTAssertEqual(model.translationConfiguration.model, "deepseek-chat")
        XCTAssertFalse(model.translationConfiguration.readiness.isReady)
        XCTAssertEqual(model.translationConfiguration.readiness.issues.map(\.kind), [.needsConfiguration])

        model.updateCloudTranslationModel("  ")

        XCTAssertNil(model.translationConfiguration.model)
        XCTAssertFalse(model.translationConfiguration.readiness.isReady)
    }

    func testChangingCloudTranslationEndpointOrEngineRequiresCredentialReconfirmation() async {
        let store = RecordingCredentialStore()
        let model = IOSMobileAppModel(
            translationConfiguration: MobileTranslationConfiguration(
                engine: .openAICompatible,
                baseURL: "https://api.openai.com",
                model: "gpt-5-mini"
            ),
            credentialStore: store
        )

        await model.saveAPIKeyDraft("TEST_SECRET_VALUE_DO_NOT_STORE")
        XCTAssertTrue(model.hasConfiguredTranslationCredential)
        XCTAssertTrue(model.translationConfiguration.readiness.isReady)

        model.updateCloudTranslationEndpoint("https://gateway.example.com")

        XCTAssertFalse(model.hasConfiguredTranslationCredential)
        XCTAssertFalse(model.translationConfiguration.readiness.isReady)
        XCTAssertEqual(model.translationConfiguration.readiness.issues.map(\.kind), [.needsConfiguration])

        await model.saveAPIKeyDraft("TEST_SECRET_VALUE_DO_NOT_STORE")
        XCTAssertTrue(model.hasConfiguredTranslationCredential)

        model.updateCloudTranslationEngine(.anthropicCompatible)

        XCTAssertFalse(model.hasConfiguredTranslationCredential)
        XCTAssertFalse(model.translationConfiguration.readiness.isReady)
        XCTAssertEqual(model.translationConfiguration.readiness.issues.map(\.kind), [.needsConfiguration])
    }

    func testChangingCloudTranslationScopeDeletesPreviousCredentialReference() async {
        let store = RecordingCredentialStore()
        let model = IOSMobileAppModel(
            translationConfiguration: MobileTranslationConfiguration(
                engine: .openAICompatible,
                baseURL: "https://api.openai.com",
                model: "gpt-5-mini"
            ),
            credentialStore: store
        )

        await model.saveAPIKeyDraft("TEST_SECRET_VALUE_DO_NOT_STORE")
        model.updateCloudTranslationEndpoint("https://gateway.example.com")
        await model.waitForPendingCredentialCleanup()

        var deletedReferences = await store.deletedReferences()
        XCTAssertEqual(deletedReferences.map(\.service), ["translation.openAICompatible.api.openai.com"])

        await model.saveAPIKeyDraft("TEST_SECRET_VALUE_DO_NOT_STORE")
        model.updateCloudTranslationEngine(.anthropicCompatible)
        await model.waitForPendingCredentialCleanup()

        deletedReferences = await store.deletedReferences()
        XCTAssertEqual(
            deletedReferences.map(\.service),
            [
                "translation.openAICompatible.api.openai.com",
                "translation.openAICompatible.gateway.example.com"
            ]
        )
    }

    func testDeletingAPIKeyUsesExplicitModelActionAndMarksConfigurationIncomplete() async {
        let store = RecordingCredentialStore()
        let model = IOSMobileAppModel(credentialStore: store)

        await model.saveAPIKeyDraft("TEST_SECRET_VALUE_DO_NOT_STORE")
        await model.deleteAPIKey()

        XCTAssertFalse(model.hasConfiguredTranslationCredential)
        XCTAssertFalse(model.translationConfiguration.readiness.isReady)
        XCTAssertEqual(model.translationConfiguration.readiness.issues.map(\.kind), [.needsConfiguration])
        let deletedReferences = await store.deletedReferences()
        XCTAssertEqual(deletedReferences.map(\.service), ["translation.openAICompatible.api.openai.com"])
    }

    func testTestingCloudTranslationConnectionUsesConfiguredProviderAndDoesNotPersistSecretInStatus() async throws {
        let store = RecordingCredentialStore()
        let transport = RecordingConnectionTestTransport(statusCode: 200, responseText: """
        {
          "output": [
            {
              "type": "message",
              "content": [
                { "type": "output_text", "text": "connection-test=连接正常" }
              ]
            }
          ]
        }
        """)
        let model = IOSMobileAppModel(
            translationConfiguration: MobileTranslationConfiguration(
                engine: .openAICompatible,
                baseURL: "https://api.openai.com",
                model: "gpt-5-mini"
            ),
            credentialStore: store,
            translationConnectionTransport: transport
        )

        await model.saveAPIKeyDraft("TEST_SECRET_VALUE_DO_NOT_STORE")
        await model.testCloudTranslationConnection()

        XCTAssertEqual(model.cloudTranslationConnectionStatus.state, .succeeded)
        XCTAssertTrue(model.cloudTranslationConnectionStatus.message.contains("连接成功"))
        XCTAssertFalse(model.cloudTranslationConnectionStatus.message.contains("TEST_SECRET_VALUE_DO_NOT_STORE"))

        let maybeRecorded = await transport.firstRecordedRequest()
        let recorded = try XCTUnwrap(maybeRecorded)
        let body = try XCTUnwrap(String(data: recorded.body, encoding: .utf8))
        XCTAssertEqual(recorded.url.absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(recorded.headers["Authorization"], "Bearer TEST_SECRET_VALUE_DO_NOT_STORE")
        XCTAssertTrue(body.contains("connection-test"))
    }

    func testFailedCloudTranslationConnectionStatusDoesNotEchoSecretOrServerBody() async {
        let store = RecordingCredentialStore()
        let transport = RecordingConnectionTestTransport(
            statusCode: 503,
            responseText: "TEST_SECRET_VALUE_DO_NOT_STORE unavailable"
        )
        let model = IOSMobileAppModel(
            translationConfiguration: MobileTranslationConfiguration(
                engine: .anthropicCompatible,
                baseURL: "https://gateway.example.com",
                model: "deepseek-chat"
            ),
            credentialStore: store,
            translationConnectionTransport: transport
        )

        await model.saveAPIKeyDraft("TEST_SECRET_VALUE_DO_NOT_STORE")
        await model.testCloudTranslationConnection()

        XCTAssertEqual(model.cloudTranslationConnectionStatus.state, .failed)
        XCTAssertTrue(model.cloudTranslationConnectionStatus.message.contains("HTTP 503"))
        XCTAssertFalse(model.cloudTranslationConnectionStatus.message.contains("TEST_SECRET_VALUE_DO_NOT_STORE"))
        XCTAssertFalse(model.cloudTranslationConnectionStatus.message.contains("unavailable"))
    }

    func testEmptyAPIKeyDraftDeletesStoredCredentialAndMarksConfigurationIncomplete() async {
        let store = RecordingCredentialStore()
        let model = IOSMobileAppModel(credentialStore: store)

        await model.saveAPIKeyDraft("TEST_SECRET_VALUE_DO_NOT_STORE")
        await model.saveAPIKeyDraft("  ")

        XCTAssertFalse(model.hasConfiguredTranslationCredential)
        XCTAssertFalse(model.translationConfiguration.readiness.isReady)
        XCTAssertEqual(model.translationConfiguration.readiness.issues.map(\.kind), [.needsConfiguration])
        let deletedReferences = await store.deletedReferences()
        XCTAssertEqual(deletedReferences.map(\.service), ["translation.openAICompatible.api.openai.com"])
    }

    func testFailedAPIKeySaveDoesNotLeaveCredentialReferenceInModel() async throws {
        let store = RecordingCredentialStore(saveError: RecordingCredentialStore.Error.saveFailed)
        let model = IOSMobileAppModel(credentialStore: store)

        await model.saveAPIKeyDraft("TEST_SECRET_VALUE_DO_NOT_STORE")

        XCTAssertFalse(model.hasConfiguredTranslationCredential)
        XCTAssertFalse(model.translationConfiguration.readiness.isReady)
        let data = try JSONEncoder().encode(model.translationConfiguration)
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(encoded.contains("TEST_SECRET_VALUE_DO_NOT_STORE"))
    }

    func testCompletedAndFailedDefaultPolicyTasksDoNotAppearInForegroundRequiredList() {
        let model = IOSMobileAppModel(queue: [
            MobileTaskSnapshot(id: "completed", platform: .iOS, state: .completed),
            MobileTaskSnapshot(id: "failed", platform: .iOS, state: .failed, error: .networkUnavailable),
            MobileTaskSnapshot(id: "cancelled", platform: .iOS, state: .cancelled),
            MobileTaskSnapshot(
                id: "foreground",
                platform: .iOS,
                state: .needsForegroundToContinue,
                backgroundPolicy: MobileBackgroundPolicy(execution: .systemInterrupted, resumability: .resumable)
            )
        ])

        XCTAssertEqual(model.foregroundRequiredTasks.map(\.id), ["foreground"])
    }

    func testAddActionsCreateReviewableMockStatesWithoutDeadButtons() {
        let model = IOSMobileAppModel(addSession: MobileAddSessionSnapshot(id: "empty"))

        model.analyzeMockURL("https://example.com/video.m3u8")

        XCTAssertEqual(model.addSession.state, .ready)
        XCTAssertEqual(model.addSession.input?.kind, .pastedURL)
        XCTAssertNotNil(model.addSession.videoInfo?.recommendedFormat)

        model.importMockFile(named: "clip.mov")

        XCTAssertEqual(model.addSession.input?.kind, .importedFile)
        XCTAssertEqual(model.addSession.videoInfo?.title, "clip.mov")

        model.applySharedMockURL("https://example.com/shared.m3u8")

        XCTAssertEqual(model.addSession.input?.kind, .sharedURL)
    }

    func testImportingLocalVideoCopiesIntoAppStorageAndCreatesCompletedQueueAndLibraryRecord() async throws {
        let storageDirectory = temporaryDirectory()
        let importDirectory = temporaryDirectory()
        let importedVideoURL = importDirectory.appendingPathComponent("Imported Clip.mov")
        try Data("fake-movie-bytes".utf8).write(to: importedVideoURL)
        let repository = RecordingTaskRepository()
        let importedFileAccessor = RecordingImportedFileAccessor()
        let model = IOSMobileAppModel(
            addSession: MobileAddSessionSnapshot(id: "empty"),
            queue: [],
            library: [],
            importedFileAccessor: importedFileAccessor,
            storageDirectoryURL: storageDirectory,
            taskRepository: repository
        )

        await model.importVideoFile(fileURL: importedVideoURL)

        XCTAssertEqual(model.selectedTab, .library)
        XCTAssertEqual(model.addSession.input?.kind, .importedFile)
        XCTAssertEqual(model.queue.count, 1)
        let task = try XCTUnwrap(model.queue.first)
        XCTAssertEqual(task.state, .completed)
        XCTAssertEqual(task.platform, .iOS)
        XCTAssertEqual(task.result?.primaryArtifact?.kind, .originalMedia)
        XCTAssertEqual(task.result?.primaryArtifact?.displayName, "Imported Clip.mov")
        XCTAssertEqual(task.progress, MobileTaskProgress(phase: .downloading, completedUnitCount: 16, totalUnitCount: 16))
        XCTAssertEqual(task.backgroundPolicy.execution, .foregroundRequired)
        XCTAssertFalse(task.backgroundPolicy.canResume)

        let artifact = try XCTUnwrap(task.result?.primaryArtifact)
        XCTAssertTrue(artifact.storageIdentifier.hasPrefix("Downloads/"))
        XCTAssertFalse(artifact.storageIdentifier.contains(importDirectory.path))
        let copiedURL = try IOSArtifactStore(storageDirectoryURL: storageDirectory).fileURL(for: artifact)
        XCTAssertNotEqual(copiedURL.standardizedFileURL.path, importedVideoURL.standardizedFileURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copiedURL.path))

        XCTAssertEqual(model.library.count, 1)
        let libraryItem = try XCTUnwrap(model.library.first)
        XCTAssertEqual(libraryItem.state, .available)
        XCTAssertEqual(libraryItem.sourceTaskID, task.id)
        XCTAssertEqual(libraryItem.artifacts.first, artifact)

        let accessedURLs = importedFileAccessor.accessedURLs()
        XCTAssertEqual(accessedURLs.map(\.standardizedFileURL.path), [importedVideoURL.standardizedFileURL.path])
        let savedTasks = await repository.savedTasks()
        let savedTask = try XCTUnwrap(savedTasks.first)
        let encoded = try String(data: JSONEncoder().encode(savedTask), encoding: .utf8)
        XCTAssertNotNil(encoded)
        XCTAssertFalse(encoded?.contains(importDirectory.path) == true)
        XCTAssertFalse(encoded?.contains("file://") == true)
    }

    func testCompletedLocalVideoCanAttachImportedSubtitleAndExportRealTranslatedFile() async throws {
        let storageDirectory = temporaryDirectory()
        let importDirectory = temporaryDirectory()
        let importedVideoURL = importDirectory.appendingPathComponent("Imported Clip.mp4")
        let importedSubtitleURL = importDirectory.appendingPathComponent("Manual English.srt")
        try Data("fake-movie-bytes".utf8).write(to: importedVideoURL)
        try """
        1
        00:00:00,000 --> 00:00:01,000
        Hello from the attached subtitle.

        """.write(to: importedSubtitleURL, atomically: true, encoding: .utf8)
        let repository = RecordingTaskRepository()
        let importedFileAccessor = RecordingImportedFileAccessor()
        let model = IOSMobileAppModel(
            addSession: MobileAddSessionSnapshot(id: "empty"),
            queue: [],
            library: [],
            subtitleProcessor: IOSMobileSubtitleProcessor(storageDirectoryURL: storageDirectory),
            importedFileAccessor: importedFileAccessor,
            storageDirectoryURL: storageDirectory,
            taskRepository: repository
        )

        await model.importVideoFile(fileURL: importedVideoURL)
        let itemID = try XCTUnwrap(model.library.first?.id)
        XCTAssertTrue(model.canAttachImportedSubtitle(toLibraryItem: try XCTUnwrap(model.library.first)))

        await model.attachImportedSubtitle(fileURL: importedSubtitleURL, toLibraryItemID: itemID, languageCode: "en")

        let taskAfterAttach = try XCTUnwrap(model.queue.first)
        XCTAssertEqual(taskAfterAttach.result?.artifacts.map(\.kind), [.originalMedia, .transcript])
        XCTAssertTrue(taskAfterAttach.availableActions.contains(.exportTranslatedSubtitle))
        let transcript = try XCTUnwrap(taskAfterAttach.result?.artifacts.first { $0.kind == .transcript })
        XCTAssertEqual(transcript.displayName, "Manual English.srt")
        XCTAssertEqual(transcript.storageIdentifier, "\(taskAfterAttach.id)-attached-en-Manual-English-srt-Manual-English.srt")
        XCTAssertFalse(transcript.storageIdentifier.contains(importDirectory.path))
        XCTAssertEqual(
            try String(contentsOf: storageDirectory.appendingPathComponent(transcript.storageIdentifier), encoding: .utf8),
            try String(contentsOf: importedSubtitleURL, encoding: .utf8)
        )
        XCTAssertEqual(model.library.first?.artifacts.map(\.kind), [.originalMedia, .transcript])
        XCTAssertEqual(model.lastLibraryActionStatus, "已添加字幕 Manual English.srt")

        await model.applyTranslationResult(
            MobileTranslationResult(segments: [
                MobileTranslationSegment(
                    id: "1",
                    startTime: "00:00:00,000",
                    endTime: "00:00:01,000",
                    text: "你好，来自后置字幕。"
                )
            ]),
            toTaskID: taskAfterAttach.id
        )
        await model.performQueueAction(.exportTranslatedSubtitle, taskID: taskAfterAttach.id)

        let completed = try XCTUnwrap(model.queue.first)
        XCTAssertEqual(completed.result?.artifacts.map(\.kind), [.originalMedia, .transcript, .translatedSubtitleFile])
        let translated = try XCTUnwrap(completed.result?.artifacts.first { $0.kind == .translatedSubtitleFile })
        XCTAssertEqual(translated.displayName, "Manual English.zh.srt")
        let translatedURL = try IOSArtifactStore(storageDirectoryURL: storageDirectory).fileURL(for: translated)
        let translatedPayload = try String(contentsOf: translatedURL, encoding: .utf8)
        XCTAssertTrue(translatedPayload.contains("你好，来自后置字幕。"))
        XCTAssertEqual(model.library.first?.artifacts.map(\.kind), [.originalMedia, .transcript, .translatedSubtitleFile])
        XCTAssertEqual(model.library.first?.sourceTaskID, taskAfterAttach.id)

        let savedTasks = await repository.savedTasks()
        let encodedLastTask = try XCTUnwrap(String(data: JSONEncoder().encode(try XCTUnwrap(savedTasks.last)), encoding: .utf8))
        XCTAssertFalse(encodedLastTask.contains(importDirectory.path))
        XCTAssertFalse(encodedLastTask.contains("file://"))
    }

    func testImportingUnsupportedLocalVideoFailsAsUnsupportedWithoutAccessingFileOrMutatingQueue() async throws {
        let storageDirectory = temporaryDirectory()
        let importDirectory = temporaryDirectory()
        let textURL = importDirectory.appendingPathComponent("notes.txt")
        try Data("not-a-video".utf8).write(to: textURL)
        let repository = RecordingTaskRepository()
        let importedFileAccessor = RecordingImportedFileAccessor()
        let model = IOSMobileAppModel(
            addSession: MobileAddSessionSnapshot(id: "empty"),
            queue: [],
            library: [],
            importedFileAccessor: importedFileAccessor,
            storageDirectoryURL: storageDirectory,
            taskRepository: repository
        )

        await model.importVideoFile(fileURL: textURL)

        XCTAssertEqual(model.addSession.input?.kind, .importedFile)
        XCTAssertEqual(model.addSession.state, .unsupported)
        XCTAssertEqual(model.addSession.error, .unsupportedOnMobile)
        XCTAssertTrue(model.lastQueueActionStatus?.contains("只支持") == true)
        XCTAssertTrue(model.queue.isEmpty)
        XCTAssertTrue(model.library.isEmpty)
        XCTAssertTrue(importedFileAccessor.accessedURLs().isEmpty)
        let savedTasks = await repository.savedTasks()
        XCTAssertTrue(savedTasks.isEmpty)
    }

    func testImportingDirectoryNamedLikeVideoFailsWithoutCreatingLibraryRecord() async throws {
        let storageDirectory = temporaryDirectory()
        let importDirectory = temporaryDirectory()
        let directoryURL = importDirectory.appendingPathComponent("Exported Package.mp4", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let repository = RecordingTaskRepository()
        let importedFileAccessor = RecordingImportedFileAccessor()
        let model = IOSMobileAppModel(
            addSession: MobileAddSessionSnapshot(id: "empty"),
            queue: [],
            library: [],
            importedFileAccessor: importedFileAccessor,
            storageDirectoryURL: storageDirectory,
            taskRepository: repository
        )

        await model.importVideoFile(fileURL: directoryURL)

        XCTAssertEqual(model.addSession.input?.kind, .importedFile)
        XCTAssertEqual(model.addSession.state, .failed)
        XCTAssertEqual(model.addSession.error, .permissionDenied)
        XCTAssertTrue(model.lastQueueActionStatus?.contains("普通视频文件") == true)
        XCTAssertTrue(model.queue.isEmpty)
        XCTAssertTrue(model.library.isEmpty)
        XCTAssertEqual(importedFileAccessor.accessedURLs().map(\.standardizedFileURL.path), [directoryURL.standardizedFileURL.path])
        let savedTasks = await repository.savedTasks()
        XCTAssertTrue(savedTasks.isEmpty)
    }

    func testImportingLocalVideoWithInsufficientStorageFailsBeforeAccessingFile() async throws {
        let storageDirectory = temporaryDirectory()
        let importDirectory = temporaryDirectory()
        let importedVideoURL = importDirectory.appendingPathComponent("Large Clip.mp4")
        try Data("large-video".utf8).write(to: importedVideoURL)
        let repository = RecordingTaskRepository()
        let importedFileAccessor = RecordingImportedFileAccessor()
        let storageChecker = RecordingImportStorageChecker(result: false)
        let model = IOSMobileAppModel(
            addSession: MobileAddSessionSnapshot(id: "empty"),
            queue: [],
            library: [],
            importedFileAccessor: importedFileAccessor,
            importStorageChecker: storageChecker,
            storageDirectoryURL: storageDirectory,
            taskRepository: repository
        )

        await model.importVideoFile(fileURL: importedVideoURL)

        XCTAssertEqual(model.addSession.input?.kind, .importedFile)
        XCTAssertEqual(model.addSession.state, .failed)
        XCTAssertEqual(model.addSession.error, .storageFull)
        XCTAssertTrue(model.lastQueueActionStatus?.contains("空间不足") == true)
        XCTAssertTrue(model.queue.isEmpty)
        XCTAssertTrue(model.library.isEmpty)
        XCTAssertTrue(importedFileAccessor.accessedURLs().isEmpty)
        XCTAssertEqual(storageChecker.requests().map(\.source.standardizedFileURL.path), [importedVideoURL.standardizedFileURL.path])
        XCTAssertEqual(storageChecker.requests().map(\.storage.standardizedFileURL.path), [storageDirectory.standardizedFileURL.path])
        let savedTasks = await repository.savedTasks()
        XCTAssertTrue(savedTasks.isEmpty)

        let encodedSession = try XCTUnwrap(String(
            data: JSONEncoder().encode(model.addSession),
            encoding: .utf8
        ))
        XCTAssertFalse(encodedSession.contains(importDirectory.path))
        XCTAssertFalse(encodedSession.contains("file://"))
    }

    func testImportingUnsafeLocalVideoNameDoesNotExposeSecretLikeFileName() async throws {
        let storageDirectory = temporaryDirectory()
        let importDirectory = temporaryDirectory()
        let unsafeURL = importDirectory.appendingPathComponent("clip-secret_token.mov")
        try Data("fake-movie-bytes".utf8).write(to: unsafeURL)
        let importedFileAccessor = RecordingImportedFileAccessor()
        let model = IOSMobileAppModel(
            addSession: MobileAddSessionSnapshot(id: "empty"),
            queue: [],
            library: [],
            importedFileAccessor: importedFileAccessor,
            storageDirectoryURL: storageDirectory
        )

        await model.importVideoFile(fileURL: unsafeURL)

        XCTAssertEqual(model.addSession.input?.kind, .importedFile)
        XCTAssertEqual(model.addSession.state, .unsupported)
        XCTAssertEqual(model.addSession.error, .unsupportedOnMobile)
        XCTAssertTrue(model.queue.isEmpty)
        XCTAssertTrue(model.library.isEmpty)
        XCTAssertTrue(importedFileAccessor.accessedURLs().isEmpty)

        let encodedSession = try XCTUnwrap(String(
            data: JSONEncoder().encode(model.addSession),
            encoding: .utf8
        ))
        XCTAssertFalse(encodedSession.contains("secret_token"))
        XCTAssertFalse(encodedSession.contains(importDirectory.path))
        XCTAssertFalse(encodedSession.contains("file://"))
    }

    func testJoiningQueueAddsSelectedVideoAndMovesToQueueTab() async {
        let model = IOSMobileAppModel(queue: [])

        model.analyzeMockURL("https://example.com/video.m3u8")
        await model.enqueueSelectedVideo()

        XCTAssertEqual(model.selectedTab, .queue)
        XCTAssertEqual(model.queue.count, 1)
        XCTAssertEqual(model.queue.first?.state, .waiting)
        XCTAssertEqual(model.queue.first?.exportProfile.subtitleMode, .translatedSubtitleFile)
        XCTAssertFalse(model.queue.first?.capabilities.supports(.videoRender) == true)
        XCTAssertFalse(model.queue.first?.capabilities.supports(.backgroundTransfer) == true)
        XCTAssertEqual(model.queue.first?.backgroundPolicy.execution, .foregroundRequired)
        XCTAssertFalse(model.queue.first?.backgroundPolicy.canResume ?? true)
    }

    func testJoiningQueueUsesSelectedBurnedInExportProfileAndRenderCapability() async throws {
        let model = IOSMobileAppModel(queue: [])

        model.selectedAddExportProfile = MobileExportProfile(subtitleMode: .burnedInSubtitle, maxRenderHeight: 1080)
        model.analyzeMockURL("https://example.com/video.m3u8")
        await model.enqueueSelectedVideo()

        let task = try XCTUnwrap(model.queue.first)
        XCTAssertEqual(task.exportProfile.subtitleMode, .burnedInSubtitle)
        XCTAssertEqual(task.exportProfile.maxRenderHeight, 1080)
        XCTAssertTrue(task.capabilities.supports(.videoRender))
        XCTAssertTrue(task.capabilities.supports(.subtitleExport))
        XCTAssertFalse(task.capabilities.supports(.backgroundTransfer))
    }

    func testJoiningQueueAddsBackgroundRenderCapabilityWhenContinuedProcessingIsAvailable() async throws {
        let model = IOSMobileAppModel(
            queue: [],
            continuedProcessingSubmitter: RecordingContinuedProcessingSubmitter(),
            renderRuntimeCapabilities: IOSRenderRuntimeCapabilities(
                supportsContinuedProcessing: true,
                supportsCheckpointedRender: false,
                continuedProcessingTimeLimitSeconds: 600
            )
        )

        model.selectedAddExportProfile = MobileExportProfile(subtitleMode: .burnedInSubtitle, maxRenderHeight: 1080)
        model.analyzeMockURL("https://example.com/video.m3u8")
        await model.enqueueSelectedVideo()

        let task = try XCTUnwrap(model.queue.first)
        XCTAssertEqual(task.exportProfile.subtitleMode, .burnedInSubtitle)
        XCTAssertTrue(task.capabilities.supports(.videoRender))
        XCTAssertTrue(task.capabilities.supports(.backgroundRender))
        XCTAssertTrue(task.capabilities.supports(.subtitleExport))
        XCTAssertFalse(task.capabilities.supports(.backgroundTransfer))
    }

    func testJoiningQueueUsesSelectedFormatAndSubtitleChoicesForDownloadRequest() async throws {
        let downloadEngine = RecordingDownloadEngine(result: MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "selected-original",
                kind: .originalMedia,
                displayName: "Selected Clip.mp4",
                storageIdentifier: "downloads/selected-clip.mp4"
            )
        ], primaryArtifactID: "selected-original"))
        let model = IOSMobileAppModel(
            addSession: MobileAddSessionSnapshot(id: "empty"),
            queue: [],
            library: [],
            mobileParser: MultiChoiceMobileParser(),
            downloadEngine: downloadEngine
        )

        await model.analyzeURL("https://cdn.example.com/selected.mp4")
        model.selectAddFormat(id: "720p")
        model.toggleAddSubtitle(id: "en")
        model.toggleAddSubtitle(id: "zh-Hans-auto")
        await model.enqueueSelectedVideo()

        let taskID = try XCTUnwrap(model.queue.first?.id)
        XCTAssertEqual(model.queue.first?.result?.primaryArtifact?.displayName, "Selectable clip · 720p")

        await model.startDownload(taskID: taskID)

        let requests = await downloadEngine.requests()
        XCTAssertEqual(requests.first?.formatID, "720p")
        XCTAssertEqual(requests.first?.subtitleIDs, ["en"])
        XCTAssertEqual(requests.first?.autoSubtitleIDs, ["zh-Hans-auto"])
    }

    func testStartDownloadUsesBackgroundStarterWhenAvailableAndLeavesTaskRecoverable() async throws {
        let registry = try BackgroundTransferRegistry(directoryURL: temporaryDirectory())
        let backgroundStarter = RecordingBackgroundDownloadStarter(registry: registry)
        let foregroundEngine = RecordingDownloadEngine(result: MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "foreground-should-not-run",
                kind: .originalMedia,
                displayName: "Foreground should not run.mp4",
                storageIdentifier: "downloads/foreground-should-not-run.mp4"
            )
        ], primaryArtifactID: "foreground-should-not-run"))
        let model = IOSMobileAppModel(
            addSession: MobileAddSessionSnapshot(id: "empty"),
            queue: [],
            library: [],
            mobileParser: MultiChoiceMobileParser(),
            downloadEngine: nil,
            backgroundDownloadStarter: backgroundStarter,
            backgroundTransferRegistry: registry
        )

        await model.analyzeURL("https://cdn.example.com/selected.mp4")
        await model.enqueueSelectedVideo()
        let taskID = try XCTUnwrap(model.queue.first?.id)

        await model.startDownload(taskID: taskID)

        let backgroundRequests = await backgroundStarter.requests()
        XCTAssertEqual(backgroundRequests.map(\.sourceURL), ["https://cdn.example.com/selected.mp4"])
        let foregroundRequests = await foregroundEngine.requests()
        XCTAssertTrue(foregroundRequests.isEmpty)

        let task = try XCTUnwrap(model.queue.first)
        XCTAssertEqual(task.state, .downloading)
        XCTAssertNil(task.error)
        XCTAssertEqual(task.backgroundPolicy.execution, .backgroundTransfer)
        XCTAssertEqual(task.backgroundPolicy.resumability, .resumable)
        XCTAssertTrue(task.backgroundPolicy.limits.contains(.systemDeferred))
        XCTAssertTrue(task.capabilities.supports(.backgroundTransfer))
        XCTAssertEqual(task.progress, MobileTaskProgress(phase: .downloading, completedUnitCount: 0))
        XCTAssertEqual(model.library, [])
        XCTAssertEqual(model.lastQueueActionStatus, "已交给系统后台下载 Selectable clip · 1080p")

        let records = try await registry.loadRecords()
        XCTAssertEqual(records.first?.taskID, taskID)
        XCTAssertEqual(records.first?.backgroundPolicy.execution, .backgroundTransfer)
    }

    func testCancellingBackgroundStartedDownloadRemovesRecoverableTransferRecord() async throws {
        let registry = try BackgroundTransferRegistry(directoryURL: temporaryDirectory())
        let backgroundStarter = RecordingBackgroundDownloadStarter(registry: registry)
        let model = IOSMobileAppModel(
            addSession: MobileAddSessionSnapshot(id: "empty"),
            queue: [],
            library: [],
            mobileParser: MultiChoiceMobileParser(),
            downloadEngine: nil,
            backgroundDownloadStarter: backgroundStarter,
            backgroundTransferRegistry: registry
        )

        await model.analyzeURL("https://cdn.example.com/selected.mp4")
        await model.enqueueSelectedVideo()
        let taskID = try XCTUnwrap(model.queue.first?.id)
        await model.startDownload(taskID: taskID)

        let recoverableTaskIDsBeforeCancel = try await registry.recoverableTaskIDs()
        XCTAssertEqual(recoverableTaskIDsBeforeCancel, [taskID])

        await model.performQueueAction(.cancel, taskID: taskID)

        let task = try XCTUnwrap(model.queue.first)
        XCTAssertEqual(task.state, .cancelled)
        let recoverableTaskIDsAfterCancel = try await registry.recoverableTaskIDs()
        let recoveryOutcomesAfterCancel = try await registry.loadRecoveryOutcomes()
        XCTAssertEqual(recoverableTaskIDsAfterCancel, [])
        XCTAssertEqual(recoveryOutcomesAfterCancel, [])
    }

    func testCancellingBackgroundStartedDownloadCancelsSystemTransferBeforeRemovingRecoveryRecord() async throws {
        let registry = try BackgroundTransferRegistry(directoryURL: temporaryDirectory())
        let backgroundStarter = RecordingBackgroundDownloadStarter(registry: registry)
        let model = IOSMobileAppModel(
            addSession: MobileAddSessionSnapshot(id: "empty"),
            queue: [],
            library: [],
            mobileParser: MultiChoiceMobileParser(),
            downloadEngine: nil,
            backgroundDownloadStarter: backgroundStarter,
            backgroundTransferRegistry: registry
        )

        await model.analyzeURL("https://cdn.example.com/selected.mp4")
        await model.enqueueSelectedVideo()
        let taskID = try XCTUnwrap(model.queue.first?.id)
        await model.startDownload(taskID: taskID)

        await model.performQueueAction(.cancel, taskID: taskID)

        let events = await backgroundStarter.events()
        XCTAssertEqual(events, [
            "start:\(taskID)",
            "cancel:\(taskID)",
            "registry-empty:false"
        ])
    }

    func testRemovingBackgroundStartedDownloadCancelsSystemTransferBeforeDroppingTask() async throws {
        let registry = try BackgroundTransferRegistry(directoryURL: temporaryDirectory())
        let backgroundStarter = RecordingBackgroundDownloadStarter(registry: registry)
        let model = IOSMobileAppModel(
            addSession: MobileAddSessionSnapshot(id: "empty"),
            queue: [],
            library: [],
            mobileParser: MultiChoiceMobileParser(),
            downloadEngine: nil,
            backgroundDownloadStarter: backgroundStarter,
            backgroundTransferRegistry: registry
        )

        await model.analyzeURL("https://cdn.example.com/selected.mp4")
        await model.enqueueSelectedVideo()
        let taskID = try XCTUnwrap(model.queue.first?.id)
        await model.startDownload(taskID: taskID)
        model.queue[0].state = .failed
        model.queue[0].error = .networkUnavailable

        await model.performQueueAction(.remove, taskID: taskID)

        let events = await backgroundStarter.events()
        XCTAssertEqual(events, [
            "start:\(taskID)",
            "cancel:\(taskID)",
            "registry-empty:false"
        ])
        XCTAssertTrue(model.queue.isEmpty)
        let remainingRecoverableTaskIDs = try await registry.recoverableTaskIDs()
        XCTAssertEqual(remainingRecoverableTaskIDs, [])
    }

    func testJoiningQueueCopiesImportedSidecarSubtitleIntoProcessableTranscriptArtifact() async throws {
        let storageDirectory = temporaryDirectory()
        let importDirectory = temporaryDirectory()
        let importedSubtitleURL = importDirectory.appendingPathComponent("Incoming English.srt")
        try """
        1
        00:00:00,000 --> 00:00:01,000
        Hello from the source subtitle.

        """.write(to: importedSubtitleURL, atomically: true, encoding: .utf8)
        let downloadEngine = RecordingDownloadEngine(result: MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "selected-original",
                kind: .originalMedia,
                displayName: "Sidecar clip.mp4",
                storageIdentifier: "downloads/sidecar-clip.mp4"
            )
        ], primaryArtifactID: "selected-original"))
        let model = IOSMobileAppModel(
            addSession: MobileAddSessionSnapshot(id: "empty"),
            queue: [],
            library: [],
            mobileParser: SidecarSubtitleMobileParser(sidecarURL: importedSubtitleURL),
            downloadEngine: downloadEngine,
            storageDirectoryURL: storageDirectory
        )

        await model.analyzeURL("https://cdn.example.com/selected.mp4")
        model.toggleAddSubtitle(id: "en-sidecar")
        await model.enqueueSelectedVideo()

        let task = try XCTUnwrap(model.queue.first)
        let transcript = try XCTUnwrap(task.result?.artifacts.first { $0.kind == .transcript })
        XCTAssertEqual(transcript.displayName, "English sidecar")
        XCTAssertEqual(transcript.storageIdentifier, "task-sidecar-video-en-sidecar-Incoming-English.srt")
        XCTAssertEqual(task.availableActions, [.startDownload, .cancel])
        let copiedURL = storageDirectory.appendingPathComponent("task-sidecar-video-en-sidecar-Incoming-English.srt")
        XCTAssertEqual(
            try String(contentsOf: copiedURL, encoding: .utf8),
            try String(contentsOf: importedSubtitleURL, encoding: .utf8)
        )

        await model.startDownload(taskID: task.id)

        let completed = try XCTUnwrap(model.queue.first)
        XCTAssertEqual(completed.result?.artifacts.map(\.kind), [.originalMedia, .transcript])
        XCTAssertTrue(completed.availableActions.contains(.exportTranslatedSubtitle))

        let encodedTask = try String(data: JSONEncoder().encode(task), encoding: .utf8)
        XCTAssertFalse(encodedTask?.contains("file://") == true)
        XCTAssertFalse(encodedTask?.contains(importedSubtitleURL.path) == true)
    }

    func testLiveDirectURLCanAttachImportedSubtitleBeforeJoiningQueue() async throws {
        let storageDirectory = temporaryDirectory()
        let importDirectory = temporaryDirectory()
        let importedSubtitleURL = importDirectory.appendingPathComponent("Manual English.srt")
        try """
        1
        00:00:00,000 --> 00:00:01,000
        Manual caption.

        """.write(to: importedSubtitleURL, atomically: true, encoding: .utf8)
        let model = IOSMobileAppModel.live(storageDirectoryURL: storageDirectory)

        await model.analyzeURL("https://cdn.example.com/videos/launch-clip.mp4")
        model.attachImportedSubtitle(fileURL: importedSubtitleURL, languageCode: "en")

        XCTAssertEqual(model.addSession.state, .ready)
        XCTAssertEqual(model.addSession.videoInfo?.subtitles.map { $0.id }, ["imported-en-Manual-English-srt"])
        guard case let .localFile(attachedSubtitleURL) = model.addSession.videoInfo?.subtitles.first?.source else {
            return XCTFail("Imported subtitles should be copied into app storage before enqueue.")
        }
        XCTAssertNotEqual(attachedSubtitleURL, importedSubtitleURL)
        XCTAssertTrue(attachedSubtitleURL.standardizedFileURL.path.hasPrefix(storageDirectory.standardizedFileURL.path + "/"))
        XCTAssertEqual(
            try String(contentsOf: attachedSubtitleURL, encoding: .utf8),
            try String(contentsOf: importedSubtitleURL, encoding: .utf8)
        )
        XCTAssertEqual(model.selectedAddSubtitleIDs, ["imported-en-Manual-English-srt"])

        await model.enqueueSelectedVideo()

        let task = try XCTUnwrap(model.queue.first)
        let transcript = try XCTUnwrap(task.result?.artifacts.first { $0.kind == .transcript })
        XCTAssertEqual(transcript.displayName, "Manual English.srt")
        XCTAssertEqual(
            transcript.storageIdentifier,
            "\(task.id)-imported-en-Manual-English-srt-add-imported-en-Manual-English-srt-Manual-English.srt"
        )
        XCTAssertEqual(
            try String(contentsOf: storageDirectory.appendingPathComponent(transcript.storageIdentifier), encoding: .utf8),
            try String(contentsOf: importedSubtitleURL, encoding: .utf8)
        )
    }

    func testImportedSubtitleUsesSecurityScopedAccessWhenCopyingFromFilesProvider() async throws {
        let storageDirectory = temporaryDirectory()
        let importDirectory = temporaryDirectory()
        let importedSubtitleURL = importDirectory.appendingPathComponent("Scoped English.srt")
        try """
        1
        00:00:00,000 --> 00:00:01,000
        Scoped caption.

        """.write(to: importedSubtitleURL, atomically: true, encoding: .utf8)
        let fileAccessor = RecordingImportedFileAccessor()
        let model = IOSMobileAppModel.live(
            storageDirectoryURL: storageDirectory,
            importedFileAccessor: fileAccessor
        )

        await model.analyzeURL("https://cdn.example.com/videos/launch-clip.mp4")
        model.attachImportedSubtitle(fileURL: importedSubtitleURL, languageCode: "en")

        XCTAssertEqual(fileAccessor.events(), [
            "start:Scoped English.srt",
            "stop:Scoped English.srt"
        ])
        XCTAssertEqual(model.addSession.videoInfo?.subtitles.map { $0.id }, ["imported-en-Scoped-English-srt"])
        guard case let .localFile(attachedSubtitleURL) = model.addSession.videoInfo?.subtitles.first?.source else {
            return XCTFail("Imported subtitle should still be copied into app-owned storage.")
        }
        XCTAssertTrue(attachedSubtitleURL.standardizedFileURL.path.hasPrefix(storageDirectory.standardizedFileURL.path + "/"))
    }

    func testImportedSubtitleRejectsSecretLikeFileNames() async throws {
        let storageDirectory = temporaryDirectory()
        let importDirectory = temporaryDirectory()
        let importedSubtitleURL = importDirectory.appendingPathComponent("access_token_SECRET.srt")
        try "1\n00:00:00,000 --> 00:00:01,000\nHidden.\n".write(
            to: importedSubtitleURL,
            atomically: true,
            encoding: .utf8
        )
        let model = IOSMobileAppModel.live(storageDirectoryURL: storageDirectory)

        await model.analyzeURL("https://cdn.example.com/videos/launch-clip.mp4")
        model.attachImportedSubtitle(fileURL: importedSubtitleURL, languageCode: "en")

        XCTAssertTrue(model.addSession.videoInfo?.subtitles.isEmpty == true)
        XCTAssertTrue(model.selectedAddSubtitleIDs.isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: storageDirectory.appendingPathComponent("access_token_SECRET.srt").path)
        )
    }

    func testQueueActionsMutateMockTaskState() async {
        let model = IOSMobileAppModel(queue: [
            MobileTaskSnapshot(id: "waiting", platform: .iOS, state: .waiting),
            MobileTaskSnapshot(id: "failed", platform: .iOS, state: .failed, error: .networkUnavailable),
            MobileTaskSnapshot(
                id: "foreground",
                platform: .iOS,
                state: .needsForegroundToContinue,
                progress: MobileTaskProgress(phase: .exporting, completedUnitCount: 1, totalUnitCount: 2),
                backgroundPolicy: MobileBackgroundPolicy(execution: .systemInterrupted, resumability: .resumable),
                error: .systemBackgroundLimit
            ),
            MobileTaskSnapshot(
                id: "completed",
                platform: .iOS,
                state: .completed,
                result: MobileTaskResult(artifacts: [
                    MobileTaskArtifact(
                        id: "video",
                        kind: .renderedVideo,
                        displayName: "video.mp4",
                        storageIdentifier: "library/video.mp4"
                    )
                ], primaryArtifactID: "video")
            )
        ])

        await model.performQueueAction(.cancel, taskID: "waiting")
        XCTAssertEqual(model.queue.first { $0.id == "waiting" }?.state, .cancelled)

        await model.performQueueAction(.retry, taskID: "failed")
        XCTAssertEqual(model.queue.first { $0.id == "failed" }?.state, .waiting)
        XCTAssertNil(model.queue.first { $0.id == "failed" }?.error)

        await model.performQueueAction(.openAppToContinue, taskID: "foreground")
        XCTAssertEqual(model.queue.first { $0.id == "foreground" }?.state, .exporting)
        XCTAssertNil(model.queue.first { $0.id == "foreground" }?.error)

        await model.performQueueAction(.shareResult, taskID: "completed")
        XCTAssertEqual(model.lastLibraryActionOutcome?.action, .share)
        XCTAssertEqual(model.lastLibraryActionOutcome?.itemID, "library-completed")
        XCTAssertEqual(model.lastLibraryActionOutcome?.presentation, .shareSheet)
        XCTAssertEqual(model.lastLibraryActionOutcome?.status, .requiresSystemPresentation)
        XCTAssertEqual(model.pendingLibraryActionCommand?.intent, .share)
        XCTAssertEqual(model.pendingLibraryActionCommand?.artifacts.map(\.displayName), ["video.mp4"])

        await model.performQueueAction(.openResult, taskID: "completed")
        XCTAssertEqual(model.lastLibraryActionOutcome?.action, .open)
        XCTAssertEqual(model.lastLibraryActionOutcome?.itemID, "library-completed")
        XCTAssertEqual(model.lastLibraryActionOutcome?.presentation, .inAppOpen)
        XCTAssertEqual(model.lastLibraryActionOutcome?.status, .prepared)
        XCTAssertEqual(model.pendingLibraryActionCommand?.intent, .open)
        XCTAssertEqual(model.pendingLibraryActionCommand?.artifacts.map(\.displayName), ["video.mp4"])
    }

    func testQueueActionRejectsStaleOrUnavailableActions() async throws {
        let downloadEngine = RecordingDownloadEngine(result: MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "unexpected",
                kind: .originalMedia,
                displayName: "Unexpected.mp4",
                storageIdentifier: "Downloads/unexpected.mp4"
            )
        ], primaryArtifactID: "unexpected"))
        let originalResult = MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "video",
                kind: .renderedVideo,
                displayName: "Done.mp4",
                storageIdentifier: "Renders/done.mp4"
            )
        ], primaryArtifactID: "video")
        let model = IOSMobileAppModel(
            queue: [
                MobileTaskSnapshot(
                    id: "completed",
                    platform: .iOS,
                    state: .completed,
                    result: originalResult
                )
            ],
            downloadEngine: downloadEngine
        )

        await model.performQueueAction(.startDownload, taskID: "completed")
        await model.performQueueAction(.retry, taskID: "completed")
        await model.performQueueAction(.pause, taskID: "completed")

        let task = try XCTUnwrap(model.queue.first { $0.id == "completed" })
        XCTAssertEqual(task.state, .completed)
        XCTAssertEqual(task.result, originalResult)
        XCTAssertEqual(model.lastQueueActionStatus, "当前状态不能执行此操作 Done.mp4")
        let requests = await downloadEngine.requests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testQueueResultActionsDoNotReportSuccessWithoutCompletedArtifact() async {
        let model = IOSMobileAppModel(queue: [
            MobileTaskSnapshot(
                id: "missing-artifact",
                platform: .iOS,
                state: .completed,
                result: MobileTaskResult()
            )
        ], library: [])

        await model.performQueueAction(.shareResult, taskID: "missing-artifact")

        XCTAssertNil(model.pendingLibraryActionCommand)
        XCTAssertNil(model.lastLibraryActionOutcome)
        XCTAssertNotEqual(model.lastQueueActionStatus, "已准备分享 missing-artifact")

        await model.performQueueAction(.openResult, taskID: "missing-artifact")

        XCTAssertNil(model.pendingLibraryActionCommand)
        XCTAssertNil(model.lastLibraryActionOutcome)
        XCTAssertNotEqual(model.lastQueueActionStatus, "已打开 missing-artifact")
    }

    func testOpenAppToContinueKeepsNonResumableInterruptedWorkForegroundBound() async {
        let model = IOSMobileAppModel(queue: [
            MobileTaskSnapshot(
                id: "non-resumable",
                platform: .iOS,
                state: .needsForegroundToContinue,
                progress: MobileTaskProgress(phase: .exporting, completedUnitCount: 1, totalUnitCount: 2),
                backgroundPolicy: MobileBackgroundPolicy(
                    execution: .systemInterrupted,
                    resumability: .nonResumable,
                    limits: [.systemInterrupted, .notResumable]
                ),
                error: .systemBackgroundLimit
            )
        ])

        await model.performQueueAction(.openAppToContinue, taskID: "non-resumable")

        let task = model.queue.first { $0.id == "non-resumable" }
        XCTAssertEqual(task?.state, .needsForegroundToContinue)
        XCTAssertEqual(task?.error, .systemBackgroundLimit)
        XCTAssertEqual(task?.backgroundPolicy.resumability, .nonResumable)
        XCTAssertEqual(model.lastQueueActionStatus, "需要重新开始或重新导出 未命名视频")
    }

    func testStartingDownloadRunsInjectedEnginePersistsTaskAndAddsLibraryRecord() async throws {
        let downloadEngine = RecordingDownloadEngine(result: MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "original-task-1",
                kind: .originalMedia,
                displayName: "Launch Clip.mp4",
                storageIdentifier: "downloads/task-1.mp4",
                byteCount: 11
            )
        ], primaryArtifactID: "original-task-1"))
        let repository = RecordingTaskRepository()
        let model = IOSMobileAppModel(
            addSession: MobileAddSessionSnapshot(id: "empty"),
            queue: [],
            library: [],
            downloadEngine: downloadEngine,
            taskRepository: repository
        )

        await model.analyzeURL("https://cdn.example.com/task-1.mp4")
        await model.enqueueSelectedVideo()
        let taskID = try XCTUnwrap(model.queue.first?.id)
        await model.startDownload(taskID: taskID)

        let task = try XCTUnwrap(model.queue.first { $0.id == taskID })
        XCTAssertEqual(task.state, .completed)
        XCTAssertEqual(task.result?.primaryArtifact?.displayName, "Launch Clip.mp4")
        XCTAssertEqual(task.progress, MobileTaskProgress(phase: .downloading, completedUnitCount: 11, totalUnitCount: 11))
        XCTAssertEqual(model.library.map(\.title), ["Launch Clip.mp4"])
        XCTAssertEqual(model.library.first?.artifacts.first?.storageIdentifier, "downloads/task-1.mp4")
        XCTAssertEqual(model.lastQueueActionStatus, "已完成 Launch Clip.mp4")

        let requests = await downloadEngine.requests()
        XCTAssertEqual(requests.map(\.id), [taskID])
        XCTAssertEqual(requests.first?.sourceURL, "https://cdn.example.com/task-1.mp4")
        let savedTasks = await repository.savedTasks()
        XCTAssertTrue(savedTasks.map(\.state).contains(.downloading))
        XCTAssertEqual(savedTasks.last?.state, .completed)
        XCTAssertTrue(savedTasks.allSatisfy { $0.error == nil })
    }

    func testQueuedSignedSourceURLCanDownloadButIsNotPersistedInTaskJSON() async throws {
        let signedURL = "https://cdn.example.com/private/launch.mp4?token=SECRET_TOKEN&X-Amz-Signature=abc123&access_token=hidden"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("moongate-ios-signed-source-\(UUID().uuidString)", isDirectory: true)
        let repository = try FileTaskRepository(directoryURL: directory)
        let downloadEngine = SuspendedDownloadEngine(result: MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "original-signed",
                kind: .originalMedia,
                displayName: "Signed Clip.mp4",
                storageIdentifier: "downloads/signed.mp4",
                byteCount: 11
            )
        ], primaryArtifactID: "original-signed"))
        let model = IOSMobileAppModel(
            addSession: MobileAddSessionSnapshot(id: "empty"),
            queue: [],
            library: [],
            downloadEngine: downloadEngine,
            taskRepository: repository
        )

        await model.analyzeURL(signedURL)
        await model.enqueueSelectedVideo()
        let taskID = try XCTUnwrap(model.queue.first?.id)

        let queuedSnapshot = try String(contentsOf: directory.appendingPathComponent("mobile-tasks.json"))
        XCTAssertFalse(queuedSnapshot.contains(signedURL))
        XCTAssertFalse(queuedSnapshot.contains("SECRET_TOKEN"))
        XCTAssertFalse(queuedSnapshot.contains("X-Amz-Signature"))
        XCTAssertFalse(queuedSnapshot.contains("access_token"))
        XCTAssertFalse(queuedSnapshot.contains("source:https://"))

        let downloadTask = Task {
            await model.startDownload(taskID: taskID)
        }
        await downloadEngine.waitUntilStarted()

        let requests = await downloadEngine.requests()
        XCTAssertEqual(requests.first?.sourceURL, signedURL)

        let stored = try String(contentsOf: directory.appendingPathComponent("mobile-tasks.json"))
        XCTAssertFalse(stored.contains(signedURL))
        XCTAssertFalse(stored.contains("SECRET_TOKEN"))
        XCTAssertFalse(stored.contains("X-Amz-Signature"))
        XCTAssertFalse(stored.contains("access_token"))
        XCTAssertFalse(stored.contains("source:https://"))

        await downloadEngine.complete()
        await downloadTask.value
    }

    func testSafeDirectHTTPSQueuedSourceRestoresFromDedicatedSourceReferenceStore() async throws {
        let sourceURL = "https://cdn.example.com/public/relaunch.mp4"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("moongate-ios-restorable-source-\(UUID().uuidString)", isDirectory: true)
        let repository = try FileTaskRepository(directoryURL: directory)
        let sourceStore = try IOSSourceReferenceStore(directoryURL: directory)
        let firstModel = IOSMobileAppModel(
            addSession: MobileAddSessionSnapshot(id: "empty"),
            queue: [],
            library: [],
            taskRepository: repository,
            sourceReferenceStore: sourceStore
        )

        await firstModel.analyzeURL(sourceURL)
        await firstModel.enqueueSelectedVideo()
        let taskID = try XCTUnwrap(firstModel.queue.first?.id)

        let queuedSnapshot = try String(contentsOf: directory.appendingPathComponent("mobile-tasks.json"))
        XCTAssertFalse(queuedSnapshot.contains(sourceURL))
        XCTAssertTrue(queuedSnapshot.contains("mobile-source:\(taskID)"))
        let queuedSources = try await sourceStore.loadSources()
        XCTAssertEqual(queuedSources[taskID], sourceURL)

        let downloadEngine = RecordingDownloadEngine(result: MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "original-restored",
                kind: .originalMedia,
                displayName: "Restored Source.mp4",
                storageIdentifier: "downloads/restored-source.mp4",
                byteCount: 11
            )
        ], primaryArtifactID: "original-restored"))
        let restoredModel = IOSMobileAppModel(
            queue: [],
            library: [],
            downloadEngine: downloadEngine,
            taskRepository: repository,
            sourceReferenceStore: sourceStore
        )

        await restoredModel.restoreQueueFromRepository()
        await restoredModel.startDownload(taskID: taskID)

        let requests = await downloadEngine.requests()
        XCTAssertEqual(requests.map(\.sourceURL), [sourceURL])
        XCTAssertEqual(restoredModel.queue.first?.state, .completed)
        XCTAssertNil(restoredModel.queue.first?.error)
        XCTAssertEqual(restoredModel.library.map(\.title), ["Restored Source.mp4"])
        let completedSnapshot = try String(contentsOf: directory.appendingPathComponent("mobile-tasks.json"))
        XCTAssertFalse(completedSnapshot.contains(sourceURL))
        let completedSources = try await sourceStore.loadSources()
        XCTAssertNil(completedSources[taskID])
    }

    func testSignedQueuedSourceDoesNotRestoreAfterRelaunchOrLeakIntoSourceReferenceStore() async throws {
        let signedURL = "https://cdn.example.com/private/relaunch.mp4?token=SECRET_TOKEN&X-Amz-Signature=abc123&access_token=hidden"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("moongate-ios-nonrestorable-signed-source-\(UUID().uuidString)", isDirectory: true)
        let repository = try FileTaskRepository(directoryURL: directory)
        let sourceStore = try IOSSourceReferenceStore(directoryURL: directory)
        let firstModel = IOSMobileAppModel(
            addSession: MobileAddSessionSnapshot(id: "empty"),
            queue: [],
            library: [],
            taskRepository: repository,
            sourceReferenceStore: sourceStore
        )

        await firstModel.analyzeURL(signedURL)
        await firstModel.enqueueSelectedVideo()
        let taskID = try XCTUnwrap(firstModel.queue.first?.id)

        let queuedSnapshot = try String(contentsOf: directory.appendingPathComponent("mobile-tasks.json"))
        XCTAssertFalse(queuedSnapshot.contains(signedURL))
        XCTAssertFalse(queuedSnapshot.contains("SECRET_TOKEN"))
        XCTAssertFalse(queuedSnapshot.contains("X-Amz-Signature"))
        XCTAssertFalse(queuedSnapshot.contains("access_token"))
        let storedSources = try await sourceStore.loadSources()
        XCTAssertNil(storedSources[taskID])

        let downloadEngine = RecordingDownloadEngine(result: MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "original-signed-relaunch",
                kind: .originalMedia,
                displayName: "Signed Relaunch.mp4",
                storageIdentifier: "downloads/signed-relaunch.mp4"
            )
        ], primaryArtifactID: "original-signed-relaunch"))
        let restoredModel = IOSMobileAppModel(
            queue: [],
            library: [],
            downloadEngine: downloadEngine,
            taskRepository: repository,
            sourceReferenceStore: sourceStore
        )

        await restoredModel.restoreQueueFromRepository()
        await restoredModel.startDownload(taskID: taskID)

        let requests = await downloadEngine.requests()
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(restoredModel.queue.first?.state, .failed)
        XCTAssertEqual(restoredModel.queue.first?.error, .sourceUnavailableAfterRelaunch)
        let completedSnapshot = try String(contentsOf: directory.appendingPathComponent("mobile-tasks.json"))
        XCTAssertFalse(completedSnapshot.contains(signedURL))
        XCTAssertFalse(completedSnapshot.contains("SECRET_TOKEN"))
        XCTAssertFalse(completedSnapshot.contains("X-Amz-Signature"))
        XCTAssertFalse(completedSnapshot.contains("access_token"))
    }

    func testFailedSignedSourceURLDoesNotPersistSecretInTaskJSON() async throws {
        let signedURL = "https://cdn.example.com/private/failure.mp4?token=SECRET_TOKEN&X-Amz-Signature=abc123&access_token=hidden"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("moongate-ios-failed-signed-source-\(UUID().uuidString)", isDirectory: true)
        let repository = try FileTaskRepository(directoryURL: directory)
        let downloadEngine = RecordingDownloadEngine(error: MobileTaskError.networkUnavailable)
        let model = IOSMobileAppModel(
            addSession: MobileAddSessionSnapshot(id: "empty"),
            queue: [],
            library: [],
            downloadEngine: downloadEngine,
            taskRepository: repository
        )

        await model.analyzeURL(signedURL)
        await model.enqueueSelectedVideo()
        let taskID = try XCTUnwrap(model.queue.first?.id)

        await model.startDownload(taskID: taskID)

        let stored = try String(contentsOf: directory.appendingPathComponent("mobile-tasks.json"))
        XCTAssertFalse(stored.contains(signedURL))
        XCTAssertFalse(stored.contains("SECRET_TOKEN"))
        XCTAssertFalse(stored.contains("X-Amz-Signature"))
        XCTAssertFalse(stored.contains("access_token"))
        XCTAssertFalse(stored.contains("source:https://"))
        XCTAssertEqual(model.queue.first?.state, .failed)
        XCTAssertEqual(model.queue.first?.error, .networkUnavailable)
    }

    func testFailedDownloadPersistsFailureWithoutCreatingLibraryRecord() async throws {
        let downloadEngine = RecordingDownloadEngine(error: MobileTaskError.networkUnavailable)
        let repository = RecordingTaskRepository()
        let model = IOSMobileAppModel(
            addSession: MobileAddSessionSnapshot(id: "empty"),
            queue: [],
            library: [],
            downloadEngine: downloadEngine,
            taskRepository: repository
        )

        await model.analyzeURL("https://cdn.example.com/task-2.mp4")
        await model.enqueueSelectedVideo()
        let taskID = try XCTUnwrap(model.queue.first?.id)
        await model.startDownload(taskID: taskID)

        let task = try XCTUnwrap(model.queue.first { $0.id == taskID })
        XCTAssertEqual(task.state, .failed)
        XCTAssertEqual(task.error, .networkUnavailable)
        XCTAssertTrue(model.library.isEmpty)
        XCTAssertTrue(model.lastQueueActionStatus?.contains("下载失败") == true)
        let savedTasks = await repository.savedTasks()
        XCTAssertTrue(savedTasks.map(\.state).contains(.downloading))
        XCTAssertEqual(savedTasks.last?.state, .failed)
    }

    func testPerformingStartDownloadQueueActionUsesDownloadEngine() async throws {
        let downloadEngine = RecordingDownloadEngine(result: MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "original-task-3",
                kind: .originalMedia,
                displayName: "Queue Clip.mp4",
                storageIdentifier: "downloads/task-3.mp4",
                byteCount: 11
            )
        ], primaryArtifactID: "original-task-3"))
        let repository = RecordingTaskRepository()
        let model = IOSMobileAppModel(
            addSession: MobileAddSessionSnapshot(id: "empty"),
            queue: [],
            library: [],
            downloadEngine: downloadEngine,
            taskRepository: repository
        )

        await model.analyzeURL("https://cdn.example.com/task-3.mp4")
        await model.enqueueSelectedVideo()
        let taskID = try XCTUnwrap(model.queue.first?.id)
        await model.performQueueAction(.startDownload, taskID: taskID)

        let task = try XCTUnwrap(model.queue.first { $0.id == taskID })
        XCTAssertEqual(task.state, .completed)
        XCTAssertEqual(model.library.map(\.title), ["Queue Clip.mp4"])
        let requests = await downloadEngine.requests()
        XCTAssertEqual(requests.map(\.id), [taskID])
    }

    func testExportingTranslatedSubtitleUsesProcessorUpdatesQueueAndLibrary() async throws {
        let processor = RecordingSubtitleProcessor(result: MobileTaskArtifact(
            id: "subtitle-translated",
            kind: .translatedSubtitleFile,
            displayName: "Queue Clip.zh.srt",
            storageIdentifier: "Subtitles/queue.zh.srt",
            byteCount: 128
        ))
        let repository = RecordingTaskRepository()
        let translation = MobileTranslationResult(segments: [
            MobileTranslationSegment(id: "1", startTime: "00:00:00,000", endTime: "00:00:01,000", text: "你好")
        ])
        let model = IOSMobileAppModel(
            queue: [
                MobileTaskSnapshot(
                    id: "task-subtitle",
                    platform: .iOS,
                    state: .completed,
                    exportProfile: MobileExportProfile(subtitleMode: .translatedSubtitleFile),
                    capabilities: MobileProcessingCapabilities(
                        platform: .iOS,
                        supportedCapabilities: [.translation, .subtitleExport]
                    ),
                    result: MobileTaskResult(artifacts: [
                        MobileTaskArtifact(
                            id: "original",
                            kind: .originalMedia,
                            displayName: "Queue Clip.mp4",
                            storageIdentifier: "Downloads/queue.mp4"
                        ),
                        MobileTaskArtifact(
                            id: "transcript",
                            kind: .transcript,
                            displayName: "Queue Clip.en.srt",
                            storageIdentifier: "queue.en.srt"
                        )
                    ], primaryArtifactID: "original")
                )
            ],
            library: [],
            subtitleProcessor: processor,
            taskRepository: repository
        )

        await model.applyTranslationResult(translation, toTaskID: "task-subtitle")
        await model.performQueueAction(.exportTranslatedSubtitle, taskID: "task-subtitle")

        let task = try XCTUnwrap(model.queue.first { $0.id == "task-subtitle" })
        XCTAssertEqual(task.state, .completed)
        XCTAssertTrue(task.result?.artifacts.contains { $0.kind == .translatedSubtitleFile } == true)
        XCTAssertEqual(task.result?.artifacts.last?.storageIdentifier, "Subtitles/queue.zh.srt")
        XCTAssertEqual(model.library.map(\.title), ["Queue Clip.mp4"])
        XCTAssertEqual(model.library.first?.artifacts.map(\.kind), [.originalMedia, .transcript, .translatedSubtitleFile])
        XCTAssertEqual(model.lastQueueActionStatus, "已生成字幕 Queue Clip.zh.srt")

        let requests = await processor.requests()
        XCTAssertEqual(requests.map(\.sourceSubtitle.id), ["transcript"])
        XCTAssertEqual(requests.first?.translation, translation)
        XCTAssertEqual(requests.first?.exportProfile.subtitleMode, .translatedSubtitleFile)
        let savedTasks = await repository.savedTasks()
        XCTAssertEqual(savedTasks.first?.state, .translating)
        XCTAssertEqual(savedTasks.last?.state, .completed)
    }

    func testExportingSoftSubtitleUsesProcessorUpdatesQueueAndLibrary() async throws {
        let processor = RecordingSubtitleProcessor(result: MobileTaskArtifact(
            id: "subtitle-soft",
            kind: .softSubtitle,
            displayName: "Queue Clip.soft-subtitles",
            storageIdentifier: "SoftSubtitles/queue.soft-subtitles",
            byteCount: 256
        ))
        let repository = RecordingTaskRepository()
        let translation = MobileTranslationResult(segments: [
            MobileTranslationSegment(id: "1", startTime: "00:00:00,000", endTime: "00:00:01,000", text: "你好")
        ])
        let model = IOSMobileAppModel(
            queue: [
                MobileTaskSnapshot(
                    id: "task-soft-subtitle",
                    platform: .iOS,
                    state: .completed,
                    exportProfile: MobileExportProfile(subtitleMode: .softSubtitle),
                    capabilities: MobileProcessingCapabilities(
                        platform: .iOS,
                        supportedCapabilities: [.translation, .subtitleExport]
                    ),
                    result: MobileTaskResult(artifacts: [
                        MobileTaskArtifact(
                            id: "original",
                            kind: .originalMedia,
                            displayName: "Queue Clip.mp4",
                            storageIdentifier: "Downloads/queue.mp4"
                        ),
                        MobileTaskArtifact(
                            id: "transcript",
                            kind: .transcript,
                            displayName: "Queue Clip.en.srt",
                            storageIdentifier: "queue.en.srt"
                        )
                    ], primaryArtifactID: "original")
                )
            ],
            library: [],
            subtitleProcessor: processor,
            taskRepository: repository
        )

        XCTAssertEqual(model.queue.first?.availableActions.first, .exportTranslatedSubtitle)

        await model.applyTranslationResult(translation, toTaskID: "task-soft-subtitle")
        await model.performQueueAction(.exportTranslatedSubtitle, taskID: "task-soft-subtitle")

        let task = try XCTUnwrap(model.queue.first { $0.id == "task-soft-subtitle" })
        XCTAssertEqual(task.state, .completed)
        XCTAssertEqual(task.result?.artifacts.map(\.kind), [.originalMedia, .transcript, .softSubtitle])
        XCTAssertEqual(task.result?.artifacts.last?.storageIdentifier, "SoftSubtitles/queue.soft-subtitles")
        XCTAssertEqual(model.library.map(\.title), ["Queue Clip.mp4"])
        XCTAssertEqual(model.library.first?.artifacts.map(\.kind), [.originalMedia, .transcript, .softSubtitle])
        XCTAssertEqual(model.lastQueueActionStatus, "已生成软字幕 Queue Clip.soft-subtitles")

        let requests = await processor.requests()
        XCTAssertEqual(requests.map(\.sourceSubtitle.id), ["transcript"])
        XCTAssertEqual(requests.first?.translation, translation)
        XCTAssertEqual(requests.first?.exportProfile.subtitleMode, .softSubtitle)
        let savedTasks = await repository.savedTasks()
        XCTAssertEqual(savedTasks.first?.state, .translating)
        XCTAssertEqual(savedTasks.last?.state, .completed)
    }

    func testExportingRenderedVideoUsesRenderExporterUpdatesQueueAndLibrary() async throws {
        let renderer = RecordingRenderExporter(result: MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "rendered-video",
                kind: .renderedVideo,
                displayName: "Queue Clip.rendered.mp4",
                storageIdentifier: "Renders/queue.rendered.mp4",
                byteCount: 2048
            )
        ], primaryArtifactID: "rendered-video"))
        let repository = RecordingTaskRepository()
        let model = IOSMobileAppModel(
            queue: [
                MobileTaskSnapshot(
                    id: "task-render",
                    platform: .iOS,
                    state: .completed,
                    exportProfile: MobileExportProfile(subtitleMode: .burnedInSubtitle),
                    capabilities: MobileProcessingCapabilities(
                        platform: .iOS,
                        supportedCapabilities: [.videoRender],
                        maxRenderHeight: 1080
                    ),
                    result: MobileTaskResult(artifacts: [
                        MobileTaskArtifact(
                            id: "original",
                            kind: .originalMedia,
                            displayName: "Queue Clip.mp4",
                            storageIdentifier: "Downloads/queue.mp4"
                        ),
                        MobileTaskArtifact(
                            id: "subtitle",
                            kind: .translatedSubtitleFile,
                            displayName: "Queue Clip.zh.srt",
                            storageIdentifier: "Subtitles/queue.zh.srt"
                        )
                    ], primaryArtifactID: "original")
                )
            ],
            library: [],
            renderExporter: renderer,
            taskRepository: repository
        )

        XCTAssertEqual(model.queue.first?.availableActions.first, .exportRenderedVideo)

        await model.performQueueAction(.exportRenderedVideo, taskID: "task-render")

        let task = try XCTUnwrap(model.queue.first { $0.id == "task-render" })
        XCTAssertEqual(task.state, .completed)
        XCTAssertEqual(task.result?.primaryArtifact?.kind, .renderedVideo)
        XCTAssertEqual(task.result?.artifacts.map(\.kind), [.originalMedia, .translatedSubtitleFile, .renderedVideo])
        XCTAssertEqual(model.library.map(\.title), ["Queue Clip.rendered.mp4"])
        XCTAssertEqual(model.library.first?.artifacts.map(\.kind), [.originalMedia, .translatedSubtitleFile, .renderedVideo])
        XCTAssertEqual(model.lastQueueActionStatus, "已导出视频 Queue Clip.rendered.mp4")

        let requests = await renderer.requests()
        XCTAssertEqual(requests.map(\.sourceMedia.id), ["original"])
        XCTAssertEqual(requests.first?.subtitles.map(\.id), ["subtitle"])
        XCTAssertEqual(requests.first?.exportProfile.subtitleMode, .burnedInSubtitle)
        let savedTasks = await repository.savedTasks()
        XCTAssertEqual(savedTasks.first?.state, .exporting)
        XCTAssertEqual(savedTasks.first?.backgroundPolicy.execution, .foregroundRequired)
        XCTAssertEqual(savedTasks.first?.backgroundPolicy.resumability, .nonResumable)
        XCTAssertEqual(savedTasks.first?.availableActions, [.cancel])
        XCTAssertEqual(savedTasks.last?.state, .completed)
    }

    func testFailedRenderedVideoExportKeepsCompletedLibraryRecordForOriginalMedia() async throws {
        let storageDirectory = temporaryDirectory()
        let downloadDirectory = storageDirectory.appendingPathComponent("Downloads", isDirectory: true)
        let subtitleDirectory = storageDirectory.appendingPathComponent("Subtitles", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: subtitleDirectory, withIntermediateDirectories: true)
        try Data("downloaded-video".utf8).write(to: downloadDirectory.appendingPathComponent("queue.mp4"))
        try "1\n00:00:00,000 --> 00:00:01,000\n你好\n".write(
            to: subtitleDirectory.appendingPathComponent("queue.zh.srt"),
            atomically: true,
            encoding: .utf8
        )
        let renderer = RecordingRenderExporter(error: MobileTaskError.exportFailed)
        let repository = RecordingTaskRepository()
        let originalResult = MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "original",
                kind: .originalMedia,
                displayName: "Queue Clip.mp4",
                storageIdentifier: "Downloads/queue.mp4"
            ),
            MobileTaskArtifact(
                id: "subtitle",
                kind: .translatedSubtitleFile,
                displayName: "Queue Clip.zh.srt",
                storageIdentifier: "Subtitles/queue.zh.srt"
            )
        ], primaryArtifactID: "original")
        let model = IOSMobileAppModel(
            queue: [
                MobileTaskSnapshot(
                    id: "task-render-failure",
                    platform: .iOS,
                    state: .completed,
                    exportProfile: MobileExportProfile(subtitleMode: .burnedInSubtitle),
                    capabilities: MobileProcessingCapabilities(
                        platform: .iOS,
                        supportedCapabilities: [.videoRender],
                        maxRenderHeight: 1080
                    ),
                    result: originalResult
                )
            ],
            library: [],
            renderExporter: renderer,
            storageDirectoryURL: storageDirectory,
            taskRepository: repository
        )

        await model.performQueueAction(.exportRenderedVideo, taskID: "task-render-failure")

        let task = try XCTUnwrap(model.queue.first { $0.id == "task-render-failure" })
        XCTAssertEqual(task.state, .completed)
        XCTAssertEqual(task.result, originalResult)
        XCTAssertEqual(task.error, .exportFailed)
        XCTAssertEqual(model.library.map(\.title), ["Queue Clip.mp4"])
        XCTAssertEqual(model.library.first?.sourceTaskID, "task-render-failure")
        XCTAssertEqual(model.library.first?.artifacts.map(\.kind), [.originalMedia, .translatedSubtitleFile])
        XCTAssertEqual(model.lastQueueActionStatus, "视频导出失败 Queue Clip.mp4")
        let savedTasks = await repository.savedTasks()
        XCTAssertEqual(savedTasks.first?.state, .exporting)
        XCTAssertEqual(savedTasks.last?.state, .completed)
        XCTAssertEqual(savedTasks.last?.error, .exportFailed)
    }

    func testRetryingFailedRenderedVideoExportReplacesOriginalLibraryRecordWithRenderedVideo() async throws {
        let storageDirectory = temporaryDirectory()
        let downloadDirectory = storageDirectory.appendingPathComponent("Downloads", isDirectory: true)
        let subtitleDirectory = storageDirectory.appendingPathComponent("Subtitles", isDirectory: true)
        let renderDirectory = storageDirectory.appendingPathComponent("Renders", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: subtitleDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: renderDirectory, withIntermediateDirectories: true)
        try Data("downloaded-video".utf8).write(to: downloadDirectory.appendingPathComponent("queue.mp4"))
        try "1\n00:00:00,000 --> 00:00:01,000\n你好\n".write(
            to: subtitleDirectory.appendingPathComponent("queue.zh.srt"),
            atomically: true,
            encoding: .utf8
        )
        try Data("rendered-video".utf8).write(to: renderDirectory.appendingPathComponent("queue.rendered.mp4"))
        let renderer = SequencedRenderExporter(outcomes: [
            .failure(MobileTaskError.exportFailed),
            .success(MobileTaskResult(artifacts: [
                MobileTaskArtifact(
                    id: "rendered-video",
                    kind: .renderedVideo,
                    displayName: "Queue Clip.rendered.mp4",
                    storageIdentifier: "Renders/queue.rendered.mp4",
                    byteCount: 2048
                )
            ], primaryArtifactID: "rendered-video"))
        ])
        let repository = RecordingTaskRepository()
        let originalResult = MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "original",
                kind: .originalMedia,
                displayName: "Queue Clip.mp4",
                storageIdentifier: "Downloads/queue.mp4"
            ),
            MobileTaskArtifact(
                id: "subtitle",
                kind: .translatedSubtitleFile,
                displayName: "Queue Clip.zh.srt",
                storageIdentifier: "Subtitles/queue.zh.srt"
            )
        ], primaryArtifactID: "original")
        let model = IOSMobileAppModel(
            queue: [
                MobileTaskSnapshot(
                    id: "task-render-retry-after-failure",
                    platform: .iOS,
                    state: .completed,
                    exportProfile: MobileExportProfile(subtitleMode: .burnedInSubtitle),
                    capabilities: MobileProcessingCapabilities(
                        platform: .iOS,
                        supportedCapabilities: [.videoRender],
                        maxRenderHeight: 1080
                    ),
                    result: originalResult
                )
            ],
            library: [],
            renderExporter: renderer,
            storageDirectoryURL: storageDirectory,
            taskRepository: repository
        )

        await model.performQueueAction(.exportRenderedVideo, taskID: "task-render-retry-after-failure")
        XCTAssertEqual(model.queue.first?.state, .completed)
        XCTAssertEqual(model.queue.first?.error, .exportFailed)
        XCTAssertEqual(model.library.map(\.title), ["Queue Clip.mp4"])

        await model.performQueueAction(.exportRenderedVideo, taskID: "task-render-retry-after-failure")

        let task = try XCTUnwrap(model.queue.first { $0.id == "task-render-retry-after-failure" })
        XCTAssertEqual(task.state, .completed)
        XCTAssertNil(task.error)
        XCTAssertEqual(task.result?.primaryArtifact?.kind, .renderedVideo)
        XCTAssertEqual(task.result?.artifacts.map(\.kind), [.originalMedia, .translatedSubtitleFile, .renderedVideo])
        XCTAssertEqual(model.library.map(\.title), ["Queue Clip.rendered.mp4"])
        XCTAssertEqual(model.library.first?.sourceTaskID, "task-render-retry-after-failure")
        XCTAssertEqual(model.library.first?.artifacts.map(\.kind), [.originalMedia, .translatedSubtitleFile, .renderedVideo])
        XCTAssertEqual(model.library.count, 1)
        XCTAssertEqual(model.lastQueueActionStatus, "已导出视频 Queue Clip.rendered.mp4")

        let requests = await renderer.requests()
        XCTAssertEqual(requests.count, 2)
        let savedTasks = await repository.savedTasks()
        XCTAssertTrue(savedTasks.contains { $0.state == .completed && $0.error == .exportFailed })
        XCTAssertEqual(savedTasks.last?.state, .completed)
        XCTAssertEqual(savedTasks.last?.error, nil)
    }

    func testExportingRenderedVideoSubmitsContinuedProcessingRequestWithoutStartingForegroundRender() async throws {
        let renderer = RecordingRenderExporter(result: MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "rendered-video",
                kind: .renderedVideo,
                displayName: "Background Queue Clip.rendered.mp4",
                storageIdentifier: "Renders/background-queue.rendered.mp4",
                byteCount: 2048
            )
        ], primaryArtifactID: "rendered-video"))
        let repository = RecordingTaskRepository()
        let submitter = RecordingContinuedProcessingSubmitter()
        let model = IOSMobileAppModel(
            queue: [
                MobileTaskSnapshot(
                    id: "task-render-background",
                    platform: .iOS,
                    state: .completed,
                    exportProfile: MobileExportProfile(subtitleMode: .burnedInSubtitle),
                    capabilities: MobileProcessingCapabilities(
                        platform: .iOS,
                        supportedCapabilities: [.videoRender, .backgroundRender],
                        maxRenderHeight: 1080
                    ),
                    result: MobileTaskResult(artifacts: [
                        MobileTaskArtifact(
                            id: "original",
                            kind: .originalMedia,
                            displayName: "Background Queue Clip.mp4",
                            storageIdentifier: "Downloads/background-queue.mp4"
                        ),
                        MobileTaskArtifact(
                            id: "subtitle",
                            kind: .translatedSubtitleFile,
                            displayName: "Background Queue Clip.zh.srt",
                            storageIdentifier: "Subtitles/background-queue.zh.srt"
                        )
                    ], primaryArtifactID: "original")
                )
            ],
            library: [],
            renderExporter: renderer,
            continuedProcessingSubmitter: submitter,
            continuedProcessingScheduler: IOSContinuedProcessingRenderScheduler(
                bundleIdentifier: "com.local.videodownloader.ios"
            ),
            renderRuntimeCapabilities: IOSRenderRuntimeCapabilities(
                supportsContinuedProcessing: true,
                supportsCheckpointedRender: false,
                continuedProcessingTimeLimitSeconds: 600
            ),
            taskRepository: repository
        )

        await model.performQueueAction(.exportRenderedVideo, taskID: "task-render-background")

        let submittedDescriptors = await submitter.descriptors()
        XCTAssertEqual(submittedDescriptors.map(\.identifier), ["com.local.videodownloader.ios.render.task-render-background"])
        XCTAssertEqual(submittedDescriptors.first?.title, "导出视频")
        XCTAssertEqual(submittedDescriptors.first?.subtitle, "Background Queue Clip.mp4")
        XCTAssertEqual(submittedDescriptors.first?.backgroundPolicy.execution, .continuedProcessing)
        XCTAssertTrue(submittedDescriptors.first?.backgroundPolicy.limits.contains(.userVisibleNotificationRequired) == true)

        let savedTasks = await repository.savedTasks()
        XCTAssertEqual(savedTasks.first?.state, .exporting)
        XCTAssertEqual(savedTasks.first?.backgroundPolicy.execution, .continuedProcessing)
        XCTAssertTrue(savedTasks.first?.backgroundPolicy.limits.contains(.userVisibleNotificationRequired) == true)
        XCTAssertEqual(savedTasks.last?.state, .exporting)
        XCTAssertEqual(model.queue.first?.state, .exporting)
        XCTAssertEqual(model.queue.first?.backgroundPolicy.execution, .continuedProcessing)
        XCTAssertEqual(model.queue.first?.result?.primaryArtifact?.kind, .originalMedia)
        XCTAssertTrue(model.library.isEmpty)

        let foregroundRequests = await renderer.requests()
        XCTAssertTrue(foregroundRequests.isEmpty)
    }

    func testCancellingActiveRenderRestoresCompletedArtifactsAndIgnoresLateCompletion() async throws {
        let renderer = SuspendedRenderExporter(result: MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "rendered-video",
                kind: .renderedVideo,
                displayName: "Cancelled Render.rendered.mp4",
                storageIdentifier: "Renders/cancelled.rendered.mp4",
                byteCount: 2048
            )
        ], primaryArtifactID: "rendered-video"))
        let repository = RecordingTaskRepository()
        let originalResult = MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "original",
                kind: .originalMedia,
                displayName: "Cancelled Render.mp4",
                storageIdentifier: "Downloads/cancelled-render.mp4"
            ),
            MobileTaskArtifact(
                id: "subtitle",
                kind: .translatedSubtitleFile,
                displayName: "Cancelled Render.zh.srt",
                storageIdentifier: "Subtitles/cancelled-render.zh.srt"
            )
        ], primaryArtifactID: "original")
        let model = IOSMobileAppModel(
            queue: [
                MobileTaskSnapshot(
                    id: "task-render-cancel",
                    platform: .iOS,
                    state: .completed,
                    exportProfile: MobileExportProfile(subtitleMode: .burnedInSubtitle),
                    capabilities: MobileProcessingCapabilities(
                        platform: .iOS,
                        supportedCapabilities: [.videoRender],
                        maxRenderHeight: 1080
                    ),
                    result: originalResult
                )
            ],
            library: [],
            renderExporter: renderer,
            taskRepository: repository
        )

        let exportTask = Task {
            await model.performQueueAction(.exportRenderedVideo, taskID: "task-render-cancel")
        }
        await renderer.waitUntilStarted()

        var task = try XCTUnwrap(model.queue.first { $0.id == "task-render-cancel" })
        XCTAssertEqual(task.state, .exporting)
        XCTAssertEqual(task.backgroundPolicy.resumability, .nonResumable)
        XCTAssertEqual(task.availableActions, [.cancel])

        await model.performQueueAction(.cancel, taskID: "task-render-cancel")
        await renderer.complete()
        await exportTask.value

        task = try XCTUnwrap(model.queue.first { $0.id == "task-render-cancel" })
        XCTAssertEqual(task.state, .cancelled)
        XCTAssertEqual(task.result, originalResult)
        XCTAssertTrue(model.library.isEmpty)
        let storedTasks = try await repository.loadTasks()
        XCTAssertEqual(storedTasks.first?.state, .cancelled)
        XCTAssertEqual(storedTasks.first?.result, originalResult)
    }

    func testCancellingActiveRenderExportCancelsUnderlyingExporter() async throws {
        let renderer = CancellableSuspendedRenderExporter(result: MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "rendered-video-underlying-cancel",
                kind: .renderedVideo,
                displayName: "Cancelled Underlying Render.rendered.mp4",
                storageIdentifier: "Renders/cancelled-underlying.rendered.mp4",
                byteCount: 2048
            )
        ], primaryArtifactID: "rendered-video-underlying-cancel"))
        let repository = RecordingTaskRepository()
        let originalResult = MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "original",
                kind: .originalMedia,
                displayName: "Cancelled Underlying Render.mp4",
                storageIdentifier: "Downloads/cancelled-underlying-render.mp4"
            ),
            MobileTaskArtifact(
                id: "subtitle",
                kind: .translatedSubtitleFile,
                displayName: "Cancelled Underlying Render.zh.srt",
                storageIdentifier: "Subtitles/cancelled-underlying-render.zh.srt"
            )
        ], primaryArtifactID: "original")
        let model = IOSMobileAppModel(
            queue: [
                MobileTaskSnapshot(
                    id: "task-render-cancel-underlying",
                    platform: .iOS,
                    state: .completed,
                    exportProfile: MobileExportProfile(subtitleMode: .burnedInSubtitle),
                    capabilities: MobileProcessingCapabilities(
                        platform: .iOS,
                        supportedCapabilities: [.videoRender],
                        maxRenderHeight: 1080
                    ),
                    result: originalResult
                )
            ],
            library: [],
            renderExporter: renderer,
            taskRepository: repository
        )

        let exportTask = Task {
            await model.performQueueAction(.exportRenderedVideo, taskID: "task-render-cancel-underlying")
        }
        await renderer.waitUntilStarted()

        await model.performQueueAction(.cancel, taskID: "task-render-cancel-underlying")
        let observedCancellation = try await waitForCondition("render exporter to observe cancellation") {
            await renderer.didObserveCancellation()
        }
        if !observedCancellation {
            await renderer.complete()
        }
        await exportTask.value

        XCTAssertTrue(observedCancellation)
        let task = try XCTUnwrap(model.queue.first { $0.id == "task-render-cancel-underlying" })
        XCTAssertEqual(task.state, .cancelled)
        XCTAssertEqual(task.result, originalResult)
        XCTAssertTrue(model.library.isEmpty)
        let storedTasks = try await repository.loadTasks()
        XCTAssertEqual(storedTasks.first?.state, .cancelled)
        XCTAssertEqual(storedTasks.first?.result, originalResult)
    }

    func testRepeatedRenderExportDoesNotOverwriteActiveExportCompletion() async throws {
        let renderer = SuspendedRenderExporter(result: MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "rendered-video",
                kind: .renderedVideo,
                displayName: "Queue Clip.rendered.mp4",
                storageIdentifier: "Renders/queue.rendered.mp4",
                byteCount: 2048
            )
        ], primaryArtifactID: "rendered-video"))
        let repository = RecordingTaskRepository()
        let model = IOSMobileAppModel(
            queue: [
                MobileTaskSnapshot(
                    id: "task-render-repeat",
                    platform: .iOS,
                    state: .completed,
                    exportProfile: MobileExportProfile(subtitleMode: .burnedInSubtitle),
                    capabilities: MobileProcessingCapabilities(
                        platform: .iOS,
                        supportedCapabilities: [.videoRender],
                        maxRenderHeight: 1080
                    ),
                    result: MobileTaskResult(artifacts: [
                        MobileTaskArtifact(
                            id: "original",
                            kind: .originalMedia,
                            displayName: "Queue Clip.mp4",
                            storageIdentifier: "Downloads/queue.mp4"
                        ),
                        MobileTaskArtifact(
                            id: "subtitle",
                            kind: .translatedSubtitleFile,
                            displayName: "Queue Clip.zh.srt",
                            storageIdentifier: "Subtitles/queue.zh.srt"
                        )
                    ], primaryArtifactID: "original")
                )
            ],
            library: [],
            renderExporter: renderer,
            taskRepository: repository
        )

        let exportTask = Task {
            await model.performQueueAction(.exportRenderedVideo, taskID: "task-render-repeat")
        }
        await renderer.waitUntilStarted()

        await model.performQueueAction(.exportRenderedVideo, taskID: "task-render-repeat")

        var task = try XCTUnwrap(model.queue.first { $0.id == "task-render-repeat" })
        XCTAssertEqual(task.state, .exporting)
        XCTAssertNil(task.error)
        XCTAssertEqual(model.lastQueueActionStatus, "当前状态不能执行此操作 Queue Clip.mp4")

        await renderer.complete()
        await exportTask.value

        task = try XCTUnwrap(model.queue.first { $0.id == "task-render-repeat" })
        XCTAssertEqual(task.state, .completed)
        XCTAssertNil(task.error)
        XCTAssertEqual(task.result?.primaryArtifact?.kind, .renderedVideo)
        XCTAssertEqual(model.library.map(\.title), ["Queue Clip.rendered.mp4"])

        let requests = await renderer.requests()
        XCTAssertEqual(requests.count, 1)
        let savedTasks = await repository.savedTasks()
        XCTAssertTrue(savedTasks.map(\.state).contains(.exporting))
        XCTAssertEqual(savedTasks.last?.state, .completed)
        XCTAssertNil(savedTasks.last?.error)
    }

    func testExportingTranslatedSubtitleTranslatesTranscriptBeforeProcessing() async throws {
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("moongate-ios-subtitle-provider-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try """
        1
        00:00:00,000 --> 00:00:01,000
        Hello

        2
        00:00:01,000 --> 00:00:02,000
        world

        """.write(to: storageDirectory.appendingPathComponent("queue.en.srt"), atomically: true, encoding: .utf8)
        let translationProvider = RecordingTranslationProvider(result: MobileTranslationResult(segments: [
            MobileTranslationSegment(id: "1", startTime: "00:00:00,000", endTime: "00:00:01,000", text: "你好"),
            MobileTranslationSegment(id: "2", startTime: "00:00:01,000", endTime: "00:00:02,000", text: "世界")
        ]))
        let processor = RecordingSubtitleProcessor(result: MobileTaskArtifact(
            id: "subtitle-translated",
            kind: .translatedSubtitleFile,
            displayName: "Queue Clip.zh.srt",
            storageIdentifier: "Subtitles/queue.zh.srt"
        ))
        let model = IOSMobileAppModel(
            queue: [
                MobileTaskSnapshot(
                    id: "task-subtitle-provider",
                    platform: .iOS,
                    state: .completed,
                    exportProfile: MobileExportProfile(subtitleMode: .translatedSubtitleFile),
                    result: MobileTaskResult(artifacts: [
                        MobileTaskArtifact(
                            id: "original",
                            kind: .originalMedia,
                            displayName: "Queue Clip.mp4",
                            storageIdentifier: "Downloads/queue.mp4"
                        ),
                        MobileTaskArtifact(
                            id: "transcript",
                            kind: .transcript,
                            displayName: "Queue Clip.en.srt",
                            storageIdentifier: "queue.en.srt"
                        )
                    ], primaryArtifactID: "original")
                )
            ],
            library: [],
            translationProvider: translationProvider,
            subtitleProcessor: processor,
            storageDirectoryURL: storageDirectory
        )

        await model.performQueueAction(.exportTranslatedSubtitle, taskID: "task-subtitle-provider")

        let translationRequests = await translationProvider.requests()
        XCTAssertEqual(translationRequests.count, 1)
        XCTAssertEqual(translationRequests.first?.context.targetLanguage, "zh-Hans")
        XCTAssertEqual(translationRequests.first?.segments.map(\.id), ["1", "2"])
        XCTAssertEqual(translationRequests.first?.segments.map(\.text), ["Hello", "world"])
        let processorRequests = await processor.requests()
        XCTAssertEqual(processorRequests.first?.translation.segments.map(\.text), ["你好", "世界"])
        XCTAssertEqual(model.queue.first?.result?.artifacts.last?.kind, .translatedSubtitleFile)
        XCTAssertEqual(model.lastQueueActionStatus, "已生成字幕 Queue Clip.zh.srt")
    }

    func testExportingTranslatedSubtitleReadsTranscriptFromAppOwnedSubdirectoryIdentifier() async throws {
        let storageDirectory = temporaryDirectory()
        let subtitleDirectory = storageDirectory.appendingPathComponent("Subtitles", isDirectory: true)
        try FileManager.default.createDirectory(at: subtitleDirectory, withIntermediateDirectories: true)
        try """
        1
        00:00:00,000 --> 00:00:01,000
        Hello

        """.write(
            to: subtitleDirectory.appendingPathComponent("queue.en.srt", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let translationProvider = RecordingTranslationProvider(result: MobileTranslationResult(segments: [
            MobileTranslationSegment(id: "1", startTime: "00:00:00,000", endTime: "00:00:01,000", text: "你好")
        ]))
        let processor = RecordingSubtitleProcessor(result: MobileTaskArtifact(
            id: "subtitle-translated",
            kind: .translatedSubtitleFile,
            displayName: "Queue Clip.zh.srt",
            storageIdentifier: "Subtitles/queue.zh.srt"
        ))
        let model = IOSMobileAppModel(
            queue: [
                MobileTaskSnapshot(
                    id: "task-subtitle-subdirectory",
                    platform: .iOS,
                    state: .completed,
                    exportProfile: MobileExportProfile(subtitleMode: .translatedSubtitleFile),
                    result: MobileTaskResult(artifacts: [
                        MobileTaskArtifact(
                            id: "original",
                            kind: .originalMedia,
                            displayName: "Queue Clip.mp4",
                            storageIdentifier: "Downloads/queue.mp4"
                        ),
                        MobileTaskArtifact(
                            id: "transcript",
                            kind: .transcript,
                            displayName: "Queue Clip.en.srt",
                            storageIdentifier: "Subtitles/queue.en.srt"
                        )
                    ], primaryArtifactID: "original")
                )
            ],
            library: [],
            translationProvider: translationProvider,
            subtitleProcessor: processor,
            storageDirectoryURL: storageDirectory
        )

        await model.performQueueAction(.exportTranslatedSubtitle, taskID: "task-subtitle-subdirectory")

        let translationRequests = await translationProvider.requests()
        XCTAssertEqual(translationRequests.count, 1)
        XCTAssertEqual(translationRequests.first?.segments.map(\.text), ["Hello"])
        XCTAssertEqual(model.queue.first?.result?.artifacts.last?.storageIdentifier, "Subtitles/queue.zh.srt")
        XCTAssertEqual(model.lastQueueActionStatus, "已生成字幕 Queue Clip.zh.srt")
    }

    func testExportingExistingChineseSubtitleBypassesTranslationProviderAndKeepsLibraryRecord() async throws {
        let storageDirectory = temporaryDirectory()
        let subtitleDirectory = storageDirectory.appendingPathComponent("Subtitles", isDirectory: true)
        try FileManager.default.createDirectory(at: subtitleDirectory, withIntermediateDirectories: true)
        try """
        1
        00:00:00,000 --> 00:00:01,000
        已有中文字幕。

        2
        00:00:01,000 --> 00:00:02,000
        不需要云端翻译。

        """.write(
            to: subtitleDirectory.appendingPathComponent("queue.zh-Hans.srt", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let translationProvider = RecordingTranslationProvider(error: MobileTranslationProviderError.missingCredential)
        let processor = RecordingSubtitleProcessor(result: MobileTaskArtifact(
            id: "subtitle-existing-zh",
            kind: .translatedSubtitleFile,
            displayName: "Queue Clip.zh-Hans.srt",
            storageIdentifier: "Subtitles/queue.zh-Hans.exported.srt"
        ))
        let model = IOSMobileAppModel(
            queue: [
                MobileTaskSnapshot(
                    id: "task-existing-chinese-subtitle",
                    platform: .iOS,
                    state: .completed,
                    exportProfile: MobileExportProfile(subtitleMode: .translatedSubtitleFile),
                    result: MobileTaskResult(artifacts: [
                        MobileTaskArtifact(
                            id: "original",
                            kind: .originalMedia,
                            displayName: "Queue Clip.mp4",
                            storageIdentifier: "Downloads/queue.mp4"
                        ),
                        MobileTaskArtifact(
                            id: "transcript",
                            kind: .transcript,
                            displayName: "Queue Clip.zh-Hans.srt",
                            storageIdentifier: "Subtitles/queue.zh-Hans.srt"
                        )
                    ], primaryArtifactID: "original")
                )
            ],
            library: [],
            translationProvider: translationProvider,
            subtitleProcessor: processor,
            storageDirectoryURL: storageDirectory
        )

        await model.performQueueAction(.exportTranslatedSubtitle, taskID: "task-existing-chinese-subtitle")

        let translationRequests = await translationProvider.requests()
        XCTAssertTrue(translationRequests.isEmpty)
        let processorRequests = await processor.requests()
        XCTAssertEqual(processorRequests.count, 1)
        XCTAssertEqual(processorRequests.first?.translation.segments.map(\.text), [
            "已有中文字幕。",
            "不需要云端翻译。"
        ])
        XCTAssertEqual(model.queue.first?.error, nil)
        XCTAssertEqual(model.queue.first?.result?.artifacts.last?.kind, .translatedSubtitleFile)
        XCTAssertEqual(model.library.first?.artifacts.map(\.kind), [.originalMedia, .transcript, .translatedSubtitleFile])
        XCTAssertEqual(model.lastQueueActionStatus, "已生成字幕 Queue Clip.zh-Hans.srt")
    }

    func testExportingTranslatedSubtitleRejectsSourceReferenceTranscriptIdentifierBeforeReadingFile() async throws {
        let storageDirectory = temporaryDirectory()
        try """
        1
        00:00:00,000 --> 00:00:01,000
        Do not read this source reference.

        """.write(
            to: storageDirectory.appendingPathComponent("source:stored-source", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let translationProvider = RecordingTranslationProvider(result: MobileTranslationResult(segments: [
            MobileTranslationSegment(id: "1", startTime: "00:00:00,000", endTime: "00:00:01,000", text: "不应调用")
        ]))
        let processor = RecordingSubtitleProcessor(result: MobileTaskArtifact(
            id: "unexpected",
            kind: .translatedSubtitleFile,
            displayName: "unexpected.srt",
            storageIdentifier: "Subtitles/unexpected.srt"
        ))
        let originalResult = MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "original",
                kind: .originalMedia,
                displayName: "Queue Clip.mp4",
                storageIdentifier: "Downloads/queue.mp4"
            ),
            MobileTaskArtifact(
                id: "transcript",
                kind: .transcript,
                displayName: "Queue Clip.en.srt",
                storageIdentifier: "source:stored-source"
            )
        ], primaryArtifactID: "original")
        let model = IOSMobileAppModel(
            queue: [
                MobileTaskSnapshot(
                    id: "task-subtitle-source-reference",
                    platform: .iOS,
                    state: .completed,
                    exportProfile: MobileExportProfile(subtitleMode: .translatedSubtitleFile),
                    result: originalResult
                )
            ],
            library: [],
            translationProvider: translationProvider,
            subtitleProcessor: processor,
            storageDirectoryURL: storageDirectory
        )

        await model.performQueueAction(.exportTranslatedSubtitle, taskID: "task-subtitle-source-reference")

        let task = try XCTUnwrap(model.queue.first { $0.id == "task-subtitle-source-reference" })
        XCTAssertEqual(task.state, .completed)
        XCTAssertEqual(task.result, originalResult)
        XCTAssertEqual(task.error, .exportFailed)
        XCTAssertEqual(model.lastQueueActionStatus, "字幕生成失败 Queue Clip.mp4")
        XCTAssertEqual(model.library.map(\.title), ["Queue Clip.mp4"])
        XCTAssertEqual(model.library.first?.sourceTaskID, "task-subtitle-source-reference")
        XCTAssertEqual(model.library.first?.artifacts.map(\.kind), [.originalMedia, .transcript])
        let translationRequests = await translationProvider.requests()
        let processingRequests = await processor.requests()
        XCTAssertTrue(translationRequests.isEmpty)
        XCTAssertTrue(processingRequests.isEmpty)
    }

    func testExportingTranslatedSubtitleUsesCurrentCloudTranslationConfigurationWhenProviderIsNotInjected() async throws {
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("moongate-ios-cloud-subtitle-provider-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try """
        1
        00:00:00,000 --> 00:00:01,000
        Hello

        """.write(to: storageDirectory.appendingPathComponent("queue.en.srt"), atomically: true, encoding: .utf8)
        let credentialStore = RecordingCredentialStore()
        let transport = RecordingConnectionTestTransport(statusCode: 200, responseText: """
        {
          "output": [
            {
              "type": "message",
              "content": [
                { "type": "output_text", "text": "1=你好" }
              ]
            }
          ]
        }
        """)
        let processor = RecordingSubtitleProcessor(result: MobileTaskArtifact(
            id: "subtitle-cloud",
            kind: .translatedSubtitleFile,
            displayName: "Queue Clip.zh.srt",
            storageIdentifier: "Subtitles/queue.zh.srt"
        ))
        let model = IOSMobileAppModel(
            queue: [
                MobileTaskSnapshot(
                    id: "task-cloud-subtitle",
                    platform: .iOS,
                    state: .completed,
                    exportProfile: MobileExportProfile(subtitleMode: .translatedSubtitleFile),
                    result: MobileTaskResult(artifacts: [
                        MobileTaskArtifact(
                            id: "original",
                            kind: .originalMedia,
                            displayName: "Queue Clip.mp4",
                            storageIdentifier: "Downloads/queue.mp4"
                        ),
                        MobileTaskArtifact(
                            id: "transcript",
                            kind: .transcript,
                            displayName: "Queue Clip.en.srt",
                            storageIdentifier: "queue.en.srt"
                        )
                    ], primaryArtifactID: "original")
                )
            ],
            library: [],
            translationConfiguration: MobileTranslationConfiguration(
                engine: .openAICompatible,
                baseURL: "https://api.example.com",
                model: "gpt-5-mini"
            ),
            credentialStore: credentialStore,
            translationConnectionTransport: transport,
            subtitleProcessor: processor,
            storageDirectoryURL: storageDirectory
        )

        await model.saveAPIKeyDraft("TEST_SECRET_VALUE_DO_NOT_STORE")
        await model.performQueueAction(.exportTranslatedSubtitle, taskID: "task-cloud-subtitle")

        let maybeRecorded = await transport.firstRecordedRequest()
        let recorded = try XCTUnwrap(maybeRecorded)
        XCTAssertEqual(recorded.url.absoluteString, "https://api.example.com/v1/responses")
        XCTAssertEqual(recorded.headers["Authorization"], "Bearer TEST_SECRET_VALUE_DO_NOT_STORE")
        XCTAssertFalse(model.lastQueueActionStatus?.contains("TEST_SECRET_VALUE_DO_NOT_STORE") == true)
        XCTAssertEqual(model.queue.first?.result?.artifacts.last?.kind, .translatedSubtitleFile)
        let processorRequests = await processor.requests()
        XCTAssertEqual(processorRequests.first?.translation.segments.map(\.text), ["你好"])
    }

    func testExportingTranslatedSubtitleUsesAppleTranslationProviderWithoutAPIKeyWhenSelected() async throws {
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("moongate-ios-apple-translation-subtitle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try """
        1
        00:00:00,000 --> 00:00:01,000
        Hello

        2
        00:00:01,000 --> 00:00:02,000
        world

        """.write(to: storageDirectory.appendingPathComponent("queue.en.srt"), atomically: true, encoding: .utf8)
        let appleExecutor = RecordingIOSAppleTranslationExecutor(responses: [
            "1": "你好",
            "2": "世界"
        ])
        let appleProvider = IOSAppleTranslationMobileProvider(executor: appleExecutor)
        let processor = RecordingSubtitleProcessor(result: MobileTaskArtifact(
            id: "subtitle-apple",
            kind: .translatedSubtitleFile,
            displayName: "Queue Clip.zh.srt",
            storageIdentifier: "Subtitles/queue.zh.srt"
        ))
        let model = IOSMobileAppModel(
            queue: [
                MobileTaskSnapshot(
                    id: "task-apple-subtitle",
                    platform: .iOS,
                    state: .completed,
                    exportProfile: MobileExportProfile(subtitleMode: .translatedSubtitleFile),
                    result: MobileTaskResult(artifacts: [
                        MobileTaskArtifact(
                            id: "original",
                            kind: .originalMedia,
                            displayName: "Queue Clip.mp4",
                            storageIdentifier: "Downloads/queue.mp4"
                        ),
                        MobileTaskArtifact(
                            id: "transcript",
                            kind: .transcript,
                            displayName: "Queue Clip.en.srt",
                            storageIdentifier: "queue.en.srt"
                        )
                    ], primaryArtifactID: "original")
                )
            ],
            library: [],
            translationConfiguration: MobileTranslationConfiguration(
                engine: .appleTranslationLowLatency,
                readiness: .ready
            ),
            translationProvider: appleProvider,
            subtitleProcessor: processor,
            storageDirectoryURL: storageDirectory
        )

        await model.performQueueAction(.exportTranslatedSubtitle, taskID: "task-apple-subtitle")

        let appleRequests = await appleExecutor.recordedRequests()
        XCTAssertEqual(appleRequests.map(\.engine), [.appleTranslationLowLatency])
        XCTAssertEqual(appleRequests.first?.context.sourceLanguage, "en")
        XCTAssertEqual(appleRequests.first?.context.targetLanguage, "zh-Hans")
        XCTAssertEqual(appleRequests.first?.segments.map(\.text), ["Hello", "world"])
        let processorRequests = await processor.requests()
        XCTAssertEqual(processorRequests.first?.translation.segments.map(\.text), ["你好", "世界"])
        XCTAssertEqual(model.queue.first?.result?.artifacts.last?.kind, .translatedSubtitleFile)
        XCTAssertEqual(model.lastQueueActionStatus, "已生成字幕 Queue Clip.zh.srt")
    }

    func testExportingTranslatedSubtitleWithIncompleteCloudConfigurationFailsAsTranslationWithoutDroppingResult() async throws {
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("moongate-ios-cloud-subtitle-missing-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try """
        1
        00:00:00,000 --> 00:00:01,000
        Hello

        """.write(to: storageDirectory.appendingPathComponent("queue.en.srt"), atomically: true, encoding: .utf8)
        let downloadDirectory = storageDirectory.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        try Data("downloaded-video".utf8).write(to: downloadDirectory.appendingPathComponent("queue.mp4"))
        let processor = RecordingSubtitleProcessor(result: MobileTaskArtifact(
            id: "unexpected",
            kind: .translatedSubtitleFile,
            displayName: "unexpected.srt",
            storageIdentifier: "Subtitles/unexpected.srt"
        ))
        let repository = RecordingTaskRepository()
        let originalResult = MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "original",
                kind: .originalMedia,
                displayName: "Queue Clip.mp4",
                storageIdentifier: "Downloads/queue.mp4"
            ),
            MobileTaskArtifact(
                id: "transcript",
                kind: .transcript,
                displayName: "Queue Clip.en.srt",
                storageIdentifier: "queue.en.srt"
            )
        ], primaryArtifactID: "original")
        let model = IOSMobileAppModel(
            queue: [
                MobileTaskSnapshot(
                    id: "task-cloud-subtitle-missing-config",
                    platform: .iOS,
                    state: .completed,
                    exportProfile: MobileExportProfile(subtitleMode: .translatedSubtitleFile),
                    result: originalResult
                )
            ],
            library: [],
            translationConfiguration: MobileTranslationConfiguration(
                engine: .openAICompatible,
                baseURL: "https://api.example.com",
                model: nil
            ),
            subtitleProcessor: processor,
            storageDirectoryURL: storageDirectory,
            taskRepository: repository
        )

        await model.performQueueAction(.exportTranslatedSubtitle, taskID: "task-cloud-subtitle-missing-config")

        let task = try XCTUnwrap(model.queue.first { $0.id == "task-cloud-subtitle-missing-config" })
        XCTAssertEqual(task.state, .completed)
        XCTAssertEqual(task.result, originalResult)
        XCTAssertEqual(task.error, .credentialRequired)
        XCTAssertEqual(model.lastQueueActionStatus, "字幕翻译失败 Queue Clip.mp4")
        XCTAssertEqual(model.library.map(\.title), ["Queue Clip.mp4"])
        XCTAssertEqual(model.library.first?.sourceTaskID, "task-cloud-subtitle-missing-config")
        XCTAssertEqual(model.library.first?.artifacts.map(\.kind), [.originalMedia, .transcript])
        let processorRequests = await processor.requests()
        XCTAssertTrue(processorRequests.isEmpty)
        let savedTasks = await repository.savedTasks()
        XCTAssertEqual(savedTasks.first?.state, .translating)
        XCTAssertEqual(savedTasks.last?.state, .completed)
        XCTAssertEqual(savedTasks.last?.error, .credentialRequired)
    }

    func testFailedTranslatedSubtitleExportKeepsCompletedDownloadResultAvailable() async throws {
        let storageDirectory = temporaryDirectory()
        let downloadDirectory = storageDirectory.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        try Data("downloaded-video".utf8).write(to: downloadDirectory.appendingPathComponent("queue.mp4"))
        let processor = RecordingSubtitleProcessor(error: MobileTaskError.exportFailed)
        let repository = RecordingTaskRepository()
        let originalResult = MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "original",
                kind: .originalMedia,
                displayName: "Queue Clip.mp4",
                storageIdentifier: "Downloads/queue.mp4"
            ),
            MobileTaskArtifact(
                id: "transcript",
                kind: .transcript,
                displayName: "Queue Clip.en.srt",
                storageIdentifier: "queue.en.srt"
            )
        ], primaryArtifactID: "original")
        let model = IOSMobileAppModel(
            queue: [
                MobileTaskSnapshot(
                    id: "task-subtitle-failure",
                    platform: .iOS,
                    state: .completed,
                    exportProfile: MobileExportProfile(subtitleMode: .translatedSubtitleFile),
                    result: originalResult
                )
            ],
            library: [],
            subtitleProcessor: processor,
            storageDirectoryURL: storageDirectory,
            taskRepository: repository
        )

        await model.applyTranslationResult(
            MobileTranslationResult(segments: [
                MobileTranslationSegment(id: "1", startTime: "00:00:00,000", endTime: "00:00:01,000", text: "你好")
            ]),
            toTaskID: "task-subtitle-failure"
        )
        await model.performQueueAction(.exportTranslatedSubtitle, taskID: "task-subtitle-failure")

        let task = try XCTUnwrap(model.queue.first { $0.id == "task-subtitle-failure" })
        XCTAssertEqual(task.state, .completed)
        XCTAssertEqual(task.result, originalResult)
        XCTAssertEqual(task.error, .exportFailed)
        XCTAssertEqual(task.availableActions, [.exportTranslatedSubtitle, .openResult, .shareResult, .remove])
        XCTAssertEqual(model.lastQueueActionStatus, "字幕生成失败 Queue Clip.mp4")
        XCTAssertEqual(model.library.map(\.title), ["Queue Clip.mp4"])
        XCTAssertEqual(model.library.first?.sourceTaskID, "task-subtitle-failure")
        XCTAssertEqual(model.library.first?.artifacts.map(\.kind), [.originalMedia, .transcript])
        XCTAssertEqual(model.library.first?.availableActions, [.open, .share, .saveToFiles, .saveToPhotos, .deleteRecord])
        let savedTasks = await repository.savedTasks()
        XCTAssertEqual(savedTasks.first?.state, .translating)
        XCTAssertEqual(savedTasks.last?.state, .completed)
        XCTAssertEqual(savedTasks.last?.error, .exportFailed)
    }

    func testRetryingFailedTranslatedSubtitleExportReplacesOriginalLibraryRecordWithSubtitleArtifact() async throws {
        let storageDirectory = temporaryDirectory()
        let downloadDirectory = storageDirectory.appendingPathComponent("Downloads", isDirectory: true)
        let subtitleDirectory = storageDirectory.appendingPathComponent("Subtitles", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: subtitleDirectory, withIntermediateDirectories: true)
        try Data("downloaded-video".utf8).write(to: downloadDirectory.appendingPathComponent("queue.mp4"))
        try "1\n00:00:00,000 --> 00:00:01,000\n你好\n".write(
            to: subtitleDirectory.appendingPathComponent("queue.zh.srt"),
            atomically: true,
            encoding: .utf8
        )
        let processor = SequencedSubtitleProcessor(outcomes: [
            .failure(MobileTaskError.exportFailed),
            .success(MobileTaskArtifact(
                id: "subtitle-translated",
                kind: .translatedSubtitleFile,
                displayName: "Queue Clip.zh.srt",
                storageIdentifier: "Subtitles/queue.zh.srt",
                byteCount: 128
            ))
        ])
        let repository = RecordingTaskRepository()
        let originalResult = MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "original",
                kind: .originalMedia,
                displayName: "Queue Clip.mp4",
                storageIdentifier: "Downloads/queue.mp4"
            ),
            MobileTaskArtifact(
                id: "transcript",
                kind: .transcript,
                displayName: "Queue Clip.en.srt",
                storageIdentifier: "queue.en.srt"
            )
        ], primaryArtifactID: "original")
        let model = IOSMobileAppModel(
            queue: [
                MobileTaskSnapshot(
                    id: "task-subtitle-retry-after-failure",
                    platform: .iOS,
                    state: .completed,
                    exportProfile: MobileExportProfile(subtitleMode: .translatedSubtitleFile),
                    result: originalResult
                )
            ],
            library: [],
            subtitleProcessor: processor,
            storageDirectoryURL: storageDirectory,
            taskRepository: repository
        )
        await model.applyTranslationResult(
            MobileTranslationResult(segments: [
                MobileTranslationSegment(id: "1", startTime: "00:00:00,000", endTime: "00:00:01,000", text: "你好")
            ]),
            toTaskID: "task-subtitle-retry-after-failure"
        )

        await model.performQueueAction(.exportTranslatedSubtitle, taskID: "task-subtitle-retry-after-failure")
        XCTAssertEqual(model.queue.first?.state, .completed)
        XCTAssertEqual(model.queue.first?.error, .exportFailed)
        XCTAssertEqual(model.library.map(\.title), ["Queue Clip.mp4"])

        await model.performQueueAction(.exportTranslatedSubtitle, taskID: "task-subtitle-retry-after-failure")

        let task = try XCTUnwrap(model.queue.first { $0.id == "task-subtitle-retry-after-failure" })
        XCTAssertEqual(task.state, .completed)
        XCTAssertNil(task.error)
        XCTAssertEqual(task.result?.primaryArtifact?.kind, .originalMedia)
        XCTAssertEqual(task.result?.artifacts.map(\.kind), [.originalMedia, .transcript, .translatedSubtitleFile])
        XCTAssertEqual(model.library.map(\.title), ["Queue Clip.mp4"])
        XCTAssertEqual(model.library.first?.sourceTaskID, "task-subtitle-retry-after-failure")
        XCTAssertEqual(model.library.first?.artifacts.map(\.kind), [.originalMedia, .transcript, .translatedSubtitleFile])
        XCTAssertEqual(model.library.count, 1)
        XCTAssertEqual(model.lastQueueActionStatus, "已生成字幕 Queue Clip.zh.srt")

        let requests = await processor.requests()
        XCTAssertEqual(requests.count, 2)
        let savedTasks = await repository.savedTasks()
        XCTAssertTrue(savedTasks.contains { $0.state == .completed && $0.error == .exportFailed })
        XCTAssertEqual(savedTasks.last?.state, .completed)
        XCTAssertEqual(savedTasks.last?.error, nil)
    }

    func testStartingDownloadWithoutSourceDoesNotCallDownloadEngine() async throws {
        let downloadEngine = RecordingDownloadEngine(result: MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "should-not-download",
                kind: .originalMedia,
                displayName: "Unexpected.mp4",
                storageIdentifier: "downloads/unexpected.mp4"
            )
        ], primaryArtifactID: "should-not-download"))
        let repository = RecordingTaskRepository()
        let model = IOSMobileAppModel(
            queue: [
                MobileTaskSnapshot(
                    id: "missing-source",
                    platform: .iOS,
                    state: .waiting,
                    result: MobileTaskResult(artifacts: [
                        MobileTaskArtifact(
                            id: "pending",
                            kind: .metadata,
                            displayName: "Missing Source",
                            storageIdentifier: "mobile-source:missing-source"
                        )
                    ], primaryArtifactID: "pending")
                )
            ],
            library: [],
            downloadEngine: downloadEngine,
            taskRepository: repository
        )

        await model.startDownload(taskID: "missing-source")

        let task = try XCTUnwrap(model.queue.first { $0.id == "missing-source" })
        XCTAssertEqual(task.state, .failed)
        XCTAssertEqual(task.error, .sourceUnavailableAfterRelaunch)
        XCTAssertEqual(model.lastQueueActionStatus, "需要重新添加原链接 Missing Source")
        XCTAssertTrue(model.library.isEmpty)
        let requests = await downloadEngine.requests()
        XCTAssertTrue(requests.isEmpty)
        let savedTasks = await repository.savedTasks()
        XCTAssertEqual(savedTasks.map(\.state), [.failed])
    }

    func testDownloadProgressCallbacksStaySynchronizedWithRepository() async throws {
        let downloadEngine = SuspendedDownloadEngine(result: MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "original-progress",
                kind: .originalMedia,
                displayName: "Progress Clip.mp4",
                storageIdentifier: "downloads/progress.mp4",
                byteCount: 11
            )
        ], primaryArtifactID: "original-progress"))
        let repository = RecordingTaskRepository()
        let model = IOSMobileAppModel(
            addSession: MobileAddSessionSnapshot(id: "empty"),
            queue: [],
            library: [],
            downloadEngine: downloadEngine,
            taskRepository: repository
        )

        await model.analyzeURL("https://cdn.example.com/progress.mp4")
        await model.enqueueSelectedVideo()
        let taskID = try XCTUnwrap(model.queue.first?.id)
        let downloadTask = Task {
            await model.startDownload(taskID: taskID)
        }
        await downloadEngine.waitUntilStarted()

        XCTAssertEqual(
            model.queue.first?.progress,
            MobileTaskProgress(phase: .downloading, completedUnitCount: 1, totalUnitCount: 2)
        )
        let storedInProgressDownload = try await waitForStoredTask(in: repository) {
            $0.id == taskID &&
                $0.state == .downloading &&
                $0.progress == MobileTaskProgress(phase: .downloading, completedUnitCount: 1, totalUnitCount: 2)
        }
        XCTAssertEqual(storedInProgressDownload.id, taskID)

        await downloadEngine.complete()
        await downloadTask.value

        let storedTasks = try await repository.loadTasks()
        XCTAssertEqual(storedTasks.first?.state, .completed)
        XCTAssertEqual(storedTasks.first?.progress, MobileTaskProgress(phase: .downloading, completedUnitCount: 11, totalUnitCount: 11))
    }

    func testCancellingActiveDownloadPreventsStaleCompletionFromOverwritingTask() async throws {
        let downloadEngine = SuspendedDownloadEngine(result: MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "original-cancelled",
                kind: .originalMedia,
                displayName: "Cancelled Clip.mp4",
                storageIdentifier: "downloads/cancelled.mp4",
                byteCount: 11
            )
        ], primaryArtifactID: "original-cancelled"))
        let repository = RecordingTaskRepository()
        let model = IOSMobileAppModel(
            addSession: MobileAddSessionSnapshot(id: "empty"),
            queue: [],
            library: [],
            downloadEngine: downloadEngine,
            taskRepository: repository
        )

        await model.analyzeURL("https://cdn.example.com/cancelled.mp4")
        await model.enqueueSelectedVideo()
        let taskID = try XCTUnwrap(model.queue.first?.id)
        let downloadTask = Task {
            await model.startDownload(taskID: taskID)
        }
        await downloadEngine.waitUntilStarted()

        await model.performQueueAction(.cancel, taskID: taskID)
        await downloadEngine.complete()
        await downloadTask.value

        let task = try XCTUnwrap(model.queue.first { $0.id == taskID })
        XCTAssertEqual(task.state, .cancelled)
        XCTAssertFalse(task.result?.artifacts.contains { $0.kind == .originalMedia } == true)
        XCTAssertTrue(model.library.isEmpty)
        let storedTasks = try await repository.loadTasks()
        XCTAssertEqual(storedTasks.first?.state, .cancelled)
        XCTAssertFalse(storedTasks.first?.result?.artifacts.contains { $0.kind == .originalMedia } == true)
    }

    func testCancellingQueueStartedDownloadCancelsUnderlyingWork() async throws {
        let downloadEngine = CancellableSuspendedDownloadEngine(result: MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "original-cancelled-underlying",
                kind: .originalMedia,
                displayName: "Cancelled Underlying Clip.mp4",
                storageIdentifier: "downloads/cancelled-underlying.mp4",
                byteCount: 11
            )
        ], primaryArtifactID: "original-cancelled-underlying"))
        let repository = RecordingTaskRepository()
        let model = IOSMobileAppModel(
            addSession: MobileAddSessionSnapshot(id: "empty"),
            queue: [],
            library: [],
            downloadEngine: downloadEngine,
            taskRepository: repository
        )

        await model.analyzeURL("https://cdn.example.com/cancelled-underlying.mp4")
        await model.enqueueSelectedVideo()
        let taskID = try XCTUnwrap(model.queue.first?.id)
        let queueActionTask = Task {
            await model.performQueueAction(.startDownload, taskID: taskID)
        }
        await downloadEngine.waitUntilStarted()

        await model.performQueueAction(.cancel, taskID: taskID)
        let observedCancellation = try await waitForCondition("download engine to observe cancellation") {
            await downloadEngine.didObserveCancellation()
        }
        if !observedCancellation {
            await downloadEngine.complete()
        }
        await queueActionTask.value

        XCTAssertTrue(observedCancellation)
        let task = try XCTUnwrap(model.queue.first { $0.id == taskID })
        XCTAssertEqual(task.state, .cancelled)
        XCTAssertTrue(model.library.isEmpty)
        let storedTasks = try await repository.loadTasks()
        XCTAssertEqual(storedTasks.first?.state, .cancelled)
    }

    func testCancellingActiveSubtitleExportPreventsStaleCompletionFromOverwritingTask() async throws {
        let processor = SuspendedSubtitleProcessor(result: MobileTaskArtifact(
            id: "subtitle-cancelled",
            kind: .translatedSubtitleFile,
            displayName: "Cancelled Clip.zh.srt",
            storageIdentifier: "Subtitles/cancelled.zh.srt",
            byteCount: 128
        ))
        let repository = RecordingTaskRepository()
        let model = IOSMobileAppModel(
            queue: [
                MobileTaskSnapshot(
                    id: "task-subtitle-cancelled",
                    platform: .iOS,
                    state: .completed,
                    exportProfile: MobileExportProfile(subtitleMode: .translatedSubtitleFile),
                    result: MobileTaskResult(artifacts: [
                        MobileTaskArtifact(
                            id: "original",
                            kind: .originalMedia,
                            displayName: "Cancelled Clip.mp4",
                            storageIdentifier: "Downloads/cancelled.mp4"
                        ),
                        MobileTaskArtifact(
                            id: "transcript",
                            kind: .transcript,
                            displayName: "Cancelled Clip.en.srt",
                            storageIdentifier: "cancelled.en.srt"
                        )
                    ], primaryArtifactID: "original")
                )
            ],
            library: [],
            subtitleProcessor: processor,
            taskRepository: repository
        )

        await model.applyTranslationResult(
            MobileTranslationResult(segments: [
                MobileTranslationSegment(id: "1", startTime: "00:00:00,000", endTime: "00:00:01,000", text: "你好")
            ]),
            toTaskID: "task-subtitle-cancelled"
        )
        let exportTask = Task {
            await model.performQueueAction(.exportTranslatedSubtitle, taskID: "task-subtitle-cancelled")
        }
        await processor.waitUntilStarted()

        await model.performQueueAction(.cancel, taskID: "task-subtitle-cancelled")
        await processor.complete()
        await exportTask.value

        let task = try XCTUnwrap(model.queue.first { $0.id == "task-subtitle-cancelled" })
        XCTAssertEqual(task.state, .cancelled)
        XCTAssertEqual(task.result?.artifacts.map(\.kind), [.originalMedia, .transcript])
        XCTAssertTrue(model.library.isEmpty)
        let storedTasks = try await repository.loadTasks()
        XCTAssertEqual(storedTasks.first?.state, .cancelled)
        XCTAssertEqual(storedTasks.first?.result?.artifacts.map(\.kind), [.originalMedia, .transcript])
    }

    func testCancellingActiveSubtitleExportCancelsUnderlyingProcessor() async throws {
        let processor = CancellableSuspendedSubtitleProcessor(result: MobileTaskArtifact(
            id: "subtitle-cancelled-underlying",
            kind: .translatedSubtitleFile,
            displayName: "Cancelled Underlying Clip.zh.srt",
            storageIdentifier: "Subtitles/cancelled-underlying.zh.srt",
            byteCount: 128
        ))
        let repository = RecordingTaskRepository()
        let model = IOSMobileAppModel(
            queue: [
                MobileTaskSnapshot(
                    id: "task-subtitle-cancelled-underlying",
                    platform: .iOS,
                    state: .completed,
                    exportProfile: MobileExportProfile(subtitleMode: .translatedSubtitleFile),
                    result: MobileTaskResult(artifacts: [
                        MobileTaskArtifact(
                            id: "original",
                            kind: .originalMedia,
                            displayName: "Cancelled Underlying Clip.mp4",
                            storageIdentifier: "Downloads/cancelled-underlying.mp4"
                        ),
                        MobileTaskArtifact(
                            id: "transcript",
                            kind: .transcript,
                            displayName: "Cancelled Underlying Clip.en.srt",
                            storageIdentifier: "cancelled-underlying.en.srt"
                        )
                    ], primaryArtifactID: "original")
                )
            ],
            library: [],
            subtitleProcessor: processor,
            taskRepository: repository
        )

        await model.applyTranslationResult(
            MobileTranslationResult(segments: [
                MobileTranslationSegment(id: "1", startTime: "00:00:00,000", endTime: "00:00:01,000", text: "你好")
            ]),
            toTaskID: "task-subtitle-cancelled-underlying"
        )
        let exportTask = Task {
            await model.performQueueAction(.exportTranslatedSubtitle, taskID: "task-subtitle-cancelled-underlying")
        }
        await processor.waitUntilStarted()

        await model.performQueueAction(.cancel, taskID: "task-subtitle-cancelled-underlying")
        let observedCancellation = try await waitForCondition("subtitle processor to observe cancellation") {
            await processor.didObserveCancellation()
        }
        if !observedCancellation {
            await processor.complete()
        }
        await exportTask.value

        XCTAssertTrue(observedCancellation)
        let task = try XCTUnwrap(model.queue.first { $0.id == "task-subtitle-cancelled-underlying" })
        XCTAssertEqual(task.state, .cancelled)
        XCTAssertEqual(task.result?.artifacts.map(\.kind), [.originalMedia, .transcript])
        XCTAssertTrue(model.library.isEmpty)
        let storedTasks = try await repository.loadTasks()
        XCTAssertEqual(storedTasks.first?.state, .cancelled)
        XCTAssertEqual(storedTasks.first?.result?.artifacts.map(\.kind), [.originalMedia, .transcript])
    }

    func testCancellingActiveSubtitleExportPreventsLateFailureFromOverwritingTask() async throws {
        let processor = SuspendedSubtitleProcessor(error: MobileTaskError.exportFailed)
        let repository = RecordingTaskRepository()
        let model = IOSMobileAppModel(
            queue: [
                MobileTaskSnapshot(
                    id: "task-subtitle-cancelled-failure",
                    platform: .iOS,
                    state: .completed,
                    exportProfile: MobileExportProfile(subtitleMode: .translatedSubtitleFile),
                    result: MobileTaskResult(artifacts: [
                        MobileTaskArtifact(
                            id: "original",
                            kind: .originalMedia,
                            displayName: "Cancelled Failure Clip.mp4",
                            storageIdentifier: "Downloads/cancelled-failure.mp4"
                        ),
                        MobileTaskArtifact(
                            id: "transcript",
                            kind: .transcript,
                            displayName: "Cancelled Failure Clip.en.srt",
                            storageIdentifier: "cancelled-failure.en.srt"
                        )
                    ], primaryArtifactID: "original")
                )
            ],
            library: [],
            subtitleProcessor: processor,
            taskRepository: repository
        )

        await model.applyTranslationResult(
            MobileTranslationResult(segments: [
                MobileTranslationSegment(id: "1", startTime: "00:00:00,000", endTime: "00:00:01,000", text: "你好")
            ]),
            toTaskID: "task-subtitle-cancelled-failure"
        )
        let exportTask = Task {
            await model.performQueueAction(.exportTranslatedSubtitle, taskID: "task-subtitle-cancelled-failure")
        }
        await processor.waitUntilStarted()

        await model.performQueueAction(.cancel, taskID: "task-subtitle-cancelled-failure")
        await processor.complete()
        await exportTask.value

        let task = try XCTUnwrap(model.queue.first { $0.id == "task-subtitle-cancelled-failure" })
        XCTAssertEqual(task.state, .cancelled)
        XCTAssertEqual(task.result?.artifacts.map(\.kind), [.originalMedia, .transcript])
        XCTAssertTrue(model.library.isEmpty)
        let storedTasks = try await repository.loadTasks()
        XCTAssertEqual(storedTasks.first?.state, .cancelled)
        XCTAssertEqual(storedTasks.first?.result?.artifacts.map(\.kind), [.originalMedia, .transcript])
    }

    func testSubtitleProgressCallbacksStaySynchronizedWithRepository() async throws {
        let processor = SuspendedSubtitleProcessor(result: MobileTaskArtifact(
            id: "subtitle-progress",
            kind: .translatedSubtitleFile,
            displayName: "Progress Clip.zh.srt",
            storageIdentifier: "Subtitles/progress.zh.srt",
            byteCount: 128
        ))
        let repository = RecordingTaskRepository()
        let model = IOSMobileAppModel(
            queue: [
                MobileTaskSnapshot(
                    id: "task-subtitle-progress",
                    platform: .iOS,
                    state: .completed,
                    exportProfile: MobileExportProfile(subtitleMode: .translatedSubtitleFile),
                    result: MobileTaskResult(artifacts: [
                        MobileTaskArtifact(
                            id: "original",
                            kind: .originalMedia,
                            displayName: "Progress Clip.mp4",
                            storageIdentifier: "Downloads/progress.mp4"
                        ),
                        MobileTaskArtifact(
                            id: "transcript",
                            kind: .transcript,
                            displayName: "Progress Clip.en.srt",
                            storageIdentifier: "progress.en.srt"
                        )
                    ], primaryArtifactID: "original")
                )
            ],
            library: [],
            subtitleProcessor: processor,
            taskRepository: repository
        )

        await model.applyTranslationResult(
            MobileTranslationResult(segments: [
                MobileTranslationSegment(id: "1", startTime: "00:00:00,000", endTime: "00:00:01,000", text: "你好")
            ]),
            toTaskID: "task-subtitle-progress"
        )
        let exportTask = Task {
            await model.performQueueAction(.exportTranslatedSubtitle, taskID: "task-subtitle-progress")
        }
        await processor.waitUntilStarted()

        XCTAssertEqual(
            model.queue.first?.progress,
            MobileTaskProgress(phase: .translating, completedUnitCount: 1, totalUnitCount: 2)
        )
        let storedInProgressSubtitle = try await waitForStoredTask(in: repository) {
            $0.id == "task-subtitle-progress" &&
                $0.state == .translating &&
                $0.progress == MobileTaskProgress(phase: .translating, completedUnitCount: 1, totalUnitCount: 2)
        }
        XCTAssertEqual(storedInProgressSubtitle.id, "task-subtitle-progress")

        await processor.complete()
        await exportTask.value

        let storedTasks = try await repository.loadTasks()
        XCTAssertEqual(storedTasks.first?.state, .completed)
        XCTAssertEqual(storedTasks.first?.progress, MobileTaskProgress(phase: .translating, completedUnitCount: 128, totalUnitCount: 128))
    }

    func testQueueMutationsStaySynchronizedWithRepository() async throws {
        let repository = RecordingTaskRepository()
        let model = IOSMobileAppModel(
            addSession: MobileAddSessionSnapshot(id: "empty"),
            queue: [],
            library: [],
            taskRepository: repository
        )

        await model.analyzeURL("https://cdn.example.com/videos/persisted.mp4")
        await model.enqueueSelectedVideo()
        let taskID = try XCTUnwrap(model.queue.first?.id)

        var storedTasks = try await repository.loadTasks()
        XCTAssertEqual(storedTasks.map(\.id), [taskID])
        XCTAssertEqual(storedTasks.first?.state, .waiting)

        await model.performQueueAction(.cancel, taskID: taskID)
        storedTasks = try await repository.loadTasks()
        XCTAssertEqual(storedTasks.first?.state, .cancelled)

        await model.performQueueAction(.retry, taskID: taskID)
        storedTasks = try await repository.loadTasks()
        XCTAssertEqual(storedTasks.first?.state, .cancelled)

        model.queue[0] = MobileTaskSnapshot(
            id: taskID,
            platform: .iOS,
            state: .failed,
            error: .networkUnavailable
        )
        await model.performQueueAction(.retry, taskID: taskID)
        storedTasks = try await repository.loadTasks()
        XCTAssertEqual(storedTasks.first?.state, .waiting)

        model.queue[0].state = .failed
        await model.performQueueAction(.remove, taskID: taskID)
        storedTasks = try await repository.loadTasks()
        XCTAssertTrue(storedTasks.isEmpty)
    }

    func testRestoringLegacySourceURLMigratesDiskSnapshotWithoutRehydratingSignedURL() async throws {
        let signedURL = "https://cdn.example.com/private/legacy.mp4?token=SECRET_TOKEN&X-Amz-Signature=abc123"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("moongate-ios-legacy-source-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacyTask = MobileTaskSnapshot(
            id: "legacy-source",
            platform: .iOS,
            state: .waiting,
            result: MobileTaskResult(artifacts: [
                MobileTaskArtifact(
                    id: "pending",
                    kind: .metadata,
                    displayName: "Legacy Clip",
                    storageIdentifier: "source:\(signedURL)"
                ),
                MobileTaskArtifact(
                    id: "original",
                    kind: .originalMedia,
                    displayName: "Legacy Clip.mp4",
                    storageIdentifier: "source:\(signedURL)"
                )
            ], primaryArtifactID: "original")
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder
            .encode([legacyTask])
            .write(to: directory.appendingPathComponent("mobile-tasks.json"), options: [.atomic])
        let repository = try FileTaskRepository(directoryURL: directory)
        let downloadEngine = RecordingDownloadEngine(result: MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "original-legacy-source",
                kind: .originalMedia,
                displayName: "Legacy Clip.mp4",
                storageIdentifier: "downloads/legacy-source.mp4",
                byteCount: 11
            )
        ], primaryArtifactID: "original-legacy-source"))
        let model = IOSMobileAppModel(
            queue: [],
            library: [],
            downloadEngine: downloadEngine,
            taskRepository: repository
        )

        await model.restoreQueueFromRepository()

        let migratedJSON = try String(contentsOf: directory.appendingPathComponent("mobile-tasks.json"))
        XCTAssertFalse(migratedJSON.contains(signedURL))
        XCTAssertFalse(migratedJSON.contains("SECRET_TOKEN"))
        XCTAssertFalse(migratedJSON.contains("X-Amz-Signature"))
        XCTAssertFalse(migratedJSON.contains("source:https://"))
        XCTAssertTrue(migratedJSON.contains("mobile-source:legacy-source"))
        XCTAssertEqual(
            model.queue.first?.result?.primaryArtifact?.storageIdentifier,
            "mobile-source:legacy-source"
        )

        await model.startDownload(taskID: "legacy-source")

        let requests = await downloadEngine.requests()
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(model.queue.first?.state, .failed)
        XCTAssertEqual(model.queue.first?.error, .sourceUnavailableAfterRelaunch)
        let completedJSON = try String(contentsOf: directory.appendingPathComponent("mobile-tasks.json"))
        XCTAssertFalse(completedJSON.contains(signedURL))
        XCTAssertFalse(completedJSON.contains("SECRET_TOKEN"))
        XCTAssertFalse(completedJSON.contains("X-Amz-Signature"))
    }

    func testRestoringPersistedTasksLoadsQueueNormalizesActiveWorkAndBackfillsLibrary() async throws {
        let completedResult = MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "video",
                kind: .originalMedia,
                displayName: "Restored Clip.mp4",
                storageIdentifier: "downloads/restored-clip.mp4",
                byteCount: 11
            )
        ], primaryArtifactID: "video")
        let repository = RecordingTaskRepository(tasks: [
            MobileTaskSnapshot(id: "waiting", platform: .iOS, state: .waiting),
            MobileTaskSnapshot(
                id: "active-download",
                platform: .iOS,
                state: .downloading,
                progress: MobileTaskProgress(phase: .downloading, completedUnitCount: 4, totalUnitCount: 10),
                backgroundPolicy: MobileBackgroundPolicy(execution: .systemManaged, resumability: .resumable)
            ),
            MobileTaskSnapshot(
                id: "active-export",
                platform: .iOS,
                state: .exporting,
                progress: MobileTaskProgress(phase: .exporting, completedUnitCount: 1, totalUnitCount: 2),
                backgroundPolicy: MobileBackgroundPolicy(execution: .foregroundRequired, resumability: .nonResumable)
            ),
            MobileTaskSnapshot(
                id: "completed",
                platform: .iOS,
                state: .completed,
                result: completedResult
            )
        ])
        let model = IOSMobileAppModel(
            queue: [],
            library: [
                MobileLibraryItem(
                    id: "library-completed",
                    title: "Existing restored record",
                    createdAt: Date(timeIntervalSince1970: 1),
                    artifacts: completedResult.artifacts,
                    sourceTaskID: "completed"
                )
            ],
            taskRepository: repository
        )

        await model.restoreQueueFromRepository()

        XCTAssertEqual(model.queue.map(\.id), ["waiting", "active-download", "active-export", "completed"])
        XCTAssertEqual(model.queue.first { $0.id == "waiting" }?.state, .waiting)

        let restoredDownload = try XCTUnwrap(model.queue.first { $0.id == "active-download" })
        XCTAssertEqual(restoredDownload.state, .needsForegroundToContinue)
        XCTAssertEqual(restoredDownload.error, .systemBackgroundLimit)
        XCTAssertEqual(restoredDownload.backgroundPolicy.execution, .systemInterrupted)
        XCTAssertEqual(restoredDownload.backgroundPolicy.resumability, .resumable)
        XCTAssertTrue(restoredDownload.backgroundPolicy.limits.contains(.systemInterrupted))

        let restoredExport = try XCTUnwrap(model.queue.first { $0.id == "active-export" })
        XCTAssertEqual(restoredExport.state, .needsForegroundToContinue)
        XCTAssertEqual(restoredExport.error, .systemBackgroundLimit)
        XCTAssertEqual(restoredExport.backgroundPolicy.execution, .systemInterrupted)
        XCTAssertEqual(restoredExport.backgroundPolicy.resumability, .nonResumable)
        XCTAssertTrue(restoredExport.backgroundPolicy.limits.contains(.notResumable))

        XCTAssertEqual(model.library.filter { $0.sourceTaskID == "completed" }.count, 1)
        XCTAssertEqual(model.library.first { $0.sourceTaskID == "completed" }?.artifacts, completedResult.artifacts)

        let storedTasks = try await repository.loadTasks()
        XCTAssertEqual(storedTasks.first { $0.id == "active-download" }?.state, .needsForegroundToContinue)
        XCTAssertEqual(storedTasks.first { $0.id == "active-download" }?.error, .systemBackgroundLimit)
        XCTAssertEqual(storedTasks.first { $0.id == "active-export" }?.state, .needsForegroundToContinue)
        XCTAssertEqual(storedTasks.first { $0.id == "active-export" }?.backgroundPolicy.resumability, .nonResumable)
    }

    func testRestoringQueueAppliesCompletedBackgroundTransferOutcomeBeforeForegroundFallback() async throws {
        let completedResult = MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "original-background",
                kind: .originalMedia,
                displayName: "Background Clip.mp4",
                storageIdentifier: "downloads/background.mp4",
                byteCount: 18
            )
        ], primaryArtifactID: "original-background")
        let repository = RecordingTaskRepository(tasks: [
            MobileTaskSnapshot(
                id: "background-download",
                platform: .iOS,
                state: .downloading,
                progress: MobileTaskProgress(phase: .downloading, completedUnitCount: 4, totalUnitCount: 18),
                backgroundPolicy: MobileBackgroundPolicy(execution: .backgroundTransfer, resumability: .resumable)
            )
        ])
        let registryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("moongate-ios-background-recovery-\(UUID().uuidString)", isDirectory: true)
        let registry = try BackgroundTransferRegistry(directoryURL: registryDirectory)
        try await registry.recordRecoveryOutcome(BackgroundTransferRecoveryOutcome(
            transferIdentifier: "ios.download.background-download",
            taskID: "background-download",
            platform: .iOS,
            status: .completed,
            result: completedResult,
            progress: MobileTaskProgress(phase: .downloading, completedUnitCount: 18, totalUnitCount: 18),
            backgroundPolicy: MobileBackgroundPolicy(execution: .backgroundTransfer, resumability: .resumable),
            updatedAt: Date(timeIntervalSince1970: 4)
        ))
        let model = IOSMobileAppModel(
            queue: [],
            library: [],
            taskRepository: repository,
            backgroundTransferRegistry: registry
        )

        await model.restoreQueueFromRepository()

        let restored = try XCTUnwrap(model.queue.first { $0.id == "background-download" })
        XCTAssertEqual(restored.state, .completed)
        XCTAssertNil(restored.error)
        XCTAssertEqual(restored.result, completedResult)
        XCTAssertEqual(restored.progress, MobileTaskProgress(phase: .downloading, completedUnitCount: 18, totalUnitCount: 18))
        XCTAssertEqual(model.library.map(\.title), ["Background Clip.mp4"])
        let storedTasks = try await repository.loadTasks()
        XCTAssertEqual(storedTasks.first?.state, .completed)
        XCTAssertEqual(storedTasks.first?.result, completedResult)
        let remainingOutcomes = try await registry.loadRecoveryOutcomes()
        XCTAssertTrue(remainingOutcomes.isEmpty)
    }

    func testRestoringQueuePrunesTerminalAndOrphanSourceReferencesButKeepsSafeRetrySources() async throws {
        let directory = temporaryDirectory()
        let repository = try FileTaskRepository(directoryURL: directory)
        let sourceStore = try IOSSourceReferenceStore(directoryURL: directory)
        let completedResult = MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "completed-video",
                kind: .originalMedia,
                displayName: "Completed Clip.mp4",
                storageIdentifier: "downloads/completed.mp4",
                byteCount: 18
            )
        ], primaryArtifactID: "completed-video")
        try await repository.saveTask(MobileTaskSnapshot(
            id: "completed-source",
            platform: .iOS,
            state: .completed,
            result: completedResult
        ))
        try await repository.saveTask(MobileTaskSnapshot(
            id: "retry-source",
            platform: .iOS,
            state: .failed,
            result: MobileTaskResult(artifacts: [
                MobileTaskArtifact(
                    id: "pending-retry",
                    kind: .metadata,
                    displayName: "Retry Clip",
                    storageIdentifier: "mobile-source:retry-source"
                )
            ], primaryArtifactID: "pending-retry"),
            error: .networkUnavailable
        ))
        try await repository.saveTask(MobileTaskSnapshot(
            id: "cancelled-source",
            platform: .iOS,
            state: .cancelled,
            result: MobileTaskResult(artifacts: [
                MobileTaskArtifact(
                    id: "pending-cancelled",
                    kind: .metadata,
                    displayName: "Cancelled Clip",
                    storageIdentifier: "mobile-source:cancelled-source"
                )
            ], primaryArtifactID: "pending-cancelled")
        ))
        try await sourceStore.saveSource("https://cdn.example.com/completed.mp4", forTaskID: "completed-source")
        try await sourceStore.saveSource("https://cdn.example.com/retry.mp4", forTaskID: "retry-source")
        try await sourceStore.saveSource("https://cdn.example.com/cancelled.mp4", forTaskID: "cancelled-source")
        try await sourceStore.saveSource("https://cdn.example.com/orphan.mp4", forTaskID: "orphan-source")
        let downloadEngine = RecordingDownloadEngine(result: MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "retried-video",
                kind: .originalMedia,
                displayName: "Retried Clip.mp4",
                storageIdentifier: "downloads/retried.mp4",
                byteCount: 11
            )
        ], primaryArtifactID: "retried-video"))
        let model = IOSMobileAppModel(
            queue: [],
            library: [],
            downloadEngine: downloadEngine,
            taskRepository: repository,
            sourceReferenceStore: sourceStore
        )

        await model.restoreQueueFromRepository()

        XCTAssertEqual(model.library.map(\.title), ["Completed Clip.mp4"])
        let restoredSources = try await sourceStore.loadSources()
        XCTAssertEqual(restoredSources, ["retry-source": "https://cdn.example.com/retry.mp4"])

        await model.performQueueAction(.retry, taskID: "retry-source")
        await model.startDownload(taskID: "retry-source")

        let requests = await downloadEngine.requests()
        XCTAssertEqual(requests.map(\.sourceURL), ["https://cdn.example.com/retry.mp4"])
        XCTAssertEqual(model.queue.first { $0.id == "retry-source" }?.state, .completed)
        let completedSources = try await sourceStore.loadSources()
        XCTAssertEqual(completedSources, [:])
    }

    func testRestoringQueueAppliesFailedAndExpiredBackgroundTransferOutcomesWithoutDroppingUnmatchedOutcomes() async throws {
        let repository = RecordingTaskRepository(tasks: [
            MobileTaskSnapshot(
                id: "failed-background",
                platform: .iOS,
                state: .downloading,
                progress: MobileTaskProgress(phase: .downloading, completedUnitCount: 2, totalUnitCount: 10),
                backgroundPolicy: MobileBackgroundPolicy(execution: .backgroundTransfer, resumability: .resumable)
            ),
            MobileTaskSnapshot(
                id: "expired-background",
                platform: .iOS,
                state: .downloading,
                progress: MobileTaskProgress(phase: .downloading, completedUnitCount: 6, totalUnitCount: 10),
                backgroundPolicy: MobileBackgroundPolicy(execution: .backgroundTransfer, resumability: .resumable)
            )
        ])
        let registry = try BackgroundTransferRegistry(directoryURL: temporaryDirectory())
        try await registry.recordRecoveryOutcome(BackgroundTransferRecoveryOutcome(
            transferIdentifier: "ios.download.failed-background",
            taskID: "failed-background",
            platform: .iOS,
            status: .failed,
            error: .networkUnavailable,
            progress: MobileTaskProgress(phase: .downloading, completedUnitCount: 2, totalUnitCount: 10),
            backgroundPolicy: MobileBackgroundPolicy(execution: .backgroundTransfer, resumability: .resumable),
            updatedAt: Date(timeIntervalSince1970: 4)
        ))
        try await registry.recordRecoveryOutcome(BackgroundTransferRecoveryOutcome(
            transferIdentifier: "ios.download.expired-background",
            taskID: "expired-background",
            platform: .iOS,
            status: .expired,
            progress: MobileTaskProgress(phase: .downloading, completedUnitCount: 6, totalUnitCount: 10),
            backgroundPolicy: MobileBackgroundPolicy(execution: .backgroundTransfer, resumability: .resumable),
            updatedAt: Date(timeIntervalSince1970: 5)
        ))
        try await registry.recordRecoveryOutcome(BackgroundTransferRecoveryOutcome(
            transferIdentifier: "ios.download.unmatched-background",
            taskID: "unmatched-background",
            platform: .iOS,
            status: .completed,
            progress: MobileTaskProgress(phase: .downloading, completedUnitCount: 1, totalUnitCount: 1),
            backgroundPolicy: MobileBackgroundPolicy(execution: .backgroundTransfer, resumability: .resumable),
            updatedAt: Date(timeIntervalSince1970: 6)
        ))
        let model = IOSMobileAppModel(
            queue: [],
            library: [],
            taskRepository: repository,
            backgroundTransferRegistry: registry
        )

        await model.restoreQueueFromRepository()

        let failed = try XCTUnwrap(model.queue.first { $0.id == "failed-background" })
        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(failed.error, .networkUnavailable)
        XCTAssertNil(failed.result)

        let expired = try XCTUnwrap(model.queue.first { $0.id == "expired-background" })
        XCTAssertEqual(expired.state, .needsForegroundToContinue)
        XCTAssertEqual(expired.error, .systemBackgroundLimit)
        XCTAssertEqual(expired.backgroundPolicy.execution, .systemInterrupted)
        XCTAssertTrue(expired.backgroundPolicy.limits.contains(.systemInterrupted))

        XCTAssertTrue(model.library.isEmpty)
        let remainingOutcomes = try await registry.loadRecoveryOutcomes()
        XCTAssertEqual(remainingOutcomes.map(\.taskID), ["unmatched-background"])
    }

    func testRestoringPersistedTasksWithoutRepositoryIsStableAndSideEffectFree() async {
        let task = MobileTaskSnapshot(id: "local", platform: .iOS, state: .waiting)
        let model = IOSMobileAppModel(queue: [task], library: [])

        await model.restoreQueueFromRepository()

        XCTAssertEqual(model.queue, [task])
        XCTAssertTrue(model.library.isEmpty)
    }

    func testRestoringCompletedTaskWithMissingArtifactCreatesLocateableLibraryRecord() async throws {
        let directory = temporaryDirectory()
        let repository = try FileTaskRepository(directoryURL: directory)
        let completedTask = MobileTaskSnapshot(
            id: "missing-after-restore",
            platform: .iOS,
            state: .completed,
            result: MobileTaskResult(artifacts: [
                MobileTaskArtifact(
                    id: "video",
                    kind: .originalMedia,
                    displayName: "Missing After Restore.mp4",
                    storageIdentifier: "Downloads/missing-after-restore.mp4",
                    byteCount: 10
                )
            ], primaryArtifactID: "video")
        )
        try await repository.saveTask(completedTask)
        let model = IOSMobileAppModel(
            queue: [],
            library: [],
            storageDirectoryURL: directory,
            taskRepository: repository
        )

        await model.restoreQueueFromRepository()

        let item = try XCTUnwrap(model.library.first { $0.sourceTaskID == "missing-after-restore" })
        XCTAssertEqual(item.state, .fileMissing)
        XCTAssertEqual(item.availableActions, [.locateFile, .deleteRecord])

        await model.performLibraryAction(.locateFile, itemID: item.id)

        XCTAssertEqual(model.lastLibraryActionOutcome?.presentation, .documentPicker)
        XCTAssertEqual(model.lastLibraryActionStatus, "需要选择文件以重新定位 Missing After Restore.mp4")
    }

    func testLibraryActionsProduceSystemOutcomesAndDeleteRecord() async throws {
        let model = IOSMobileAppModel.preview()
        let itemID = try XCTUnwrap(model.library.first?.id)

        await model.performLibraryAction(.share, itemID: itemID)
        XCTAssertEqual(model.lastLibraryActionOutcome?.action, .share)
        XCTAssertEqual(model.lastLibraryActionOutcome?.presentation, .shareSheet)
        XCTAssertEqual(model.lastLibraryActionOutcome?.status, .requiresSystemPresentation)
        XCTAssertEqual(model.lastLibraryActionOutcome?.artifacts.map(\.kind), [.renderedVideo, .translatedSubtitleFile])
        XCTAssertEqual(model.lastLibraryActionOutcome?.requiresSystemUI, true)
        XCTAssertEqual(model.lastLibraryActionStatus, "需要打开系统分享面板")
        XCTAssertEqual(model.pendingLibraryActionCommand?.intent, .share)
        XCTAssertEqual(model.pendingLibraryActionCommand?.artifacts.map(\.kind), [.renderedVideo, .translatedSubtitleFile])

        await model.performLibraryAction(.saveToFiles, itemID: itemID)
        XCTAssertEqual(model.lastLibraryActionOutcome?.action, .saveToFiles)
        XCTAssertEqual(model.lastLibraryActionOutcome?.presentation, .fileExporter)
        XCTAssertEqual(model.lastLibraryActionOutcome?.status, .requiresSystemPresentation)
        XCTAssertEqual(model.lastLibraryActionOutcome?.artifacts.map(\.displayName), [
            "产品发布片段（中文字幕）.mp4",
            "产品发布片段.zh-Hans.srt"
        ])
        XCTAssertEqual(model.lastLibraryActionStatus, "需要选择保存位置")

        await model.performLibraryAction(.saveToPhotos, itemID: itemID)
        XCTAssertEqual(model.lastLibraryActionOutcome?.action, .saveToPhotos)
        XCTAssertEqual(model.lastLibraryActionOutcome?.presentation, .photoLibraryExporter)
        XCTAssertEqual(model.lastLibraryActionOutcome?.status, .requiresSystemPresentation)
        XCTAssertEqual(model.lastLibraryActionOutcome?.artifacts.map(\.kind), [.renderedVideo])
        XCTAssertEqual(model.lastLibraryActionStatus, "需要授权保存到照片")

        await model.performLibraryAction(.deleteRecord, itemID: itemID)
        XCTAssertFalse(model.library.contains { $0.id == itemID })
        XCTAssertEqual(model.lastLibraryActionOutcome?.status, .completed)
        XCTAssertEqual(model.lastLibraryActionOutcome?.completedRecordMutation, true)
        XCTAssertEqual(model.lastLibraryActionStatus, "已删除记录 产品发布片段")
        XCTAssertNil(model.pendingLibraryActionCommand)
    }

    func testDeletingLibraryRecordRemovesCompletedQueueProjectionAndPersistedTask() async throws {
        let completedResult = MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "video",
                kind: .originalMedia,
                displayName: "Deleted Clip.mp4",
                storageIdentifier: "downloads/deleted-clip.mp4",
                byteCount: 11
            )
        ], primaryArtifactID: "video")
        let completedTask = MobileTaskSnapshot(
            id: "deleted-task",
            platform: .iOS,
            state: .completed,
            result: completedResult
        )
        let repository = RecordingTaskRepository(tasks: [completedTask])
        let model = IOSMobileAppModel(
            queue: [completedTask],
            library: [
                MobileLibraryItem(
                    id: "library-deleted-task",
                    title: "Deleted Clip.mp4",
                    createdAt: Date(timeIntervalSince1970: 1),
                    artifacts: completedResult.artifacts,
                    state: .available,
                    sourceTaskID: "deleted-task"
                )
            ],
            taskRepository: repository
        )

        await model.performLibraryAction(.deleteRecord, itemID: "library-deleted-task")

        XCTAssertTrue(model.library.isEmpty)
        XCTAssertFalse(model.queue.contains { $0.id == "deleted-task" })
        XCTAssertEqual(model.lastLibraryActionOutcome?.status, .completed)
        XCTAssertEqual(model.lastLibraryActionOutcome?.completedRecordMutation, true)
        let storedTasksAfterDelete = try await repository.loadTasks()
        XCTAssertFalse(storedTasksAfterDelete.contains { $0.id == "deleted-task" })

        let relaunched = IOSMobileAppModel(
            queue: [],
            library: [],
            taskRepository: repository
        )
        await relaunched.restoreQueueFromRepository()

        XCTAssertTrue(relaunched.queue.isEmpty)
        XCTAssertTrue(relaunched.library.isEmpty)
    }

    func testLibraryActionsRepresentMissingMediaDisallowedActionsAndLocateFileSystemUI() async throws {
        let subtitle = MobileTaskArtifact(
            id: "subtitle",
            kind: .translatedSubtitleFile,
            displayName: "clip.zh-Hans.srt",
            storageIdentifier: "subtitles/clip.zh-Hans.srt"
        )
        let item = MobileLibraryItem(
            id: "subtitle-only",
            title: "字幕文件",
            createdAt: Date(timeIntervalSince1970: 1),
            artifacts: [subtitle],
            state: .available
        )
        let missing = MobileLibraryItem(
            id: "missing",
            title: "缺失文件",
            createdAt: Date(timeIntervalSince1970: 2),
            artifacts: [],
            state: .fileMissing
        )
        let model = IOSMobileAppModel(library: [item, missing])

        await model.performLibraryAction(.saveToPhotos, itemID: "subtitle-only")
        XCTAssertEqual(model.library.count, 2)
        XCTAssertEqual(model.lastLibraryActionOutcome?.presentation, .unavailable)
        XCTAssertEqual(model.lastLibraryActionOutcome?.status, .unavailable)
        XCTAssertEqual(model.lastLibraryActionOutcome?.artifacts, [])
        XCTAssertEqual(model.lastLibraryActionOutcome?.requiresSystemUI, false)
        XCTAssertEqual(model.lastLibraryActionStatus, "没有可存到照片的视频")

        await model.performLibraryAction(.locateFile, itemID: "missing")
        XCTAssertEqual(model.lastLibraryActionOutcome?.presentation, .documentPicker)
        XCTAssertEqual(model.lastLibraryActionOutcome?.status, .requiresSystemPresentation)
        XCTAssertEqual(model.lastLibraryActionOutcome?.requiresSystemUI, true)
        XCTAssertEqual(model.lastLibraryActionStatus, "需要选择文件以重新定位 缺失文件")

        await model.performLibraryAction(.share, itemID: "does-not-exist")
        XCTAssertEqual(model.lastLibraryActionOutcome?.status, .unavailable)
        XCTAssertEqual(model.lastLibraryActionOutcome?.itemID, "does-not-exist")
        XCTAssertEqual(model.lastLibraryActionStatus, "未找到记录")
    }

    func testRelocatingMissingLibraryFileCopiesIntoAppStorageAndUpdatesPersistedTask() async throws {
        let directory = temporaryDirectory()
        let importedURL = directory.appendingPathComponent("external-picked-video.mp4", isDirectory: false)
        try Data("relocated-video".utf8).write(to: importedURL)
        let missingArtifact = MobileTaskArtifact(
            id: "video",
            kind: .originalMedia,
            displayName: "Missing Clip.mp4",
            storageIdentifier: "Downloads/missing-clip.mp4",
            byteCount: 111
        )
        let missingResult = MobileTaskResult(artifacts: [missingArtifact], primaryArtifactID: missingArtifact.id)
        let missingTask = MobileTaskSnapshot(
            id: "missing-task",
            platform: .iOS,
            state: .completed,
            result: missingResult
        )
        let repository = try FileTaskRepository(directoryURL: directory)
        try await repository.saveTask(missingTask)
        let model = IOSMobileAppModel(
            queue: [missingTask],
            library: [
                MobileLibraryItem(
                    id: "library-missing-task",
                    title: "Missing Clip.mp4",
                    createdAt: Date(timeIntervalSince1970: 2),
                    artifacts: [missingArtifact],
                    state: .fileMissing,
                    sourceTaskID: "missing-task"
                )
            ],
            storageDirectoryURL: directory,
            taskRepository: repository
        )

        await model.relocateLibraryFile(itemID: "library-missing-task", pickedFileURL: importedURL)

        let item = try XCTUnwrap(model.library.first { $0.id == "library-missing-task" })
        XCTAssertEqual(item.state, .available)
        XCTAssertEqual(item.availableActions, [.open, .share, .saveToFiles, .saveToPhotos, .deleteRecord])
        XCTAssertEqual(item.artifacts.first?.displayName, "external-picked-video.mp4")
        XCTAssertEqual(item.artifacts.first?.storageIdentifier, "Downloads/missing-task-video-external-picked-video.mp4")
        XCTAssertEqual(item.artifacts.first?.byteCount, 15)
        XCTAssertEqual(model.queue.first { $0.id == "missing-task" }?.result?.primaryArtifact, item.artifacts.first)
        XCTAssertEqual(model.lastLibraryActionOutcome?.status, .completed)
        XCTAssertEqual(model.lastLibraryActionStatus, "已重新定位 external-picked-video.mp4")

        let copiedURL = directory.appendingPathComponent("Downloads/missing-task-video-external-picked-video.mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copiedURL.path))
        XCTAssertEqual(try Data(contentsOf: copiedURL), Data("relocated-video".utf8))
        let storedTasks = try await repository.loadTasks()
        let storedTask = try XCTUnwrap(storedTasks.first { $0.id == "missing-task" })
        XCTAssertEqual(storedTask.result?.primaryArtifact, item.artifacts.first)
        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(storedTask), encoding: .utf8))
        XCTAssertFalse(encoded.contains(importedURL.path))
        XCTAssertFalse(encoded.contains("file://"))
    }

    func testRelocatingMissingLibraryFileWithoutQueueTaskFailsInsteadOfClaimingPersistence() async throws {
        let directory = temporaryDirectory()
        let importedURL = directory.appendingPathComponent("external-picked-video.mp4", isDirectory: false)
        try Data("relocated-video".utf8).write(to: importedURL)
        let model = IOSMobileAppModel(
            queue: [],
            library: [
                MobileLibraryItem(
                    id: "library-stale-task",
                    title: "Stale Clip.mp4",
                    createdAt: Date(timeIntervalSince1970: 3),
                    artifacts: [
                        MobileTaskArtifact(
                            id: "video",
                            kind: .originalMedia,
                            displayName: "Stale Clip.mp4",
                            storageIdentifier: "Downloads/stale.mp4"
                        )
                    ],
                    state: .fileMissing,
                    sourceTaskID: "stale-task"
                )
            ],
            storageDirectoryURL: directory,
            taskRepository: try FileTaskRepository(directoryURL: directory)
        )

        await model.relocateLibraryFile(itemID: "library-stale-task", pickedFileURL: importedURL)

        XCTAssertEqual(model.library.first?.state, .fileMissing)
        XCTAssertEqual(model.lastLibraryActionOutcome?.status, .failed)
        XCTAssertEqual(model.lastLibraryActionStatus, "无法重新定位文件")
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("Downloads/stale-task-video-external-picked-video.mp4").path
            )
        )
    }

    func testOpenPreparedLibraryOutcomeCreatesPreviewCommandAndPendingCommandIsConsumedOnce() async throws {
        let model = IOSMobileAppModel.preview()
        let itemID = try XCTUnwrap(model.library.first?.id)

        await model.performLibraryAction(.open, itemID: itemID)

        XCTAssertEqual(model.lastLibraryActionOutcome?.status, .prepared)
        XCTAssertEqual(model.pendingLibraryActionCommand?.intent, .open)
        XCTAssertEqual(model.pendingLibraryActionCommand?.presentation, .inAppOpen)
        XCTAssertEqual(model.pendingLibraryActionCommand?.artifacts.map(\.kind), [.renderedVideo])

        let command = model.consumePendingLibraryActionCommand()

        XCTAssertEqual(command?.intent, .open)
        XCTAssertNil(model.consumePendingLibraryActionCommand())
        XCTAssertEqual(model.lastLibraryActionOutcome?.status, .prepared)
        XCTAssertEqual(model.lastLibraryActionStatus, "准备打开 产品发布片段（中文字幕）.mp4")
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("moongate-ios-mobile-app-model-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func waitForStoredTask(
        in repository: RecordingTaskRepository,
        matching predicate: (MobileTaskSnapshot) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> MobileTaskSnapshot {
        for _ in 0..<50 {
            let tasks = try await repository.loadTasks()
            if let task = tasks.first(where: predicate) {
                return task
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Timed out waiting for persisted task state.", file: file, line: line)
        let tasks = try await repository.loadTasks()
        return try XCTUnwrap(tasks.first, file: file, line: line)
    }

    private func waitForCondition(
        _ description: String,
        matching predicate: () async -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> Bool {
        for _ in 0..<50 {
            if await predicate() {
                return true
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Timed out waiting for \(description).", file: file, line: line)
        return false
    }
}

private actor RecordingTranslationRuntimeReadinessEvaluator: TranslationRuntimeReadinessEvaluating {
    private let evaluate: @Sendable (TranslationRuntimeReadinessRequest) async -> TranslationReadiness
    private var recordedRequests: [TranslationRuntimeReadinessRequest] = []

    init(evaluate: @escaping @Sendable (TranslationRuntimeReadinessRequest) async -> TranslationReadiness) {
        self.evaluate = evaluate
    }

    func readiness(for request: TranslationRuntimeReadinessRequest) async -> TranslationReadiness {
        recordedRequests.append(request)
        return await evaluate(request)
    }

    func requests() -> [TranslationRuntimeReadinessRequest] {
        recordedRequests
    }
}

private struct SuccessfulMobileParser: MobileParser {
    func resolveCandidates(for input: MobileInputSource) async throws -> [MobileVideoCandidate] {
        [
            MobileVideoCandidate(
                id: "injected-candidate",
                sourceURL: input.value,
                kind: .directFile,
                title: "Injected video"
            )
        ]
    }

    func analyze(candidate: MobileVideoCandidate) async throws -> MobileVideoInfo {
        MobileVideoInfo(
            candidate: candidate,
            videoID: "injected-video",
            title: "Injected video",
            durationSeconds: 42,
            formats: [
                MobileFormatChoice(id: "mobile-best", label: "Mobile best", detail: nil, height: 720)
            ],
            subtitles: [
                MobileSubtitleChoice(id: "en", languageCode: "en", label: "English", isAutoGenerated: false)
            ]
        )
    }
}

private struct MultipleCandidateMobileParser: MobileParser {
    func resolveCandidates(for input: MobileInputSource) async throws -> [MobileVideoCandidate] {
        [
            MobileVideoCandidate(
                id: "main",
                sourceURL: input.value,
                kind: .directFile,
                title: "Main video"
            ),
            MobileVideoCandidate(
                id: "alternate",
                sourceURL: input.value,
                kind: .directFile,
                title: "Alternate video"
            )
        ]
    }

    func analyze(candidate: MobileVideoCandidate) async throws -> MobileVideoInfo {
        MobileVideoInfo(
            candidate: candidate,
            videoID: "multiple-candidate-video",
            title: candidate.title,
            durationSeconds: 42,
            formats: [
                MobileFormatChoice(id: "mobile-best", label: "Mobile best", detail: nil, height: 720)
            ],
            subtitles: []
        )
    }
}

private struct MultiChoiceMobileParser: MobileParser {
    func resolveCandidates(for input: MobileInputSource) async throws -> [MobileVideoCandidate] {
        [
            MobileVideoCandidate(
                id: "multi-choice-candidate",
                sourceURL: input.value,
                kind: .directFile,
                title: "Selectable clip"
            )
        ]
    }

    func analyze(candidate: MobileVideoCandidate) async throws -> MobileVideoInfo {
        MobileVideoInfo(
            candidate: candidate,
            videoID: "selectable-video",
            title: "Selectable clip",
            durationSeconds: 64,
            formats: [
                MobileFormatChoice(id: "1080p", label: "1080p", detail: "高清", height: 1080),
                MobileFormatChoice(id: "720p", label: "720p", detail: "省流量", height: 720)
            ],
            subtitles: [
                MobileSubtitleChoice(id: "en", languageCode: "en", label: "English", isAutoGenerated: false),
                MobileSubtitleChoice(id: "zh-Hans-auto", languageCode: "zh-Hans", label: "简体中文自动字幕", isAutoGenerated: true)
            ]
        )
    }
}

private struct SidecarSubtitleMobileParser: MobileParser {
    var sidecarURL: URL

    func resolveCandidates(for input: MobileInputSource) async throws -> [MobileVideoCandidate] {
        [
            MobileVideoCandidate(
                id: "sidecar-candidate",
                sourceURL: input.value,
                kind: .directFile,
                title: "Sidecar clip"
            )
        ]
    }

    func analyze(candidate: MobileVideoCandidate) async throws -> MobileVideoInfo {
        MobileVideoInfo(
            candidate: candidate,
            videoID: "sidecar-video",
            title: "Sidecar clip",
            durationSeconds: 64,
            formats: [
                MobileFormatChoice(id: "mp4", label: "MP4", detail: nil, height: 720)
            ],
            subtitles: [
                MobileSubtitleChoice(
                    id: "en-sidecar",
                    languageCode: "en",
                    label: "English sidecar",
                    isAutoGenerated: false,
                    source: .localFile(sidecarURL)
                )
            ]
        )
    }
}

private actor RecordingCredentialStore: SecureCredentialStore {
    enum Error: Swift.Error {
        case saveFailed
    }

    private let saveError: Swift.Error?
    private var secrets: [String] = []
    private var references: [SecureCredentialReference] = []
    private var deletions: [SecureCredentialReference] = []

    init(saveError: Swift.Error? = nil) {
        self.saveError = saveError
    }

    func saveCredential(
        _ secret: String,
        for reference: SecureCredentialReference
    ) async throws -> SecureCredentialReference {
        if let saveError {
            throw saveError
        }
        secrets.append(secret)
        references.append(reference)
        return reference
    }

    func deleteCredential(_ reference: SecureCredentialReference) async throws {
        deletions.append(reference)
    }

    func hasCredential(_ reference: SecureCredentialReference) async throws -> Bool {
        references.contains(reference)
    }

    func credential(for reference: SecureCredentialReference) async throws -> String? {
        guard let index = references.firstIndex(of: reference) else {
            return nil
        }
        return secrets[index]
    }

    func savedSecrets() -> [String] {
        secrets
    }

    func savedReferences() -> [SecureCredentialReference] {
        references
    }

    func deletedReferences() -> [SecureCredentialReference] {
        deletions
    }
}

private actor RecordingConnectionTestTransport: MobileTranslationTransport {
    private let statusCode: Int
    private let responseText: String
    private var recordedRequests: [MobileTranslationTransportRequest] = []

    init(statusCode: Int, responseText: String) {
        self.statusCode = statusCode
        self.responseText = responseText
    }

    func send(_ request: MobileTranslationTransportRequest) async throws -> MobileTranslationTransportResponse {
        recordedRequests.append(request)
        return MobileTranslationTransportResponse(statusCode: statusCode, body: Data(responseText.utf8))
    }

    func firstRecordedRequest() -> MobileTranslationTransportRequest? {
        recordedRequests.first
    }
}

private actor RecordingDownloadEngine: MobileDownloadEngine {
    private let result: MobileTaskResult?
    private let error: Error?
    private var recordedRequests: [MobileDownloadRequest] = []

    init(result: MobileTaskResult? = nil, error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func download(
        _ request: MobileDownloadRequest,
        progress: @escaping @Sendable (MobileTaskProgress) -> Void
    ) async throws -> MobileTaskResult {
        recordedRequests.append(request)
        progress(MobileTaskProgress(phase: .downloading, completedUnitCount: 5, totalUnitCount: 11))
        if let error {
            throw error
        }
        progress(MobileTaskProgress(phase: .downloading, completedUnitCount: 11, totalUnitCount: 11))
        return result ?? MobileTaskResult()
    }

    func requests() -> [MobileDownloadRequest] {
        recordedRequests
    }
}

private final class RecordingImportedFileAccessor: IOSImportedFileAccessing, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEvents: [String] = []
    private var recordedURLs: [URL] = []

    func withAccess<T>(
        to url: URL,
        _ operation: () throws -> T
    ) rethrows -> T {
        lock.lock()
        recordedURLs.append(url)
        recordedEvents.append("start:\(url.lastPathComponent)")
        lock.unlock()
        defer {
            lock.lock()
            recordedEvents.append("stop:\(url.lastPathComponent)")
            lock.unlock()
        }
        return try operation()
    }

    func events() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedEvents
    }

    func accessedURLs() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return recordedURLs
    }
}

private final class RecordingImportStorageChecker: IOSImportStorageChecking, @unchecked Sendable {
    struct Request {
        var source: URL
        var storage: URL
    }

    private let lock = NSLock()
    private let result: Bool
    private var recordedRequests: [Request] = []

    init(result: Bool) {
        self.result = result
    }

    func hasEnoughSpaceToImport(
        sourceURL: URL,
        storageDirectoryURL: URL
    ) -> Bool {
        lock.lock()
        recordedRequests.append(Request(source: sourceURL, storage: storageDirectoryURL))
        lock.unlock()
        return result
    }

    func requests() -> [Request] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }
}

private actor RecordingBackgroundDownloadStarter: IOSBackgroundDownloadStarting {
    private let registry: BackgroundTransferRegistry
    private var recordedRequests: [MobileDownloadRequest] = []
    private var recordedEvents: [String] = []

    init(registry: BackgroundTransferRegistry) {
        self.registry = registry
    }

    func startBackgroundDownload(
        _ request: MobileDownloadRequest
    ) async throws -> IOSBackgroundURLSessionDownloadStartResult {
        recordedRequests.append(request)
        recordedEvents.append("start:\(request.id)")
        let safeTaskID = request.id
        let record = BackgroundTransferRecord(
            transferIdentifier: "ios.download.\(safeTaskID)",
            taskID: request.id,
            platform: .iOS,
            backgroundPolicy: MobileBackgroundPolicy(
                execution: .backgroundTransfer,
                resumability: .resumable,
                limits: [.systemDeferred]
            ),
            artifactStorageIdentifier: "downloads/\(safeTaskID).mp4",
            lastProgress: MobileTaskProgress(phase: .downloading, completedUnitCount: 0),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        try await registry.record(record)
        return IOSBackgroundURLSessionDownloadStartResult(
            transferIdentifier: record.transferIdentifier,
            record: record
        )
    }

    func requests() -> [MobileDownloadRequest] {
        recordedRequests
    }

    func cancelBackgroundDownload(taskID: String) async throws {
        recordedEvents.append("cancel:\(taskID)")
        recordedEvents.append("registry-empty:\((try await registry.loadRecords()).isEmpty)")
    }

    func events() -> [String] {
        recordedEvents
    }
}

private actor RecordingTranslationProvider: MobileTranslationProvider {
    private let result: MobileTranslationResult?
    private let error: Error?
    private var recordedRequests: [MobileTranslationRequest] = []

    init(result: MobileTranslationResult? = nil, error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func readiness(for context: TranslationContext) async -> TranslationReadiness {
        error == nil ? .ready : TranslationReadiness(issues: [
            TranslationReadinessIssue(kind: .needsConfiguration)
        ])
    }

    func translate(_ request: MobileTranslationRequest) async throws -> MobileTranslationResult {
        recordedRequests.append(request)
        if let error {
            throw error
        }
        return result ?? MobileTranslationResult(segments: [])
    }

    func requests() -> [MobileTranslationRequest] {
        recordedRequests
    }
}

private actor RecordingIOSAppleTranslationExecutor: IOSAppleTranslationExecuting {
    private let responses: [String: String]
    private var requests: [IOSAppleTranslationRequest] = []

    init(responses: [String: String]) {
        self.responses = responses
    }

    func translate(_ request: IOSAppleTranslationRequest) async throws -> [String: String] {
        requests.append(request)
        return responses
    }

    func recordedRequests() -> [IOSAppleTranslationRequest] {
        requests
    }
}

private actor SuspendedDownloadEngine: MobileDownloadEngine {
    private let result: MobileTaskResult
    private var recordedRequests: [MobileDownloadRequest] = []
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var finishContinuation: CheckedContinuation<MobileTaskResult, Error>?

    init(result: MobileTaskResult) {
        self.result = result
    }

    func download(
        _ request: MobileDownloadRequest,
        progress: @escaping @Sendable (MobileTaskProgress) -> Void
    ) async throws -> MobileTaskResult {
        recordedRequests.append(request)
        progress(MobileTaskProgress(phase: .downloading, completedUnitCount: 1, totalUnitCount: 2))
        return try await withCheckedThrowingContinuation { continuation in
            finishContinuation = continuation
            startedContinuation?.resume()
            startedContinuation = nil
        }
    }

    func waitUntilStarted() async {
        guard recordedRequests.isEmpty else {
            return
        }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func complete() {
        finishContinuation?.resume(returning: result)
        finishContinuation = nil
    }

    func requests() -> [MobileDownloadRequest] {
        recordedRequests
    }
}

private actor CancellableSuspendedDownloadEngine: MobileDownloadEngine {
    private let result: MobileTaskResult
    private var recordedRequests: [MobileDownloadRequest] = []
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var finishContinuation: CheckedContinuation<MobileTaskResult, Error>?
    private var observedCancellation = false

    init(result: MobileTaskResult) {
        self.result = result
    }

    func download(
        _ request: MobileDownloadRequest,
        progress: @escaping @Sendable (MobileTaskProgress) -> Void
    ) async throws -> MobileTaskResult {
        recordedRequests.append(request)
        progress(MobileTaskProgress(phase: .downloading, completedUnitCount: 1, totalUnitCount: 2))
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                finishContinuation = continuation
                startedContinuation?.resume()
                startedContinuation = nil
            }
        } onCancel: {
            Task {
                await self.cancelSuspendedDownload()
            }
        }
    }

    func waitUntilStarted() async {
        guard finishContinuation == nil else {
            return
        }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func complete() {
        finishContinuation?.resume(returning: result)
        finishContinuation = nil
    }

    func didObserveCancellation() -> Bool {
        observedCancellation
    }

    private func cancelSuspendedDownload() {
        observedCancellation = true
        finishContinuation?.resume(throwing: CancellationError())
        finishContinuation = nil
    }
}

private actor SuspendedSubtitleProcessor: SubtitleProcessor {
    private let result: MobileTaskArtifact
    private let completionError: Error?
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var finishContinuation: CheckedContinuation<MobileTaskArtifact, Error>?

    init(result: MobileTaskArtifact) {
        self.result = result
        self.completionError = nil
    }

    init(error: Error) {
        self.result = MobileTaskArtifact(
            id: "unused",
            kind: .translatedSubtitleFile,
            displayName: "unused.srt",
            storageIdentifier: "unused.srt"
        )
        self.completionError = error
    }

    func process(
        _ request: MobileSubtitleProcessingRequest,
        progress: @escaping @Sendable (MobileTaskProgress) -> Void
    ) async throws -> MobileTaskArtifact {
        progress(MobileTaskProgress(phase: .translating, completedUnitCount: 1, totalUnitCount: 2))
        return try await withCheckedThrowingContinuation { continuation in
            finishContinuation = continuation
            startedContinuation?.resume()
            startedContinuation = nil
        }
    }

    func waitUntilStarted() async {
        guard finishContinuation == nil else {
            return
        }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func complete() {
        if let completionError {
            finishContinuation?.resume(throwing: completionError)
        } else {
            finishContinuation?.resume(returning: result)
        }
        finishContinuation = nil
    }
}

private actor CancellableSuspendedSubtitleProcessor: SubtitleProcessor {
    private let result: MobileTaskArtifact
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var finishContinuation: CheckedContinuation<MobileTaskArtifact, Error>?
    private var observedCancellation = false

    init(result: MobileTaskArtifact) {
        self.result = result
    }

    func process(
        _ request: MobileSubtitleProcessingRequest,
        progress: @escaping @Sendable (MobileTaskProgress) -> Void
    ) async throws -> MobileTaskArtifact {
        progress(MobileTaskProgress(phase: .translating, completedUnitCount: 1, totalUnitCount: 2))
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                finishContinuation = continuation
                startedContinuation?.resume()
                startedContinuation = nil
            }
        } onCancel: {
            Task {
                await self.cancelSuspendedProcessing()
            }
        }
    }

    func waitUntilStarted() async {
        guard finishContinuation == nil else {
            return
        }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func complete() {
        finishContinuation?.resume(returning: result)
        finishContinuation = nil
    }

    func didObserveCancellation() -> Bool {
        observedCancellation
    }

    private func cancelSuspendedProcessing() {
        observedCancellation = true
        finishContinuation?.resume(throwing: CancellationError())
        finishContinuation = nil
    }
}

private actor RecordingSubtitleProcessor: SubtitleProcessor {
    private let result: MobileTaskArtifact
    private let error: Error?
    private var recordedRequests: [MobileSubtitleProcessingRequest] = []

    init(result: MobileTaskArtifact) {
        self.result = result
        self.error = nil
    }

    init(error: Error) {
        self.result = MobileTaskArtifact(
            id: "unused",
            kind: .translatedSubtitleFile,
            displayName: "unused.srt",
            storageIdentifier: "unused.srt"
        )
        self.error = error
    }

    func process(
        _ request: MobileSubtitleProcessingRequest,
        progress: @escaping @Sendable (MobileTaskProgress) -> Void
    ) async throws -> MobileTaskArtifact {
        recordedRequests.append(request)
        progress(MobileTaskProgress(phase: .translating, completedUnitCount: 1, totalUnitCount: 1))
        if let error {
            throw error
        }
        return result
    }

    func requests() -> [MobileSubtitleProcessingRequest] {
        recordedRequests
    }
}

private actor SequencedSubtitleProcessor: SubtitleProcessor {
    enum Outcome {
        case success(MobileTaskArtifact)
        case failure(Error)
    }

    private var outcomes: [Outcome]
    private var recordedRequests: [MobileSubtitleProcessingRequest] = []

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func process(
        _ request: MobileSubtitleProcessingRequest,
        progress: @escaping @Sendable (MobileTaskProgress) -> Void
    ) async throws -> MobileTaskArtifact {
        recordedRequests.append(request)
        progress(MobileTaskProgress(phase: .translating, completedUnitCount: 1, totalUnitCount: 1))
        let outcome = outcomes.isEmpty ? .failure(MobileTaskError.exportFailed) : outcomes.removeFirst()
        switch outcome {
        case .success(let artifact):
            return artifact
        case .failure(let error):
            throw error
        }
    }

    func requests() -> [MobileSubtitleProcessingRequest] {
        recordedRequests
    }
}

private actor RecordingRenderExporter: RenderExporter {
    private let result: MobileTaskResult
    private let error: Error?
    private var recordedRequests: [MobileRenderRequest] = []

    init(result: MobileTaskResult) {
        self.result = result
        self.error = nil
    }

    init(error: Error) {
        self.result = MobileTaskResult()
        self.error = error
    }

    func export(
        _ request: MobileRenderRequest,
        progress: @escaping @Sendable (MobileTaskProgress) -> Void
    ) async throws -> MobileTaskResult {
        recordedRequests.append(request)
        progress(MobileTaskProgress(phase: .exporting, completedUnitCount: 1, totalUnitCount: 1))
        if let error {
            throw error
        }
        return result
    }

    func requests() -> [MobileRenderRequest] {
        recordedRequests
    }
}

private actor SequencedRenderExporter: RenderExporter {
    enum Outcome {
        case success(MobileTaskResult)
        case failure(Error)
    }

    private var outcomes: [Outcome]
    private var recordedRequests: [MobileRenderRequest] = []

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func export(
        _ request: MobileRenderRequest,
        progress: @escaping @Sendable (MobileTaskProgress) -> Void
    ) async throws -> MobileTaskResult {
        recordedRequests.append(request)
        progress(MobileTaskProgress(phase: .exporting, completedUnitCount: 1, totalUnitCount: 1))
        let outcome = outcomes.isEmpty ? .failure(MobileTaskError.exportFailed) : outcomes.removeFirst()
        switch outcome {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }

    func requests() -> [MobileRenderRequest] {
        recordedRequests
    }
}

private actor RecordingContinuedProcessingSubmitter: IOSContinuedProcessingTaskSubmitting {
    private var submittedDescriptors: [IOSContinuedProcessingRequestDescriptor] = []

    func submit(_ descriptor: IOSContinuedProcessingRequestDescriptor) async throws {
        submittedDescriptors.append(descriptor)
    }

    func descriptors() -> [IOSContinuedProcessingRequestDescriptor] {
        submittedDescriptors
    }
}

private actor SuspendedRenderExporter: RenderExporter {
    private let result: MobileTaskResult
    private var recordedRequests: [MobileRenderRequest] = []
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var finishContinuation: CheckedContinuation<MobileTaskResult, Error>?

    init(result: MobileTaskResult) {
        self.result = result
    }

    func export(
        _ request: MobileRenderRequest,
        progress: @escaping @Sendable (MobileTaskProgress) -> Void
    ) async throws -> MobileTaskResult {
        recordedRequests.append(request)
        progress(MobileTaskProgress(phase: .exporting, completedUnitCount: 1, totalUnitCount: 2))
        return try await withCheckedThrowingContinuation { continuation in
            finishContinuation = continuation
            startedContinuation?.resume()
            startedContinuation = nil
        }
    }

    func waitUntilStarted() async {
        guard finishContinuation == nil else {
            return
        }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func complete() {
        finishContinuation?.resume(returning: result)
        finishContinuation = nil
    }

    func requests() -> [MobileRenderRequest] {
        recordedRequests
    }
}

private actor CancellableSuspendedRenderExporter: RenderExporter {
    private let result: MobileTaskResult
    private var recordedRequests: [MobileRenderRequest] = []
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var finishContinuation: CheckedContinuation<MobileTaskResult, Error>?
    private var observedCancellation = false

    init(result: MobileTaskResult) {
        self.result = result
    }

    func export(
        _ request: MobileRenderRequest,
        progress: @escaping @Sendable (MobileTaskProgress) -> Void
    ) async throws -> MobileTaskResult {
        recordedRequests.append(request)
        progress(MobileTaskProgress(phase: .exporting, completedUnitCount: 1, totalUnitCount: 2))
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                finishContinuation = continuation
                startedContinuation?.resume()
                startedContinuation = nil
            }
        } onCancel: {
            Task {
                await self.cancelSuspendedExport()
            }
        }
    }

    func waitUntilStarted() async {
        guard finishContinuation == nil else {
            return
        }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func complete() {
        finishContinuation?.resume(returning: result)
        finishContinuation = nil
    }

    func didObserveCancellation() -> Bool {
        observedCancellation
    }

    private func cancelSuspendedExport() {
        observedCancellation = true
        finishContinuation?.resume(throwing: CancellationError())
        finishContinuation = nil
    }
}

private actor RecordingTaskRepository: TaskRepository {
    private var tasks: [MobileTaskSnapshot] = []
    private var savedHistory: [MobileTaskSnapshot] = []

    init(tasks: [MobileTaskSnapshot] = []) {
        self.tasks = tasks
    }

    func loadTasks() async throws -> [MobileTaskSnapshot] {
        tasks
    }

    func saveTask(_ snapshot: MobileTaskSnapshot) async throws {
        tasks.removeAll { $0.id == snapshot.id }
        tasks.append(snapshot)
        savedHistory.append(snapshot)
    }

    func removeTask(id: String) async throws {
        tasks.removeAll { $0.id == id }
    }

    func savedTasks() -> [MobileTaskSnapshot] {
        savedHistory
    }
}
