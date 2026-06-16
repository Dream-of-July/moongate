import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers
import MoongateMobileCore
#if os(iOS)
import QuickLook
#endif

private struct IOSExportFile: Transferable {
    let url: URL
    let contentType: UTType
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .data) { file in
            SentTransferredFile(file.url)
        }
    }
}

public struct MoongateIOSRootView: View {
    @ObservedObject private var model: IOSMobileAppModel

    public init(model: IOSMobileAppModel) {
        self.model = model
    }

    public var body: some View {
        TabView(selection: $model.selectedTab) {
            IOSAddView(model: model)
                .tabItem { Label(IOSMobileTab.add.title, systemImage: IOSMobileTab.add.systemImage) }
                .tag(IOSMobileTab.add)
            IOSQueueView(model: model)
                .tabItem { Label(IOSMobileTab.queue.title, systemImage: IOSMobileTab.queue.systemImage) }
                .tag(IOSMobileTab.queue)
            IOSLibraryView(model: model)
                .tabItem { Label(IOSMobileTab.library.title, systemImage: IOSMobileTab.library.systemImage) }
                .tag(IOSMobileTab.library)
            IOSSettingsView(model: model)
                .tabItem { Label(IOSMobileTab.settings.title, systemImage: IOSMobileTab.settings.systemImage) }
                .tag(IOSMobileTab.settings)
        }
        .task {
            await model.restoreQueueFromRepository()
            await model.refreshCloudTranslationCredentialReadiness()
        }
    }
}

private struct IOSAddView: View {
    @ObservedObject var model: IOSMobileAppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var urlDraft = ""
    @State private var isVideoImporterPresented = false
    @State private var isSubtitleImporterPresented = false

    var body: some View {
        NavigationStack {
            List {
                if hasActiveAddSessionContent {
                    addSessionContent
                    addEntryForms
                } else {
                    addEntryForms
                    addSessionContent
                }
            }
            .safeAreaInset(edge: .bottom) {
                IOSAddBottomScrollSpacer()
            }
            .navigationTitle("添加")
            .fileImporter(
                isPresented: $isVideoImporterPresented,
                allowedContentTypes: [.movie, .mpeg4Movie, .video],
                allowsMultipleSelection: false
            ) { result in
                guard case let .success(urls) = result,
                      let url = urls.first else {
                    return
                }
                Task {
                    await model.importVideoFile(fileURL: url)
                }
            }
            .fileImporter(
                isPresented: $isSubtitleImporterPresented,
                allowedContentTypes: [UTType(filenameExtension: "srt") ?? .plainText],
                allowsMultipleSelection: false
            ) { result in
                guard case let .success(urls) = result,
                      let url = urls.first else {
                    return
                }
                model.attachImportedSubtitle(fileURL: url, languageCode: "en")
            }
        }
    }

    @ViewBuilder
    private var addEntryForms: some View {
        Section("导入视频") {
            Button {
                isVideoImporterPresented = true
            } label: {
                Label(
                    usesAccessibilityDynamicType ? "选择视频" : "选择视频文件",
                    systemImage: "square.and.arrow.down"
                )
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.borderedProminent)
            if !usesAccessibilityDynamicType {
                Text("本地视频会复制到 App 资料库。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Section("直链") {
            TextField("粘贴 .mp4 或 .mov 直链", text: $urlDraft)
                .mobileSensitiveInput()
            Button {
                let url = urlDraft
                Task {
                    await model.analyzeURL(url)
                }
            } label: {
                Label("检查直链", systemImage: "magnifyingglass")
            }
            .disabled(urlDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if !usesAccessibilityDynamicType {
                Text("仅支持直接 HTTPS 视频文件链接，不解析网页。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var addSessionContent: some View {
        switch model.addSession.state {
        case .idle:
            if !usesAccessibilityDynamicType {
                Section {
                    IOSAddInlineHint(
                        title: "准备添加视频",
                        message: "优先选择本地视频；也可以粘贴 .mp4 / .mov 等直接 HTTPS 视频文件链接。",
                        systemImage: "plus.circle"
                    )
                }
            }
        case .analyzing:
            Section {
                HStack {
                    ProgressView()
                    Text("正在检查")
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("链接检查进度")
                .accessibilityValue("正在检查")
            }
        case .candidateSelection:
            Section("选择视频") {
                ForEach(model.addSession.candidates) { candidate in
                    candidateActionButton(candidate)
                }
            }
        case .ready:
            if let info = model.addSession.videoInfo {
                Section("视频") {
                    LabeledContent("标题", value: info.title)
                    if let duration = info.durationSeconds {
                        LabeledContent("时长", value: durationText(duration))
                    }
                    Picker("格式", selection: addFormatBinding(for: info)) {
                        ForEach(info.formats) { format in
                            Text(format.label).tag(format.id as String?)
                        }
                    }
                }
                Section("字幕") {
                    Button {
                        isSubtitleImporterPresented = true
                    } label: {
                        Label("导入字幕", systemImage: "text.badge.plus")
                    }
                    if info.subtitles.isEmpty {
                        Text("没有可用字幕")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(info.subtitles) { subtitle in
                            Toggle(isOn: addSubtitleBinding(for: subtitle.id)) {
                                LabeledContent(subtitle.label, value: subtitle.isAutoGenerated ? "自动" : "原始")
                            }
                        }
                    }
                }
                Section("导出") {
                    Picker("导出为", selection: $model.selectedAddExportProfile.subtitleMode) {
                        Text("字幕文件").tag(MobileExportProfile.SubtitleMode.translatedSubtitleFile)
                        Text("软字幕包").tag(MobileExportProfile.SubtitleMode.softSubtitle)
                        Text("带字幕视频").tag(MobileExportProfile.SubtitleMode.burnedInSubtitle)
                    }
                    if model.selectedAddExportProfile.requiresVideoRender {
                        Text("导出时需要保持 App 打开。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button {
                        Task {
                            await model.enqueueSelectedVideo()
                        }
                    } label: {
                        Label("加入队列", systemImage: "arrow.down.circle")
                    }
                }
            }
        case .unsupported:
            Section {
                ContentUnavailableView {
                    Label("这个链接暂不支持", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("当前仅支持 HTTPS 视频文件直链，例如 .mp4 / .mov；也可以导入本地视频文件。")
                } actions: {
                    Button {
                        isVideoImporterPresented = true
                    } label: {
                        Label("导入视频", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        case .failed:
            Section {
                ContentUnavailableView {
                    Label("解析失败", systemImage: "xmark.circle")
                } description: {
                    Text("检查链接后重试。")
                } actions: {
                    if let retryValue = model.addSession.input?.value,
                       !retryValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button {
                            Task {
                                await model.analyzeURL(retryValue)
                            }
                        } label: {
                            Label("重新检查", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func candidateActionButton(_ candidate: MobileVideoCandidate) -> some View {
        if candidate.isSupportedOnMobile {
            supportedCandidateButton(candidate)
        } else {
            unsupportedCandidateRow(candidate)
        }
    }

    private func supportedCandidateButton(_ candidate: MobileVideoCandidate) -> some View {
        Button {
            Task {
                await model.selectAddCandidate(id: candidate.id)
            }
        } label: {
            candidateActionContent(candidate)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(candidate.title)
        .accessibilityValue(candidateAccessibilityValue(candidate))
        .accessibilityHint(candidateAccessibilityHint(candidate))
    }

    private func unsupportedCandidateRow(_ candidate: MobileVideoCandidate) -> some View {
        candidateActionContent(candidate)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(candidate.title)
            .accessibilityValue(candidateAccessibilityValue(candidate))
            .accessibilityHint(candidateAccessibilityHint(candidate))
    }

    private func candidateActionContent(_ candidate: MobileVideoCandidate) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.title)
                Text(candidate.detail ?? iosCandidateKindLabel(candidate.kind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.addSession.selectedCandidateID == candidate.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
            } else if !candidate.isSupportedOnMobile {
                Text(unsupportedCandidateStatusText(candidate))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule()
                            .fill(Color.secondary.opacity(0.12))
                    }
            }
        }
    }

    private func unsupportedCandidateStatusText(_ candidate: MobileVideoCandidate) -> String {
        guard let reason = candidate.unsupportedReason else {
            return "可选择"
        }
        switch reason {
        case .requiresDesktopExtractor:
            return "需要桌面端"
        case .drmOrAccessControl:
            return "受访问限制"
        case .loginRequired:
            return "需要登录"
        case .unsupportedFormat:
            return "格式不支持"
        case .unknown:
            return "暂不支持"
        }
    }

    private func candidateAccessibilityValue(_ candidate: MobileVideoCandidate) -> String {
        if candidate.isSupportedOnMobile {
            return model.addSession.selectedCandidateID == candidate.id ? "已选择，可在手机端处理" : "可在手机端处理"
        }
        return "\(unsupportedCandidateStatusText(candidate))，\(candidate.detail ?? iosCandidateKindLabel(candidate.kind))"
    }

    private func candidateAccessibilityHint(_ candidate: MobileVideoCandidate) -> String {
        if candidate.isSupportedOnMobile {
            return "选择这个候选视频。"
        }
        return "这个候选不能在手机端继续处理，请导入本地视频，或回到桌面端解析。"
    }

    private func addFormatBinding(for info: MobileVideoInfo) -> Binding<String?> {
        Binding(
            get: {
                model.selectedAddFormatID ?? info.recommendedFormat?.id
            },
            set: { value in
                guard let value else { return }
                model.selectAddFormat(id: value)
            }
        )
    }

    private func addSubtitleBinding(for subtitleID: String) -> Binding<Bool> {
        Binding(
            get: {
                model.selectedAddSubtitleIDs.contains(subtitleID)
            },
            set: { isSelected in
                let currentlySelected = model.selectedAddSubtitleIDs.contains(subtitleID)
                guard isSelected != currentlySelected else { return }
                model.toggleAddSubtitle(id: subtitleID)
            }
        )
    }

    private func durationText(_ duration: Double) -> String {
        let totalSeconds = Int(duration.rounded())
        return "\(totalSeconds / 60):" + String(format: "%02d", totalSeconds % 60)
    }

    private var usesAccessibilityDynamicType: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var hasActiveAddSessionContent: Bool {
        model.addSession.state != .idle
    }
}

private struct IOSAddBottomScrollSpacer: View {
    var body: some View {
        Color.clear
            .frame(height: 96)
            .accessibilityHidden(true)
    }
}

private struct IOSAddInlineHint: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct IOSQueueView: View {
    @ObservedObject var model: IOSMobileAppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let recoveryPresenter = IOSQueueRecoveryPresenter()

    var body: some View {
        NavigationStack {
            List {
                if model.queue.isEmpty {
                    queueEmptyState
                } else {
                    ForEach(model.queue) { task in
                        taskRow(task)
                    }
                    if let status = model.lastQueueActionStatus {
                        queueStatusRow(status)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                IOSListBottomScrollSpacer()
            }
            .navigationTitle("队列")
            .toolbar {
                if model.activeQueueCount > 0 {
                    Text("\(model.activeQueueCount) 个进行中")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var queueEmptyState: some View {
        Group {
            if usesAccessibilityDynamicType {
                IOSCompactEmptyState(
                    title: "队列为空",
                    message: "添加视频后会显示下载、翻译和导出进度。",
                    systemImage: "tray"
                ) {
                    Button {
                        model.selectedTab = .add
                    } label: {
                        Label("添加视频", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                ContentUnavailableView {
                    Label("队列为空", systemImage: "tray")
                } description: {
                    Text("添加视频后会在这里显示下载、翻译和导出进度。")
                } actions: {
                    Button {
                        model.selectedTab = .add
                    } label: {
                        Label("添加视频", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var usesAccessibilityDynamicType: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private func taskRow(_ task: MobileTaskSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon(for: task.state))
                    .foregroundStyle(task.error == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                Text(title(for: task))
                    .lineLimit(2)
                Spacer()
                Text(stateText(task.state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let fraction = task.progress.fractionCompleted {
                ProgressView(value: fraction)
                    .accessibilityLabel("任务进度")
                    .accessibilityValue(progressAccessibilityValue(for: task))
            } else if [.downloading, .translating, .exporting].contains(task.state) {
                ProgressView()
                    .accessibilityLabel("任务进度")
                    .accessibilityValue(progressAccessibilityValue(for: task))
            }
            if let recovery = recoveryPresenter.presentation(for: task) {
                Label(recovery.message, systemImage: recovery.systemImage)
                    .font(.caption)
                    .foregroundStyle(recovery.isActionable ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .accessibilityHint(recovery.accessibilityHint)
                Text(recovery.recoveryHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if task.state == .needsForegroundToContinue || task.backgroundPolicy.isSystemLimited {
                Text(backgroundText(for: task))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let primaryAction = primaryQueueAction(for: task) {
                HStack(spacing: 10) {
                    Button {
                        Task {
                            await model.performQueueAction(primaryAction, taskID: task.id)
                        }
                    } label: {
                        Label(queueActionTitle(primaryAction, for: task), systemImage: queueActionIcon(primaryAction))
                    }
                    .accessibilityLabel(queueActionAccessibilityLabel(primaryAction, for: task))
                    .accessibilityHint(queueActionAccessibilityHint(primaryAction, for: task))
                    .buttonStyle(.borderedProminent)

                    if !secondaryQueueActions(for: task).isEmpty {
                        Menu {
                            ForEach(secondaryQueueActions(for: task), id: \.rawValue) { action in
                                Button {
                                    Task {
                                    await model.performQueueAction(action, taskID: task.id)
                                }
                            } label: {
                                Label(queueActionTitle(action, for: task), systemImage: queueActionIcon(action))
                            }
                            .accessibilityLabel(queueActionAccessibilityLabel(action, for: task))
                            .accessibilityHint(queueActionAccessibilityHint(action, for: task))
                        }
                    } label: {
                            Label("更多", systemImage: "ellipsis.circle")
                        }
                        .accessibilityLabel(queueMoreActionsAccessibilityLabel(for: task))
                        .accessibilityHint("显示这个任务的其他操作。")
                    }
                }
            } else if !task.availableActions.isEmpty {
                Menu {
                    ForEach(secondaryQueueActions(for: task), id: \.rawValue) { action in
                        Button {
                            Task {
                            await model.performQueueAction(action, taskID: task.id)
                        }
                    } label: {
                        Label(queueActionTitle(action, for: task), systemImage: queueActionIcon(action))
                    }
                    .accessibilityLabel(queueActionAccessibilityLabel(action, for: task))
                    .accessibilityHint(queueActionAccessibilityHint(action, for: task))
                }
            } label: {
                    Label("操作", systemImage: "ellipsis.circle")
                }
                .accessibilityLabel(queueMoreActionsAccessibilityLabel(for: task))
                .accessibilityHint("显示这个任务的可用操作。")
            }
        }
        .padding(.vertical, 4)
    }

    private func progressAccessibilityValue(for task: MobileTaskSnapshot) -> String {
        if let fraction = task.progress.fractionCompleted {
            return "\(Int((fraction * 100).rounded()))%"
        }

        switch task.progress.phase {
        case .waiting: return stateText(task.state)
        case .analyzing: return "正在解析"
        case .downloading: return "正在下载"
        case .translating: return "正在翻译"
        case .exporting: return "正在导出"
        }
    }

    private func queueStatusRow(_ status: String) -> some View {
        Label(status, systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func queueActionAccessibilityLabel(_ action: MobileTaskAction, for task: MobileTaskSnapshot) -> String {
        "\(queueActionTitle(action, for: task)) \(title(for: task))"
    }

    private func queueActionAccessibilityHint(_ action: MobileTaskAction, for task: MobileTaskSnapshot) -> String {
        "对任务 \(title(for: task)) 执行\(queueActionTitle(action, for: task))。"
    }

    private func queueMoreActionsAccessibilityLabel(for task: MobileTaskSnapshot) -> String {
        "更多操作 \(title(for: task))"
    }

    private func title(for task: MobileTaskSnapshot) -> String {
        iosTaskDisplayName(task)
    }

    private func primaryQueueAction(for task: MobileTaskSnapshot) -> MobileTaskAction? {
        let priority: [MobileTaskAction] = [
            .startDownload,
            .exportRenderedVideo,
            .exportTranslatedSubtitle,
            .openAppToContinue,
            .retry,
            .openResult,
            .shareResult
        ]
        return priority.first { action in
            if action == .openAppToContinue && isNonResumableForegroundTask(task) {
                return false
            }
            return task.availableActions.contains(action)
        }
    }

    private func secondaryQueueActions(for task: MobileTaskSnapshot) -> [MobileTaskAction] {
        guard let primary = primaryQueueAction(for: task) else {
            return task.availableActions
        }
        return task.availableActions.filter { $0 != primary }
    }

    private func icon(for state: MobileTaskState) -> String {
        switch state {
        case .waiting, .ready: return "clock"
        case .analyzing: return "waveform"
        case .downloading: return "arrow.down.circle"
        case .translating: return "captions.bubble"
        case .exporting: return "film"
        case .needsForegroundToContinue: return "iphone"
        case .completed: return "checkmark.circle"
        case .failed: return "exclamationmark.circle"
        case .cancelled: return "xmark.circle"
        }
    }

    private func stateText(_ state: MobileTaskState) -> String {
        switch state {
        case .waiting: return "等待"
        case .analyzing: return "解析"
        case .ready: return "就绪"
        case .downloading: return "下载"
        case .translating: return "翻译"
        case .exporting: return "导出"
        case .needsForegroundToContinue: return "需回到前台"
        case .completed: return "完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }

    private func backgroundText(for task: MobileTaskSnapshot) -> String {
        if task.state == .needsForegroundToContinue {
            if isNonResumableForegroundTask(task) {
                return "这次处理已被系统中断，需要重新添加或重新开始。"
            }
            return "系统已暂停后台处理，打开 App 后继续导出。"
        }
        if task.backgroundPolicy.execution == .systemDeferred {
            return "后台任务由系统调度，可能稍后继续。"
        }
        return "后台处理受系统限制，进度以实际恢复为准。"
    }

    private func isNonResumableForegroundTask(_ task: MobileTaskSnapshot) -> Bool {
        task.state == .needsForegroundToContinue &&
            (
                task.backgroundPolicy.resumability == .nonResumable ||
                    task.backgroundPolicy.limits.contains(.notResumable)
            )
    }

    private func queueActionTitle(_ action: MobileTaskAction, for task: MobileTaskSnapshot) -> String {
        switch action {
        case .startDownload: return "开始下载"
        case .exportTranslatedSubtitle: return "生成字幕"
        case .exportRenderedVideo: return "导出视频"
        case .pause: return "暂停"
        case .resume: return "继续"
        case .cancel: return "取消"
        case .retry: return "重试"
        case .openAppToContinue:
            return "回到前台"
        case .openResult: return "在资料库打开"
        case .shareResult: return "在资料库分享"
        case .remove: return "移除"
        }
    }

    private func queueActionIcon(_ action: MobileTaskAction) -> String {
        switch action {
        case .startDownload: return "arrow.down.circle"
        case .exportTranslatedSubtitle: return "captions.bubble"
        case .exportRenderedVideo: return "film"
        case .pause: return "pause.circle"
        case .resume: return "play.circle"
        case .cancel: return "xmark.circle"
        case .retry: return "arrow.clockwise"
        case .openAppToContinue: return "iphone"
        case .openResult: return "arrow.up.right.square"
        case .shareResult: return "square.and.arrow.up"
        case .remove: return "trash"
        }
    }
}

private struct IOSLibraryView: View {
    @ObservedObject var model: IOSMobileAppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var shareURL: URL?
    @State private var quickLookURL: URL?
    @State private var exportFile: IOSExportFile?
    @State private var isFileExporterPresented = false
    @State private var pendingLocateCommand: IOSLibraryActionCommand?
    @State private var isLocateFileImporterPresented = false
    @State private var pendingSubtitleAttachmentItemID: String?
    @State private var isSubtitleAttachmentImporterPresented = false
    @State private var pendingDeletion: MobileLibraryItem?
    @State private var isDeleteConfirmationPresented = false

    private let artifactStore = IOSArtifactStore(storageDirectoryURL: Self.defaultStorageDirectoryURL())
    private let photoLibraryExporter = IOSSystemPhotoLibraryExporter()

    var body: some View {
        NavigationStack {
            List {
                if model.library.isEmpty {
                    libraryEmptyState
                } else {
                    ForEach(model.library) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title)
                                .font(.headline)
                            ForEach(item.artifacts) { artifact in
                                LabeledContent(artifact.displayName, value: iosArtifactKindLabel(artifact.kind))
                                    .font(.caption)
                            }
                            let primaryActions = primaryLibraryActions(for: item)
                            if !primaryActions.isEmpty {
                                HStack(spacing: 10) {
                                    ForEach(primaryActions, id: \.rawValue) { action in
                                        primaryLibraryActionButton(action, isProminent: action == primaryActions.first, item: item)
                                    }

                                    if !secondaryLibraryActions(for: item).isEmpty {
                                        Menu {
                                            subtitleAttachmentButton(for: item)
                                            ForEach(secondaryLibraryActions(for: item), id: \.rawValue) { action in
                                                libraryMenuActionButton(action, item: item)
                                            }
                                        } label: {
                                            Label("更多", systemImage: "ellipsis.circle")
                                        }
                                        .accessibilityLabel(libraryMoreActionsAccessibilityLabel(for: item))
                                        .accessibilityHint("显示这个资料库记录的其他操作。")
                                    }
                                }
                            } else if !item.availableActions.isEmpty {
                                Menu {
                                    subtitleAttachmentButton(for: item)
                                    ForEach(secondaryLibraryActions(for: item), id: \.rawValue) { action in
                                        libraryMenuActionButton(action, item: item)
                                    }
                                } label: {
                                    Label("更多", systemImage: "ellipsis.circle")
                                }
                                .accessibilityLabel(libraryMoreActionsAccessibilityLabel(for: item))
                                .accessibilityHint("显示这个资料库记录的可用操作。")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                libraryStatusContent
            }
            .safeAreaInset(edge: .bottom) {
                IOSListBottomScrollSpacer()
            }
            .navigationTitle("资料库")
            .fileExporter(
                isPresented: $isFileExporterPresented,
                item: exportFile,
                contentTypes: exportFile.map { [$0.contentType] } ?? [.data],
                defaultFilename: exportFile?.fileName
            ) { result in
                if case .failure = result {
                    model.lastLibraryActionStatus = "导出失败"
                } else {
                    exportFile = nil
                }
            } onCancellation: {
                exportFile = nil
            }
            .fileImporter(
                isPresented: $isLocateFileImporterPresented,
                allowedContentTypes: [.movie, .mpeg4Movie, .video, .plainText, .data],
                allowsMultipleSelection: false
            ) { result in
                guard let command = pendingLocateCommand else { return }
                defer { pendingLocateCommand = nil }
                guard case let .success(urls) = result,
                      let url = urls.first else {
                    model.lastLibraryActionStatus = "未选择文件"
                    return
                }
                Task { @MainActor in
                    await model.relocateLibraryFile(itemID: command.itemID, pickedFileURL: url)
                }
            }
            .fileImporter(
                isPresented: $isSubtitleAttachmentImporterPresented,
                allowedContentTypes: [UTType(filenameExtension: "srt") ?? .plainText],
                allowsMultipleSelection: false
            ) { result in
                guard let itemID = pendingSubtitleAttachmentItemID else { return }
                defer { pendingSubtitleAttachmentItemID = nil }
                guard case let .success(urls) = result,
                      let url = urls.first else {
                    model.lastLibraryActionStatus = "未选择字幕"
                    return
                }
                Task { @MainActor in
                    await model.attachImportedSubtitle(fileURL: url, toLibraryItemID: itemID, languageCode: "en")
                }
            }
            .sheet(isPresented: quickLookPresentedBinding) {
                if let quickLookURL {
                    IOSQuickLookPreview(url: quickLookURL)
                }
            }
            .confirmationDialog(
                "删除记录？",
                isPresented: $isDeleteConfirmationPresented,
                titleVisibility: Visibility.visible
            ) {
                Button("删除", role: .destructive) {
                    if let pendingDeletion {
                        Task { @MainActor in
                            await model.performLibraryAction(.deleteRecord, itemID: pendingDeletion.id)
                        }
                    }
                    pendingDeletion = nil
                }
                Button("取消", role: .cancel) {
                    pendingDeletion = nil
                }
            } message: {
                Text(pendingDeletion.map { "只删除资料库记录，不删除文件：\($0.title)" } ?? "只删除资料库记录。")
            }
            .onAppear(perform: performPendingLibraryActionCommand)
            .onChange(of: model.pendingLibraryActionCommand?.id) { _, _ in
                performPendingLibraryActionCommand()
            }
        }
    }

    private var libraryEmptyState: some View {
        Group {
            if usesAccessibilityDynamicType {
                IOSCompactEmptyState(
                    title: "资料库为空",
                    message: "完成的视频和字幕会保存为可分享的记录。",
                    systemImage: "rectangle.stack"
                ) {
                    Button {
                        model.selectedTab = .queue
                    } label: {
                        Label("查看队列", systemImage: "list.bullet")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                ContentUnavailableView {
                    Label("资料库为空", systemImage: "rectangle.stack")
                } description: {
                    Text("完成的视频和字幕会保存为可分享的记录。")
                } actions: {
                    Button {
                        model.selectedTab = .queue
                    } label: {
                        Label("查看队列", systemImage: "list.bullet")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var usesAccessibilityDynamicType: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private func performPendingLibraryActionCommand() {
        guard model.selectedTab == .library,
              let command = model.consumePendingLibraryActionCommand() else {
            return
        }

        do {
            try present(command)
        } catch {
            model.lastLibraryActionStatus = "无法打开系统操作"
        }
    }

    @ViewBuilder
    private var libraryStatusContent: some View {
        if let status = model.lastLibraryActionStatus {
            Label(status, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if let outcome = model.lastLibraryActionOutcome,
           outcome.requiresSystemUI {
            Label(systemPresentationText(outcome.presentation), systemImage: "rectangle.and.hand.point.up.left")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if let shareURL {
            ShareLink(item: shareURL) {
                Label("打开分享面板", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func primaryLibraryActions(for item: MobileLibraryItem) -> [MobileLibraryAction] {
        let priority: [MobileLibraryAction] = [
            .open,
            .share,
            .locateFile,
            .saveToFiles,
            .saveToPhotos
        ]
        return Array(priority.filter { item.availableActions.contains($0) }.prefix(2))
    }

    private func secondaryLibraryActions(for item: MobileLibraryItem) -> [MobileLibraryAction] {
        let primaryActions = primaryLibraryActions(for: item)
        return item.availableActions.filter { !primaryActions.contains($0) }
    }

    @ViewBuilder
    private func primaryLibraryActionButton(
        _ action: MobileLibraryAction,
        isProminent: Bool,
        item: MobileLibraryItem
    ) -> some View {
        if isProminent {
            Button {
                perform(action, for: item)
            } label: {
                Label(libraryActionTitle(action), systemImage: libraryActionIcon(action))
            }
            .accessibilityLabel(libraryActionAccessibilityLabel(action, item: item))
            .accessibilityHint(libraryActionAccessibilityHint(action, item: item))
            .buttonStyle(.borderedProminent)
        } else {
            Button {
                perform(action, for: item)
            } label: {
                Label(libraryActionTitle(action), systemImage: libraryActionIcon(action))
            }
            .accessibilityLabel(libraryActionAccessibilityLabel(action, item: item))
            .accessibilityHint(libraryActionAccessibilityHint(action, item: item))
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func libraryMenuActionButton(_ action: MobileLibraryAction, item: MobileLibraryItem) -> some View {
        Button(role: libraryActionRole(action)) {
            perform(action, for: item)
        } label: {
            Label(libraryActionTitle(action), systemImage: libraryActionIcon(action))
        }
        .accessibilityLabel(libraryActionAccessibilityLabel(action, item: item))
        .accessibilityHint(libraryActionAccessibilityHint(action, item: item))
    }

    @ViewBuilder
    private func subtitleAttachmentButton(for item: MobileLibraryItem) -> some View {
        if model.canAttachImportedSubtitle(toLibraryItem: item) {
            Button {
                pendingSubtitleAttachmentItemID = item.id
                isSubtitleAttachmentImporterPresented = true
            } label: {
                Label("添加字幕", systemImage: "text.badge.plus")
            }
            .accessibilityLabel("添加字幕 \(item.title)")
            .accessibilityHint("为这个资料库记录选择一个 SRT 字幕文件。")
        }
    }

    private func libraryActionAccessibilityLabel(_ action: MobileLibraryAction, item: MobileLibraryItem) -> String {
        "\(libraryActionTitle(action)) \(item.title)"
    }

    private func libraryActionAccessibilityHint(_ action: MobileLibraryAction, item: MobileLibraryItem) -> String {
        if action == .deleteRecord {
            return "只删除资料库记录，不删除文件。"
        }
        return "对资料库记录 \(item.title) 执行\(libraryActionTitle(action))。"
    }

    private func libraryMoreActionsAccessibilityLabel(for item: MobileLibraryItem) -> String {
        "更多操作 \(item.title)"
    }

    private func libraryActionRole(_ action: MobileLibraryAction) -> ButtonRole? {
        action == .deleteRecord ? .destructive : nil
    }

    private func perform(_ action: MobileLibraryAction, for item: MobileLibraryItem) {
        if action != .share {
            shareURL = nil
        }

        if action == .deleteRecord {
            pendingDeletion = item
            isDeleteConfirmationPresented = true
            return
        }

        Task { @MainActor in
            await model.performLibraryAction(action, itemID: item.id)
            guard let command = model.consumePendingLibraryActionCommand() else { return }

            do {
                try present(command)
            } catch {
                model.lastLibraryActionStatus = "无法打开系统操作"
            }
        }
    }

    private var quickLookPresentedBinding: Binding<Bool> {
        Binding(
            get: { quickLookURL != nil },
            set: { isPresented in
                if !isPresented {
                    quickLookURL = nil
                }
            }
        )
    }

    private func present(_ command: IOSLibraryActionCommand) throws {
        switch command.intent {
        case .open:
            quickLookURL = try artifactStore.fileURL(for: command.artifacts[0])
        case .share:
            shareURL = try artifactStore.fileURL(for: command.artifacts[0])
        case .exportToFiles:
            let url = try artifactStore.fileURL(for: command.artifacts[0])
            exportFile = IOSExportFile(
                url: url,
                contentType: UTType(filenameExtension: url.pathExtension) ?? .data,
                fileName: url.lastPathComponent
            )
            isFileExporterPresented = true
        case .saveToPhotos:
            let handler = IOSPhotoLibrarySaveHandler(
                artifactStore: artifactStore,
                exporter: photoLibraryExporter
            )
            Task { @MainActor in
                model.lastLibraryActionStatus = command.systemMessage
                model.lastLibraryActionStatus = await handler.save(command)
            }
        case .locateFile:
            pendingLocateCommand = command
            isLocateFileImporterPresented = true
            model.lastLibraryActionStatus = command.systemMessage
        }
    }

    private static func defaultStorageDirectoryURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("MoongateMobile", isDirectory: true)
        ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("MoongateMobile", isDirectory: true)
    }

    private func libraryActionTitle(_ action: MobileLibraryAction) -> String {
        switch action {
        case .open: return "打开"
        case .share: return "分享"
        case .saveToFiles: return "存到文件"
        case .saveToPhotos: return "存到照片"
        case .deleteRecord: return "删除"
        case .locateFile: return "定位"
        }
    }

    private func libraryActionIcon(_ action: MobileLibraryAction) -> String {
        switch action {
        case .open: return "arrow.up.right.square"
        case .share: return "square.and.arrow.up"
        case .saveToFiles: return "folder"
        case .saveToPhotos: return "photo"
        case .deleteRecord: return "trash"
        case .locateFile: return "scope"
        }
    }

    private func systemPresentationText(_ presentation: MobileLibraryActionPresentation) -> String {
        switch presentation {
        case .inAppOpen: return "需要打开系统预览"
        case .shareSheet: return "需要打开分享面板"
        case .fileExporter: return "需要选择保存位置"
        case .photoLibraryExporter: return "需要授权保存到照片"
        case .documentPicker: return "需要选择文件"
        case .confirmationOnly: return "已在资料库中更新"
        case .unavailable: return "当前没有可用文件"
        }
    }
}

#if os(iOS)
private struct IOSQuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        context.coordinator.url = url
        uiViewController.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> QLPreviewItem {
            url as NSURL
        }
    }
}
#else
private struct IOSQuickLookPreview: View {
    let url: URL

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(url.lastPathComponent)
                .font(.headline)
            Text(url.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
        .padding()
    }
}
#endif

private struct IOSSettingsView: View {
    @ObservedObject var model: IOSMobileAppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var apiKeyDraft = ""
    @State private var isDeleteAPIKeyConfirmationPresented = false

    var body: some View {
        NavigationStack {
            Form {
                Section("翻译 API") {
                    settingsProtocolRow
                    settingsFieldRow(
                        title: "服务地址",
                        text: endpointBinding,
                        accessibilityValue: endpointAccessibilityValue,
                        accessibilityHint: "输入 HTTPS API 服务地址"
                    )
                    settingsFieldRow(
                        title: "模型",
                        text: modelBinding,
                        accessibilityValue: modelAccessibilityValue,
                        accessibilityHint: "输入云端翻译模型名称"
                    )
                    settingsSecureFieldRow(
                        title: "API key",
                        text: $apiKeyDraft,
                        accessibilityValue: apiKeyAccessibilityValue,
                        accessibilityHint: model.hasConfiguredTranslationCredential ? "输入新密钥后可替换已保存的 API key" : "输入密钥后保存到系统安全存储"
                    )
                    Button(model.hasConfiguredTranslationCredential ? "替换 API key" : "保存 API key") {
                        let secret = apiKeyDraft
                        Task {
                            await model.saveAPIKeyDraft(secret)
                        }
                        apiKeyDraft = ""
                    }
                    .disabled(
                        !model.translationConfiguration.engine.requiresCloudConfiguration ||
                        apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    if model.hasConfiguredTranslationCredential {
                        Button("删除 API key", role: .destructive) {
                            isDeleteAPIKeyConfirmationPresented = true
                        }
                    }
                    settingsStatusRow(
                        title: "API key",
                        value: model.hasConfiguredTranslationCredential ? "密钥已安全保存。" : "还没有保存密钥。",
                        accessibilityLabel: "API key 状态",
                        accessibilityValue: apiKeyAccessibilityValue
                    )
                    Button {
                        Task {
                            await model.testCloudTranslationConnection()
                        }
                    } label: {
                        if model.cloudTranslationConnectionStatus.state == .testing {
                            Label("正在测试", systemImage: "network")
                        } else {
                            Label("测试连接", systemImage: "network")
                        }
                    }
                    .disabled(
                        !model.translationConfiguration.engine.requiresCloudConfiguration ||
                        model.cloudTranslationConnectionStatus.state == .testing ||
                        model.translationConfiguration.readiness.issues.contains { $0.kind == .needsConfiguration }
                    )
                    .accessibilityLabel("测试翻译 API 连接")
                    .accessibilityValue(model.cloudTranslationConnectionStatus.message)
                    .accessibilityHint("使用当前协议、服务地址、模型和已保存的 API key 测试连接")
                    settingsStatusRow(
                        title: "连接",
                        value: model.cloudTranslationConnectionStatus.message,
                        foregroundStyle: connectionStatusStyle,
                        accessibilityLabel: "翻译 API 连接状态",
                        accessibilityValue: model.cloudTranslationConnectionStatus.message
                    )
                }
                .confirmationDialog("删除 API key？",
                    isPresented: $isDeleteAPIKeyConfirmationPresented,
                    titleVisibility: Visibility.visible
                ) {
                    Button("删除 API key", role: .destructive) {
                        Task {
                            await model.deleteAPIKey()
                        }
                        apiKeyDraft = ""
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("删除后，云端翻译需要重新保存密钥才能使用。")
                }

                Section("Apple Intelligence") {
                    Picker("模式", selection: $model.selectedAppleIntelligenceRoute) {
                        ForEach(IOSAppleIntelligenceRoute.allCases) { route in
                            Text(route.shortTitle).tag(route)
                        }
                    }
                    .onChange(of: model.selectedAppleIntelligenceRoute) { _, route in
                        Task {
                            await model.refreshAppleIntelligenceStatus(for: route)
                        }
                    }
                    .accessibilityLabel("Apple Intelligence 路线")
                    .accessibilityValue(model.selectedAppleIntelligenceRoute.shortTitle)
                    .accessibilityHint("选择 Apple Intelligence 翻译方式；这里只显示当前设备是否可用。")
                    ForEach(model.appleIntelligenceStatuses) { status in
                        appleIntelligenceStatusRow(status)
                    }
                }

                Section("后台处理") {
                    if model.foregroundRequiredTasks.isEmpty {
                        Label("没有需要回到前台的任务", systemImage: "checkmark.circle")
                    } else {
                        ForEach(model.foregroundRequiredTasks) { task in
                            Label(iosTaskDisplayName(task, fallback: "处理中任务"), systemImage: "iphone")
                        }
                    }
                    if !usesAccessibilityDynamicType {
                        Text("后台下载和导出由系统调度，界面只展示可恢复状态，不承诺无限后台运行。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                IOSListBottomScrollSpacer()
            }
            .navigationTitle("设置")
        }
    }

    private var usesAccessibilityDynamicType: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var cloudEngineBinding: Binding<TranslationEngine> {
        Binding(
            get: {
                switch model.translationConfiguration.engine {
                case .anthropicCompatible:
                    return .anthropicCompatible
                case .openAICompatible,
                     .appleTranslationLowLatency,
                     .appleTranslationHighFidelity,
                     .appleFoundationOnDevice,
                     .appleFoundationPCC,
                     .appleFoundationCloudPro:
                    return .openAICompatible
                }
            },
            set: { model.updateCloudTranslationEngine($0) }
        )
    }

    private var endpointBinding: Binding<String> {
        Binding(
            get: { model.translationConfiguration.baseURL ?? "" },
            set: { model.updateCloudTranslationEndpoint($0) }
        )
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { model.translationConfiguration.model ?? "" },
            set: { model.updateCloudTranslationModel($0) }
        )
    }

    private var connectionStatusStyle: AnyShapeStyle {
        switch model.cloudTranslationConnectionStatus.state {
        case .idle, .testing:
            return AnyShapeStyle(.secondary)
        case .succeeded:
            return AnyShapeStyle(.green)
        case .failed:
            return AnyShapeStyle(.red)
        }
    }

    private var endpointAccessibilityValue: String {
        trimmedValue(model.translationConfiguration.baseURL).isEmpty ? "未配置服务地址" : "已配置服务地址"
    }

    private var modelAccessibilityValue: String {
        trimmedValue(model.translationConfiguration.model).isEmpty ? "未配置模型" : "已配置模型"
    }

    private var apiKeyAccessibilityValue: String {
        model.hasConfiguredTranslationCredential ? "已保存 API key" : "未保存 API key"
    }

    private var settingsProtocolRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("协议")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Picker("协议", selection: cloudEngineBinding) {
                Text("OpenAI").tag(TranslationEngine.openAICompatible)
                Text("Anthropic").tag(TranslationEngine.anthropicCompatible)
            }
            .labelsHidden()
            .accessibilityLabel("翻译协议")
            .accessibilityValue(cloudEngineBinding.wrappedValue.displayName)
            .accessibilityHint("选择云端翻译 API 的兼容协议")
        }
    }

    private func settingsFieldRow(
        title: String,
        text: Binding<String>,
        accessibilityValue: String,
        accessibilityHint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(title, text: text)
                .mobileSensitiveInput()
                .accessibilityLabel(title)
                .accessibilityValue(accessibilityValue)
                .accessibilityHint(accessibilityHint)
        }
    }

    private func settingsSecureFieldRow(
        title: String,
        text: Binding<String>,
        accessibilityValue: String,
        accessibilityHint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            SecureField(title, text: text)
                .mobileSensitiveInput()
                .accessibilityLabel(title)
                .accessibilityValue(accessibilityValue)
                .accessibilityHint(accessibilityHint)
        }
    }

    private func settingsStatusRow(
        title: String,
        value: String,
        foregroundStyle: AnyShapeStyle = AnyShapeStyle(.secondary),
        accessibilityLabel: String,
        accessibilityValue: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .foregroundStyle(foregroundStyle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    private func appleIntelligenceStatusRow(_ status: IOSAppleIntelligenceStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            appleIntelligenceStatusHeader(status)
            Text(status.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(appleIntelligenceFallbackText(for: status))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Apple Intelligence 状态")
        .accessibilityValue(appleIntelligenceAccessibilityValue(for: status))
        .accessibilityHint("如果这条路线暂不可用，可以先改用 API 兼容引擎或其它已就绪路线。")
    }

    @ViewBuilder
    private func appleIntelligenceStatusHeader(_ status: IOSAppleIntelligenceStatus) -> some View {
        if usesAccessibilityDynamicType {
            VStack(alignment: .leading, spacing: 2) {
                Text(status.route.title)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text(status.availabilityLabel)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(status.isAvailable ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(status.route.title)
                    .font(.body)
                Spacer(minLength: 8)
                Text(status.availabilityLabel)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(status.isAvailable ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
            }
        }
    }

    private func appleIntelligenceAccessibilityValue(for status: IOSAppleIntelligenceStatus) -> String {
        "\(status.route.title)，\(status.availabilityLabel)。\(status.detail) \(appleIntelligenceFallbackText(for: status))"
    }

    private func appleIntelligenceFallbackText(for status: IOSAppleIntelligenceStatus) -> String {
        if status.isAvailable {
            return "可用后仍会按系统能力处理，不会绕过设备和系统限制。"
        }
        return "替代路径：先改用 API 兼容引擎，或选择其它已就绪路线。"
    }

    private func trimmedValue(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct IOSListBottomScrollSpacer: View {
    var body: some View {
        Color.clear
            .frame(height: 116)
            .accessibilityHidden(true)
    }
}

private struct IOSCompactEmptyState<Actions: View>: View {
    let title: String
    let message: String
    let systemImage: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            actions
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
    }
}

private extension View {
    @ViewBuilder
    func mobileSensitiveInput() -> some View {
        #if os(iOS)
        self
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self
            .autocorrectionDisabled()
        #endif
    }
}

private func iosTaskDisplayName(
    _ task: MobileTaskSnapshot,
    fallback: String = "未命名视频"
) -> String {
    task.result?.primaryArtifact?.displayName ?? fallback
}

private func iosCandidateKindLabel(_ kind: MobileCandidateKind) -> String {
    switch kind {
    case .directFile:
        return "直接视频文件"
    case .hlsStream:
        return "流媒体视频"
    case .webPageVideo:
        return "网页视频"
    case .importedFile:
        return "本地文件"
    }
}

private func iosArtifactKindLabel(_ kind: MobileArtifactKind) -> String {
    switch kind {
    case .originalMedia:
        return "原视频"
    case .translatedSubtitleFile:
        return "字幕文件"
    case .softSubtitle:
        return "软字幕包"
    case .renderedVideo:
        return "带字幕视频"
    case .transcript:
        return "文稿"
    case .metadata:
        return "元数据"
    }
}
