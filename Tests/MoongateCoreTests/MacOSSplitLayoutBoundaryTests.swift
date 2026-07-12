import XCTest

/// SplitLayoutView（备忘录式三栏原型）此前 440 行零测试守护。补一个源码扫描 boundary 测试，
/// 与其它 MacOS*BoundaryTests 同风格（App target 的 SwiftUI 视图无法 @testable import，只能扫源码），
/// 锁定原型的关键不变量，防静默回归。
final class MacOSSplitLayoutBoundaryTests: XCTestCase {

    /// 0.9 将资料库工作台作为默认入口，但仍保留可见的 legacy fallback。
    /// 这能让本地测试版直接覆盖新路径，同时在发现回归时不阻断既有下载工作流。
    func testLibraryWorkspaceIsDefaultWithLegacyFallback() throws {
        let content = try contentViewSource()
        XCTAssertTrue(content.contains("@AppStorage(\"libraryWorkspace.enabled\")"),
                      "资料库工作台必须由可回退的 feature flag 控制")
        XCTAssertTrue(content.contains("private var useLibraryWorkspace = true"),
                      "0.9 本地测试版默认应打开资料库工作台")
        XCTAssertTrue(content.contains("if useLibraryWorkspace {"))
        XCTAssertTrue(content.contains("LibraryWorkspaceView(model: model, workspace: libraryWorkspace)"))
        XCTAssertTrue(content.contains("legacyBody"),
                      "legacy 界面必须保留为 else 分支回退")
        XCTAssertTrue(content.contains("@StateObject private var libraryWorkspace"),
                      "资料库协调器必须由根视图拥有，不能随 workspace/legacy 切换被销毁")
        XCTAssertTrue(content.contains("LibraryWorkspaceModel(model: model)"),
                      "根协调器必须订阅同一个实时队列")
    }

    /// onboarding、依赖检查、登录、设置窗口联动属于 App 根生命周期，不能绑在 legacyBody 上；
    /// 否则切到资料库工作台就会静默丢失这些入口。
    func testRootLifecycleModifiersApplyToBothLayouts() throws {
        let content = try contentViewSource()
        let legacy = try XCTUnwrap(functionBody(named: "legacyBody", in: content))

        for marker in [
            "model.onAppear()",
            "NSApplication.didBecomeActiveNotification",
            "openWindow(id: \"settings\")",
            ".sheet(isPresented: $model.showOnboarding)",
            ".sheet(isPresented: $model.showDependencySetup)",
            ".sheet(isPresented: loginSheetBinding)"
        ] {
            XCTAssertTrue(content.contains(marker), "根视图应保留 \(marker) 生命周期入口")
            XCTAssertFalse(legacy.contains(marker), "legacyBody 不应独占 \(marker)")
        }
    }

    func testLibraryCoordinatorPersistsNewQueueItemsWithoutAProgressDebounce() throws {
        let source = try libraryWorkspaceModelSource()
        let receive = try XCTUnwrap(functionBody(named: "receiveQueue", in: source))
        let schedule = try XCTUnwrap(functionBody(named: "scheduleQueueSynchronization", in: source))

        XCTAssertTrue(receive.contains("guard bootstrapFinished else { return }"),
                      "初始 Queue publisher 事件必须等资料库 load 完成再写入，避免与持久化读取竞争")
        XCTAssertTrue(schedule.contains("hasUnpersistedItem"),
                      "新任务必须区别于普通进度刷新")
        XCTAssertTrue(schedule.contains("if !hasUnpersistedItem"),
                      "新任务不应等待 300ms 进度防抖才建立稳定资料记录")
    }

    func testWorkspaceInspectorNeverAutoOpensForAWindowBreakpoint() throws {
        let source = try libraryWorkspaceModelSource()
        let layout = try XCTUnwrap(functionBody(named: "updateLayout", in: source))

        XCTAssertTrue(source.contains("@Published var showInspector = false"))
        XCTAssertFalse(layout.contains("showInspector ="),
                       "资料库首次打开时，Inspector 只能由用户主动打开")
    }

    func testWideResizeDoesNotUndoAnExplicitSidebarChoice() throws {
        let source = try libraryWorkspaceViewSource()
        let layout = try XCTUnwrap(functionBody(named: "applyResponsiveLayout", in: source))

        XCTAssertTrue(layout.contains("if width < 1_100"))
        XCTAssertFalse(layout.contains("columnVisibility = .all"),
                       "窗口重新变宽不能强制恢复人们刚刚隐藏的侧栏。")
    }

    /// 0.9.2 removes the hand-built fourth column. The inspector belongs to
    /// the split view itself and is initially closed until a person asks for
    /// it; window resizing must not unexpectedly reveal it.
    func testDownloadFirstWorkspaceUsesSystemInspectorWithoutAutoOpeningIt() throws {
        let view = try libraryWorkspaceViewSource()
        let model = try libraryWorkspaceModelSource()
        let detail = try XCTUnwrap(slice(
            view,
            from: "private struct LibraryWorkbenchDetail",
            to: "private struct PlayerStageView"
        ))
        let layout = try XCTUnwrap(functionBody(named: "updateLayout", in: model))

        XCTAssertTrue(view.contains(".inspector(isPresented: $workspace.showInspector)"),
                      "信息栏必须由 SwiftUI 系统 Inspector 承载，不能再作为 detail 内的伪第四列")
        XCTAssertTrue(model.contains("@Published var showInspector = false"),
                      "资料库首次打开应先让用户选择内容，不应自动弹出信息栏")
        XCTAssertFalse(detail.contains("LibraryInspector("),
                       "工作台 detail 不得手写嵌入 Inspector")
        XCTAssertFalse(layout.contains("showInspector ="),
                       "窗口宽度变化不能自动改变用户明确的 Inspector 状态")
    }

    func testLibraryListUsesOneNativeTitleAndOwnsMiddleColumnToolbarActions() throws {
        let source = try libraryWorkspaceViewSource()
        let list = try XCTUnwrap(functionBody(named: "libraryList", in: source))

        XCTAssertTrue(list.contains(".navigationTitle(listTitle)"))
        XCTAssertFalse(list.contains("Text(listTitle)"),
                       "中栏标题只能由原生 navigation title 呈现，不能重复手写一个“全部视频”")
        XCTAssertTrue(list.contains("ToolbarItemGroup(placement: .primaryAction)"),
                      "新建下载和开始全部应归属中栏原生 toolbar")
        XCTAssertTrue(list.contains("Label(\"新建下载\", systemImage: \"plus\")"))
        XCTAssertTrue(list.contains("if workspace.hasQueuedTasks"),
                      "开始全部只在确有待开始任务时出现")
    }

    func testInspectorMenuUsesSystemCommandsRatherThanASecondNotificationBridge() throws {
        let app = try appSource()
        let workspace = try libraryWorkspaceViewSource()

        XCTAssertTrue(app.contains("InspectorCommands()"),
                      "系统 InspectorCommands 必须提供 Control-Command-I 菜单栏等价入口")
        XCTAssertFalse(app.contains("AppWorkspaceCommand.inspectorToggleRequested"),
                       "不能再维护一条与系统 Inspector 重复的自定义菜单命令")
        XCTAssertFalse(workspace.contains("AppWorkspaceCommand.inspectorToggleRequested"),
                       "工作台应由系统 Inspector 状态控制，而不是 Notification 桥")
    }

    func testQueuedAndCompletedProcessingOpenContextualSheetsInsteadOfInspectorTabs() throws {
        let view = try libraryWorkspaceViewSource()
        let model = try libraryWorkspaceModelSource()
        let inspector = try XCTUnwrap(slice(
            view,
            from: "private struct LibraryInspector",
            to: "private struct InspectorKeyValueRow"
        ))

        XCTAssertTrue(model.contains("enum ProcessingSheet"))
        XCTAssertTrue(view.contains("ProcessingOptionsSheet"))
        XCTAssertTrue(view.contains("更改选项…"))
        XCTAssertTrue(view.contains("重新处理…"))
        XCTAssertFalse(inspector.contains("Picker(\"检查器\""),
                       "信息栏不得再混入“信息 / 处理”分段和完整配置表单")
        XCTAssertFalse(inspector.contains("TranscriptionModelPicker"),
                       "模型选择只应在按需打开的高级 Sheet 中出现")
    }

    func testProgressOverlaysDoNotResortTheLibraryOnEveryQueueTick() throws {
        let model = try libraryWorkspaceModelSource()
        let receive = try XCTUnwrap(functionBody(named: "receiveQueue", in: model))
        let rebuild = try XCTUnwrap(functionBody(named: "rebuildProjectionCache", in: model))
        let synchronize = try XCTUnwrap(functionBody(named: "synchronizeQueue", in: model))

        XCTAssertTrue(receive.contains("scheduleLiveOverlayRefresh"),
                      "高频队列状态必须先进入节流后的活动覆盖层")
        XCTAssertFalse(receive.contains("rebuildProjectionCache()"),
                       "进度 tick 不能直接触发整库筛选排序")
        XCTAssertTrue(rebuild.contains("liveProcessing: [:]"),
                      "稳定列表投影不应因实时覆盖层变化而重排")
        XCTAssertTrue(synchronize.contains("if stored != original"),
                      "无结构变化的进度同步不能重新赋值资料库并触发列表重建")
    }

    func testProgressTicksReuseArtifactMetadataUntilTheQueueStructureChanges() throws {
        let model = try libraryWorkspaceModelSource()
        let snapshot = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources/Moongate/LibraryWorkspaceModel.swift"))

        XCTAssertTrue(model.contains("artifactSnapshotCache"))
        XCTAssertTrue(model.contains("artifactsForQueueItem"))
        XCTAssertTrue(model.contains("QueueLibrarySnapshot($0, artifacts: artifactsForQueueItem($0))"),
                      "进度 tick 应复用产物 metadata，而不是重复读取每个文件的大小和修改时间。")
        XCTAssertTrue(snapshot.contains("init(_ item: QueueManager.QueueItem, artifacts:"))
    }

    func testCancelledQueueSyncCannotWriteAnOlderSnapshotAfterNewerProgressArrives() throws {
        let model = try libraryWorkspaceModelSource()
        let schedule = try XCTUnwrap(functionBody(named: "scheduleQueueSynchronization", in: model))
        let synchronize = try XCTUnwrap(functionBody(named: "synchronizeQueue", in: model))

        XCTAssertTrue(model.contains("private var queueSyncGeneration = 0"))
        XCTAssertTrue(schedule.contains("queueSyncGeneration &+= 1"))
        XCTAssertTrue(model.contains("generation == queueSyncGeneration"),
                      "被更新快照取代的同步不能在异步存储后回写旧状态。")
        XCTAssertTrue(synchronize.contains("isCurrentQueueSync(generation)"))
    }

    func testWorkspaceDoesNotAutoSelectTheFirstLibraryItem() throws {
        let model = try libraryWorkspaceModelSource()
        let bootstrap = try XCTUnwrap(functionBody(named: "bootstrap", in: model))
        let remove = try XCTUnwrap(functionBody(named: "removeFromLibrary", in: model))

        XCTAssertTrue(model.contains("restoreExplicitSelectionIfAvailable"),
                      "只应恢复用户曾明确选择的项目")
        XCTAssertFalse(model.contains("projectedItems.first?.id"),
                       "首次进入、筛选或删除后不得擅自选中第一条视频")
        XCTAssertFalse(bootstrap.contains("selectedItemID ="),
                       "初次资料库加载必须保持空选择状态")
        XCTAssertTrue(remove.contains("self.selectedItemID = nil"),
                      "移除当前选中项后应回到明确空态，而不是跳到另一条视频")
    }

    func testChangingFilterOrSearchClearsASelectionThatIsNoLongerVisible() throws {
        let model = try libraryWorkspaceModelSource()
        let sidebar = try XCTUnwrap(slice(
            model,
            from: "@Published var sidebarDestination",
            to: "@Published var selectedItemID"
        ))
        let search = try XCTUnwrap(slice(
            model,
            from: "@Published var searchText",
            to: "@Published var showInspector"
        ))

        XCTAssertTrue(sidebar.contains("clearSelectionIfHiddenByProjection()"))
        XCTAssertTrue(search.contains("clearSelectionIfHiddenByProjection()"))
        XCTAssertTrue(model.contains("private func clearSelectionIfHiddenByProjection()"))
        XCTAssertFalse(model.contains("selectedItemID = projectedItems.first?.id"),
                       "筛选变化后应清空不可见选择，不能又自动选中第一条。")
    }

    func testQueuedReadinessCopyNeverEchoesRawQueueDiagnostics() throws {
        let source = try libraryWorkspaceViewSource()
        let display = try XCTUnwrap(slice(
            source,
            from: "private enum LibraryDisplay",
            to: "static func completedDetail"
        ))

        XCTAssertTrue(display.contains("本地字幕识别尚未准备好"))
        XCTAssertTrue(display.contains("开始前需要处理一项设置"))
        XCTAssertFalse(display.contains("return detail"),
                       "普通资料库路径不得直接展示 QueueManager 的技术诊断原文")
    }

    func testWorkspaceToolbarKeepsOnlyInspectorAndListOwnsNewDownload() throws {
        let source = try libraryWorkspaceViewSource()
        let toolbar = try XCTUnwrap(functionBody(named: "workspaceToolbar", in: source))
        let list = try XCTUnwrap(functionBody(named: "libraryList", in: source))

        XCTAssertTrue(toolbar.contains("systemImage: \"sidebar.right\""),
                      "右上角只保留可发现的 Inspector 开关")
        XCTAssertFalse(toolbar.contains("systemImage: \"plus\""),
                       "新建下载不应继续挤在右侧工具栏")
        XCTAssertFalse(toolbar.contains("systemImage: \"sidebar.left\""),
                       "NavigationSplitView 已提供系统侧栏控制，不能再在右侧复制一个")
        XCTAssertTrue(list.contains("Label(\"新建下载\", systemImage: \"plus\")"),
                      "新建下载应属于当前资料列表的标题区")
        XCTAssertTrue(list.contains("AppWorkspaceCommand.newDownloadRequested"),
                      "列表标题区的新增动作必须接入同一真实 Sheet 命令")
    }

    func testStartAllToolbarActionHasAMenuBarEquivalent() throws {
        let app = try appSource()
        let workspace = try libraryWorkspaceViewSource()
        let commands = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources/Moongate/AppRootHost.swift"))

        XCTAssertTrue(commands.contains("startAllRequested"))
        XCTAssertTrue(app.contains("AppWorkspaceCommand.startAllRequested"))
        XCTAssertTrue(app.contains("Button(\"开始全部\")"))
        XCTAssertTrue(workspace.contains("AppWorkspaceCommand.startAllRequested"))
        XCTAssertTrue(workspace.contains("workspace.startAllQueuedTasks()"))
    }

    func testWorkspaceToolbarUsesSystemInspectorMenuEquivalent() throws {
        let app = try appSource()
        let workspace = try libraryWorkspaceViewSource()

        XCTAssertTrue(app.contains("InspectorCommands()"),
                      "Inspector toolbar action 必须由系统菜单提供等价入口")
        XCTAssertTrue(workspace.contains(".inspector(isPresented: $workspace.showInspector)"))
    }

    func testMovingFilesToTrashDoesNotOfferIndexOnlyUndo() throws {
        let source = try libraryWorkspaceModelSource()
        let trash = try XCTUnwrap(functionBody(named: "moveArtifactsToTrash", in: source))

        XCTAssertFalse(trash.contains("removeFromLibrary()"),
                       "移到废纸篓后不能走只恢复索引的撤销路径")
        XCTAssertTrue(trash.contains("removedItemForUndo = nil"))
        XCTAssertTrue(trash.contains("undoRemovalAvailable = false"))
        XCTAssertTrue(trash.contains("store.remove(itemID: item.id)"),
                      "文件已入废纸篓后仍需移除持久资料库索引")
    }

    func testIndexRemovalSuppressesResidentQueueItemUntilUndo() throws {
        let source = try libraryWorkspaceModelSource()
        let remove = try XCTUnwrap(functionBody(named: "removeFromLibrary", in: source))
        let undo = try XCTUnwrap(functionBody(named: "undoRemoveFromLibrary", in: source))
        let synchronize = try XCTUnwrap(functionBody(named: "synchronizeQueue", in: source))

        XCTAssertTrue(remove.contains("suppressedQueueLibraryItemIDs.insert(targetItemID)"),
                      "索引移除后，尚在内存的 QueueItem 不能在下一次同步时复活记录")
        XCTAssertTrue(undo.contains("suppressedQueueLibraryItemIDs.remove(removedItemForUndo.id)"),
                      "撤销必须重新允许该资料库记录接收实时队列投影")
        XCTAssertTrue(synchronize.contains("let visibleSnapshots = snapshots.filter"))
        XCTAssertTrue(synchronize.contains("!suppressedQueueLibraryItemIDs.contains($0.libraryItemID)"))
    }

    func testProcessingSheetProgressivelyDisclosesAdvancedSubtitleSourceChoices() throws {
        let source = try libraryWorkspaceViewSource()
        let sheet = try XCTUnwrap(slice(
            source,
            from: "private struct ProcessingOptionsSheet",
            to: "private struct FlowLayout"
        ))

        XCTAssertTrue(sheet.contains("DisclosureGroup(\"高级选项\")"),
                      "底层字幕来源只能在用户主动展开高级选项后出现")
        for kind in ["importedFile", "manual", "platformAuto", "hlsManifest", "localASR", "cloudASR"] {
            XCTAssertTrue(sheet.contains("SubtitleSourceKind.\(kind).rawValue"))
        }
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

    func testCancellingTaskStaysVisibleButDoesNotOfferConflictingControls() throws {
        let legacy = try queueItemViewSource()
        let split = try splitLayoutSource()
        let workspace = try libraryWorkspaceViewSource()

        XCTAssertTrue(legacy.contains("case .cancelling:"),
                      "legacy 队列必须给可见的 cancelling 状态专门文案")
        XCTAssertTrue(split.contains("case .queued, .cancelling, .downloading, .translating, .burning:"),
                      "取消收敛中仍属于进行中，不能提前移入已完成分组")
        let controls = try XCTUnwrap(functionBody(named: "buttons", in: legacy))
        XCTAssertTrue(controls.contains("case .cancelling:"),
                      "取消收敛中不能复用暂停/重试控制，避免相互竞争")
        XCTAssertTrue(workspace.contains("WorkbenchActionStrip"),
                      "收起 Inspector 后必须仍有状态化快捷操作")
        XCTAssertTrue(workspace.contains("workspace.startSelectedQueuedTask()"),
                      "待开始任务必须提供真实开始入口")
    }

    func testLibraryRowsProvideStateAwareContextMenuAndSafeDeletion() throws {
        let source = try libraryWorkspaceViewSource()

        XCTAssertTrue(source.contains(".contextMenu"),
                      "列表行应提供 macOS 原生右键菜单")
        for label in ["播放", "在访达中显示", "复制来源链接", "重新处理", "移出资料库", "移到废纸篓…"] {
            XCTAssertTrue(source.contains(label), "右键菜单缺少 \(label) 操作")
        }
        XCTAssertTrue(source.contains("LibraryRowContextMenu"),
                      "右键操作应从列表行抽成可审查的独立组件")
        XCTAssertTrue(source.contains("case .queued:") && source.contains("Button(\"开始\")"),
                      "待开始任务在右键菜单中必须显示“开始”，不能被误称为恢复")
    }

    func testLibraryContextActionsTargetTheirOwnItemAndKeepTrashSeparate() throws {
        let source = try libraryWorkspaceModelSource()

        XCTAssertTrue(source.contains("func removeFromLibrary(itemID:"),
                      "右键移出资料库必须能针对被点中的项目，而非依赖当前选中行")
        XCTAssertTrue(source.contains("func moveArtifactsToTrash(itemID:"),
                      "右键废纸篓操作必须能针对被点中的项目")
        XCTAssertTrue(source.contains("func revealInFinder(itemID:"),
                      "右键在访达中显示必须能针对被点中的项目")
        XCTAssertTrue(source.contains("func canRevealInFinder(itemID:"),
                      "没有本地产物的记录不应提供一个必然失败的访达动作")
    }

    func testWorkspacePolishAvoidsMisleadingEmptyCopyAndPrefersVideoInFinder() throws {
        let view = try libraryWorkspaceViewSource()
        let model = try libraryWorkspaceModelSource()

        XCTAssertTrue(view.contains("点列表标题中的＋添加链接。"))
        XCTAssertFalse(view.contains("点右上角“新建下载”添加链接。"))
        XCTAssertTrue(model.contains("$0.role == .video || $0.role == .renderedVideo"))
    }

    func testLibraryRowsUseSpecificRecoveryTextWithoutGreenSuccessBadge() throws {
        let source = try libraryWorkspaceViewSource()

        XCTAssertTrue(source.contains("LibraryDisplay.recoveryLabel("),
                      "异常项目应优先显示具体恢复原因，而不是笼统的“需要登录或处理”")
        XCTAssertTrue(source.contains("LibraryDisplay.completedDetail(projected.item)"),
                      "完成项的第三行应显示保存结果，不能重复“已完成”")
        XCTAssertFalse(source.contains("Image(systemName: \"checkmark.circle.fill\").foregroundStyle(.green)"),
                      "完成项不应再额外显示绿色成功徽章")
    }

    func testPausedRunningTaskKeepsItsProcessingSnapshotReadOnly() throws {
        let model = try libraryWorkspaceModelSource()
        let view = try libraryWorkspaceViewSource()

        XCTAssertFalse(model.contains("if item.isPaused {\n            state = .queued"),
                       "暂停只是运行任务的覆盖状态，不能把它重新投影成可编辑的待开始任务")
        XCTAssertTrue(view.contains("processing.state.isRunning"),
                      "Inspector 必须继续以运行态锁定暂停任务的处理快照")
    }

    func testQueuedProcessingSheetEditsItsOwnConfigurationWithoutCreatingAVersion() throws {
        let source = try libraryWorkspaceViewSource()
        XCTAssertTrue(source.contains("ProcessingOptionsSheet"))
        XCTAssertTrue(source.contains("workspace.showQueuedOptions"))
    }

    func testProcessingSheetCarriesSubtitleOutcomeThroughQueuedAndReprocessFlows() throws {
        let view = try libraryWorkspaceViewSource()
        let model = try libraryWorkspaceModelSource()

        XCTAssertTrue(view.contains("Picker(\"字幕结果\""))
        XCTAssertTrue(model.contains("changes.insert(.subtitleMode)"))
        XCTAssertTrue(model.contains("previousConfiguration: version.processing.configuration"))
    }

    func testReprocessSheetKeepsContextUntilAsyncCreationSucceeds() throws {
        let view = try libraryWorkspaceViewSource()
        let model = try libraryWorkspaceModelSource()
        let sheet = try XCTUnwrap(slice(
            view,
            from: "private struct ProcessingOptionsSheet",
            to: "private struct FlowLayout"
        ))

        XCTAssertTrue(model.contains("func createReprocessTask() async -> ReprocessCreationResult"))
        XCTAssertTrue(sheet.contains("await workspace.createReprocessTask()"),
                      "重新处理必须等待真实入队结果，而不是立即关闭 Sheet。")
        XCTAssertTrue(sheet.contains("case .success"))
        XCTAssertTrue(sheet.contains("case .failure(let message)"))
        XCTAssertTrue(sheet.contains("Button(isQueued ? \"完成\" : \"取消\")"))
        XCTAssertTrue(sheet.contains("workspace.discardProcessingDraft()"),
                      "取消重处理应放弃未应用的草稿，而不是把隐形修改留给下次打开。")
    }

    func testLocalReprocessDoesNotRequireASourceButRefreshDoes() throws {
        let view = try libraryWorkspaceViewSource()
        let model = try libraryWorkspaceModelSource()

        XCTAssertTrue(model.contains("func reprocessBlockerReason"))
        XCTAssertTrue(model.contains("plan.steps.contains(.refreshVideo)"))
        XCTAssertTrue(model.contains("source.supportsRestart"))
        XCTAssertTrue(view.contains("workspace.canCreateReprocess"))
        XCTAssertFalse(view.contains("if item.source != nil {\n                        Button(\"创建重新处理任务\")"))
    }

    func testFailedTaskKeepsRecoveryActionsVisibleWithOrWithoutInspector() throws {
        let source = try libraryWorkspaceViewSource()

        XCTAssertTrue(source.contains("case .failed:"),
                      "失败任务应在统一动作条中保持恢复入口")
        XCTAssertTrue(source.contains("workspace.recoverQueueTask(for: item.id)"),
                      "失败任务必须复用同一条登录或重试恢复动作")
    }

    func testBlockedQueuedTasksExposeSpecificWarningAndRealRecoveryActions() throws {
        let view = try libraryWorkspaceViewSource()
        let model = try libraryWorkspaceModelSource()

        XCTAssertTrue(view.contains("LibraryDisplay.queuedReadinessDetail(details)"),
                      "待开始预检失败时，列表第三行必须优先显示具体的可恢复原因")
        XCTAssertTrue(view.contains("需要处理，\\(readiness)"),
                      "VoiceOver 必须读出待开始任务的具体阻塞原因，而不是笼统的等待中")
        XCTAssertTrue(view.contains("workspace.openQueuedReadinessRecovery"),
                      "待开始的本地/云端预检失败必须提供真实恢复入口")
        XCTAssertTrue(model.contains("enum QueuedReadinessRecovery"))
        XCTAssertTrue(model.contains("case .localSpeech: \"subtitlesLanguage\""),
                      "本地模型缺失应直达真实的字幕与语言设置")
        XCTAssertTrue(model.contains("case .cloudASR: \"servicesAccounts\""),
                      "云端 ASR 缺失应直达真实的服务与账户设置")
        XCTAssertTrue(model.contains("appModel.openSettings(paneID: recovery.settingsPaneID)"))
    }

    func testQueuedContextMenuUsesConfigurationLanguageAndFinderNeedsAnArtifact() throws {
        let source = try libraryWorkspaceViewSource()
        let contextMenu = try XCTUnwrap(slice(
            source,
            from: "private struct LibraryRowContextMenu",
            to: "private struct LibraryStatusGlyph"
        ))

        XCTAssertTrue(source.contains("Button(\"更改选项…\")"),
                      "待开始任务应使用“更改选项”，不能误称为“重新处理”")
        XCTAssertTrue(source.contains("if processing?.state.isQueued == true"),
                      "普通重新处理不应与待开始任务的配置动作并存")
        XCTAssertTrue(contextMenu.contains("if let recovery = workspace.queuedReadinessRecovery(for: item.id)"),
                      "预检阻塞时，右键菜单应改给恢复入口而不是继续提供无效的开始动作")
        XCTAssertTrue(contextMenu.contains("} else {\n                        Button(\"开始\")"),
                      "仅无阻塞的待开始任务才显示开始动作")
        XCTAssertTrue(source.contains("if workspace.canRevealInFinder(itemID: item.id)"),
                      "没有本地产物的完成或异常项不应显示必然失败的访达按钮")
    }

    func testTrashConfirmationClearsItsTargetAndRequiresAnExistingFile() throws {
        let view = try libraryWorkspaceViewSource()
        let model = try libraryWorkspaceModelSource()

        XCTAssertTrue(view.contains("let itemID = trashItemID"))
        XCTAssertTrue(view.contains("trashItemID = nil"))
        XCTAssertTrue(model.contains("let existingURLs = urls.filter"))
        XCTAssertTrue(model.contains("guard !existingURLs.isEmpty"))
    }

    func testActiveTasksCannotTrashArtifactsStillUsedByThePipeline() throws {
        let view = try libraryWorkspaceViewSource()
        let model = try libraryWorkspaceModelSource()
        let contextMenu = try XCTUnwrap(slice(
            view,
            from: "private struct LibraryRowContextMenu",
            to: "private struct LibraryStatusGlyph"
        ))
        let moveToTrash = try XCTUnwrap(functionBody(named: "moveArtifactsToTrash", in: model))

        XCTAssertTrue(contextMenu.contains("if processing?.state.isActive != true"),
                      "运行或待开始的任务不应提供会移走仍在使用产物的废纸篓操作")
        XCTAssertTrue(moveToTrash.contains("guard processing(for: item.id)?.state.isActive != true"),
                      "即使从其他 UI 路径调用，模型层也必须拒绝活动任务的废纸篓操作")
    }

    func testActiveRowsExposeProgressAndEtaToVoiceOver() throws {
        let source = try libraryWorkspaceViewSource()

        XCTAssertTrue(source.contains("activeAccessibilityValue"))
        XCTAssertTrue(source.contains("LibraryDisplay.liveDetail(details)"),
                      "活跃任务的 VoiceOver 值必须包含 ETA 或估算状态")
    }

    func testInterruptedLibraryItemsExposeARealRestartAction() throws {
        let model = try libraryWorkspaceModelSource()

        XCTAssertTrue(model.contains("case .restart: \"重新开始\""))
        XCTAssertTrue(model.contains("func restartInterruptedTask"))
        XCTAssertTrue(model.contains("restartInterruptedLibraryItem"))
    }

    func testWorkspaceShowsRestartAndBatchFeedbackOutsideTheDownloadSheet() throws {
        let source = try libraryWorkspaceViewSource()

        XCTAssertTrue(source.contains("LibraryEnqueueNoticeBar"))
        XCTAssertTrue(source.contains("model.enqueueNotice"))
    }

    func testPlayerDistinguishesMissingFilesFromUnsupportedFormatsAndStopsOnTeardown() throws {
        let source = try libraryWorkspaceViewSource()

        XCTAssertTrue(source.contains("missingVideoStage"),
                      "文件已移动时必须给明确恢复态，不能误报格式不支持")
        XCTAssertTrue(source.contains("视频文件已移动或删除"),
                      "缺失文件状态应使用可行动的中文文案")
        XCTAssertTrue(source.contains("func dismantleNSView"),
                      "离开详情时系统播放器必须停止，避免后台继续播放")
        XCTAssertTrue(source.contains("workspace.consumePlaybackRequest"),
                      "右键播放请求只能消费一次，不能在再次选中同一项目时意外自动播放")
        XCTAssertTrue(source.contains("handledPlaybackRequestID"),
                      "系统播放器必须按请求 nonce 去重，而不是按所选视频去重")
        XCTAssertTrue(source.contains("onPlaybackRequestHandled"),
                      "播放器实际开始后必须回调清除一次性播放请求")
    }

    func testIndexRemovalUndoLivesAboveTheSelectedDetail() throws {
        let source = try libraryWorkspaceViewSource()

        XCTAssertTrue(source.contains("LibraryRemovalUndoBar"),
                      "移出最后一个项目后，撤销入口仍应留在工作台根部")
        XCTAssertTrue(source.contains("workspace.undoRemoveFromLibrary()"),
                      "根级撤销条必须接入真实恢复动作")
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

    /// playableVideo（播放叠层资格）必须复用 QueueManager.videoExtensions 单一来源，
    /// 与 canRetryWithLocalASR 的资格判定同集合。此前它内联了一份重复的扩展名字面量集合——
    /// 若 QM 的集合新增扩展名，两处会对同一文件给出不一致判断（可重识别但无播放叠层）。
    func testPlayableVideoReusesQueueManagerExtensionSet() throws {
        let source = try splitLayoutSource()
        XCTAssertTrue(source.contains("QueueManager.videoExtensions.contains("),
                      "playableVideo 应复用 QueueManager.videoExtensions，而非内联副本")
        XCTAssertFalse(source.contains("[\"mp4\", \"mov\", \"mkv\""),
                       "不应再内联视频扩展名字面量集合（已收敛到 QueueManager.videoExtensions 单一来源）")
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
        // 打开 sheet 时链接输入框应自动获得焦点，键盘用户无需先 Tab（与主界面 URL 输入框一致）。
        XCTAssertTrue(source.contains(".focused($addFieldFocused)") && source.contains("addFieldFocused = true"),
                      "添加 sheet 应把初始焦点落到输入框（@FocusState + focused + onAppear）。")
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

    /// 状态文案一致性：三栏的 QueueStatusFormatter 是 legacy QueueItemView.statusText 的等价重写
    /// （legacy 的是 private 无法复用）。两份手维护副本有漂移风险——给 legacy 加了 stage/phase 文案却
    /// 忘了同步 formatter，三栏用户就会看到过时状态。守护两处引用完全相同的 L.Queue.* 状态 key 集合，
    /// 任一处新增/删除 key 未同步即失败。
    func testStatusFormatterKeySetMatchesLegacyStatusText() throws {
        let formatter = try splitLayoutSource()
        let legacy = try queueItemViewSource()
        // formatter 的状态文案实现区（statusText/localASRProgressText/postDownloadProcessingText/remainingText/approximateDurationText）。
        let formatterKeys = queueStatusKeys(in: try XCTUnwrap(
            slice(formatter, from: "private func statusText(compact: Bool)", to: "// MARK: - Sidebar 行")))
        // legacy 的对应实现区（statusText 到 approximateDurationText，止于其后的 isFailed）。
        let legacyKeys = queueStatusKeys(in: try XCTUnwrap(
            slice(legacy, from: "private var statusText: String", to: "private var isFailed: Bool")))
        XCTAssertFalse(formatterKeys.isEmpty, "应能从 formatter 区解析出 L.Queue.* 状态 key")
        XCTAssertEqual(formatterKeys, legacyKeys,
                       "三栏 QueueStatusFormatter 与 legacy statusText 引用的 L.Queue.* 状态 key 集合必须一致；" +
                       "差异=\(formatterKeys.symmetricDifference(legacyKeys).sorted())")
    }

    /// 可访问性：装饰性图标 hidden、行/详情合并为可读元素、播放/添加按钮有 label。
    func testSplitLayoutAccessibility() throws {
        let source = try splitLayoutSource()
        XCTAssertTrue(source.contains(".accessibilityHidden(true)"), "装饰图标应对 VoiceOver 隐藏")
        XCTAssertTrue(source.contains(".accessibilityElement(children: .combine)"))
        XCTAssertTrue(source.contains(".accessibilityLabel(localizer.t(L.SplitLayout.play))"))
    }

    // MARK: - helpers（与其它 boundary 测试同款）

    private func queueItemViewSource() throws -> String {
        try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources").appendingPathComponent("Moongate")
            .appendingPathComponent("QueueItemView.swift"))
    }

    /// 从 source 截取 [from, to) 之间的片段（找不到边界返回 nil）。
    private func slice(_ source: String, from: String, to: String) -> String? {
        guard let start = source.range(of: from) else { return nil }
        let tail = source[start.lowerBound...]
        guard let end = tail.range(of: to) else { return String(tail) }
        return String(source[start.lowerBound..<end.lowerBound])
    }

    /// 解析片段里所有 L.Queue.<key> 引用，去重成集合。
    private func queueStatusKeys(in fragment: String) -> Set<String> {
        var keys = Set<String>()
        var search = fragment.startIndex
        let marker = "L.Queue."
        while let range = fragment.range(of: marker, range: search..<fragment.endIndex) {
            var cursor = range.upperBound
            var name = ""
            while cursor < fragment.endIndex, fragment[cursor].isLetter || fragment[cursor].isNumber {
                name.append(fragment[cursor])
                cursor = fragment.index(after: cursor)
            }
            if !name.isEmpty { keys.insert(name) }
            search = cursor
        }
        return keys
    }


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

    private func appSource() throws -> String {
        try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources").appendingPathComponent("Moongate")
            .appendingPathComponent("App.swift"))
    }

    private func libraryWorkspaceModelSource() throws -> String {
        try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources").appendingPathComponent("Moongate")
            .appendingPathComponent("LibraryWorkspaceModel.swift"))
    }

    private func libraryWorkspaceViewSource() throws -> String {
        try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources").appendingPathComponent("Moongate")
            .appendingPathComponent("LibraryWorkspaceView.swift"))
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
