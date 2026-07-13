import AppKit
import Combine
import Foundation
#if canImport(MoongateCore)
import MoongateCore
#endif

/// 字幕处理方式（ready 页「字幕处理」分组的选项）
enum ChineseSubtitleMode: String, CaseIterable, Codable, Sendable {
    case off
    case srtOnly
    case burnIn
    case burnOriginal

    var localizationKey: String {
        switch self {
        case .off: return L.Ready.subtitleModeOff
        case .srtOnly: return L.Ready.subtitleModeSrtOnly
        case .burnIn: return L.Ready.subtitleModeBurnIn
        case .burnOriginal: return L.Ready.subtitleModeBurnOriginal
        }
    }

    var requiresTranslation: Bool {
        self == .srtOnly || self == .burnIn
    }

    var requiresBurner: Bool {
        self == .burnIn || self == .burnOriginal
    }
}

struct ReadySubtitleState {
    let intent: SubtitleIntent
    let sourcePolicy: SubtitleSourcePolicy
    let selectedTrack: SubtitleChoice?
    let sourceDecision: SubtitleSourceDecisionReport?
    let translationRequired: Bool
    let translationReady: Bool
    let localASRRequiredButUnavailable: Bool
    let cloudASRRequiredButUnavailable: Bool

    var needsSubtitleSource: Bool { intent.needsSubtitleSource }
}

struct SourceLanguagePreferenceOption: Identifiable, Hashable {
    let code: String
    var id: String { code }
}

/// The user-facing source of a local subtitle capability request. Keeping a
/// queued task id here lets the Settings-hosted sheet resolve that one task
/// instead of silently changing only future-download defaults.
enum LocalRecognitionCapabilitySetupRequest: Equatable {
    case defaults
    case queuedTask(UUID)

    var queuedTaskID: UUID? {
        guard case .queuedTask(let id) = self else { return nil }
        return id
    }
}

/// A recovery choice made from the local-recognition capability sheet for a
/// deferred task. These are outcomes a person can understand; model/runtime
/// details remain in the capability implementation.
enum QueuedRecognitionFallback: Equatable {
    case platformSubtitles
    case cloudRecognition
    case videoOnly
}

@MainActor
final class ViewModel: ObservableObject {

    /// 解析与选档的前半段；下载之后的流水线全部交给 QueueManager。
    enum Stage {
        case idle
        case resolving
        case choosing([VideoCandidate])
        case analyzing
        case ready(VideoInfo)
        case failed(String)
    }

    @Published var urlText: String = ""
    @Published var stage: Stage = .idle
    @Published var selectedFormatID: String?
    /// 用户是否选择下载 HDR（仅当所选档有 HDR 源时生效）。
    @Published var preferHDR: Bool = false {
        didSet { persistCurrentDownloadOptions() }
    }
    /// 下载后输出格式（转码/remux）；.original 不转码。
    @Published var selectedOutputFormat: OutputFormat = .original {
        didSet { persistCurrentDownloadOptions() }
    }
    @Published var primarySubtitleTrackID: String? {
        didSet {
            selectedSubtitleIDs = primarySubtitleTrackID.map { [$0] } ?? []
            if primarySubtitleTrackID == nil, chineseMode != .off {
                chineseMode = .off
            }
            refreshTranslationRuntimeReadiness()
            persistCurrentDownloadOptions()
        }
    }
    @Published var selectedSubtitleIDs: Set<String> = [] {
        didSet {
            // 字幕处理依赖至少勾选一条字幕；全部取消勾选时强制回「不需要」
            if selectedSubtitleIDs.isEmpty, chineseMode != .off {
                chineseMode = .off
            }
            refreshTranslationRuntimeReadiness()
            persistCurrentDownloadOptions()
        }
    }
    @Published var chineseMode: ChineseSubtitleMode = .off {
        didSet { persistCurrentDownloadOptions() }
    }
    /// Ready 页默认只让用户选字幕结果；来源策略保留为高级控制，当前作为旧字段的兼容层。
    @Published var subtitleSourcePolicy: SubtitleSourcePolicy = .autoBest
    @Published var importedSubtitleFileURL: URL?
    /// Ready 页语言区是否展开（默认折叠：只显示推荐语言，展开后才显示其他语言与来源细节）。
    @Published var languageSectionExpanded: Bool = false
    @Published var showSourceLanguagePicker: Bool = false
    /// Ready 页单视频原声语言偏好。默认跟随全局设置；只影响当前选档页。
    @Published var readySourceLanguagePreference: String = "auto"
    var readySourceLanguageIntent: SourceLanguageIntent {
        get { Self.sourceLanguageIntent(from: readySourceLanguagePreference) }
        set { readySourceLanguagePreference = Self.sourceLanguagePreference(from: newValue) }
    }
    /// 启动时（ViewModel 实例化前）读取持久化的界面语言，供 App 在 init 注入 Localizer。
    /// 仅一次性磁盘读取（非子进程），可安全用于 @StateObject 初始化。
    static var persistedAppLanguage: String { AppSettings.load(readCredentials: false).appLanguage }

    private static func localASRGeneratorSettingsChanged(_ old: AppSettings, _ new: AppSettings) -> Bool {
        old.localASREnabled != new.localASREnabled
            || old.localASRRuntimePath != new.localASRRuntimePath
            || old.localASRModelPath != new.localASRModelPath
            || old.localASRModelID != new.localASRModelID
            || old.localASRPreciseModeEnabled != new.localASRPreciseModeEnabled
            || old.localASRSidecarRuntimePath != new.localASRSidecarRuntimePath
            || old.localASRSidecarModelPath != new.localASRSidecarModelPath
            || old.localASRVADModelPath != new.localASRVADModelPath
    }

    private static func cloudASRGeneratorSettingsChanged(_ old: AppSettings, _ new: AppSettings) -> Bool {
        old.cloudASREnabled != new.cloudASREnabled
            || old.cloudASRConsentAccepted != new.cloudASRConsentAccepted
            || old.cloudASRBaseURL != new.cloudASRBaseURL
            || old.cloudASRModel != new.cloudASRModel
            || old.cloudASRAuthToken != new.cloudASRAuthToken
    }

    /// 启动时不读 Keychain 凭证（避免首次启动弹授权）；首次真正需要凭证时由 hydrateCredentials() 补齐。
    /// 默认空设置仅作占位，init 会立刻用 load(readCredentials: false) 覆盖。
    @Published var settings = AppSettings() {
        didSet {
            CoreL10n.sync(from: settings)
            queue.syncConcurrency(from: settings)
            if oldValue.subtitleRecognitionMode != settings.subtitleRecognitionMode {
                applySubtitleRecognitionMode(settings.subtitleRecognitionMode)
            }
            if Self.localASRGeneratorSettingsChanged(oldValue, settings) {
                queue.syncLocalASRGenerator(from: settings)
                queue.syncCloudASRGenerator(from: settings)
            }
            if Self.cloudASRGeneratorSettingsChanged(oldValue, settings) {
                queue.syncCloudASRGenerator(from: settings)
            }
            refreshTranslationRuntimeReadiness()
            refreshSummaryRuntimeReadiness()
        }
    }
    @Published var showSettings = false
    @Published var pendingSettingsPaneID: String?
    /// A transient request from a queue/library recovery action. The Settings
    /// view consumes it once and presents the user-facing capability sheet.
    @Published var localRecognitionCapabilitySetupRequest: LocalRecognitionCapabilitySetupRequest?
    /// A queued cloud-recognition recovery needs the service editor, not the
    /// local capability sheet. Preserve the originating task until Settings
    /// saves the service snapshot back into that queued configuration.
    @Published var cloudRecognitionConfigurationRequestQueueID: UUID?
    @Published var cloudRecognitionConfigurationRequested = false
    /// 首启引导：选择 App 语言与默认译文目标；不强制配置 API。
    @Published var showOnboarding = false
    /// 非 nil 时弹出站点 Cookie 捕获窗（值为站点 host，如 "youtube.com"）
    @Published var loginSite: String?
    /// Cookie 捕获窗的起始 URL；nil 时使用该站点默认入口。
    @Published var loginStartURL: URL?
    /// 失败原因是需要登录/验证时记录站点，failed 页据此把主按钮换成站点验证入口。
    @Published var failedNeedsLogin: String?
    /// 失败页触发 Cookie 捕获时优先打开的原始失败 URL。
    @Published var failedLoginURL: URL?
    /// 失败原因是缺依赖（yt-dlp/ffmpeg 找不到）时，failed 页给「一键安装依赖」入口
    @Published var failedNeedsDependency = false
    /// 一键安装依赖的弹层
    @Published var showDependencySetup = false
    /// 设置窗里的提示（保存失败 / 请先配置翻译服务）
    @Published var settingsNotice: String?
    /// 入队成功后的一行轻提示（如「已加入队列」）
    @Published var enqueueNotice: String?
    /// 批量粘贴多链接时的进度文案（解析中显示，如「批量解析中（2/5）」）
    @Published var batchStatusText: String?
    /// 仅供“新建下载”Sheet 决定成功后是否可以自动收起。它不持久化，
    /// 也不把“已排入待开始”伪装成已经下载完成。
    @Published private(set) var deferredBatchAddedCount: Int?
    /// 触发器：自增时 ContentView 重新聚焦链接输入框（入队后方便继续粘贴）。
    @Published var requestUrlFocus = 0
    /// 队列浮层形态：true=铺满内容区，false=缩成底部小把手。
    /// 开始解析新链接时自动收起（让位给下载设置），入队完成/回到空闲时自动铺满。
    @Published var queueExpanded = false
    @Published private(set) var runtimeTranslationReadiness: TranslationReadiness?
    private var runtimeTranslationReadinessContext: TranslationContext?
    @Published private(set) var runtimeSummaryReadiness: TranslationReadiness?
    private var runtimeSummaryReadinessContext: TranslationContext?

    /// AI 内容总结状态。按需触发；切换/重置视频时回到 idle。
    enum SummaryState: Equatable {
        case idle
        case running
        case done(String)
        case failed(String)
    }
    @Published private(set) var summaryState: SummaryState = .idle
    private var summaryTask: Task<Void, Never>?

    /// 并发下载队列，贯穿整个 App 生命周期。
    let queue: QueueManager
    /// 远程更新器贯穿主界面与设置页；发现新版后用于设置按钮红点提示。
    let updater: UpdateService
    private let engine: any DownloadEngine
    private let runtimeReadinessEvaluator: any TranslationRuntimeReadinessEvaluating
    private var runtimeReadinessTask: Task<Void, Never>?
    private var summaryReadinessTask: Task<Void, Never>?
    private var parseTask: Task<Void, Never>?
    private var candidates: [VideoCandidate] = []
    private var chosenCandidate: VideoCandidate?
    private var retryAction: (@MainActor () -> Void)?
    /// 设置窗里点了「登录 ××」：先收起设置 sheet，再由其 onDismiss 弹出登录窗
    private var pendingLoginSite: String?
    /// 队列中登录类失败项触发的登录：登录成功后据此重试该站点全部失败项。nil 表示非队列触发。
    private var pendingQueueLoginSite: String?
    /// Ready 页字幕提示触发的登录：登录成功后据此清缓存并重新解析该 URL，以拿到平台字幕。
    private var pendingReadyReanalyzeURL: String?
    /// 设置窗里点了「配置依赖」：先收起设置 sheet，再由其 onDismiss 弹出依赖配置窗
    private var pendingDependencySetup = false
    /// 代际令牌：reset / 取消后，旧解析任务的回调全部作废
    private var session = 0

    /// 凭证是否已从安全存储补齐（见 hydrateCredentials）。启动时为 false，首次需要时置 true。
    private var credentialsHydrated = false

    init(
        engine: any DownloadEngine = makeDefaultEngine(),
        queue: QueueManager? = nil,
        updater: UpdateService? = nil,
        runtimeReadinessEvaluator: any TranslationRuntimeReadinessEvaluating = AppleRuntimeReadinessEvaluator()
    ) {
        let initialSettings = AppSettings.load(readCredentials: false)
        self.settings = initialSettings
        self.primarySubtitleTrackID = nil
        self.readySourceLanguagePreference = initialSettings.preferredSourceLanguage
        self.engine = engine
        let initialLocalASRGenerator = LocalASRGeneratorFactory.make(settings: initialSettings)
        self.queue = queue ?? QueueManager(
            engine: engine,
            localASRGenerator: initialLocalASRGenerator,
            cloudASRGenerator: CloudASRGeneratorFactory.make(
                settings: initialSettings,
                localASRGenerator: initialLocalASRGenerator
            ),
            localASRRunProvider: { settings in
                LocalASRGeneratorFactory.make(settings: settings)
            },
            cloudASRRunProvider: { settings, localASRGenerator in
                CloudASRGeneratorFactory.make(
                    settings: settings,
                    localASRGenerator: localASRGenerator
                )
            },
            completionNotifier: SystemQueueCompletionNotifier(settingsProvider: { AppSettings.load(readCredentials: false) })
        )
        self.updater = updater ?? UpdateService()
        self.runtimeReadinessEvaluator = runtimeReadinessEvaluator
        self.updater.prepareForUpdateUI = { [weak self] in
            self?.dismissSheetsForUpdateUI()
        }
        CoreL10n.sync(from: settings)
    }

    /// 首次真正需要 API 凭证（打开设置 / 开始下载翻译 / 总结）时，从 Keychain 补齐 Token。
    /// 启动时刻意不读，避免首次启动还没用到 API 就弹 Keychain 授权；幂等，仅读一次。
    /// 注意：必须在任何会写回设置（保存）之前调用，否则会把空 Token 写盖掉安全存储里的值。
    func hydrateCredentials() {
        guard !credentialsHydrated else { return }
        credentialsHydrated = true
        settings = AppSettings.load(readCredentials: true)
    }

    // MARK: - 派生状态

    var isParsing: Bool {
        switch stage {
        case .resolving, .analyzing: return true
        default: return false
        }
    }

    var canReturnToList: Bool { candidates.count > 1 }

    // MARK: - 行为

    func onAppear() {
        prefillFromClipboardIfAppropriate()
        showOnboardingIfNeeded()
        checkForUpdatesIfNeeded()
        refreshTranslationRuntimeReadiness()
        refreshSummaryRuntimeReadiness()
    }

    func checkForUpdatesIfNeeded() {
        // 后台更新检查由 Sparkle 的自动调度驱动（Info.plist 的 SUEnableAutomaticChecks +
        // SUScheduledCheckInterval=86400）。之前这里调用的 updater.check(silent:true) 实为 no-op，
        // 既不真正检查、注释又声称会检查，已删除——显式检查仍由更新区的「检查更新」按钮触发。
    }

    func dismissSheetsForUpdateUI() {
        showSettings = false
    }

    /// 视图出现或 App 激活时：处于可输入阶段且输入框为空，用剪贴板里的链接预填（不自动解析）。
    func prefillFromClipboardIfAppropriate() {
        switch stage {
        case .idle, .ready:
            break
        default:
            return
        }
        guard urlText.isEmpty else { return }
        guard let clip = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            clip.lowercased().hasPrefix("http") else { return }
        urlText = clip
    }

    /// 「一键粘贴」：直接读剪贴板（绕过输入框对多行粘贴的处理差异），填入后立即解析。
    func pasteAndParse() {
        guard !isParsing else { return }
        guard let clip = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !clip.isEmpty else {
            enqueueNotice = CoreL10n.t(L.Main.clipboardEmpty)
            return
        }
        urlText = clip
        parse()
    }

    func parse() {
        let input = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, !isParsing else { return }
        // 用户开始处理任务即补齐凭证：ready 页的「翻译/总结是否已配置」判断需要 Token，
        // 且此时弹一次 Keychain 授权（仅当有旧凭证项）比首次启动就弹更合理。
        hydrateCredentials()

        // 一次粘贴多条链接：逐个解析并按默认选项（最高画质）自动加入队列
        let urls = Self.extractURLs(from: input)
        if urls.count > 1 {
            processBatch(urls)
            return
        }

        // 单链接也用提取结果（容忍尾随标点/前后杂字），提不出再退回原始输入
        let target = urls.first ?? input
        guard let url = URL(string: target),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            session += 1
            retryAction = nil
            failedNeedsLogin = nil
            failedNeedsDependency = false
            queueExpanded = false
            stage = .failed(CoreL10n.t(L.Main.invalidURL))
            return
        }
        session += 1
        let token = session
        retryAction = nil
        failedNeedsLogin = nil
        failedNeedsDependency = false
        enqueueNotice = nil
        queueExpanded = false
        stage = .resolving
        chosenCandidate = nil
        parseTask?.cancel()
        parseTask = Task {
            do {
                let found = try await self.engine.resolveCandidates(for: target)
                guard token == self.session else { return }
                guard !found.isEmpty else { throw MoongateError.sniffFailed("") }
                self.candidates = found
                if found.count == 1 {
                    self.choose(found[0])
                } else {
                    self.stage = .choosing(found)
                }
            } catch {
                guard token == self.session else { return }
                self.fail(error) { [weak self] in self?.parse() }
            }
        }
    }

    /// App 管理的下载根目录。设置页的存储清理只允许操作这个目录，不能扫描整个 Downloads。
    static var appDownloadsDirectory: URL {
        // 极少数沙箱/无 Downloads 目录的环境下 urls(for:) 可能为空，回退到家目录下 Downloads，避免越界崩溃。
        let base = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        return base.appendingPathComponent("Moongate", isDirectory: true)
    }

    /// 下载目的地：所有 v0.8 产物都放在 Downloads/Moongate 下；多文件任务再按视频标题建子文件夹。
    static func destinationDirectory(forTitle title: String, multiFile: Bool) -> URL {
        let downloads = appDownloadsDirectory
        guard multiFile else { return downloads }
        return downloads.appendingPathComponent(sanitizedFolderName(title), isDirectory: true)
    }

    /// 标题转安全文件夹名：去路径分隔/控制字符、截长、去结尾点号（兼容 Windows）。
    static func sanitizedFolderName(_ title: String) -> String {
        var name = title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:\0").union(.newlines))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if name.count > 80 {
            name = String(name.prefix(80)).trimmingCharacters(in: .whitespaces)
        }
        while name.hasSuffix(".") { name.removeLast() }
        return name.isEmpty ? CoreL10n.t(L.Main.defaultVideoFolderName) : name
    }

    /// 从粘贴文本里提取全部 http(s) 链接，保序去重。
    /// 按 `http(s)://` 锚点切分而非只按空白：单行输入框粘贴多行时换行可能被吞掉、
    /// 多条链接首尾相接，按空白分隔会整段当成一条导致「只解析出一个地址」。
    static func extractURLs(from input: String) -> [String] {
        var seen = Set<String>()
        var urls: [String] = []
        guard let regex = urlExtractionRegex else { return [] }
        let ns = input as NSString
        for match in regex.matches(in: input, range: NSRange(location: 0, length: ns.length)) {
            let raw = ns.substring(with: match.range)
            let token = raw.trimmingCharacters(in: CharacterSet(charactersIn: ",;，；、。.)）]》〉>」』\"'"))
            guard let url = URL(string: token),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  url.host != nil,
                  seen.insert(token).inserted else { continue }
            urls.append(token)
        }
        return urls
    }

    /// 三栏原型「添加任务」入口：从一段文本提取一或多个链接，按默认设置（最高画质、
    /// 当前字幕模式）自动入队，不经 ready 配置页。复用批量自动入队引擎；对单个链接也走
    /// 同一路径（直接入队，不进入单流程的 choosing/ready 阶段）。空输入或无有效链接时
    /// 设 enqueueNotice 提示并返回。
    func addTasks(from text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isParsing else { return }
        hydrateCredentials()
        let urls = Self.extractURLs(from: trimmed)
        guard !urls.isEmpty else {
            enqueueNotice = CoreL10n.t(L.Main.invalidURL)
            return
        }
        processBatch(urls)
    }

    /// Resolves links into stable library records without starting their
    /// processing pipelines. The per-task configuration stays editable until
    /// the user explicitly starts this item or the queued batch.
    @discardableResult
    func enqueueDeferredDrafts(from text: String, configuration: QueuedProcessingConfiguration) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isParsing else { return false }
        let urls = Self.extractURLs(from: trimmed)
        guard !urls.isEmpty else {
            enqueueNotice = CoreL10n.t(L.Main.invalidURL)
            return false
        }
        deferredBatchAddedCount = nil
        processBatch(urls, queuedConfiguration: configuration, startImmediately: false)
        return true
    }

    /// Restarts an interrupted library version as a fresh pipeline run. This
    /// deliberately uses the same durable item/version identity, but does not
    /// claim to resume an in-memory process from a previous app launch.
    func restartInterruptedLibraryItem(_ item: MoongateCore.LibraryItem) {
        guard let version = item.latestVersion,
              version.processing.state == .interrupted else {
            return
        }
        guard let source = item.source, source.supportsRestart else {
            enqueueNotice = "此记录未保存可安全重新开始的来源标识。请使用原链接新建下载。"
            return
        }
        let sourceURL = source.urlString
        guard !sourceURL.isEmpty else {
            enqueueNotice = "此记录没有可重新开始的来源链接。"
            return
        }

        hydrateCredentials()
        let persisted = version.processing.configuration
        var configuration = QueuedProcessingConfiguration.defaults(from: settings)
        if let quality = persisted.quality, !quality.isEmpty {
            configuration.quality = quality
        }
        if let outputFormat = persisted.outputFormat.flatMap(OutputFormat.init(rawValue:)) {
            configuration.outputFormat = outputFormat
        }
        if let subtitleMode = persisted.subtitleMode.flatMap(ChineseSubtitleMode.init(rawValue:)) {
            configuration.subtitleMode = subtitleMode
        }
        configuration.subtitleSourcePolicy = queuedSubtitlePolicy(
            from: persisted.subtitleSource,
            fallback: configuration.subtitleSourcePolicy
        )
        if let targetLanguage = persisted.targetLanguage, !targetLanguage.isEmpty {
            configuration.targetLanguage = targetLanguage
        }
        if let transcriptionModel = persisted.transcriptionModel, !transcriptionModel.isEmpty {
            configuration.transcriptionModel = transcriptionModel
        }
        if let translationModel = persisted.translationModel, !translationModel.isEmpty {
            configuration.translationModel = translationModel
        }
        if let subtitleStyle = persisted.subtitleStyle.flatMap(SubtitleStyle.init(rawValue:)) {
            configuration.subtitleStyle = subtitleStyle
        }

        processBatch(
            [sourceURL],
            queuedConfiguration: configuration,
            libraryItemID: item.id,
            libraryVersionID: version.id,
            startImmediately: true
        )
    }

    @discardableResult
    func startQueuedTask(id: UUID) -> Bool {
        hydrateCredentials()
        guard let item = queue.items.first(where: { $0.id == id }),
              item.stage == .queued else {
            return false
        }
        let settingsWithCredentials = applyingCurrentCredentials(to: item.settings)
        guard queue.updateQueuedConfiguration(
            id: id,
            request: item.request,
            mode: item.chineseMode,
            settings: settingsWithCredentials
        ) else {
            return false
        }
        return queue.start(id: id)
    }

    @discardableResult
    func startAllQueuedTasks() -> Int {
        let queuedIDs = queue.items.filter { $0.stage == .queued }.map(\.id)
        return queuedIDs.reduce(into: 0) { count, id in
            if startQueuedTask(id: id) { count += 1 }
        }
    }

    @discardableResult
    func updateQueuedTaskConfiguration(
        id: UUID,
        configuration: LibraryProcessingConfiguration
    ) -> Bool {
        guard let item = queue.items.first(where: { $0.id == id }),
              item.stage == .queued else {
            return false
        }
        let sourcePolicy = queuedSubtitlePolicy(
            from: configuration.subtitleSource,
            fallback: item.request.subtitleSourcePolicy
        )
        let queuedConfiguration = QueuedProcessingConfiguration(
            quality: configuration.quality ?? item.request.formatID,
            outputFormat: OutputFormat(rawValue: configuration.outputFormat ?? "") ?? item.request.outputFormat,
            subtitleMode: ChineseSubtitleMode(rawValue: configuration.subtitleMode ?? "") ?? item.chineseMode,
            subtitleSourcePolicy: sourcePolicy,
            targetLanguage: configuration.targetLanguage ?? item.settings.translationTargetLanguage,
            transcriptionModel: configuration.transcriptionModel ?? item.settings.localASRModelID,
            translationModel: configuration.translationModel
                ?? (item.settings.translationFollowsDefault ? item.settings.aiModel : item.settings.translationModel),
            subtitleStyle: SubtitleStyle(rawValue: configuration.subtitleStyle ?? "") ?? item.settings.subtitleStyle
        )
        return updateQueuedTaskConfiguration(id: id, configuration: queuedConfiguration)
    }

    @discardableResult
    private func updateQueuedTaskConfiguration(
        id: UUID,
        configuration: QueuedProcessingConfiguration
    ) -> Bool {
        guard let item = queue.items.first(where: { $0.id == id }),
              item.stage == .queued else {
            return false
        }
        let subtitleTrack = queuedSubtitleTrack(for: configuration, from: item.request)
        let subtitleTracks = configuration.subtitleMode == .off
            ? [] : subtitleTrack.map { [$0] } ?? []
        let subtitleLangs = subtitleTrack?.sourceKind == .manual ? [subtitleTrack!.languageCode] : []
        let autoSubtitleLangs = subtitleTrack?.sourceKind == .platformAuto ? [subtitleTrack!.languageCode] : []
        let request = DownloadRequest(
            url: item.request.url,
            videoID: item.request.videoID,
            formatID: configuration.quality == "best" ? item.request.formatID : configuration.quality,
            subtitleLangs: subtitleLangs,
            autoSubtitleLangs: autoSubtitleLangs,
            subtitleTracks: subtitleTracks,
            primarySubtitleTrackID: subtitleTrack?.id,
            preferredSubtitleLanguageCode: subtitleTrack?.languageCode,
            sourceLanguageIntent: item.request.sourceLanguageIntent,
            subtitleSourcePolicy: configuration.subtitleSourcePolicy,
            importedSubtitleFileURL: item.request.importedSubtitleFileURL,
            destinationDirectory: item.request.destinationDirectory,
            preferredTitle: item.request.preferredTitle,
            preferHDR: item.request.preferHDR,
            outputFormat: configuration.outputFormat
        )
        return queue.updateQueuedConfiguration(
            id: id,
            request: request,
            mode: configuration.subtitleMode,
            settings: configuration.applying(to: item.settings)
        )
    }

    /// Applies a recovery choice to one deferred task only. It never changes
    /// the default for future downloads, so a person can safely recover a
    /// single row from the capability sheet.
    @discardableResult
    func applyQueuedRecognitionFallback(
        id: UUID,
        fallback: QueuedRecognitionFallback
    ) -> Bool {
        guard let item = queue.items.first(where: { $0.id == id }),
              item.stage == .queued else {
            return false
        }

        var configuration = queuedProcessingConfiguration(for: item)
        switch fallback {
        case .platformSubtitles:
            configuration.subtitleSourcePolicy = .forcePlatform
            configuration.transcriptionModel = nil
        case .cloudRecognition:
            configuration.subtitleSourcePolicy = .cloudASR
            configuration.transcriptionModel = nil
        case .videoOnly:
            configuration.subtitleMode = .off
            configuration.subtitleSourcePolicy = .autoBest
            configuration.transcriptionModel = nil
            configuration.translationModel = nil
        }
        return updateQueuedTaskConfiguration(id: id, configuration: configuration)
    }

    /// The capability itself is global, but a deferred queue snapshot is
    /// intentionally frozen until an explicit update. Once the person enables
    /// local recognition, copy the verified settings into the originating task
    /// so its existing force-local choice can really start.
    @discardableResult
    func refreshQueuedLocalRecognitionCapability(id: UUID) -> Bool {
        guard let item = queue.items.first(where: { $0.id == id }),
              item.stage == .queued else {
            return false
        }
        var taskSettings = item.settings
        taskSettings.localASREnabled = settings.localASREnabled
        taskSettings.localASRRuntimePath = settings.localASRRuntimePath
        taskSettings.localASRModelID = settings.localASRModelID
        taskSettings.localASRModelPath = settings.localASRModelPath
        taskSettings.localASRVADModelPath = settings.localASRVADModelPath
        taskSettings.subtitleRecognitionMode = settings.subtitleRecognitionMode
        return queue.updateQueuedConfiguration(
            id: id,
            request: item.request,
            mode: item.chineseMode,
            settings: applyingCurrentCredentials(to: taskSettings)
        )
    }

    @discardableResult
    func refreshQueuedCloudRecognitionCapability(id: UUID) -> Bool {
        guard let item = queue.items.first(where: { $0.id == id }),
              item.stage == .queued else {
            return false
        }
        var taskSettings = item.settings
        taskSettings.cloudASREnabled = settings.cloudASREnabled
        taskSettings.cloudASRConsentAccepted = settings.cloudASRConsentAccepted
        taskSettings.cloudASRBaseURL = settings.cloudASRBaseURL
        taskSettings.cloudASRModel = settings.cloudASRModel
        taskSettings.cloudASRAuthToken = settings.cloudASRAuthToken
        return queue.updateQueuedConfiguration(
            id: id,
            request: item.request,
            mode: item.chineseMode,
            settings: applyingCurrentCredentials(to: taskSettings)
        )
    }

    private func queuedProcessingConfiguration(
        for item: QueueManager.QueueItem
    ) -> QueuedProcessingConfiguration {
        QueuedProcessingConfiguration(
            quality: item.request.formatID,
            outputFormat: item.request.outputFormat,
            subtitleMode: item.chineseMode,
            subtitleSourcePolicy: item.request.subtitleSourcePolicy,
            targetLanguage: item.settings.translationTargetLanguage,
            transcriptionModel: item.settings.localASRModelID,
            translationModel: item.settings.translationFollowsDefault
                ? item.settings.aiModel
                : item.settings.translationModel,
            subtitleStyle: item.settings.subtitleStyle
        )
    }

    private func applyingCurrentCredentials(to taskSettings: AppSettings) -> AppSettings {
        var snapshot = taskSettings
        snapshot.translationAuthToken = settings.translationAuthToken
        snapshot.aiAuthToken = settings.aiAuthToken
        snapshot.summaryAuthToken = settings.summaryAuthToken
        snapshot.cloudASRAuthToken = settings.cloudASRAuthToken
        return snapshot
    }

    private func queuedSubtitlePolicy(
        from persistedSource: String?,
        fallback: SubtitleSourcePolicy
    ) -> SubtitleSourcePolicy {
        guard let kind = persistedSource.flatMap(SubtitleSourceKind.init(rawValue:)) else {
            return fallback
        }
        switch kind {
        case .localASR: return .forceLocalASR
        case .cloudASR: return .cloudASR
        case .importedFile: return .importedFile
        case .manual, .platformAuto, .hlsManifest: return .forcePlatform
        }
    }

    private func queuedSubtitleTrack(
        for configuration: QueuedProcessingConfiguration,
        from request: DownloadRequest
    ) -> SubtitleChoice? {
        let sourceLanguage = request.primarySubtitleTrack?.languageCode
            ?? request.preferredSubtitleLanguageCode
            ?? "auto"
        switch configuration.subtitleSourcePolicy {
        case .forceLocalASR, .preferLocalASR, .compareLocalASR:
            return request.subtitleTracks.first(where: { $0.sourceKind == .localASR })
                ?? SubtitleChoice(
                    languageCode: sourceLanguage,
                    label: "本地识别字幕",
                    sourceKind: .localASR,
                    provider: "whisper.cpp",
                    variant: "queued"
                )
        case .cloudASR:
            return SubtitleChoice(
                languageCode: sourceLanguage,
                label: "云端识别字幕",
                sourceKind: .cloudASR,
                provider: "cloud-asr",
                variant: "queued"
            )
        case .importedFile:
            return request.subtitleTracks.first(where: { $0.sourceKind == .importedFile })
        case .forcePlatform, .preferPlatform:
            return request.subtitleTracks.first(where: {
                $0.sourceKind == .manual || $0.sourceKind == .platformAuto || $0.sourceKind == .hlsManifest
            })
        case .autoBest:
            return request.primarySubtitleTrack
        }
    }

    // 每个字符既非空白、也不是下一条链接的开头（负向前瞻保证相接的链接被切开）。
    private static let urlExtractionRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?i)https?://(?:(?!https?://)\S)+"#
    )

    /// 批量模式：逐个解析（多候选页取第一个，即页面主视频），按最高画质自动入队。
    /// 当前已选字幕处理模式会沿用，并自动挑一条字幕作翻译源（真实字幕优先）。
    private func processBatch(
        _ urls: [String],
        queuedConfiguration: QueuedProcessingConfiguration? = nil,
        libraryItemID: UUID? = nil,
        libraryVersionID: UUID? = nil,
        startImmediately: Bool = true
    ) {
        let mode = queuedConfiguration?.subtitleMode ?? chineseMode
        guard !startImmediately || dependenciesReady(for: mode) else { return }
        session += 1
        let token = session
        retryAction = nil
        failedNeedsLogin = nil
        failedNeedsDependency = false
        enqueueNotice = nil
        candidates = []
        chosenCandidate = nil
        queueExpanded = false
        stage = .resolving
        let currentSettings = queuedConfiguration?.applying(to: settings) ?? settings
        let sourcePolicy = queuedConfiguration?.subtitleSourcePolicy ?? subtitleSourcePolicy
        parseTask?.cancel()
        parseTask = Task {
            var added = 0
            var duplicated = 0
            var failedHosts: [String] = []
            for (index, urlString) in urls.enumerated() {
                guard token == self.session else { return }
                self.batchStatusText = CoreL10n.t(L.Main.batchParsing, index + 1, urls.count)
                do {
                    let found = try await self.engine.resolveCandidates(for: urlString)
                    guard token == self.session else { return }
                    guard let candidate = found.first else { throw MoongateError.sniffFailed("") }
                    var info = try await self.engine.analyze(url: candidate.url)
                    guard token == self.session else { return }
                    if candidate.kind == .pageMain || candidate.kind == .directFile,
                       !candidate.title.isEmpty, candidate.title != info.title {
                        info = VideoInfo(
                            sourceURL: info.sourceURL, videoID: info.videoID, title: candidate.title,
                            durationText: info.durationText, thumbnailURL: info.thumbnailURL,
                            uploader: info.uploader, detectedLanguageCode: info.detectedLanguageCode,
                            description: info.description,
                            formats: info.formats, subtitles: info.subtitles,
                            platformSubtitleHint: info.platformSubtitleHint
                        )
                    }
                    let formatID: String
                    if let quality = queuedConfiguration?.quality,
                       quality != "best" {
                        formatID = quality
                    } else if let preferred = info.formats.first?.id {
                        formatID = preferred
                    } else {
                        throw MoongateError.analyzeFailed(CoreL10n.t(L.Main.noAvailableFormat))
                    }
                    if self.queue.hasOpenDuplicate(
                        videoID: info.videoID, sourceURL: info.sourceURL, formatID: formatID
                    ) {
                        duplicated += 1
                        continue
                    }
                    // 字幕处理开启时自动选一条推荐语言；同语言内仍由 track 排序决定人工/自动/本地源。
                    var subtitleLangs: [String] = []
                    var autoSubtitleLangs: [String] = []
                    var subtitleTracks: [SubtitleChoice] = []
                    var primarySubtitleTrackID: String?
                    let sourceDecision = self.subtitleSourceDecision(
                        for: info,
                        targetLanguage: currentSettings.translationTargetLanguage,
                        sourcePolicy: sourcePolicy,
                        preferredSourceLanguageCode: currentSettings.preferredSourceLanguage
                    )
                    let configuredCloudASRTrack: SubtitleChoice? = sourcePolicy == .cloudASR
                        ? SubtitleChoice(
                            languageCode: self.effectiveSourceLanguagePreference(for: info),
                            label: "云端识别字幕",
                            sourceKind: .cloudASR,
                            provider: "cloud-asr",
                            variant: "queued"
                        )
                        : nil
                    if mode != .off,
                       let sub = configuredCloudASRTrack ?? sourceDecision.selectedTrack {
                        subtitleTracks = [sub]
                        primarySubtitleTrackID = sub.id
                        if sub.sourceKind == .platformAuto {
                            autoSubtitleLangs = [sub.languageCode]
                        } else if sub.sourceKind == .manual {
                            subtitleLangs = [sub.languageCode]
                        }
                    }
                    if startImmediately && shouldRequireTranslationReadiness(
                        for: mode,
                        info: info,
                        subtitleLangs: subtitleLangs,
                        autoSubtitleLangs: autoSubtitleLangs
                    ) {
                        let translationContext = currentSettings.makeTranslationContext(
                            sourceLanguage: subtitleTracks.first?.languageCode
                        )
                        guard await blockIfTranslationNotReady(
                            for: mode,
                            settings: currentSettings,
                            context: translationContext
                        ) else {
                            failedHosts.append(URL(string: urlString)?.host ?? urlString)
                            continue
                        }
                    }
                    let multiFile = mode != .off
                        || !subtitleLangs.isEmpty || !autoSubtitleLangs.isEmpty
                    let request = DownloadRequest(
                        url: info.sourceURL,
                        videoID: info.videoID,
                        formatID: formatID,
                        subtitleLangs: subtitleLangs,
                        autoSubtitleLangs: autoSubtitleLangs,
                        subtitleTracks: subtitleTracks,
                        primarySubtitleTrackID: primarySubtitleTrackID,
                        preferredSubtitleLanguageCode: primarySubtitleTrackID.map(normalizedLang),
                        sourceLanguageIntent: self.readySourceLanguageIntent,
                        subtitleSourcePolicy: sourcePolicy,
                        destinationDirectory: Self.destinationDirectory(
                            forTitle: info.title, multiFile: multiFile
                        ),
                        preferredTitle: (candidate.kind == .pageMain || candidate.kind == .directFile)
                            ? info.title : nil,
                        outputFormat: queuedConfiguration?.outputFormat ?? .original
                    )
                    self.queue.enqueue(
                        info: info,
                        request: request,
                        chineseMode: mode,
                        settings: currentSettings,
                        libraryItemID: libraryItemID,
                        libraryVersionID: libraryVersionID,
                        startImmediately: startImmediately
                    )
                    added += 1
                } catch is CancellationError {
                    return
                } catch {
                    guard token == self.session else { return }
                    if case MoongateError.cancelled = error { return }
                    failedHosts.append(URL(string: urlString)?.host ?? urlString)
                }
            }
            guard token == self.session else { return }
            self.batchStatusText = nil
            self.urlText = ""
            self.selectedFormatID = nil
            self.primarySubtitleTrackID = nil
            self.importedSubtitleFileURL = nil
            self.chineseMode = .off
            self.stage = .idle
            var parts: [String] = [CoreL10n.t(L.Main.batchAdded, added)]
            if duplicated > 0 { parts.append(CoreL10n.t(L.Main.batchDuplicateCount, duplicated)) }
            if !failedHosts.isEmpty {
                let sample = failedHosts.prefix(2).joined(separator: "、")
                let suffix = failedHosts.count > 2 ? CoreL10n.t(L.Main.batchFailedSuffix) : ""
                parts.append(CoreL10n.t(L.Main.batchFailedCount, failedHosts.count, sample, suffix))
            }
            self.enqueueNotice = parts.joined(separator: "；")
            if !startImmediately {
                self.deferredBatchAddedCount = added
            }
            self.queueExpanded = true
            self.requestUrlFocus += 1
        }
    }

    func cancelParse() {
        switch stage {
        case .resolving:
            session += 1
            parseTask?.cancel()
            parseTask = nil
            batchStatusText = nil
            stage = .idle
            queueExpanded = true
        case .analyzing:
            session += 1
            parseTask?.cancel()
            parseTask = nil
            stage = candidates.count > 1 ? .choosing(candidates) : .idle
        default:
            break
        }
    }

    func choose(_ candidate: VideoCandidate) {
        session += 1
        let token = session
        retryAction = nil
        failedNeedsLogin = nil
        failedNeedsDependency = false
        chosenCandidate = candidate
        stage = .analyzing
        parseTask?.cancel()
        parseTask = Task {
            do {
                var info = try await self.engine.analyze(url: candidate.url)
                // 直链/页面主视频的 yt-dlp 标题往往是 CDN 文件名，换成嗅探到的页面标题
                if candidate.kind == .pageMain || candidate.kind == .directFile,
                   !candidate.title.isEmpty, candidate.title != info.title {
                    info = VideoInfo(
                        sourceURL: info.sourceURL, videoID: info.videoID, title: candidate.title,
                        durationText: info.durationText, thumbnailURL: info.thumbnailURL,
                        uploader: info.uploader, detectedLanguageCode: info.detectedLanguageCode,
                        description: info.description,
                        formats: info.formats, subtitles: info.subtitles,
                        platformSubtitleHint: info.platformSubtitleHint
                    )
                }
                guard token == self.session else { return }
                self.selectedFormatID = info.formats.first?.id
                self.restoreDownloadOptions(for: info)
                self.resetSummary()
                self.stage = .ready(info)
            } catch {
                guard token == self.session else { return }
                self.fail(error) { [weak self] in self?.choose(candidate) }
            }
        }
    }

    /// ready 页「加入队列」：构造 DownloadRequest 入队，然后清空回可输入态以便继续添加下一条。
    func startDownload() async {
        guard case .ready(let info) = stage else { return }
        hydrateCredentials()
        let startSession = session
        let mode = chineseMode
        let selectedFormatIDSnapshot = selectedFormatID
        let selectedSubtitleIDsSnapshot = selectedSubtitleIDs
        let primarySubtitleTrackIDSnapshot = primarySubtitleTrackID
        let subtitleSourcePolicySnapshot = subtitleSourcePolicy
        let importedSubtitleFileURLSnapshot = importedSubtitleFileURL
        let preferHDRSnapshot = preferHDR
        let outputFormatSnapshot = selectedOutputFormat
        let currentSettings = settings
        let selectedCandidate = chosenCandidate

        if let primaryTrack = primarySubtitleTrack(in: info),
           primaryTrack.sourceKind == .localASR,
           !localASRReadyForDownload {
            openLocalASRSettings()
            return
        }
        if subtitleSourcePolicySnapshot == .cloudASR,
           !queue.hasCloudASRGenerator {
            openCloudASRSettings()
            return
        }
        guard dependenciesReady(for: mode) else { return }
        if shouldRequireTranslationReadiness(for: mode, info: info) {
            let translationContext = currentSettings.makeTranslationContext(
                sourceLanguage: translationSourceSubtitle(in: info)?.languageCode
            )
            guard await blockIfTranslationNotReady(
                for: mode,
                settings: currentSettings,
                context: translationContext
            ) else { return }
            guard startSession == session else { return }
            guard case .ready(let currentInfo) = stage,
                  currentInfo.sourceURL == info.sourceURL,
                  currentInfo.videoID == info.videoID else { return }
        }
        guard let formatID = selectedFormatIDSnapshot ?? info.formats.first?.id else { return }
        let selectedFormat = info.formats.first { $0.id == formatID }
        let requestPreferHDR = preferHDRSnapshot && (selectedFormat?.hdrAvailable ?? false)
        // 去重：队列里已有同源未完成任务时不再起新任务，只给一行提示。
        if queue.hasOpenDuplicate(videoID: info.videoID, sourceURL: info.sourceURL, formatID: formatID) {
            enqueueNotice = CoreL10n.t(L.Main.videoAlreadyQueued)
            return
        }
        let chosen = availableSubtitleChoices(for: info).filter { selectedSubtitleIDsSnapshot.contains($0.id) }
        // 会产出多个文件（字幕 / 翻译 / 烧录件）时在 App 下载目录下按视频建独立文件夹。
        let multiFile = !chosen.isEmpty || mode != .off
        let request = DownloadRequest(
            url: info.sourceURL,
            videoID: info.videoID,
            formatID: formatID,
            subtitleLangs: chosen.filter { !$0.isAuto }.map(\.languageCode),
            autoSubtitleLangs: chosen.filter { $0.isAuto }.map(\.languageCode),
            subtitleTracks: chosen,
            primarySubtitleTrackID: primarySubtitleTrackIDSnapshot,
            preferredSubtitleLanguageCode: primarySubtitleTrackIDSnapshot.map(normalizedLang),
            sourceLanguageIntent: readySourceLanguageIntent,
            subtitleSourcePolicy: subtitleSourcePolicySnapshot,
            importedSubtitleFileURL: importedSubtitleFileURLSnapshot,
            destinationDirectory: Self.destinationDirectory(forTitle: info.title, multiFile: multiFile),
            preferredTitle: {
                guard let kind = selectedCandidate?.kind, kind == .pageMain || kind == .directFile else { return nil }
                return info.title
            }(),
            preferHDR: requestPreferHDR,
            outputFormat: outputFormatSnapshot
        )
        queue.enqueue(info: info, request: request, chineseMode: mode, settings: currentSettings)

        // 回到可输入态，方便粘贴下一条。先切到 idle 再清空选项，避免清空触发 didSet 把
        // 已记住的「上次选项」误清（持久化只在 stage == .ready 时发生）。
        stage = .idle
        session += 1
        parseTask?.cancel()
        parseTask = nil
        urlText = ""
        selectedFormatID = nil
        self.primarySubtitleTrackID = nil
        importedSubtitleFileURL = nil
        chineseMode = .off
        candidates = []
        chosenCandidate = nil
        retryAction = nil
        failedNeedsLogin = nil
        failedNeedsDependency = false
        enqueueNotice = CoreL10n.t(L.Main.enqueuedTitle, info.title)
        // 入队即铺满队列（新任务落位可见），重新聚焦输入框方便直接粘贴下一条。
        queueExpanded = true
        requestUrlFocus += 1
    }

    /// Creates a distinct QueueItem for a completed library version. Each
    /// reprocess gets an isolated output folder, and only a source-quality
    /// refresh is allowed to call the network engine again.
    @discardableResult
    func enqueueLibraryReprocess(
        item: MoongateCore.LibraryItem,
        configuration: LibraryProcessingConfiguration,
        plan: ReprocessPlan
    ) async throws -> UUID {
        guard let sourceVersion = item.latestVersion else {
            throw MoongateError.analyzeFailed("找不到可重新处理的版本。")
        }
        let refreshesSourceVideo = plan.steps.contains(.refreshVideo)
        let sourceURL: String
        if refreshesSourceVideo {
            guard let source = item.source, source.supportsRestart else {
                throw MoongateError.analyzeFailed("此变更需要重新下载原视频。请使用可安全重新开始的原链接新建下载。")
            }
            sourceURL = source.urlString
        } else {
            // QueueManager skips the network for local reprocesses. A
            // non-HTTP scheme keeps recovered records source-less when their
            // snapshot is persisted instead of inventing a fake web link.
            sourceURL = item.source?.urlString ?? "moongate-library://\(item.id.uuidString)"
        }

        hydrateCredentials()
        let existingArtifacts = sourceVersion.artifacts.compactMap { artifact -> (LibraryArtifact, URL)? in
            let root = Self.appDownloadsDirectory.standardizedFileURL
            let candidate = root.appendingPathComponent(artifact.relativePath).standardizedFileURL
            let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
            guard candidate.path.hasPrefix(rootPrefix),
                  FileManager.default.fileExists(atPath: candidate.path) else {
                return nil
            }
            return (artifact, candidate)
        }
        let existingFiles = existingArtifacts.map(\.1)
        guard existingFiles.contains(where: { QueueManager.videoExtensions.contains($0.pathExtension.lowercased()) }) else {
            throw MoongateError.analyzeFailed("找不到原始视频文件，无法创建重新处理任务。")
        }

        let outputFormat: OutputFormat
        if let rawOutputFormat = configuration.outputFormat?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !rawOutputFormat.isEmpty {
            guard let parsed = OutputFormat(rawValue: rawOutputFormat) else {
                throw MoongateError.analyzeFailed("输出格式无效。请从列表中选择保持源格式、H.264、H.265 或 MKV。")
            }
            outputFormat = parsed
        } else {
            outputFormat = .original
        }
        let needsBurn = plan.steps.contains(.burn)
        let needsTranslation = plan.steps.contains(.translate)
        let requiresASR = plan.steps.contains(.transcribe)
        let subtitleSourceChanged = sourceVersion.processing.configuration.subtitleSource != configuration.subtitleSource
        let reusesCompletedSubtitle = needsBurn && !needsTranslation && !requiresASR && !subtitleSourceChanged
        let configuredSubtitleKind: SubtitleSourceKind?
        if let rawSubtitleSource = configuration.subtitleSource?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !rawSubtitleSource.isEmpty {
            guard let parsed = SubtitleSourceKind(rawValue: rawSubtitleSource) else {
                throw MoongateError.analyzeFailed("字幕来源无效。请从列表中选择已有字幕、本地识别或云端识别。")
            }
            configuredSubtitleKind = parsed
        } else {
            configuredSubtitleKind = nil
        }
        let mode: ChineseSubtitleMode
        if let configuredMode = ChineseSubtitleMode(rawValue: configuration.subtitleMode ?? "") {
            mode = configuredMode
        } else if needsBurn {
            mode = needsTranslation ? .burnIn : .burnOriginal
        } else if needsTranslation {
            mode = .srtOnly
        } else {
            mode = .off
        }
        let requiresSubtitleInput = mode != .off
            && (needsBurn || needsTranslation || requiresASR || subtitleSourceChanged)
        guard dependenciesReady(for: mode) else {
            throw MoongateError.analyzeFailed("请先完成所需依赖配置。")
        }

        var taskSettings = settings
        if let rawStyle = configuration.subtitleStyle,
           let style = SubtitleStyle(rawValue: rawStyle) {
            taskSettings.subtitleStyle = style
        }
        if let targetLanguage = configuration.targetLanguage,
           !targetLanguage.isEmpty {
            taskSettings.translationTargetLanguage = targetLanguage
        }
        if let translationModel = configuration.translationModel,
           !translationModel.isEmpty {
            if taskSettings.translationFollowsDefault {
                taskSettings.aiModel = translationModel
            } else {
                taskSettings.translationModel = translationModel
            }
        }
        // Reuse the queued-draft model resolver instead of changing only the
        // visible model ID. A different local model must also resolve to its
        // verified managed path; otherwise an unavailable selection would
        // silently run the previous model file. Keep the other task-scoped
        // settings unchanged while applying this focused ASR override.
        let taskConfiguration = QueuedProcessingConfiguration(
            targetLanguage: taskSettings.translationTargetLanguage,
            transcriptionModel: requiresASR ? configuration.transcriptionModel : nil,
            subtitleStyle: taskSettings.subtitleStyle
        )
        taskSettings = taskConfiguration.applying(to: taskSettings)
        guard let sourceVideo = existingArtifacts.first(where: {
            QueueManager.videoExtensions.contains($0.1.pathExtension.lowercased())
        })?.1 else {
            throw MoongateError.analyzeFailed("找不到原始视频文件，无法创建重新处理任务。")
        }
        let versionDirectory = try ReprocessWorkspace.createVersionDirectory(
            beside: sourceVideo.deletingLastPathComponent(),
            versionNumber: sourceVersion.number + 1
        )
        // A source-quality refresh downloads a new video into vN. Keep only
        // reusable subtitles there; copying v1's video would create an
        // unindexed duplicate once the fresh download completes.
        let artifactURLsByID = Dictionary(uniqueKeysWithValues: existingArtifacts.map { ($0.0.id, $0.1) })
        let artifactsToCopy: [URL]
        if refreshesSourceVideo {
            artifactsToCopy = existingArtifacts.compactMap { artifact, url in
                switch artifact.role {
                case .video, .renderedVideo: nil
                case .sourceSubtitle, .translatedSubtitle, .thumbnail, .other: url
                }
            }
        } else {
            artifactsToCopy = ReprocessWorkspace.localReprocessArtifacts(
                from: sourceVersion,
                requiresCleanVideo: needsBurn
            ).compactMap { artifactURLsByID[$0.id] }
        }
        let isolatedFiles = try ReprocessWorkspace.copyArtifacts(artifactsToCopy, to: versionDirectory)
        if !refreshesSourceVideo,
           !isolatedFiles.contains(where: { QueueManager.videoExtensions.contains($0.pathExtension.lowercased()) }) {
            throw MoongateError.analyzeFailed("无法为重新处理准备独立的视频版本。")
        }

        let subtitleFiles = isolatedFiles.filter {
            ["srt", "vtt"].contains($0.pathExtension.lowercased())
        }
        let translatedSubtitle = subtitleFiles.first {
            TranslationLanguage.isTranslatedSubtitleFileName($0.lastPathComponent)
        }
        let existingSourceSubtitle = subtitleFiles.first {
            !TranslationLanguage.isTranslatedSubtitleFileName($0.lastPathComponent)
        }

        let subtitleKind: SubtitleSourceKind?
        let selectedSubtitle: URL?
        if reusesCompletedSubtitle {
            guard let reusableSubtitle = translatedSubtitle ?? existingSourceSubtitle else {
                throw MoongateError.analyzeFailed("未找到可复用字幕，无法只重新压制。请选择新的字幕来源或重新转录。")
            }
            subtitleKind = .importedFile
            selectedSubtitle = reusableSubtitle
        } else if requiresASR {
            subtitleKind = configuredSubtitleKind == .cloudASR ? .cloudASR : .localASR
            selectedSubtitle = nil
        } else if requiresSubtitleInput {
            guard let configuredSubtitleKind else {
                throw MoongateError.analyzeFailed("请选择要使用的已有字幕来源，或改为本地/云端识别。")
            }
            switch configuredSubtitleKind {
            case .localASR, .cloudASR:
                // The planner normally reaches this through `requiresASR`.
                // Keep the choice explicit if a migrated record gets here.
                subtitleKind = configuredSubtitleKind
                selectedSubtitle = nil
            case .manual, .platformAuto, .hlsManifest, .importedFile:
                guard let existingSourceSubtitle else {
                    throw MoongateError.analyzeFailed("当前版本没有可复用的源字幕；请选择本地或云端识别。")
                }
                // 0.9 can select a known existing subtitle but cannot invent
                // a new remote/manual track without a picker. Normalise it to
                // importedFile and pass the exact isolated path below.
                subtitleKind = .importedFile
                selectedSubtitle = existingSourceSubtitle
            }
        } else {
            subtitleKind = nil
            selectedSubtitle = nil
        }
        // Local ASR is resolved from the immutable per-task snapshot in
        // QueueManager. Do not preflight the mutable global generator here:
        // it can still point to the previous model and would either reject a
        // valid replacement or let an unavailable one inherit that old file.
        // QueueManager leaves an unavailable selection queued with a
        // recoverable preparation message instead.
        if subtitleKind == .cloudASR, !queue.hasCloudASRGenerator {
            openCloudASRSettings()
            throw MoongateError.analyzeFailed("云端语音识别尚未配置。请先在设置中完成配置。")
        }

        let subtitleTrack = subtitleKind.map { kind in
            SubtitleChoice(
                languageCode: "auto",
                label: {
                    switch kind {
                    case .localASR: "本地识别字幕"
                    case .cloudASR: "云端识别字幕"
                    default: "已有字幕"
                    }
                }(),
                sourceKind: kind,
                provider: kind == .localASR ? "whisper.cpp" : "library",
                variant: "reprocess",
                metadata: selectedSubtitle.map { ["path": $0.path] } ?? [:]
            )
        }
        let sourcePolicy: SubtitleSourcePolicy
        switch subtitleKind {
        case .localASR: sourcePolicy = .forceLocalASR
        case .cloudASR: sourcePolicy = .cloudASR
        case .importedFile: sourcePolicy = .importedFile
        case .manual, .platformAuto, .hlsManifest, .none: sourcePolicy = .autoBest
        }

        let formatID = configuration.quality?.isEmpty == false ? configuration.quality! : "best"
        let request = DownloadRequest(
            url: sourceURL,
            videoID: "library-\(item.id.uuidString)",
            formatID: formatID,
            subtitleLangs: [],
            autoSubtitleLangs: [],
            subtitleTracks: subtitleTrack.map { [$0] } ?? [],
            primarySubtitleTrackID: subtitleTrack?.id,
            preferredSubtitleLanguageCode: subtitleTrack?.languageCode,
            sourceLanguageIntent: .automatic,
            subtitleSourcePolicy: sourcePolicy,
            importedSubtitleFileURL: selectedSubtitle,
            destinationDirectory: versionDirectory,
            preferredTitle: item.title,
            outputFormat: outputFormat
        )
        let info = VideoInfo(
            sourceURL: sourceURL,
            videoID: "library-\(item.id.uuidString)",
            title: item.title,
            durationText: nil,
            thumbnailURL: item.thumbnail.flatMap { URL(string: $0.urlString) },
            uploader: nil,
            formats: [FormatChoice(id: formatID, label: "资料库重新处理")],
            subtitles: subtitleTrack.map { [$0] } ?? []
        )
        let reuseExistingArtifacts = !refreshesSourceVideo
        let taskID = queue.enqueueReprocess(
            info: info,
            request: request,
            chineseMode: mode,
            settings: taskSettings,
            existingFiles: isolatedFiles,
            libraryItemID: item.id,
            libraryVersionID: plan.outputVersionID,
            reuseExistingArtifacts: reuseExistingArtifacts
        )
        enqueueNotice = "已创建重新处理任务：\(item.title)"
        queueExpanded = true
        return taskID
    }

    /// 把当前选档页的选择即时记住（持久化为「上次下载选项」），供下次选档页恢复。
    /// 仅在 ready（用户正在选档）时记：恢复发生在 analyzing 阶段、入队后的清空发生在 idle 阶段，
    /// 都不会触发记忆，避免「恢复值/清空值」污染记忆。无变化时不落盘，避免每次切换都写磁盘。
    private func persistCurrentDownloadOptions() {
        guard case .ready(let info) = stage else { return }
        let selectedSubtitleLangs = availableSubtitleChoices(for: info)
            .filter { selectedSubtitleIDs.contains($0.id) }
            .map(\.languageCode)
        if settings.lastSubtitleMode == chineseMode.rawValue,
           settings.lastOutputFormat == selectedOutputFormat,
           settings.lastPreferHDR == preferHDR,
           settings.lastPrimarySubtitleTrackID == primarySubtitleTrackID,
           Set(settings.lastSubtitleLangs) == Set(selectedSubtitleLangs) {
            return
        }
        var updated = settings
        updated.lastSubtitleMode = chineseMode.rawValue
        updated.lastSubtitleLangs = selectedSubtitleLangs
        updated.lastPrimarySubtitleTrackID = primarySubtitleTrackID
        updated.lastOutputFormat = selectedOutputFormat
        updated.lastPreferHDR = preferHDR
        settings = updated
        _ = saveSettings()
    }

    /// 字幕 id 归一成语言代码：小写、取首个 `-` 前的部分。
    /// 这样上次选「ja」能匹配下个视频的「ja」/「ja-JP」/「ja-orig」/自动生成的日语字幕。
    private func normalizedLang(_ id: String) -> String {
        SubtitleLanguageChoice.normalizedLanguageCode(SubtitleTrackID(rawValue: id).languageCode)
    }

    func availableSubtitleChoices(for info: VideoInfo) -> [SubtitleChoice] {
        var choices = info.subtitles

        var seenIDs = Set(choices.map(\.id))
        let preferredSourceLanguage = effectiveSourceLanguagePreference(for: info)
        if info.subtitles.isEmpty {
            appendLocalASRChoice(
                languageCode: preferredSourceLanguage,
                label: preferredSourceLanguage == "auto" ? CoreL10n.t(L.Ready.localASRAutoDetectLabel) : nil,
                to: &choices,
                seenIDs: &seenIDs
            )
            appendImportedSubtitleChoice(for: info, to: &choices, seenIDs: &seenIDs)
            return choices
        }

        var seenLanguages: Set<String> = []
        for subtitle in info.subtitles {
            let languageCode = normalizedLang(subtitle.languageCode)
            guard !languageCode.isEmpty, seenLanguages.insert(languageCode).inserted else { continue }

            appendLocalASRChoice(
                languageCode: languageCode,
                label: subtitle.label,
                to: &choices,
                seenIDs: &seenIDs
            )
        }
        if preferredSourceLanguage != "auto" {
            appendLocalASRChoice(
                languageCode: preferredSourceLanguage,
                label: TranslationLanguage.sourceDisplayName(for: preferredSourceLanguage),
                to: &choices,
                seenIDs: &seenIDs
            )
        }
        appendImportedSubtitleChoice(for: info, to: &choices, seenIDs: &seenIDs)
        return choices
    }

    private func appendImportedSubtitleChoice(
        for info: VideoInfo,
        to choices: inout [SubtitleChoice],
        seenIDs: inout Set<String>
    ) {
        guard let imported = importedSubtitleChoice(for: info) else { return }
        if seenIDs.insert(imported.id).inserted {
            choices.append(imported)
        }
    }

    private func appendLocalASRChoice(
        languageCode: String,
        label: String?,
        to choices: inout [SubtitleChoice],
        seenIDs: inout Set<String>
    ) {
        let localASR = SubtitleChoice(
            languageCode: languageCode,
            label: TranslationLanguage.sourceDisplayName(for: languageCode)
                ?? label
                ?? CoreL10n.t(L.Ready.localASRAutoDetectLabel),
            sourceKind: .localASR,
            provider: "whisper.cpp",
            variant: "local"
        )
        if seenIDs.insert(localASR.id).inserted {
            choices.append(localASR)
        }
    }

    private func importedSubtitleChoice(for info: VideoInfo) -> SubtitleChoice? {
        guard let url = importedSubtitleFileURL else { return nil }
        let languageCode = importedSubtitleLanguageCode(for: info)
        return SubtitleChoice(
            languageCode: languageCode,
            label: CoreL10n.t(L.Ready.importedSubtitleFileLabel, url.lastPathComponent),
            sourceKind: .importedFile,
            provider: "local-file",
            variant: url.lastPathComponent,
            qualityHint: url.lastPathComponent,
            metadata: ["path": url.path]
        )
    }

    private func importedSubtitleLanguageCode(for info: VideoInfo) -> String {
        let preferred = effectiveSourceLanguagePreference(for: info)
        if preferred != "auto" { return preferred }
        return SubtitleLanguageRecommender.inferredLocalASRLanguageCode(title: info.title) ?? "auto"
    }

    func importSubtitleFile(_ url: URL, for info: VideoInfo) {
        let supportedExtensions: Set<String> = ["srt", "vtt"]
        guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
            enqueueNotice = CoreL10n.t(L.Ready.importedSubtitleUnsupported)
            return
        }
        importedSubtitleFileURL = url
        subtitleSourcePolicy = .importedFile
        ensureSubtitleSourceSelected(for: info)
        if let imported = importedSubtitleChoice(for: info) {
            primarySubtitleTrackID = imported.id
        }
        if subtitleIntent == .none {
            setSubtitleIntent(.sourceSRT, for: info)
        }
    }

    func clearImportedSubtitleFile(for info: VideoInfo) {
        let selectedImported = primarySubtitleTrack(in: info)?.sourceKind == .importedFile
        importedSubtitleFileURL = nil
        if selectedImported {
            subtitleSourcePolicy = .autoBest
            primarySubtitleTrackID = nil
            ensureSubtitleSourceSelected(for: info)
        }
    }

    func effectiveSourceLanguagePreference(for info: VideoInfo) -> String {
        let preferred = readySourceLanguagePreference.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "auto"
            ? "auto"
            : LanguageCatalog.normalize(readySourceLanguagePreference)
        if preferred != "auto" {
            return preferred
        }
        if let detectedLanguageCode = info.detectedLanguageCode,
           !detectedLanguageCode.isEmpty {
            return detectedLanguageCode
        }
        return SubtitleLanguageRecommender.inferredLocalASRLanguageCode(title: info.title) ?? "auto"
    }

    func subtitleSourceDecision(
        for info: VideoInfo,
        targetLanguage: String? = nil,
        sourcePolicy: SubtitleSourcePolicy? = nil,
        preferredSourceLanguageCode: String? = nil
    ) -> SubtitleSourceDecisionReport {
        SubtitleSourceDecision.decide(
            videoTitle: info.title,
            detectedLanguageCode: info.detectedLanguageCode,
            targetLanguageCode: targetLanguage ?? settings.translationTargetLanguage,
            preferredSourceLanguageCode: preferredSourceLanguageCode ?? readySourceLanguagePreference,
            sourcePolicy: sourcePolicy ?? subtitleSourcePolicy,
            choices: availableSubtitleChoices(for: info),
            localASRAvailable: localASRReadyForDownload,
            cloudASRAvailable: queue.hasCloudASRGenerator
        )
    }

    var localASRReadyForDownload: Bool {
        queue.hasLocalASRGenerator
    }

    // MARK: - Language-first ready page

    var subtitleIntent: SubtitleIntent {
        if primarySubtitleTrackID == nil && chineseMode == .off {
            return .none
        }
        switch chineseMode {
        case .off:
            return .sourceSRT
        case .srtOnly:
            return .translatedSRT
        case .burnIn:
            return .burnTranslated
        case .burnOriginal:
            return .burnSource
        }
    }

    func setSubtitleIntent(_ intent: SubtitleIntent, for info: VideoInfo) {
        switch intent {
        case .none:
            primarySubtitleTrackID = nil
            chineseMode = .off
        case .sourceSRT:
            ensureSubtitleSourceSelected(for: info)
            chineseMode = .off
        case .translatedSRT:
            ensureSubtitleSourceSelected(for: info)
            chineseMode = .srtOnly
        case .burnTranslated:
            ensureSubtitleSourceSelected(for: info)
            chineseMode = .burnIn
        case .burnSource:
            ensureSubtitleSourceSelected(for: info)
            chineseMode = .burnOriginal
        }
    }

    func readySubtitleState(for info: VideoInfo) -> ReadySubtitleState {
        let intent = subtitleIntent
        let sourceDecision = intent.needsSubtitleSource ? subtitleSourceDecision(for: info) : nil
        let selectedTrack = primarySubtitleTrack(in: info) ?? sourceDecision?.selectedTrack
        let translationRequired = intent.requiresTranslation && !translationSourceMatchesTarget(in: info)
        let translationReady = !translationRequired || translationReadinessForCurrentSettings().isReady
        let localASRRequiredButUnavailable = selectedTrack?.sourceKind == .localASR && !localASRReadyForDownload
        let cloudASRRequiredButUnavailable = subtitleSourcePolicy == .cloudASR && !queue.hasCloudASRGenerator
        return ReadySubtitleState(
            intent: intent,
            sourcePolicy: subtitleSourcePolicy,
            selectedTrack: selectedTrack,
            sourceDecision: sourceDecision,
            translationRequired: translationRequired,
            translationReady: translationReady,
            localASRRequiredButUnavailable: localASRRequiredButUnavailable,
            cloudASRRequiredButUnavailable: cloudASRRequiredButUnavailable
        )
    }

    func setSubtitleSourcePolicy(_ policy: SubtitleSourcePolicy, for info: VideoInfo) {
        subtitleSourcePolicy = policy
        guard subtitleIntent.needsSubtitleSource else { return }
        if let track = trackMatching(policy: policy, for: info) {
            primarySubtitleTrackID = track.id
        }
    }

    private func applySubtitleRecognitionMode(_ mode: SubtitleRecognitionMode) {
        switch mode {
        case .automatic:
            if subtitleSourcePolicy == .forceLocalASR || subtitleSourcePolicy == .forcePlatform {
                subtitleSourcePolicy = .autoBest
            }
        case .alwaysLocal:
            subtitleSourcePolicy = .forceLocalASR
        case .platformOnly:
            subtitleSourcePolicy = .forcePlatform
        }
    }

    private func ensureSubtitleSourceSelected(for info: VideoInfo) {
        if primarySubtitleTrack(in: info) != nil { return }
        if let policyTrack = trackMatching(policy: subtitleSourcePolicy, for: info) {
            primarySubtitleTrackID = policyTrack.id
            return
        }
        if let recommended = recommendedLanguage(for: info) {
            selectLanguage(recommended)
        }
    }

    private func trackMatching(policy: SubtitleSourcePolicy, for info: VideoInfo) -> SubtitleChoice? {
        let currentLanguage = primarySubtitleTrack(in: info)?.languageCode
        return subtitleSourceDecision(
            for: info,
            sourcePolicy: policy,
            preferredSourceLanguageCode: currentLanguage ?? readySourceLanguagePreference
        ).selectedTrack
    }

    private func isPlatformTrack(_ track: SubtitleChoice) -> Bool {
        track.sourceKind == .manual || track.sourceKind == .platformAuto || track.sourceKind == .hlsManifest
    }

    static let sourceLanguagePreferenceOptions: [SourceLanguagePreferenceOption] = [
        SourceLanguagePreferenceOption(code: "auto"),
        SourceLanguagePreferenceOption(code: "en"),
        SourceLanguagePreferenceOption(code: "ja"),
        SourceLanguagePreferenceOption(code: "zh-Hans"),
        SourceLanguagePreferenceOption(code: "ko"),
        SourceLanguagePreferenceOption(code: "yue"),
    ]

    static func sourceLanguageIntent(from preference: String) -> SourceLanguageIntent {
        let normalized = preference.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "auto"
            ? "auto"
            : LanguageCatalog.normalize(preference)
        return normalized == "auto" ? .automatic : .language(normalized)
    }

    static func sourceLanguagePreference(from intent: SourceLanguageIntent) -> String {
        switch intent {
        case .automatic:
            return "auto"
        case .language(let code):
            return LanguageCatalog.normalize(code)
        }
    }

    /// Language groups for the ready page (manual / auto / localASR collapsed per language).
    func availableLanguageChoices(for info: VideoInfo) -> [SubtitleLanguageChoice] {
        SubtitleLanguageRecommender.aggregate(availableSubtitleChoices(for: info))
    }

    /// Deterministic recommendation (recommended language + the rest), driven by title + tracks.
    func languageRecommendation(for info: VideoInfo) -> SubtitleLanguageRecommender.Result {
        SubtitleLanguageRecommender.recommend(
            title: info.title,
            languages: availableLanguageChoices(for: info),
            targetLanguage: settings.translationTargetLanguage,
            preferredSourceLanguage: effectiveSourceLanguagePreference(for: info)
        )
    }

    func sourceLanguageRecommendation(for info: VideoInfo) -> SubtitleLanguageRecommender.SourceLanguageRecommendation {
        SubtitleLanguageRecommender.sourceRecommendation(
            title: info.title,
            languages: availableLanguageChoices(for: info),
            targetLanguage: settings.translationTargetLanguage,
            preferredSourceLanguage: effectiveSourceLanguagePreference(for: info)
        )
    }

    /// The single language shown by default in the ready page main area.
    func recommendedLanguage(for info: VideoInfo) -> SubtitleLanguageChoice? {
        let languages = availableLanguageChoices(for: info)
        if let selected = subtitleSourceDecision(for: info).selectedTrack,
           let match = languages.first(where: { language in
            language.tracks.contains { $0.id == selected.id }
           }) {
            return match
        }
        return languageRecommendation(for: info).recommended
    }

    /// Other languages for the disclosure area (everything except the recommended one).
    func otherLanguages(for info: VideoInfo) -> [SubtitleLanguageChoice] {
        languageRecommendation(for: info).others
    }

    /// True when this language group is the currently selected source (by its preferred track).
    func isLanguageSelected(_ language: SubtitleLanguageChoice) -> Bool {
        guard let primarySubtitleTrackID else { return false }
        return language.tracks.contains { $0.id == primarySubtitleTrackID }
    }

    /// Selects a language: picks its preferred track (manual > auto > localASR) as the primary source.
    /// localASR-only groups still select when the generator isn't ready — the row shows a configure
    /// entry point, but the user's language intent is recorded.
    func selectLanguage(_ language: SubtitleLanguageChoice) {
        guard let track = language.preferredTrack else { return }
        primarySubtitleTrackID = track.id
    }

    func setReadySourceLanguagePreference(_ code: String, for info: VideoInfo) {
        readySourceLanguagePreference = code
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "auto"
            ? "auto"
            : LanguageCatalog.normalize(code)
        if normalized == "auto" {
            if let recommended = recommendedLanguage(for: info) {
                selectLanguage(recommended)
            }
            return
        }
        if let selected = availableLanguageChoices(for: info).first(where: { $0.languageCode == normalized }) {
            selectLanguage(selected)
        } else {
            ensureSubtitleSourceSelected(for: info)
        }
    }

    func openSettings(paneID: String? = nil) {
        pendingSettingsPaneID = paneID
        showSettings = true
    }

    func openLocalASRSettings() {
        settingsNotice = nil
        localRecognitionCapabilitySetupRequest = .defaults
        openSettings(paneID: "subtitlesLanguage")
    }

    func openLocalASRSettings(forQueuedTaskID queueID: UUID) {
        settingsNotice = nil
        localRecognitionCapabilitySetupRequest = .queuedTask(queueID)
        openSettings(paneID: "subtitlesLanguage")
    }

    /// Keeps the ready-page recovery entry point stable while the queued-task
    /// variant below carries task context for a draft-specific repair.
    func openCloudASRSettings() {
        openCloudASRSettings(forQueuedTaskID: nil)
    }

    func openCloudASRSettings(forQueuedTaskID queueID: UUID?) {
        settingsNotice = CoreL10n.t(L.Ready.cloudASRSetupRequired)
        cloudRecognitionConfigurationRequestQueueID = queueID
        cloudRecognitionConfigurationRequested = true
        openSettings(paneID: "servicesAccounts")
    }

    /// 选档页恢复上次的下载选项：输出格式 / HDR 直接套用；字幕按语言代码在本视频可用字幕里匹配
    /// （真实字幕优先于自动字幕）；字幕处理方式在字幕恢复之后再设，避免 selectedSubtitleIDs 的
    /// didSet 把它打回 .off。本方法在 analyzing 阶段调用，期间不会触发 persist（持久化只认 .ready）。
    private func restoreDownloadOptions(for info: VideoInfo) {
        readySourceLanguagePreference = settings.preferredSourceLanguage
        preferHDR = settings.lastPreferHDR
        selectedOutputFormat = settings.lastOutputFormat ?? .original

        let available = availableSubtitleChoices(for: info)
        var matchedPrimaryID: String?
        if let lastPrimarySubtitleTrackID = settings.lastPrimarySubtitleTrackID,
           let exact = available.first(where: { $0.id == lastPrimarySubtitleTrackID }),
           exact.sourceKind != .localASR || localASRReadyForDownload {
            matchedPrimaryID = exact.id
        } else {
            let wantedLangs = Set(settings.lastSubtitleLangs.map { normalizedLang($0) })
            for lang in wantedLangs {
                let group = available.filter {
                    normalizedLang($0.languageCode) == lang && $0.sourceKind != .localASR
                }
                if let best = group.first(where: { !$0.isAuto }) ?? group.first,
                   best.sourceKind != .localASR {
                    matchedPrimaryID = best.id
                    break
                }
            }
        }
        // 没有命中上次手选/语言 → 用语言优先推荐器选一个推荐语言（确定性，随视频内容变化）。
        if matchedPrimaryID == nil {
            if let recommended = recommendedLanguage(for: info)?.preferredTrack,
               recommended.sourceKind != .localASR || localASRReadyForDownload {
                matchedPrimaryID = recommended.id
            }
        }
        languageSectionExpanded = false
        primarySubtitleTrackID = matchedPrimaryID

        // 仅当字幕成功恢复、且记录的处理方式不是「不需要」时才恢复 mode（否则保持 didSet 设好的 .off）。
        if matchedPrimaryID != nil,
           let raw = settings.lastSubtitleMode,
           let mode = ChineseSubtitleMode(rawValue: raw),
           mode != .off {
            chineseMode = mode
        }
    }

    func primarySubtitleTrack(in info: VideoInfo) -> SubtitleChoice? {
        guard let primarySubtitleTrackID else { return nil }
        return availableSubtitleChoices(for: info).first { $0.id == primarySubtitleTrackID }
    }

    /// ready 页提示用：勾选多条字幕时实际作为翻译源的那条（真实字幕优先、按解析顺序取第一条）。
    func translationSourceSubtitle(in info: VideoInfo) -> SubtitleChoice? {
        primarySubtitleTrack(in: info)
    }

    /// 实际翻译源字幕是否已与翻译目标语言同一脚本（同则跳过翻译、直接使用/烧录）。
    /// 例：目标=简中且源=zh-Hans → 跳过；目标=繁中且源=zh-Hans → 不跳过（仍要简转繁翻译）。
    func translationSourceMatchesTarget(in info: VideoInfo) -> Bool {
        guard let source = translationSourceSubtitle(in: info) else { return false }
        return TranslationLanguage.matches(source: source.languageCode, target: settings.translationTargetLanguage)
    }

    func shouldRequireTranslationReadiness(for mode: ChineseSubtitleMode, info: VideoInfo) -> Bool {
        mode.requiresTranslation && !translationSourceMatchesTarget(in: info)
    }

    private func shouldRequireTranslationReadiness(
        for mode: ChineseSubtitleMode,
        info: VideoInfo,
        subtitleLangs: [String],
        autoSubtitleLangs: [String]
    ) -> Bool {
        mode.requiresTranslation
            && !translationSourceMatchesTarget(
                in: info,
                subtitleLangs: subtitleLangs,
                autoSubtitleLangs: autoSubtitleLangs
            )
    }

    private func translationSourceMatchesTarget(
        in info: VideoInfo,
        subtitleLangs: [String],
        autoSubtitleLangs: [String]
    ) -> Bool {
        let sourceID = subtitleLangs.first ?? autoSubtitleLangs.first
        guard let sourceID else { return false }
        guard info.subtitles.contains(where: { $0.languageCode == sourceID }) else { return false }
        return TranslationLanguage.matches(source: sourceID, target: settings.translationTargetLanguage)
    }

    func backToList() {
        guard candidates.count > 1 else { return }
        session += 1
        parseTask?.cancel()
        parseTask = nil
        retryAction = nil
        failedNeedsLogin = nil
        failedNeedsDependency = false
        resetSummary()
        stage = .choosing(candidates)
    }

    func retry() {
        guard case .failed = stage else { return }
        if let action = retryAction {
            action()
        } else {
            reset()
        }
    }

    func reset() {
        session += 1
        parseTask?.cancel()
        parseTask = nil
        urlText = ""
        resetSummary()
        stage = .idle
        queueExpanded = true
        selectedFormatID = nil
        primarySubtitleTrackID = nil
        importedSubtitleFileURL = nil
        chineseMode = .off
        candidates = []
        chosenCandidate = nil
        retryAction = nil
        failedNeedsLogin = nil
        failedNeedsDependency = false
        enqueueNotice = nil
    }

    private func dependenciesReady(for mode: ChineseSubtitleMode) -> Bool {
        guard mode.requiresBurner else { return true }
        let missing = DependencySetup.missing
        guard missing.contains(where: { $0.id == "ffmpeg" }) else { return true }
        settingsNotice = CoreL10n.t(L.Settings.installFfmpegFullNotice)
        showDependencySetup = true
        return false
    }

    func translationReadinessForCurrentSettings() -> TranslationReadiness {
        translationReadinessForCurrentSettings(context: currentTranslationContext())
    }

    private func translationReadinessForCurrentSettings(context: TranslationContext) -> TranslationReadiness {
        if runtimeTranslationReadinessContext == context,
           let runtimeTranslationReadiness {
            return runtimeTranslationReadiness
        }
        return settings.translationReadiness(context: context)
    }

    func translationReadinessMessageForCurrentSettings() -> String {
        translationReadinessMessageForCurrentSettings(context: currentTranslationContext())
    }

    private func translationReadinessMessageForCurrentSettings(context: TranslationContext) -> String {
        let readiness = translationReadinessForCurrentSettings(context: context)
        return translationReadinessMessage(for: readiness)
    }

    private func translationReadinessMessage(for readiness: TranslationReadiness) -> String {
        guard !readiness.isReady else { return CoreL10n.t(L.Settings.statusReady) }
        let message = readiness.issues.map(\.message).joined(separator: " ")
        return message.isEmpty ? CoreL10n.t(L.Settings.readinessUnavailable) : message
    }

    private func blockIfTranslationNotReady(for mode: ChineseSubtitleMode) -> Bool {
        guard mode.requiresTranslation else { return true }
        let readiness = translationReadinessForCurrentSettings()
        guard readiness.isReady else {
            settingsNotice = translationReadinessMessageForCurrentSettings()
            openSettings(paneID: "aiServices")
            return false
        }
        return true
    }

    private func blockIfTranslationNotReady(
        for mode: ChineseSubtitleMode,
        settings: AppSettings,
        context: TranslationContext
    ) async -> Bool {
        guard mode.requiresTranslation else { return true }
        let readiness = await settings.translationRuntimeReadiness(
            context: context,
            evaluator: runtimeReadinessEvaluator
        )
        guard readiness.isReady else {
            settingsNotice = translationReadinessMessage(for: readiness)
            openSettings(paneID: "aiServices")
            return false
        }
        return true
    }

    func refreshTranslationRuntimeReadiness() {
        runtimeReadinessTask?.cancel()
        let settings = settings
        let context = currentTranslationContext()
        runtimeTranslationReadinessContext = context
        runtimeTranslationReadiness = settings.translationReadiness(context: context)
        runtimeReadinessTask = Task { [runtimeReadinessEvaluator] in
            let readiness = await settings.translationRuntimeReadiness(
                context: context,
                evaluator: runtimeReadinessEvaluator
            )
            guard !Task.isCancelled else { return }
            guard self.runtimeTranslationReadinessContext == context else { return }
            self.runtimeTranslationReadiness = readiness
        }
    }

    func refreshSummaryRuntimeReadiness() {
        summaryReadinessTask?.cancel()
        let settings = settings.applyingTranslationConfig(settings.effectiveSummaryConfig)
        let context = summaryReadinessContext()
        runtimeSummaryReadinessContext = context
        runtimeSummaryReadiness = settings.translationReadiness(context: context)
        summaryReadinessTask = Task { [runtimeReadinessEvaluator] in
            let readiness = await settings.translationRuntimeReadiness(
                context: context,
                evaluator: runtimeReadinessEvaluator
            )
            guard !Task.isCancelled else { return }
            guard self.runtimeSummaryReadinessContext == context else { return }
            self.runtimeSummaryReadiness = readiness
        }
    }

    private func currentTranslationContext() -> TranslationContext {
        let sourceLanguage: String?
        if case .ready(let info) = stage {
            sourceLanguage = translationSourceSubtitle(in: info)?.languageCode
        } else {
            sourceLanguage = nil
        }
        return settings.makeTranslationContext(sourceLanguage: sourceLanguage)
    }

    private func summaryReadinessContext() -> TranslationContext {
        settings.makeTranslationContext(sourceLanguage: nil)
    }

    // MARK: - AI 内容总结

    /// 总结当前不可用的原因；nil 表示可用。供 Ready 页禁用按钮并给提示。
    var summaryUnavailableReason: String? {
        let config = settings.effectiveSummaryConfig
        if !config.engine.canGenerateText {
            return CoreL10n.t(L.Summary.unavailableEngine)
        }
        let summarySettings = settings.applyingTranslationConfig(config)
        if !summarySettings.isTranslationConfigured {
            return CoreL10n.t(L.Summary.notConfigured)
        }
        let context = summaryReadinessContext()
        let readiness = runtimeSummaryReadinessContext == context
            ? (runtimeSummaryReadiness ?? summarySettings.translationReadiness(context: context))
            : summarySettings.translationReadiness(context: context)
        if !readiness.isReady {
            return translationReadinessMessage(for: readiness)
        }
        return nil
    }

    var isSummaryAvailable: Bool { summaryUnavailableReason == nil }

    func resetSummary() {
        summaryTask?.cancel()
        summaryTask = nil
        summaryState = .idle
    }

    /// 对当前 Ready 的视频做 AI 总结：优先现拉字幕文本，拿不到回退视频简介。
    func summarizeCurrentVideo() {
        guard case .ready(let info) = stage else { return }
        hydrateCredentials()
        if let reason = summaryUnavailableReason {
            summaryState = .failed(reason)
            return
        }
        summaryTask?.cancel()
        summaryState = .running
        let settings = settings
        let config = settings.effectiveSummaryConfig
        let preferredLangs = info.subtitles.map(\.languageCode)
        summaryTask = Task { [engine] in
            do {
                // 优先字幕文本；最佳努力，失败/无字幕回退简介。
                let subtitleText = try? await engine.fetchSubtitleText(
                    url: info.sourceURL,
                    preferredLanguages: preferredLangs,
                    control: nil
                )
                if Task.isCancelled { return }
                let source = (subtitleText?.isEmpty == false) ? subtitleText : info.description
                let summary = try await summarizeVideo(
                    title: info.title,
                    uploader: info.uploader,
                    durationText: info.durationText,
                    source: source,
                    config: config,
                    settings: settings
                )
                if Task.isCancelled { return }
                self.summaryState = .done(summary)
            } catch is CancellationError {
                return
            } catch let MoongateError.translateFailed(message) {
                if Task.isCancelled { return }
                self.summaryState = .failed(message)
            } catch MoongateError.cancelled {
                return
            } catch {
                if Task.isCancelled { return }
                self.summaryState = .failed(error.localizedDescription)
            }
        }
    }

    private func showOnboardingIfNeeded() {
        guard !settings.onboardingCompleted else { return }
        showOnboarding = true
    }

    /// Reopens onboarding as a draft-only flow. Existing settings, credentials,
    /// login state, and the durable video library are deliberately untouched.
    func restartOnboarding() {
        settingsNotice = nil
        showOnboarding = true
    }

    /// Adopts a runtime that is already installed locally. This is intentionally
    /// not an installer: without a published, verified project asset the app
    /// must not pretend it can download or repair the runtime.
    @discardableResult
    func adoptExistingLocalASRRuntime() -> Bool {
        // This action writes settings. The launch-time value deliberately
        // omits Keychain credentials, so hydrate before copying it into a
        // draft or save() would interpret empty tokens as removals.
        hydrateCredentials()
        let runtimeDirectory = AppSettings.supportDirectory
            .appendingPathComponent("asr", isDirectory: true)
            .appendingPathComponent("runtime", isDirectory: true)
        var searchURLs = [
            runtimeDirectory,
            runtimeDirectory.appendingPathComponent("bin", isDirectory: true),
        ]
        let configuredPath = settings.localASRRuntimePath
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !configuredPath.isEmpty {
            searchURLs.append(URL(fileURLWithPath: configuredPath))
        }
        if let bundledRuntimeURL = Bundle.main.resourceURL?
            .appendingPathComponent("asr", isDirectory: true)
            .appendingPathComponent("runtime", isDirectory: true) {
            searchURLs.append(bundledRuntimeURL)
            searchURLs.append(bundledRuntimeURL.appendingPathComponent("bin", isDirectory: true))
        }
        // Finder-launched apps often receive a minimal PATH. This explicit
        // capability check can still adopt a verified Homebrew installation
        // without changing the generic locator's deterministic behavior.
        searchURLs.append(URL(fileURLWithPath: "/opt/homebrew/bin/whisper-cli"))
        searchURLs.append(URL(fileURLWithPath: "/usr/local/bin/whisper-cli"))
        guard let runtime = ASRRuntimeLocator(extraSearchURLs: searchURLs).locate() else {
            settingsNotice = nil
            return false
        }

        var draft = settings
        draft.localASRRuntimePath = runtime.executableURL.path
        do {
            try draft.save()
            settings = draft
            settingsNotice = nil
            return true
        } catch {
            settingsNotice = CoreL10n.t(L.Settings.saveFailed, error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func acknowledgeOnboardingKeepingCurrentDefaults() -> Bool {
        // This is the welcome-page exit: it must preserve every existing
        // download, subtitle, service, and credential preference.
        hydrateCredentials()
        let draft = Self.acknowledgingOnboarding(settings)
        do {
            try draft.save()
            settings = draft
            settingsNotice = nil
            showOnboarding = false
            return true
        } catch {
            settingsNotice = CoreL10n.t(L.Settings.saveFailed, error.localizedDescription)
            return false
        }
    }

    /// Persists only the choices a person explicitly made in onboarding's
    /// optional defaults page. Service endpoints and credentials stay intact.
    @discardableResult
    func commitOnboardingDefaultEdits(
        appLanguage: AppLanguage,
        subtitleMode: ChineseSubtitleMode,
        translationTargetLanguage: String?,
        useSystemTranslation: Bool?
    ) -> Bool {
        hydrateCredentials()
        let draft = Self.applyingOnboardingDefaults(
            to: settings,
            appLanguage: appLanguage,
            subtitleMode: subtitleMode,
            translationTargetLanguage: translationTargetLanguage,
            useSystemTranslation: useSystemTranslation
        )
        do {
            try draft.save()
            settings = draft
            settingsNotice = nil
            showOnboarding = false
            return true
        } catch {
            settingsNotice = CoreL10n.t(L.Settings.saveFailed, error.localizedDescription)
            return false
        }
    }

    /// The two download-first onboarding exits deliberately share small,
    /// side-effect-free settings transitions. This keeps the persisted action
    /// easy to verify with isolated settings/credential stores and prevents a
    /// future UI branch from silently rewriting unrelated service or ASR data.
    static func acknowledgingOnboarding(_ settings: AppSettings) -> AppSettings {
        var draft = settings
        draft.onboardingCompleted = true
        return draft
    }

    static func applyingOnboardingDefaults(
        to settings: AppSettings,
        appLanguage: AppLanguage,
        subtitleMode: ChineseSubtitleMode,
        translationTargetLanguage: String?,
        useSystemTranslation: Bool?
    ) -> AppSettings {
        var draft = acknowledgingOnboarding(settings)
        draft.appLanguage = appLanguage.rawValue
        draft.lastSubtitleMode = subtitleMode.rawValue
        if let translationTargetLanguage {
            draft.translationTargetLanguage = translationTargetLanguage
        }
        if let useSystemTranslation {
            if useSystemTranslation {
                draft.translationEngine = .appleTranslationLowLatency
                draft.translationFollowsDefault = false
            } else {
                draft.translationFollowsDefault = true
            }
        }
        return draft
    }

    // MARK: - 设置与站点登录

    /// 保存设置；失败时把原因写进 settingsNotice。
    @discardableResult
    func saveSettings() -> Bool {
        do {
            try settings.save()
            settingsNotice = nil
            return true
        } catch {
            settingsNotice = CoreL10n.t(L.Settings.saveFailed, error.localizedDescription)
            return false
        }
    }

    /// 设置窗里点「登录 ××」：先保存设置再收起设置窗。保存失败则保持设置窗打开、不进入登录
    /// （settingsNotice 已写明原因），避免静默丢掉用户刚改的草稿（SETTINGS-001）。
    func requestLogin(site: String) {
        guard saveSettings() else { return }
        pendingLoginSite = site
        showSettings = false
    }

    /// 设置窗里点「配置依赖」：先保存设置再收起设置窗。保存失败则保持设置窗打开、不进入依赖流程。
    /// 与 requestLogin 一致先 save：设置窗 onDisappear 会用磁盘值回滚 model.settings，
    /// 不先落盘就会丢掉用户在设置里改了但还没点「完成」的草稿。
    func requestDependencySetup() {
        guard saveSettings() else { return }
        pendingDependencySetup = true
        showSettings = false
    }

    /// 设置 sheet 的 onDismiss 调用：若有待弹出的二级流程则继续弹出。
    func consumePendingSettingsActions() {
        consumePendingLogin()
        consumePendingDependencySetup()
    }

    private func consumePendingLogin() {
        guard let site = pendingLoginSite else { return }
        pendingLoginSite = nil
        loginStartURL = nil
        loginSite = site
    }

    private func consumePendingDependencySetup() {
        guard pendingDependencySetup else { return }
        pendingDependencySetup = false
        showDependencySetup = true
    }

    func closeDependencySetup() {
        showDependencySetup = false
    }

    func completeDependencySetup() {
        showDependencySetup = false
        settingsNotice = nil
        let shouldRetry = failedNeedsDependency
        failedNeedsDependency = false
        if shouldRetry {
            retry()
        }
    }

    /// failed 页点「打开网页并保存验证信息」。
    func openLoginForFailure() {
        guard let site = failedNeedsLogin else { return }
        loginStartURL = failedLoginURL
        loginSite = site
    }

    /// 队列中某个登录类失败项点「登录」：打开对应站点登录窗，登录成功后自动重试该站点全部失败项。
    func openLoginForQueueItem(site: String, loginURL: URL?) {
        pendingQueueLoginSite = site
        loginStartURL = loginURL
        loginSite = site
    }

    /// Ready 页字幕提示点「登录」：打开该站点登录窗，登录成功后清缓存并重新解析以拿到平台字幕。
    func openLoginForPlatformSubtitleHint(_ hint: PlatformSubtitleHint) {
        guard case .ready(let info) = stage else { return }
        pendingReadyReanalyzeURL = info.sourceURL
        loginStartURL = URL(string: info.sourceURL)
        loginSite = hint.loginSite
    }

    /// 登录窗导出 cookies 成功后调用：关窗并自动重试上次失败的操作。
    func loginCompleted() {
        loginSite = nil
        loginStartURL = nil
        // 队列登录类失败：重试该站点全部失败项（下载阶段的登录失败走这条路）。
        if let site = pendingQueueLoginSite {
            pendingQueueLoginSite = nil
            queue.retryFailedNeedingLogin(site: site)
        }
        // Ready 页字幕提示登录：清缓存 + 重新解析，拿到登录后才可见的平台字幕。
        if let url = pendingReadyReanalyzeURL {
            pendingReadyReanalyzeURL = nil
            reanalyzeCurrentReady(url: url)
        }
        if case .failed = stage, let action = retryAction {
            action()
        }
    }

    /// 登录后重新解析当前 Ready 页视频：先失效缓存，再重跑 analyze 刷新字幕列表。
    private func reanalyzeCurrentReady(url: String) {
        guard case .ready = stage else { return }
        session += 1
        let token = session
        stage = .analyzing
        parseTask?.cancel()
        parseTask = Task {
            self.engine.invalidateInfoCache(for: url)
            do {
                let info = try await self.engine.analyze(url: url)
                guard token == self.session else { return }
                self.selectedFormatID = info.formats.first?.id
                self.restoreDownloadOptions(for: info)
                self.resetSummary()
                self.stage = .ready(info)
            } catch {
                guard token == self.session else { return }
                self.fail(error) { [weak self] in self?.reanalyzeCurrentReady(url: url) }
            }
        }
    }

    func cancelLogin() {
        loginSite = nil
        loginStartURL = nil
        pendingQueueLoginSite = nil
        pendingReadyReanalyzeURL = nil
    }

    // MARK: - 私有

    private func fail(_ error: Error, retry: @escaping @MainActor () -> Void) {
        retryAction = retry
        if case MoongateError.loginRequired(let site) = error {
            failedNeedsLogin = site
            failedLoginURL = nil
        } else if case MoongateError.siteCookieRequired(let site, let url, _) = error {
            failedNeedsLogin = site
            failedLoginURL = URL(string: url)
        } else {
            failedNeedsLogin = nil
            failedLoginURL = nil
            failedNeedsDependency = false
        }
        if case MoongateError.binaryNotFound = error {
            failedNeedsDependency = true
        } else {
            failedNeedsDependency = false
        }
        stage = .failed(error.localizedDescription)
    }
}
