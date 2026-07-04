import AppKit
import SwiftUI
#if canImport(MoongateCore)
import MoongateCore
#endif

/// 实验性「备忘录式三栏布局」原型（feature flag `experimental.splitLayout` 默认关闭）。
///
/// 用 `NavigationSplitView` 呈现：左侧视频列表（缩略图 + 标题 + 状态 + 进度环），
/// 右侧详情（大预览框 + 元信息 + 一排功能按钮）。所有数据与操作复用现有
/// `QueueManager`（`model.queue`），不新增任何业务逻辑；进度环复用
/// `QueueOverlayView.swift` 里的 `ProgressRingView`。
///
/// 本轮仅为可运行原型：sidebar 的「添加」入口是占位（提示去主界面粘贴链接），
/// 后续可接 Parabolic 式的粘贴/添加对话框；detail 与 sidebar 的状态文案通过
/// `QueueStatusFormatter` 复用 `QueueItemView` 等价的丰富逻辑（下载 百分比·速度·剩余、
/// 本地 ASR 三子阶段、翻译/烧录/转码%、部分成功、失败原因等），detail 并显示进度条。
/// 预览播放与 pause/resume/cancel/retry/remove/reveal 等按钮操作均为真实可用。
struct SplitLayoutView: View {
    @ObservedObject var model: ViewModel
    @ObservedObject private var queue: QueueManager
    @State private var selectedItemID: UUID?
    @State private var showAddSheet = false
    @State private var addURLText = ""
    @EnvironmentObject private var localizer: Localizer

    init(model: ViewModel) {
        self.model = model
        self._queue = ObservedObject(wrappedValue: model.queue)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            detail
        }
        .onAppear {
            // 默认选中第一项，避免右侧空白。
            if selectedItemID == nil {
                selectedItemID = queue.items.first?.id
            }
        }
        .onChange(of: queue.items.map(\.id)) { _, ids in
            // 选中项被移除后回退到第一项；首个任务入队时自动选中。
            if let selected = selectedItemID, !ids.contains(selected) {
                selectedItemID = ids.first
            } else if selectedItemID == nil {
                selectedItemID = ids.first
            }
        }
    }

    // MARK: - Sidebar（左侧列表）

    /// 进行中分组：stage 为 queued/downloading/translating/burning（无论是否 paused），保持 items 原始相对顺序。
    private var activeItems: [QueueManager.QueueItem] {
        queue.items.filter { item in
            switch item.stage {
            case .queued, .downloading, .translating, .burning:
                return true
            case .done, .failed, .cancelled:
                return false
            }
        }
    }

    /// 已完成分组：stage 为 done/failed/cancelled，保持 items 原始相对顺序。
    private var finishedItems: [QueueManager.QueueItem] {
        queue.items.filter { item in
            switch item.stage {
            case .done, .failed, .cancelled:
                return true
            case .queued, .downloading, .translating, .burning:
                return false
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            addFeedbackBanner
            sidebarList
        }
        .navigationTitle(localizer.t(L.SplitLayout.sidebarTitle))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    // 打开轻量「添加下载」sheet：粘贴一或多个链接，确认后按默认设置自动入队。
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .help(localizer.t(L.SplitLayout.addTask))
                .accessibilityLabel(localizer.t(L.SplitLayout.addTask))
            }
        }
        .sheet(isPresented: $showAddSheet) {
            addTaskSheet
        }
    }

    /// 添加任务后的反馈条（sheet 关闭后仍可见）：解析中显示批量进度（batchStatusText），
    /// 结束显示添加/重复/失败摘要（enqueueNotice）。复用 legacy 已有的 @Published，三栏只是也展示——
    /// 否则用户在三栏粘贴无效链接/全部失败时毫无反馈（sheet 即时关闭、成功项才进 sidebar）。
    @ViewBuilder
    private var addFeedbackBanner: some View {
        if let status = model.batchStatusText {
            HStack(spacing: Spacing.sm) {
                ProgressView().controlSize(.small)
                Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .transition(.opacity)
        } else if let notice = model.enqueueNotice {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Text(notice).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var sidebarList: some View {
        Group {
            if queue.items.isEmpty {
                sidebarEmptyState
            } else {
                // 按任务状态分区（备忘录/邮件式）：进行中在上，已完成在下。
                // 分组仅重组渲染，不改动 queue.items 数据或任何操作；跨 Section 的选中态由 List(selection:) 统一维护。
                List(selection: $selectedItemID) {
                    if !activeItems.isEmpty {
                        Section("\(localizer.t(L.SplitLayout.sectionActive)) \(activeItems.count)") {
                            ForEach(activeItems) { item in
                                QueueSidebarRow(item: item)
                                    .tag(item.id)
                            }
                        }
                    }
                    if !finishedItems.isEmpty {
                        Section("\(localizer.t(L.SplitLayout.sectionFinished)) \(finishedItems.count)") {
                            ForEach(finishedItems) { item in
                                QueueSidebarRow(item: item)
                                    .tag(item.id)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    // MARK: - 添加任务 sheet（轻量粘贴入口，复用默认设置自动入队）

    /// 轻量「添加下载」对话框：多行输入一或多个链接，确认后调用 `model.addTasks(from:)`
    /// 按默认设置（最高画质、当前字幕模式）自动入队——复用批量自动入队引擎，不经 ready 配置页。
    /// 新任务通过 `queue.items` 实时出现在左侧 sidebar「进行中」分组。取消/确认均清空输入并关闭。
    private var addTaskSheet: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text(localizer.t(L.SplitLayout.addTaskSheetTitle))
                .font(.headline)

            TextField(
                localizer.t(L.SplitLayout.addSheetPlaceholder),
                text: $addURLText,
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(1...5)

            Text(localizer.t(L.SplitLayout.addSheetHint))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: Spacing.md) {
                Spacer(minLength: 0)
                Button(localizer.t(L.Common.cancel)) {
                    addURLText = ""
                    showAddSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button(localizer.t(L.SplitLayout.addSheetConfirm)) {
                    model.addTasks(from: addURLText)
                    addURLText = ""
                    showAddSheet = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(addURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 460)
    }

    private var sidebarEmptyState: some View {
        VStack(spacing: Spacing.emptyStack) {
            Image(systemName: "tray")
                .font(.system(size: 32, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(localizer.t(L.SplitLayout.emptyListTitle))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Detail（右侧详情）

    @ViewBuilder
    private var detail: some View {
        if let id = selectedItemID, let item = queue.items.first(where: { $0.id == id }) {
            QueueDetailView(item: item, queue: queue) { site, loginURL in
                model.openLoginForQueueItem(site: site, loginURL: loginURL)
            }
        } else {
            detailEmptyState
        }
    }

    private var detailEmptyState: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 44, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(localizer.t(L.SplitLayout.emptyDetailTitle))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Text(localizer.t(L.SplitLayout.emptyDetailSubtitle))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Spacing.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 状态文案格式化（与 QueueItemView 保持一致）

/// 把 `QueueItem` 的 stage + progressPhase + postDownloadProcessingKind + speed + remaining
/// 组装成与 `QueueItemView.statusText` 等价的丰富状态文案。QueueItemView 的对应计算属性是
/// private，无法直接复用，这里在原型内写等价实现，复用相同的 `item` 字段与 `L.Queue.*` 文案 key，
/// 保证用户在 legacy 列表与三栏原型看到的状态文案一致。
///
/// `compact` 为 true 时给 sidebar 行用（省略速度/剩余等次要细节，保持单行紧凑）。
@MainActor
private struct QueueStatusFormatter {
    let item: QueueManager.QueueItem
    let localizer: Localizer

    /// 详情用：完整文案（下载显示 百分比·速度·剩余；ASR 子阶段；转码/翻译/烧录%；done/部分成功；failed 原因）。
    var detailText: String { statusText(compact: false) }

    /// sidebar 用：紧凑文案（保留百分比与阶段，去掉速度/剩余，单行不溢出）。
    var compactText: String { statusText(compact: true) }

    private func statusText(compact: Bool) -> String {
        if item.isPaused { return localizer.t(L.Queue.paused) }
        switch item.stage {
        case .queued:
            return item.statusText ?? localizer.t(L.Queue.queuedEllipsis)
        case .downloading:
            // 下载 stage 内可能实际处于本地 ASR 各子阶段或下载后处理（转码）——与 QueueItemView 一致地优先判定。
            if let asr = localASRProgressText {
                return withDetails(asr, includeSpeed: false, compact: compact)
            }
            if item.isPostDownloadProcessing {
                return withDetails(postDownloadProcessingText, includeSpeed: false, compact: compact)
            }
            if let p = item.progress {
                return withDetails(localizer.t(L.Queue.downloadingPercent, Int(p * 100)), compact: compact)
            }
            return withDetails(localizer.t(L.Queue.downloading), compact: compact)
        case .translating:
            if let p = item.progress {
                return withDetails(localizer.t(L.Queue.translatingPercent, Int(p * 100)), includeSpeed: false, compact: compact)
            }
            return withDetails(localizer.t(L.Queue.translating), includeSpeed: false, compact: compact)
        case .burning:
            if let p = item.progress {
                return withDetails(localizer.t(L.Queue.burningPercent, Int(p * 100)), includeSpeed: false, compact: compact)
            }
            return withDetails(localizer.t(L.Queue.burning), includeSpeed: false, compact: compact)
        case .done:
            return item.statusText ?? localizer.t(L.Queue.done)
        case .cancelled:
            return item.statusText ?? localizer.t(L.Queue.cancelled)
        case .failed(let reason):
            return localizer.t(L.Queue.failedWithReason, reason)
        }
    }

    /// 本地 ASR 三子阶段（音频提取 / 语音识别 / 字幕分段），非这三个阶段返回 nil。
    private var localASRProgressText: String? {
        switch item.progressPhase {
        case .audioExtract:
            if let p = item.progress { return localizer.t(L.Queue.audioExtractingPercent, Int(p * 100)) }
            return localizer.t(L.Queue.audioExtracting)
        case .speechRecognition:
            if let p = item.progress { return localizer.t(L.Queue.speechRecognizingPercent, Int(p * 100)) }
            return localizer.t(L.Queue.speechRecognizing)
        case .subtitleSegment:
            if let p = item.progress { return localizer.t(L.Queue.subtitleSegmentingPercent, Int(p * 100)) }
            return localizer.t(L.Queue.subtitleSegmenting)
        default:
            return nil
        }
    }

    /// 下载后处理（转码等）文案。
    private var postDownloadProcessingText: String {
        switch item.postDownloadProcessingKind {
        case .transcoding:
            if let p = item.progress { return localizer.t(L.Queue.transcodingPercent, Int(p * 100)) }
            return localizer.t(L.Queue.transcoding)
        case .generic, nil:
            return (item.statusText ?? localizer.t(L.Queue.processing)) + "…"
        }
    }

    /// 用 " · " 拼接 基础文案·速度·剩余。compact（sidebar）模式省略速度与剩余，保持单行。
    private func withDetails(_ base: String, includeSpeed: Bool = true, compact: Bool) -> String {
        if compact { return base }
        var parts = [base]
        if includeSpeed, let speed = item.speedText, !speed.isEmpty {
            parts.append(speed)
        }
        if let remaining = remainingText {
            parts.append(remaining)
        }
        return parts.joined(separator: " · ")
    }

    /// 剩余时间文案：精确 mm:ss / 约 N 分钟 / 正在估算。与 QueueItemView 的实现一致。
    private var remainingText: String? {
        if let seconds = item.remainingSeconds {
            if item.remainingIsApproximate {
                return localizer.t(L.Queue.remainingApprox, approximateDurationText(seconds))
            }
            return localizer.t(L.Queue.remainingExact, clockDurationText(seconds))
        }
        if item.isEstimatingRemaining {
            return localizer.t(L.Queue.remainingEstimating)
        }
        return nil
    }

    private func clockDurationText(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    private func approximateDurationText(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        if total < 60 {
            return localizer.t(L.Queue.remainingLessThanMinute)
        }
        let minutes = Int(ceil(Double(total) / 60.0))
        if minutes < 60 {
            return localizer.t(L.Queue.remainingMinutes, minutes)
        }
        let hours = minutes / 60
        let rest = minutes % 60
        return localizer.t(L.Queue.remainingHoursMinutes, hours, rest)
    }
}

// MARK: - Sidebar 行

/// 备忘录式列表行：紧凑缩略图 + 标题/状态两级文本 + 右侧进度环 / 完成对勾 / 失败图标。
/// 比 `QueueItemView` 更紧凑（无按钮组、无进度条），选中高亮交给 `List(selection:)` 系统胶囊。
private struct QueueSidebarRow: View {
    let item: QueueManager.QueueItem
    @EnvironmentObject private var localizer: Localizer

    var body: some View {
        HStack(spacing: Spacing.rowGutter) {
            thumbnail
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(item.title)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.sm)
            statusIndicator
        }
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.title)
        .accessibilityValue(statusText)
    }

    private var thumbnail: some View {
        VideoThumbnail(
            url: item.thumbnailURL,
            cornerRadius: Radius.thumbnailRow,
            placeholderFont: .caption2
        )
        .frame(width: 48, height: 27)
    }

    /// 右侧状态指示：进行中→进度环；done→对勾；failed→橙色告警；cancelled→灰色。
    @ViewBuilder
    private var statusIndicator: some View {
        switch item.stage {
        case .queued, .downloading, .translating, .burning:
            ProgressRingView(progress: item.overallProgress ?? 0, finished: false)
        case .done:
            ProgressRingView(progress: 1, finished: true)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
        case .cancelled:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    /// 状态副文：复用 `QueueStatusFormatter` 的紧凑口径（保留百分比与阶段，去掉速度/剩余），
    /// 与 legacy 列表和 detail 的状态文案保持一致，单行 lineLimit 1 不溢出。
    private var statusText: String {
        QueueStatusFormatter(item: item, localizer: localizer).compactText
    }
}

// MARK: - Detail 视图

/// 右侧详情：大预览框（缩略图 + done 时的播放叠层）+ 标题/元信息/状态 + 一排功能按钮
/// + 可折叠简介。所有按钮复用 `QueueManager` 操作，均为真实可用。
private struct QueueDetailView: View {
    let item: QueueManager.QueueItem
    @ObservedObject var queue: QueueManager
    /// 登录类失败项点「登录并重试」：把站点 + 登录起始 URL 交给外层打开登录窗（与 legacy 队列一致）。
    var onLogin: (_ site: String, _ loginURL: URL?) -> Void = { _, _ in }
    @EnvironmentObject private var localizer: Localizer
    @State private var descriptionExpanded = false

    /// done 态下第一个可播放的视频产物（供预览框播放叠层）。
    private var playableVideo: URL? {
        guard case .done = item.stage else { return nil }
        let videoExtensions: Set<String> = ["mp4", "mov", "mkv", "webm", "m4v", "avi", "flv", "ts"]
        return item.resultFiles.first { videoExtensions.contains($0.pathExtension.lowercased()) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                preview
                header
                statusRow
                actionButtons
                descriptionSection
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.vertical, Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: 预览框

    private var preview: some View {
        AsyncImage(url: item.thumbnailURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .empty where item.thumbnailURL != nil:
                // 缩略图加载中：轻量 ProgressView，避免立刻闪现「无缩略图」占位（HIG progressive-loading）。
                Rectangle()
                    .fill(.quaternary)
                    .overlay(ProgressView().controlSize(.small))
            default:
                Rectangle()
                    .fill(.quaternary)
                    .overlay(Image(systemName: "film").font(.largeTitle).foregroundStyle(.tertiary))
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: 320)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: Stroke.hairline)
        )
        .overlay {
            if let video = playableVideo {
                Button {
                    NSWorkspace.shared.open(video)
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 56))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 8)
                }
                .buttonStyle(.plain)
                .help(localizer.t(L.SplitLayout.play))
                .accessibilityLabel(localizer.t(L.SplitLayout.play))
            }
        }
    }

    // MARK: 标题与元信息

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(item.title)
                .font(.title3.weight(.semibold))
                .lineLimit(3)
                .help(item.title)
            let meta = [item.info.durationText, item.info.uploader]
                .compactMap { $0 }
                .joined(separator: " · ")
            if !meta.isEmpty {
                Text(meta)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: 状态行（复用 QueueStatusFormatter 的丰富文案）+ 进度条

    private var statusRow: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                statusIcon
                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(isFailed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            if showsProgressBar {
                progressBar
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// 非终态（进行中）才显示进度条，与 QueueItemView.showsProgressBar 口径一致。
    private var showsProgressBar: Bool {
        switch item.stage {
        case .queued, .downloading, .translating, .burning:
            return true
        case .done, .failed, .cancelled:
            return false
        }
    }

    /// 有 overallProgress 时确定进度，否则 indeterminate；暂停时灰色 tint——与 QueueItemView.progressBar 一致。
    private var progressBar: some View {
        Group {
            if let p = item.overallProgress {
                ProgressView(value: min(max(p, 0), 1))
                    .tint(item.isPaused ? .gray : nil)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(item.isPaused ? .gray : nil)
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.stage {
        case .queued, .downloading, .translating, .burning:
            ProgressRingView(progress: item.overallProgress ?? 0, finished: false)
        case .done:
            ProgressRingView(progress: 1, finished: true)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
        case .cancelled:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private var isFailed: Bool {
        if case .failed = item.stage { return true }
        return false
    }

    /// 状态文案：复用 `QueueStatusFormatter` 的完整口径（下载 百分比·速度·剩余、ASR 三子阶段、
    /// 翻译/烧录/转码%、暂停、done/部分成功、failed 原因），与 legacy 列表保持一致。
    private var statusText: String {
        QueueStatusFormatter(item: item, localizer: localizer).detailText
    }

    // MARK: 一排功能按钮（复用 QueueManager 操作，真实可用）

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: Spacing.md) {
            switch item.stage {
            case .queued, .downloading, .translating, .burning:
                if item.isPaused {
                    actionButton("play.fill", title: localizer.t(L.Queue.resume)) { queue.resume(item.id) }
                } else {
                    actionButton("pause.fill", title: localizer.t(L.Queue.pause)) { queue.pause(item.id) }
                }
                actionButton("xmark", title: localizer.t(L.Queue.cancelAction)) { queue.cancel(item.id) }
            case .done:
                // 部分成功（视频下好、字幕处理失败）：只重跑字幕处理，与 legacy 一致。
                if item.partialFailure {
                    actionButton("arrow.clockwise", title: localizer.t(L.Queue.retrySubtitle)) { queue.retry(item.id) }
                }
                // 完成项可用本地 Whisper 重识别（仅在生成器就绪时显示，retryWithLocalASR 内部也再校验）。
                if queue.canRetryWithLocalASR(item.id), queue.hasLocalASRGenerator {
                    actionButton("waveform", title: localizer.t(L.Queue.retryWithLocalASR)) { queue.retryWithLocalASR(item.id) }
                }
                if !item.resultFiles.isEmpty {
                    actionButton("folder", title: localizer.t(L.Queue.revealInFinder)) { queue.revealInFinder(item.id) }
                }
                actionButton("trash", title: localizer.t(L.Queue.remove), role: .destructive) { queue.remove(item.id) }
            case .failed:
                // 登录类失败：给「登录并重试」入口（与 legacy 队列一致），否则用户无法从三栏恢复登录门失败。
                if let prompt = item.needsLogin {
                    actionButton("person.crop.circle.badge.plus", title: localizer.t(L.Queue.loginAndRetry)) {
                        onLogin(prompt.site, prompt.loginURL)
                    }
                }
                actionButton("arrow.clockwise", title: localizer.t(L.Queue.retryTask)) { queue.retry(item.id) }
                actionButton("trash", title: localizer.t(L.Queue.remove), role: .destructive) { queue.remove(item.id) }
            case .cancelled:
                actionButton("arrow.clockwise", title: localizer.t(L.Queue.retryTask)) { queue.retry(item.id) }
                if !item.resultFiles.isEmpty {
                    actionButton("folder", title: localizer.t(L.Queue.revealInFinder)) { queue.revealInFinder(item.id) }
                }
                actionButton("trash", title: localizer.t(L.Queue.remove), role: .destructive) { queue.remove(item.id) }
            }
            Spacer(minLength: 0)
        }
    }

    private func actionButton(
        _ systemName: String,
        title: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemName)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(title)
    }

    // MARK: 可折叠简介

    @ViewBuilder
    private var descriptionSection: some View {
        if let description = item.info.description, !description.isEmpty {
            DisclosureGroup(localizer.t(L.SplitLayout.descriptionSection), isExpanded: $descriptionExpanded) {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Spacing.xs)
            }
        }
    }

}

