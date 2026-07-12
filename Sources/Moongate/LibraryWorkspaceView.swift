import AppKit
import AVFoundation
import AVKit
import MoongateCore
import SwiftUI

/// The default 0.9 macOS workspace: a persistent library in the first two
/// columns and a focused player/workbench in the detail column. The Inspector
/// is intentionally inside the detail column rather than a fixed fourth split.
struct LibraryWorkspaceView: View {
    @ObservedObject var model: ViewModel
    @EnvironmentObject private var localizer: Localizer
    @ObservedObject var workspace: LibraryWorkspaceModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @FocusState private var searchFocused: Bool
    @State private var trashItemID: UUID?

    init(model: ViewModel, workspace: LibraryWorkspaceModel) {
        self.model = model
        self.workspace = workspace
    }

    var body: some View {
        GeometryReader { proxy in
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebar
                    .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
            } content: {
                libraryList
                    .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 440)
            } detail: {
                workbench
            }
            .navigationSplitViewStyle(.balanced)
            .onAppear { applyResponsiveLayout(width: proxy.size.width) }
            .onChange(of: proxy.size.width) { _, width in
                applyResponsiveLayout(width: width)
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                if workspace.undoRemovalAvailable {
                    LibraryRemovalUndoBar(workspace: workspace)
                }
                if let notice = model.enqueueNotice {
                    LibraryEnqueueNoticeBar(notice: notice) {
                        model.enqueueNotice = nil
                    }
                }
            }
            .padding(.bottom, 14)
        }
        .toolbar { workspaceToolbar }
        .onReceive(NotificationCenter.default.publisher(for: .moongateLibrarySearchFocus)) { _ in
            searchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: AppWorkspaceCommand.inspectorToggleRequested)) { _ in
            workspace.toggleInspector()
        }
        .sheet(isPresented: $workspace.showRecoverySheet) {
            recoverySheet
        }
        .alert("资料库需要处理", isPresented: Binding(
            get: { workspace.errorMessage != nil },
            set: { if !$0 { workspace.errorMessage = nil } }
        )) {
            Button("好") { workspace.errorMessage = nil }
        } message: {
            Text(workspace.errorMessage ?? "")
        }
        .confirmationDialog(
            "将文件移到废纸篓？",
            isPresented: Binding(
                get: { trashItemID != nil },
                set: { if !$0 { trashItemID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("移到废纸篓", role: .destructive) {
                let itemID = trashItemID
                trashItemID = nil
                workspace.moveArtifactsToTrash(itemID: itemID)
            }
            Button("取消", role: .cancel) {
                trashItemID = nil
            }
        } message: {
            Text("这会将所有版本的本地文件移到废纸篓，并从资料库移除索引。")
        }
    }

    @ToolbarContentBuilder
    private var workspaceToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                workspace.toggleInspector()
            } label: {
                Label(
                    workspace.showInspector ? "隐藏检查器" : "显示检查器",
                    systemImage: "sidebar.right"
                )
            }
            .help(workspace.showInspector ? "隐藏信息栏" : "显示信息栏")
        }
    }

    private var sidebar: some View {
        List(selection: $workspace.sidebarDestination) {
            Section {
                sidebarRow("全部视频", systemImage: "rectangle.stack", destination: .all, count: workspace.sidebarCount(for: .all))
                sidebarRow("进行中", systemImage: "arrow.triangle.2.circlepath", destination: .active, count: count(for: .active))
                sidebarRow("需处理", systemImage: "exclamationmark.triangle", destination: .needsAttention, count: count(for: .needsAttention))
                sidebarRow("已完成", systemImage: "checkmark.circle", destination: .completed, count: count(for: .completed))
                sidebarRow("已置顶", systemImage: "pin", destination: .pinned, count: count(for: .pinned))
            }

            if !workspace.availableTags.isEmpty {
                Section("标签") {
                    ForEach(workspace.availableTags) { tag in
                        Label(tag.name, systemImage: "tag")
                            .tag(LibraryWorkspaceModel.SidebarDestination.tag(tag.name))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("资料库")
    }

    private func sidebarRow(
        _ title: String,
        systemImage: String,
        destination: LibraryWorkspaceModel.SidebarDestination,
        count: Int
    ) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer(minLength: 8)
            if count > 0 {
                Text("\(count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .tag(destination)
    }

    private func count(for filter: LibraryFilter) -> Int {
        workspace.sidebarCount(for: filter)
    }

    private var libraryList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(listTitle)
                    .font(.headline)
                Spacer(minLength: 8)
                if workspace.hasQueuedTasks {
                    Button("开始全部") {
                        workspace.startAllQueuedTasks()
                    }
                    .buttonStyle(.borderless)
                }
                Button {
                    NotificationCenter.default.post(name: AppWorkspaceCommand.newDownloadRequested, object: nil)
                } label: {
                    Label("新建下载", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .help("新建下载（⌘N）")
                .accessibilityLabel("新建下载")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索视频", text: $workspace.searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .accessibilityLabel("搜索资料库")
                if !workspace.searchText.isEmpty {
                    Button {
                        workspace.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除搜索")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 10)
            .background(.bar)

            if workspace.projectedItems.isEmpty {
                libraryEmptyState
            } else {
                List(selection: workspace.selectedItemBinding) {
                    ForEach(workspace.projectedItems) { projected in
                        LibraryVideoRow(
                            projected: projected,
                            details: workspace.queueDetails(for: projected.id)
                        )
                        .tag(projected.id)
                        .contextMenu {
                            LibraryRowContextMenu(
                                item: projected.item,
                                processing: projected.processing,
                                workspace: workspace,
                                requestTrash: { trashItemID = projected.id }
                            )
                        }
                        .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(listTitle)
    }

    private var listTitle: String {
        switch workspace.sidebarDestination {
        case .all: "全部视频"
        case .active: "进行中"
        case .needsAttention: "需处理"
        case .completed: "已完成"
        case .pinned: "已置顶"
        case .tag(let tag): tag
        }
    }

    private var libraryEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 34, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text(workspace.searchText.isEmpty ? "还没有视频" : "没有匹配的视频")
                .font(.headline)
            Text(workspace.searchText.isEmpty ? "点列表标题中的＋添加链接。" : "换个关键词，或清除搜索试试。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    @ViewBuilder
    private var workbench: some View {
        if let item = workspace.selectedItem {
            LibraryWorkbenchDetail(
                item: item,
                processing: workspace.selectedProcessing,
                queueDetails: workspace.queueDetails(for: item.id),
                appModel: model,
                workspace: workspace,
                onRequestTrash: { trashItemID = item.id }
            )
        } else {
            VStack(spacing: 12) {
                Image(systemName: "play.rectangle.on.rectangle")
                    .font(.system(size: 44, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                Text("选择一个视频")
                    .font(.title3.weight(.semibold))
                Text("在列表中选择视频，即可预览、查看产物和调整处理方式。")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(36)
        }
    }

    private var recoverySheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("发现 \(workspace.recoveryCandidates.count) 个已有视频", systemImage: "arrow.clockwise")
                .font(.headline)
            Text("月之门可以只读取 Downloads/Moongate 中的已有文件，创建“已恢复”资料记录；不会移动或删除文件。来源和模型无法确认的项目会标为未知。")
                .font(.callout)
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(workspace.recoveryCandidates.prefix(12)) { candidate in
                        Text(candidate.relativePath)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                    }
                    if workspace.recoveryCandidates.count > 12 {
                        Text("以及另外 \(workspace.recoveryCandidates.count - 12) 个文件")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxHeight: 180)

            HStack {
                Spacer()
                Button("暂不恢复") { workspace.dismissRecovery() }
                    .keyboardShortcut(.cancelAction)
                Button("恢复到资料库") { workspace.importRecoveredVideos() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func applyResponsiveLayout(width: CGFloat) {
        workspace.updateLayout(for: width)
        if width < 1_100 {
            columnVisibility = .doubleColumn
        } else if columnVisibility != .all {
            columnVisibility = .all
        }
    }
}

private struct LibraryRemovalUndoBar: View {
    @ObservedObject var workspace: LibraryWorkspaceModel

    var body: some View {
        HStack(spacing: 10) {
            Text("已从资料库移除。")
                .foregroundStyle(.secondary)
            Button("撤销") {
                workspace.undoRemoveFromLibrary()
            }
            .buttonStyle(.bordered)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("已从资料库移除")
    }
}

private struct LibraryEnqueueNoticeBar: View {
    let notice: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(notice)
                .lineLimit(2)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("关闭提示")
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(notice)
    }
}

private struct LibraryVideoRow: View {
    let projected: LibraryProjectedItem
    let details: LibraryWorkspaceModel.LiveQueueDetails?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VideoThumbnail(
                url: projected.item.thumbnail.flatMap { URL(string: $0.urlString) },
                cornerRadius: 7,
                placeholderFont: .caption
            )
            .frame(width: 72, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(projected.item.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if projected.item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }

                HStack(spacing: 4) {
                    Text(LibraryDisplay.recoveryLabel(projected.processing, details: details))
                    if let model = LibraryDisplay.modelLabel(projected.processing) {
                        Text("·")
                        Text(model)
                    }
                }
                .font(.caption)
                .foregroundStyle(LibraryDisplay.statusColor(projected.processing, details: details))
                .lineLimit(1)

                statusSlot
            }
            Spacer(minLength: 0)
            LibraryStatusGlyph(processing: projected.processing)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(projected.item.title)
        .accessibilityValue(activeAccessibilityValue)
    }

    @ViewBuilder
    private var statusSlot: some View {
        Group {
            if let processing = projected.processing, processing.state.isRunning {
                HStack(spacing: 6) {
                    ProgressRingView(progress: processing.progress, finished: false)
                    Text("\(Int((processing.progress * 100).rounded()))%")
                        .monospacedDigit()
                    Text(LibraryDisplay.liveDetail(details))
                        .lineLimit(1)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else if projected.processing?.state == .completed {
                Text(LibraryDisplay.completedDetail(projected.item))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if projected.processing?.state == .queued {
                if let readiness = LibraryDisplay.queuedReadinessDetail(details) {
                    Label(readiness, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .accessibilityLabel("需要处理，\(readiness)")
                } else {
                    Text("可在信息栏调整配置")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else if projected.processing?.state == .cancelled {
                Text("可重新处理或移出资料库")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(LibraryDisplay.recoveryLabel(projected.processing, details: details))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(height: 18, alignment: .leading)
    }

    private var activeAccessibilityValue: String {
        guard let processing = projected.processing, processing.state.isRunning else {
            if projected.processing?.state == .queued,
               let readiness = LibraryDisplay.queuedReadinessDetail(details) {
                return "需要处理，\(readiness)"
            }
            return LibraryDisplay.recoveryLabel(projected.processing, details: details)
        }
        let percent = Int((processing.progress * 100).rounded())
        return "\(LibraryDisplay.stageLabel(projected.processing))，\(percent)%，\(LibraryDisplay.liveDetail(details))"
    }
}

private struct LibraryRowContextMenu: View {
    let item: MoongateCore.LibraryItem
    let processing: ProcessingSummary?
    @ObservedObject var workspace: LibraryWorkspaceModel
    let requestTrash: () -> Void

    var body: some View {
        if workspace.canPlayEmbeddedVideo(itemID: item.id) {
            Button("播放") {
                workspace.playEmbeddedVideo(itemID: item.id)
            }
        }

        if workspace.canRevealInFinder(itemID: item.id) {
            Button("在访达中显示") {
                workspace.revealInFinder(itemID: item.id)
            }
        }

        if item.source?.urlString != nil {
            Button("复制来源链接") {
                workspace.copySourceLink(itemID: item.id)
            }
        }

        if let queueItem = workspace.queueItem(for: item.id) {
            switch queueItem.stage {
            case .queued:
                if queueItem.isDeferredDraft {
                    if let recovery = workspace.queuedReadinessRecovery(for: item.id) {
                        Button(recovery.actionTitle) {
                            workspace.openQueuedReadinessRecovery(for: item.id)
                        }
                    } else {
                        Button("开始") {
                            workspace.recoverQueueTask(for: item.id)
                        }
                    }
                }
            case .failed:
                Button(queueItem.needsLogin == nil ? "恢复" : "登录") {
                    workspace.recoverQueueTask(for: item.id)
                }
            case .cancelling, .downloading, .translating, .burning, .done, .cancelled:
                EmptyView()
            }
        }

        if processing?.state.isQueued == true {
            Button("调整配置") {
                workspace.showInspector(.processing, for: item.id)
            }
        } else if processing?.state.isRunning != true {
            Button("重新处理") {
                workspace.showInspector(.processing, for: item.id)
            }
        }

        if item.isPinned {
            Button("取消置顶") {
                workspace.setPinned(false, itemID: item.id)
            }
        } else {
            Button("置顶") {
                workspace.setPinned(true, itemID: item.id)
            }
        }

        Divider()

        Button("移出资料库") {
            workspace.removeFromLibrary(itemID: item.id)
        }

        Divider()

        Button("移到废纸篓…", role: .destructive) {
            requestTrash()
        }
    }

}

private struct LibraryStatusGlyph: View {
    let processing: ProcessingSummary?

    var body: some View {
        switch processing?.state {
        case .completed:
            EmptyView()
        case .partialSuccess, .needsAttention, .interrupted, .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .cancelled:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
        case .cancelling:
            ProgressView().controlSize(.small)
        case .queued, .downloading, .transcribing, .translating, .transcoding, .burning:
            EmptyView()
        case .none:
            EmptyView()
        }
    }
}

private struct LibraryWorkbenchDetail: View {
    let item: MoongateCore.LibraryItem
    let processing: ProcessingSummary?
    let queueDetails: LibraryWorkspaceModel.LiveQueueDetails?
    @ObservedObject var appModel: ViewModel
    @ObservedObject var workspace: LibraryWorkspaceModel
    let onRequestTrash: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PlayerStageView(item: item, workspace: workspace)

                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .top, spacing: 8) {
                            Text(item.title)
                                .font(.title2.weight(.semibold))
                                .textSelection(.enabled)
                            if item.isPinned {
                                Image(systemName: "pin.fill")
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("已置顶")
                            }
                        }
                        Text(LibraryDisplay.recoveryLabel(processing, details: queueDetails))
                            .font(.callout)
                            .foregroundStyle(LibraryDisplay.statusColor(processing, details: queueDetails))

                        if let processing, processing.state.isRunning {
                            ProgressView(value: processing.progress)
                            Text(LibraryDisplay.liveDetail(queueDetails))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let queueDetails,
                       let queueItem = appModel.queue.items.first(where: { $0.id == queueDetails.queueID }) {
                        QueueWorkbenchActions(item: queueItem, queue: appModel.queue, workspace: workspace)
                    }

                    if processing?.state == .interrupted {
                        Button {
                            workspace.restartInterruptedTask()
                        } label: {
                            Label("重新开始", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                    }

                    if !workspace.showInspector {
                        CollapsedInspectorActionStrip(
                            item: item,
                            processing: processing,
                            queueItem: workspace.selectedQueueItem,
                            appModel: appModel,
                            workspace: workspace
                        )
                    }

                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if workspace.showInspector {
                Divider()
                LibraryInspector(
                    item: item,
                    processing: processing,
                    workspace: workspace,
                    onConfirmTrash: onRequestTrash
                )
                .frame(width: 320)
                .background(.bar)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.2),
            value: workspace.inspectorInteractionGeneration
        )
        .navigationTitle(item.title)
    }
}

private struct PlayerStageView: View {
    let item: MoongateCore.LibraryItem
    @ObservedObject var workspace: LibraryWorkspaceModel

    private var videoArtifact: LibraryArtifact? {
        item.latestVersion?.artifacts.first {
            $0.role == .video || $0.role == .renderedVideo
        }
    }

    private var videoURL: URL? {
        guard let videoArtifact else { return nil }
        return workspace.absoluteURL(for: videoArtifact)
    }

    private var supportsEmbeddedPlayback: Bool {
        guard let videoURL else { return false }
        return ["mp4", "mov", "m4v"].contains(videoURL.pathExtension.lowercased())
    }

    private var playbackRequestID: UUID? {
        guard let request = workspace.playbackRequest, request.itemID == item.id else {
            return nil
        }
        return request.requestID
    }

    var body: some View {
        Group {
            if let videoURL {
                if !FileManager.default.fileExists(atPath: videoURL.path) {
                    missingVideoStage(videoURL)
                } else if supportsEmbeddedPlayback {
                    NativeVideoPlayer(
                        url: videoURL,
                        playbackRequestID: playbackRequestID,
                        onPlaybackRequestHandled: { requestID in
                            DispatchQueue.main.async {
                                workspace.consumePlaybackRequest(id: requestID)
                            }
                        }
                    )
                    .aspectRatio(16 / 9, contentMode: .fit)
                } else {
                    unsupportedVideoStage(videoURL)
                }
            } else {
                previewStage
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 280, maxHeight: 560)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }

    private var previewStage: some View {
        ZStack {
            VideoThumbnail(
                url: item.thumbnail.flatMap { URL(string: $0.urlString) },
                cornerRadius: 12,
                placeholderFont: .title2
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(.black.opacity(0.12))

            VStack(spacing: 8) {
                Image(systemName: "film")
                    .font(.system(size: 34, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                Text("预览将在视频文件可用后显示")
                    .font(.callout)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.45), radius: 4)
        }
        .accessibilityLabel("视频预览尚不可用")
    }

    private func missingVideoStage(_ url: URL) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34, weight: .regular))
                .symbolRenderingMode(.hierarchical)
            Text("视频文件已移动或删除")
                .font(.headline)
            Text("资料库保留了记录，但原视频不在预期位置。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("打开输出文件夹") {
                NSWorkspace.shared.open(url.deletingLastPathComponent())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("视频文件已移动或删除")
    }

    private func unsupportedVideoStage(_ url: URL) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "play.slash")
                .font(.system(size: 34, weight: .regular))
                .symbolRenderingMode(.hierarchical)
            Text("此格式不支持内嵌播放")
                .font(.headline)
            Text("\(url.pathExtension.uppercased()) 将使用默认 App 打开。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("使用默认 App 打开") {
                NSWorkspace.shared.open(url)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("此格式不支持内嵌播放")
    }
}

private struct NativeVideoPlayer: NSViewRepresentable {
    let url: URL
    let playbackRequestID: UUID?
    let onPlaybackRequestHandled: (UUID) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.controlsStyle = .floating
        playerView.videoGravity = .resizeAspect
        context.coordinator.load(
            url,
            into: playerView,
            playbackRequestID: playbackRequestID,
            onPlaybackRequestHandled: onPlaybackRequestHandled
        )
        return playerView
    }

    func updateNSView(_ playerView: AVPlayerView, context: Context) {
        context.coordinator.load(
            url,
            into: playerView,
            playbackRequestID: playbackRequestID,
            onPlaybackRequestHandled: onPlaybackRequestHandled
        )
    }

    static func dismantleNSView(_ playerView: AVPlayerView, coordinator: Coordinator) {
        playerView.player?.pause()
        playerView.player = nil
        coordinator.unload()
    }

    final class Coordinator {
        private var loadedURL: URL?
        private var handledPlaybackRequestID: UUID?

        func load(
            _ url: URL,
            into playerView: AVPlayerView,
            playbackRequestID: UUID?,
            onPlaybackRequestHandled: (UUID) -> Void
        ) {
            if loadedURL != url {
                loadedURL = url
                playerView.player = AVPlayer(url: url)
            }
            if let playbackRequestID, handledPlaybackRequestID != playbackRequestID {
                handledPlaybackRequestID = playbackRequestID
                playerView.player?.play()
                onPlaybackRequestHandled(playbackRequestID)
            }
        }

        func unload() {
            loadedURL = nil
        }
    }
}

private struct QueueWorkbenchActions: View {
    let item: QueueManager.QueueItem
    @ObservedObject var queue: QueueManager
    @ObservedObject var workspace: LibraryWorkspaceModel

    var body: some View {
        HStack(spacing: 10) {
            if item.isDeferredDraft {
                if let recovery = workspace.queuedReadinessRecovery(for: item.libraryItemID) {
                    Button(recovery.actionTitle) {
                        workspace.openQueuedReadinessRecovery(for: item.libraryItemID)
                    }
                    Button {
                        workspace.showInspector(.processing)
                    } label: {
                        Label("调整配置", systemImage: "slider.horizontal.3")
                    }
                } else {
                    Button {
                        workspace.startSelectedQueuedTask()
                    } label: {
                        Label("开始", systemImage: "play.fill")
                    }
                }
                Button(role: .destructive) {
                    queue.cancel(item.id)
                } label: {
                    Label("取消任务", systemImage: "xmark")
                }
            } else if item.stage == .cancelling {
                Label("正在取消…", systemImage: "hourglass")
                    .foregroundStyle(.secondary)
            } else if case .failed = item.stage {
                Button {
                    workspace.recoverQueueTask(for: item.libraryItemID)
                } label: {
                    Label(item.needsLogin == nil ? "恢复" : "登录", systemImage: "arrow.clockwise")
                }
            } else if item.isPaused {
                Button {
                    queue.resume(item.id)
                } label: {
                    Label("继续", systemImage: "play.fill")
                }
            } else if !isTerminal {
                Button {
                    queue.pause(item.id)
                } label: {
                    Label("暂停", systemImage: "pause.fill")
                }
            }

            if !item.isDeferredDraft,
               item.stage != .cancelling,
               !isTerminal {
                Button(role: .destructive) {
                    queue.cancel(item.id)
                } label: {
                    Label("取消任务", systemImage: "xmark")
                }
            }

            if !item.resultFiles.isEmpty {
                Button {
                    queue.revealInFinder(item.id)
                } label: {
                    Label("在访达中显示", systemImage: "folder")
                }
            }
        }
        .buttonStyle(.bordered)
    }

    private var isTerminal: Bool {
        switch item.stage {
        case .done, .failed, .cancelled:
            true
        case .queued, .cancelling, .downloading, .translating, .burning:
            false
        }
    }
}

private struct CollapsedInspectorActionStrip: View {
    let item: MoongateCore.LibraryItem
    let processing: ProcessingSummary?
    let queueItem: QueueManager.QueueItem?
    @ObservedObject var appModel: ViewModel
    @ObservedObject var workspace: LibraryWorkspaceModel

    var body: some View {
        HStack(spacing: 8) {
            if let queueItem {
                queueActions(queueItem)
            } else if processing?.state == .interrupted {
                Button {
                    workspace.restartInterruptedTask()
                } label: {
                    Label("重新开始", systemImage: "arrow.clockwise")
                }
            } else {
                if workspace.canRevealInFinder(itemID: item.id) {
                    Button {
                        workspace.revealSelectedInFinder()
                    } label: {
                        Label("在访达中显示", systemImage: "folder")
                    }
                }
                Button {
                    workspace.showInspector(.processing)
                } label: {
                    Label("重新处理", systemImage: "arrow.clockwise")
                }
            }

            Menu {
                Button("查看信息") { workspace.showInspector(.information) }
                Button("调整处理") { workspace.showInspector(.processing) }
                if item.isPinned {
                    Button("取消置顶") { workspace.setPinned(false) }
                } else {
                    Button("置顶") { workspace.setPinned(true) }
                }
            } label: {
                Label("更多", systemImage: "ellipsis.circle")
            }
        }
        .buttonStyle(.bordered)
        .padding(10)
        .background(.bar, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("视频快捷操作")
    }

    @ViewBuilder
    private func queueActions(_ queueItem: QueueManager.QueueItem) -> some View {
        switch queueItem.stage {
        case .queued where queueItem.isDeferredDraft:
            if let recovery = workspace.queuedReadinessRecovery(for: item.id) {
                Button(recovery.actionTitle) {
                    workspace.openQueuedReadinessRecovery(for: item.id)
                }
                Button {
                    workspace.showInspector(.processing)
                } label: {
                    Label("调整配置", systemImage: "slider.horizontal.3")
                }
            } else {
                Button {
                    workspace.startSelectedQueuedTask()
                } label: {
                    Label("开始", systemImage: "play.fill")
                }
            }
            Button(role: .destructive) {
                appModel.queue.cancel(queueItem.id)
            } label: {
                Label("取消", systemImage: "xmark")
            }
        case .cancelling:
            Label("正在取消…", systemImage: "hourglass")
                .foregroundStyle(.secondary)
        case .queued, .downloading, .translating, .burning:
            if queueItem.isPaused {
                Button {
                    appModel.queue.resume(queueItem.id)
                } label: {
                    Label("继续", systemImage: "play.fill")
                }
            } else {
                Button {
                    appModel.queue.pause(queueItem.id)
                } label: {
                    Label("暂停", systemImage: "pause.fill")
                }
            }
            Button(role: .destructive) {
                appModel.queue.cancel(queueItem.id)
            } label: {
                Label("取消", systemImage: "xmark")
            }
        case .failed:
            if let prompt = queueItem.needsLogin {
                Button {
                    appModel.openLoginForQueueItem(site: prompt.site, loginURL: prompt.loginURL)
                } label: {
                    Label("登录", systemImage: "person.crop.circle.badge.checkmark")
                }
            } else {
                Button {
                    appModel.queue.retry(queueItem.id)
                } label: {
                    Label("恢复", systemImage: "arrow.clockwise")
                }
            }
            if !queueItem.resultFiles.isEmpty {
                Button {
                    workspace.revealInFinder(itemID: queueItem.libraryItemID)
                } label: {
                    Label("在访达中显示", systemImage: "folder")
                }
            }
        case .done, .cancelled:
            if workspace.canRevealInFinder(itemID: item.id) {
                Button {
                    workspace.revealSelectedInFinder()
                } label: {
                    Label("在访达中显示", systemImage: "folder")
                }
            }
            Button {
                workspace.showInspector(.processing)
            } label: {
                Label("重新处理", systemImage: "arrow.clockwise")
            }
        }
    }
}

private struct LibraryInspector: View {
    let item: MoongateCore.LibraryItem
    let processing: ProcessingSummary?
    @ObservedObject var workspace: LibraryWorkspaceModel
    let onConfirmTrash: () -> Void
    @State private var note = ""
    @State private var tagInput = ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("检查器", selection: $workspace.inspectorMode) {
                Text("信息").tag(LibraryWorkspaceModel.InspectorMode.information)
                Text("处理").tag(LibraryWorkspaceModel.InspectorMode.processing)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch workspace.inspectorMode {
                    case .information:
                        information
                    case .processing:
                        processingEditor
                    }
                }
                .padding(14)
            }
        }
        .onAppear { note = item.note ?? "" }
        .onChange(of: item.id) { _, _ in
            note = item.note ?? ""
            tagInput = ""
        }
        .accessibilityLabel("视频检查器")
    }

    private var information: some View {
        Group {
            inspectorSection("文件信息") {
                InspectorKeyValueRow("标题", value: item.title)
                InspectorKeyValueRow("状态", value: LibraryDisplay.stageLabel(processing))
                InspectorKeyValueRow("版本", value: "v\(item.latestVersion?.number ?? 1)")
                if let source = item.source?.urlString {
                    InspectorKeyValueRow("来源", value: source, lineLimit: 2)
                } else {
                    InspectorKeyValueRow("来源", value: "未知")
                }
            }

            inspectorSection("产物") {
                let artifacts = item.latestVersion?.artifacts ?? []
                if artifacts.isEmpty {
                    Text("文件会在任务完成后显示。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(artifacts) { artifact in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LibraryDisplay.artifactLabel(artifact.role))
                                .font(.caption.weight(.medium))
                            Text(artifact.relativePath)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        if artifact.id != artifacts.last?.id { Divider() }
                    }
                }
            }

            inspectorSection("标签") {
                if item.tags.isEmpty {
                    Text("尚未添加标签")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(item.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }
                HStack(spacing: 6) {
                    TextField("添加标签", text: $tagInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addTag() }
                    Button("添加") { addTag() }
                        .disabled(tagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            inspectorSection("备注") {
                TextEditor(text: $note)
                    .font(.callout)
                    .frame(minHeight: 72)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    )
                    .onChange(of: note) { _, newValue in
                        workspace.updateNote(newValue)
                    }
            }

            Toggle("置顶视频", isOn: Binding(
                get: { item.isPinned },
                set: { workspace.setPinned($0) }
            ))

            inspectorSection("资料库") {
                Button("从资料库移除") {
                    workspace.removeFromLibrary()
                }
                .accessibilityHint("仅移除资料库索引，不会删除本地文件。")

                Button("将文件移到废纸篓", role: .destructive) {
                    onConfirmTrash()
                }
                .accessibilityHint("需要再次确认；会将所有版本的文件移到废纸篓。")
            }
        }
    }

    @ViewBuilder
    private var processingEditor: some View {
        if processing?.state.isQueued == true {
            queuedProcessingEditor
        } else if let processing, processing.state.isRunning {
            inspectorSection("运行中的配置") {
                Label("任务正在运行，配置快照为只读。", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                processingSummaryRows(processing.configuration)
            }
        } else {
            inspectorSection("处理配置") {
                Text("调整完成项后会创建新版本，不覆盖当前产物。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("字幕处理", selection: workspace.configurationBinding(\.subtitleMode)) {
                    Text("不处理字幕").tag(ChineseSubtitleMode.off.rawValue)
                    Text("生成译文 SRT").tag(ChineseSubtitleMode.srtOnly.rawValue)
                    Text("压制译文字幕").tag(ChineseSubtitleMode.burnIn.rawValue)
                    Text("压制原字幕").tag(ChineseSubtitleMode.burnOriginal.rawValue)
                }
                .pickerStyle(.menu)
                Picker("输出格式", selection: workspace.configurationBinding(\.outputFormat)) {
                    Text("使用默认").tag("")
                    Text("保持源格式").tag(OutputFormat.original.rawValue)
                    Text("MP4 · H.264").tag(OutputFormat.mp4H264.rawValue)
                    Text("MP4 · H.265").tag(OutputFormat.mp4H265.rawValue)
                    Text("MKV").tag(OutputFormat.mkv.rawValue)
                }
                .pickerStyle(.menu)

                Picker("源画质", selection: workspace.configurationBinding(\.quality)) {
                    Text("使用默认").tag("")
                    Text("最佳可用").tag("best")
                    Text("1080p").tag("bv*[height<=1080]+ba/b[height<=1080]")
                    Text("720p").tag("bv*[height<=720]+ba/b[height<=720]")
                }
                .pickerStyle(.menu)

                if workspace.draftSubtitleMode != .off {
                    Picker("字幕来源", selection: workspace.configurationBinding(\.subtitleSource)) {
                        Text("使用默认").tag("")
                        Text("沿用当前本地字幕").tag(SubtitleSourceKind.importedFile.rawValue)
                        Text("沿用当前手动字幕").tag(SubtitleSourceKind.manual.rawValue)
                        Text("沿用当前平台字幕").tag(SubtitleSourceKind.platformAuto.rawValue)
                        Text("沿用当前 HLS 字幕").tag(SubtitleSourceKind.hlsManifest.rawValue)
                        Text("本地识别（Whisper）").tag(SubtitleSourceKind.localASR.rawValue)
                        Text("云端识别").tag(SubtitleSourceKind.cloudASR.rawValue)
                    }
                    .pickerStyle(.menu)

                    TranscriptionModelPicker(selection: workspace.configurationBinding(\.transcriptionModel))

                    if workspace.draftSubtitleMode.requiresTranslation {
                        processingField("翻译模型", binding: workspace.configurationBinding(\.translationModel), placeholder: "例如 GPT-4.1 mini")
                        Picker("目标语言", selection: workspace.configurationBinding(\.targetLanguage)) {
                            Text("使用默认").tag("")
                            Text("简体中文").tag("zh-Hans")
                            Text("繁体中文").tag("zh-Hant")
                            Text("English").tag("en")
                        }
                        .pickerStyle(.menu)
                    }

                    if workspace.draftSubtitleMode.requiresBurner {
                        Picker("字幕样式", selection: workspace.configurationBinding(\.subtitleStyle)) {
                            Text("使用默认").tag("")
                            Text("双语").tag(SubtitleStyle.bilingual.rawValue)
                            Text("仅译文").tag(SubtitleStyle.chineseOnly.rawValue)
                        }
                        .pickerStyle(.menu)
                    }
                }
            }

            if let plan = workspace.reprocessPlan {
                inspectorSection("重新处理摘要") {
                    Text("将创建 v\((item.latestVersion?.number ?? 0) + 1)")
                        .font(.callout.weight(.medium))
                    Text(LibraryDisplay.reprocessDescription(plan))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if workspace.canCreateReprocess {
                        Button("创建重新处理任务") {
                            workspace.createReprocessTask()
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Text(workspace.reprocessBlockerReason ?? "当前配置无法创建重新处理任务。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var queuedProcessingEditor: some View {
        inspectorSection("待开始配置") {
            Text("这些选项会自动保存到此任务；开始后将冻结为只读快照。")
                .font(.caption)
                .foregroundStyle(.secondary)
            processingConfigurationFields
        }
    }

    @ViewBuilder
    private var processingConfigurationFields: some View {
        Picker("字幕处理", selection: workspace.configurationBinding(\.subtitleMode)) {
            Text("不处理字幕").tag(ChineseSubtitleMode.off.rawValue)
            Text("生成译文 SRT").tag(ChineseSubtitleMode.srtOnly.rawValue)
            Text("压制译文字幕").tag(ChineseSubtitleMode.burnIn.rawValue)
            Text("压制原字幕").tag(ChineseSubtitleMode.burnOriginal.rawValue)
        }
        .pickerStyle(.menu)

        Picker("输出格式", selection: workspace.configurationBinding(\.outputFormat)) {
            Text("使用默认").tag("")
            Text("保持源格式").tag(OutputFormat.original.rawValue)
            Text("MP4 · H.264").tag(OutputFormat.mp4H264.rawValue)
            Text("MP4 · H.265").tag(OutputFormat.mp4H265.rawValue)
            Text("MKV").tag(OutputFormat.mkv.rawValue)
        }
        .pickerStyle(.menu)

        Picker("源画质", selection: workspace.configurationBinding(\.quality)) {
            Text("使用默认").tag("")
            Text("最佳可用").tag("best")
            Text("1080p").tag("bv*[height<=1080]+ba/b[height<=1080]")
            Text("720p").tag("bv*[height<=720]+ba/b[height<=720]")
        }
        .pickerStyle(.menu)

        if workspace.draftSubtitleMode != .off {
            Picker("字幕来源", selection: workspace.configurationBinding(\.subtitleSource)) {
                Text("使用默认").tag("")
                Text("沿用当前本地字幕").tag(SubtitleSourceKind.importedFile.rawValue)
                Text("沿用当前手动字幕").tag(SubtitleSourceKind.manual.rawValue)
                Text("沿用当前平台字幕").tag(SubtitleSourceKind.platformAuto.rawValue)
                Text("沿用当前 HLS 字幕").tag(SubtitleSourceKind.hlsManifest.rawValue)
                Text("本地识别（Whisper）").tag(SubtitleSourceKind.localASR.rawValue)
                Text("云端识别").tag(SubtitleSourceKind.cloudASR.rawValue)
            }
            .pickerStyle(.menu)

            TranscriptionModelPicker(selection: workspace.configurationBinding(\.transcriptionModel))

            if workspace.draftSubtitleMode.requiresTranslation {
                processingField("翻译模型", binding: workspace.configurationBinding(\.translationModel), placeholder: "例如 GPT-4.1 mini")
                Picker("目标语言", selection: workspace.configurationBinding(\.targetLanguage)) {
                    Text("使用默认").tag("")
                    Text("简体中文").tag("zh-Hans")
                    Text("繁体中文").tag("zh-Hant")
                    Text("English").tag("en")
                }
                .pickerStyle(.menu)
            }

            if workspace.draftSubtitleMode.requiresBurner {
                Picker("字幕样式", selection: workspace.configurationBinding(\.subtitleStyle)) {
                    Text("使用默认").tag("")
                    Text("双语").tag(SubtitleStyle.bilingual.rawValue)
                    Text("仅译文").tag(SubtitleStyle.chineseOnly.rawValue)
                }
                .pickerStyle(.menu)
            }
        }
    }

    private func processingSummaryRows(_ configuration: LibraryProcessingConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            InspectorKeyValueRow("画质 / 格式", value: configuration.outputFormat ?? "未记录")
            InspectorKeyValueRow("字幕处理", value: configuration.subtitleMode ?? "未记录")
            InspectorKeyValueRow("字幕来源", value: configuration.subtitleSource ?? "未记录")
            InspectorKeyValueRow("转录模型", value: configuration.transcriptionModel ?? "未记录")
            InspectorKeyValueRow("翻译模型", value: configuration.translationModel ?? "未记录")
            InspectorKeyValueRow("目标语言", value: configuration.targetLanguage ?? "未记录")
            InspectorKeyValueRow("字幕样式", value: configuration.subtitleStyle ?? "未记录")
        }
    }

    private func processingField(_ label: String, binding: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption.weight(.medium))
            TextField(placeholder, text: binding)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func inspectorSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func addTag() {
        workspace.addTag(tagInput)
        tagInput = ""
    }
}

private struct InspectorKeyValueRow: View {
    let key: String
    let value: String
    var lineLimit: Int = 1

    init(_ key: String, value: String, lineLimit: Int = 1) {
        self.key = key
        self.value = value
        self.lineLimit = lineLimit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
                .lineLimit(lineLimit)
        }
    }
}

private struct FlowLayout: SwiftUI.Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: SwiftUI.ProposedViewSize, subviews: SwiftUI.LayoutSubviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(SwiftUI.ProposedViewSize.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + (x > 0 ? spacing : 0)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: SwiftUI.ProposedViewSize, subviews: SwiftUI.LayoutSubviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(SwiftUI.ProposedViewSize.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: SwiftUI.ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private enum LibraryDisplay {
    static func stageLabel(_ processing: ProcessingSummary?) -> String {
        switch processing?.state {
        case .queued: "等待中"
        case .cancelling: "正在取消…"
        case .downloading: "下载中"
        case .transcribing: "转录中"
        case .translating: "翻译中"
        case .transcoding: "转码中"
        case .burning: "压制字幕"
        case .completed: "已完成"
        case .partialSuccess: "部分完成"
        case .needsAttention: "需要处理"
        case .interrupted: "上次任务已中断"
        case .failed: "处理失败"
        case .cancelled: "已取消"
        case .none: "未处理"
        }
    }

    static func recoveryLabel(
        _ processing: ProcessingSummary?,
        details: LibraryWorkspaceModel.LiveQueueDetails?
    ) -> String {
        switch processing?.state {
        case .queued where queuedReadinessDetail(details) != nil:
            return "需要处理"
        case .partialSuccess, .needsAttention, .interrupted, .failed:
            if let status = details?.statusText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !status.isEmpty {
                return status
            }
            return stageLabel(processing)
        default:
            return stageLabel(processing)
        }
    }

    static func statusColor(
        _ processing: ProcessingSummary?,
        details: LibraryWorkspaceModel.LiveQueueDetails? = nil
    ) -> Color {
        if processing?.state == .queued, queuedReadinessDetail(details) != nil {
            return .orange
        }
        return switch processing?.state {
        case .completed: .secondary
        case .partialSuccess, .needsAttention, .interrupted, .failed: .orange
        case .cancelling, .cancelled: .secondary
        case .queued, .downloading, .transcribing, .translating, .transcoding, .burning: .accentColor
        case .none: .secondary
        }
    }

    static func modelLabel(_ processing: ProcessingSummary?) -> String? {
        processing?.actualModels.transcription ?? processing?.actualModels.translation
    }

    static func queuedReadinessDetail(
        _ details: LibraryWorkspaceModel.LiveQueueDetails?
    ) -> String? {
        guard let detail = details?.statusText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !detail.isEmpty else {
            return nil
        }
        return detail
    }

    static func completedDetail(_ item: MoongateCore.LibraryItem) -> String {
        guard let artifact = item.latestVersion?.artifacts.first(where: {
            $0.role == .renderedVideo || $0.role == .video
        }) else {
            return "已保存"
        }
        let format = URL(fileURLWithPath: artifact.relativePath).pathExtension.uppercased()
        return format.isEmpty ? "已保存" : "已保存 · \(format)"
    }

    static func liveDetail(_ details: LibraryWorkspaceModel.LiveQueueDetails?) -> String {
        guard let details else { return "正在估算…" }
        var parts: [String] = []
        if let speed = details.speedText, !speed.isEmpty { parts.append(speed) }
        if let seconds = details.remainingSeconds {
            let minutes = max(1, Int((seconds / 60).rounded(.up)))
            parts.append(details.remainingIsApproximate ? "约 \(minutes) 分钟" : "剩余 \(minutes) 分钟")
        } else if details.isEstimatingRemaining {
            parts.append("正在估算…")
        }
        return parts.isEmpty ? (details.statusText ?? "处理中") : parts.joined(separator: " · ")
    }

    static func artifactLabel(_ role: LibraryArtifactRole) -> String {
        switch role {
        case .video: "视频"
        case .sourceSubtitle: "源字幕"
        case .translatedSubtitle: "译文字幕"
        case .renderedVideo: "压制成片"
        case .thumbnail: "缩略图"
        case .other: "其他文件"
        }
    }

    static func reprocessDescription(_ plan: ReprocessPlan) -> String {
        let names = plan.steps.map {
            switch $0 {
            case .refreshVideo: "重新获取源视频"
            case .transcribe: "重新转录"
            case .translate: "重新翻译"
            case .transcode: "重新转码"
            case .burn: "重新压制"
            }
        }
        return names.isEmpty ? "不会覆盖已有产物。" : names.joined(separator: " → ")
    }
}
