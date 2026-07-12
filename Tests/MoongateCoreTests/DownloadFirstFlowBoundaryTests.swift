import XCTest

/// The download-first entry points live in the app target, so these source
/// boundaries protect their product contract without inventing a second UI
/// test harness just for SwiftUI sheets.
final class DownloadFirstFlowBoundaryTests: XCTestCase {
    func testNewDownloadKeepsItsDefaultPathResultFocused() throws {
        let source = try appRootHostSource()
        let defaultPath = try XCTUnwrap(section(
            in: source,
            from: "var body: some View {",
            to: "DisclosureGroup(localizer.t(L.Download.advancedOptions)"
        ))
        let advancedOptions = try XCTUnwrap(section(
            in: source,
            from: "DisclosureGroup(localizer.t(L.Download.advancedOptions)",
            to: "Text(localizer.t(L.Download.deferredQueueHint))"
        ))

        XCTAssertTrue(source.contains("@State private var draft: DownloadOptionsDraft"))
        XCTAssertTrue(source.contains("Text(localizer.t(L.Download.defaultSummary, configurationSummary))"),
                      "默认设置只应以一个简短摘要出现一次")
        XCTAssertTrue(source.contains("Picker(localizer.t(L.Download.quality)"))
        XCTAssertTrue(source.contains("Picker(localizer.t(L.Download.subtitleResult)"))
        XCTAssertTrue(source.contains("Picker(localizer.t(L.Download.outputFormat)"))
        XCTAssertTrue(source.contains("DisclosureGroup(localizer.t(L.Download.advancedOptions)"))
        XCTAssertTrue(source.contains("if draft.showsTranslationOptions"))
        XCTAssertTrue(source.contains("if draft.subtitleOutcome == .embeddedTranslation"))
        XCTAssertTrue(source.contains("if draft.usesCustomRecognition"))
        XCTAssertTrue(source.contains("configuration: draft.queuedConfiguration()"),
                      "提交时必须把人话选项映射回既有的待开始配置")
        XCTAssertFalse(defaultPath.contains("Picker(localizer.t(L.Download.subtitleSource"),
                       "字幕来源不是默认路径的一部分")
        XCTAssertFalse(defaultPath.contains("TranscriptionModelPicker"),
                       "精确模型不能在默认路径出现")
        XCTAssertTrue(advancedOptions.contains("TranscriptionModelPicker"),
                      "精确模型选择只能放在二级高级选项中")
        XCTAssertFalse(source.contains("本地识别（Whisper）"))
        XCTAssertFalse(source.contains("L.SplitLayout.addSheetHint"),
                       "旧的“当前设置”提示会与新的结果摘要重复")
        XCTAssertFalse(source.contains("当前处理设置"),
                       "不要与默认摘要重复表达同一件事")
    }

    func testOnboardingIsAOptionalTwoStepEntryToTheFirstDownload() throws {
        let source = try contentViewSource()
        let onboarding = try XCTUnwrap(section(
            in: source,
            from: "private enum DownloadFirstOnboardingStep",
            to: "\n}\n"
        ))
        let view = try XCTUnwrap(section(
            in: source,
            from: "private struct DownloadFirstOnboardingView",
            to: "__end_of_file__"
        ))

        XCTAssertTrue(onboarding.contains("case welcome"))
        XCTAssertTrue(onboarding.contains("case defaults"))
        XCTAssertFalse(onboarding.contains("case readiness"))
        XCTAssertFalse(onboarding.contains("case subtitleSource"))
        XCTAssertFalse(onboarding.contains("case translationMethod"))

        XCTAssertTrue(source.contains("DownloadFirstOnboardingView(model: model)"))
        XCTAssertTrue(view.contains("Button(localizer.t(L.Onboarding.addFirstVideo))"))
        XCTAssertTrue(view.contains("localizer.t(L.Onboarding.configureDownloadDefaults)"))
        XCTAssertTrue(view.contains("localizer.t(L.Onboarding.setDefaultsLater)"))
        XCTAssertTrue(view.contains("model.acknowledgeOnboardingKeepingCurrentDefaults()"),
                      "欢迎页必须只确认 onboarding，不重写用户已有默认项")
        XCTAssertTrue(view.contains("model.commitOnboardingDefaultEdits("),
                      "只有默认项页才提交用户明确编辑的结果")
        XCTAssertTrue(view.contains("AppWorkspaceCommand.newDownloadRequested"),
                      "主操作完成 onboarding 后必须直接进入新建下载")
        XCTAssertFalse(view.contains("PreparationCenterView"))
        XCTAssertFalse(view.contains("showPreparationCenter"))
        XCTAssertFalse(view.contains("onboardingAuthToken"))
        XCTAssertFalse(view.contains("APIConfigEditor"))
    }

    func testWelcomeAcknowledgesWithoutWritingDefaultsAndDefaultsRevealTranslationOnlyWhenNeeded() throws {
        let source = try contentViewSource()
        let welcome = try XCTUnwrap(section(
            in: source,
            from: "private var welcomeContent",
            to: "private var defaultsContent"
        ))
        let defaults = try XCTUnwrap(section(
            in: source,
            from: "private var defaultsContent",
            to: "private func finish"
        ))
        let acknowledgement = try XCTUnwrap(section(
            in: source,
            from: "private func acknowledgeOnboarding",
            to: "private func commitDefaults"
        ))

        XCTAssertTrue(welcome.contains("acknowledgeOnboarding(openNewDownload:"))
        XCTAssertFalse(welcome.contains("commitOnboardingDefaultEdits("))
        XCTAssertFalse(welcome.contains("lastSubtitleMode"))
        XCTAssertTrue(acknowledgement.contains("model.acknowledgeOnboardingKeepingCurrentDefaults()"))
        XCTAssertFalse(acknowledgement.contains("commitOnboardingDefaultEdits("))
        XCTAssertTrue(defaults.contains("if needsTranslationDefaults"))
        XCTAssertTrue(defaults.contains("Picker(localizer.t(L.Onboarding.translateTo)"))
        XCTAssertTrue(defaults.contains("Toggle(localizer.t(L.Onboarding.useSystemTranslation)"))
    }

    private func appRootHostSource() throws -> String {
        try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources/Moongate/AppRootHost.swift"))
    }

    private func contentViewSource() throws -> String {
        try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources/Moongate/ContentView.swift"))
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func section(in source: String, from: String, to: String) -> String? {
        guard let start = source.range(of: from) else { return nil }
        let tail = source[start.lowerBound...]
        guard let end = tail.range(of: to) else { return String(tail) }
        return String(source[start.lowerBound..<end.lowerBound])
    }
}
