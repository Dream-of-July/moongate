import AppKit
import Combine
import Foundation
import UserNotifications
#if canImport(MoongateCore)
import MoongateCore
#endif

struct QueueCompletionNotification: Equatable {
    let completedCount: Int
    let partialFailureCount: Int
    let failedCount: Int
    let cancelledCount: Int
    let titles: [String]
}

@MainActor
protocol QueueCompletionNotifying: AnyObject {
    func queueDidComplete(_ notification: QueueCompletionNotification)
}

@MainActor
final class SystemQueueCompletionNotifier: QueueCompletionNotifying {
    private let settingsProvider: () -> AppSettings

    init(settingsProvider: @escaping () -> AppSettings) {
        self.settingsProvider = settingsProvider
    }

    func queueDidComplete(_ notification: QueueCompletionNotification) {
        let settings = settingsProvider()
        guard settings.completionNotificationsEnabled || settings.completionSoundEnabled else { return }

        let active = NSApp.isActive
        if settings.completionNotificationsEnabled, !active {
            let content = UNMutableNotificationContent()
            content.title = title(for: notification)
            content.body = body(for: notification)
            if settings.completionSoundEnabled {
                content.sound = .default
            }
            let request = UNNotificationRequest(
                identifier: "moongate.queue-complete.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        } else if settings.completionSoundEnabled {
            NSSound.beep()
        }
    }

    private func title(for notification: QueueCompletionNotification) -> String {
        if notification.completedCount == 1 {
            return CoreL10n.text(en: "Download complete", zhHans: "下载完成", zhHant: "下載完成")
        }
        return CoreL10n.text(
            en: "\(notification.completedCount) downloads complete",
            zhHans: "\(notification.completedCount) 个下载已完成",
            zhHant: "\(notification.completedCount) 個下載已完成"
        )
    }

    private func body(for notification: QueueCompletionNotification) -> String {
        if notification.completedCount == 1, let title = notification.titles.first {
            return title
        }
        if notification.partialFailureCount > 0 {
            return CoreL10n.text(
                en: "\(notification.partialFailureCount) item(s) need subtitle retry.",
                zhHans: "\(notification.partialFailureCount) 个任务需要重试字幕处理。",
                zhHant: "\(notification.partialFailureCount) 個任務需要重試字幕處理。"
            )
        }
        return CoreL10n.text(en: "All selected tasks have finished.", zhHans: "本批任务已完成。", zhHant: "本批任務已完成。")
    }
}

// StageSlotPool 已下沉到 MoongateCore（Sources/MoongateCore/StageSlotPool.swift）以支持行为单测。


/// 下载队列。每个 QueueItem 是一条「下载 →[翻译]→[烧录]」完整流水线，
/// 持有独立的 TaskControlToken，可随时独立暂停 / 恢复 / 取消，并发执行互不阻塞；
/// 三个阶段各有并发上限（下载/压制可在设置里调，翻译固定 2 防网关限流），
/// 暂停会让出占用的下载/压制槽位给其它任务，恢复时重新排队领取。
@MainActor
final class QueueManager: ObservableObject {

    /// 队列项当前所处阶段。暂停态不单列，由 QueueItem.isPaused 叠加表示。
    enum ItemStage: Equatable {
        case queued
        case cancelling
        case downloading
        case translating
        case burning
        case done
        case failed(String)
        case cancelled
    }

    enum PostDownloadProcessingKind: Equatable {
        case generic
        case transcoding
    }

    /// 下载/处理阶段的「需要登录该站点」信号。从 MoongateError 提取，供 QueueItemView 显示登录按钮。
    struct QueueLoginPrompt: Equatable {
        let site: String
        let loginURL: URL?
    }

    /// 从错误中提取登录提示：仅登录类错误（siteCookieRequired / loginRequired）返回非 nil。
    static func loginPrompt(from error: Error) -> QueueLoginPrompt? {
        switch error {
        case MoongateError.siteCookieRequired(let site, let url, _):
            return QueueLoginPrompt(site: site, loginURL: URL(string: url))
        case MoongateError.loginRequired(let site):
            return QueueLoginPrompt(site: site, loginURL: nil)
        default:
            return nil
        }
    }

    struct QueueItem: Identifiable {
        let id: UUID
        /// Durable-library identity. Normal downloads use a new item id; a
        /// reprocess task uses a fresh queue id but retains its parent item id.
        let libraryItemID: UUID
        /// Stable output-version identity used by the library projection. It is
        /// separate from QueueItem.id so reprocessing never overwrites v1.
        let libraryVersionID: UUID
        let title: String
        let thumbnailURL: URL?
        let info: VideoInfo
        var request: DownloadRequest
        var chineseMode: ChineseSubtitleMode
        /// 待开始时可编辑；`start(id:)` 会在后续生命周期切片中冻结为运行快照。
        var settings: AppSettings
        var stage: ItemStage
        /// 0...1；nil 表示不确定（处理 / 翻译启动等）
        var progress: Double?
        /// 整条任务的 0...1 进度；跨下载 / 转码 / 翻译 / 烧录保持单调。
        var overallProgress: Double?
        var speedText: String?
        var remainingSeconds: Double?
        var remainingIsApproximate: Bool = false
        var isEstimatingRemaining: Bool = false
        var progressPhase: QueueProgressPhase?
        var progressPlan: QueueProgressPlan
        var workPlan: TaskWorkPlan
        /// 暂停 / 部分成功 / 失败原因等附加说明
        var statusText: String?
        /// 已落盘的产物（下载文件、译文、烧录视频）
        var resultFiles: [URL]
        /// 仅在对应引擎真正被调用后写入。配置模型与实际调用模型
        /// 分开保存，避免资料库把待开始草稿误标为已执行的模型。
        var executedModels: LibraryActualModels = .init()
        var isPaused: Bool
        /// 下载已 100%、正在合并/转码/字幕转换（progress 为 nil 但仍处于 .downloading）。
        /// UI 据此显示「处理中…」而非「下载中…」（避免像卡死）。
        var isPostDownloadProcessing: Bool = false
        var postDownloadProcessingKind: PostDownloadProcessingKind?
        /// 部分成功：视频已下载但字幕处理失败（done 态显示「重试字幕处理」按钮）。
        var partialFailure: Bool = false
        /// 完成后检测到字幕时序可能不可靠（多为平台滚动字幕的 10ms 闪现），建议用本地 Whisper 重跑。
        var timingWarning: Bool = false
        /// 下载后源质量解析的结果：实际选中的源、是否回退到本地识别、回退原因。供 UI 展开区显示。
        var resolvedSubtitleSource: ResolvedSubtitleSource? = nil
        /// 面向用户的源说明（如“平台字幕质量较差，已自动改用本地识别”）。nil 时不显示。
        var subtitleSourceNote: String? = nil
        /// 失败态若为「需要登录该站点」：记录站点 host 与登录起始 URL，供 UI 显示登录按钮并在登录后自动重试。
        /// nil 表示这不是登录类失败（走普通重试）。
        var needsLogin: QueueLoginPrompt? = nil
        /// 本项流水线的控制令牌；retry 时换新的（旧的已 cancel）。
        var control: TaskControlToken
        /// 流水线代际：每次 enqueue/retry 递增；@MainActor 写回前校验，作废陈旧回调。
        var generation: Int = 0
        /// 重新处理任务可跳过网络下载，但仍会在启动时按冻结配置执行后处理。
        var skipDownloadWhenStarted: Bool
        var task: Task<Void, Never>?

        /// A queued item is editable only before its processing task is
        /// created. A slot-waiting task intentionally keeps `.queued` until
        /// its download stage begins, so the task reference is the stable
        /// boundary between a deferred draft and an already frozen run.
        var isDeferredDraft: Bool { stage == .queued && task == nil }

        @MainActor
        var canRetryWithLocalASR: Bool {
            guard case .done = stage else { return false }
            return resultFiles.contains {
                QueueManager.videoExtensions.contains($0.pathExtension.lowercased())
            }
        }

        mutating func clearProgress(resetOverall: Bool = false) {
            progress = nil
            speedText = nil
            remainingSeconds = nil
            remainingIsApproximate = false
            isEstimatingRemaining = false
            progressPhase = nil
            if resetOverall { overallProgress = nil }
        }

        mutating func completeProgress() {
            clearProgress()
            overallProgress = 1
        }
    }

    /// A single pipeline attempt. The queue item stays editable only until this
    /// context is created; later updates must not leak into an already-started
    /// Task, including one that has not yet reached its first await.
    private struct RunContext {
        let id: UUID
        let generation: Int
        let control: TaskControlToken
        let snapshot: ProcessingSnapshot
        let asr: ASRRunResources

        var request: DownloadRequest { snapshot.request }
        var mode: ChineseSubtitleMode { snapshot.mode }
        var settings: AppSettings { snapshot.settings }
        var skipDownload: Bool { snapshot.skipDownload }
        var initialFiles: [URL] { snapshot.initialFiles }
    }

    /// ASR can be reconfigured in Settings while another item is running.
    /// Keep the concrete generators in the run context so that a started task
    /// never changes model or transport half-way through its pipeline.
    private struct ASRRunResources {
        let local: (any LocalASRSubtitleGenerator)?
        let cloud: (any CloudASRSubtitleGenerator)?
        let localModelLabel: String?
        let cloudModelLabel: String?
    }

    @Published var items: [QueueItem] = []

    /// 同时下载数（设置变更时由 ViewModel 同步；调大即时生效）。
    var maxConcurrentDownloads: Int {
        didSet { downloadPool.wakeAll() }
    }
    /// 同时压制数（设置里的原始值）。
    var maxConcurrentBurns: Int {
        didSet { burnPool.wakeAll() }
    }
    /// 实际压制并发上限：硬件编码后端时比原始值多放一路（编码走媒体引擎、不占 CPU），
    /// 软件后端时等于原始值。由 syncConcurrency 从 settings.effectiveMaxConcurrentBurns 同步。
    private var effectiveBurnCapacity: Int {
        didSet { if effectiveBurnCapacity != oldValue { burnPool.wakeAll() } }
    }

    private let engine: any DownloadEngine
    private lazy var downloadPool = StageSlotPool { [weak self] in self?.maxConcurrentDownloads ?? 3 }
    private lazy var burnPool = StageSlotPool { [weak self] in self?.effectiveBurnCapacity ?? 2 }
    /// 翻译并发固定 2（每项内部还有 3 路分块并行，再高容易撞网关限流）。
    private lazy var translatePool = StageSlotPool { 2 }
    /// 正在占用槽位的项（暂停让位 / 阶段结束释放用）。带代际：重试后旧流水线的
    /// 延迟释放不得动新代际刚领到的槽位。
    private var holdingPool: [UUID: (generation: Int, pool: StageSlotPool)] = [:]
    /// 暂停时让出的槽位池：恢复时需先重新领到槽位再 SIGCONT。
    private var resumePool: [UUID: (generation: Int, pool: StageSlotPool)] = [:]
    private var progressPhaseStarts: [UUID: (generation: Int, phase: QueueProgressPhase, startedAt: Date)] = [:]
    private var phaseDurationSamples: [QueueProgressPhase: [Double]] = [:]
    private var localASRGenerator: (any LocalASRSubtitleGenerator)?
    private var cloudASRGenerator: (any CloudASRSubtitleGenerator)?
    private let localASRRunProvider: ((AppSettings) -> (any LocalASRSubtitleGenerator)?)?
    private let cloudASRRunProvider: ((AppSettings, (any LocalASRSubtitleGenerator)?) -> (any CloudASRSubtitleGenerator)?)?
    private let completionNotifier: (any QueueCompletionNotifying)?
    private var notifiedTerminalIDs = Set<UUID>()

    /// 视频文件后缀（用于在产物里识别可烧录的视频）
    /// 可播放/可本地重识别判定共用的视频扩展名集合。非 private 以便同 target 的三栏预览
    /// （SplitLayoutView.playableVideo）复用同一份来源，避免两处副本漂移（播放叠层与重识别资格判定不一致）。
    static let videoExtensions: Set<String> = [
        "mp4", "mov", "mkv", "webm", "m4v", "avi", "flv", "ts",
    ]

    init(
        engine: any DownloadEngine = makeDefaultEngine(),
        localASRGenerator: (any LocalASRSubtitleGenerator)? = nil,
        cloudASRGenerator: (any CloudASRSubtitleGenerator)? = nil,
        localASRRunProvider: ((AppSettings) -> (any LocalASRSubtitleGenerator)?)? = nil,
        cloudASRRunProvider: ((AppSettings, (any LocalASRSubtitleGenerator)?) -> (any CloudASRSubtitleGenerator)?)? = nil,
        completionNotifier: (any QueueCompletionNotifying)? = nil
    ) {
        self.engine = engine
        self.localASRGenerator = localASRGenerator
        self.cloudASRGenerator = cloudASRGenerator
        self.localASRRunProvider = localASRRunProvider
        self.cloudASRRunProvider = cloudASRRunProvider
        self.completionNotifier = completionNotifier
        let settings = AppSettings.load()
        self.maxConcurrentDownloads = settings.maxConcurrentDownloads
        self.maxConcurrentBurns = settings.maxConcurrentBurns
        self.effectiveBurnCapacity = settings.effectiveMaxConcurrentBurns
    }

    var hasLocalASRGenerator: Bool { localASRGenerator != nil }
    var hasCloudASRGenerator: Bool { cloudASRGenerator != nil }

    func syncLocalASRGenerator(from settings: AppSettings) {
        localASRGenerator = LocalASRGeneratorFactory.make(settings: settings)
    }

    func syncCloudASRGenerator(from settings: AppSettings) {
        cloudASRGenerator = CloudASRGeneratorFactory.make(
            settings: settings,
            localASRGenerator: localASRGenerator
        )
    }

    func canRetryWithLocalASR(_ id: UUID) -> Bool {
        guard let item = item(id) else { return false }
        return item.canRetryWithLocalASR
    }

    /// 设置保存后同步并发上限（didSet 会唤醒排队者）。
    func syncConcurrency(from settings: AppSettings) {
        if maxConcurrentDownloads != settings.maxConcurrentDownloads {
            maxConcurrentDownloads = settings.maxConcurrentDownloads
        }
        if maxConcurrentBurns != settings.maxConcurrentBurns {
            maxConcurrentBurns = settings.maxConcurrentBurns
        }
        // 后端切换（硬件/软件）会改变有效压制并发，即使原始压制数没变也要同步。
        if effectiveBurnCapacity != settings.effectiveMaxConcurrentBurns {
            effectiveBurnCapacity = settings.effectiveMaxConcurrentBurns
        }
    }

    // MARK: - 槽位辅助

    private func runMatches(_ context: RunContext) -> Bool {
        guard let current = item(context.id) else { return false }
        return current.generation == context.generation && current.control === context.control
    }

    private func isRunActive(id: UUID, generation: Int, control: TaskControlToken) -> Bool {
        guard let current = item(id) else { return false }
        return current.generation == generation
            && current.control === control
            && !control.isCancelled
            && current.stage != .cancelling
    }

    /// Returns false for an obsolete or cancelled attempt. Cancellation is
    /// settled by runPipeline's outer defer, after any nested slot release has
    /// converged, so the visible state cannot outrun the actual pipeline.
    @discardableResult
    private func ensureRunActive(_ context: RunContext) -> Bool {
        isRunActive(id: context.id, generation: context.generation, control: context.control)
    }

    private func finishCancelled(id: UUID, generation: Int) {
        guard let current = item(id), current.generation == generation else { return }
        guard current.control.isCancelled || current.stage == .cancelling else { return }
        update(id, generation: generation) {
            $0.stage = .cancelled
            $0.isPaused = false
            $0.clearProgress()
            $0.statusText = $0.resultFiles.isEmpty
                ? CoreL10n.t(L.Queue.cancelled)
                : CoreL10n.t(L.Queue.cancelledSaved)
            $0.isPostDownloadProcessing = false
            $0.postDownloadProcessingKind = nil
            $0.task = nil
        }
        clearProgressTracking(id)
    }

    private func settleRunCancellationIfNeeded(_ context: RunContext) {
        guard runMatches(context) else { return }
        guard context.control.isCancelled || item(context.id)?.stage == .cancelling else { return }
        finishCancelled(id: context.id, generation: context.generation)
    }

    /// 等槽位（满员时先把状态文案改成等待提示），拿到后按代际登记为持有。
    private func acquireSlot(
        _ pool: StageSlotPool,
        context: RunContext,
        waitingText: String
    ) async throws {
        if !pool.hasFreeSlot {
            update(context.id, generation: context.generation) { $0.statusText = waitingText }
        }
        try await pool.acquire(id: context.id, control: context.control)
        // 等待期间可能已被 retry / remove / cancel：旧代际拿到的槽立即归还，避免错记。
        guard ensureRunActive(context) else {
            pool.release()
            throw MoongateError.cancelled
        }
        holdingPool[context.id] = (context.generation, pool)
        update(context.id, generation: context.generation) {
            if $0.statusText == waitingText { $0.statusText = nil }
        }
    }

    /// 阶段结束（成功或失败）释放槽位；只释放本代际登记的，暂停已让位时自然空操作。
    private func releaseSlot(_ id: UUID, generation: Int) {
        guard let holding = holdingPool[id], holding.generation == generation else { return }
        holdingPool.removeValue(forKey: id)
        holding.pool.release()
    }

    private func wakeFromAllPools(_ id: UUID) {
        downloadPool.wake(id: id)
        burnPool.wake(id: id)
        translatePool.wake(id: id)
    }

    // MARK: - 派生状态

    /// 未到终态的任务数（queued/downloading/translating/burning，含已暂停）。
    /// 关窗确认据此统计，避免「只剩暂停任务」时静默丢弃。
    var openTaskCount: Int {
        items.filter { Self.isOpen($0.stage) }.count
    }

    /// 其中处于暂停态的数量。
    var pausedOpenTaskCount: Int {
        items.filter { $0.isPaused && Self.isOpen($0.stage) }.count
    }

    private static func isOpen(_ stage: ItemStage) -> Bool {
        switch stage {
        case .queued, .cancelling, .downloading, .translating, .burning:
            return true
        case .done, .failed, .cancelled:
            return false
        }
    }

    /// 存在已到终态（done/failed/cancelled）的项，「清除已完成」入口据此显示。
    var hasFinishedItems: Bool {
        items.contains { !Self.isOpen($0.stage) }
    }

    var progressSnapshot: QueueProgressSnapshot {
        QueueProgressEstimator.queueSnapshot(items: items.map { item in
            let terminal = !Self.isOpen(item.stage)
            return TaskProgressSnapshot(
                overallProgress: terminal ? 1 : item.overallProgress,
                remainingSeconds: item.remainingSeconds,
                isEstimatingRemaining: item.isEstimatingRemaining,
                isTerminal: terminal,
                plan: item.progressPlan,
                currentPhase: item.progressPhase,
                workPlan: item.workPlan
            )
        }, phaseMedianDurations: phaseMedianDurations, phaseCapacities: [
            .download: max(1, maxConcurrentDownloads),
            .audioExtract: max(1, maxConcurrentDownloads),
            .speechRecognition: 1,
            .subtitleSegment: 2,
            .transcode: max(1, maxConcurrentDownloads),
            .translate: 2,
            .burn: max(1, effectiveBurnCapacity),
        ])
    }

    private var phaseMedianDurations: [QueueProgressPhase: Double] {
        phaseDurationSamples.compactMapValues { samples in
            let valid = samples.filter { $0.isFinite && $0 >= 0 }.sorted()
            guard !valid.isEmpty else { return nil }
            return valid[valid.count / 2]
        }
    }

    private static func progressPlan(for request: DownloadRequest, mode: ChineseSubtitleMode) -> QueueProgressPlan {
        QueueProgressPlan(
            shouldTranscode: Transcoder.needsProcessing(request.outputFormat),
            shouldTranslate: mode.requiresTranslation,
            shouldBurn: mode.requiresBurner
        )
    }

    private static func workPlan(for request: DownloadRequest, mode: ChineseSubtitleMode) -> TaskWorkPlan {
        let needsLocalASR = shouldPrepareLocalASRSource(for: request)
        // Weights approximate real wall-clock so the bar tracks time: download, transcription,
        // translation and burn are all multi-minute phases. (Previously speechRecognition=12 vs
        // translate=1 made the bar hit ~87% during transcription, then crawl through the slow
        // translation — looking like it had "reached the translating zone" before transcription
        // finished.)
        return TaskWorkPlan(
            shouldExtractAudio: needsLocalASR,
            shouldRunASR: needsLocalASR,
            shouldSegmentSubtitles: needsLocalASR,
            shouldTranscode: Transcoder.needsProcessing(request.outputFormat),
            shouldTranslate: mode.requiresTranslation,
            shouldBurn: mode.requiresBurner,
            downloadUnits: 2,
            audioExtractUnits: 1,
            speechRecognitionUnits: needsLocalASR ? 6 : 1,
            subtitleSegmentUnits: 1,
            transcodeUnits: 2,
            translateUnits: 6,
            burnUnits: 4
        )
    }

    private static func shouldPrepareLocalASRSource(for request: DownloadRequest) -> Bool {
        if request.subtitleSourcePolicy == .compareLocalASR {
            if let primarySubtitleTrack = request.primarySubtitleTrack {
                return primarySubtitleTrack.sourceKind == .platformAuto
            }
            return request.requestedSubtitleTracks.contains { $0.sourceKind == .platformAuto }
        }
        if let primarySubtitleTrack = request.primarySubtitleTrack {
            return primarySubtitleTrack.sourceKind == .localASR
        }
        let hasNonLocalTrack = request.requestedSubtitleTracks.contains { $0.sourceKind != .localASR }
        return !hasNonLocalTrack && request.requestedSubtitleTracks.contains { $0.sourceKind == .localASR }
    }

    // MARK: - 入队

    /// 去重键：优先 videoID，取不到用 sourceURL + formatID。
    private static func dedupeKey(videoID: String, sourceURL: String, formatID: String) -> String {
        let id = videoID.trimmingCharacters(in: .whitespaces)
        if !id.isEmpty, id != "video" { return "id:" + id }
        return "url:" + sourceURL + "|" + formatID
    }

    /// 队列里是否已有同源且未到终态（非 done/failed/cancelled）的任务。
    func hasOpenDuplicate(videoID: String, sourceURL: String, formatID: String) -> Bool {
        let key = Self.dedupeKey(videoID: videoID, sourceURL: sourceURL, formatID: formatID)
        return items.contains { item in
            guard Self.isOpen(item.stage) else { return false }
            return Self.dedupeKey(
                videoID: item.info.videoID,
                sourceURL: item.request.url,
                formatID: item.request.formatID
            ) == key
        }
    }

    /// 仅待开始草稿可改配置。运行任务的配置必须由其启动快照决定。
    @discardableResult
    func updateQueuedConfiguration(
        id: UUID,
        request: DownloadRequest,
        mode: ChineseSubtitleMode,
        settings: AppSettings
    ) -> Bool {
        guard let target = item(id),
              target.stage == .queued,
              target.task == nil,
              !target.control.isCancelled else {
            return false
        }

        update(id) {
            $0.request = request
            $0.chineseMode = mode
            $0.settings = settings
            $0.progressPlan = Self.progressPlan(for: request, mode: mode)
            $0.workPlan = Self.workPlan(for: request, mode: mode)
            $0.clearProgress(resetOverall: true)
            $0.statusText = nil
            $0.isPostDownloadProcessing = false
            $0.postDownloadProcessingKind = nil
        }
        return true
    }

    @discardableResult
    func enqueue(
        info: VideoInfo,
        request: DownloadRequest,
        chineseMode: ChineseSubtitleMode,
        settings: AppSettings,
        libraryItemID: UUID? = nil,
        libraryVersionID: UUID? = nil,
        startImmediately: Bool = true
    ) -> UUID {
        let id = UUID()
        let control = TaskControlToken()
        let item = QueueItem(
            id: id,
            libraryItemID: libraryItemID ?? id,
            libraryVersionID: libraryVersionID ?? UUID(),
            title: info.title,
            thumbnailURL: info.thumbnailURL,
            info: info,
            request: request,
            chineseMode: chineseMode,
            settings: settings,
            stage: .queued,
            progress: nil,
            overallProgress: nil,
            speedText: nil,
            remainingSeconds: nil,
            progressPhase: nil,
            progressPlan: Self.progressPlan(for: request, mode: chineseMode),
            workPlan: Self.workPlan(for: request, mode: chineseMode),
            statusText: nil,
            resultFiles: [],
            isPaused: false,
            control: control,
            skipDownloadWhenStarted: false
        )
        items.append(item)
        if startImmediately {
            _ = beginRun(id: id)
        }
        return id
    }

    /// Starts a new processing task from existing artifacts. It uses a new
    /// queue/version id while keeping the original library item id, so the UI
    /// can present the result as v2 instead of replacing v1.
    @discardableResult
    func enqueueReprocess(
        info: VideoInfo,
        request: DownloadRequest,
        chineseMode: ChineseSubtitleMode,
        settings: AppSettings,
        existingFiles: [URL],
        libraryItemID: UUID,
        libraryVersionID: UUID,
        reuseExistingArtifacts: Bool,
        startImmediately: Bool = true
    ) -> UUID {
        let id = UUID()
        let control = TaskControlToken()
        let item = QueueItem(
            id: id,
            libraryItemID: libraryItemID,
            libraryVersionID: libraryVersionID,
            title: info.title,
            thumbnailURL: info.thumbnailURL,
            info: info,
            request: request,
            chineseMode: chineseMode,
            settings: settings,
            stage: .queued,
            progress: nil,
            overallProgress: nil,
            speedText: nil,
            remainingSeconds: nil,
            progressPhase: nil,
            progressPlan: Self.progressPlan(for: request, mode: chineseMode),
            workPlan: Self.workPlan(for: request, mode: chineseMode),
            statusText: nil,
            resultFiles: existingFiles,
            isPaused: false,
            control: control,
            skipDownloadWhenStarted: reuseExistingArtifacts
        )
        items.append(item)
        if startImmediately {
            _ = beginRun(id: id)
        }
        return id
    }

    // MARK: - 流水线

    private func beginRun(id: UUID) -> Bool {
        guard let target = item(id),
              target.stage == .queued,
              target.task == nil,
              !target.control.isCancelled else {
            return false
        }

        let snapshot = ProcessingSnapshot(
            request: target.request,
            mode: target.chineseMode,
            settings: target.settings,
            skipDownload: target.skipDownloadWhenStarted,
            initialFiles: target.resultFiles
        )
        let asr = makeASRRunResources(settings: snapshot.settings)
        if Self.needsFreshLocalASRSource(
            for: snapshot.request,
            initialFiles: snapshot.initialFiles
        ), asr.local == nil {
            update(id) {
                $0.statusText = CoreL10n.text(
                    en: "Local subtitle recognition isn't enabled. Choose automatic captions or enable it in Subtitles & Languages.",
                    zhHans: "本机字幕识别未启用。请改用自动字幕，或在“字幕与语言”中启用。",
                    zhHant: "本機字幕識別未啟用。請改用自動字幕，或在「字幕與語言」中啟用。"
                )
            }
            return false
        }
        if snapshot.request.subtitleSourcePolicy == .cloudASR, asr.cloud == nil {
            update(id) {
                $0.statusText = CoreL10n.t(L.Ready.cloudASRSetupRequired)
            }
            return false
        }

        let context = RunContext(
            id: id,
            generation: target.generation,
            control: target.control,
            snapshot: snapshot,
            asr: asr
        )
        notifiedTerminalIDs.remove(id)
        let task = Task { [weak self] in
            guard let self else { return }
            await self.runPipeline(context)
        }
        update(id) { $0.task = task }
        return true
    }

    private func makeASRRunResources(settings: AppSettings) -> ASRRunResources {
        let local = localASRRunProvider?(settings) ?? localASRGenerator
        let cloud = cloudASRRunProvider?(settings, local) ?? cloudASRGenerator
        let localModelLabel: String?
        if local == nil {
            localModelLabel = nil
        } else if settings.localASRPreciseModeEnabled {
            localModelLabel = "sidecar:local-precise"
        } else {
            let configured = settings.localASRModelID.trimmingCharacters(in: .whitespacesAndNewlines)
            localModelLabel = configured.isEmpty ? "Whisper" : configured
        }
        let configuredCloud = settings.cloudASRModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let cloudModelLabel = cloud == nil || configuredCloud.isEmpty ? nil : configuredCloud
        return ASRRunResources(
            local: local,
            cloud: cloud,
            localModelLabel: localModelLabel,
            cloudModelLabel: cloudModelLabel
        )
    }

    /// Starts one deferred draft and freezes its current request, mode, and settings.
    @discardableResult
    func start(id: UUID) -> Bool {
        beginRun(id: id)
    }

    /// Starts every deferred draft in queue order. Already-started and terminal items are ignored.
    @discardableResult
    func startAll() -> Int {
        let ids = items.compactMap { item -> UUID? in
            item.isDeferredDraft ? item.id : nil
        }
        var started = 0
        for id in ids where beginRun(id: id) {
            started += 1
        }
        return started
    }

    /// Runs one immutable configuration snapshot for a queue generation.
    private func runPipeline(_ context: RunContext) async {
        defer {
            // Nested stage defers run first; don't expose a terminal cancel
            // until the pool bookkeeping for this run has converged.
            releaseSlot(context.id, generation: context.generation)
            if resumePool[context.id]?.generation == context.generation {
                resumePool.removeValue(forKey: context.id)
            }
            settleRunCancellationIfNeeded(context)
        }
        guard ensureRunActive(context), let info = item(context.id)?.info else { return }
        let id = context.id
        let control = context.control
        let settings = context.settings
        let mode = context.mode
        let request = context.request
        let generation = context.generation

        // 1. 下载
        var downloadFiles: [URL]
        if context.skipDownload {
            downloadFiles = context.initialFiles
            update(id, generation: generation) {
                $0.overallProgress = QueueProgressEstimator.taskOverallProgress(
                    workPlan: $0.workPlan,
                    currentPhase: .download,
                    phaseProgress: 1,
                    previousOverallProgress: $0.overallProgress
                )
                $0.clearProgress()
            }
            // Reprocessing an isolated vN artifact must never call the
            // network engine again just because the requested output format
            // needs conversion. Reuse the normal transcode implementation
            // while holding the same bounded processing slot as downloads.
            if Transcoder.needsProcessing(request.outputFormat) {
                let requestedHDRFallback = request.preferHDR
                do {
                    try await acquireSlot(
                        downloadPool,
                        context: context,
                        waitingText: CoreL10n.t(L.Queue.waitingForDownloadSlot)
                    )
                    defer { releaseSlot(id, generation: generation) }
                    downloadFiles = try await transcodeExistingVideoIfNeeded(
                        downloadFiles,
                        initialFiles: context.initialFiles,
                        request: request,
                        settings: settings,
                        id: id,
                        generation: generation,
                        control: control,
                        sourceIsHDRFallback: requestedHDRFallback
                    )
                } catch {
                    finishPipelineFailure(id: id, generation: generation, error: error)
                    return
                }
            }
        } else {
            do {
                try await acquireSlot(
                    downloadPool,
                    context: context,
                    waitingText: CoreL10n.t(L.Queue.waitingForDownloadSlot)
                )
                defer { releaseSlot(id, generation: generation) }
                update(id, generation: generation) {
                    $0.stage = .downloading
                    $0.clearProgress(resetOverall: true)
                    $0.statusText = nil
                    $0.isPostDownloadProcessing = false
                    $0.postDownloadProcessingKind = nil
                    self.applyProgress(&$0, id: id, generation: generation, phase: .download, phaseProgress: nil)
                }
                let result = try await engine.download(request, control: control) { [weak self] p in
                    Task { @MainActor in
                        self?.applyDownloadProgress(id: id, generation: generation, p)
                    }
                }
                guard ensureRunActive(context) else { return }
                downloadFiles = result.files
                // A quality/original-format refresh may start with isolated
                // v1 subtitle artifacts. Keep those alongside the freshly
                // downloaded video; otherwise mode == .off would complete
                // and silently drop them from the vN library projection.
                let retainedSubtitleFiles = context.initialFiles.filter { file in
                    ["srt", "vtt", "ass"].contains(file.pathExtension.lowercased())
                }
                for subtitle in retainedSubtitleFiles where !downloadFiles.contains(subtitle) {
                    downloadFiles.append(subtitle)
                }
                completeProgressPhase(id, generation: generation, phase: .download)
                update(id, generation: generation) { $0.resultFiles = downloadFiles; $0.clearProgress() }
                // Downloads and isolated reprocesses share this path, so a
                // non-original output is converted exactly once in either case.
                let requestedHDRFallback = request.preferHDR
                downloadFiles = try await transcodeExistingVideoIfNeeded(
                    downloadFiles,
                    initialFiles: context.initialFiles,
                    request: request,
                    settings: settings,
                    id: id,
                    generation: generation,
                    control: control,
                    sourceIsHDRFallback: requestedHDRFallback
                )
            } catch {
                finishPipelineFailure(id: id, generation: generation, error: error)
                return
            }
        }

        do {
            downloadFiles = try appendImportedSubtitleFileIfNeeded(
                files: downloadFiles,
                request: request
            )
            downloadFiles = try await prepareLocalASRSourceSubtitleIfNeeded(
                files: downloadFiles,
                request: request,
                id: id,
                generation: generation,
                control: control,
                asr: context.asr
            )
            downloadFiles = try await prepareCloudASRSourceSubtitleIfNeeded(
                files: downloadFiles,
                request: request,
                id: id,
                generation: generation,
                control: control,
                asr: context.asr
            )
            guard ensureRunActive(context) else { return }
        } catch {
            guard runMatches(context) else { return }
            settlePartial(
                id,
                generation: generation,
                files: item(id)?.resultFiles ?? downloadFiles,
                error: error,
                phase: CoreL10n.text(en: "speech recognition", zhHans: "语音识别", zhHant: "語音識別")
            )
            return
        }

        let shouldResolveSourceOnly = mode == .off
            && (request.primarySubtitleTrack != nil
                || request.importedSubtitleFileURL != nil
                || request.subtitleSourcePolicy == .cloudASR)

        // 完全不处理字幕：直接完成。下载源字幕 SRT 仍要走来源解析和任务详情披露。
        guard mode != .off || shouldResolveSourceOnly else {
            finishDone(id, generation: generation, files: downloadFiles, statusText: nil)
            return
        }

        // 找翻译源字幕；没有就完成并提示已跳过
        let primarySubtitleTrack = request.primarySubtitleTrack
        let preferredLang = request.effectivePreferredLanguageCode
            ?? primarySubtitleTrack?.languageCode
            ?? request.subtitleLangs.first
            ?? request.autoSubtitleLangs.first
        guard var sourceSubtitle = Self.pickSourceSubtitle(
            from: downloadFiles,
            preferredLang: preferredLang,
            preferredTrack: primarySubtitleTrack
        ) else {
            finishDone(
                id, generation: generation, files: downloadFiles,
                statusText: mode == .burnOriginal
                    ? CoreL10n.t(L.Queue.noSubtitleFileSkippedBurn)
                    : CoreL10n.t(L.Queue.noSubtitleFileSkippedTranslation)
            )
            return
        }

        // 下载后源质量解析：用户选了某语言后，若选中的是平台自动字幕且质量门判定不可用，
        // 在本地识别可用时自动改用 Whisper（语言优先、自动定源）。人工字幕与用户显式选的
        // 本地识别都不过门。质量门只看自动字幕自身可用性（语言/密度/覆盖/乱码），绝不比时序。
        do {
            let resolution = try await resolveSubtitleSourceWithQualityGate(
                pickedSource: sourceSubtitle,
                downloadFiles: &downloadFiles,
                preferredLang: preferredLang,
                primarySubtitleTrack: primarySubtitleTrack,
                request: request,
                info: info,
                id: id,
                generation: generation,
                control: control,
                asr: context.asr
            )
            guard ensureRunActive(context) else { return }
            sourceSubtitle = resolution.selectedFile
            if let note = resolution.note {
                update(id, generation: generation) {
                    $0.resolvedSubtitleSource = resolution.resolved
                    $0.subtitleSourceNote = note
                }
            } else {
                update(id, generation: generation) { $0.resolvedSubtitleSource = resolution.resolved }
            }
        } catch {
            guard runMatches(context) else { return }
            // 用户取消要如实中止；其余错误（回退 whisper 生成失败）不阻塞，沿用原平台字幕继续翻译。
            if isCancellation(error) || !ensureRunActive(context) {
                return
            }
        }

        if shouldResolveSourceOnly {
            finishDone(id, generation: generation, files: downloadFiles, statusText: nil)
            return
        }

        // 平台字幕（非本地识别）若清洗后出现大量 ~10ms 闪现 cue（YouTube 滚动字幕常见），完成后
        // 温和提示用户：可用本地 Whisper 重跑。不强制上来做选择，只在结果可能不准时给建议。
        if !Self.isLocalASRSubtitle(sourceSubtitle.lastPathComponent) {
            let assessment = SubtitleTimingHealth.assess(subtitleFileURL: sourceSubtitle)
            if assessment.looksUnreliable {
                update(id, generation: generation) { $0.timingWarning = true }
            }
        }

        // 直接烧录模式：跳过翻译，把所选源字幕原样压进视频（无论语言、无需配置翻译服务）。
        if mode == .burnOriginal {
            guard let video = downloadFiles.first(where: {
                Self.videoExtensions.contains($0.pathExtension.lowercased())
            }) else {
                finishDone(id, generation: generation, files: downloadFiles, statusText: CoreL10n.t(L.Queue.noVideoFileSkippedBurn))
                return
            }
            do {
                try await acquireSlot(
                    burnPool,
                    context: context,
                    waitingText: CoreL10n.t(L.Queue.waitingForBurnSlot)
                )
                defer { releaseSlot(id, generation: generation) }
                update(id, generation: generation) {
                    $0.stage = .burning
                    $0.clearProgress()
                    $0.statusText = CoreL10n.t(L.Queue.burnOriginalSubtitle)
                    $0.isPostDownloadProcessing = false
                    $0.postDownloadProcessingKind = nil
                    self.applyProgress(&$0, id: id, generation: generation, phase: .burn, phaseProgress: nil)
                }
                let burnSubtitle = try Self.ensureSRTSubtitle(sourceSubtitle)
                let burner = makeBurner()
                let burned = try await burner.burn(
                    video: video,
                    subtitle: burnSubtitle,
                    maxHeight: settings.maxBurnHeight,
                    backend: settings.encodeBackend,
                    alwaysH264: settings.burnAlwaysH264,
                    control: control,
                    outputTag: CoreL10n.t(L.Queue.subtitleVersionTag),
                    subtitleFontScale: settings.subtitleFontScale.multiplier,
                    subtitleAlignment: settings.subtitlePosition.assAlignment,
                    subtitleColorBGRHex: settings.subtitleColor.assBGRHex
                ) { [weak self] p in
                    Task { @MainActor in
                        self?.update(id, generation: generation) {
                            guard $0.stage == .burning else { return }
                            self?.applyProgress(&$0, id: id, generation: generation, phase: .burn, phaseProgress: p)
                        }
                    }
                }
                guard ensureRunActive(context) else { return }
                completeProgressPhase(id, generation: generation, phase: .burn)
                update(id, generation: generation) {
                    $0.resultFiles.removeAll { $0 == burned }
                    $0.resultFiles.insert(burned, at: 0)
                }
                finishDone(id, generation: generation, files: item(id)?.resultFiles ?? downloadFiles, statusText: CoreL10n.t(L.Queue.burnedOriginalSubtitle))
            } catch {
                guard runMatches(context) else { return }
                settlePartial(id, generation: generation, files: item(id)?.resultFiles ?? downloadFiles, error: error, phase: CoreL10n.t(L.Queue.phaseBurn))
            }
            return
        }

        // 成熟的同语言软字幕：源字幕已与翻译目标语言同一脚本时直接使用，跳过 LLM 翻译。
        // 判定优先用 request 里记录的 lang，回退按所选文件名 ".<lang>.srt/.vtt" 解析。
        let sourceLang = primarySubtitleTrack?.languageCode ?? Self.langCode(of: sourceSubtitle)
        let sourceMatchesTarget = TranslationLanguage.matches(
            source: sourceLang,
            target: settings.translationTargetLanguage
        )
        if sourceMatchesTarget {
            // srtOnly：原目标语言字幕即结果；若源是 VTT，先转成 SRT，保持模式语义。
            guard mode == .burnIn else {
                do {
                    let normalized = try Self.ensureSRTSubtitle(sourceSubtitle)
                    var files = downloadFiles
                    if !files.contains(normalized) { files.append(normalized) }
                    finishDone(id, generation: generation, files: files, statusText: CoreL10n.t(L.Queue.sourceTargetSubtitleSkippedTranslation))
                } catch {
                    settlePartial(id, generation: generation, files: downloadFiles, error: error, phase: CoreL10n.t(L.Queue.phaseTranslation))
                }
                return
            }
            // burnIn：直接拿目标语言字幕去烧录；VTT 先转成 SRT。
            guard let video = downloadFiles.first(where: {
                Self.videoExtensions.contains($0.pathExtension.lowercased())
            }) else {
                finishDone(id, generation: generation, files: downloadFiles, statusText: CoreL10n.t(L.Queue.noVideoFileSkippedBurn))
                return
            }
            do {
                try await acquireSlot(
                    burnPool,
                    context: context,
                    waitingText: CoreL10n.t(L.Queue.waitingForBurnSlot)
                )
                defer { releaseSlot(id, generation: generation) }
                update(id, generation: generation) {
                    $0.stage = .burning
                    $0.clearProgress()
                    $0.statusText = CoreL10n.t(L.Queue.sourceTargetSubtitleBurn)
                    $0.isPostDownloadProcessing = false
                    $0.postDownloadProcessingKind = nil
                    self.applyProgress(&$0, id: id, generation: generation, phase: .burn, phaseProgress: nil)
                }
                let burnSubtitle = try Self.ensureSRTSubtitle(sourceSubtitle)
                let burner = makeBurner()
                let burned = try await burner.burn(
                    video: video,
                    subtitle: burnSubtitle,
                    maxHeight: settings.maxBurnHeight,
                    backend: settings.encodeBackend,
                    alwaysH264: settings.burnAlwaysH264,
                    control: control,
                    subtitleFontScale: settings.subtitleFontScale.multiplier,
                    subtitleAlignment: settings.subtitlePosition.assAlignment,
                    subtitleColorBGRHex: settings.subtitleColor.assBGRHex
                ) { [weak self] p in
                    Task { @MainActor in
                        self?.update(id, generation: generation) {
                            guard $0.stage == .burning else { return }
                            self?.applyProgress(&$0, id: id, generation: generation, phase: .burn, phaseProgress: p)
                        }
                    }
                }
                guard ensureRunActive(context) else { return }
                completeProgressPhase(id, generation: generation, phase: .burn)
                update(id, generation: generation) {
                    $0.resultFiles.removeAll { $0 == burned }
                    $0.resultFiles.insert(burned, at: 0)
                }
                finishDone(id, generation: generation, files: item(id)?.resultFiles ?? downloadFiles, statusText: CoreL10n.t(L.Queue.burnedSourceTargetSubtitle))
            } catch {
                guard runMatches(context) else { return }
                settlePartial(id, generation: generation, files: item(id)?.resultFiles ?? downloadFiles, error: error, phase: CoreL10n.t(L.Queue.phaseBurn))
            }
            return
        }

        // 2. 翻译
        let zhSrt: URL
        do {
            try await acquireSlot(
                translatePool,
                context: context,
                waitingText: CoreL10n.t(L.Queue.waitingForTranslationSlot)
            )
            defer { releaseSlot(id, generation: generation) }
            update(id, generation: generation) {
                $0.stage = .translating
                $0.clearProgress()
                $0.statusText = nil
                $0.isPostDownloadProcessing = false
                $0.postDownloadProcessingKind = nil
                let configuredModel = $0.settings.translationFollowsDefault
                    ? $0.settings.aiModel
                    : $0.settings.translationModel
                $0.executedModels.translation = configuredModel
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty ? nil : configuredModel
                self.applyProgress(&$0, id: id, generation: generation, phase: .translate, phaseProgress: nil)
            }
            let translator = makeTranslator(settings: settings)
            zhSrt = try await translator.translate(
                srtFile: sourceSubtitle,
                style: settings.subtitleStyle,
                context: settings.makeTranslationContext(sourceLanguage: primarySubtitleTrack?.languageCode),
                control: control
            ) { [weak self] p in
                    Task { @MainActor in
                        self?.update(id, generation: generation) {
                            guard $0.stage == .translating else { return }
                            self?.applyProgress(&$0, id: id, generation: generation, phase: .translate, phaseProgress: p)
                        }
                    }
                }
            guard ensureRunActive(context) else { return }
            completeProgressPhase(id, generation: generation, phase: .translate)
            update(id, generation: generation) {
                $0.clearProgress()
                if !$0.resultFiles.contains(zhSrt) { $0.resultFiles.append(zhSrt) }
            }
        } catch {
            guard runMatches(context) else { return }
            settlePartial(id, generation: generation, files: downloadFiles, error: error, phase: CoreL10n.t(L.Queue.phaseTranslation))
            return
        }

        // 3. 烧录（仅 burnIn）
        guard mode == .burnIn else {
            finishDone(id, generation: generation, files: item(id)?.resultFiles ?? downloadFiles, statusText: nil)
            return
        }
        guard let video = downloadFiles.first(where: {
            Self.videoExtensions.contains($0.pathExtension.lowercased())
        }) else {
            finishDone(id, generation: generation, files: item(id)?.resultFiles ?? downloadFiles, statusText: CoreL10n.t(L.Queue.noVideoFileSkippedBurn))
            return
        }

        do {
            try await acquireSlot(
                burnPool,
                context: context,
                waitingText: CoreL10n.t(L.Queue.waitingForBurnSlot)
            )
            defer { releaseSlot(id, generation: generation) }
            update(id, generation: generation) {
                $0.stage = .burning
                $0.clearProgress()
                $0.statusText = nil
                $0.isPostDownloadProcessing = false
                $0.postDownloadProcessingKind = nil
                self.applyProgress(&$0, id: id, generation: generation, phase: .burn, phaseProgress: nil)
            }
            let burner = makeBurner()
            let burned = try await burner.burn(
                video: video,
                subtitle: zhSrt,
                maxHeight: settings.maxBurnHeight,
                backend: settings.encodeBackend,
                alwaysH264: settings.burnAlwaysH264,
                control: control,
                subtitleFontScale: settings.subtitleFontScale.multiplier,
                subtitleAlignment: settings.subtitlePosition.assAlignment,
                subtitleColorBGRHex: settings.subtitleColor.assBGRHex
            ) { [weak self] p in
                    Task { @MainActor in
                        self?.update(id, generation: generation) {
                            guard $0.stage == .burning else { return }
                            self?.applyProgress(&$0, id: id, generation: generation, phase: .burn, phaseProgress: p)
                        }
                    }
                }
            guard ensureRunActive(context) else { return }
            completeProgressPhase(id, generation: generation, phase: .burn)
            update(id, generation: generation) {
                $0.resultFiles.removeAll { $0 == burned }
                $0.resultFiles.insert(burned, at: 0)
            }
            finishDone(id, generation: generation, files: item(id)?.resultFiles ?? downloadFiles, statusText: nil)
        } catch {
            guard runMatches(context) else { return }
            settlePartial(id, generation: generation, files: item(id)?.resultFiles ?? downloadFiles, error: error, phase: CoreL10n.t(L.Queue.phaseBurn))
        }
    }

    /// Runs output conversion against a file already owned by this queue item.
    /// The caller decides whether it is holding a download slot; both a fresh
    /// download and an isolated vN reprocess use this exact code path so a
    /// format change cannot accidentally download twice or skip conversion.
    private func transcodeExistingVideoIfNeeded(
        _ files: [URL],
        initialFiles: [URL],
        request: DownloadRequest,
        settings: AppSettings,
        id: UUID,
        generation: Int,
        control: TaskControlToken,
        sourceIsHDRFallback: Bool
    ) async throws -> [URL] {
        guard isRunActive(id: id, generation: generation, control: control) else {
            throw MoongateError.cancelled
        }
        guard Transcoder.needsProcessing(request.outputFormat),
              let videoFile = files.first(where: {
                  Self.videoExtensions.contains($0.pathExtension.lowercased())
              }) else {
            return files
        }

        update(id, generation: generation) {
            $0.stage = .downloading
            $0.clearProgress()
            $0.statusText = nil
            $0.isPostDownloadProcessing = true
            $0.postDownloadProcessingKind = .transcoding
            self.applyProgress(&$0, id: id, generation: generation, phase: .transcode, phaseProgress: nil)
        }
        // Transcoder probes the actual artifact; the HDR preference is only a
        // fallback when probing is unavailable.
        let transcoded = try await Transcoder().transcode(
            inputFile: videoFile,
            format: request.outputFormat,
            sourceVCodec: nil,
            sourceIsHDR: sourceIsHDRFallback,
            backend: settings.encodeBackend,
            control: control
        ) { [weak self] fraction in
            Task { @MainActor in
                guard let self,
                      self.isRunActive(id: id, generation: generation, control: control) else { return }
                self.update(id, generation: generation) {
                    self.applyProgress(&$0, id: id, generation: generation, phase: .transcode, phaseProgress: fraction)
                }
            }
        }
        guard isRunActive(id: id, generation: generation, control: control) else {
            throw MoongateError.cancelled
        }

        let isInitialArtifact = initialFiles.contains {
            $0.standardizedFileURL == videoFile.standardizedFileURL
        }
        if transcoded != videoFile && !isInitialArtifact {
            try? FileManager.default.removeItem(at: videoFile)
        }
        var resultFiles = files.map { $0 == videoFile ? transcoded : $0 }
        if !resultFiles.contains(transcoded) { resultFiles.append(transcoded) }
        completeProgressPhase(id, generation: generation, phase: .transcode)
        update(id, generation: generation) {
            $0.resultFiles = resultFiles
            $0.clearProgress()
            $0.statusText = nil
            $0.isPostDownloadProcessing = false
            $0.postDownloadProcessingKind = nil
        }
        return resultFiles
    }

    private func finishPipelineFailure(id: UUID, generation: Int, error: Error) {
        guard let current = item(id), current.generation == generation else { return }
        guard !current.control.isCancelled, current.stage != .cancelling else { return }
        if !isCancellation(error) {
            update(id, generation: generation) {
                $0.stage = .failed(Self.shortReason(of: error))
                $0.isPaused = false
                $0.clearProgress()
                $0.statusText = CoreL10n.t(L.Queue.failedWithReason, Self.shortReason(of: error))
                $0.needsLogin = Self.loginPrompt(from: error)
                $0.isPostDownloadProcessing = false
                $0.postDownloadProcessingKind = nil
                $0.task = nil
            }
        }
        clearProgressTracking(id)
    }

    /// 下载进度显示态：进度分数（nil=不确定）+ 是否「处理中」（合并/收尾，显示不确定）。
    struct DownloadProgressState: Equatable {
        var progress: Double?
        var isProcessing: Bool
    }

    /// 由当前显示态 + yt-dlp 上报百分比推导下一显示态（纯函数）。
    /// Engine 层会把 DASH 分流下载聚合成一个整体百分比；这里再做防御，避免任何
    /// 迟到/回落的子进程百分比让用户可见进度倒退。仅过滤 < 0.5 个百分点的高频抖动。
    /// 合并阶段由 [Merger] 行单独触发「处理中」。
    static func nextDownloadProgressState(_ current: DownloadProgressState, incoming: Double?) -> DownloadProgressState {
        guard let next = incoming else { return current }
        if let old = current.progress, next <= old || abs(next - old) < 0.005 { return current }
        return DownloadProgressState(progress: next, isProcessing: false)
    }

    private func progressPhaseStart(id: UUID, generation: Int, phase: QueueProgressPhase, now: Date) -> Date {
        if let existing = progressPhaseStarts[id],
           existing.generation == generation,
           existing.phase == phase {
            return existing.startedAt
        }
        progressPhaseStarts[id] = (generation, phase, now)
        return now
    }

    private func clearProgressTracking(_ id: UUID) {
        progressPhaseStarts.removeValue(forKey: id)
    }

    private func completeProgressPhase(
        _ id: UUID,
        generation: Int,
        phase expectedPhase: QueueProgressPhase,
        now: Date = Date()
    ) {
        guard let existing = progressPhaseStarts[id],
              existing.generation == generation,
              existing.phase == expectedPhase else {
            return
        }
        let duration = max(0.1, now.timeIntervalSince(existing.startedAt))
        progressPhaseStarts.removeValue(forKey: id)
        var samples = phaseDurationSamples[expectedPhase] ?? []
        samples.append(duration)
        if samples.count > 9 {
            samples.removeFirst(samples.count - 9)
        }
        phaseDurationSamples[expectedPhase] = samples
    }

    private func applyProgress(
        _ item: inout QueueItem,
        id: UUID,
        generation: Int,
        phase: QueueProgressPhase,
        phaseProgress: Double?,
        speedText: String? = nil,
        etaText: String? = nil,
        now: Date = Date()
    ) {
        let normalized = QueueProgressEstimator.normalizedFraction(phaseProgress)
        let startedAt = progressPhaseStart(id: id, generation: generation, phase: phase, now: now)
        item.progress = normalized
        item.progressPhase = phase
        item.overallProgress = QueueProgressEstimator.taskOverallProgress(
            workPlan: item.workPlan,
            currentPhase: phase,
            phaseProgress: normalized,
            previousOverallProgress: item.overallProgress
        )
        item.speedText = speedText
        let remaining = QueueProgressEstimator.estimatedRemainingSeconds(
            elapsedSeconds: max(0, now.timeIntervalSince(startedAt)),
            phaseProgress: normalized,
            sourceEtaSeconds: QueueProgressEstimator.parseEtaSeconds(etaText)
        )
        item.remainingSeconds = remaining?.seconds
        item.remainingIsApproximate = remaining?.isApproximate ?? false
        item.isEstimatingRemaining = remaining == nil && normalized != 1 && !item.isPaused
    }

    /// 下载进度上报：转 0...1（processing 阶段进度不确定，置 nil）。
    /// 节流：进度变化 < 1% 时不写 items，避免高频 objectWillChange 在长队列时拖累 UI。
    private func applyDownloadProgress(id: UUID, generation: Int, _ p: DownloadProgress) {
        update(id, generation: generation) {
            // 进入烧录/翻译后不再被迟到的下载回调覆盖
            guard $0.stage == .downloading else { return }
            switch p.phase {
            case .downloading:
                let newValue = p.percent.map { min(max($0 / 100, 0), 1) }
                let isProcessing = $0.isPostDownloadProcessing && $0.postDownloadProcessingKind == .generic
                let nextState = Self.nextDownloadProgressState(
                    DownloadProgressState(progress: $0.progress, isProcessing: isProcessing), incoming: newValue)
                self.applyProgress(
                    &$0,
                    id: id,
                    generation: generation,
                    phase: .download,
                    phaseProgress: nextState.progress,
                    speedText: p.speedText,
                    etaText: p.etaText
                )
                $0.isPostDownloadProcessing = nextState.isProcessing
                $0.postDownloadProcessingKind = nextState.isProcessing ? .generic : nil
            case .preparing:
                self.applyProgress(&$0, id: id, generation: generation, phase: .download, phaseProgress: nil)
                $0.isPostDownloadProcessing = false
                $0.postDownloadProcessingKind = nil
            case .finished:
                self.applyProgress(&$0, id: id, generation: generation, phase: .download, phaseProgress: 1)
                $0.clearProgress()
                $0.isPostDownloadProcessing = false
                $0.postDownloadProcessingKind = nil
            case .processing:
                // 下载 100% 后的合并/转码：进度不确定，标记为「处理中」避免像卡死。
                self.applyProgress(&$0, id: id, generation: generation, phase: .download, phaseProgress: nil)
                $0.isPostDownloadProcessing = true
                $0.postDownloadProcessingKind = .generic
                $0.statusText = p.detail
            }
        }
    }

    /// 部分成功：下载产物已落盘 → .done + 失败说明（可重试字幕处理）；否则视为 .failed。
    /// 取消（MoongateError.cancelled / Task 取消）→ .cancelled，保留已下产物。
    private func settlePartial(_ id: UUID, generation: Int, files: [URL], error: Error, phase: String) {
        guard let current = item(id), current.generation == generation else { return }
        guard !current.control.isCancelled, current.stage != .cancelling else { return }
        guard !isCancellation(error) else { return }
        let reason = Self.shortReason(of: error)
        if !files.isEmpty {
            update(id, generation: generation) {
                $0.stage = .done
                $0.isPaused = false
                $0.completeProgress()
                $0.partialFailure = true
                $0.statusText = CoreL10n.t(L.Queue.partialSubtitleFailed, phase, reason)
                $0.isPostDownloadProcessing = false
                $0.postDownloadProcessingKind = nil
                $0.task = nil
            }
            clearProgressTracking(id)
        } else {
            update(id, generation: generation) {
                $0.stage = .failed(reason)
                $0.isPaused = false
                $0.clearProgress()
                $0.statusText = CoreL10n.t(L.Queue.failedWithReason, reason)
                $0.needsLogin = Self.loginPrompt(from: error)
                $0.isPostDownloadProcessing = false
                $0.postDownloadProcessingKind = nil
                $0.task = nil
            }
            clearProgressTracking(id)
        }
    }

    private func finishDone(_ id: UUID, generation: Int, files: [URL], statusText: String?) {
        guard let current = item(id), current.generation == generation else { return }
        guard !current.control.isCancelled, current.stage != .cancelling else { return }
        update(id, generation: generation) {
            $0.stage = .done
            $0.isPaused = false
            $0.completeProgress()
            $0.partialFailure = false
            $0.isPostDownloadProcessing = false
            $0.postDownloadProcessingKind = nil
            $0.resultFiles = files.isEmpty ? $0.resultFiles : files
            $0.statusText = statusText
            $0.task = nil
        }
        clearProgressTracking(id)
    }

    // MARK: - 单项控制

    @discardableResult
    func pause(_ id: UUID) -> Bool {
        guard let target = item(id),
              Self.isOpen(target.stage),
              target.stage != .cancelling,
              !target.isPaused else { return false }
        guard target.control.pause() else { return false }
        // 让出占用的下载/压制槽位给其它任务；恢复时重新排队领取。
        // 翻译请求不是本地可挂起进程，暂停后仍可能有分块请求在飞行中，不能释放翻译并发位。
        if let holding = holdingPool[id], holding.generation == target.generation {
            if holding.pool !== translatePool {
                holdingPool.removeValue(forKey: id)
                holding.pool.release()
                resumePool[id] = holding
            }
        }
        update(id) { $0.isPaused = true }
        return true
    }

    @discardableResult
    func resume(_ id: UUID) -> Bool {
        guard let target = item(id), target.stage != .cancelling, target.isPaused else { return false }
        guard let parked = resumePool.removeValue(forKey: id),
              parked.generation == target.generation else {
            // 没让过位（翻译阶段 / 排队中暂停）：直接恢复，acquire 循环或 gate 会接着走。
            guard target.control.resume() else { return false }
            update(id) { $0.isPaused = false }
            return true
        }
        // 让过位的：先重新领到槽位再 SIGCONT，避免恢复瞬间超出并发上限。
        guard target.control.isPaused else { return false }
        let control = target.control
        let generation = target.generation
        update(id) { $0.isPaused = false }
        update(id, generation: generation) { $0.statusText = CoreL10n.t(L.Queue.waitingSlotResume) }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await parked.pool.acquire(id: id, control: control, respectPause: false)
                guard self.isRunActive(id: id, generation: generation, control: control) else {
                    parked.pool.release()
                    return
                }
                self.holdingPool[id] = (generation, parked.pool)
                self.update(id, generation: generation) {
                    if $0.statusText == CoreL10n.t(L.Queue.waitingSlotResume) { $0.statusText = nil }
                }
                control.resume()
            } catch {
                // 等槽期间被取消：流水线任务自会收敛，这里不动状态。
            }
        }
        return true
    }

    func cancel(_ id: UUID) {
        guard let target = item(id), Self.isOpen(target.stage), target.stage != .cancelling else { return }
        if target.stage == .queued, target.task == nil {
            target.control.cancel()
            finishCancelled(id: id, generation: target.generation)
            return
        }
        update(id, generation: target.generation) {
            $0.stage = .cancelling
            $0.isPaused = false
            $0.clearProgress()
            $0.statusText = CoreL10n.text(
                en: "Cancelling…", zhHans: "正在取消…", zhHant: "正在取消…"
            )
            $0.isPostDownloadProcessing = false
            $0.postDownloadProcessingKind = nil
        }
        resumePool.removeValue(forKey: id)
        clearProgressTracking(id)
        target.control.cancel()
        target.task?.cancel()
        // 还在排队等槽位的，唤出来让 acquire 循环抛出取消。
        wakeFromAllPools(id)
    }

    func remove(_ id: UUID) {
        guard let target = item(id) else { return }
        guard target.stage != .cancelling else { return }
        if Self.isOpen(target.stage) {
            cancel(id)
            return
        }
        resumePool.removeValue(forKey: id)
        clearProgressTracking(id)
        target.control.cancel()
        target.task?.cancel()
        wakeFromAllPools(id)
        notifiedTerminalIDs.remove(id)
        items.removeAll { $0.id == id }
    }

    /// 重试：保留已下载产物则跳过下载，仅重跑字幕处理；无产物则整条重跑。
    /// 登录成功后调用：重试所有因该站点需要登录而失败的队列项。
    /// site 为 nil 时重试所有登录类失败项（登录窗不总能回传站点）。
    func retryFailedNeedingLogin(site: String?) {
        let targets = items.filter { item in
            guard case .failed = item.stage, let prompt = item.needsLogin else { return false }
            guard let site else { return true }
            return prompt.site.caseInsensitiveCompare(site) == .orderedSame
        }
        for target in targets {
            retry(target.id)
        }
    }

    func retry(_ id: UUID) {
        guard let old = item(id), !Self.isOpen(old.stage) else { return }
        // 旧 control 若仍登记着进程，确保释放；清掉旧代际的槽位记账。
        resumePool.removeValue(forKey: id)
        clearProgressTracking(id)
        old.control.cancel()
        old.task?.cancel()
        wakeFromAllPools(id)

        let hasVideo = old.resultFiles.contains {
            Self.videoExtensions.contains($0.pathExtension.lowercased())
        }
        let skipDownload = hasVideo && old.chineseMode != .off
        let newControl = TaskControlToken()
        update(id) {
            $0.control = newControl
            $0.generation += 1
            $0.stage = .queued
            $0.isPaused = false
            $0.clearProgress(resetOverall: true)
            $0.isPostDownloadProcessing = false
            $0.postDownloadProcessingKind = nil
            $0.partialFailure = false
            $0.needsLogin = nil
            $0.executedModels = .init()
            $0.statusText = skipDownload ? nil : CoreL10n.t(L.Queue.retryDownloadAndProcess)
            if !skipDownload { $0.resultFiles = [] }
            $0.skipDownloadWhenStarted = skipDownload
            $0.task = nil
        }
        _ = beginRun(id: id)
    }

    func retryWithLocalASR(_ id: UUID) {
        guard let old = item(id),
              !Self.isOpen(old.stage),
              localASRGenerator != nil else { return }
        let request = Self.localASRRetryRequest(for: old.request)
        let retryMode: ChineseSubtitleMode = .burnIn
        let hasVideo = old.resultFiles.contains {
            Self.videoExtensions.contains($0.pathExtension.lowercased())
        }
        guard hasVideo else { return }

        resumePool.removeValue(forKey: id)
        clearProgressTracking(id)
        old.control.cancel()
        old.task?.cancel()
        wakeFromAllPools(id)

        let newControl = TaskControlToken()
        update(id) {
            $0.request = request
            $0.chineseMode = retryMode
            $0.progressPlan = Self.progressPlan(for: request, mode: retryMode)
            $0.workPlan = Self.workPlan(for: request, mode: retryMode)
            $0.control = newControl
            $0.generation += 1
            $0.stage = .queued
            $0.isPaused = false
            $0.clearProgress(resetOverall: true)
            $0.isPostDownloadProcessing = false
            $0.postDownloadProcessingKind = nil
            $0.partialFailure = false
            $0.needsLogin = nil
            $0.timingWarning = false
            $0.executedModels = .init()
            $0.statusText = nil
            $0.skipDownloadWhenStarted = true
            $0.task = nil
        }
        _ = beginRun(id: id)
    }

    private static func localASRRetryRequest(for request: DownloadRequest) -> DownloadRequest {
        let source = request.requestedSubtitleTracks.first(where: { $0.sourceKind != .localASR })
            ?? request.primarySubtitleTrack
            ?? request.requestedSubtitleTracks.first
        let languageCode = source?.languageCode.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let inferredLanguageCode = request.preferredTitle
            .flatMap { SubtitleLanguageRecommender.inferredLocalASRLanguageCode(title: $0) }
        let localASRLanguageCode = languageCode.isEmpty ? (inferredLanguageCode ?? "auto") : languageCode
        let localASRTrack = SubtitleChoice(
            languageCode: localASRLanguageCode,
            label: source?.label ?? CoreL10n.t(L.Ready.localASRAutoDetectLabel),
            sourceKind: .localASR,
            provider: "whisper.cpp",
            variant: "local"
        )
        return DownloadRequest(
            url: request.url,
            videoID: request.videoID,
            formatID: request.formatID,
            subtitleLangs: [],
            autoSubtitleLangs: [],
            subtitleTracks: [localASRTrack],
            primarySubtitleTrackID: localASRTrack.id,
            preferredSubtitleLanguageCode: localASRTrack.languageCode,
            sourceLanguageIntent: localASRLanguageCode == "auto" ? .automatic : .language(localASRLanguageCode),
            subtitleSourcePolicy: .forceLocalASR,
            destinationDirectory: request.destinationDirectory,
            preferredTitle: request.preferredTitle,
            preferHDR: request.preferHDR,
            outputFormat: request.outputFormat
        )
    }

    private static func localASRPromptMetadata(info: VideoInfo) -> ASRPromptMetadata {
        ASRPromptMetadata(
            title: info.title,
            channel: info.uploader
        )
    }

    /// 在访达中选中该项的产物（烧录视频排第一）。
    func revealInFinder(_ id: UUID) {
        guard let target = item(id), !target.resultFiles.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(target.resultFiles)
    }

    /// 一次移除所有已到终态（done/failed/cancelled）的项。
    func clearFinished() {
        let finishedIDs = items.filter { !Self.isOpen($0.stage) }.map(\.id)
        notifiedTerminalIDs.subtract(Set(finishedIDs))
        items.removeAll { !Self.isOpen($0.stage) }
    }

    // MARK: - 工具

    private func index(of id: UUID) -> Int? {
        items.firstIndex { $0.id == id }
    }

    private func item(_ id: UUID) -> QueueItem? {
        guard let i = index(of: id) else { return nil }
        return items[i]
    }

    /// 按 id 定位并就地修改；项已被移除时安全跳过。
    private func update(_ id: UUID, _ mutate: (inout QueueItem) -> Void) {
        guard let i = index(of: id) else { return }
        mutate(&items[i])
        notifyQueueCompletionIfNeeded()
    }

    /// 代际校验版：仅当当前 generation 与捕获值一致时才写回，作废重试后的陈旧回调。
    private func update(_ id: UUID, generation: Int, _ mutate: (inout QueueItem) -> Void) {
        guard let i = index(of: id), items[i].generation == generation else { return }
        mutate(&items[i])
        notifyQueueCompletionIfNeeded()
    }

    private func notifyQueueCompletionIfNeeded() {
        guard let completionNotifier else { return }
        let openItems = items.filter { Self.isOpen($0.stage) }
        guard openItems.isEmpty else { return }
        let terminalItems = items.filter { !Self.isOpen($0.stage) && !notifiedTerminalIDs.contains($0.id) }
        guard !terminalItems.isEmpty else { return }

        notifiedTerminalIDs.formUnion(terminalItems.map(\.id))
        let completedItems = terminalItems.filter {
            if case .done = $0.stage { return true }
            return false
        }
        guard !completedItems.isEmpty else { return }

        let failedCount = terminalItems.filter {
            if case .failed = $0.stage { return true }
            return false
        }.count
        let cancelledCount = terminalItems.filter { $0.stage == .cancelled }.count
        completionNotifier.queueDidComplete(QueueCompletionNotification(
            completedCount: completedItems.count,
            partialFailureCount: completedItems.filter(\.partialFailure).count,
            failedCount: failedCount,
            cancelledCount: cancelledCount,
            titles: completedItems.map(\.title)
        ))
    }

    private func isCancellation(_ error: Error) -> Bool {
        if case MoongateError.cancelled = error { return true }
        return error is CancellationError
    }

    struct SubtitleSourceResolution {
        let selectedFile: URL
        let resolved: ResolvedSubtitleSource
        /// User-facing note for the disclosure area; nil when nothing noteworthy happened.
        let note: String?
    }

    /// Post-download source resolution. Manual subtitles and an explicit local-ASR pick pass
    /// through untouched. A platform auto-caption is run through `PlatformSubtitleQualityGate`
    /// (intrinsic usability only — never timing): if unusable and a local-ASR generator is
    /// available, Whisper is generated and used; if unusable but local ASR is unavailable, the
    /// auto-caption is kept (non-blocking) and the reasons are recorded so the UI can offer the
    /// "enable local recognition" entry point.
    private func resolveSubtitleSourceWithQualityGate(
        pickedSource: URL,
        downloadFiles: inout [URL],
        preferredLang: String?,
        primarySubtitleTrack: SubtitleChoice?,
        request: DownloadRequest,
        info: VideoInfo,
        id: UUID,
        generation: Int,
        control: TaskControlToken,
        asr: ASRRunResources
    ) async throws -> SubtitleSourceResolution {
        guard isRunActive(id: id, generation: generation, control: control) else {
            throw MoongateError.cancelled
        }
        let language = preferredLang ?? Self.langCode(of: pickedSource) ?? ""
        let pickedIsLocalASR = Self.isLocalASRSubtitle(pickedSource.lastPathComponent)
        let pickedIsCloudASR = Self.isCloudASRSubtitle(pickedSource.lastPathComponent)
        let pickedIsAuto: Bool
        if pickedIsCloudASR || pickedIsLocalASR {
            pickedIsAuto = false
        } else if let primarySubtitleTrack {
            pickedIsAuto = primarySubtitleTrack.sourceKind == .platformAuto
        } else {
            pickedIsAuto = pickedSource.pathExtension.lowercased() == "vtt"
        }
        let videoDurationSeconds = PlatformSubtitleQualityGate.parseDurationSeconds(info.durationText)
        func candidate(
            kind: SubtitleSourceKind,
            fileURL: URL?,
            displayName: String? = nil,
            provider: String? = nil
        ) -> SubtitleSourceCandidate {
            SubtitleSourceCandidate(
                id: "\(kind.rawValue):\(language):\(fileURL?.path ?? "missing")",
                kind: kind,
                languageCode: language.isEmpty ? "auto" : language,
                displayName: displayName ?? fileURL?.lastPathComponent ?? kind.rawValue,
                fileURL: fileURL,
                isGenerated: kind == .localASR || kind == .cloudASR || kind == .platformAuto,
                provider: provider
            )
        }
        func resolverResult(candidates: [SubtitleSourceCandidate]) -> ResolvedSubtitleSource? {
            SubtitleSourceResolver.resolve(SubtitleResolutionRequest(
                languageIntent: request.sourceLanguageIntent,
                sourcePolicy: request.subtitleSourcePolicy,
                candidates: candidates,
                videoDurationSeconds: videoDurationSeconds
            ))
        }
        func resolvedSource(
            selectedFile: URL,
            selectedKind: SubtitleSourceKind,
            candidates: [SubtitleSourceCandidate],
            fallbackReasons: [PlatformSubtitleQualityGate.Reason] = []
        ) -> ResolvedSubtitleSource {
            guard let resolved = resolverResult(candidates: candidates) else {
                return ResolvedSubtitleSource(
                    languageCode: language,
                    selectedFile: selectedFile,
                    selectedKind: selectedKind,
                    fallbackReasons: fallbackReasons)
            }
            return ResolvedSubtitleSource(
                languageCode: resolved.languageCode,
                selectedFile: selectedFile,
                selectedKind: selectedKind,
                qualityVerdict: resolved.qualityVerdict,
                sourceQualityVerdict: resolved.sourceQualityVerdict,
                usedLocalASRFallback: selectedKind == .localASR && pickedIsAuto,
                fallbackReasons: fallbackReasons,
                candidateReports: resolved.candidateReports)
        }

        // Manual subtitle or explicit local-ASR pick → no gate.
        if pickedIsLocalASR {
            return SubtitleSourceResolution(
                selectedFile: pickedSource,
                resolved: resolvedSource(
                    selectedFile: pickedSource,
                    selectedKind: .localASR,
                    candidates: [
                        candidate(
                            kind: .localASR,
                            fileURL: pickedSource,
                            displayName: primarySubtitleTrack?.label,
                            provider: "whisper.cpp")
                    ]),
                note: nil)
        }
        if pickedIsCloudASR {
            return SubtitleSourceResolution(
                selectedFile: pickedSource,
                resolved: resolvedSource(
                    selectedFile: pickedSource,
                    selectedKind: .cloudASR,
                    candidates: [
                        candidate(
                            kind: .cloudASR,
                            fileURL: pickedSource,
                            displayName: primarySubtitleTrack?.label,
                            provider: "OpenAI-compatible")
                    ]),
                note: nil)
        }
        guard pickedIsAuto else {
            // Manual / official subtitle: trusted, no gate.
            let kind = primarySubtitleTrack?.sourceKind ?? .manual
            return SubtitleSourceResolution(
                selectedFile: pickedSource,
                resolved: resolvedSource(
                    selectedFile: pickedSource,
                    selectedKind: kind,
                    candidates: [
                        candidate(kind: kind, fileURL: pickedSource, displayName: primarySubtitleTrack?.label)
                    ]),
                note: nil)
        }

        // Platform auto-caption: assess intrinsic usability ONCE via the unified decision engine.
        // No separate gate + scorer double-run, and no "门(布尔) || 评分器(枚举)" 双裁决 OR —
        // the engine's gate verdict is the sole authority for "should we generate Whisper".
        let platformCandidate = candidate(
            kind: .platformAuto,
            fileURL: pickedSource,
            displayName: primarySubtitleTrack?.label,
            provider: primarySubtitleTrack?.provider
        )
        let platformAssessment = SubtitleSourceDecisionEngine.assess(
            candidate: platformCandidate,
            requestedSourceLanguageCode: preferredLang,
            videoDurationSeconds: videoDurationSeconds
        )
        let generatorUnavailableNote = platformAssessment.gateUsable && platformAssessment.verdict >= .usable
            ? CoreL10n.t(L.Queue.subtitleSourceCompareLocalASRUnavailable)
            : CoreL10n.t(L.Queue.subtitleSourceLowQualityEnableLocalASR)
        switch SubtitleSourceDecisionEngine.generationPlan(
            policy: request.subtitleSourcePolicy,
            platform: platformAssessment,
            localASRAvailable: asr.local != nil,
            cloudASRAvailable: asr.cloud != nil
        ) {
        case .none:
            return SubtitleSourceResolution(
                selectedFile: pickedSource,
                resolved: resolvedSource(
                    selectedFile: pickedSource,
                    selectedKind: .platformAuto,
                    candidates: [platformCandidate]),
                note: nil)
        case .keepPlatformRecordReasons(let reasons):
            // Policy wanted local ASR but no generator is configured: keep the auto-caption
            // (non-blocking) and record reasons for the UI.
            return SubtitleSourceResolution(
                selectedFile: pickedSource,
                resolved: resolvedSource(
                    selectedFile: pickedSource,
                    selectedKind: .platformAuto,
                    candidates: [platformCandidate],
                    fallbackReasons: reasons),
                note: generatorUnavailableNote)
        case .generateLocalASRThenChoose:
            break
        }

        // Engine planned local ASR generation. Need a generator and a downloaded video file.
        guard let localASRGenerator = asr.local,
              let videoFile = downloadFiles.first(where: {
                  Self.videoExtensions.contains($0.pathExtension.lowercased())
              }) else {
            return SubtitleSourceResolution(
                selectedFile: pickedSource,
                resolved: resolvedSource(
                    selectedFile: pickedSource,
                    selectedKind: .platformAuto,
                    candidates: [platformCandidate],
                    fallbackReasons: platformAssessment.gateReasons),
                note: generatorUnavailableNote)
        }

        // Generate Whisper for this language and let the resolver compare it with the platform source.
        update(id, generation: generation) {
            $0.stage = .downloading
            $0.clearProgress()
            $0.statusText = nil
            $0.isPostDownloadProcessing = true
            $0.postDownloadProcessingKind = .generic
            self.applyProgress(&$0, id: id, generation: generation, phase: .audioExtract, phaseProgress: nil)
        }
        let generated = try await localASRGenerator.generateSourceSubtitle(
            videoFile: videoFile,
            languageCode: language.isEmpty ? "auto" : language,
            promptMetadata: Self.localASRPromptMetadata(info: info),
            control: control
        ) { [weak self] progress in
            Task { @MainActor in
                guard let self, self.item(id)?.generation == generation else { return }
                self.applyASRProgress(id: id, generation: generation, progress)
            }
        }
        let sourceSRT = generated.url
        guard isRunActive(id: id, generation: generation, control: control) else {
            throw MoongateError.cancelled
        }
        update(id, generation: generation) {
            $0.executedModels.transcription = asr.localModelLabel
        }
        completeProgressPhase(id, generation: generation, phase: .audioExtract)
        completeProgressPhase(id, generation: generation, phase: .speechRecognition)
        completeProgressPhase(id, generation: generation, phase: .subtitleSegment)
        if !downloadFiles.contains(sourceSRT) { downloadFiles.append(sourceSRT) }

        // B3 弱语言云端救场（opt-in）：本地 whisper 对 sung 中/粤/韩有转写硬上限。若本地结果质量较低，
        // 且用户已配置并同意云端识别（cloudASRGenerator != nil 已隐含 cloudASREnabled && consentAccepted），
        // 则用云端重识别取代本地源。绝不自动上传——没配置/没同意就保持本地结果。
        var finalSourceSRT = sourceSRT
        var finalConfidence = generated.confidence
        var usedCloudEscalation = false
        let generatedLocalCandidate = candidate(kind: .localASR, fileURL: sourceSRT, provider: "whisper.cpp")
        let generatedLocalAssessment = SubtitleSourceDecisionEngine.assess(
            candidate: generatedLocalCandidate,
            requestedSourceLanguageCode: preferredLang,
            videoDurationSeconds: videoDurationSeconds
        )
        if SubtitleSourceDecisionEngine.shouldEscalateGeneratedLocalASR(
            policy: request.subtitleSourcePolicy,
            localAssessment: generatedLocalAssessment,
            localASRConfidenceIsLowQuality: generated.confidence?.isLowQuality == true,
            cloudASRAvailable: asr.cloud != nil) {
            if let cloudSRT = try? await generateCloudASRSourceSubtitle(
                videoFile: videoFile,
                languageCode: language.isEmpty ? "auto" : language,
                promptMetadata: Self.localASRPromptMetadata(info: info),
                control: control,
                asr: asr
            ) {
                finalSourceSRT = cloudSRT.url
                finalConfidence = nil
                usedCloudEscalation = true
                if !downloadFiles.contains(cloudSRT.url) { downloadFiles.append(cloudSRT.url) }
                update(id, generation: generation) {
                    if let local = asr.localModelLabel, let cloud = asr.cloudModelLabel {
                        $0.executedModels.transcription = "\(local) → \(cloud)"
                    } else {
                        $0.executedModels.transcription = asr.cloudModelLabel
                    }
                }
            }
        }
        // 云端识别可能耗时数秒；与本地路径(1636)一致,await 后重查 generation,避免取消后仍按陈旧结果继续。
        guard isRunActive(id: id, generation: generation, control: control) else {
            throw MoongateError.cancelled
        }

        let snapshot = downloadFiles
        update(id, generation: generation) {
            $0.resultFiles = snapshot
            $0.clearProgress()
            $0.isPostDownloadProcessing = false
            $0.postDownloadProcessingKind = nil
        }
        if usedCloudEscalation {
            // 云端救场成功：直接用云端源，附诚实来源说明。
            return SubtitleSourceResolution(
                selectedFile: finalSourceSRT,
                resolved: resolvedSource(
                    selectedFile: finalSourceSRT,
                    selectedKind: .cloudASR,
                    candidates: [candidate(kind: .cloudASR, fileURL: finalSourceSRT, provider: "OpenAI-compatible")],
                    fallbackReasons: platformAssessment.gateReasons),
                note: CoreL10n.text(
                    en: "Local recognition quality was low, so Moongate used cloud recognition you enabled.",
                    zhHans: "本地识别质量较低，已改用你启用的云端精准识别。",
                    zhHant: "本機識別品質較低，已改用你啟用的雲端精準識別。"))
        }
        let resolved = resolverResult(candidates: [
            platformCandidate,
            generatedLocalCandidate
        ])
        let selectedKind = resolved?.selectedKind ?? .localASR
        let selectedFile = selectedKind == .localASR ? finalSourceSRT : pickedSource
        return SubtitleSourceResolution(
            selectedFile: selectedFile,
            resolved: ResolvedSubtitleSource(
                languageCode: resolved?.languageCode ?? language,
                selectedFile: selectedFile,
                selectedKind: selectedKind,
                qualityVerdict: resolved?.qualityVerdict,
                sourceQualityVerdict: resolved?.sourceQualityVerdict,
                usedLocalASRFallback: selectedKind == .localASR,
                fallbackReasons: platformAssessment.gateReasons,
                candidateReports: resolved?.candidateReports ?? []),
            note: selectedKind == .localASR
                ? Self.localASRSourceNote(fallbackReasons: platformAssessment.gateReasons, confidence: finalConfidence)
                : nil)
    }

    /// Maps gate reasons to the user-facing fallback note.
    private static func fallbackNote(for reasons: [PlatformSubtitleQualityGate.Reason]) -> String {
        if reasons.contains(.languageMismatch) { return CoreL10n.t(L.Queue.subtitleSourceFallbackLanguageMismatch) }
        if reasons.contains(.garbledOrRepetitive) { return CoreL10n.t(L.Queue.subtitleSourceFallbackGarbled) }
        if reasons.contains(.lowCoverage) { return CoreL10n.t(L.Queue.subtitleSourceFallbackCoverage) }
        if reasons.contains(.tooFewCues) { return CoreL10n.t(L.Queue.subtitleSourceFallbackFewCues) }
        return CoreL10n.t(L.Queue.subtitleSourceFallbackGeneric)
    }

    /// Note for a freshly generated local-ASR source: the platform-fallback reason (if any) plus an
    /// honest "recognition quality is low" caveat when the transcript is pervasively low-confidence.
    private static func localASRSourceNote(
        fallbackReasons: [PlatformSubtitleQualityGate.Reason]?,
        confidence: LocalASRConfidenceSummary?
    ) -> String? {
        let fallback = fallbackReasons.map { fallbackNote(for: $0) }
        let qualityCaveat: String?
        if confidence?.hasSevereQualityBlocker == true {
            // 重复循环 / 语言误判：识别可能彻底不可靠（不再硬失败，诚实告警 + 让用户决定）。
            qualityCaveat = CoreL10n.text(
                en: "Local recognition may have looped or mis-detected the language, so these subtitles can be unreliable. Set the source language and retry, or use a platform subtitle if available.",
                zhHans: "本地识别可能发生重复循环或语言误判，这份字幕可能不可靠。可指定源语言后重试，或改用平台字幕。",
                zhHant: "本機識別可能發生重複循環或語言誤判，這份字幕可能不可靠。可指定來源語言後重試，或改用平台字幕。")
        } else if confidence?.isLowQuality == true {
            qualityCaveat = CoreL10n.t(L.Queue.subtitleSourceLowConfidenceLocalASR)
        } else {
            qualityCaveat = nil
        }
        switch (fallback, qualityCaveat) {
        case let (reason?, caveat?): return "\(reason) · \(caveat)"
        case let (reason?, nil): return reason
        case let (nil, caveat?): return caveat
        case (nil, nil): return nil
        }
    }

    private func appendImportedSubtitleFileIfNeeded(
        files: [URL],
        request: DownloadRequest
    ) throws -> [URL] {
        guard let sourceURL = request.importedSubtitleFileURL else { return files }
        let ext = sourceURL.pathExtension.lowercased()
        guard ["srt", "vtt"].contains(ext) else { return files }
        if files.contains(where: { $0.path == sourceURL.path }) { return files }

        let language = SubtitleLanguageChoice
            .normalizedLanguageCode(request.effectivePreferredLanguageCode ?? "auto")
        let destination = try importedSubtitleDestination(
            in: request.destinationDirectory,
            languageCode: language.isEmpty ? "auto" : language,
            pathExtension: ext
        )
        if sourceURL.standardizedFileURL.path == destination.standardizedFileURL.path {
            var nextFiles = files
            nextFiles.append(sourceURL)
            return nextFiles
        }
        try FileManager.default.createDirectory(
            at: request.destinationDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        var nextFiles = files
        nextFiles.append(destination)
        return nextFiles
    }

    private func importedSubtitleDestination(
        in directory: URL,
        languageCode: String,
        pathExtension ext: String
    ) throws -> URL {
        let safeLanguage = languageCode.map { character -> Character in
            character.isLetter || character.isNumber || character == "-" ? character : "-"
        }
        let stem = "imported-subtitle.\(String(safeLanguage))"
        return UniqueFilename.url(in: directory, stem: stem, ext: ext)
    }

    private func prepareLocalASRSourceSubtitleIfNeeded(
        files: [URL],
        request: DownloadRequest,
        id: UUID,
        generation: Int,
        control: TaskControlToken,
        asr: ASRRunResources
    ) async throws -> [URL] {
        guard isRunActive(id: id, generation: generation, control: control) else {
            throw MoongateError.cancelled
        }
        guard let languageCode = Self.localASRLanguageCode(in: request) else {
            return files
        }
        if let existing = Self.existingLocalASRSubtitle(in: files, languageCode: languageCode),
           Self.existingLocalASRSubtitleIsUsable(existing, languageCode: languageCode, request: request) {
            var nextFiles = files
            if !nextFiles.contains(existing) { nextFiles.append(existing) }
            return nextFiles
        }
        guard let localASRGenerator = asr.local,
              let videoFile = files.first(where: { Self.videoExtensions.contains($0.pathExtension.lowercased()) }) else {
            return files
        }
        let promptMetadata = item(id).map { Self.localASRPromptMetadata(info: $0.info) }
            ?? ASRPromptMetadata(title: request.preferredTitle)
        update(id, generation: generation) {
            $0.stage = .downloading
            $0.clearProgress()
            $0.statusText = nil
            $0.isPostDownloadProcessing = true
            $0.postDownloadProcessingKind = .generic
            self.applyProgress(&$0, id: id, generation: generation, phase: .audioExtract, phaseProgress: nil)
        }
        let generated = try await localASRGenerator.generateSourceSubtitle(
            videoFile: videoFile,
            languageCode: languageCode,
            promptMetadata: promptMetadata,
            control: control
        ) { [weak self] progress in
            Task { @MainActor in
                guard let self, self.item(id)?.generation == generation else { return }
                self.applyASRProgress(id: id, generation: generation, progress)
            }
        }
        let sourceSRT = generated.url
        if generated.confidence?.qualityIssues.contains("nearEmptyTranscript") == true {
            throw MoongateError.downloadFailed(CoreL10n.text(
                en: "Local recognition found almost no usable speech. Check the source language or model, then retry; use platform or cloud recognition if available.",
                zhHans: "本地识别几乎没有得到可用文字。请检查源语言或模型后重试；如果有平台字幕或云端识别，建议改用它们。",
                zhHant: "本機識別幾乎沒有得到可用文字。請檢查來源語言或模型後重試；如果有平台字幕或雲端識別，建議改用它們。"))
        }
        // 严重质量问题(重复循环/语言误判)**不再让整个任务失败**——whisper 是用户显式选择的源,没有更好的可换,
        // 硬失败只会让用户一无所得。与 autoBest 路径一致:照常产出字幕,由下方 localASRSourceNote 附诚实告警。
        guard isRunActive(id: id, generation: generation, control: control) else {
            throw MoongateError.cancelled
        }
        completeProgressPhase(id, generation: generation, phase: .audioExtract)
        completeProgressPhase(id, generation: generation, phase: .speechRecognition)
        completeProgressPhase(id, generation: generation, phase: .subtitleSegment)
        var nextFiles = files
        if !nextFiles.contains(sourceSRT) { nextFiles.append(sourceSRT) }
        let lowConfidenceNote = Self.localASRSourceNote(fallbackReasons: nil, confidence: generated.confidence)
        update(id, generation: generation) {
            $0.resultFiles = nextFiles
            $0.executedModels.transcription = asr.localModelLabel
            $0.clearProgress()
            $0.statusText = CoreL10n.t(L.Queue.localASRGeneratedSubtitleReady)
            $0.isPostDownloadProcessing = false
            $0.postDownloadProcessingKind = nil
            if let lowConfidenceNote { $0.subtitleSourceNote = lowConfidenceNote }
        }
        return nextFiles
    }

    private func prepareCloudASRSourceSubtitleIfNeeded(
        files: [URL],
        request: DownloadRequest,
        id: UUID,
        generation: Int,
        control: TaskControlToken,
        asr: ASRRunResources
    ) async throws -> [URL] {
        guard isRunActive(id: id, generation: generation, control: control) else {
            throw MoongateError.cancelled
        }
        guard request.subtitleSourcePolicy == .cloudASR else { return files }
        guard let videoFile = files.first(where: { Self.videoExtensions.contains($0.pathExtension.lowercased()) }) else {
            return files
        }
        guard asr.cloud != nil else {
            throw MoongateError.downloadFailed(CoreL10n.t(L.Ready.cloudASRSetupRequired))
        }
        let languageCode = request.effectivePreferredLanguageCode
            ?? request.primarySubtitleTrack?.languageCode
            ?? "auto"
        update(id, generation: generation) {
            $0.stage = .downloading
            $0.clearProgress()
            $0.statusText = nil
            $0.isPostDownloadProcessing = true
            $0.postDownloadProcessingKind = .generic
            self.applyProgress(&$0, id: id, generation: generation, phase: .speechRecognition, phaseProgress: nil)
        }
        let promptMetadata = item(id).map { Self.localASRPromptMetadata(info: $0.info) }
            ?? ASRPromptMetadata(title: request.preferredTitle)
        let generated = try await generateCloudASRSourceSubtitle(
            videoFile: videoFile,
            languageCode: languageCode,
            promptMetadata: promptMetadata,
            control: control,
            asr: asr
        )
        guard isRunActive(id: id, generation: generation, control: control) else {
            throw MoongateError.cancelled
        }
        completeProgressPhase(id, generation: generation, phase: .speechRecognition)
        completeProgressPhase(id, generation: generation, phase: .subtitleSegment)
        var nextFiles = files
        if !nextFiles.contains(generated.url) { nextFiles.append(generated.url) }
        update(id, generation: generation) {
            $0.resultFiles = nextFiles
            $0.executedModels.transcription = asr.cloudModelLabel
            $0.clearProgress()
            $0.isPostDownloadProcessing = false
            $0.postDownloadProcessingKind = nil
        }
        return nextFiles
    }

    private func generateCloudASRSourceSubtitle(
        videoFile: URL,
        languageCode: String,
        promptMetadata: ASRPromptMetadata?,
        control: TaskControlToken,
        asr: ASRRunResources
    ) async throws -> GeneratedCloudASRSource {
        guard let cloudASRGenerator = asr.cloud else {
            throw MoongateError.downloadFailed(CoreL10n.t(L.Ready.cloudASRSetupRequired))
        }
        return try await cloudASRGenerator.generateSourceSubtitle(
            videoFile: videoFile,
            languageCode: languageCode,
            promptMetadata: promptMetadata,
            control: control
        )
    }

    private static func existingLocalASRSubtitleIsUsable(
        _ subtitle: URL,
        languageCode: String,
        request: DownloadRequest
    ) -> Bool {
        guard let raw = try? String(contentsOf: subtitle, encoding: .utf8) else { return false }
        let detectedLanguageCode = langCode(ofSubtitle: subtitle) ?? languageCode
        let languageHintCode = request.preferredTitle
            .flatMap { SubtitleLanguageRecommender.inferredLocalASRLanguageCode(title: $0) }
        let summary = LocalASRConfidence.assessSubtitle(
            raw: raw,
            fileName: subtitle.lastPathComponent,
            languageCode: detectedLanguageCode,
            requestedLanguageCode: languageCode,
            languageHintCode: languageHintCode
        )
        return !summary.hasSevereQualityBlocker
    }

    private func applyASRProgress(id: UUID, generation: Int, _ progress: ASRProgress) {
        update(id, generation: generation) {
            guard $0.stage == .downloading else { return }
            self.applyProgress(
                &$0,
                id: id,
                generation: generation,
                phase: Self.queuePhase(for: progress.phase),
                phaseProgress: progress.fraction
            )
        }
    }

    private static func queuePhase(for phase: ASRProgress.Phase) -> QueueProgressPhase {
        switch phase {
        case .modelDownload: return .modelDownload
        case .audioExtract: return .audioExtract
        case .speechRecognition: return .speechRecognition
        case .subtitleSegment: return .subtitleSegment
        }
    }

    private static func localASRLanguageCode(in request: DownloadRequest) -> String? {
        if let primarySubtitleTrack = request.primarySubtitleTrack {
            return primarySubtitleTrack.sourceKind == .localASR ? primarySubtitleTrack.languageCode : nil
        }
        guard shouldPrepareLocalASRSource(for: request) else { return nil }
        return request.requestedSubtitleTracks
            .first(where: { $0.sourceKind == .localASR })?
            .languageCode
    }

    /// A reused local-ASR subtitle is a valid source for a reprocess task and
    /// must not be blocked just because the local generator is no longer
    /// installed. Only require the generator when a fresh source is needed.
    private static func needsFreshLocalASRSource(
        for request: DownloadRequest,
        initialFiles: [URL]
    ) -> Bool {
        guard let languageCode = localASRLanguageCode(in: request) else { return false }
        guard let existing = existingLocalASRSubtitle(in: initialFiles, languageCode: languageCode) else {
            return true
        }
        return !existingLocalASRSubtitleIsUsable(
            existing,
            languageCode: languageCode,
            request: request
        )
    }

    private static func existingLocalASRSubtitle(in files: [URL], languageCode: String) -> URL? {
        let normalized = languageCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // auto / 空：whisper 产物名用的是“检测到的语言”（如 .local-asr.ja.srt），不会是 .local-asr.auto.srt。
        // 所以 auto/空 要通配命中任意已存在的 local-ASR 字幕，与 transcript cache 的 auto-wildcard 语义一致；
        // 否则完成项以 auto 重跑会因后缀不匹配而重复抽音频 / 重跑 whisper（BUG-C）。
        let wildcard = normalized.isEmpty || normalized == "auto"
        return files.first { file in
            guard isLocalASRSubtitle(file.lastPathComponent) else { return false }
            return wildcard || langCode(ofSubtitle: file) == normalized
        }
    }

    private static func shortReason(of error: Error) -> String {
        switch error {
        case MoongateError.translateFailed(let r), MoongateError.burnFailed(let r), MoongateError.downloadFailed(let r):
            return r
        default:
            return error.localizedDescription
        }
    }

    /// 从字幕文件名 "<名>.<lang>.srt/.vtt" 解析出 lang code（无法解析返回 nil）。
    private static func langCode(of file: URL) -> String? {
        let stem = file.deletingPathExtension().lastPathComponent
        guard let dotIndex = stem.lastIndex(of: ".") else { return nil }
        return String(stem[stem.index(after: dotIndex)...]).lowercased()
    }

    private static func langCode(ofSubtitle file: URL) -> String? {
        langCode(of: file)
    }

    /// 按主字幕来源挑翻译源字幕：大小写不敏感、允许前缀匹配。
    /// preferredTrack 命中时先按来源类型筛选，同语言 local ASR 和平台字幕不再互相抢源；
    /// 没有主来源时回退第一个非译文字幕，避免把上次译文当源二次翻译。
    private static func pickSourceSubtitle(
        from files: [URL],
        preferredLang: String?,
        preferredTrack: SubtitleChoice? = nil
    ) -> URL? {
        let subtitleFiles = files
            .filter { ["srt", "vtt"].contains($0.pathExtension.lowercased()) }
            .sorted { subtitleSourceRank($0) < subtitleSourceRank($1) }
        if let preferredTrack, preferredTrack.sourceKind == .importedFile {
            if let importedPath = preferredTrack.metadata["path"],
               let exact = subtitleFiles.first(where: {
                   $0.path == importedPath
                       || $0.resolvingSymlinksInPath().path == URL(fileURLWithPath: importedPath).resolvingSymlinksInPath().path
                       || $0.lastPathComponent == URL(fileURLWithPath: importedPath).lastPathComponent
               }) {
                return exact
            }
            if let imported = subtitleFiles.first(where: { isImportedSubtitle($0.lastPathComponent) }) {
                return imported
            }
        }
        if let lang = preferredLang?.lowercased(), !lang.isEmpty {
            let matches = subtitleFiles.filter { file in
                guard let code = langCode(of: file) else { return false }
                return code == lang || code.hasPrefix(lang + "-") || lang.hasPrefix(code + "-")
            }
            if preferredTrack?.sourceKind == .localASR,
               let matched = matches.first(where: { isLocalASRSubtitle($0.lastPathComponent) }) {
                return matched
            }
            if let preferredTrack, preferredTrack.sourceKind != .localASR,
               let matched = matches.first(where: { !isLocalASRSubtitle($0.lastPathComponent) }) {
                return matched
            }
            if let matched = matches.first {
                return matched
            }
        }
        let nonTranslated = subtitleFiles.filter { file in
            !TranslationLanguage.isTranslatedSubtitleFileName(file.lastPathComponent)
        }
        return nonTranslated.first ?? subtitleFiles.first
    }

    private static func subtitleSourceRank(_ file: URL) -> Int {
        if isCloudASRSubtitle(file.lastPathComponent) { return -3 }
        if isImportedSubtitle(file.lastPathComponent) { return -2 }
        if isLocalASRSubtitle(file.lastPathComponent) { return -1 }
        switch file.pathExtension.lowercased() {
        case "vtt": return 0
        case "srt": return 1
        default: return 2
        }
    }

    private static func isLocalASRSubtitle(_ fileName: String) -> Bool {
        fileName.lowercased().contains(".local-asr.")
    }

    private static func isCloudASRSubtitle(_ fileName: String) -> Bool {
        fileName.lowercased().contains(".cloud-asr.")
    }

    private static func isImportedSubtitle(_ fileName: String) -> Bool {
        fileName.lowercased().hasPrefix("imported-subtitle.")
    }

    private static func ensureSRTSubtitle(_ file: URL) throws -> URL {
        if file.pathExtension.lowercased() == "srt" { return file }
        return try cleanSRTFile(at: file).output
    }
}
