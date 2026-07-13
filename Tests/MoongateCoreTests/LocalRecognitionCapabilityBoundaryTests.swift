import XCTest
@testable import MoongateMobileCore

final class LocalRecognitionCapabilityBoundaryTests: XCTestCase {
    func testCapabilitySheetPresentsOnlyHonestUserFacingRecoveryStates() throws {
        let source = try settingsSource()

        XCTAssertTrue(source.contains("LocalRecognitionCapabilitySheet("))
        XCTAssertTrue(source.contains("showLocalRecognitionCapability = true"))
        XCTAssertTrue(source.contains("localRecognitionCapabilityPresentation"))
        XCTAssertTrue(source.contains("recheckExistingLocalRecognition"))
        XCTAssertTrue(source.contains("installRecommendedLocalRecognitionModel"))
        XCTAssertTrue(source.contains("cancelLocalRecognitionInstall"))
        XCTAssertTrue(source.contains("retryLocalRecognitionInstall"))
        XCTAssertTrue(source.contains("LocalRecognitionCapabilityPresentation.runtimeMissing"))
        XCTAssertTrue(source.contains("LocalRecognitionCapabilityPresentation.modelRequired"))
        XCTAssertTrue(source.contains("LocalRecognitionCapabilityPresentation.enabled"))
        XCTAssertFalse(source.contains("showPreparationCenter"))
    }

    func testCapabilitySheetDoesNotPromiseAnUnavailableRuntimeDownload() throws {
        let sheetURL = packageRoot()
            .appendingPathComponent("Sources/Moongate/LocalRecognitionCapabilitySheet.swift")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sheetURL.path),
                      "按需能力 Sheet 必须是独立可审查的用户层，不应回退到准备中心")
        guard FileManager.default.fileExists(atPath: sheetURL.path) else { return }

        let source = try String(contentsOf: sheetURL)
        for key in [
            "L.Settings.localRecognitionRuntimeMissingTitle",
            "L.Settings.localRecognitionRecheck",
            "L.Settings.localRecognitionUseAutomatic",
            "L.Settings.localRecognitionUseCloud",
            "L.Settings.localRecognitionContinueVideoOnly",
            "L.Settings.localRecognitionDownloadEnable",
            "L.Settings.localRecognitionCancelDownload",
            "L.Common.retry"
        ] {
            XCTAssertTrue(source.contains(key), "能力 Sheet 必须通过本地化 key 呈现 \(key)")
        }
        for language in ResolvedLanguage.allCases {
            XCTAssertNotEqual(
                LocalizedStrings.string(L.Settings.localRecognitionRuntimeMissingTitle, language: language),
                L.Settings.localRecognitionRuntimeMissingTitle
            )
            XCTAssertNotEqual(
                LocalizedStrings.string(L.Settings.localRecognitionDownloadEnable, language: language),
                L.Settings.localRecognitionDownloadEnable
            )
        }
        XCTAssertFalse(source.contains("一键准备"))
        XCTAssertFalse(source.contains("下载运行时"))
        XCTAssertFalse(source.contains("Whisper"))
        XCTAssertFalse(source.contains("VAD"))
        XCTAssertFalse(source.contains("SHA"))
    }

    func testOnboardingDoesNotAutomaticallyOpenTechnicalDependencySetup() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources/Moongate/ViewModel.swift"))

        let onAppear = try XCTUnwrap(functionBody(named: "onAppear", in: source))
        let acknowledge = try XCTUnwrap(functionBody(named: "acknowledgeOnboardingKeepingCurrentDefaults", in: source))
        let commitDefaults = try XCTUnwrap(functionBody(named: "commitOnboardingDefaultEdits", in: source))

        XCTAssertFalse(onAppear.contains("showDependencySetupIfNeededOnStartup"))
        XCTAssertFalse(acknowledge.contains("showDependencySetupIfNeededOnStartup"))
        XCTAssertFalse(commitDefaults.contains("showDependencySetupIfNeededOnStartup"))
        XCTAssertTrue(source.contains("func requestDependencySetup()"),
                      "显式请求和真实下载失败后的依赖修复必须保留")
    }

    func testHomebrewRuntimeCandidatesWorkWithoutFinderPathInheritance() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources/Moongate/ViewModel.swift"))

        XCTAssertTrue(source.contains("/opt/homebrew/bin/whisper-cli"))
        XCTAssertTrue(source.contains("/usr/local/bin/whisper-cli"))
    }

    func testAttentionRoutesLocalAndCloudRecognitionToDifferentHonestDestinations() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources/Moongate/ViewModel.swift"))
        let local = try XCTUnwrap(functionBody(named: "openLocalASRSettings", in: source))

        XCTAssertTrue(source.contains("enum LocalRecognitionCapabilitySetupRequest"))
        XCTAssertTrue(source.contains("case queuedTask(UUID)"))
        XCTAssertTrue(source.contains("@Published var localRecognitionCapabilitySetupRequest"))
        XCTAssertTrue(local.contains("localRecognitionCapabilitySetupRequest = .defaults"))
        XCTAssertTrue(local.contains("openSettings(paneID: \"subtitlesLanguage\")"))
        XCTAssertFalse(local.contains("settingsNotice = CoreL10n"))
        XCTAssertTrue(source.contains("func openLocalASRSettings(forQueuedTaskID queueID: UUID)"))
        XCTAssertTrue(source.contains("localRecognitionCapabilitySetupRequest = .queuedTask(queueID)"))
        XCTAssertTrue(source.contains("func applyQueuedRecognitionFallback("))
        XCTAssertTrue(source.contains("func refreshQueuedLocalRecognitionCapability(id: UUID)"))
        XCTAssertTrue(source.contains("func refreshQueuedCloudRecognitionCapability(id: UUID)"))
        XCTAssertTrue(source.contains("func openCloudASRSettings()"),
                      "下载页的既有云端恢复入口应继续保留")
        XCTAssertTrue(source.contains("func openCloudASRSettings(forQueuedTaskID queueID: UUID?)"),
                      "待开始任务需要一个携带任务 ID 的恢复入口")
        XCTAssertTrue(source.contains("openSettings(paneID: \"servicesAccounts\")"))
        XCTAssertTrue(source.contains("cloudRecognitionConfigurationRequestQueueID = queueID"))
        XCTAssertFalse(source.contains("openSettings(paneID: \"localSpeech\")"))
    }

    func testQueuedCapabilityRecoveryUpdatesTheOriginatingTaskAndOffersRealCloudSetup() throws {
        let settings = try settingsSource()
        let workspace = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources/Moongate/LibraryWorkspaceModel.swift"))

        XCTAssertTrue(workspace.contains("openLocalASRSettings(forQueuedTaskID: queueID)"))
        XCTAssertTrue(settings.contains("activeQueuedCapabilityTaskID"))
        XCTAssertTrue(settings.contains("applyQueuedRecognitionFallback(id: queueID, fallback: .platformSubtitles)"))
        XCTAssertTrue(settings.contains("applyQueuedRecognitionFallback(id: queueID, fallback: .videoOnly)"))
        XCTAssertTrue(settings.contains("refreshQueuedLocalRecognitionCapability(id: queueID)"))
        XCTAssertTrue(settings.contains("cloudRecognitionServiceSection"))
        XCTAssertTrue(settings.contains("$draft.cloudASREnabled"))
        XCTAssertTrue(settings.contains("$draft.cloudASRConsentAccepted"))
        XCTAssertTrue(settings.contains("$draft.cloudASRBaseURL"))
        XCTAssertTrue(settings.contains("$draft.cloudASRModel"))
        XCTAssertTrue(settings.contains("$draft.cloudASRAuthToken"))
        XCTAssertTrue(settings.contains("saveCloudRecognitionForPendingTask()"))
    }

    func testOrdinarySurfacesHideSetupInternalsAndAbsolutePaths() throws {
        let settings = try settingsSource()
        let capabilitySheet = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources/Moongate/LocalRecognitionCapabilitySheet.swift"))
        let newDownload = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources/Moongate/AppRootHost.swift"))
        let workspace = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources/Moongate/LibraryWorkspaceView.swift"))

        let ordinarySettings = [
            try XCTUnwrap(functionBody(named: "settingsPaneDetail", in: settings)),
            try XCTUnwrap(functionBody(named: "localRecognitionPreferencesSection", in: settings)),
            try XCTUnwrap(functionBody(named: "translationConfigSection", in: settings)),
            try XCTUnwrap(functionBody(named: "storageSection", in: settings)),
        ].joined(separator: "\n")
        let newDownloadDefaultPath = try XCTUnwrap(section(
            in: newDownload,
            from: "var body: some View {",
            to: "DisclosureGroup(localizer.t(L.Download.advancedOptions)"
        ))
        let settingsBody = try XCTUnwrap(section(
            in: settings,
            from: "var body: some View {",
            to: "private func recordDraftChange"
        ))

        for term in ["PreparationCenter", "Whisper", "VAD", "系统语言包"] {
            XCTAssertFalse(ordinarySettings.localizedCaseInsensitiveContains(term), "常规设置不应暴露 \(term)")
            XCTAssertFalse(capabilitySheet.localizedCaseInsensitiveContains(term), "能力 Sheet 不应暴露 \(term)")
            XCTAssertFalse(newDownloadDefaultPath.localizedCaseInsensitiveContains(term), "默认新建下载路径不应暴露 \(term)")
        }

        XCTAssertFalse(ordinarySettings.localizedCaseInsensitiveContains("runtime"))
        XCTAssertFalse(ordinarySettings.localizedCaseInsensitiveContains("sha256"))
        XCTAssertFalse(newDownloadDefaultPath.localizedCaseInsensitiveContains("runtime"))
        XCTAssertFalse(capabilitySheet.contains("运行时"))
        XCTAssertFalse(capabilitySheet.contains("下载运行时"))

        let queuedReadiness = try XCTUnwrap(functionBody(named: "queuedReadinessDetail", in: workspace))
        XCTAssertTrue(queuedReadiness.contains("L.Library.localRecognitionUnavailable"))
        XCTAssertTrue(queuedReadiness.contains("L.Library.cloudRecognitionUnavailable"))
        XCTAssertFalse(queuedReadiness.contains("return detail"), "底层队列诊断不可原样显示在工作台")

        XCTAssertFalse(ordinarySettings.contains("path:"), "存储和设置路径不得展示绝对路径")
        XCTAssertFalse(ordinarySettings.contains(".path"), "存储和设置路径不得展示绝对路径")
        XCTAssertFalse(settingsBody.contains("refreshDependencies()"), "打开普通设置不应触发底层组件体检")
        XCTAssertFalse(capabilitySheet.contains("下载运行时"), "当前没有可验证运行时下载资产时，不得承诺可下载")
        XCTAssertTrue(newDownloadDefaultPath.contains("Picker(localizer.t(L.Download.quality)"))
        XCTAssertTrue(newDownloadDefaultPath.contains("Picker(localizer.t(L.Download.subtitleResult)"))
        XCTAssertTrue(newDownloadDefaultPath.contains("Picker(localizer.t(L.Download.outputFormat)"))
        XCTAssertFalse(newDownloadDefaultPath.contains("TranscriptionModelPicker"))
        XCTAssertTrue(workspace.contains("NavigationSplitView"))
        XCTAssertTrue(workspace.contains(".inspector(isPresented:"))
    }

    private func settingsSource() throws -> String {
        try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources/Moongate/SettingsView.swift"))
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func functionBody(named name: String, in source: String) -> String? {
        let declarations = [
            "func \(name)(",
            "private func \(name)(",
            "static func \(name)(",
            "private var \(name):",
            "private var \(name) "
        ]
        guard let declaration = declarations.compactMap({ source.range(of: $0) }).first,
              let openingBrace = source[declaration.lowerBound...].firstIndex(of: "{") else {
            return nil
        }

        var depth = 0
        var cursor = openingBrace
        while cursor < source.endIndex {
            switch source[cursor] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return String(source[openingBrace...cursor])
                }
            default: break
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }

    private func section(in source: String, from: String, to: String) -> String? {
        guard let start = source.range(of: from) else { return nil }
        let tail = source[start.lowerBound...]
        guard let end = tail.range(of: to) else { return String(tail) }
        return String(source[start.lowerBound..<end.lowerBound])
    }
}
