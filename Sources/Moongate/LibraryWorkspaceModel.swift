import AppKit
import Combine
import Foundation
import MoongateCore
import SwiftUI

/// UI-facing coordinator for the durable library. It intentionally persists a
/// narrow `LibraryItem` projection instead of serialising QueueItem/AppSettings
/// snapshots, which can contain credentials and runtime-only controls.
@MainActor
final class LibraryWorkspaceModel: ObservableObject {
    enum SidebarDestination: Hashable {
        case all
        case active
        case needsAttention
        case completed
        case pinned
        case tag(String)

        var libraryFilter: LibraryFilter {
            switch self {
            case .all: .all
            case .active: .active
            case .needsAttention: .needsAttention
            case .completed: .completed
            case .pinned: .pinned
            case .tag(let name): .tag(name)
            }
        }
    }

    enum InspectorMode: String, CaseIterable, Identifiable {
        case information
        case processing

        var id: String { rawValue }
    }

    /// A deferred task can remain editable when its selected local or cloud
    /// recognizer is unavailable. Keep the recovery destination typed here so
    /// the workspace never presents a button that merely looks actionable.
    enum QueuedReadinessRecovery: Equatable {
        case localSpeech
        case cloudASR

        var settingsPaneID: String {
            switch self {
            case .localSpeech: "subtitlesLanguage"
            case .cloudASR: "servicesAccounts"
            }
        }

        var actionTitle: String {
            switch self {
            case .localSpeech: "打开字幕与语言设置"
            case .cloudASR: "打开服务与账户设置"
            }
        }
    }

    struct LiveQueueDetails: Equatable {
        let queueID: UUID
        let speedText: String?
        let remainingSeconds: Double?
        let remainingIsApproximate: Bool
        let isEstimatingRemaining: Bool
        let statusText: String?
    }

    struct PlaybackRequest: Equatable {
        let requestID: UUID
        let itemID: UUID

        init(itemID: UUID) {
            requestID = UUID()
            self.itemID = itemID
        }
    }

    @Published private(set) var envelope = LibraryEnvelope() {
        didSet {
            rebuildProjectionCache()
            selectFirstItemIfNeeded()
        }
    }
    @Published var sidebarDestination: SidebarDestination = .all {
        didSet {
            rebuildProjectionCache()
            selectFirstItemIfNeeded()
        }
    }
    @Published var selectedItemID: UUID? {
        didSet { loadDraftForSelection() }
    }
    @Published var searchText = "" {
        didSet {
            rebuildProjectionCache()
            selectFirstItemIfNeeded()
        }
    }
    @Published var showInspector = true
    @Published private(set) var inspectorInteractionGeneration = 0
    @Published var inspectorMode: InspectorMode = .information
    /// A one-way request from a list context-menu action to the AVKit stage.
    /// Its nonce makes repeated explicit plays of the same item distinguishable.
    @Published private(set) var playbackRequest: PlaybackRequest?
    @Published var processingDraft = LibraryProcessingConfiguration()
    @Published var showRecoverySheet = false
    @Published private(set) var recoveryCandidates: [LibraryRecoveredCandidate] = []
    @Published private(set) var liveQueueDetails: [UUID: LiveQueueDetails] = [:]
    @Published private(set) var projectedItems: [LibraryProjectedItem] = []
    @Published private(set) var sidebarCounts: [LibraryFilter: Int] = [:]
    @Published var errorMessage: String?
    @Published private(set) var undoRemovalAvailable = false

    private let appModel: ViewModel
    private let store: LibraryStore
    private var queueSubscription: AnyCancellable?
    private var notificationSubscriptions = Set<AnyCancellable>()
    private var queueSyncTask: Task<Void, Never>?
    private var removedItemForUndo: MoongateCore.LibraryItem?
    /// An index-only removal must not be resurrected by a still-resident
    /// QueueItem on its next progress update. This is session-scoped because
    /// QueueItem itself is intentionally not restored across app launches.
    private var suppressedQueueLibraryItemIDs = Set<UUID>()
    private var liveProcessing: [UUID: ProcessingSummary] = [:] {
        didSet {
            rebuildProjectionCache()
            selectFirstItemIfNeeded()
        }
    }
    /// The queue publisher emits immediately during init. Do not let that
    /// first value race the on-disk library load; bootstrap replays the latest
    /// queue state once the durable envelope is ready.
    private var bootstrapFinished = false
    /// Until the user explicitly changes it, the Inspector follows the window
    /// breakpoint defaults. Once toggled, their choice wins for this session.
    private var inspectorPreferenceIsExplicit = false

    init(model: ViewModel, store: LibraryStore = LibraryStore()) {
        self.appModel = model
        self.store = store

        queueSubscription = model.queue.$items
            .sink { [weak self] items in
                self?.receiveQueue(items)
            }
        NotificationCenter.default.publisher(for: AppWorkspaceCommand.searchRequested)
            .sink { [weak self] _ in self?.requestSearchFocus() }
            .store(in: &notificationSubscriptions)

        Task { [weak self] in
            await self?.bootstrap()
        }
    }

    deinit {
        queueSyncTask?.cancel()
    }

    func sidebarCount(for filter: LibraryFilter) -> Int {
        sidebarCounts[filter] ?? 0
    }

    var selectedItem: MoongateCore.LibraryItem? {
        guard let selectedItemID else { return nil }
        return envelope.items.first { $0.id == selectedItemID }
    }

    var selectedProcessing: ProcessingSummary? {
        guard let selectedItem else { return nil }
        return liveProcessing[selectedItem.id] ?? selectedItem.latestVersion?.processing
    }

    var selectedItemBinding: Binding<UUID?> {
        Binding(get: { self.selectedItemID }, set: { self.selectedItemID = $0 })
    }

    var availableTags: [LibraryTag] {
        envelope.tags.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func queueDetails(for itemID: UUID) -> LiveQueueDetails? {
        liveQueueDetails[itemID]
    }

    var selectedQueueItem: QueueManager.QueueItem? {
        guard let selectedItemID else { return nil }
        return queueItem(for: selectedItemID)
    }

    func queueItem(for itemID: UUID) -> QueueManager.QueueItem? {
        if let queueID = liveQueueDetails[itemID]?.queueID,
           let exact = appModel.queue.items.first(where: { $0.id == queueID }) {
            return exact
        }
        return appModel.queue.items.last(where: { $0.libraryItemID == itemID })
    }

    /// Returns a real settings destination only for a deferred task that has
    /// already failed its recognizer preflight. Ordinary queued work continues
    /// to use the normal Start action.
    func queuedReadinessRecovery(for itemID: UUID) -> QueuedReadinessRecovery? {
        guard let queueItem = queueItem(for: itemID),
              queueItem.isDeferredDraft,
              let status = queueItem.statusText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !status.isEmpty else {
            return nil
        }

        if queueItem.request.subtitleSourcePolicy == .cloudASR {
            return .cloudASR
        }

        switch queueItem.request.subtitleSourcePolicy {
        case .forceLocalASR, .preferLocalASR, .compareLocalASR:
            return .localSpeech
        case .autoBest, .preferPlatform, .forcePlatform, .cloudASR, .importedFile:
            return queueItem.request.primarySubtitleTrack?.sourceKind == .localASR
                ? .localSpeech
                : nil
        }
    }

    /// Opens an existing Settings pane; the action label deliberately matches
    /// the destination instead of promising an in-place component installer.
    func openQueuedReadinessRecovery(for itemID: UUID) {
        guard let recovery = queuedReadinessRecovery(for: itemID) else { return }
        appModel.openSettings(paneID: recovery.settingsPaneID)
    }

    var hasQueuedTasks: Bool {
        appModel.queue.items.contains { $0.isDeferredDraft }
    }

    @discardableResult
    func startSelectedQueuedTask() -> Bool {
        guard let selectedQueueItem, selectedQueueItem.isDeferredDraft else { return false }
        return appModel.startQueuedTask(id: selectedQueueItem.id)
    }

    @discardableResult
    func startAllQueuedTasks() -> Int {
        appModel.startAllQueuedTasks()
    }

    func recoverQueueTask(for itemID: UUID) {
        guard let queueItem = queueItem(for: itemID) else { return }
        switch queueItem.stage {
        case .queued:
            guard queueItem.isDeferredDraft else { return }
            _ = appModel.startQueuedTask(id: queueItem.id)
        case .failed:
            if let prompt = queueItem.needsLogin {
                appModel.openLoginForQueueItem(site: prompt.site, loginURL: prompt.loginURL)
            } else {
                appModel.queue.retry(queueItem.id)
            }
        case .cancelling, .downloading, .translating, .burning, .done, .cancelled:
            break
        }
    }

    /// Defaults follow the agreed three breakpoints: show at 1380 pt and
    /// above; hide in the compact and medium ranges. The toolbar can still
    /// explicitly show/hide the Inspector at any usable window width.
    func updateLayout(for width: CGFloat) {
        guard width > 0, !inspectorPreferenceIsExplicit else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            showInspector = width >= 1_380
        }
    }

    func toggleInspector() {
        inspectorPreferenceIsExplicit = true
        inspectorInteractionGeneration &+= 1
        showInspector.toggle()
    }

    func showInspector(_ mode: InspectorMode) {
        inspectorPreferenceIsExplicit = true
        inspectorMode = mode
        guard !showInspector else { return }
        inspectorInteractionGeneration &+= 1
        showInspector = true
    }

    func showInspector(_ mode: InspectorMode, for itemID: UUID) {
        selectedItemID = itemID
        showInspector(mode)
    }

    func revealSelectedInFinder() {
        guard let selectedItemID else { return }
        revealInFinder(itemID: selectedItemID)
    }

    func canRevealInFinder(itemID: UUID) -> Bool {
        revealableArtifactURL(itemID: itemID) != nil
    }

    func revealInFinder(itemID: UUID) {
        guard let url = revealableArtifactURL(itemID: itemID) else {
            errorMessage = "找不到可在访达中显示的本地文件。"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func revealableArtifactURL(itemID: UUID) -> URL? {
        guard let item = libraryItem(id: itemID),
              let artifact = item.latestVersion?.artifacts.first(where: {
                  $0.role == .video || $0.role == .renderedVideo
              }) ?? item.latestVersion?.artifacts.first,
              let url = absoluteURL(for: artifact),
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    func copySourceLink(itemID: UUID) {
        guard let source = libraryItem(id: itemID)?.source?.urlString,
              !source.isEmpty else {
            errorMessage = "这个项目没有可复制的来源链接。"
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(source, forType: .string)
    }

    func canPlayEmbeddedVideo(itemID: UUID) -> Bool {
        guard let artifact = libraryItem(id: itemID)?.latestVersion?.artifacts.first(where: {
            $0.role == .video || $0.role == .renderedVideo
        }),
        let url = absoluteURL(for: artifact) else {
            return false
        }
        return ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased())
            && FileManager.default.fileExists(atPath: url.path)
    }

    func playEmbeddedVideo(itemID: UUID) {
        guard canPlayEmbeddedVideo(itemID: itemID) else {
            errorMessage = "该视频暂时不能在月之门内播放。"
            return
        }
        selectedItemID = itemID
        playbackRequest = PlaybackRequest(itemID: itemID)
    }

    func consumePlaybackRequest(id: UUID) {
        guard playbackRequest?.requestID == id else { return }
        playbackRequest = nil
    }

    func requestSearchFocus() {
        NotificationCenter.default.post(name: .moongateLibrarySearchFocus, object: nil)
    }

    func configurationBinding(
        _ keyPath: WritableKeyPath<LibraryProcessingConfiguration, String?>
    ) -> Binding<String> {
        Binding(
            get: { self.processingDraft[keyPath: keyPath] ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                self.processingDraft[keyPath: keyPath] = trimmed.isEmpty ? nil : trimmed
                self.persistSelectedQueuedConfiguration()
            }
        )
    }

    var draftSubtitleMode: ChineseSubtitleMode {
        ChineseSubtitleMode(rawValue: processingDraft.subtitleMode ?? "") ?? .off
    }

    var changedFields: Set<ReprocessChangedField> {
        guard let original = selectedItem?.latestVersion?.processing.configuration else { return [] }
        var changes = Set<ReprocessChangedField>()
        if original.subtitleMode != processingDraft.subtitleMode { changes.insert(.subtitleMode) }
        if original.subtitleStyle != processingDraft.subtitleStyle { changes.insert(.subtitleStyle) }
        if original.targetLanguage != processingDraft.targetLanguage { changes.insert(.targetLanguage) }
        if original.translationModel != processingDraft.translationModel { changes.insert(.translationModel) }
        if original.transcriptionModel != processingDraft.transcriptionModel { changes.insert(.transcriptionModel) }
        if original.subtitleSource != processingDraft.subtitleSource { changes.insert(.subtitleSource) }
        if original.outputFormat != processingDraft.outputFormat { changes.insert(.outputFormat) }
        if original.quality != processingDraft.quality { changes.insert(.quality) }
        return changes
    }

    var reprocessPlan: ReprocessPlan? {
        guard let version = selectedItem?.latestVersion,
              !changedFields.isEmpty else {
            return nil
        }
        return ReprocessPlanner.plan(for: ReprocessRequest(
            sourceVersionID: version.id,
            changedFields: changedFields,
            configuration: processingDraft,
            previousConfiguration: version.processing.configuration
        ))
    }

    var reprocessBlockerReason: String? {
        guard let plan = reprocessPlan else { return nil }
        return reprocessBlockerReason(for: plan)
    }

    var canCreateReprocess: Bool {
        reprocessPlan != nil && reprocessBlockerReason == nil
    }

    func reprocessBlockerReason(for plan: ReprocessPlan) -> String? {
        guard !plan.steps.isEmpty else {
            return "此修改不会改变当前输出。"
        }
        guard plan.steps.contains(.refreshVideo) else { return nil }
        guard let source = selectedItem?.source, source.supportsRestart else {
            return "此变更需要重新下载原视频。请使用可安全重新开始的原链接新建下载。"
        }
        return nil
    }

    func setPinned(_ pinned: Bool, itemID: UUID? = nil) {
        guard var item = libraryItem(id: itemID ?? selectedItemID) else { return }
        item.isPinned = pinned
        item.updatedAt = Date()
        persistItem(item)
    }

    func updateNote(_ note: String) {
        guard var item = selectedItem else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        item.note = trimmed.isEmpty ? nil : trimmed
        item.updatedAt = Date()
        persistItem(item)
    }

    func addTag(_ rawTag: String) {
        guard var item = selectedItem else { return }
        let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty,
              !item.tags.contains(where: { $0.compare(tag, options: String.CompareOptions.caseInsensitive) == .orderedSame }) else {
            return
        }

        item.tags.append(tag)
        item.updatedAt = Date()
        Task { [weak self] in
            guard let self else { return }
            do {
                try await store.upsert(item)
                var updated = try await store.load()
                if !updated.tags.contains(where: { $0.name.compare(tag, options: String.CompareOptions.caseInsensitive) == .orderedSame }) {
                    updated.tags.append(LibraryTag(name: tag))
                    try await store.save(updated)
                }
                envelope = try await store.load()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Removes only the durable index. The returned item stays in memory so
    /// the UI can offer a genuine undo rather than pretending media was erased.
    func removeFromLibrary(itemID: UUID? = nil) {
        guard let targetItemID = itemID ?? selectedItemID else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                removedItemForUndo = try await store.remove(itemID: targetItemID)
                undoRemovalAvailable = removedItemForUndo != nil
                if removedItemForUndo != nil {
                    suppressedQueueLibraryItemIDs.insert(targetItemID)
                }
                envelope = try await store.load()
                if selectedItemID == targetItemID {
                    self.selectedItemID = envelope.items.first?.id
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func undoRemoveFromLibrary() {
        guard let removedItemForUndo else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await store.upsert(removedItemForUndo)
                suppressedQueueLibraryItemIDs.remove(removedItemForUndo.id)
                envelope = try await store.load()
                selectedItemID = removedItemForUndo.id
                self.removedItemForUndo = nil
                undoRemovalAvailable = false
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func importRecoveredVideos() {
        let candidates = recoveryCandidates
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await store.importRecovered(candidates)
                envelope = try await store.load()
                recoveryCandidates = []
                showRecoverySheet = false
                UserDefaults.standard.set(true, forKey: Self.recoveryScanDefaultsKey)
                selectFirstItemIfNeeded()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func dismissRecovery() {
        recoveryCandidates = []
        showRecoverySheet = false
        UserDefaults.standard.set(true, forKey: Self.recoveryScanDefaultsKey)
    }

    func absoluteURL(for artifact: LibraryArtifact) -> URL? {
        let root = ViewModel.appDownloadsDirectory.standardizedFileURL
        let candidate = root.appendingPathComponent(artifact.relativePath).standardizedFileURL
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(rootPrefix) else { return nil }
        return candidate
    }

    /// The destructive operation is intentionally separate from index removal
    /// and is called only after the Inspector's explicit confirmation dialog.
    func moveArtifactsToTrash(itemID: UUID? = nil) {
        guard let item = libraryItem(id: itemID ?? selectedItemID) else { return }
        let urls = Array(Set(
            item.versions
                .flatMap(\.artifacts)
                .compactMap(absoluteURL(for:))
        ))
        guard !urls.isEmpty else {
            errorMessage = "找不到可移到废纸篓的本地文件。"
            return
        }

        let existingURLs = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existingURLs.isEmpty else {
            errorMessage = "本地文件已不在原位置。若只想隐藏这条记录，请使用“从资料库移除”。"
            return
        }

        do {
            for url in existingURLs {
                _ = try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            }
            // Finder's trash operation is destructive from the library's
            // point of view: an index-only undo would restore a record whose
            // media is still in the Trash. Keep undo exclusively for the
            // non-destructive "从资料库移除" action.
            removedItemForUndo = nil
            undoRemovalAvailable = false
            suppressedQueueLibraryItemIDs.insert(item.id)
            Task { [weak self] in
                guard let self else { return }
                do {
                    _ = try await store.remove(itemID: item.id)
                    envelope = try await store.load()
                    if selectedItemID == item.id {
                        selectedItemID = envelope.items.first?.id
                    }
                } catch {
                    errorMessage = "文件已移到废纸篓，但未能从资料库移除：\(error.localizedDescription)"
                }
            }
        } catch {
            errorMessage = "部分文件没有移到废纸篓：\(error.localizedDescription)"
        }
    }

    /// The QueueManager receives a new task/version identity, so this action
    /// cannot overwrite the completed record currently shown in the Inspector.
    func createReprocessTask() {
        guard let item = selectedItem,
              let plan = reprocessPlan,
              reprocessBlockerReason(for: plan) == nil else {
            return
        }
        let configuration = processingDraft
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await appModel.enqueueLibraryReprocess(
                    item: item,
                    configuration: configuration,
                    plan: plan
                )
                processingDraft = item.latestVersion?.processing.configuration ?? .init()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func restartInterruptedTask() {
        guard let item = selectedItem,
              selectedProcessing?.state == .interrupted else {
            return
        }
        appModel.restartInterruptedLibraryItem(item)
    }

    private func bootstrap() async {
        do {
            _ = try await store.markActiveItemsInterrupted()
            envelope = try await store.load()
            selectFirstItemIfNeeded()
            await discoverRecoveryIfNeeded()
            bootstrapFinished = true
            receiveQueue(appModel.queue.items)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func discoverRecoveryIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: Self.recoveryScanDefaultsKey) else { return }
        do {
            let candidates = try await store.discoverLegacyDownloads(at: ViewModel.appDownloadsDirectory)
            let knownPaths = Set(
                envelope.items.flatMap { $0.versions.flatMap(\.artifacts).map(\.relativePath) }
            )
            recoveryCandidates = candidates.filter { !knownPaths.contains($0.relativePath) }
            showRecoverySheet = !recoveryCandidates.isEmpty
            if recoveryCandidates.isEmpty {
                UserDefaults.standard.set(true, forKey: Self.recoveryScanDefaultsKey)
            }
        } catch {
            // A read-only scan is helpful but must never prevent the app shell
            // from opening.
            errorMessage = error.localizedDescription
        }
    }

    private func persistItem(_ item: MoongateCore.LibraryItem) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await store.upsert(item)
                envelope = try await store.load()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func rebuildProjectionCache() {
        projectedItems = LibraryProjection.items(
            in: envelope,
            filter: sidebarDestination.libraryFilter,
            searchQuery: searchText,
            liveProcessing: liveProcessing
        )
        sidebarCounts = LibraryProjection.sidebarCounts(
            in: envelope,
            liveProcessing: liveProcessing
        )
    }

    private func selectFirstItemIfNeeded() {
        let projectedIDs = Set(projectedItems.map(\.id))
        if let selectedItemID, projectedIDs.contains(selectedItemID) {
            return
        }
        selectedItemID = projectedItems.first?.id
    }

    private func libraryItem(id: UUID?) -> MoongateCore.LibraryItem? {
        guard let id else { return nil }
        return envelope.items.first { $0.id == id }
    }

    private func loadDraftForSelection() {
        processingDraft = selectedItem?.latestVersion?.processing.configuration ?? .init()
        inspectorMode = .information
    }

    private func persistSelectedQueuedConfiguration() {
        guard let selectedQueueItem,
              selectedQueueItem.isDeferredDraft else {
            return
        }
        _ = appModel.updateQueuedTaskConfiguration(
            id: selectedQueueItem.id,
            configuration: processingDraft
        )
    }

    private static let recoveryScanDefaultsKey = "v0.9.libraryRecoveryScanV1"

    private func receiveQueue(_ items: [QueueManager.QueueItem]) {
        let snapshots = items.map(QueueLibrarySnapshot.init)
        // A completed v1 and an active v2 can coexist in QueueManager. Prefer
        // the active/newest snapshot without `Dictionary(uniqueKeys...)`, which
        // would otherwise trap on the intentional shared library item id.
        var latestProcessing: [UUID: ProcessingSummary] = [:]
        var latestDetails: [UUID: LiveQueueDetails] = [:]
        for snapshot in snapshots {
            let current = latestProcessing[snapshot.libraryItemID]
            if current == nil
                || !current!.state.isActive
                || snapshot.processing.state.isActive {
                latestProcessing[snapshot.libraryItemID] = snapshot.processing
                latestDetails[snapshot.libraryItemID] = LiveQueueDetails(
                    queueID: snapshot.queueID,
                    speedText: snapshot.speedText,
                    remainingSeconds: snapshot.remainingSeconds,
                    remainingIsApproximate: snapshot.remainingIsApproximate,
                    isEstimatingRemaining: snapshot.isEstimatingRemaining,
                    statusText: snapshot.statusText
                )
            }
        }
        liveProcessing = latestProcessing
        liveQueueDetails = latestDetails
        guard bootstrapFinished else { return }
        scheduleQueueSynchronization(snapshots)
    }

    private func scheduleQueueSynchronization(_ snapshots: [QueueLibrarySnapshot]) {
        queueSyncTask?.cancel()
        // A newly enqueued item is the durable identity boundary. Persist it
        // without the normal UI-progress debounce so switching to legacy or
        // closing immediately after enqueue cannot leave an orphaned queue
        // task with no restart/recovery record.
        let hasUnpersistedItem = snapshots.contains { snapshot in
            !envelope.items.contains(where: { $0.id == snapshot.libraryItemID })
        }
        queueSyncTask = Task { [weak self, snapshots] in
            if !hasUnpersistedItem {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            guard !Task.isCancelled, let self else { return }
            await self.synchronizeQueue(snapshots)
        }
    }

    private func synchronizeQueue(_ snapshots: [QueueLibrarySnapshot]) async {
        let visibleSnapshots = snapshots.filter {
            !suppressedQueueLibraryItemIDs.contains($0.libraryItemID)
        }
        guard !visibleSnapshots.isEmpty else { return }
        do {
            var stored = try await store.load()
            let original = stored

            for snapshot in visibleSnapshots {
                if let itemIndex = stored.items.firstIndex(where: { $0.id == snapshot.libraryItemID }) {
                    var item = stored.items[itemIndex]
                    item.title = snapshot.title
                    item.source = item.source ?? snapshot.source
                    item.thumbnail = snapshot.thumbnail ?? item.thumbnail

                    if let versionIndex = item.versions.firstIndex(where: { $0.id == snapshot.libraryVersionID }) {
                        let previous = item.versions[versionIndex]
                        let stateChanged = previous.processing.state != snapshot.processing.state
                            || previous.processing.stage != snapshot.processing.stage
                        let configurationChanged = previous.processing.actualModels != snapshot.processing.actualModels
                            || previous.processing.configuration != snapshot.processing.configuration
                        let artifactsChanged = !snapshot.artifacts.isEmpty && previous.artifacts != snapshot.artifacts

                        // Queue progress is a high-frequency in-memory overlay.
                        // Persist only structural phase/config/artifact changes so
                        // four concurrent tasks do not rewrite library.json on
                        // every tick while their list rows stay live.
                        if stateChanged || configurationChanged || artifactsChanged {
                            item.versions[versionIndex].processing = snapshot.processing
                        }
                        if artifactsChanged {
                            item.versions[versionIndex].artifacts = snapshot.artifacts
                        }
                        // Keep active rows stable while their progress ticks.
                        // Move a record only when it enters/leaves a terminal
                        // state, matching the product rule “no list jumping”.
                        if stateChanged, previous.processing.state.isActive != snapshot.processing.state.isActive {
                            item.updatedAt = snapshot.updatedAt
                        }
                    } else {
                        let nextVersion = (item.versions.map(\.number).max() ?? 0) + 1
                        item.versions.append(
                            LibraryVersion(
                                id: snapshot.libraryVersionID,
                                number: nextVersion,
                                processing: snapshot.processing,
                                artifacts: snapshot.artifacts,
                                createdAt: snapshot.createdAt
                            )
                        )
                        item.updatedAt = snapshot.updatedAt
                    }
                    stored.items[itemIndex] = item
                } else {
                    let version = LibraryVersion(
                        id: snapshot.libraryVersionID,
                        number: 1,
                        processing: snapshot.processing,
                        artifacts: snapshot.artifacts,
                        createdAt: snapshot.createdAt
                    )
                    stored.items.append(
                        MoongateCore.LibraryItem(
                            id: snapshot.libraryItemID,
                            title: snapshot.title,
                            source: snapshot.source,
                            thumbnail: snapshot.thumbnail,
                            versions: [version],
                            createdAt: snapshot.createdAt,
                            updatedAt: snapshot.updatedAt
                        )
                    )
                }
            }

            if stored != original {
                try await store.save(stored)
            }
            envelope = stored
            selectFirstItemIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension Notification.Name {
    static let moongateLibrarySearchFocus = Notification.Name("com.moongate.workspace.librarySearchFocus")
}

private struct QueueLibrarySnapshot: Sendable {
    let queueID: UUID
    let libraryItemID: UUID
    let libraryVersionID: UUID
    let title: String
    let source: LibrarySourceDescriptor?
    let thumbnail: LibrarySourceDescriptor?
    let processing: ProcessingSummary
    let artifacts: [LibraryArtifact]
    let speedText: String?
    let remainingSeconds: Double?
    let remainingIsApproximate: Bool
    let isEstimatingRemaining: Bool
    let statusText: String?
    let createdAt: Date
    let updatedAt: Date

    @MainActor
    init(_ item: QueueManager.QueueItem) {
        let now = Date()
        queueID = item.id
        libraryItemID = item.libraryItemID
        libraryVersionID = item.libraryVersionID
        title = item.title
        source = LibrarySourceDescriptor(urlString: item.request.url)
        thumbnail = item.thumbnailURL.flatMap { LibrarySourceDescriptor(urlString: $0.absoluteString) }
        processing = Self.processingSummary(for: item, updatedAt: now)
        artifacts = Self.libraryArtifacts(from: item)
        speedText = item.speedText
        remainingSeconds = item.remainingSeconds
        remainingIsApproximate = item.remainingIsApproximate
        isEstimatingRemaining = item.isEstimatingRemaining
        statusText = item.needsLogin.map {
            CoreL10n.text(
                en: "Login required · \($0.site)",
                zhHans: "需要登录 · \($0.site)",
                zhHant: "需要登入 · \($0.site)"
            )
        } ?? item.statusText
        createdAt = now
        updatedAt = now
    }

    @MainActor
    private static func processingSummary(for item: QueueManager.QueueItem, updatedAt: Date) -> ProcessingSummary {
        let state: LibraryItemState
        let stage: LibraryProcessingStage

        switch item.stage {
            case .queued:
                state = item.isDeferredDraft ? .queued : .downloading
                stage = .download
            case .cancelling:
                state = .cancelling
                stage = .recovery
            case .downloading:
                switch item.progressPhase {
                case .speechRecognition, .audioExtract, .subtitleSegment:
                    state = .transcribing
                    stage = .transcribe
                case .transcode:
                    state = .transcoding
                    stage = .transcode
                default:
                    state = .downloading
                    stage = .download
                }
            case .translating:
                state = .translating
                stage = .translate
            case .burning:
                state = .burning
                stage = .burning
            case .done:
                state = item.partialFailure ? .partialSuccess : .completed
                stage = .complete
            case .failed:
                state = item.needsLogin == nil ? .failed : .needsAttention
                stage = .recovery
            case .cancelled:
                state = .cancelled
                stage = .complete
        }

        let actualSource = item.resolvedSubtitleSource?.selectedKind ?? item.request.primarySubtitleTrack?.sourceKind
        let requestedTranscriptionModel: String?
        switch actualSource {
        case .localASR:
            requestedTranscriptionModel = item.settings.localASRModelID.isEmpty ? "Whisper" : item.settings.localASRModelID
        case .cloudASR:
            requestedTranscriptionModel = item.settings.cloudASRModel.isEmpty ? nil : item.settings.cloudASRModel
        default:
            requestedTranscriptionModel = nil
        }
        let requestedTranslationModel = item.chineseMode.requiresTranslation
            ? (item.settings.translationFollowsDefault ? item.settings.aiModel : item.settings.translationModel)
            : nil
        let safeTranslationModel = requestedTranslationModel?.isEmpty == true ? nil : requestedTranslationModel
        let configuration = LibraryProcessingConfiguration(
            outputFormat: item.request.outputFormat.rawValue,
            subtitleMode: item.chineseMode.rawValue,
            subtitleSource: actualSource?.rawValue,
            transcriptionModel: requestedTranscriptionModel,
            translationModel: safeTranslationModel,
            targetLanguage: item.chineseMode.requiresTranslation ? item.settings.translationTargetLanguage : nil,
            subtitleStyle: item.chineseMode == .off ? nil : item.settings.subtitleStyle.rawValue,
            quality: item.request.formatID
        )
        return ProcessingSummary(
            state: state,
            stage: stage,
            progress: item.overallProgress ?? item.progress ?? 0,
            actualModels: item.executedModels,
            configuration: configuration,
            updatedAt: updatedAt
        )
    }

    @MainActor
    private static func libraryArtifacts(from item: QueueManager.QueueItem) -> [LibraryArtifact] {
        let files = item.resultFiles
        let videoFiles = files.filter {
            QueueManager.videoExtensions.contains($0.pathExtension.lowercased())
        }
        // Burner inserts its new output before the still-clean input video.
        // Persist that distinction so a later vN reprocess can never burn
        // captions onto an already rendered result.
        let renderedVideo = item.chineseMode.requiresBurner && videoFiles.count > 1
            ? videoFiles.first?.standardizedFileURL
            : nil
        let root = ViewModel.appDownloadsDirectory.standardizedFileURL
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return files.compactMap { fileURL in
            let standardized = fileURL.standardizedFileURL
            guard standardized.path.hasPrefix(rootPrefix) else { return nil }
            let relativePath = String(standardized.path.dropFirst(rootPrefix.count))
            let role: LibraryArtifactRole
            switch standardized.pathExtension.lowercased() {
            case "mp4", "mov", "m4v", "mkv", "webm", "avi", "flv", "ts":
                role = standardized == renderedVideo ? .renderedVideo : .video
            case "srt", "vtt", "ass":
                role = TranslationLanguage.isTranslatedSubtitleFileName(standardized.lastPathComponent)
                    ? .translatedSubtitle : .sourceSubtitle
            default: role = .other
            }
            let values = try? standardized.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return try? LibraryArtifact(
                role: role,
                relativePath: relativePath,
                size: values?.fileSize.map(Int64.init),
                modifiedAt: values?.contentModificationDate
            )
        }
    }
}
