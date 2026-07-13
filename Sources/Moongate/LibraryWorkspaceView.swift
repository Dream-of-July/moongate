import AppKit
import AVFoundation
import AVKit
import MoongateCore
import SwiftUI

/// The default 0.9 macOS workspace: a persistent library in the first two
/// columns and a focused player/workbench in the detail column. Information is
/// attached with the system Inspector API, so this stays a genuine three-column
/// NavigationSplitView instead of looking like a hand-built fourth pane.
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
            .inspector(isPresented: $workspace.showInspector) {
                if let item = workspace.selectedItem {
                    LibraryInspector(
                        item: item,
                        processing: workspace.selectedProcessing,
                        workspace: workspace,
                        onConfirmTrash: { trashItemID = item.id }
                    )
                } else {
                    ContentUnavailableView(
                        localizer.t(L.Library.noSelectedVideo),
                        systemImage: "info.circle",
                        description: Text(localizer.t(L.Library.noSelectedVideoDetail))
                    )
                }
            }
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
        .onReceive(NotificationCenter.default.publisher(for: AppWorkspaceCommand.startAllRequested)) { _ in
            _ = workspace.startAllQueuedTasks()
        }
        .sheet(isPresented: $workspace.showRecoverySheet) {
            recoverySheet
        }
        .sheet(item: $workspace.processingSheet) { sheet in
            if let item = workspace.item(for: sheet.itemID) {
                ProcessingOptionsSheet(
                    item: item,
                    mode: sheet,
                    workspace: workspace
                )
            } else {
                VStack(spacing: 16) {
                    ContentUnavailableView(
                        localizer.t(L.Library.missingVideoRecord),
                        systemImage: "exclamationmark.triangle",
                        description: Text(localizer.t(L.Library.missingVideoRecordDetail))
                    )
                    Button(localizer.t(L.Common.close)) {
                        workspace.dismissProcessingSheet()
                    }
                }
                .padding(32)
            }
        }
        .alert(localizer.t(L.Library.needsAttentionAlert), isPresented: Binding(
            get: { workspace.errorMessage != nil },
            set: { if !$0 { workspace.errorMessage = nil } }
        )) {
            Button(localizer.t(L.Common.done)) { workspace.errorMessage = nil }
        } message: {
            Text(workspace.errorMessage ?? "")
        }
        .confirmationDialog(
            localizer.t(L.Library.moveToTrashConfirmation),
            isPresented: Binding(
                get: { trashItemID != nil },
                set: { if !$0 { trashItemID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(localizer.t(L.Library.moveToTrash), role: .destructive) {
                let itemID = trashItemID
                trashItemID = nil
                workspace.moveArtifactsToTrash(itemID: itemID)
            }
            Button(localizer.t(L.Common.cancel), role: .cancel) {
                trashItemID = nil
            }
        } message: {
            Text(localizer.t(L.Library.moveToTrashDetail))
        }
    }

    @ToolbarContentBuilder
    private var workspaceToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                workspace.toggleInspector()
            } label: {
                Label(
                    workspace.showInspector ? localizer.t(L.Library.hideInspector) : localizer.t(L.Library.showInspector),
                    systemImage: "sidebar.right"
                )
            }
            .help(workspace.showInspector ? localizer.t(L.Library.hideInfo) : localizer.t(L.Library.showInfo))
        }
    }

    private var sidebar: some View {
        List(selection: $workspace.sidebarDestination) {
            Section {
                sidebarRow(localizer.t(L.Library.allVideos), systemImage: "rectangle.stack", destination: .all, count: workspace.sidebarCount(for: .all))
                sidebarRow(localizer.t(L.Library.active), systemImage: "arrow.triangle.2.circlepath", destination: .active, count: count(for: .active))
                sidebarRow(localizer.t(L.Library.needsAttention), systemImage: "exclamationmark.triangle", destination: .needsAttention, count: count(for: .needsAttention))
                sidebarRow(localizer.t(L.Library.completed), systemImage: "checkmark.circle", destination: .completed, count: count(for: .completed))
                sidebarRow(localizer.t(L.Library.pinned), systemImage: "pin", destination: .pinned, count: count(for: .pinned))
            }

            if !workspace.availableTags.isEmpty {
                Section(localizer.t(L.Library.tags)) {
                    ForEach(workspace.availableTags) { tag in
                        Label(tag.name, systemImage: "tag")
                            .tag(LibraryWorkspaceModel.SidebarDestination.tag(tag.name))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(localizer.t(L.Library.title))
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
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(localizer.t(L.Library.searchVideos), text: $workspace.searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .accessibilityLabel(localizer.t(L.Library.searchLibrary))
                if !workspace.searchText.isEmpty {
                    Button {
                        workspace.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(localizer.t(L.Library.clearSearch))
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
                            processing: workspace.processing(for: projected.id),
                            details: workspace.queueDetails(for: projected.id)
                        )
                        .tag(projected.id)
                        .contextMenu {
                            LibraryRowContextMenu(
                                item: projected.item,
                                processing: workspace.processing(for: projected.id),
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
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if workspace.hasQueuedTasks {
                    Button(localizer.t(L.Library.startAll)) {
                        workspace.startAllQueuedTasks()
                    }
                }
                Button {
                    NotificationCenter.default.post(name: AppWorkspaceCommand.newDownloadRequested, object: nil)
                } label: {
                    Label(localizer.t(L.Library.newDownload), systemImage: "plus")
                }
                .help(localizer.t(L.Library.newDownloadHelp))
                .accessibilityLabel(localizer.t(L.Library.newDownload))
            }
        }
    }

    private var listTitle: String {
        switch workspace.sidebarDestination {
        case .all: localizer.t(L.Library.allVideos)
        case .active: localizer.t(L.Library.active)
        case .needsAttention: localizer.t(L.Library.needsAttention)
        case .completed: localizer.t(L.Library.completed)
        case .pinned: localizer.t(L.Library.pinned)
        case .tag(let tag): tag
        }
    }

    private var libraryEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 34, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text(workspace.searchText.isEmpty ? localizer.t(L.Library.noVideos) : localizer.t(L.Library.noMatchingVideos))
                .font(.headline)
            Text(workspace.searchText.isEmpty ? localizer.t(L.Library.addLinkHint) : localizer.t(L.Library.changeSearchHint))
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
                Text(localizer.t(L.Library.chooseVideoOrNewDownload))
                    .font(.title3.weight(.semibold))
                Text(localizer.t(L.Library.chooseVideoDetail))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(36)
        }
    }

    private var recoverySheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(localizer.t(L.Library.recoveryFound, workspace.recoveryCandidates.count), systemImage: "arrow.clockwise")
                .font(.headline)
            Text(localizer.t(L.Library.recoveryDetail))
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
                        Text(localizer.t(L.Library.recoveryAdditional, workspace.recoveryCandidates.count - 12))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxHeight: 180)

            HStack {
                Spacer()
                Button(localizer.t(L.Library.notNow)) { workspace.dismissRecovery() }
                    .keyboardShortcut(.cancelAction)
                Button(localizer.t(L.Library.recoverToLibrary)) { workspace.importRecoveredVideos() }
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
        }
    }
}

private struct LibraryRemovalUndoBar: View {
    @ObservedObject var workspace: LibraryWorkspaceModel
    @EnvironmentObject private var localizer: Localizer

    var body: some View {
        HStack(spacing: 10) {
            Text(localizer.t(L.Library.removed))
                .foregroundStyle(.secondary)
            Button(localizer.t(L.Library.undo)) {
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
        .accessibilityLabel(localizer.t(L.Library.removedAccessibility))
    }
}

private struct LibraryEnqueueNoticeBar: View {
    let notice: String
    let dismiss: () -> Void
    @EnvironmentObject private var localizer: Localizer

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
            .accessibilityLabel(localizer.t(L.Library.dismissNotice))
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
    let processing: ProcessingSummary?
    let details: LibraryWorkspaceModel.LiveQueueDetails?
    @EnvironmentObject private var localizer: Localizer

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

                Text(LibraryDisplay.recoveryLabel(processing, details: details, localizer: localizer))
                .font(.caption)
                .foregroundStyle(LibraryDisplay.statusColor(processing, details: details))
                .lineLimit(1)

                statusSlot
            }
            Spacer(minLength: 0)
            LibraryStatusGlyph(processing: processing)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(projected.item.title)
        .accessibilityValue(activeAccessibilityValue)
    }

    @ViewBuilder
    private var statusSlot: some View {
        Group {
            if let processing, processing.state.isRunning {
                HStack(spacing: 6) {
                    ProgressRingView(progress: processing.progress, finished: false)
                    Text("\(Int((processing.progress * 100).rounded()))%")
                        .monospacedDigit()
                    Text(LibraryDisplay.liveDetail(details, localizer: localizer))
                        .lineLimit(1)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else if processing?.state == .completed {
                Text(LibraryDisplay.completedDetail(projected.item, localizer: localizer))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if processing?.state == .queued {
                if let readiness = LibraryDisplay.queuedReadinessDetail(details, localizer: localizer) {
                    Label(readiness, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .accessibilityLabel(localizer.t(L.Library.needsAttentionAccessibility, readiness))
                } else {
                    Text(localizer.t(L.Library.queuedConfigurationHint))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else if processing?.state == .cancelled {
                Text(localizer.t(L.Library.cancelledHint))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(LibraryDisplay.recoveryLabel(processing, details: details, localizer: localizer))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(height: 18, alignment: .leading)
    }

    private var activeAccessibilityValue: String {
        guard let processing, processing.state.isRunning else {
            if processing?.state == .queued,
               let readiness = LibraryDisplay.queuedReadinessDetail(details, localizer: localizer) {
                return localizer.t(L.Library.needsAttentionAccessibility, readiness)
            }
            return LibraryDisplay.recoveryLabel(processing, details: details, localizer: localizer)
        }
        let percent = Int((processing.progress * 100).rounded())
        return "\(LibraryDisplay.stageLabel(processing, localizer: localizer)) \(percent)% · \(LibraryDisplay.liveDetail(details, localizer: localizer))"
    }
}

private struct LibraryRowContextMenu: View {
    let item: MoongateCore.LibraryItem
    let processing: ProcessingSummary?
    @ObservedObject var workspace: LibraryWorkspaceModel
    let requestTrash: () -> Void
    @EnvironmentObject private var localizer: Localizer

    var body: some View {
        if workspace.canPlayEmbeddedVideo(itemID: item.id) {
            Button(localizer.t(L.Library.play)) {
                workspace.playEmbeddedVideo(itemID: item.id)
            }
        }

        if workspace.canRevealInFinder(itemID: item.id) {
            Button(localizer.t(L.Library.revealInFinder)) {
                workspace.revealInFinder(itemID: item.id)
            }
        }

        if item.source?.urlString != nil {
            Button(localizer.t(L.Library.copySourceLink)) {
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
                        Button(localizer.t(L.Library.start)) {
                            workspace.recoverQueueTask(for: item.id)
                        }
                    }
                }
            case .failed:
                Button(queueItem.needsLogin == nil ? localizer.t(L.Library.recover) : localizer.t(L.Library.login)) {
                    workspace.recoverQueueTask(for: item.id)
                }
            case .cancelling, .downloading, .translating, .burning, .done, .cancelled:
                EmptyView()
            }
        }

        if workspace.queueItem(for: item.id) == nil,
           let attentionAction = workspace.attentionActionTitle(for: item.id) {
            Button(attentionAction) {
                workspace.performAttentionAction(for: item.id)
            }
        }

        if processing?.state.isQueued == true {
            Button(localizer.t(L.Library.changeOptions)) {
                workspace.showQueuedOptions(for: item.id)
            }
        } else if processing?.state.isRunning != true {
            Button(localizer.t(L.Library.reprocess)) {
                workspace.showReprocessOptions(for: item.id)
            }
        }

        if item.isPinned {
            Button(localizer.t(L.Library.unpin)) {
                workspace.setPinned(false, itemID: item.id)
            }
        } else {
            Button(localizer.t(L.Library.pin)) {
                workspace.setPinned(true, itemID: item.id)
            }
        }

        Divider()

        Button(localizer.t(L.Library.removeFromLibrary)) {
            workspace.removeFromLibrary(itemID: item.id)
        }

        if processing?.state.isActive != true {
            Divider()

            Button(localizer.t(L.Library.moveToTrashEllipsis), role: .destructive) {
                requestTrash()
            }
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
    @EnvironmentObject private var localizer: Localizer

    var body: some View {
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
                                .accessibilityLabel(localizer.t(L.Library.alreadyPinned))
                        }
                    }
                    Text(LibraryDisplay.recoveryLabel(processing, details: queueDetails, localizer: localizer))
                        .font(.callout)
                        .foregroundStyle(LibraryDisplay.statusColor(processing, details: queueDetails))

                    if let attention = processing?.attention {
                        Text(LibraryDisplay.attentionDetail(attention, localizer: localizer))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else if let processing, processing.state.isRunning {
                        ProgressView(value: processing.progress)
                        Text(LibraryDisplay.liveDetail(queueDetails, localizer: localizer))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                WorkbenchActionStrip(
                    item: item,
                    processing: processing,
                    queueItem: workspace.queueItem(for: item.id),
                    appModel: appModel,
                    workspace: workspace,
                    onRequestTrash: onRequestTrash
                )
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(item.title)
    }
}

private struct PlayerStageView: View {
    let item: MoongateCore.LibraryItem
    @ObservedObject var workspace: LibraryWorkspaceModel
    @EnvironmentObject private var localizer: Localizer

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
                Text(localizer.t(L.Library.previewAvailableLater))
                    .font(.callout)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.45), radius: 4)
        }
        .accessibilityLabel(localizer.t(L.Library.previewUnavailableAccessibility))
    }

    private func missingVideoStage(_ url: URL) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34, weight: .regular))
                .symbolRenderingMode(.hierarchical)
            Text(localizer.t(L.Library.videoMoved))
                .font(.headline)
            Text(localizer.t(L.Library.videoMovedDetail))
                .font(.callout)
                .foregroundStyle(.secondary)
            Button(localizer.t(L.Library.openOutputFolder)) {
                NSWorkspace.shared.open(url.deletingLastPathComponent())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(localizer.t(L.Library.videoMoved))
    }

    private func unsupportedVideoStage(_ url: URL) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "play.slash")
                .font(.system(size: 34, weight: .regular))
                .symbolRenderingMode(.hierarchical)
            Text(localizer.t(L.Library.unsupportedPlayback))
                .font(.headline)
            Text(localizer.t(L.Library.unsupportedPlaybackDetail, url.pathExtension.uppercased()))
                .font(.callout)
                .foregroundStyle(.secondary)
            Button(localizer.t(L.Library.openInDefaultApp)) {
                NSWorkspace.shared.open(url)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(localizer.t(L.Library.unsupportedPlayback))
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

private struct WorkbenchActionStrip: View {
    let item: MoongateCore.LibraryItem
    let processing: ProcessingSummary?
    let queueItem: QueueManager.QueueItem?
    @ObservedObject var appModel: ViewModel
    @ObservedObject var workspace: LibraryWorkspaceModel
    let onRequestTrash: () -> Void
    @EnvironmentObject private var localizer: Localizer

    var body: some View {
        HStack(spacing: 8) {
            if let queueItem {
                queueActions(queueItem)
            } else if let attentionAction = workspace.attentionActionTitle(for: item.id) {
                Button(attentionAction) {
                    workspace.performAttentionAction(for: item.id)
                }
                if workspace.canRevealInFinder(itemID: item.id) {
                    Button(localizer.t(L.Library.revealInFinder)) {
                        workspace.revealInFinder(itemID: item.id)
                    }
                }
            } else {
                completedActions
            }

            Menu {
                Button(localizer.t(L.Library.viewInfo)) {
                    workspace.showInformation(for: item.id)
                }
                if item.source?.urlString != nil {
                    Button(localizer.t(L.Library.copySourceLink)) {
                        workspace.copySourceLink(itemID: item.id)
                    }
                }
                if item.isPinned {
                    Button(localizer.t(L.Library.unpin)) { workspace.setPinned(false, itemID: item.id) }
                } else {
                    Button(localizer.t(L.Library.pin)) { workspace.setPinned(true, itemID: item.id) }
                }
                Divider()
                Button(localizer.t(L.Library.removeFromLibrary)) {
                    workspace.removeFromLibrary(itemID: item.id)
                }
                if processing?.state.isActive != true {
                    Divider()
                    Button(localizer.t(L.Library.moveToTrashEllipsis), role: .destructive) {
                        onRequestTrash()
                    }
                }
            } label: {
                Label(localizer.t(L.Library.more), systemImage: "ellipsis.circle")
            }
        }
        .buttonStyle(.bordered)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localizer.t(L.Library.videoQuickActions))
    }

    @ViewBuilder
    private var completedActions: some View {
        if workspace.canPlayEmbeddedVideo(itemID: item.id) {
            Button(localizer.t(L.Library.play)) {
                workspace.playEmbeddedVideo(itemID: item.id)
            }
        }
        if workspace.canRevealInFinder(itemID: item.id) {
            Button(localizer.t(L.Library.revealInFinder)) {
                workspace.revealInFinder(itemID: item.id)
            }
        }
        if processing?.state.isRunning != true {
            Button(localizer.t(L.Library.reprocess)) {
                workspace.showReprocessOptions(for: item.id)
            }
        }
    }

    @ViewBuilder
    private func queueActions(_ queueItem: QueueManager.QueueItem) -> some View {
        switch queueItem.stage {
        case .queued where queueItem.isDeferredDraft:
            if let recovery = workspace.queuedReadinessRecovery(for: item.id) {
                Button(recovery.actionTitle) {
                    workspace.openQueuedReadinessRecovery(for: item.id)
                }
            } else {
                Button(localizer.t(L.Library.start)) {
                    workspace.startSelectedQueuedTask()
                }
            }
            Button(localizer.t(L.Library.changeOptions)) {
                workspace.showQueuedOptions(for: item.id)
            }
        case .cancelling:
            Label(localizer.t(L.Library.cancelling), systemImage: "hourglass")
                .foregroundStyle(.secondary)
        case .queued, .downloading, .translating, .burning:
            if queueItem.isPaused {
                Button(localizer.t(L.Library.continueTask)) {
                    appModel.queue.resume(queueItem.id)
                }
            } else {
                Button(localizer.t(L.Library.pause)) {
                    appModel.queue.pause(queueItem.id)
                }
            }
            Button(localizer.t(L.Library.cancel), role: .destructive) {
                appModel.queue.cancel(queueItem.id)
            }
        case .failed:
            Button(queueItem.needsLogin == nil ? localizer.t(L.Library.recover) : localizer.t(L.Library.login)) {
                workspace.recoverQueueTask(for: item.id)
            }
            if workspace.canRevealInFinder(itemID: item.id) {
                Button(localizer.t(L.Library.revealInFinder)) {
                    workspace.revealInFinder(itemID: item.id)
                }
            }
        case .done, .cancelled:
            completedActions
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
    @EnvironmentObject private var localizer: Localizer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                information
            }
            .padding(14)
        }
        .onAppear { note = item.note ?? "" }
        .onChange(of: item.id) { _, _ in
            note = item.note ?? ""
            tagInput = ""
        }
        .accessibilityLabel(localizer.t(L.Library.inspectorAccessibility))
    }

    private var information: some View {
        Group {
            inspectorSection(localizer.t(L.Library.fileInformation)) {
                InspectorKeyValueRow(localizer.t(L.Library.fieldTitle), value: item.title)
                InspectorKeyValueRow(localizer.t(L.Library.fieldStatus), value: LibraryDisplay.stageLabel(processing, localizer: localizer))
                InspectorKeyValueRow(localizer.t(L.Library.fieldVersion), value: "v\(item.latestVersion?.number ?? 1)")
                if let source = item.source?.urlString {
                    InspectorKeyValueRow(localizer.t(L.Library.fieldSource), value: source, lineLimit: 2)
                } else {
                    InspectorKeyValueRow(localizer.t(L.Library.fieldSource), value: localizer.t(L.Library.unknown))
                }
                if workspace.canRevealInFinder(itemID: item.id) {
                    Button(localizer.t(L.Library.revealInFinder)) {
                        workspace.revealInFinder(itemID: item.id)
                    }
                }
            }

            inspectorSection(localizer.t(L.Library.artifacts)) {
                let artifacts = item.latestVersion?.artifacts ?? []
                if artifacts.isEmpty {
                    Text(localizer.t(L.Library.artifactPending))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(artifacts) { artifact in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LibraryDisplay.artifactLabel(artifact.role, localizer: localizer))
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

            inspectorSection(localizer.t(L.Library.tags)) {
                if item.tags.isEmpty {
                    Text(localizer.t(L.Library.noTags))
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
                    TextField(localizer.t(L.Library.addTag), text: $tagInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addTag() }
                    Button(localizer.t(L.Library.add)) { addTag() }
                        .disabled(tagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            inspectorSection(localizer.t(L.Library.note)) {
                TextEditor(text: $note)
                    .font(.callout)
                    .frame(minHeight: 72)
                    .accessibilityLabel(localizer.t(L.Library.note))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    )
                    .onChange(of: note) { _, newValue in
                        workspace.updateNote(newValue)
                    }
            }

            Toggle(localizer.t(L.Library.pinVideo), isOn: Binding(
                get: { item.isPinned },
                set: { workspace.setPinned($0) }
            ))

            inspectorSection(localizer.t(L.Library.title)) {
                Button(localizer.t(L.Library.removeFromLibrary)) {
                    workspace.removeFromLibrary()
                }
                .accessibilityHint(localizer.t(L.Library.removeHint))

                if processing?.state.isActive != true {
                    Button(localizer.t(L.Library.moveToTrash), role: .destructive) {
                        onConfirmTrash()
                    }
                    .accessibilityHint(localizer.t(L.Library.trashHint))
                }
            }
        }
    }


    private func inspectorSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
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

/// Configuration is intentionally a task sheet instead of a permanent
/// inspector mode. The first section describes results people recognize; raw
/// source/model choices remain behind an explicit advanced disclosure.
private struct ProcessingOptionsSheet: View {
    let item: MoongateCore.LibraryItem
    let mode: LibraryWorkspaceModel.ProcessingSheet
    @ObservedObject var workspace: LibraryWorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localizer: Localizer
    @State private var isCreating = false
    @State private var creationError: String?

    private var isQueued: Bool {
        if case .queued = mode { return true }
        return false
    }

    private var subtitleMode: Binding<ChineseSubtitleMode> {
        Binding(
            get: { workspace.draftSubtitleMode },
            set: { workspace.setDraftSubtitleMode($0) }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(isQueued
                         ? localizer.t(L.Library.queuedOptionsDetail)
                         : localizer.t(L.Library.reprocessOptionsDetail))
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Picker(localizer.t(L.Download.subtitleResult), selection: subtitleMode) {
                        Text(localizer.t(L.Download.subtitleResultNone)).tag(ChineseSubtitleMode.off)
                        Text(localizer.t(L.Download.subtitleResultOriginal)).tag(ChineseSubtitleMode.burnOriginal)
                        Text(localizer.t(L.Download.subtitleResultTranslated)).tag(ChineseSubtitleMode.srtOnly)
                        Text(localizer.t(L.Download.subtitleResultEmbedded)).tag(ChineseSubtitleMode.burnIn)
                    }
                    Picker(localizer.t(L.Download.outputFormat), selection: workspace.configurationBinding(\.outputFormat)) {
                        Text(localizer.t(L.Download.outputOriginal)).tag(OutputFormat.original.rawValue)
                        Text(localizer.t(L.Download.outputMP4H264)).tag(OutputFormat.mp4H264.rawValue)
                        Text(localizer.t(L.Download.outputMP4H265)).tag(OutputFormat.mp4H265.rawValue)
                        Text(localizer.t(L.Download.outputMKV)).tag(OutputFormat.mkv.rawValue)
                    }
                    Picker(localizer.t(L.Download.quality), selection: workspace.configurationBinding(\.quality)) {
                        Text(localizer.t(L.Download.qualityBestAvailable)).tag("best")
                        Text(localizer.t(L.Download.quality1080p)).tag("bv*[height<=1080]+ba/b[height<=1080]")
                        Text(localizer.t(L.Download.quality720p)).tag("bv*[height<=720]+ba/b[height<=720]")
                    }
                }

                if workspace.draftSubtitleMode.requiresTranslation {
                    Section(localizer.t(L.Library.translatedSubtitles)) {
                        Picker(localizer.t(L.Download.targetLanguage), selection: workspace.configurationBinding(\.targetLanguage)) {
                            Text(localizer.t(L.Download.languageChineseSimplified)).tag("zh-Hans")
                            Text(localizer.t(L.Download.languageChineseTraditional)).tag("zh-Hant")
                            Text(localizer.t(L.Download.languageEnglish)).tag("en")
                        }
                        if workspace.draftSubtitleMode.requiresBurner {
                            Picker(localizer.t(L.Download.subtitleStyle), selection: workspace.configurationBinding(\.subtitleStyle)) {
                                Text(localizer.t(L.Download.subtitleStyleBilingual)).tag(SubtitleStyle.bilingual.rawValue)
                                Text(localizer.t(L.Download.subtitleStyleTranslationOnly)).tag(SubtitleStyle.chineseOnly.rawValue)
                            }
                        }
                    }
                }

                DisclosureGroup(localizer.t(L.Download.advancedOptions)) {
                    Picker(localizer.t(L.Ready.subtitleSourceSection), selection: workspace.configurationBinding(\.subtitleSource)) {
                        Text(localizer.t(L.Download.recognitionAutomatic)).tag("")
                        Text(localizer.t(L.Library.useExistingSubtitles)).tag(SubtitleSourceKind.importedFile.rawValue)
                        Text(localizer.t(L.Library.useCurrentManualSubtitles)).tag(SubtitleSourceKind.manual.rawValue)
                        Text(localizer.t(L.Ready.platformSubtitle)).tag(SubtitleSourceKind.platformAuto.rawValue)
                        Text(localizer.t(L.Library.useCurrentHLSSubtitles)).tag(SubtitleSourceKind.hlsManifest.rawValue)
                        Text(localizer.t(L.Library.localRecognition)).tag(SubtitleSourceKind.localASR.rawValue)
                        Text(localizer.t(L.Library.cloudRecognition)).tag(SubtitleSourceKind.cloudASR.rawValue)
                    }
                    if workspace.draftSubtitleMode != .off {
                        TranscriptionModelPicker(selection: workspace.configurationBinding(\.transcriptionModel))
                    }
                    if workspace.draftSubtitleMode.requiresTranslation {
                        TextField(localizer.t(L.Library.translationServiceOptional), text: workspace.configurationBinding(\.translationModel))
                    }
                }

                if !isQueued {
                    Section(localizer.t(L.Library.reprocessImpact)) {
                        Text(localizer.t(L.Library.reprocessWillCreateVersion, (item.latestVersion?.number ?? 0) + 1))
                        if let plan = workspace.reprocessPlan {
                            Text(LibraryDisplay.reprocessDescription(plan, localizer: localizer))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(localizer.t(L.Library.reprocessNoPlan))
                                .foregroundStyle(.secondary)
                        }
                        if let reason = workspace.reprocessBlockerReason {
                            Text(reason)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let creationError {
                    Section {
                        Label(creationError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isQueued ? localizer.t(L.Library.changeOptionsTitle) : localizer.t(L.Library.reprocessTitle))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isQueued ? localizer.t(L.Common.done) : localizer.t(L.Common.cancel)) {
                        if !isQueued {
                            workspace.discardProcessingDraft()
                        }
                        workspace.dismissProcessingSheet()
                        dismiss()
                    }
                }
                if !isQueued {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isCreating ? localizer.t(L.Library.creatingTask) : localizer.t(L.Library.createTask)) {
                            guard !isCreating else { return }
                            isCreating = true
                            creationError = nil
                            Task { @MainActor in
                                switch await workspace.createReprocessTask() {
                                case .success:
                                    workspace.dismissProcessingSheet()
                                    dismiss()
                                case .failure(let message):
                                    creationError = message
                                }
                                isCreating = false
                            }
                        }
                        .disabled(!workspace.canCreateReprocess || isCreating)
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 520)
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

@MainActor
private enum LibraryDisplay {
    static func stageLabel(_ processing: ProcessingSummary?, localizer: Localizer) -> String {
        switch processing?.state {
        case .queued: localizer.t(L.Library.queued)
        case .cancelling: localizer.t(L.Library.cancelling)
        case .downloading: localizer.t(L.Library.downloading)
        case .transcribing: localizer.t(L.Library.transcribing)
        case .translating: localizer.t(L.Library.translating)
        case .transcoding: localizer.t(L.Library.transcoding)
        case .burning: localizer.t(L.Library.burning)
        case .completed: localizer.t(L.Library.completed)
        case .partialSuccess: localizer.t(L.Library.partialSuccess)
        case .needsAttention: localizer.t(L.Library.needsAttention)
        case .interrupted: localizer.t(L.Library.interrupted)
        case .failed: localizer.t(L.Library.processingFailed)
        case .cancelled: localizer.t(L.Library.cancelled)
        case .none: localizer.t(L.Library.unprocessed)
        }
    }

    static func recoveryLabel(
        _ processing: ProcessingSummary?,
        details: LibraryWorkspaceModel.LiveQueueDetails?,
        localizer: Localizer
    ) -> String {
        if let attention = processing?.attention {
            return attentionLabel(attention, localizer: localizer)
        }
        switch processing?.state {
        case .queued where queuedReadinessDetail(details, localizer: localizer) != nil:
            return queuedReadinessDetail(details, localizer: localizer) ?? localizer.t(L.Library.waitingToStart)
        case .partialSuccess, .needsAttention, .interrupted, .failed:
            return stageLabel(processing, localizer: localizer)
        default:
            return stageLabel(processing, localizer: localizer)
        }
    }

    private static func attentionLabel(_ attention: ProcessingAttention, localizer: Localizer) -> String {
        switch (attention.kind, attention.primaryAction) {
        case (.loginRequired, _):
            return localizer.t(L.Library.loginRequiredGeneric)
        case (.fileMissing, _):
            return localizer.t(L.Library.videoMoved)
        case (.capabilityUnavailable, .prepareLocalRecognition):
            return localizer.t(L.Library.localRecognitionUnavailable)
        case (.capabilityUnavailable, .configureCloudRecognition):
            return localizer.t(L.Library.cloudRecognitionUnavailable)
        case (.interrupted, _):
            return localizer.t(L.Library.interrupted)
        case (.processingFailed, _):
            return localizer.t(L.Library.processingFailed)
        case (.needsReview, _):
            return localizer.t(L.Library.needsAttention)
        default:
            return stageLabel(nil, localizer: localizer)
        }
    }

    static func attentionDetail(_ attention: ProcessingAttention, localizer: Localizer) -> String {
        switch (attention.kind, attention.primaryAction) {
        case (.loginRequired, _):
            return localizer.t(L.Library.loginRequiredDetail)
        case (.fileMissing, _):
            return localizer.t(L.Library.videoMovedDetail)
        case (.capabilityUnavailable, .prepareLocalRecognition):
            return localizer.t(L.Library.localRecognitionUnavailableDetail)
        case (.capabilityUnavailable, .configureCloudRecognition):
            return localizer.t(L.Library.cloudRecognitionUnavailableDetail)
        case (.interrupted, _):
            return localizer.t(L.Library.interruptedDetail)
        case (.processingFailed, _):
            return localizer.t(L.Library.processingFailedDetail)
        case (.needsReview, _):
            return localizer.t(L.Library.needsReviewDetail)
        default:
            return localizer.t(L.Library.needsReviewDetail)
        }
    }

    static func statusColor(
        _ processing: ProcessingSummary?,
        details: LibraryWorkspaceModel.LiveQueueDetails? = nil
    ) -> Color {
        if processing?.state == .queued, details?.queuedReadiness != nil {
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

    static func queuedReadinessDetail(
        _ details: LibraryWorkspaceModel.LiveQueueDetails?,
        localizer: Localizer
    ) -> String? {
        switch details?.queuedReadiness {
        case .localSpeech:
            return localizer.t(L.Library.localRecognitionUnavailable)
        case .cloudASR:
            return localizer.t(L.Library.cloudRecognitionUnavailable)
        case .none:
            return nil
        }
    }

    static func completedDetail(_ item: MoongateCore.LibraryItem, localizer: Localizer) -> String {
        guard let artifact = item.latestVersion?.artifacts.first(where: {
            $0.role == .renderedVideo || $0.role == .video
        }) else {
            return localizer.t(L.Library.saved)
        }
        let format = URL(fileURLWithPath: artifact.relativePath).pathExtension.uppercased()
        return format.isEmpty
            ? localizer.t(L.Library.saved)
            : localizer.t(L.Library.savedWithFormat, format)
    }

    static func liveDetail(_ details: LibraryWorkspaceModel.LiveQueueDetails?, localizer: Localizer) -> String {
        guard let details else { return localizer.t(L.Library.estimating) }
        var parts: [String] = []
        if let speed = details.speedText, !speed.isEmpty { parts.append(speed) }
        if let seconds = details.remainingSeconds {
            let minutes = max(1, Int((seconds / 60).rounded(.up)))
            parts.append(details.remainingIsApproximate
                ? localizer.t(L.Library.approximateMinutes, minutes)
                : localizer.t(L.Library.remainingMinutes, minutes))
        } else if details.isEstimatingRemaining {
            parts.append(localizer.t(L.Library.estimating))
        }
        return parts.isEmpty ? localizer.t(L.Library.processing) : parts.joined(separator: " · ")
    }

    static func artifactLabel(_ role: LibraryArtifactRole, localizer: Localizer) -> String {
        switch role {
        case .video: localizer.t(L.Library.artifactVideo)
        case .sourceSubtitle: localizer.t(L.Library.artifactSourceSubtitle)
        case .translatedSubtitle: localizer.t(L.Library.artifactTranslatedSubtitle)
        case .renderedVideo: localizer.t(L.Library.artifactRenderedVideo)
        case .thumbnail: localizer.t(L.Library.artifactThumbnail)
        case .other: localizer.t(L.Library.artifactOther)
        }
    }

    static func reprocessDescription(_ plan: ReprocessPlan, localizer: Localizer) -> String {
        let names = plan.steps.map {
            switch $0 {
            case .refreshVideo: localizer.t(L.Library.reprocessRefreshVideo)
            case .transcribe: localizer.t(L.Library.reprocessTranscribe)
            case .translate: localizer.t(L.Library.reprocessTranslate)
            case .transcode: localizer.t(L.Library.reprocessTranscode)
            case .burn: localizer.t(L.Library.reprocessBurn)
            }
        }
        return names.isEmpty ? localizer.t(L.Library.reprocessNoOverwrite) : names.joined(separator: " → ")
    }
}
