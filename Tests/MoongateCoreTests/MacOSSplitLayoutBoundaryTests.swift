import XCTest

/// SplitLayoutView（备忘录式三栏原型）此前 440 行零测试守护。补一个源码扫描 boundary 测试，
/// 与其它 MacOS*BoundaryTests 同风格（App target 的 SwiftUI 视图无法 @testable import，只能扫源码），
/// 锁定原型的关键不变量，防静默回归。
final class MacOSSplitLayoutBoundaryTests: XCTestCase {

    /// 三栏是 feature-flag 隔离的原型，默认关闭；ContentView 在 flag 上二选一，
    /// legacy 界面零改动。这条守护"默认不影响现有用户"这一硬约束。
    func testSplitLayoutIsFeatureFlaggedOffByDefault() throws {
        let content = try contentViewSource()
        XCTAssertTrue(content.contains("@AppStorage(\"experimental.splitLayout\")"),
                      "三栏必须由 experimental.splitLayout 开关控制")
        XCTAssertTrue(content.contains("private var useSplitLayout = false"),
                      "默认必须为 false（不影响现有界面）")
        XCTAssertTrue(content.contains("if useSplitLayout {"))
        XCTAssertTrue(content.contains("SplitLayoutView(model: model)"))
        XCTAssertTrue(content.contains("legacyBody"),
                      "原界面必须原样抽成 legacyBody 走 else 分支")
    }

    /// sidebar 按状态分组：进行中(queued/downloading/translating/burning) vs 已完成(done/failed/cancelled)。
    func testSidebarPartitionsByStageIntoActiveAndFinished() throws {
        let source = try splitLayoutSource()
        let active = try XCTUnwrap(functionBody(named: "activeItems", in: source))
        let finished = try XCTUnwrap(functionBody(named: "finishedItems", in: source))
        // 进行中组覆盖四个未终态。
        for stage in ["queued", "downloading", "translating", "burning"] {
            XCTAssertTrue(active.contains(".\(stage)"), "进行中组应含 .\(stage)")
        }
        // 已完成组覆盖三个终态。
        for stage in ["done", "failed", "cancelled"] {
            XCTAssertTrue(finished.contains(".\(stage)"), "已完成组应含 .\(stage)")
        }
        // 两个 Section 带计数。
        XCTAssertTrue(source.contains("L.SplitLayout.sectionActive"))
        XCTAssertTrue(source.contains("L.SplitLayout.sectionFinished"))
    }

    /// 复用既有组件与真实队列操作，不重造：ProgressRingView 进度环 + QueueManager 操作。
    func testDetailReusesProgressRingAndRealQueueOperations() throws {
        let source = try splitLayoutSource()
        XCTAssertTrue(source.contains("ProgressRingView("), "进度环应复用 ProgressRingView")
        for op in ["queue.pause(", "queue.resume(", "queue.cancel(", "queue.retry(",
                   "queue.remove(", "queue.revealInFinder("] {
            XCTAssertTrue(source.contains(op), "detail 操作应调用真实 \(op)")
        }
        // 完成态预览的播放走系统播放器。
        XCTAssertTrue(source.contains("NSWorkspace.shared.open("))
    }

    /// done 态动作集必须与 legacy 队列对等（commit 084768a 补齐）：
    /// partialFailure→重跑字幕(retry)、完成视频+本地生成器就绪→本地 Whisper 重识别(retryWithLocalASR)、
    /// 有产物→在 Finder 显示、始终可移除。此前 detail 的 .done 只有 reveal/remove，是完整性缺口。
    func testDoneStateActionsMatchLegacyQueue() throws {
        let source = try splitLayoutSource()
        let actions = try XCTUnwrap(functionBody(named: "actionButtons", in: source))
        // 部分成功只重跑字幕处理（不重新下载），条件为 partialFailure。
        XCTAssertTrue(actions.contains("item.partialFailure"),
                      "done 态应据 partialFailure 决定是否显示重跑字幕")
        XCTAssertTrue(actions.contains("L.Queue.retrySubtitle"),
                      "部分成功应提供「重跑字幕」")
        // 完成项本地 Whisper 重识别：既要 done+有视频(canRetryWithLocalASR)，也要生成器就绪(hasLocalASRGenerator)。
        XCTAssertTrue(actions.contains("queue.retryWithLocalASR("),
                      "done 态应提供本地 ASR 重识别真实操作（此前无测试守护）")
        XCTAssertTrue(actions.contains("queue.canRetryWithLocalASR(") && actions.contains("queue.hasLocalASRGenerator"),
                      "本地 ASR 重识别按钮需 done+有视频 且 生成器就绪双重守护")
        XCTAssertTrue(actions.contains("L.Queue.retryWithLocalASR"),
                      "本地重识别按钮应用 retryWithLocalASR 文案")
    }

    /// 登录类失败项必须在 detail 提供「登录并重试」恢复入口（与 legacy 队列一致），
    /// 否则用户无法从三栏恢复登录门失败——完整性守护。
    func testFailedLoginItemExposesLoginRecovery() throws {
        let source = try splitLayoutSource()
        XCTAssertTrue(source.contains("item.needsLogin"),
                      "failed 分支应根据 needsLogin 决定是否显示登录入口")
        XCTAssertTrue(source.contains("L.Queue.loginAndRetry"),
                      "登录类失败应显示「登录并重试」按钮")
        XCTAssertTrue(source.contains("onLogin("),
                      "登录按钮应调用 onLogin 闭包（外层 wire 到 model.openLoginForQueueItem）")
    }

    /// "添加"是真实流程：走 model.addTasks（复用批量自动入队），非占位。
    func testAddSheetWiresToRealAddTasks() throws {
        let source = try splitLayoutSource()
        XCTAssertTrue(source.contains("model.addTasks(from:"),
                      "添加应调用 model.addTasks（真实入队），而非占位提示")
        XCTAssertTrue(source.contains(".sheet(isPresented: $showAddSheet)"))
        // 取消/确认都清空输入并关闭。
        XCTAssertTrue(source.contains("keyboardShortcut(.cancelAction)"))
        XCTAssertTrue(source.contains("keyboardShortcut(.defaultAction)"))
    }

    /// 添加反馈必须在三栏可见：sheet 即时关闭、成功项才进 sidebar，若不展示 batchStatusText/
    /// enqueueNotice，用户粘贴无效链接/全部失败时毫无反馈。守护三栏也观察这两个 @Published。
    func testAddFeedbackSurfacesBatchStatusAndEnqueueNotice() throws {
        let source = try splitLayoutSource()
        XCTAssertTrue(source.contains("model.batchStatusText"),
                      "三栏应展示批量解析进度 batchStatusText")
        XCTAssertTrue(source.contains("model.enqueueNotice"),
                      "三栏应展示添加结果摘要 enqueueNotice（含无效/失败/重复反馈）")
    }

    /// 可访问性：装饰性图标 hidden、行/详情合并为可读元素、播放/添加按钮有 label。
    func testSplitLayoutAccessibility() throws {
        let source = try splitLayoutSource()
        XCTAssertTrue(source.contains(".accessibilityHidden(true)"), "装饰图标应对 VoiceOver 隐藏")
        XCTAssertTrue(source.contains(".accessibilityElement(children: .combine)"))
        XCTAssertTrue(source.contains(".accessibilityLabel(localizer.t(L.SplitLayout.play))"))
    }

    // MARK: - helpers（与其它 boundary 测试同款）

    private func splitLayoutSource() throws -> String {
        try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources").appendingPathComponent("Moongate")
            .appendingPathComponent("SplitLayoutView.swift"))
    }

    private func contentViewSource() throws -> String {
        try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources").appendingPathComponent("Moongate")
            .appendingPathComponent("ContentView.swift"))
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func functionBody(named name: String, in source: String) -> String? {
        let declarations = [
            "private var \(name):", "private var \(name) ",
            "var \(name):", "var \(name) ",
            "private func \(name)(", "func \(name)("
        ]
        guard let declaration = declarations.compactMap({ source.range(of: $0) }).first else { return nil }
        guard let openingBrace = source[declaration.lowerBound...].firstIndex(of: "{") else { return nil }
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
}
