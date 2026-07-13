import XCTest

final class MacOSAppBoundaryTests: XCTestCase {
    func testAppSettingsCommandOpensStandaloneSettingsWindow() throws {
        let source = try appSource()
        let commandBody = try XCTUnwrap(functionBody(prefix: "CommandGroup(replacing: .appSettings)", in: source))

        XCTAssertTrue(source.contains(".commands {"))
        XCTAssertTrue(source.contains("CommandGroup(replacing: .appSettings)"))
        XCTAssertTrue(commandBody.contains("model.showSettings = true"))
        XCTAssertTrue(commandBody.contains(".keyboardShortcut(\",\", modifiers: .command)"))
        // 不使用 SwiftUI 的 Settings 场景（那是 preferences 风格）；命令本身也不直接构造 SettingsView。
        XCTAssertFalse(source.contains("Settings {"))
        XCTAssertFalse(commandBody.contains("SettingsView(model:"))
        // 11c：设置改为独立 Window 场景，只保留红灯关闭；关闭时复位 showSettings 并消费挂起动作。
        XCTAssertTrue(source.contains("Window(localizer.t(L.App.settingsWindowTitle), id: \"settings\")"))
        XCTAssertTrue(source.contains("SettingsView(model: model)"))
        XCTAssertTrue(source.contains("SettingsWindowAccessor()"))
        XCTAssertTrue(source.contains("standardWindowButton(.miniaturizeButton)?.isHidden = true"))
        XCTAssertTrue(source.contains("standardWindowButton(.zoomButton)?.isHidden = true"))
        XCTAssertTrue(source.contains("window.styleMask.remove([.miniaturizable, .resizable])"))
        XCTAssertTrue(source.contains("model.consumePendingSettingsActions()"))
    }

    func testLibraryWorkspaceWindowAndCommandsHaveNativeFallbacks() throws {
        let source = try appSource()
        let content = try contentViewSource()
        let rootHost = try appRootHostSource()

        XCTAssertTrue(source.contains(".defaultSize(width: 1440, height: 900)"))
        XCTAssertTrue(source.contains(".windowResizability(.contentMinSize)"))
        XCTAssertTrue(content.contains(".frame(minWidth: 900, minHeight: 640)"))

        XCTAssertTrue(source.contains("AppWorkspaceCommand.newDownloadRequested"))
        XCTAssertTrue(source.contains(".keyboardShortcut(\"n\", modifiers: .command)"))
        XCTAssertTrue(source.contains("AppWorkspaceCommand.searchRequested"))
        XCTAssertTrue(source.contains(".keyboardShortcut(\"f\", modifiers: .command)"))
        XCTAssertTrue(source.contains("Toggle(localizer.t(L.Library.workspaceToggle)"),
                      "新布局必须保留菜单级 legacy fallback")
        XCTAssertTrue(rootHost.contains("model.enqueueDeferredDrafts(from: urlText, configuration: draft.queuedConfiguration())"),
                      "⌘N 的新建下载 sheet 必须创建可编辑的待开始任务")
    }

    func testSearchCommandKeepsLegacyFallbackFunctional() throws {
        let source = try appSource()
        XCTAssertTrue(source.contains("if useLibraryWorkspace {\n                    Button(localizer.t(L.Library.searchLibrary))"))
        XCTAssertTrue(source.contains("} else {\n                    Button(localizer.t(L.Main.urlInputAccessibility))"))
    }

    func testNewDownloadSheetCreatesEditableDeferredDraftsWithoutReadinessGate() throws {
        let rootHost = try appRootHostSource()
        let viewModel = try viewModelSource()

        XCTAssertTrue(rootHost.contains("@State private var draft: DownloadOptionsDraft"))
        XCTAssertTrue(rootHost.contains("Picker(localizer.t(L.Download.quality)"))
        XCTAssertTrue(rootHost.contains("Picker(localizer.t(L.Download.subtitleResult)"))
        XCTAssertTrue(rootHost.contains("Picker(localizer.t(L.Download.outputFormat)"))
        XCTAssertTrue(rootHost.contains("DisclosureGroup(localizer.t(L.Download.advancedOptions)"))
        XCTAssertTrue(rootHost.contains("configuration: draft.queuedConfiguration()"))
        XCTAssertFalse(rootHost.contains("L.SplitLayout.addSheetHint"),
                       "新下载流程不能复用旧的当前设置提示")

        let body = try XCTUnwrap(functionBody(prefix: "func enqueueDeferredDrafts", in: viewModel))
        XCTAssertTrue(body.contains("startImmediately: false"))
        let batch = try XCTUnwrap(functionBody(prefix: "private func processBatch", in: viewModel))
        XCTAssertTrue(batch.contains("queuedConfiguration?.applying(to: settings)"))
        XCTAssertTrue(batch.contains("queuedConfiguration?.outputFormat"))
        XCTAssertTrue(batch.contains("queuedConfiguration?.subtitleSourcePolicy"))
        XCTAssertFalse(body.contains("dependenciesReady("),
                       "待开始任务必须在真正启动前允许保存，即使运行环境尚未准备好")
        XCTAssertFalse(body.contains("blockIfTranslationNotReady("),
                       "翻译可用性不能阻止待开始任务的创建")
    }

    func testQueuedTaskStartRefreshesCredentialsWithoutReplacingTaskConfiguration() throws {
        let source = try viewModelSource()
        let start = try XCTUnwrap(functionBody(prefix: "func startQueuedTask", in: source))
        let startAll = try XCTUnwrap(functionBody(prefix: "func startAllQueuedTasks", in: source))
        let update = try XCTUnwrap(functionBody(prefix: "func updateQueuedTaskConfiguration", in: source))

        XCTAssertTrue(start.contains("hydrateCredentials()"))
        XCTAssertTrue(start.contains("queue.updateQueuedConfiguration("))
        XCTAssertTrue(start.contains("queue.start(id: id)"))
        XCTAssertTrue(startAll.contains("startQueuedTask(id:"))
        XCTAssertTrue(update.contains("item.stage == .queued"))
        XCTAssertTrue(source.contains("private func updateQueuedTaskConfiguration"))
        XCTAssertTrue(source.contains("queue.updateQueuedConfiguration("))
    }

    func testNewDownloadSheetKeepsAsyncResolutionFeedbackVisible() throws {
        let rootHost = try appRootHostSource()
        let viewModel = try viewModelSource()

        XCTAssertTrue(rootHost.contains("@State private var isSubmitting"))
        XCTAssertTrue(rootHost.contains("submissionResult"))
        XCTAssertTrue(rootHost.contains(".onChange(of: model.enqueueNotice)"))
        XCTAssertTrue(rootHost.contains("localizer.t(L.Download.resolvingLinks)"))
        XCTAssertTrue(viewModel.contains("func enqueueDeferredDrafts(from text: String, configuration: QueuedProcessingConfiguration) -> Bool"),
                      "无效链接必须让 Sheet 当场保留并显示结果")
    }

    func testInterruptedLibraryItemRestartsWithItsStableIdentity() throws {
        let viewModel = try viewModelSource()
        let queue = try queueManagerSource()

        let restart = try XCTUnwrap(functionBody(prefix: "func restartInterruptedLibraryItem", in: viewModel))
        XCTAssertTrue(restart.contains("processBatch("))
        XCTAssertTrue(restart.contains("libraryItemID: item.id"))
        XCTAssertTrue(restart.contains("libraryVersionID: version.id"))
        XCTAssertTrue(queue.contains("libraryItemID: UUID? = nil"))
        XCTAssertTrue(queue.contains("libraryVersionID: UUID? = nil"))
    }

    func testReprocessDefersLocalASRReadinessToItsFrozenTaskSettings() throws {
        let source = try viewModelSource()
        let body = try XCTUnwrap(functionBody(prefix: "func enqueueLibraryReprocess", in: source))

        // The global generator can still represent the previous selected
        // model. Let QueueManager inspect this task's validated snapshot so
        // an unavailable replacement stays queued with a recovery message.
        XCTAssertFalse(body.contains("subtitleKind == .localASR, !queue.hasLocalASRGenerator"))
        XCTAssertTrue(body.contains("subtitleKind == .cloudASR, !queue.hasCloudASRGenerator"))
        XCTAssertTrue(body.contains("openCloudASRSettings()"))
        XCTAssertTrue(body.contains("taskConfiguration.applying(to: taskSettings)"))
    }

    func testReprocessValidatesAChangedLocalASRModelBeforeEnqueueing() throws {
        let source = try viewModelSource()
        let body = try XCTUnwrap(functionBody(prefix: "func enqueueLibraryReprocess", in: source))

        // 重新处理不能只改 localASRModelID 而沿用旧路径，否则 UI 会显示新模型、
        // 实际却静默运行旧模型。必须复用待开始任务的受校验配置路径。
        XCTAssertTrue(body.contains("let taskConfiguration = QueuedProcessingConfiguration("))
        XCTAssertTrue(body.contains("transcriptionModel: requiresASR ? configuration.transcriptionModel : nil"))
        XCTAssertTrue(body.contains("taskConfiguration.applying(to: taskSettings)"))
        XCTAssertFalse(body.contains("taskSettings.localASRModelID = transcriptionModel"))

        let configuration = try XCTUnwrap(body.range(of: "let taskConfiguration = QueuedProcessingConfiguration("))
        let enqueue = try XCTUnwrap(body.range(of: "queue.enqueueReprocess("))
        XCTAssertLessThan(
            configuration.lowerBound,
            enqueue.lowerBound,
            "模型路径必须在重新处理任务入队前解析；未知或未安装模型应保持为无路径的待开始任务"
        )
    }

    func testAbortConfirmationExplainsChoicesWithoutChangingButtonsOrReturnMapping() throws {
        let source = try appSource()
        let body = try XCTUnwrap(functionBody(prefix: "private func confirmAbortDownload", in: source))

        XCTAssertTrue(body.contains("alert.informativeText ="))
        XCTAssertTrue(body.contains("localizer.t(L.App.abortInformativeText)"))
        XCTAssertTrue(body.contains("localizer.t(L.App.keepTasks)"))
        XCTAssertTrue(body.contains("localizer.t(L.App.abortTasks)"))
        XCTAssertTrue(body.contains("return alert.runModal() == .alertSecondButtonReturn"))

        let keepButton = try XCTUnwrap(body.range(of: "alert.addButton(withTitle: localizer.t(L.App.keepTasks))"))
        let abortButton = try XCTUnwrap(body.range(of: "alert.addButton(withTitle: localizer.t(L.App.abortTasks))"))
        let abortReturn = try XCTUnwrap(body.range(of: ".alertSecondButtonReturn"))

        XCTAssertLessThan(keepButton.lowerBound, abortButton.lowerBound)
        XCTAssertLessThan(abortButton.lowerBound, abortReturn.lowerBound)

        let messageBody = try XCTUnwrap(functionBody(prefix: "private func abortConfirmationMessage", in: source))
        XCTAssertTrue(messageBody.contains("localizer.t(L.App.abortPausedTasks"))
        XCTAssertTrue(messageBody.contains("localizer.t(L.App.abortRunningTasks"))
    }

    private func appSource() throws -> String {
        try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("Moongate")
            .appendingPathComponent("App.swift"))
    }

    private func contentViewSource() throws -> String {
        try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("Moongate")
            .appendingPathComponent("ContentView.swift"))
    }

    private func appRootHostSource() throws -> String {
        try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("Moongate")
            .appendingPathComponent("AppRootHost.swift"))
    }

    private func viewModelSource() throws -> String {
        try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("Moongate")
            .appendingPathComponent("ViewModel.swift"))
    }

    private func queueManagerSource() throws -> String {
        try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("Moongate")
            .appendingPathComponent("QueueManager.swift"))
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func functionBody(prefix: String, in source: String) -> String? {
        guard let declaration = source.range(of: prefix) else { return nil }
        guard let openingBrace = source[declaration.lowerBound...].firstIndex(of: "{") else { return nil }

        var depth = 0
        var cursor = openingBrace
        while cursor < source.endIndex {
            switch source[cursor] {
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return String(source[openingBrace...cursor])
                }
            default:
                break
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }
}
