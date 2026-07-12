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
        XCTAssertTrue(source.contains("Toggle(\"资料库工作台\""),
                      "新布局必须保留菜单级 legacy fallback")
        XCTAssertTrue(rootHost.contains("model.enqueueDeferredDrafts(from: urlText, configuration: configuration)"),
                      "⌘N 的新建下载 sheet 必须创建可编辑的待开始任务")
    }

    func testNewDownloadSheetCreatesEditableDeferredDraftsWithoutReadinessGate() throws {
        let rootHost = try appRootHostSource()
        let viewModel = try viewModelSource()

        XCTAssertTrue(rootHost.contains("@State private var configuration: QueuedProcessingConfiguration"))
        XCTAssertTrue(rootHost.contains("Picker(\"画质\""))
        XCTAssertTrue(rootHost.contains("Picker(\"字幕来源\""))
        XCTAssertTrue(rootHost.contains("Picker(\"字幕样式\""))
        XCTAssertFalse(rootHost.contains("高级设置\") {\n                Text(\"画质、字幕来源和模型可在“设置”中调整"))

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

    func testReprocessChecksASRReadinessBeforeCreatingAnIsolatedTask() throws {
        let source = try viewModelSource()
        let body = try XCTUnwrap(functionBody(prefix: "func enqueueLibraryReprocess", in: source))

        XCTAssertTrue(body.contains("subtitleKind == .localASR, !queue.hasLocalASRGenerator"))
        XCTAssertTrue(body.contains("subtitleKind == .cloudASR, !queue.hasCloudASRGenerator"))
        XCTAssertTrue(body.contains("openLocalASRSettings()"))
        XCTAssertTrue(body.contains("openCloudASRSettings()"))
        XCTAssertLessThan(
            try XCTUnwrap(body.range(of: "subtitleKind == .localASR")).lowerBound,
            try XCTUnwrap(body.range(of: "let subtitleTrack")).lowerBound,
            "ASR 依赖必须在构建并入队请求前失败"
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
