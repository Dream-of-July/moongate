import XCTest

final class PackageBoundaryTests: XCTestCase {
    func testIOSShellDependsOnMobileCoreInsteadOfDesktopCore() throws {
        let manifest = try String(contentsOf: packageRoot().appendingPathComponent("Package.swift"))

        XCTAssertTrue(
            manifest.contains(#".target(name: "MoongateMobileCore""#),
            "Package.swift should declare a pure mobile core target."
        )
        XCTAssertNotNil(
            manifest.range(
                of: #"(?s)\.target\(\s*name:\s*"MoongateiOS",\s*dependencies:\s*\["MoongateMobileCore"\]"#,
                options: .regularExpression
            ),
            "MoongateiOS should depend on MoongateMobileCore, not desktop MoongateCore."
        )
        XCTAssertNil(
            manifest.range(
                of: #"(?s)\.target\(\s*name:\s*"MoongateiOS",\s*dependencies:\s*\["MoongateCore"\]"#,
                options: .regularExpression
            ),
            "MoongateiOS must not pull in the desktop Process/Homebrew/ffmpeg core."
        )
    }

    func testDesktopCoreIsNotExposedAsMobileFacingLibraryProduct() throws {
        let root = packageRoot()
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"))
        let engineSource = try String(contentsOf: root
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateCore")
            .appendingPathComponent("Engine.swift"))
        let dependencySource = try String(contentsOf: root
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateCore")
            .appendingPathComponent("DependencySetup.swift"))

        XCTAssertTrue(
            manifest.contains(#".target(name: "MoongateCore", dependencies: ["MoongateMobileCore"], path: "Sources/MoongateCore")"#),
            "The desktop core target should remain available to macOS, CLI, and tests."
        )
        XCTAssertTrue(
            manifest.contains(#".executable(name: "moongate-cli", targets: ["moongate-cli"])"#),
            "The CLI product should continue to expose the desktop core workflow."
        )
        XCTAssertTrue(
            engineSource.contains("Process()") || engineSource.contains("Process("),
            "This boundary test only applies while MoongateCore still wraps desktop subprocess tools."
        )
        XCTAssertTrue(
            dependencySource.contains("Homebrew") || dependencySource.contains("brew"),
            "This boundary test only applies while MoongateCore still owns desktop dependency setup."
        )
        XCTAssertFalse(
            manifest.contains(#".library(name: "MoongateCore", targets: ["MoongateCore"])"#),
            "MoongateCore contains desktop Process/Homebrew/yt-dlp/ffmpeg behavior and should not be advertised as an iOS-capable library product."
        )
    }

    func testIOSAppHostExistsAndDependsOnShellOnly() throws {
        let root = packageRoot()
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"))
        let appFile = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOSApp")
            .appendingPathComponent("MoongateiOSApp.swift")

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: appFile.path),
            "A native iOS SwiftUI app host should exist instead of only a shell library."
        )
        XCTAssertNotNil(
            manifest.range(
                of: #"(?s)\.executableTarget\(\s*name:\s*"MoongateiOSApp",\s*dependencies:\s*\["MoongateiOS"\]"#,
                options: .regularExpression
            ),
            "MoongateiOSApp should depend on the iOS shell target, not desktop MoongateCore."
        )
        XCTAssertNil(
            manifest.range(
                of: #"(?s)\.executableTarget\(\s*name:\s*"MoongateiOSApp",\s*dependencies:\s*\[[^\]]*"MoongateCore""#,
                options: .regularExpression
            ),
            "The iOS app host must not depend on the desktop core target."
        )
    }

    func testIOSAppHostTargetIsDeclaredOnlyOnce() throws {
        let manifest = try String(contentsOf: packageRoot().appendingPathComponent("Package.swift"))
        let matches = manifest.matches(
            of: #"\.(?:executableTarget|target)\(\s*name:\s*"MoongateiOSApp""#
        )

        XCTAssertEqual(matches.count, 1, "MoongateiOSApp should be declared once.")
    }

    func testREADMEStatesMobileTargetsAreWorkInProgressAndNoShip() throws {
        let readme = try String(contentsOf: packageRoot().appendingPathComponent("README.md"))

        XCTAssertTrue(readme.contains("## 移动端状态"))
        XCTAssertTrue(readme.contains("no-ship"))
        XCTAssertTrue(readme.contains("iOS"))
        XCTAssertTrue(readme.contains("Android"))
        XCTAssertTrue(readme.contains("Scripts/build-ios-xcode.sh"))
        XCTAssertTrue(readme.contains("Scripts/build-ios-swiftpm.sh"))
        XCTAssertTrue(readme.contains("Scripts/run-ios-simulator-smoke.sh"))
        XCTAssertTrue(readme.contains("Scripts/build-android-local.sh"))
        XCTAssertTrue(readme.contains("--offline"))
        XCTAssertTrue(readme.contains("SwiftPM host/shared code"))
        XCTAssertTrue(readme.contains("iOS 26 SDK"))
        XCTAssertTrue(readme.contains("android/gradlew"))
        XCTAssertTrue(readme.contains("Gradle"))
        XCTAssertTrue(readme.contains("MoongateMobileCore"))
        XCTAssertTrue(readme.contains("MoongateiOS"))
        XCTAssertTrue(readme.contains("android/"))
        XCTAssertFalse(
            readme.contains("iOS/Android 已可发布"),
            "README must not imply mobile release readiness before runtime gates pass."
        )
    }

    func testIOSCredentialAdapterUsesKeychainWithoutDesktopOrPlainPreferenceFallback() throws {
        let root = packageRoot()
        let keychainFile = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("IOSKeychainCredentialStore.swift")
        let source = try String(contentsOf: keychainFile)

        XCTAssertTrue(
            source.contains("import Security"),
            "iOS credentials must use the platform Security framework."
        )
        XCTAssertTrue(
            source.contains("SecItemAdd") && source.contains("SecItemDelete") && source.contains("SecItemCopyMatching"),
            "The Keychain adapter should save, delete, and check credentials through SecItem APIs."
        )
        XCTAssertFalse(
            source.contains("import MoongateCore"),
            "The iOS credential adapter must not depend on the desktop core target."
        )
        XCTAssertFalse(
            source.contains("UserDefaults") || source.contains("FileManager.default"),
            "API keys must not fall back to ordinary preferences or files."
        )
    }

    func testIOSShellDoesNotExposeMockImportOrShareActionsInProductionView() throws {
        let root = packageRoot()
        let source = try String(contentsOf: root
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))

        XCTAssertFalse(source.contains("analyzeMockURL("))
        XCTAssertFalse(source.contains("模拟分享链接"))
        XCTAssertFalse(source.contains("importMockFile("))
        XCTAssertFalse(source.contains("applySharedMockURL("))
        XCTAssertTrue(
            source.contains("await model.analyzeURL("),
            "The production Add action should use the injected mobile parser path."
        )
    }

    func testIOSProductionShellUsesProductLabelsInsteadOfRawEnumsOrTaskIDs() throws {
        let root = packageRoot()
        let source = try String(contentsOf: root
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))

        XCTAssertFalse(
            source.contains("candidate.detail ?? candidate.kind.rawValue"),
            "Candidate fallback text should use a product label, not the raw enum value."
        )
        XCTAssertFalse(
            source.contains("artifact.kind.rawValue"),
            "Library artifact rows should use product labels, not raw enum values."
        )
        XCTAssertFalse(
            source.contains("Label(task.id"),
            "Settings/background task rows should not display raw task identifiers."
        )
        XCTAssertFalse(
            source.contains("?? task.id"),
            "Visible task title fallbacks should not expose raw task identifiers."
        )
        XCTAssertTrue(source.contains("iosCandidateKindLabel"))
        XCTAssertTrue(source.contains("iosArtifactKindLabel"))
        XCTAssertTrue(source.contains("iosTaskDisplayName"))
    }

    func testIOSAddViewExposesSidecarSubtitleImporter() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))

        XCTAssertTrue(source.contains("isSubtitleImporterPresented"))
        XCTAssertTrue(source.contains(".fileImporter("))
        XCTAssertTrue(source.contains("UTType(filenameExtension: \"srt\")"))
        XCTAssertTrue(source.contains("model.attachImportedSubtitle(fileURL: url, languageCode: \"en\")"))
        XCTAssertTrue(source.contains("isSubtitleImporterPresented = true"))
    }

    func testIOSAddViewExposesLocalVideoImporterAsPrimaryPath() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))

        XCTAssertTrue(source.contains("isVideoImporterPresented"))
        XCTAssertTrue(source.contains("Section(\"导入视频\")"))
        XCTAssertTrue(source.contains("usesAccessibilityDynamicType ? \"选择视频\" : \"选择视频文件\""))
        XCTAssertTrue(source.contains(".lineLimit(2)"))
        XCTAssertTrue(source.contains(".minimumScaleFactor(0.82)"))
        XCTAssertTrue(source.contains(".buttonStyle(.borderedProminent)"))
        XCTAssertTrue(source.contains("isVideoImporterPresented = true"))
        XCTAssertTrue(source.contains("allowedContentTypes: [.movie, .mpeg4Movie, .video]"))
        XCTAssertTrue(source.contains("await model.importVideoFile(fileURL: url)"))
        XCTAssertTrue(source.contains("本地视频会复制到 App 资料库"))
    }

    func testIOSAddFirstScreenPrioritizesImportOverDirectLink() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))
        let bodySource = try XCTUnwrap(source.fragment(
            from: "private var addEntryForms: some View",
            to: "private var addSessionContent: some View"
        ))
        let importRange = try XCTUnwrap(bodySource.range(of: "Section(\"导入视频\")"))
        let directLinkRange = try XCTUnwrap(bodySource.range(of: "Section(\"直链\")"))
        let idleSource = try XCTUnwrap(source.fragment(
            from: "case .idle:",
            to: "case .analyzing:"
        ))

        XCTAssertLessThan(importRange.lowerBound, directLinkRange.lowerBound)
        XCTAssertTrue(bodySource.contains("usesAccessibilityDynamicType ? \"选择视频\" : \"选择视频文件\""))
        XCTAssertTrue(bodySource.contains("TextField(\"粘贴 .mp4 或 .mov 直链\""))
        XCTAssertTrue(bodySource.contains("仅支持直接 HTTPS 视频文件链接，不解析网页。"))
        XCTAssertTrue(idleSource.contains("title: \"准备添加视频\""))
        XCTAssertTrue(idleSource.contains("优先选择本地视频"))
        XCTAssertFalse(idleSource.contains("等待直链"))
    }

    func testIOSAddViewUsesHonestDirectMediaCopyAndActionableCandidateSelection() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))
        let candidateSource = try XCTUnwrap(source.fragment(
            from: "case .candidateSelection:",
            to: "case .ready:"
        ))
        let candidateButtonSource = try XCTUnwrap(source.fragment(
            from: "private func candidateActionButton",
            to: "private func addFormatBinding"
        ))
        let unsupportedSource = try XCTUnwrap(source.fragment(
            from: "case .unsupported:",
            to: "case .failed:"
        ))

        XCTAssertTrue(source.contains("TextField(\"粘贴 .mp4 或 .mov 直链\""))
        XCTAssertTrue(source.contains("Label(\"检查直链\""))
        XCTAssertTrue(source.contains("仅支持直接 HTTPS 视频文件链接，不解析网页。"))
        XCTAssertTrue(candidateSource.contains("candidateActionButton(candidate)"))
        XCTAssertTrue(candidateButtonSource.contains("if candidate.isSupportedOnMobile"))
        XCTAssertTrue(candidateButtonSource.contains("Button"))
        XCTAssertTrue(candidateButtonSource.contains("model.selectAddCandidate(id: candidate.id)"))
        XCTAssertTrue(candidateButtonSource.contains("candidateActionContent(candidate)"))
        XCTAssertTrue(candidateButtonSource.contains("checkmark.circle.fill"))
        XCTAssertTrue(candidateButtonSource.contains("unsupportedCandidateStatusText(candidate)"))
        XCTAssertTrue(candidateButtonSource.contains("Capsule()"))
        XCTAssertTrue(candidateButtonSource.contains("Color.secondary.opacity(0.12)"))
        XCTAssertTrue(candidateButtonSource.contains(".accessibilityLabel(candidate.title)"))
        XCTAssertTrue(candidateButtonSource.contains(".accessibilityValue(candidateAccessibilityValue(candidate))"))
        XCTAssertTrue(candidateButtonSource.contains(".accessibilityHint(candidateAccessibilityHint(candidate))"))
        XCTAssertTrue(candidateButtonSource.contains("requiresDesktopExtractor"))
        XCTAssertTrue(candidateButtonSource.contains("请导入本地视频，或回到桌面端解析。"))
        XCTAssertFalse(candidateButtonSource.contains(".disabled(!candidate.isSupportedOnMobile)"))
        XCTAssertFalse(candidateSource.contains("candidateRow(candidate)"))
        XCTAssertFalse(source.contains("粘贴视频链接"))
        XCTAssertFalse(source.contains("解析视频"))
        XCTAssertFalse(source.contains("等待直链"))
        XCTAssertTrue(unsupportedSource.contains("也可以导入本地视频文件。"))
    }

    func testIOSAddFailureStatesExposePrimaryRecoveryActions() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))
        let unsupportedSource = try XCTUnwrap(source.fragment(
            from: "case .unsupported:",
            to: "case .failed:"
        ))
        let failedSource = try XCTUnwrap(source.fragment(
            from: "case .failed:",
            to: "private func candidateActionButton"
        ))

        XCTAssertTrue(
            unsupportedSource.contains("Label(\"导入视频\", systemImage: \"square.and.arrow.down\")"),
            "Unsupported direct links should still offer the local-video path as a visible primary recovery action."
        )
        XCTAssertTrue(
            unsupportedSource.contains("isVideoImporterPresented = true"),
            "The unsupported-state recovery action should open the existing video importer."
        )
        XCTAssertTrue(
            failedSource.contains("Label(\"重新检查\", systemImage: \"arrow.clockwise\")"),
            "A failed direct-link check should offer a visible retry action."
        )
        XCTAssertTrue(
            failedSource.contains("if let retryValue = model.addSession.input?.value") &&
                failedSource.contains("await model.analyzeURL(retryValue)"),
            "Retry should re-run analysis for the preserved input instead of asking the user to retype."
        )
    }

    func testIOSShellCapturesAPIKeyDraftBeforeAsyncSave() throws {
        let root = packageRoot()
        let source = try String(contentsOf: root
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))

        XCTAssertTrue(
            source.contains("let secret = apiKeyDraft"),
            "The API-key draft must be captured before launching async save work."
        )
        XCTAssertTrue(
            source.contains("await model.saveAPIKeyDraft(secret)"),
            "Async save should use the captured value, not read @State after the field is cleared."
        )
        XCTAssertFalse(
            source.contains("await model.saveAPIKeyDraft(apiKeyDraft)"),
            "Reading @State in the async task can save an empty value after the UI clears the field."
        )
    }

    func testIOSSettingsExposesCredentialReplaceAndDeleteInUserLanguage() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))
        let settingsSource = try XCTUnwrap(source.fragment(
            from: "private struct IOSSettingsView",
            to: "private extension View"
        ))

        XCTAssertTrue(settingsSource.contains("model.hasConfiguredTranslationCredential ? \"替换 API key\" : \"保存 API key\""))
        XCTAssertTrue(settingsSource.contains("Button(\"删除 API key\", role: .destructive)"))
        XCTAssertTrue(settingsSource.contains("confirmationDialog(\"删除 API key？\""))
        XCTAssertTrue(settingsSource.contains("await model.deleteAPIKey()"))
        XCTAssertTrue(settingsSource.contains("密钥已安全保存。"))
        XCTAssertTrue(settingsSource.contains("还没有保存密钥。"))
        XCTAssertFalse(settingsSource.contains("Keychain"))
        XCTAssertFalse(settingsSource.contains("安全存储引用"))
        XCTAssertFalse(settingsSource.contains("普通设置"))
        XCTAssertFalse(settingsSource.contains("队列记录"))
    }

    func testIOSRuntimeReadinessAdapterIsIsolatedFromDesktopCoreAndFutureClaims() throws {
        let root = packageRoot()
        let adapterFile = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("IOSRuntimeReadinessEvaluator.swift")
        let source = try String(contentsOf: adapterFile)

        XCTAssertTrue(
            source.contains("#if canImport(FoundationModels)") && source.contains("import FoundationModels"),
            "The iOS runtime adapter should isolate FoundationModels behind a guarded import."
        )
        XCTAssertTrue(
            source.contains("#if canImport(Translation)") && source.contains("import Translation"),
            "The iOS runtime adapter should isolate Translation.framework behind a guarded import."
        )
        XCTAssertTrue(
            source.contains("LanguageAvailability()"),
            "Apple Translation readiness should use runtime language availability checks."
        )
        XCTAssertTrue(
            source.contains("SystemLanguageModel.default"),
            "Foundation Models readiness should use the system model availability surface."
        )
        XCTAssertTrue(
            source.contains(".pccUnavailable"),
            "PCC/Cloud Pro must remain explicitly unavailable until a verified public runtime exists."
        )
        XCTAssertFalse(
            source.contains("import MoongateCore"),
            "The iOS runtime adapter must not pull in the desktop core target."
        )
        XCTAssertFalse(
            source.contains("iOS 27"),
            "The adapter must not claim future iOS runtime support without SDK evidence."
        )
    }

    func testIOSAppleTranslationReadinessCannotClaimReadyBelowExecutionRuntime() throws {
        let root = packageRoot()
        let adapterFile = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("IOSRuntimeReadinessEvaluator.swift")
        let providerFile = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("IOSAppleTranslationMobileProvider.swift")
        let adapterSource = try String(contentsOf: adapterFile)
        let providerSource = try String(contentsOf: providerFile)
        let appleReadinessBody = try XCTUnwrap(adapterSource.fragment(
            from: "private func appleTranslationReadiness",
            to: "private func foundationModelsReadiness"
        ))
        let executorBody = try XCTUnwrap(providerSource.fragment(
            from: "public func translate(_ request: IOSAppleTranslationBatchRequest)",
            to: "private func requiredSourceLanguage"
        ))

        XCTAssertTrue(
            appleReadinessBody.contains("guard #available(macOS 26.0, iOS 26.0, *)"),
            "Readiness must not claim Apple Translation is runnable on an OS version where the executor refuses to run."
        )
        XCTAssertTrue(
            executorBody.contains("guard #available(iOS 26.0, macOS 26.0, *)"),
            "The runtime-readiness test should stay aligned with the executor's OS gate."
        )
        XCTAssertFalse(
            appleReadinessBody.contains("guard #available(macOS 15.0, iOS 18.0, *)"),
            "LanguageAvailability existing on older SDKs is weaker than executable subtitle translation readiness."
        )
        XCTAssertTrue(
            appleReadinessBody.contains("guard let source = request.context.sourceLanguage.flatMap(language(from:))"),
            "Readiness should require the same explicit source language that the executor requires."
        )
        XCTAssertFalse(
            appleReadinessBody.contains("status(for: \"Hello\""),
            "Implicit language guessing can make Settings look ready while export later fails for missing source language."
        )
        XCTAssertTrue(
            appleReadinessBody.contains("guard #available(macOS 26.4, iOS 26.4, *)"),
            "High-fidelity readiness must match the high-fidelity executor runtime gate."
        )
    }

    func testIOSAppModelDefaultsToIOSRuntimeReadinessEvaluator() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("IOSMobileAppModel.swift"))

        XCTAssertTrue(
            source.contains("runtimeReadinessEvaluator: any TranslationRuntimeReadinessEvaluating = IOSRuntimeReadinessEvaluator()"),
            "The live iOS model should use the iOS runtime adapter by default while keeping tests injectable."
        )
        XCTAssertFalse(
            source.contains("runtimeReadinessEvaluator: any TranslationRuntimeReadinessEvaluating = StaticTranslationRuntimeReadinessEvaluator()"),
            "The iOS shell should not default to a static fallback once a platform adapter exists."
        )
    }

    func testIOSShellRefreshesAppleIntelligenceSelectionAsynchronously() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))

        XCTAssertTrue(
            source.contains("await model.refreshAppleIntelligenceStatus(for: route)"),
            "Changing the Apple Intelligence picker should trigger the runtime readiness adapter."
        )
        XCTAssertFalse(
            source.contains("model.selectAppleIntelligenceRoute(route)"),
            "The production iOS view should not stop at the old synchronous static status path."
        )
    }

    func testIOSSettingsExposesEditableCloudTranslationConfigurationAndConnectionTest() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))

        XCTAssertTrue(
            source.contains("settingsProtocolRow") &&
                source.contains("Picker(\"协议\", selection: cloudEngineBinding"),
            "Settings should expose the two cloud protocol choices as an editable picker."
        )
        XCTAssertTrue(
            source.contains("title: \"服务地址\"") &&
                source.contains("text: endpointBinding") &&
                source.contains("TextField(title, text: text)")
        )
        XCTAssertTrue(
            source.contains("title: \"模型\"") &&
                source.contains("text: modelBinding") &&
                source.contains("TextField(title, text: text)")
        )
        XCTAssertTrue(source.contains("await model.testCloudTranslationConnection()"))
        XCTAssertTrue(source.contains("model.cloudTranslationConnectionStatus.message"))
        XCTAssertFalse(
            source.contains("LabeledContent(\"协议\", value: engineTitle"),
            "The protocol row must not be read-only once M3 configuration is wired."
        )
    }

    func testIOSSettingsDisablesAPICredentialActionsForNonCloudEngines() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))
        let settingsSource = try XCTUnwrap(source.fragment(
            from: "private struct IOSSettingsView",
            to: "private extension View"
        ))
        let cloudSection = try XCTUnwrap(settingsSource.fragment(
            from: "Section(\"翻译 API\")",
            to: "Section(\"Apple Intelligence\")"
        ))
        let saveButtonSource = try sourceSlice(
            in: cloudSection,
            from: "Button(model.hasConfiguredTranslationCredential ? \"替换 API key\" : \"保存 API key\")",
            to: "if model.hasConfiguredTranslationCredential"
        )
        let connectionTestSource = try sourceSlice(
            in: cloudSection,
            from: "await model.testCloudTranslationConnection()",
            to: ".accessibilityLabel(\"测试翻译 API 连接\")"
        )
        let protocolRow = try XCTUnwrap(settingsSource.fragment(
            from: "private var settingsProtocolRow: some View",
            to: "private func settingsFieldRow"
        ))

        XCTAssertTrue(
            saveButtonSource.contains("requiresCloudConfiguration"),
            "The API-key save/replace button must be disabled when the selected engine is Apple Translation, on-device, PCC, or Cloud Pro."
        )
        XCTAssertTrue(
            connectionTestSource.contains("requiresCloudConfiguration"),
            "The connection-test button must be disabled before non-API-compatible engines can trigger credential/provider work."
        )
        XCTAssertEqual(
            protocolRow.matches(of: #"Text\("[^"]+"\)\.tag\(TranslationEngine\."#).count,
            2,
            "The API protocol picker should remain limited to OpenAI-compatible and Anthropic-compatible choices."
        )
        XCTAssertTrue(protocolRow.contains("Text(\"OpenAI\").tag(TranslationEngine.openAICompatible)"))
        XCTAssertTrue(protocolRow.contains("Text(\"Anthropic\").tag(TranslationEngine.anthropicCompatible)"))
        XCTAssertFalse(protocolRow.contains("appleTranslation"))
        XCTAssertFalse(protocolRow.contains("appleFoundation"))
    }

    func testCLIPingLLMGuardsNonCloudEnginesBeforeTokenMaskingOrConnectionTest() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("moongate-cli")
            .appendingPathComponent("main.swift"))
        let pingBranch = try XCTUnwrap(source.fragment(
            from: "case \"ping-llm\":",
            to: "default:"
        ))
        let guardRange = try XCTUnwrap(
            pingBranch.range(of: "settings.translationEngine.requiresCloudConfiguration"),
            "ping-llm should reject Apple Translation/on-device/PCC/Cloud Pro before using the cloud testing path."
        )
        let maskRange = try XCTUnwrap(pingBranch.range(of: "maskToken(settings.translationAuthToken)"))
        let connectionRange = try XCTUnwrap(pingBranch.range(of: "testTranslationConnection(settings: settings)"))

        XCTAssertLessThan(guardRange.lowerBound, maskRange.lowerBound)
        XCTAssertLessThan(guardRange.lowerBound, connectionRange.lowerBound)
        XCTAssertTrue(source.contains("ping-llm 只支持 Anthropic-compatible / OpenAI-compatible"))
        XCTAssertTrue(source.contains("TranslationEngine.supportedCLIValues"))
    }

    func testIOSSettingsUsesDynamicTypeSafeCloudConfigurationRowsWithVoiceOverState() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))
        let settingsSource = try XCTUnwrap(source.fragment(
            from: "private struct IOSSettingsView",
            to: "private struct IOSListBottomScrollSpacer"
        ))
        let cloudSection = try XCTUnwrap(settingsSource.fragment(
            from: "Section(\"翻译 API\")",
            to: "Section(\"Apple Intelligence\")"
        ))

        XCTAssertTrue(
            cloudSection.contains("settingsProtocolRow") &&
                cloudSection.matches(of: #"settingsFieldRow\("#).count >= 2 &&
                cloudSection.contains("settingsSecureFieldRow(") &&
                cloudSection.contains("title: \"服务地址\"") &&
                cloudSection.contains("title: \"模型\"") &&
                cloudSection.contains("title: \"API key\""),
            "Long Settings values should use label-above-field rows so accessibility Dynamic Type does not force protocol/endpoint/model/API-key copy into one line."
        )
        XCTAssertTrue(
            settingsSource.contains("private var settingsProtocolRow: some View") &&
            settingsSource.contains("private func settingsFieldRow") &&
                settingsSource.contains("private func settingsSecureFieldRow"),
            "The label-above-field treatment should be centralized for future Settings fields."
        )
        XCTAssertTrue(
            settingsSource.contains("private var settingsProtocolRow: some View") &&
                settingsSource.contains("Text(\"OpenAI\").tag(TranslationEngine.openAICompatible)") &&
                settingsSource.contains("Text(\"Anthropic\").tag(TranslationEngine.anthropicCompatible)") &&
                settingsSource.contains("Text(\"协议\")") &&
                settingsSource.contains(".accessibilityHidden(true)") &&
                settingsSource.contains(".accessibilityLabel(\"翻译协议\")") &&
                settingsSource.contains(".accessibilityValue(cloudEngineBinding.wrappedValue.displayName)") &&
                settingsSource.contains(".accessibilityHint(\"选择云端翻译 API 的兼容协议\")"),
            "The protocol picker should expose its state without relying on adjacent visual text."
        )
        let protocolRow = try XCTUnwrap(settingsSource.fragment(
            from: "private var settingsProtocolRow: some View",
            to: "private func settingsFieldRow"
        ))
        XCTAssertFalse(
            protocolRow.contains(".accessibilityElement(children: .ignore)"),
            "The protocol row must not hide the actual Picker from VoiceOver; the Picker itself needs the adjustable accessibility semantics."
        )
        XCTAssertTrue(
            cloudSection.contains("accessibilityValue: endpointAccessibilityValue") &&
                cloudSection.contains("accessibilityValue: modelAccessibilityValue") &&
                cloudSection.contains("accessibilityValue: apiKeyAccessibilityValue"),
            "Endpoint, model, and API-key rows should expose configured/missing status to VoiceOver."
        )
        let textFieldRow = try XCTUnwrap(settingsSource.fragment(
            from: "private func settingsFieldRow",
            to: "private func settingsSecureFieldRow"
        ))
        let secureFieldRow = try XCTUnwrap(settingsSource.fragment(
            from: "private func settingsSecureFieldRow",
            to: "private func settingsStatusRow"
        ))
        XCTAssertTrue(
            textFieldRow.contains("TextField(title, text: text)") &&
                textFieldRow.contains(".mobileSensitiveInput()") &&
                textFieldRow.contains(".accessibilityLabel(title)") &&
                textFieldRow.contains(".accessibilityValue(accessibilityValue)") &&
                textFieldRow.contains(".accessibilityHint(accessibilityHint)") &&
                textFieldRow.contains(".accessibilityHidden(true)"),
            "Editable text fields should carry their own VoiceOver label, configured/missing value, and hint instead of relying on a wrapper element."
        )
        XCTAssertFalse(
            textFieldRow.contains(".accessibilityElement(children: .contain)"),
            "TextField rows must not put the editable control behind a container-level accessibility element."
        )
        XCTAssertTrue(
            secureFieldRow.contains("SecureField(title, text: text)") &&
                secureFieldRow.contains(".mobileSensitiveInput()") &&
                secureFieldRow.contains(".accessibilityLabel(title)") &&
                secureFieldRow.contains(".accessibilityValue(accessibilityValue)") &&
                secureFieldRow.contains(".accessibilityHint(accessibilityHint)") &&
                secureFieldRow.contains(".accessibilityHidden(true)"),
            "Secure fields should carry their own VoiceOver label, saved/missing status, and hint while keeping the visual label hidden from duplicate speech."
        )
        XCTAssertFalse(
            secureFieldRow.contains(".accessibilityElement(children: .contain)"),
            "SecureField rows must not put the editable control behind a container-level accessibility element."
        )
        XCTAssertTrue(
            cloudSection.contains("settingsStatusRow(") &&
                cloudSection.contains("accessibilityLabel: \"API key 状态\"") &&
                cloudSection.contains("accessibilityValue: apiKeyAccessibilityValue"),
            "The API-key saved/missing status should remain visible and spoken at accessibility Dynamic Type sizes."
        )
        XCTAssertFalse(
            cloudSection.contains("if !usesAccessibilityDynamicType"),
            "Critical Settings status and connection-test copy must not disappear at accessibility Dynamic Type sizes."
        )
    }

    func testIOSSettingsAppleIntelligenceStatusKeepsFallbackGuidanceVisibleAndAccessible() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))
        let settingsSource = try XCTUnwrap(source.fragment(
            from: "private struct IOSSettingsView",
            to: "private struct IOSListBottomScrollSpacer"
        ))
        let appleSection = try XCTUnwrap(settingsSource.fragment(
            from: "Section(\"Apple Intelligence\")",
            to: "Section(\"后台处理\")"
        ))

        XCTAssertTrue(
            appleSection.contains(".accessibilityLabel(\"Apple Intelligence 路线\")") &&
                appleSection.contains(".accessibilityValue(model.selectedAppleIntelligenceRoute.shortTitle)") &&
                appleSection.contains(".accessibilityHint(\"选择 Apple Intelligence 翻译方式；这里只显示当前设备是否可用。\")"),
            "The Apple Intelligence route picker should expose route and conservative scope to VoiceOver."
        )
        XCTAssertTrue(
            appleSection.contains("appleIntelligenceStatusRow(status)") &&
                settingsSource.contains("private func appleIntelligenceStatusRow") &&
                settingsSource.contains("private func appleIntelligenceStatusHeader"),
            "Apple Intelligence status rows should use a focused component rather than a dense HStack."
        )
        XCTAssertTrue(
            settingsSource.contains("if usesAccessibilityDynamicType") &&
                settingsSource.contains("VStack(alignment: .leading, spacing: 2)") &&
                settingsSource.contains("Spacer(minLength: 8)"),
            "Apple Intelligence status should switch from compact horizontal metadata to stacked header text at accessibility Dynamic Type sizes."
        )
        XCTAssertTrue(
            settingsSource.contains(".accessibilityLabel(\"Apple Intelligence 状态\")") &&
                settingsSource.contains(".accessibilityValue(appleIntelligenceAccessibilityValue(for: status))") &&
                settingsSource.contains(".accessibilityHint(\"如果这条路线暂不可用，可以先改用 API 兼容引擎或其它已就绪路线。\")"),
            "Apple Intelligence status should speak availability, reason, and alternate path."
        )
        XCTAssertTrue(
            settingsSource.contains("Text(status.detail)") &&
                settingsSource.contains("Text(appleIntelligenceFallbackText(for: status))") &&
                settingsSource.contains("private func appleIntelligenceFallbackText"),
            "Maximum Dynamic Type users must still see why Apple Intelligence is unavailable and what fallback path exists."
        )
        XCTAssertFalse(
            appleSection.contains("if !usesAccessibilityDynamicType"),
            "Apple Intelligence detail must not be hidden at accessibility Dynamic Type sizes."
        )
    }

    func testIOSProductionCopyAvoidsImplementationTerms() throws {
        let root = packageRoot()
        let appModel = try String(contentsOf: root
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("IOSMobileAppModel.swift"))
        let rootView = try String(contentsOf: root
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))
        let productionCopy = appModel + "\n" + rootView

        for term in ["运行时 adapter", "运行时检测", "运行时可用性", "未接入", "当前仓库", "SDK 证据"] {
            XCTAssertFalse(productionCopy.contains(term), "\(term) should not appear in production iOS copy.")
        }
    }

    func testIOSDownloadEngineUsesMobileContractsAndNoDesktopProcess() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("IOSMobileDownloadEngine.swift"))

        XCTAssertTrue(source.contains("struct IOSMobileDownloadEngine: MobileDownloadEngine"))
        XCTAssertTrue(source.contains("IOSURLSessionMobileDownloadTransport"))
        XCTAssertTrue(source.contains("BackgroundTransferRecord"))
        XCTAssertTrue(source.contains("execution: .foregroundRequired"))
        XCTAssertFalse(source.contains("import MoongateCore"))
        XCTAssertFalse(source.contains("Process("))
        XCTAssertFalse(source.contains("yt-dlp"))
        XCTAssertFalse(source.contains("ffmpeg"))
    }

    func testIOSBackgroundURLSessionDelegateUsesBackgroundNoCacheBoundary() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("IOSBackgroundURLSessionDownloadDelegate.swift"))
        let appHostSource = try String(contentsOf: packageRoot()
            .appendingPathComponent("ios")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateiOSApp.swift"))

        XCTAssertTrue(source.contains("URLSessionConfiguration.background(withIdentifier: identifier)"))
        XCTAssertTrue(source.contains("urlCache = nil"))
        XCTAssertTrue(source.contains("httpCookieStorage = nil"))
        XCTAssertTrue(source.contains("urlCredentialStorage = nil"))
        XCTAssertTrue(source.contains(".reloadIgnoringLocalCacheData"))
        XCTAssertTrue(source.contains("URLSessionDownloadDelegate"))
        XCTAssertTrue(source.contains("recordCompletedDownload("))
        XCTAssertTrue(source.contains("recordFailedDownload("))
        XCTAssertTrue(source.contains("urlSessionDidFinishEvents(forBackgroundURLSession"))
        XCTAssertTrue(source.contains("IOSBackgroundURLSessionPendingEventDrain"))
        XCTAssertTrue(source.contains("pendingEvents.markSessionFinished(identifier)"))
        XCTAssertTrue(source.contains("drainFinishedSessionsIfReady()"))
        XCTAssertTrue(source.contains("completionConsumer.consumeCompletionHandler(for: identifier)"))
        let finishEvents = try XCTUnwrap(source.fragment(
            from: "public func finishEvents(forSessionIdentifier identifier: String)",
            to: "public func enqueueFinishedDownload("
        ))
        XCTAssertFalse(
            finishEvents.contains("completionConsumer.consumeCompletionHandler"),
            "The app delegate background completion handler must wait for pending download file moves and registry writes before being consumed."
        )
        XCTAssertTrue(appHostSource.contains("IOSBackgroundURLSessionCompletionRegistry: IOSBackgroundURLSessionCompletionConsuming"))
        XCTAssertFalse(source.contains("URLSession.shared"))
        XCTAssertFalse(source.contains("import MoongateCore"))
        XCTAssertFalse(source.contains("Process("))
        XCTAssertFalse(source.contains("yt-dlp"))
        XCTAssertFalse(source.contains("ffmpeg"))
    }

    func testIOSRenderExporterUsesAVFoundationBoundaryWithoutDesktopProcess() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("IOSMobileRenderExporter.swift"))

        XCTAssertTrue(source.contains("struct IOSMobileRenderExporter: RenderExporter"))
        XCTAssertTrue(source.contains("protocol IOSVideoRendering"))
        XCTAssertTrue(source.contains("IOSAVFoundationVideoRenderer"))
        XCTAssertTrue(source.contains("AVAssetExportSession"))
        XCTAssertTrue(source.contains("AVVideoCompositionCoreAnimationTool"))
        XCTAssertTrue(source.contains("MobileSubtitleDocument.parseSRT"))
        XCTAssertTrue(source.contains("IOSArtifactStore"))
        XCTAssertFalse(source.contains("import MoongateCore"))
        XCTAssertFalse(source.contains("Process("))
        XCTAssertFalse(source.contains("yt-dlp"))
        XCTAssertFalse(source.contains("ffmpeg"))
    }

    func testIOSContinuedProcessingSchedulerIsGuardedBehindIOS26BackgroundTasksAPI() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("IOSContinuedProcessingRenderScheduler.swift"))

        XCTAssertTrue(source.contains("#if os(iOS) && canImport(BackgroundTasks)"))
        XCTAssertTrue(source.contains("import BackgroundTasks"))
        XCTAssertTrue(source.contains("BGContinuedProcessingTaskRequest("))
        XCTAssertTrue(source.contains("BGTaskScheduler.shared.submit"))
        XCTAssertTrue(source.contains("#available(iOS 26.0, *)"))
        XCTAssertTrue(source.contains("userVisibleNotificationRequired"))
        XCTAssertFalse(source.contains("import MoongateCore"))
        XCTAssertFalse(source.contains("allowsUnboundedBackgroundExecution = true"))
    }

    func testIOSContinuedProcessingTaskHandlerKeepsPureSourceSeamAndGuardedAdapter() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("IOSContinuedProcessingTaskHandler.swift"))

        XCTAssertTrue(source.contains("protocol IOSContinuedProcessingSystemTask"))
        XCTAssertTrue(source.contains("struct IOSContinuedProcessingTaskHandler"))
        XCTAssertTrue(source.contains("IOSContinuedProcessingTaskCoordinator"))
        XCTAssertTrue(source.contains("#if os(iOS) && canImport(BackgroundTasks)"))
        XCTAssertTrue(source.contains("import BackgroundTasks"))
        XCTAssertTrue(source.contains("BGContinuedProcessingTask"))
        XCTAssertTrue(source.contains("task.expirationHandler"))
        XCTAssertTrue(source.contains("setTaskCompleted(success: success)"))
        XCTAssertTrue(source.contains("task.progress"))
        XCTAssertTrue(
            source.contains("task.progress.totalUnitCount") &&
                source.contains("task.progress.completedUnitCount"),
            "BGContinuedProcessingTask conforms to NSProgressReporting; update its existing Progress instead of assigning a new one."
        )
        XCTAssertFalse(
            source.contains("task.progress ="),
            "The iOS 26 SDK exposes BGContinuedProcessingTask.progress as read-only."
        )
        XCTAssertFalse(source.contains("import UIKit"))
        XCTAssertFalse(source.contains("import MoongateCore"))
        XCTAssertFalse(source.contains("allowsUnboundedBackgroundExecution = true"))
    }

    func testIOSMobileTranslationTransportDefaultsToEphemeralNoCacheSession() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("URLSessionMobileTranslationTransport.swift"))

        XCTAssertTrue(source.contains("URLSessionConfiguration.ephemeral"))
        XCTAssertTrue(source.contains("urlCache = nil"))
        XCTAssertTrue(source.contains("httpCookieStorage = nil"))
        XCTAssertTrue(source.contains("urlCredentialStorage = nil"))
        XCTAssertTrue(source.contains(".reloadIgnoringLocalCacheData"))
        XCTAssertFalse(
            source.contains("session: URLSession = .shared"),
            "Translation requests carry API keys and subtitle text, so the default transport must not use URLSession.shared."
        )
    }

    func testIOSQueueViewStartsDownloadThroughAsyncModelAction() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))

        XCTAssertTrue(
            source.contains("await model.performQueueAction(action, taskID: task.id)"),
            "Queue actions should use the async model dispatch path so start-download can invoke the real engine."
        )
        XCTAssertNil(
            source.range(
                of: #"Button\s*\{\s*model\.performQueueAction\(action, taskID: task\.id\)"#,
                options: .regularExpression
            ),
            "The production Queue UI should not route every action through synchronous mock state mutation."
        )
    }

    func testIOSQueueRowsExposePrimaryActionOutsideOverflowMenu() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))

        XCTAssertTrue(
            source.contains("if let primaryAction = primaryQueueAction(for: task)"),
            "Queue rows should expose the next expected action as a visible button instead of hiding every action in a menu."
        )
        XCTAssertTrue(source.contains("await model.performQueueAction(primaryAction, taskID: task.id)"))
        XCTAssertTrue(source.contains("ForEach(secondaryQueueActions(for: task), id: \\.rawValue)"))
        XCTAssertFalse(
            source.contains("ForEach(task.availableActions, id: \\.rawValue)"),
            "The overflow menu should contain only secondary actions once a primary row action is visible."
        )
    }

    func testIOSQueueDoesNotPresentNonResumableForegroundWorkAsRestartablePrimaryAction() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))
        let primaryActionSource = try XCTUnwrap(source.fragment(
            from: "private func primaryQueueAction(for task: MobileTaskSnapshot) -> MobileTaskAction?",
            to: "private func secondaryQueueActions(for task: MobileTaskSnapshot) -> [MobileTaskAction]"
        ))
        let actionTitleSource = try XCTUnwrap(source.fragment(
            from: "private func queueActionTitle(_ action: MobileTaskAction, for task: MobileTaskSnapshot) -> String",
            to: "private func queueActionIcon(_ action: MobileTaskAction) -> String"
        ))
        let backgroundSource = try XCTUnwrap(source.fragment(
            from: "private func backgroundText(for task: MobileTaskSnapshot) -> String",
            to: "private func queueActionTitle(_ action: MobileTaskAction, for task: MobileTaskSnapshot) -> String"
        ))

        XCTAssertTrue(
            primaryActionSource.contains("if action == .openAppToContinue && isNonResumableForegroundTask(task)"),
            "Non-resumable foreground work should not expose openAppToContinue as the prominent row action."
        )
        XCTAssertFalse(
            actionTitleSource.contains("case .exporting: return \"重新导出\"") ||
                actionTitleSource.contains("case .downloading: return \"重新下载\"") ||
                actionTitleSource.contains("case .translating: return \"重新翻译\""),
            "The openAppToContinue action does not restart work, so its label must not promise restart."
        )
        XCTAssertTrue(
            backgroundSource.contains("这次处理已被系统中断，需要重新添加或重新开始。"),
            "Interrupted non-resumable work needs honest row copy instead of saying it can continue."
        )
        XCTAssertTrue(
            source.contains("private func isNonResumableForegroundTask(_ task: MobileTaskSnapshot) -> Bool"),
            "The non-resumable check should be centralized so action priority, copy, and labels stay aligned."
        )
    }

    func testIOSQueueActionStatusIsGlobalInsteadOfRepeatedPerTaskRow() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))
        let taskRowSource = try XCTUnwrap(source.fragment(
            from: "private func taskRow(_ task: MobileTaskSnapshot) -> some View",
            to: "private func queueStatusRow(_ status: String) -> some View"
        ))

        XCTAssertFalse(
            taskRowSource.contains("lastQueueActionStatus"),
            "Queue rows must not render global action status once per task."
        )
        XCTAssertEqual(
            source.matches(of: "lastQueueActionStatus").count,
            1,
            "The global Queue action status should have a single rendering site."
        )
        XCTAssertTrue(source.contains("if let status = model.lastQueueActionStatus"))
        XCTAssertTrue(source.contains("queueStatusRow(status)"))
    }

    func testIOSLiveModelWiresRenderExporterAndQueueRenderAction() throws {
        let root = packageRoot()
        let modelSource = try String(contentsOf: root
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("IOSMobileAppModel.swift"))
        let viewSource = try String(contentsOf: root
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))

        XCTAssertTrue(modelSource.contains("renderExporter: (any RenderExporter)?"))
        XCTAssertTrue(modelSource.contains("IOSMobileRenderExporter(storageDirectoryURL: storageURL)"))
        XCTAssertTrue(modelSource.contains("case .exportRenderedVideo:"))
        XCTAssertTrue(modelSource.contains("MobileRenderRequestPlanner().plan(for: queue[index])"))
        XCTAssertTrue(viewSource.contains("case .exportRenderedVideo: return \"导出视频\""))
        XCTAssertTrue(viewSource.contains("case .exportRenderedVideo: return \"film\""))
    }

    func testIOSAddReadyStateExposesNativeExportPickerModes() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))
        let readySource = try XCTUnwrap(source.fragment(
            from: "case .ready:",
            to: "case .unsupported:"
        ))

        XCTAssertTrue(readySource.contains("Section(\"导出\")"))
        XCTAssertTrue(readySource.contains("Picker(\"格式\", selection: addFormatBinding(for: info))"))
        XCTAssertTrue(readySource.contains("Toggle(isOn: addSubtitleBinding(for: subtitle.id))"))
        XCTAssertTrue(source.contains("model.selectAddFormat(id: value)"))
        XCTAssertTrue(source.contains("model.toggleAddSubtitle(id: subtitleID)"))
        XCTAssertTrue(readySource.contains("Picker(\"导出为\", selection: $model.selectedAddExportProfile.subtitleMode)"))
        XCTAssertTrue(readySource.contains("Text(\"字幕文件\")"))
        XCTAssertTrue(readySource.contains("Text(\"软字幕包\")"))
        XCTAssertTrue(readySource.contains("Text(\"带字幕视频\")"))
        XCTAssertTrue(readySource.contains(".translatedSubtitleFile"))
        XCTAssertTrue(readySource.contains(".softSubtitle"))
        XCTAssertTrue(readySource.contains(".burnedInSubtitle"))
        XCTAssertTrue(readySource.contains("导出时需要保持 App 打开。"))
        XCTAssertFalse(readySource.contains("桌面解析器"))
        XCTAssertFalse(readySource.contains("LabeledContent(\"格式\""))
    }

    func testIOSAddAnalyzingStateExposesVoiceOverProgressLabelAndValue() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))
        let analyzingSource = try XCTUnwrap(source.fragment(
            from: "case .analyzing:",
            to: "case .candidateSelection:"
        ))

        XCTAssertTrue(
            analyzingSource.contains("ProgressView()"),
            "The Add analyzing state should still show a native progress indicator."
        )
        XCTAssertTrue(
            analyzingSource.contains(".accessibilityElement(children: .ignore)"),
            "The spinner and copy should be exposed as one coherent VoiceOver element."
        )
        XCTAssertTrue(
            analyzingSource.contains(".accessibilityLabel(\"链接检查进度\")"),
            "The Add analyzing progress indicator should have a stable VoiceOver label."
        )
        XCTAssertTrue(
            analyzingSource.contains(".accessibilityValue(\"正在检查\")"),
            "The Add analyzing progress indicator should expose the active checking state."
        )
    }

    func testIOSAddIdleStateUsesCompactDynamicTypeSafeHint() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))
        let idleSource = try XCTUnwrap(source.fragment(
            from: "case .idle:",
            to: "case .analyzing:"
        ))

        XCTAssertTrue(
            idleSource.contains("IOSAddInlineHint("),
            "The Add idle hint should stay compact so accessibility-extra-extra-large screenshots do not push copy behind the tab bar."
        )
        XCTAssertTrue(
            idleSource.contains("if !usesAccessibilityDynamicType"),
            "The secondary Add idle hint should be hidden at accessibility Dynamic Type sizes so primary actions remain visible."
        )
        XCTAssertFalse(
            idleSource.contains("ContentUnavailableView"),
            "The Add idle state is part of the first-screen form, so it should not use the large empty-state treatment."
        )
        XCTAssertTrue(
            source.contains("@Environment(\\.dynamicTypeSize) private var dynamicTypeSize") &&
                source.contains("private var usesAccessibilityDynamicType: Bool") &&
                source.contains("dynamicTypeSize.isAccessibilitySize"),
            "The Add screen should adapt to accessibility Dynamic Type using the native environment value."
        )
        XCTAssertTrue(
            source.contains("private struct IOSAddInlineHint"),
            "The compact Add hint should be a focused component rather than one-off layout code."
        )
        XCTAssertTrue(
            source.contains(".fixedSize(horizontal: false, vertical: true)") &&
                source.contains(".accessibilityElement(children: .combine)"),
            "The compact hint should wrap text naturally and expose one coherent VoiceOver element."
        )
    }

    func testIOSAddListKeepsDynamicTypeContentAboveTabBar() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))
        let bodySource = try XCTUnwrap(source.fragment(
            from: "var body: some View",
            to: "@ViewBuilder"
        ))

        XCTAssertTrue(
            bodySource.contains(".safeAreaInset(edge: .bottom)"),
            "The Add List should reserve explicit bottom scrolling space so accessibility-extra-extra-large content is not hidden behind the tab bar."
        )
        XCTAssertTrue(
            bodySource.contains("IOSAddBottomScrollSpacer()"),
            "The bottom inset should be a named component so future visual QA can find the Dynamic Type tab-bar protection."
        )
        XCTAssertTrue(
            source.contains("private struct IOSAddBottomScrollSpacer"),
            "The tab-bar protection should live near the Add view as a focused component."
        )
    }

    func testIOSAddActiveSessionContentComesBeforeEntryFormsForLargeType() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))
        let bodySource = try XCTUnwrap(source.fragment(
            from: "var body: some View",
            to: ".safeAreaInset(edge: .bottom)"
        ))
        let entryFormsSource = try XCTUnwrap(source.fragment(
            from: "private var addEntryForms",
            to: "@ViewBuilder"
        ))
        let activeContentRange = try XCTUnwrap(bodySource.range(of: "if hasActiveAddSessionContent"))
        let entryFormsRange = try XCTUnwrap(bodySource.range(of: "addEntryForms"))

        XCTAssertLessThan(
            activeContentRange.lowerBound,
            entryFormsRange.lowerBound,
            "When Add has candidate/ready/error state, that state should appear before entry forms so accessibility Dynamic Type screenshots expose the active decision."
        )
        XCTAssertTrue(
            bodySource.contains("if hasActiveAddSessionContent") &&
                bodySource.contains("addSessionContent") &&
                bodySource.contains("addEntryForms"),
            "The Add list should explicitly branch active-session ordering instead of relying on the idle form order."
        )
        XCTAssertTrue(
            source.contains("private var hasActiveAddSessionContent: Bool") &&
                source.contains("model.addSession.state != .idle"),
            "The active-session ordering should use Add state, not screenshot-only flags."
        )
        XCTAssertTrue(
            entryFormsSource.contains("Section(\"导入视频\")") &&
                entryFormsSource.contains("Section(\"直链\")"),
            "The import and direct-link entry forms should stay available after the active session content."
        )
    }

    func testIOSAVFoundationRendererUsesPreconcurrencyImportBoundary() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("IOSMobileRenderExporter.swift"))

        XCTAssertTrue(
            source.contains("@preconcurrency import AVFoundation"),
            "AVFoundation render integration should isolate legacy non-Sendable SDK types so Swift 6 builds stay warning-free."
        )
        XCTAssertFalse(
            source.contains("\nimport AVFoundation"),
            "Use @preconcurrency import AVFoundation rather than a plain import in this async renderer boundary."
        )
    }

    func testIOSQueueResultActionsRouteThroughLibraryPresentation() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))

        XCTAssertTrue(source.contains("case .openResult: return \"在资料库打开\""))
        XCTAssertTrue(source.contains("case .shareResult: return \"在资料库分享\""))
        XCTAssertTrue(
            source.contains(".onAppear(perform: performPendingLibraryActionCommand)"),
            "Queue result actions can switch to Library with a pending command, so Library must consume it on appear."
        )
        XCTAssertTrue(
            source.contains(".onChange(of: model.pendingLibraryActionCommand?.id)"),
            "Library should present pending commands produced outside the Library row menu."
        )
    }

    func testIOSQueueRowsUseRecoveryPresenterForActionableErrors() throws {
        let root = packageRoot()
        let rootView = try String(contentsOf: root
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))
        let presenter = try String(contentsOf: root
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("IOSQueueRecoveryPresenter.swift"))

        XCTAssertTrue(
            rootView.contains("IOSQueueRecoveryPresenter"),
            "Queue rows should use a focused presenter for failure and recovery copy instead of generic state text."
        )
        XCTAssertTrue(
            rootView.contains("recovery.message") &&
                rootView.contains("recovery.recoveryHint") &&
                rootView.contains("accessibilityHint(recovery.accessibilityHint)"),
            "Queue failures should expose a clear reason, next step, and VoiceOver hint."
        )
        XCTAssertTrue(
            presenter.contains("networkUnavailable") &&
                presenter.contains("credentialRequired") &&
                presenter.contains("systemBackgroundLimit") &&
                presenter.contains("storageFull") &&
                presenter.contains("permissionDenied"),
            "The presenter should distinguish common user-fixable and system-limit failure causes."
        )
    }

    func testIOSQueueProgressViewsExposeVoiceOverLabelsAndValues() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))
        let taskRowSource = try XCTUnwrap(source.fragment(
            from: "private func taskRow(_ task: MobileTaskSnapshot) -> some View",
            to: "private func queueStatusRow(_ status: String) -> some View"
        ))

        XCTAssertTrue(
            taskRowSource.contains(".accessibilityLabel(\"任务进度\")"),
            "Queue progress indicators should have a stable VoiceOver label."
        )
        XCTAssertTrue(
            taskRowSource.contains(".accessibilityValue(progressAccessibilityValue(for: task))"),
            "Queue progress indicators should expose a spoken percentage or active phase."
        )
        XCTAssertTrue(
            source.contains("private func progressAccessibilityValue(for task: MobileTaskSnapshot) -> String"),
            "Progress accessibility copy should be centralized so determinate and indeterminate states stay consistent."
        )
    }

    func testIOSQueueAndLibraryActionsExposeVoiceOverContext() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))

        XCTAssertTrue(source.contains("queueActionAccessibilityLabel("))
        XCTAssertTrue(source.contains("queueActionAccessibilityHint("))
        XCTAssertTrue(source.contains("queueMoreActionsAccessibilityLabel(for: task)"))
        XCTAssertTrue(source.contains(".accessibilityLabel(queueActionAccessibilityLabel("))
        XCTAssertTrue(source.contains(".accessibilityHint(queueActionAccessibilityHint("))
        XCTAssertTrue(source.contains("libraryActionAccessibilityLabel("))
        XCTAssertTrue(source.contains("libraryActionAccessibilityHint("))
        XCTAssertTrue(source.contains("libraryMoreActionsAccessibilityLabel(for: item)"))
        XCTAssertTrue(source.contains(".accessibilityLabel(libraryActionAccessibilityLabel("))
        XCTAssertTrue(source.contains(".accessibilityHint(libraryActionAccessibilityHint("))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"添加字幕 \\(item.title)\""))
        XCTAssertTrue(source.contains("只删除资料库记录，不删除文件。"))
    }

    func testIOSQueueTaskTitlesCanWrapForDynamicTypeAndVoiceOver() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))
        let taskRowSource = try XCTUnwrap(source.fragment(
            from: "private func taskRow(_ task: MobileTaskSnapshot) -> some View",
            to: "private func progressAccessibilityValue(for task: MobileTaskSnapshot) -> String"
        ))

        XCTAssertTrue(
            taskRowSource.contains(".lineLimit(2)"),
            "Queue task titles should allow a second line so Dynamic Type and long filenames do not lose the identifying title."
        )
        XCTAssertFalse(
            taskRowSource.contains(".lineLimit(1)"),
            "Queue task titles should not be hard-truncated to one line."
        )
    }

    func testIOSLibraryUsesSystemPresentationInsteadOfStatusOnlyActions() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))

        XCTAssertTrue(
            source.contains("ShareLink("),
            "Library sharing should invoke the native share sheet instead of only showing status text."
        )
        XCTAssertTrue(
            source.contains(".fileExporter("),
            "Save to Files should present the native file exporter instead of only showing status text."
        )
        XCTAssertTrue(
            source.contains("QLPreviewController"),
            "Open should present a native iOS Quick Look preview for app-owned artifacts."
        )
        XCTAssertFalse(
            source.contains("func quickLookPreview(_ item: Binding<URL?>) -> some View"),
            "The iOS shell must not satisfy preview wiring with a no-op quickLookPreview shim."
        )
        XCTAssertTrue(
            source.contains(".confirmationDialog("),
            "Deleting a Library record should require a confirmation dialog."
        )
        XCTAssertTrue(
            source.contains("IOSArtifactStore"),
            "System presentations should resolve only app-owned artifact identifiers."
        )
    }

    func testIOSLibrarySaveToFilesDoesNotReadWholeArtifactIntoMemory() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))

        XCTAssertTrue(
            source.contains(".fileExporter("),
            "Save to Files should still present the native file exporter."
        )
        XCTAssertTrue(
            source.contains("item: exportFile,"),
            "Large video export should pass a Transferable file wrapper to the system exporter instead of wrapping bytes in Data."
        )
        XCTAssertTrue(
            source.contains("FileRepresentation"),
            "Save to Files should export the app-owned file URL through file transfer representation."
        )
        XCTAssertTrue(
            source.contains("SentTransferredFile"),
            "Save to Files should hand the system exporter a file URL, not in-memory bytes."
        )
        XCTAssertFalse(
            source.contains("Data(contentsOf: fileURL)"),
            "Save to Files must not load an entire exported video into memory before presenting the exporter."
        )
        XCTAssertFalse(
            source.contains("regularFileWithContents"),
            "Save to Files should not create a Data-backed FileWrapper for large media artifacts."
        )
    }

    func testIOSLibraryRowsExposeOpenAndShareOutsideOverflowMenu() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))
        let primaryHelper = try XCTUnwrap(source.fragment(
            from: "private func primaryLibraryActions(for item: MobileLibraryItem) -> [MobileLibraryAction]",
            to: "private func secondaryLibraryActions(for item: MobileLibraryItem) -> [MobileLibraryAction]"
        ))

        XCTAssertTrue(source.contains("let primaryActions = primaryLibraryActions(for: item)"))
        XCTAssertTrue(source.contains("ForEach(primaryActions, id: \\.rawValue)"))
        XCTAssertTrue(source.contains("primaryLibraryActionButton(action, isProminent: action == primaryActions.first, item: item)"))
        XCTAssertTrue(source.contains("ForEach(secondaryLibraryActions(for: item), id: \\.rawValue)"))
        XCTAssertFalse(
            source.contains("ForEach(item.availableActions, id: \\.rawValue)"),
            "Library overflow menus must not hide every available action behind a single menu."
        )
        XCTAssertTrue(
            primaryHelper.contains(".open") && primaryHelper.contains(".share"),
            "Open and Share should be promoted to visible Library row actions when available."
        )
        XCTAssertTrue(
            primaryHelper.contains("prefix(2)"),
            "Available records should expose both Open and Share before falling back to secondary actions."
        )
        XCTAssertTrue(
            source.contains("libraryStatusContent"),
            "Library global feedback should be rendered outside individual item rows."
        )
    }

    func testIOSQueueAndLibraryEmptyStatesExposePrimaryRecoveryActions() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift"))

        let queueEmptyState = try XCTUnwrap(source.fragment(
            from: "private var queueEmptyState: some View",
            to: "private func taskRow(_ task: MobileTaskSnapshot) -> some View"
        ))
        let libraryEmptyState = try XCTUnwrap(source.fragment(
            from: "private var libraryEmptyState: some View",
            to: "private func performPendingLibraryActionCommand()"
        ))

        XCTAssertTrue(
            queueEmptyState.contains("Label(\"添加视频\", systemImage: \"plus.circle\")"),
            "The empty Queue should expose a visible primary action, not only explanatory copy."
        )
        XCTAssertTrue(
            queueEmptyState.contains("model.selectedTab = .add"),
            "The Queue empty-state action should take the user directly to Add."
        )
        XCTAssertTrue(
            libraryEmptyState.contains("Label(\"查看队列\", systemImage: \"list.bullet\")"),
            "The empty Library should expose a visible primary action, not only explanatory copy."
        )
        XCTAssertTrue(
            libraryEmptyState.contains("model.selectedTab = .queue"),
            "The Library empty-state action should take the user directly to Queue."
        )
    }

    func testIOSLiveModelUsesAppOwnedStorageForDownloadAndTaskState() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("IOSMobileAppModel.swift"))

        XCTAssertTrue(source.contains("public static func live("))
        XCTAssertTrue(source.contains("storageDirectoryURL: URL? = nil"))
        XCTAssertTrue(source.contains("credentialStore: any SecureCredentialStore = IOSKeychainCredentialStore()"))
        XCTAssertNotNil(
            source.range(
                of: #"FileManager\.default\s*\.urls\(for:\s*\.applicationSupportDirectory,\s*in:\s*\.userDomainMask\)"#,
                options: .regularExpression
            )
        )
        XCTAssertTrue(source.contains("IOSMobileDownloadEngine("))
        XCTAssertTrue(source.contains("FileTaskRepository("))
        XCTAssertFalse(
            source.contains("FileManager.default.temporaryDirectory"),
            "The live model should not use tmp storage for task state or downloaded artifacts."
        )
    }

    func testIOSSwiftPMBuildScriptUsesExplicitAppleSDKsAndDocumentsBoundary() throws {
        let scriptURL = packageRoot()
            .appendingPathComponent("Scripts")
            .appendingPathComponent("build-ios-swiftpm.sh")
        let script = try String(contentsOf: scriptURL)

        XCTAssertTrue(script.contains("xcrun --sdk \"$sdk_name\" --show-sdk-path"))
        XCTAssertTrue(script.contains("--sdk \"$sdk_path\""))
        XCTAssertTrue(script.contains("arm64-apple-ios17.0-simulator"))
        XCTAssertTrue(script.contains("arm64-apple-ios17.0"))
        XCTAssertTrue(script.contains("MoongateiOSApp"))
        XCTAssertTrue(script.contains("shared code / SwiftPM host only"))
        XCTAssertTrue(script.contains("not the native Xcode app-bundle host"))
        XCTAssertTrue(script.contains("iOS 26 SDK-backed adapters require Xcode/iPhoneOS 26 SDK validation"))
        XCTAssertTrue(script.contains("does not sign"))
        XCTAssertTrue(script.contains("does not install"))
        XCTAssertTrue(script.contains("device"))
        XCTAssertFalse(
            script.contains("curl ") || script.contains("wget ") || script.contains("gradle wrapper"),
            "The iOS SwiftPM build helper must stay local and must not download dependencies or generate wrappers."
        )
    }

    func testIOSXcodeProjectDefinesNativeAppBundleBoundary() throws {
        let root = packageRoot()
        let projectFile = root
            .appendingPathComponent("ios")
            .appendingPathComponent("MoongateiOSApp.xcodeproj")
            .appendingPathComponent("project.pbxproj")
        guard FileManager.default.fileExists(atPath: projectFile.path) else {
            XCTFail("A minimal iOS Xcode project should exist so xcodebuild can produce an app bundle.")
            return
        }

        let project = try String(contentsOf: projectFile)
        XCTAssertTrue(project.contains("MoongateiOSApp"))
        XCTAssertTrue(project.contains("com.apple.product-type.application"))
        XCTAssertTrue(project.contains("MoongateiOS"))
        XCTAssertTrue(project.contains("MoongateiOS/Info.plist"))
        XCTAssertTrue(project.contains("com.local.videodownloader.ios"))
        XCTAssertFalse(project.contains("MoongateCore"))
        XCTAssertFalse(project.contains("Sources/Moongate/"))
        XCTAssertFalse(project.contains("CODE_SIGN_STYLE = Automatic"))
    }

    func testIOSXcodeProjectDefinesHostedKeychainIntegrationTestTarget() throws {
        let root = packageRoot()
        let projectFile = root
            .appendingPathComponent("ios")
            .appendingPathComponent("MoongateiOSApp.xcodeproj")
            .appendingPathComponent("project.pbxproj")
        let schemeFile = root
            .appendingPathComponent("ios")
            .appendingPathComponent("MoongateiOSApp.xcodeproj")
            .appendingPathComponent("xcshareddata")
            .appendingPathComponent("xcschemes")
            .appendingPathComponent("MoongateiOSApp.xcscheme")
        let integrationTestFile = root
            .appendingPathComponent("ios")
            .appendingPathComponent("MoongateiOSAppTests")
            .appendingPathComponent("IOSKeychainCredentialStoreIntegrationTests.swift")
        let project = try String(contentsOf: projectFile)
        let scheme = try String(contentsOf: schemeFile)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: integrationTestFile.path),
            "The native Xcode app should have an iOS-hosted Keychain roundtrip test file."
        )
        guard FileManager.default.fileExists(atPath: integrationTestFile.path) else {
            return
        }

        let integrationTest = try String(contentsOf: integrationTestFile)

        XCTAssertTrue(project.contains("MoongateiOSAppTests"))
        XCTAssertTrue(project.contains("com.apple.product-type.bundle.unit-test"))
        XCTAssertTrue(project.contains("TEST_HOST = \"$(BUILT_PRODUCTS_DIR)/MoongateiOSApp.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/MoongateiOSApp\""))
        XCTAssertTrue(project.contains("BUNDLE_LOADER = \"$(TEST_HOST)\""))
        XCTAssertTrue(project.contains("MoongateiOSAppTests.xctest"))
        XCTAssertTrue(project.contains("MoongateiOS in Frameworks"))
        XCTAssertTrue(project.contains("IOSKeychainCredentialStoreIntegrationTests.swift in Sources"))
        XCTAssertTrue(project.contains("PBXTargetDependency"))

        XCTAssertTrue(scheme.contains("<TestAction"))
        XCTAssertTrue(scheme.contains("<Testables>"))
        XCTAssertTrue(scheme.contains("MoongateiOSAppTests.xctest"))
        XCTAssertTrue(scheme.contains("BlueprintName = \"MoongateiOSAppTests\""))
        XCTAssertTrue(scheme.contains("buildForTesting = \"YES\""))

        XCTAssertTrue(integrationTest.contains("final class IOSKeychainCredentialStoreIntegrationTests: XCTestCase"))
        XCTAssertTrue(integrationTest.contains("IOSKeychainCredentialStore()"))
        XCTAssertTrue(integrationTest.contains("SecureCredentialReference("))
        XCTAssertTrue(integrationTest.contains("com.local.videodownloader.ios.tests."))
        XCTAssertTrue(integrationTest.contains("UUID().uuidString"))
        XCTAssertTrue(integrationTest.contains("try await store.saveCredential("))
        XCTAssertTrue(integrationTest.contains("try await store.hasCredential(reference)"))
        XCTAssertTrue(integrationTest.contains("try await store.credential(for: reference)"))
        XCTAssertTrue(integrationTest.contains("try await store.deleteCredential(reference)"))
        XCTAssertFalse(integrationTest.contains("sk-"))
        XCTAssertFalse(integrationTest.contains("Bearer "))
        XCTAssertFalse(integrationTest.contains("URLSession"))
        XCTAssertFalse(integrationTest.contains("http://"))
        XCTAssertFalse(integrationTest.contains("https://"))
    }

    func testIOSAppBundleMetadataDoesNotOverclaimBackgroundModes() throws {
        let infoPlist = packageRoot()
            .appendingPathComponent("ios")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("Info.plist")
        guard FileManager.default.fileExists(atPath: infoPlist.path) else {
            XCTFail("The iOS app target should declare bundle metadata in ios/MoongateiOS/Info.plist.")
            return
        }

        let plist = try String(contentsOf: infoPlist)
        XCTAssertTrue(plist.contains("CFBundleDisplayName"))
        XCTAssertTrue(plist.contains("视频下载器"))
        XCTAssertTrue(plist.contains("UIApplicationSceneManifest"))
        XCTAssertTrue(plist.contains("UIInterfaceOrientationPortraitUpsideDown"))
        XCTAssertFalse(
            plist.contains("UIBackgroundModes"),
            "Do not declare background modes until a real background URLSession/BGTask runner is wired and tested."
        )
        XCTAssertFalse(plist.contains("NSAppTransportSecurity"))
    }

    func testIOSAppBundleDeclaresPhotoLibraryWriteUsageForSaveToPhotos() throws {
        let infoPlist = packageRoot()
            .appendingPathComponent("ios")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("Info.plist")
        guard FileManager.default.fileExists(atPath: infoPlist.path) else {
            XCTFail("The iOS app target should declare bundle metadata in ios/MoongateiOS/Info.plist.")
            return
        }

        let plist = try String(contentsOf: infoPlist)
        XCTAssertTrue(
            plist.contains("NSPhotoLibraryAddUsageDescription"),
            "Saving rendered videos to Photos requires the add-only Photos usage description."
        )
        XCTAssertTrue(
            plist.contains("保存导出视频到照片"),
            "The Photos usage text should plainly describe the save-to-Photos action."
        )
    }

    func testIOSLibrarySaveToPhotosUsesSystemPhotoLibraryHandlerInsteadOfStatusOnly() throws {
        let rootView = packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateIOSRootView.swift")
        let source = try String(contentsOf: rootView)
        let handlerSource = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("IOSPhotoLibrarySaveHandler.swift"))

        XCTAssertTrue(
            source.contains("IOSPhotoLibrarySaveHandler"),
            "The iOS library view should route Save to Photos through the PhotoKit handler seam."
        )
        XCTAssertTrue(
            source.contains("photoLibraryExporter"),
            "The iOS library view should provide the production photo-library exporter."
        )
        XCTAssertTrue(
            source.contains("await handler.save(command)"),
            "Save to Photos should execute the handler and publish the returned status instead of only showing the permission prompt."
        )
        XCTAssertTrue(
            handlerSource.contains("PHPhotoLibrary.requestAuthorization(for: .addOnly)"),
            "The production photo exporter should request add-only Photos authorization."
        )
        XCTAssertTrue(
            handlerSource.contains("PHAssetCreationRequest.forAsset().addResource(with: .video"),
            "The production photo exporter should create a video resource in Photos."
        )
        XCTAssertNil(
            source.range(
                of: #"case \.saveToPhotos:\s*\n\s*model\.lastLibraryActionStatus = command\.systemMessage"#,
                options: .regularExpression
            ),
            "Save to Photos must not stop at a status string once the system exporter seam exists."
        )
    }

    func testIOSXcodeAppHostCapturesBackgroundURLSessionCompletionHandlerWithoutOverclaimingModes() throws {
        let root = packageRoot()
        let appHost = root
            .appendingPathComponent("ios")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateiOSApp.swift")
        let source = try String(contentsOf: appHost)
        let plist = try String(contentsOf: root
            .appendingPathComponent("ios")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("Info.plist"))

        XCTAssertTrue(
            source.contains("UIApplicationDelegateAdaptor"),
            "The native iOS app host should attach an app delegate for background URLSession relaunch callbacks."
        )
        XCTAssertTrue(
            source.contains("application(_:handleEventsForBackgroundURLSession:completionHandler:)"),
            "The app delegate should receive system background URLSession events instead of relying only on foreground restore."
        )
        XCTAssertTrue(
            source.contains("IOSBackgroundURLSessionCompletionRegistry.shared.store("),
            "The delegate should persist the system completion handler until the URLSession delegate drains events."
        )
        XCTAssertTrue(
            source.contains("consumeCompletionHandler(for identifier: String)") &&
                source.contains("handler()"),
            "The completion registry should expose a one-shot consume path so future URLSession delegate code can release the system snapshot."
        )
        XCTAssertFalse(
            plist.contains("UIBackgroundModes"),
            "A background callback hook alone is not enough to declare background modes before the real background runner is wired and tested."
        )
    }

    func testIOSXcodeAppHostRegistersContinuedProcessingLaunchHandler() throws {
        let root = packageRoot()
        let appHost = root
            .appendingPathComponent("ios")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateiOSApp.swift")
        let source = try String(contentsOf: appHost)
        let plist = try String(contentsOf: root
            .appendingPathComponent("ios")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("Info.plist"))

        XCTAssertTrue(
            source.contains("#if canImport(BackgroundTasks)") && source.contains("import BackgroundTasks"),
            "The native iOS app host should isolate BackgroundTasks behind a guarded import."
        )
        XCTAssertTrue(
            source.contains("BGTaskScheduler.shared.register("),
            "The app host should register a launch handler for submitted continued-processing render identifiers."
        )
        XCTAssertTrue(
            source.contains("static var continuedProcessingRenderTaskIdentifierPattern: String") &&
                source.contains(#""\(bundleIdentifier).render.*""#) &&
                source.contains("forTaskWithIdentifier: Self.continuedProcessingRenderTaskIdentifierPattern"),
            "The registered identifier pattern should match the continued-processing render request prefix plus dynamic task IDs."
        )
        XCTAssertTrue(
            source.contains("IOSContinuedProcessingTaskHandler(") &&
                source.contains("IOSContinuedProcessingTaskCoordinator(taskRepository: repository)"),
            "The launch handler should route system tasks through the existing source-tested continued-processing handler seam."
        )
        XCTAssertTrue(
            source.contains("IOSBackgroundContinuedProcessingSystemTask(task: task)"),
            "The guarded adapter should wrap the system BGContinuedProcessingTask before handing it to the pure handler."
        )
        XCTAssertTrue(
            source.contains("IOSContinuedProcessingRenderTaskRunner(") &&
                source.contains("IOSMobileRenderExporter(storageDirectoryURL: storageDirectoryURL)"),
            "The system launch handler should run the persisted render task through the existing renderer instead of only installing an expiration handler."
        )
        XCTAssertTrue(
            plist.contains("BGTaskSchedulerPermittedIdentifiers") &&
                plist.contains("$(PRODUCT_BUNDLE_IDENTIFIER).render.*"),
            "The app bundle should permit the continued-processing render identifier it registers and submits."
        )
        XCTAssertFalse(
            source.contains("BGTaskScheduler.shared.register(") && !source.contains("#available(iOS 26.0, *)"),
            "BGContinuedProcessingTask registration must stay behind the verified iOS 26 availability gate."
        )
    }

    func testIOSBackgroundIdentifiersAreDerivedFromBundleConfiguration() throws {
        let root = packageRoot()
        let modelSource = try String(contentsOf: root
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("IOSMobileAppModel.swift"))
        let appHostSource = try String(contentsOf: root
            .appendingPathComponent("ios")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateiOSApp.swift"))
        let project = try String(contentsOf: root
            .appendingPathComponent("ios")
            .appendingPathComponent("MoongateiOSApp.xcodeproj")
            .appendingPathComponent("project.pbxproj"))
        let smokeScript = try String(contentsOf: root
            .appendingPathComponent("Scripts")
            .appendingPathComponent("run-ios-simulator-smoke.sh"))

        XCTAssertTrue(
            modelSource.contains("bundleIdentifier: String = Bundle.main.bundleIdentifier ??"),
            "The live iOS model should derive background identifiers from the running bundle, with only an explicit local fallback."
        )
        XCTAssertTrue(
            modelSource.contains("IOSBackgroundURLSessionDescriptor(") &&
                modelSource.contains("bundleIdentifier: bundleIdentifier"),
            "Background URLSession identifiers should use the injected bundle identifier."
        )
        XCTAssertTrue(
            modelSource.contains("IOSContinuedProcessingRenderScheduler(bundleIdentifier: bundleIdentifier"),
            "Continued-processing render request identifiers should use the injected bundle identifier."
        )
        XCTAssertTrue(
            appHostSource.contains("Bundle.main.bundleIdentifier ??"),
            "The native iOS app delegate should derive the continued-processing pattern from the built app bundle identifier."
        )
        XCTAssertFalse(
            appHostSource.contains("static let bundleIdentifier = \"com.local.videodownloader.ios\""),
            "The app host must not hardcode the local bundle id into background task registration."
        )
        XCTAssertTrue(
            project.contains("MOONGATE_IOS_BUNDLE_IDENTIFIER = com.local.videodownloader.ios"),
            "The local Xcode project may define a build-setting fallback bundle id for unsigned local builds."
        )
        XCTAssertTrue(
            project.contains(#"PRODUCT_BUNDLE_IDENTIFIER = "$(MOONGATE_IOS_BUNDLE_IDENTIFIER)""#),
            "The Xcode target should route PRODUCT_BUNDLE_IDENTIFIER through a build setting so CI or release builds can override it."
        )
        XCTAssertTrue(
            smokeScript.contains("MOONGATE_IOS_BUNDLE_IDENTIFIER"),
            "The simulator smoke helper should launch the configured bundle id instead of hardcoding the local id."
        )
    }

    func testIOSXcodeBuildScriptUsesLocalProjectAndDocumentsRemainingGates() throws {
        let scriptURL = packageRoot()
            .appendingPathComponent("Scripts")
            .appendingPathComponent("build-ios-xcode.sh")
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            XCTFail("A local xcodebuild helper should exist for the iOS app-bundle gate.")
            return
        }

        let script = try String(contentsOf: scriptURL)
        XCTAssertTrue(script.contains("xcodebuild"))
        XCTAssertTrue(script.contains("-project \"$PROJECT\""))
        XCTAssertTrue(script.contains("-scheme \"$SCHEME\""))
        XCTAssertTrue(script.contains("CODE_SIGNING_ALLOWED=NO"))
        XCTAssertTrue(script.contains("MOONGATE_IOS_BUNDLE_IDENTIFIER"))
        XCTAssertTrue(script.contains("derivedDataPath"))
        XCTAssertTrue(script.contains("clonedSourcePackagesDirPath"))
        XCTAssertTrue(script.contains("Usage: $0 [simulator|device|all]"))
        XCTAssertTrue(script.contains("iphoneos"))
        XCTAssertTrue(script.contains("generic/platform=iOS"))
        XCTAssertTrue(script.contains("iOS 26 SDK-backed adapters require"))
        XCTAssertTrue(script.contains("Xcode/iPhoneOS 26 SDK"))
        XCTAssertTrue(script.contains("does not install"))
        XCTAssertTrue(script.contains("does not create an ipa"))
        XCTAssertFalse(
            script.contains("curl ") || script.contains("wget ") || script.contains("-allowProvisioningUpdates"),
            "The iOS app-bundle helper must stay local and must not contact Apple Developer services."
        )
    }

    func testIOSSimulatorSmokeScriptInstallsAndLaunchesLocalAppBundleOnly() throws {
        let scriptURL = packageRoot()
            .appendingPathComponent("Scripts")
            .appendingPathComponent("run-ios-simulator-smoke.sh")
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            XCTFail("A local simulator smoke helper should exist so the iOS gate can prove launch, not only app-bundle build.")
            return
        }

        let script = try String(contentsOf: scriptURL)
        XCTAssertTrue(script.contains("xcodebuild"))
        XCTAssertTrue(script.contains("-project \"$PROJECT\""))
        XCTAssertTrue(script.contains("-scheme \"$SCHEME\""))
        XCTAssertTrue(script.contains("CODE_SIGNING_ALLOWED=NO"))
        XCTAssertTrue(script.contains("xcrun simctl bootstatus"))
        XCTAssertTrue(script.contains("xcrun simctl install"))
        XCTAssertTrue(script.contains("xcrun simctl launch"))
        XCTAssertTrue(script.contains("xcrun simctl terminate"))
        XCTAssertTrue(
            script.contains("Warning: app was already terminated before cleanup."),
            "The cleanup terminate step should not fail a successful build/install/launch/screenshot run when the app has already exited."
        )
        XCTAssertTrue(script.contains("MOONGATE_IOS_BUNDLE_IDENTIFIER"))
        XCTAssertTrue(script.contains("BUNDLE_IDENTIFIER=\"$MOONGATE_IOS_BUNDLE_IDENTIFIER\""))
        XCTAssertTrue(script.contains("IOS_SIMULATOR_UDID"))
        XCTAssertTrue(script.contains("does not contact Apple Developer services"))
        XCTAssertTrue(script.contains("does not run UI automation"))
        XCTAssertFalse(
            script.contains("curl ") ||
                script.contains("wget ") ||
                script.contains("-allowProvisioningUpdates") ||
                script.contains("generic/platform=iOS\"") ||
                script.contains("simctl erase") ||
                script.contains("simctl create"),
            "The simulator smoke helper must stay local, avoid provisioning, avoid physical-device destinations, and avoid destructive simulator setup."
        )
    }

    func testIOSSimulatorSmokeScriptCanOptIntoBootingExistingSimulatorWithoutCreatingDevices() throws {
        let scriptURL = packageRoot()
            .appendingPathComponent("Scripts")
            .appendingPathComponent("run-ios-simulator-smoke.sh")
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            XCTFail("A local simulator smoke helper should exist before the launch gate can be proven.")
            return
        }

        let script = try String(contentsOf: scriptURL)
        XCTAssertTrue(
            script.contains("MOONGATE_IOS_SIMULATOR_BOOT_IF_NEEDED"),
            "The smoke helper should have an explicit opt-in for booting an existing simulator."
        )
        XCTAssertTrue(
            script.contains("xcrun simctl boot \"$IOS_SIMULATOR_UDID\""),
            "The helper may boot only a selected existing simulator when explicitly opted in."
        )
        XCTAssertTrue(
            script.contains("xcrun simctl list devices available"),
            "When no simulator is booted, the helper should select from existing available devices instead of creating one."
        )
        XCTAssertFalse(
            script.contains("simctl create") || script.contains("simctl erase"),
            "The opt-in boot path must not create, erase, or reset simulator devices."
        )
    }

    func testIOSSimulatorSmokeScriptCanCaptureLocalScreenshotEvidenceWithoutUIAutomation() throws {
        let root = packageRoot()
        let scriptURL = root
            .appendingPathComponent("Scripts")
            .appendingPathComponent("run-ios-simulator-smoke.sh")
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            XCTFail("A local simulator smoke helper should exist before screenshot evidence can be captured.")
            return
        }

        let script = try String(contentsOf: scriptURL)
        let standardSmokeSource = try XCTUnwrap(script.fragment(
            from: "MOONGATE_IOS_SIMULATOR_CAPTURE_SCREENSHOT",
            to: "if [[ \"$MOONGATE_IOS_SIMULATOR_SCREENSHOT_MATRIX\" == \"1\" ]]"
        ))
        let gitignore = try String(contentsOf: root.appendingPathComponent(".gitignore"))

        XCTAssertTrue(
            script.contains("MOONGATE_IOS_SIMULATOR_CAPTURE_SCREENSHOT"),
            "Screenshot capture should be an explicit opt-in, not part of every launch smoke."
        )
        XCTAssertTrue(
            script.contains("MOONGATE_IOS_SIMULATOR_SCREENSHOT_DIR"),
            "The screenshot output directory should be configurable for local review runs."
        )
        XCTAssertTrue(
            script.contains("SCREENSHOT_DELAY_SECONDS=\"${MOONGATE_IOS_SIMULATOR_SCREENSHOT_DELAY_SECONDS:-8}\""),
            "The default screenshot delay should let the SwiftUI root view render before capturing visual evidence."
        )
        XCTAssertTrue(
            script.contains("$PROJECT_DIR/artifacts/ios-simulator-smoke"),
            "Default screenshots should stay inside a project-local artifacts folder."
        )
        XCTAssertTrue(
            script.contains("xcrun simctl io \"$IOS_SIMULATOR_UDID\" screenshot \"$SCREENSHOT_PATH\""),
            "The helper should capture the launched simulator screen through simctl screenshot."
        )
        XCTAssertTrue(
            gitignore.contains("artifacts/ios-simulator-smoke/"),
            "Local simulator screenshots should not be committed accidentally."
        )
        XCTAssertFalse(
            standardSmokeSource.contains("xcrun simctl ui") ||
                standardSmokeSource.contains("xcrun simctl keychain") ||
                standardSmokeSource.contains("xcrun simctl privacy") ||
                standardSmokeSource.contains("osascript") ||
                standardSmokeSource.contains("curl ") ||
                standardSmokeSource.contains("wget ") ||
                standardSmokeSource.contains("-allowProvisioningUpdates") ||
                standardSmokeSource.contains("simctl erase") ||
                standardSmokeSource.contains("simctl create"),
            "The screenshot smoke helper must stay local, avoid UI automation, avoid provisioning, and avoid destructive simulator setup."
        )
    }

    func testIOSSimulatorSmokeScriptCanCaptureAppearanceAndDynamicTypeScreenshotMatrix() throws {
        let root = packageRoot()
        let scriptURL = root
            .appendingPathComponent("Scripts")
            .appendingPathComponent("run-ios-simulator-smoke.sh")
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            XCTFail("A local simulator smoke helper should exist before screenshot matrix evidence can be captured.")
            return
        }

        let script = try String(contentsOf: scriptURL)

        XCTAssertTrue(
            script.contains("MOONGATE_IOS_SIMULATOR_SCREENSHOT_MATRIX"),
            "The screenshot matrix should be explicit opt-in, not part of every launch smoke."
        )
        XCTAssertTrue(
            script.contains("capture_screenshot_variant"),
            "The helper should name each local screenshot variant deterministically for review."
        )
        XCTAssertTrue(
            script.contains("xcrun simctl ui \"$IOS_SIMULATOR_UDID\" appearance"),
            "The local matrix should cover light and dark appearance using simctl UI overrides."
        )
        XCTAssertTrue(
            script.contains("xcrun simctl ui \"$IOS_SIMULATOR_UDID\" content_size"),
            "The local matrix should cover Dynamic Type using simctl content_size overrides."
        )
        XCTAssertTrue(
            script.contains("xcrun simctl ui \"$IOS_SIMULATOR_UDID\" increase_contrast"),
            "The local matrix should cover a high-contrast variant when the simulator runtime supports it."
        )
        XCTAssertTrue(
            script.contains("light-large") &&
                script.contains("dark-large") &&
                script.contains("light-accessibility-extra-extra-large") &&
                script.contains("dark-accessibility-extra-extra-large") &&
                script.contains("dark-high-contrast"),
            "The matrix should produce reviewable light/dark, Dynamic Type, and contrast filenames."
        )
        XCTAssertFalse(
            script.contains("simctl create") ||
                script.contains("simctl erase") ||
                script.contains("curl ") ||
                script.contains("wget ") ||
                script.contains("-allowProvisioningUpdates"),
            "The screenshot matrix must stay local, avoid network/provisioning, and avoid destructive simulator setup."
        )
    }

    func testIOSSimulatorScreenshotMatrixRelaunchesAppForEachVariant() throws {
        let scriptURL = packageRoot()
            .appendingPathComponent("Scripts")
            .appendingPathComponent("run-ios-simulator-smoke.sh")
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            XCTFail("A local simulator smoke helper should exist before screenshot matrix evidence can be captured.")
            return
        }

        let script = try String(contentsOf: scriptURL)
        let matrixSource = try XCTUnwrap(script.fragment(
            from: "if [[ \"$MOONGATE_IOS_SIMULATOR_SCREENSHOT_MATRIX\" == \"1\" ]]",
            to: "echo \"==> xcrun simctl terminate $BUNDLE_IDENTIFIER\""
        ))

        XCTAssertTrue(
            script.contains("launch_for_screenshot_variant"),
            "Each matrix variant should relaunch the app after simulator UI overrides so screenshots do not capture a blank launcher state."
        )
        XCTAssertEqual(
            matrixSource.matches(of: "capture_screenshot_matrix_tabs").count,
            5,
            "The five matrix variants should each capture the configured tab set after changing appearance/content size/contrast."
        )
        XCTAssertTrue(
            script.contains("MOONGATE_IOS_SIMULATOR_SCREENSHOT_TABS") &&
                script.contains("--moongate-ios-initial-tab"),
            "The screenshot matrix should support capturing Add, Queue, Library, and Settings without UI automation."
        )
        XCTAssertTrue(
            script.contains("MOONGATE_IOS_SIMULATOR_SCREENSHOT_VARIANTS") &&
                script.contains("matrix_should_capture_variant"),
            "The screenshot matrix should allow focused reruns of one visual variant after a review fix."
        )
        XCTAssertFalse(
            matrixSource.contains("simctl create") || matrixSource.contains("simctl erase"),
            "Relaunching for screenshots must not create, erase, or reset simulator devices."
        )
    }

    func testIOSXcodeAppHostSupportsSmokeOnlyInitialTabArgument() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("ios")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateiOSApp.swift"))

        XCTAssertTrue(source.contains("applyInitialTabArgumentIfPresent()"))
        XCTAssertTrue(source.contains("ProcessInfo.processInfo.arguments"))
        XCTAssertTrue(source.contains(#""--moongate-ios-initial-tab""#))
        XCTAssertTrue(source.contains("IOSMobileTab(rawValue: arguments[flagIndex + 1])"))
        XCTAssertTrue(source.contains("model.selectedTab = tab"))
        XCTAssertFalse(
            source.contains("simctl") || source.contains("XCTest"),
            "The app host should only read a local launch argument; simulator control stays in the script."
        )
    }

    func testIOSSimulatorSmokeCanSeedAddCandidateSelectionForVisualReviewOnly() throws {
        let root = packageRoot()
        let source = try String(contentsOf: root
            .appendingPathComponent("ios")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("MoongateiOSApp.swift"))
        let script = try String(contentsOf: root
            .appendingPathComponent("Scripts")
            .appendingPathComponent("run-ios-simulator-smoke.sh"))
        let smokeSeedSource = try XCTUnwrap(source.fragment(
            from: "private func applySmokeAddCandidatesArgumentIfPresent()",
            to: "private static func smokeAddCandidateSelectionSession()"
        ))
        let smokeSessionSource = try XCTUnwrap(source.fragment(
            from: "private static func smokeAddCandidateSelectionSession()",
            to: "}\n}"
        ))

        XCTAssertTrue(
            source.contains("applySmokeAddCandidatesArgumentIfPresent()") &&
                source.contains(#""--moongate-ios-smoke-add-candidates""#),
            "The app host should expose an explicit smoke-only launch argument for Add candidate screenshots."
        )
        XCTAssertTrue(
            source.contains("MobileAddSessionSnapshot(") &&
                source.contains("state: .candidateSelection") &&
                source.contains("selectedCandidateID: \"smoke-direct-media\""),
            "The seeded Add state should open directly on candidate selection with a supported candidate selected."
        )
        XCTAssertTrue(
            source.contains("https://example.com/mobile-smoke.mp4") &&
                source.contains("https://example.com/watch/mobile-smoke") &&
                source.contains("unsupportedReason: .requiresDesktopExtractor"),
            "The seeded candidates must use fixed public example URLs and include an unsupported desktop-extractor case."
        )
        XCTAssertFalse(
            smokeSeedSource.contains("UIPasteboard") ||
                smokeSeedSource.contains("UserDefaults") ||
                smokeSeedSource.contains("Keychain") ||
                smokeSeedSource.contains("URLSession") ||
                smokeSessionSource.contains("UIPasteboard") ||
                smokeSessionSource.contains("UserDefaults") ||
                smokeSessionSource.contains("Keychain") ||
                smokeSessionSource.contains("URLSession"),
            "Smoke seeding should read only local launch arguments and must not touch pasteboard, persistence, credentials, or network."
        )
        XCTAssertTrue(
            script.contains("MOONGATE_IOS_SIMULATOR_ADD_STATE") &&
                script.contains("if [[ \"$tab_name\" == \"add\" && \"$MOONGATE_IOS_SIMULATOR_ADD_STATE\" == \"candidates\" ]]") &&
                script.contains("--moongate-ios-smoke-add-candidates"),
            "The simulator script should pass the Add candidate seed only when explicitly opted in for Add screenshots."
        )
        XCTAssertFalse(
            script.contains("MOONGATE_IOS_SIMULATOR_ADD_STATE=\"candidates\""),
            "Candidate seeding must not become the default simulator smoke state."
        )
    }

    func testAndroidSettingsKeepsAPIKeyDraftEphemeralAndSavesThroughKeystore() throws {
        let source = try String(
            contentsOf: packageRoot()
                .appendingPathComponent("android")
                .appendingPathComponent("app")
                .appendingPathComponent("src")
                .appendingPathComponent("main")
                .appendingPathComponent("kotlin")
                .appendingPathComponent("com")
                .appendingPathComponent("moongate")
                .appendingPathComponent("mobile")
                .appendingPathComponent("android")
                .appendingPathComponent("MainActivity.kt")
        )

        XCTAssertFalse(
            source.contains("rememberSaveable { mutableStateOf(\"\") }"),
            "API-key drafts must not use rememberSaveable because saved instance state can persist the secret."
        )
        XCTAssertTrue(
            source.contains("var apiKeyDraft by remember { mutableStateOf(\"\") }"),
            "The API-key draft may exist only as ordinary Compose state so it is not saved across process recreation."
        )
        XCTAssertTrue(
            source.contains("PasswordVisualTransformation()") &&
                source.contains("KeyboardOptions(keyboardType = KeyboardType.Password)"),
            "The Android settings surface should mask the credential entry while saving through secure storage."
        )
        XCTAssertTrue(
            source.contains("remember { AndroidKeystoreCredentialStore(context) }") &&
                source.contains("credentialStore.saveCredential(secret, reference)"),
            "The Android settings surface should save API keys through the Keystore-backed credential store."
        )
        XCTAssertTrue(
            source.contains("apiKeyDraft = \"\""),
            "The Android settings surface should clear the in-memory API-key draft after a successful save."
        )
        XCTAssertTrue(
            source.contains("apiKeyAction.helperText") &&
                source.contains("ActionStatusChip(appState.settings.apiKeyAction)"),
            "The Android settings surface should show secure-storage readiness without exposing the saved secret value."
        )
    }

    func testAndroidProductionCopyAvoidsImplementationTerms() throws {
        let root = packageRoot()
        let androidDomain = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppModels.kt"))
        let mainActivity = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))
        let productionCopy = androidDomain + "\n" + mainActivity

        for term in [
            "live 路径",
            "requires direct",
            "推理引擎",
            "app 私有目录",
            "任务 JSON",
            "可序列化界面状态",
            "已保存到 Android Keystore",
            "任务服务",
            "运行时验证",
            "适配器接入",
            "接入后执行"
        ] {
            XCTAssertFalse(productionCopy.contains(term), "\(term) should not appear in production mobile copy.")
        }
        XCTAssertTrue(productionCopy.contains("视频下载器"))
        XCTAssertTrue(productionCopy.contains("密钥只保存在本机安全存储中"))
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func sourceSlice(in source: String, from startMarker: String, to endMarker: String) throws -> String {
        let startRange = try XCTUnwrap(source.range(of: startMarker), "Missing start marker: \(startMarker)")
        let remaining = source[startRange.upperBound...]
        let endRange = try XCTUnwrap(remaining.range(of: endMarker), "Missing end marker: \(endMarker)")
        return String(remaining[..<endRange.lowerBound])
    }
}

private extension String {
    func matches(of pattern: String) -> [Range<String.Index>] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let nsRange = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, range: nsRange).compactMap { match in
            Range(match.range, in: self)
        }
    }

    func fragment(from start: String, to end: String) -> String? {
        guard let startRange = range(of: start),
              let endRange = self[startRange.upperBound...].range(of: end)
        else {
            return nil
        }
        return String(self[startRange.lowerBound..<endRange.lowerBound])
    }
}
