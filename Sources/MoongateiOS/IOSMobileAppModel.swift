import Combine
import Foundation
import MoongateMobileCore

public enum IOSMobileTab: String, CaseIterable, Identifiable, Sendable {
    case add
    case queue
    case library
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .add: return "添加"
        case .queue: return "队列"
        case .library: return "资料库"
        case .settings: return "设置"
        }
    }

    public var systemImage: String {
        switch self {
        case .add: return "plus.circle"
        case .queue: return "list.bullet.rectangle"
        case .library: return "rectangle.stack"
        case .settings: return "gearshape"
        }
    }
}

public enum IOSAppleIntelligenceRoute: String, CaseIterable, Identifiable, Codable, Sendable, Equatable {
    case onDevice
    case privateCloud
    case privateCloudPro

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .onDevice: return "本地 Apple Intelligence"
        case .privateCloud: return "云端 Apple Intelligence"
        case .privateCloudPro: return "云端 Pro Apple Intelligence"
        }
    }

    public var shortTitle: String {
        switch self {
        case .onDevice: return "本地"
        case .privateCloud: return "云端"
        case .privateCloudPro: return "云端 Pro"
        }
    }

    public var translationEngine: TranslationEngine {
        switch self {
        case .onDevice:
            return .appleFoundationOnDevice
        case .privateCloud:
            return .appleFoundationPCC
        case .privateCloudPro:
            return .appleFoundationCloudPro
        }
    }
}

public struct IOSAppleIntelligenceStatus: Codable, Sendable, Equatable, Identifiable {
    public var route: IOSAppleIntelligenceRoute
    public var readiness: TranslationReadiness
    public var detail: String
    public var isRuntimeVerified: Bool
    public var supportsIOS26RuntimeChecks: Bool
    public var supportsIOS27RuntimeChecks: Bool

    public var id: String { route.id }
    public var isAvailable: Bool { readiness.isReady && isRuntimeVerified }

    public var availabilityLabel: String {
        if isAvailable {
            return "可用"
        }
        if isRuntimeVerified {
            return "暂不可用"
        }
        return "需检测"
    }

    public init(
        route: IOSAppleIntelligenceRoute,
        readiness: TranslationReadiness,
        detail: String,
        isRuntimeVerified: Bool = false,
        supportsIOS26RuntimeChecks: Bool = true,
        supportsIOS27RuntimeChecks: Bool = false
    ) {
        self.route = route
        self.readiness = readiness
        self.detail = detail
        self.isRuntimeVerified = isRuntimeVerified
        self.supportsIOS26RuntimeChecks = supportsIOS26RuntimeChecks
        self.supportsIOS27RuntimeChecks = supportsIOS27RuntimeChecks
    }
}

public enum IOSCloudTranslationConnectionState: String, Codable, Sendable, Equatable {
    case idle
    case testing
    case succeeded
    case failed
}

public struct IOSCloudTranslationConnectionStatus: Codable, Sendable, Equatable {
    public var state: IOSCloudTranslationConnectionState
    public var message: String

    public init(
        state: IOSCloudTranslationConnectionState = .idle,
        message: String = "未测试连接。"
    ) {
        self.state = state
        self.message = message
    }
}

@MainActor
public final class IOSMobileAppModel: ObservableObject {
    @Published public var selectedTab: IOSMobileTab
    @Published public var addSession: MobileAddSessionSnapshot
    @Published public var queue: [MobileTaskSnapshot]
    @Published public var library: [MobileLibraryItem]
    @Published public var translationConfiguration: MobileTranslationConfiguration
    @Published public var appleIntelligenceStatuses: [IOSAppleIntelligenceStatus]
    @Published public var selectedAppleIntelligenceRoute: IOSAppleIntelligenceRoute
    @Published public var cloudTranslationConnectionStatus: IOSCloudTranslationConnectionStatus
    @Published public var selectedAddExportProfile: MobileExportProfile
    @Published public var selectedAddFormatID: String?
    @Published public var selectedAddSubtitleIDs: [String]
    @Published public var lastQueueActionStatus: String?
    @Published public var lastLibraryActionStatus: String?
    @Published public var lastLibraryActionOutcome: MobileLibraryActionOutcome?
    @Published public var pendingLibraryActionCommand: IOSLibraryActionCommand?

    private let credentialStore: any SecureCredentialStore
    private let runtimeReadinessEvaluator: any TranslationRuntimeReadinessEvaluating
    private let translationConnectionTransport: any MobileTranslationTransport
    private let mobileParser: any MobileParser
    private let downloadEngine: (any MobileDownloadEngine)?
    private let backgroundDownloadStarter: (any IOSBackgroundDownloadStarting)?
    let backgroundURLSessionDownloadDelegateForTesting: IOSBackgroundURLSessionDownloadDelegate?
    private let translationProvider: (any MobileTranslationProvider)?
    private let subtitleProcessor: (any SubtitleProcessor)?
    private let renderExporter: (any RenderExporter)?
    private let continuedProcessingSubmitter: (any IOSContinuedProcessingTaskSubmitting)?
    private let continuedProcessingScheduler: IOSContinuedProcessingRenderScheduler
    private let renderRuntimeCapabilities: IOSRenderRuntimeCapabilities
    private let importedFileAccessor: any IOSImportedFileAccessing
    private let importStorageChecker: any IOSImportStorageChecking
    private let storageDirectoryURL: URL?
    private let taskRepository: (any TaskRepository)?
    private let backgroundTransferRegistry: BackgroundTransferRegistry?
    private let sourceReferenceStore: IOSSourceReferenceStore?
    private var sourceURLByTaskID: [String: String] = [:]
    private var translationResultByTaskID: [String: MobileTranslationResult] = [:]
    private var preExportTaskByID: [String: MobileTaskSnapshot] = [:]
    private var activeQueueTasksByID: [String: ActiveQueueTask] = [:]
    private var pendingCredentialCleanupTasks: [Task<Void, Never>] = []

    private static let importedFileSourcePlaceholder = "imported-file://local"

    public let tabs: [IOSMobileTab] = IOSMobileTab.allCases

    public var hasConfiguredTranslationCredential: Bool {
        translationConfiguration.credential != nil
    }

    public var activeQueueCount: Int {
        queue.filter { task in
            switch task.state {
            case .waiting, .analyzing, .ready, .downloading, .translating, .exporting, .needsForegroundToContinue:
                return true
            case .completed, .failed, .cancelled:
                return false
            }
        }.count
    }

    public var foregroundRequiredTasks: [MobileTaskSnapshot] {
        queue.filter { task in
            guard Self.isActiveQueueState(task.state) else {
                return false
            }
            return task.state == .needsForegroundToContinue || task.backgroundPolicy.requiresForeground
        }
    }

    public init(
        selectedTab: IOSMobileTab = .add,
        addSession: MobileAddSessionSnapshot? = nil,
        queue: [MobileTaskSnapshot]? = nil,
        library: [MobileLibraryItem]? = nil,
        translationConfiguration: MobileTranslationConfiguration? = nil,
        appleIntelligenceStatuses: [IOSAppleIntelligenceStatus]? = nil,
        selectedAppleIntelligenceRoute: IOSAppleIntelligenceRoute = .onDevice,
        cloudTranslationConnectionStatus: IOSCloudTranslationConnectionStatus = IOSCloudTranslationConnectionStatus(),
        selectedAddExportProfile: MobileExportProfile = MobileExportProfile(subtitleMode: .translatedSubtitleFile),
        selectedAddFormatID: String? = nil,
        selectedAddSubtitleIDs: [String] = [],
        lastQueueActionStatus: String? = nil,
        lastLibraryActionStatus: String? = nil,
        lastLibraryActionOutcome: MobileLibraryActionOutcome? = nil,
        pendingLibraryActionCommand: IOSLibraryActionCommand? = nil,
        credentialStore: any SecureCredentialStore = IOSKeychainCredentialStore(),
        runtimeReadinessEvaluator: any TranslationRuntimeReadinessEvaluating = IOSRuntimeReadinessEvaluator(),
        translationConnectionTransport: any MobileTranslationTransport = URLSessionMobileTranslationTransport(),
        mobileParser: any MobileParser = IOSDirectMediaMobileParser(),
        downloadEngine: (any MobileDownloadEngine)? = nil,
        backgroundDownloadStarter: (any IOSBackgroundDownloadStarting)? = nil,
        backgroundURLSessionDownloadDelegateForTesting: IOSBackgroundURLSessionDownloadDelegate? = nil,
        translationProvider: (any MobileTranslationProvider)? = nil,
        subtitleProcessor: (any SubtitleProcessor)? = nil,
        renderExporter: (any RenderExporter)? = nil,
        continuedProcessingSubmitter: (any IOSContinuedProcessingTaskSubmitting)? = nil,
        continuedProcessingScheduler: IOSContinuedProcessingRenderScheduler = IOSContinuedProcessingRenderScheduler(bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.local.videodownloader.ios"),
        renderRuntimeCapabilities: IOSRenderRuntimeCapabilities = IOSRenderRuntimeCapabilities(),
        importedFileAccessor: any IOSImportedFileAccessing = IOSImportedFileAccessor(),
        importStorageChecker: any IOSImportStorageChecking = IOSImportStorageChecker(),
        storageDirectoryURL: URL? = nil,
        taskRepository: (any TaskRepository)? = nil,
        backgroundTransferRegistry: BackgroundTransferRegistry? = nil,
        sourceReferenceStore: IOSSourceReferenceStore? = nil
    ) {
        self.selectedTab = selectedTab
        self.addSession = addSession ?? IOSMobilePreviewData.addSession
        self.queue = queue ?? IOSMobilePreviewData.queue
        self.library = library ?? IOSMobilePreviewData.library
        self.translationConfiguration = translationConfiguration ?? IOSMobilePreviewData.translationConfiguration
        self.appleIntelligenceStatuses = (appleIntelligenceStatuses ?? IOSMobilePreviewData.appleIntelligenceStatuses)
            .map(Self.markNeedsRuntimeRefresh)
        self.selectedAppleIntelligenceRoute = selectedAppleIntelligenceRoute
        self.cloudTranslationConnectionStatus = cloudTranslationConnectionStatus
        self.selectedAddExportProfile = selectedAddExportProfile
        self.selectedAddFormatID = selectedAddFormatID
        self.selectedAddSubtitleIDs = selectedAddSubtitleIDs
        self.lastQueueActionStatus = lastQueueActionStatus
        self.lastLibraryActionStatus = lastLibraryActionStatus
        self.lastLibraryActionOutcome = lastLibraryActionOutcome
        self.pendingLibraryActionCommand = pendingLibraryActionCommand
        self.credentialStore = credentialStore
        self.runtimeReadinessEvaluator = runtimeReadinessEvaluator
        self.translationConnectionTransport = translationConnectionTransport
        self.mobileParser = mobileParser
        self.downloadEngine = downloadEngine
        self.backgroundDownloadStarter = backgroundDownloadStarter
        self.backgroundURLSessionDownloadDelegateForTesting = backgroundURLSessionDownloadDelegateForTesting
        self.translationProvider = translationProvider
        self.subtitleProcessor = subtitleProcessor
        self.renderExporter = renderExporter
        self.continuedProcessingSubmitter = continuedProcessingSubmitter
        self.continuedProcessingScheduler = continuedProcessingScheduler
        self.renderRuntimeCapabilities = renderRuntimeCapabilities
        self.importedFileAccessor = importedFileAccessor
        self.importStorageChecker = importStorageChecker
        self.storageDirectoryURL = storageDirectoryURL
        self.taskRepository = taskRepository
        self.backgroundTransferRegistry = backgroundTransferRegistry
        self.sourceReferenceStore = sourceReferenceStore
    }

    public func updateCloudTranslationEngine(_ engine: TranslationEngine) {
        guard engine == .openAICompatible || engine == .anthropicCompatible else {
            translationConfiguration.readiness = TranslationReadiness(issues: [
                TranslationReadinessIssue(kind: .needsConfiguration, message: "云翻译只支持 OpenAI-compatible 或 Anthropic-compatible 协议。")
            ])
            return
        }
        let previousEngine = translationConfiguration.engine
        translationConfiguration.engine = engine
        clearCloudCredentialIfChanged(previousEngine != engine)
        translationConfiguration.readiness = Self.readiness(for: translationConfiguration)
        persistTranslationConfiguration()
        cloudTranslationConnectionStatus = IOSCloudTranslationConnectionStatus()
    }

    public func updateCloudTranslationEndpoint(_ value: String) {
        let previousBaseURL = normalizedBaseURL(translationConfiguration.baseURL)
        translationConfiguration.baseURL = Self.trimmedOptional(value)
        clearCloudCredentialIfChanged(previousBaseURL != normalizedBaseURL(translationConfiguration.baseURL))
        translationConfiguration.readiness = Self.readiness(for: translationConfiguration)
        persistTranslationConfiguration()
        cloudTranslationConnectionStatus = IOSCloudTranslationConnectionStatus()
    }

    public func updateCloudTranslationModel(_ value: String) {
        translationConfiguration.model = Self.trimmedOptional(value)
        translationConfiguration.readiness = Self.readiness(for: translationConfiguration)
        persistTranslationConfiguration()
        cloudTranslationConnectionStatus = IOSCloudTranslationConnectionStatus()
    }

    public func saveAPIKeyDraft(_ secret: String, service: String? = nil) async {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingReference = translationConfiguration.credential
        guard Self.isAPICompatibleEngine(translationConfiguration.engine) else {
            translationConfiguration.credential = nil
            translationConfiguration.readiness = Self.nonAPICompatibleReadiness(for: translationConfiguration.engine)
            persistTranslationConfiguration()
            cloudTranslationConnectionStatus = IOSCloudTranslationConnectionStatus(
                state: .failed,
                message: Self.unsupportedCloudConnectionMessage(for: translationConfiguration.engine)
            )
            return
        }
        let reference = SecureCredentialReference(
            service: service ?? cloudCredentialService(),
            account: "default",
            displayName: "API key"
        )

        guard !trimmed.isEmpty else {
            await deleteAPIKey(existingReference: existingReference)
            return
        }

        do {
            let savedReference = try await credentialStore.saveCredential(trimmed, for: reference)
            translationConfiguration.credential = savedReference
            translationConfiguration.readiness = Self.readiness(for: translationConfiguration)
            persistTranslationConfiguration()
        } catch {
            translationConfiguration.credential = nil
            translationConfiguration.readiness = TranslationReadiness(issues: [
                TranslationReadinessIssue(kind: .needsConfiguration, message: "API key 未保存成功，请重试。")
            ])
            persistTranslationConfiguration()
        }
    }

    public func deleteAPIKey() async {
        guard Self.isAPICompatibleEngine(translationConfiguration.engine) else {
            translationConfiguration.credential = nil
            translationConfiguration.readiness = Self.nonAPICompatibleReadiness(for: translationConfiguration.engine)
            persistTranslationConfiguration()
            cloudTranslationConnectionStatus = IOSCloudTranslationConnectionStatus()
            return
        }
        await deleteAPIKey(existingReference: translationConfiguration.credential)
    }

    public func waitForPendingCredentialCleanup() async {
        let tasks = pendingCredentialCleanupTasks
        pendingCredentialCleanupTasks.removeAll()
        for task in tasks {
            await task.value
        }
    }

    public func refreshCloudTranslationCredentialReadiness() async {
        guard translationConfiguration.engine.requiresCloudConfiguration else {
            return
        }

        guard Self.hasCompleteCloudTranslationMetadata(translationConfiguration),
              let credential = translationConfiguration.credential else {
            translationConfiguration.readiness = Self.readiness(for: translationConfiguration)
            return
        }

        do {
            let secret = try await credentialStore.credential(for: credential)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            translationConfiguration.readiness = secret?.isEmpty == false
                ? .ready
                : TranslationReadiness(issues: [
                    TranslationReadinessIssue(kind: .needsConfiguration, message: "需要重新保存 API key。")
                ])
        } catch {
            translationConfiguration.readiness = TranslationReadiness(issues: [
                TranslationReadinessIssue(kind: .needsConfiguration, message: "需要重新保存 API key。")
            ])
        }
    }

    public func testCloudTranslationConnection() async {
        cloudTranslationConnectionStatus = IOSCloudTranslationConnectionStatus(
            state: .testing,
            message: "正在测试连接。"
        )
        guard Self.isAPICompatibleEngine(translationConfiguration.engine) else {
            translationConfiguration.credential = nil
            translationConfiguration.readiness = Self.nonAPICompatibleReadiness(for: translationConfiguration.engine)
            cloudTranslationConnectionStatus = IOSCloudTranslationConnectionStatus(
                state: .failed,
                message: Self.unsupportedCloudConnectionMessage(for: translationConfiguration.engine)
            )
            return
        }
        let provider = APICompatibleMobileTranslationProvider(
            configuration: translationConfiguration,
            credentialStore: credentialStore,
            transport: translationConnectionTransport
        )
        do {
            _ = try await provider.translate(MobileTranslationRequest(
                segments: [
                    MobileTranslationSegment(
                        id: "connection-test",
                        startTime: "00:00:00,000",
                        endTime: "00:00:01,000",
                        text: "connection-test"
                    )
                ],
                context: TranslationContext(sourceLanguage: "en", targetLanguage: "zh-Hans")
            ))
            cloudTranslationConnectionStatus = IOSCloudTranslationConnectionStatus(
                state: .succeeded,
                message: "连接成功。"
            )
        } catch let error as MobileTranslationProviderError {
            cloudTranslationConnectionStatus = IOSCloudTranslationConnectionStatus(
                state: .failed,
                message: Self.connectionFailureMessage(for: error)
            )
        } catch {
            cloudTranslationConnectionStatus = IOSCloudTranslationConnectionStatus(
                state: .failed,
                message: "连接失败，请检查网络、模型或网关配置。"
            )
        }
    }

    private static func readiness(for configuration: MobileTranslationConfiguration) -> TranslationReadiness {
        guard configuration.engine.requiresCloudConfiguration else {
            return MobileTranslationConfiguration.conservativeReadiness(for: configuration.engine)
        }

        return hasCompleteCloudTranslationMetadata(configuration)
            ? .ready
            : TranslationReadiness(issues: [TranslationReadinessIssue(kind: .needsConfiguration)])
    }

    private static func persistedReadiness(for configuration: MobileTranslationConfiguration) -> TranslationReadiness {
        guard configuration.engine.requiresCloudConfiguration else {
            return MobileTranslationConfiguration.conservativeReadiness(for: configuration.engine)
        }

        return hasCompleteCloudTranslationMetadata(configuration)
            ? TranslationReadiness(issues: [
                TranslationReadinessIssue(kind: .needsConfiguration, message: "需要验证已保存的 API key。")
            ])
            : TranslationReadiness(issues: [TranslationReadinessIssue(kind: .needsConfiguration)])
    }

    private static func hasCompleteCloudTranslationMetadata(_ configuration: MobileTranslationConfiguration) -> Bool {
        let hasEndpoint = configuration.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasModel = configuration.model?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasCredential = configuration.credential != nil
        return hasEndpoint && hasModel && hasCredential
    }

    private static func trimmedOptional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func clearCloudCredentialIfChanged(_ didChangeScope: Bool) {
        guard didChangeScope else { return }
        if let existingReference = translationConfiguration.credential {
            scheduleCredentialCleanup(existingReference)
        }
        translationConfiguration.credential = nil
    }

    private func deleteAPIKey(existingReference: SecureCredentialReference?) async {
        if let existingReference {
            try? await credentialStore.deleteCredential(existingReference)
        }
        translationConfiguration.credential = nil
        translationConfiguration.readiness = TranslationReadiness(issues: [
            TranslationReadinessIssue(kind: .needsConfiguration, message: "需要先保存 API key。")
        ])
        persistTranslationConfiguration()
        cloudTranslationConnectionStatus = IOSCloudTranslationConnectionStatus()
    }

    private func scheduleCredentialCleanup(_ reference: SecureCredentialReference) {
        let credentialStore = credentialStore
        pendingCredentialCleanupTasks.append(Task {
            try? await credentialStore.deleteCredential(reference)
        })
    }

    private func normalizedBaseURL(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    }

    private func cloudCredentialService() -> String {
        let host = translationConfiguration.baseURL
            .flatMap { URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines))?.host }
            .map(Self.safeCredentialScopeComponent) ?? "custom"
        return "translation.\(translationConfiguration.engine.rawValue).\(host)"
    }

    private func persistTranslationConfiguration() {
        guard let storageDirectoryURL,
              let store = try? IOSTranslationConfigurationStore(directoryURL: storageDirectoryURL) else {
            return
        }
        do {
            try store.saveConfiguration(translationConfiguration)
        } catch {
            cloudTranslationConnectionStatus = IOSCloudTranslationConnectionStatus(
                state: .failed,
                message: "保存翻译配置失败。"
            )
        }
    }

    private static func isAPICompatibleEngine(_ engine: TranslationEngine) -> Bool {
        engine == .openAICompatible || engine == .anthropicCompatible
    }

    private static func nonAPICompatibleReadiness(for engine: TranslationEngine) -> TranslationReadiness {
        MobileTranslationConfiguration.conservativeReadiness(for: engine)
    }

    private static func safeCredentialScopeComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        let scalars = value.lowercased().unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let sanitized = String(scalars)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        return sanitized.isEmpty ? "custom" : sanitized
    }

    private static func connectionFailureMessage(for error: MobileTranslationProviderError) -> String {
        switch error {
        case .invalidConfiguration, .missingCredential:
            return "连接失败：需要完整填写协议、服务地址、模型并保存 API key。"
        case .unsupportedEngine:
            return "连接失败：当前引擎不支持 API 兼容连接测试。"
        case .requestFailed(let statusCode):
            return "连接失败：HTTP \(statusCode)。"
        case .invalidResponse:
            return "连接失败：服务返回格式不符合预期。"
        }
    }

    private static func unsupportedCloudConnectionMessage(for engine: TranslationEngine) -> String {
        switch engine {
        case .appleFoundationCloudPro:
            return "连接失败：Apple Intelligence Cloud Pro（云端 Pro）当前不可用，请改用 OpenAI-compatible 或 Anthropic-compatible。"
        case .appleFoundationPCC:
            return "连接失败：云端 Apple Intelligence 当前不可用，请改用 OpenAI-compatible 或 Anthropic-compatible。"
        case .appleFoundationOnDevice,
             .appleTranslationLowLatency,
             .appleTranslationHighFidelity:
            return "连接失败：当前 Apple 翻译引擎不支持 API 兼容连接测试，请改用 OpenAI-compatible 或 Anthropic-compatible。"
        case .openAICompatible, .anthropicCompatible:
            return "连接失败：需要完整填写协议、服务地址、模型并保存 API key。"
        }
    }

    public func selectAppleIntelligenceRoute(_ route: IOSAppleIntelligenceRoute) {
        selectedAppleIntelligenceRoute = route
        let previousCredential = translationConfiguration.credential
        translationConfiguration.engine = route.translationEngine
        if !Self.isAPICompatibleEngine(route.translationEngine) {
            if let previousCredential {
                scheduleCredentialCleanup(previousCredential)
            }
            translationConfiguration.credential = nil
        }
        if let index = appleIntelligenceStatuses.firstIndex(where: { $0.route == route }) {
            appleIntelligenceStatuses[index] = Self.markNeedsRuntimeRefresh(appleIntelligenceStatuses[index])
            translationConfiguration.readiness = appleIntelligenceStatuses[index].readiness
        } else {
            translationConfiguration.readiness = TranslationReadiness(issues: [
                TranslationReadinessIssue(kind: .needsRuntimeVerification, message: "需要先在本设备检查 Apple Intelligence 能力。")
            ])
        }
        persistTranslationConfiguration()
    }

    public func refreshAppleIntelligenceStatus(for route: IOSAppleIntelligenceRoute) async {
        selectedAppleIntelligenceRoute = route
        translationConfiguration.engine = route.translationEngine

        let fallback: TranslationReadiness
        if let index = appleIntelligenceStatuses.firstIndex(where: { $0.route == route }) {
            fallback = appleIntelligenceStatuses[index].readiness
        } else {
            fallback = TranslationReadiness(issues: [
                TranslationReadinessIssue(kind: .needsRuntimeVerification)
            ])
        }

        let runtimeReadiness = await runtimeReadinessEvaluator.readiness(
            for: TranslationRuntimeReadinessRequest(
                engine: route.translationEngine,
                context: TranslationContext(),
                isCloudConfigurationComplete: !route.translationEngine.requiresCloudConfiguration,
                fallbackReadiness: fallback
            )
        )
        let readiness = Self.translationExecutionReadiness(
            route: route,
            runtimeReadiness: runtimeReadiness
        )

        var status = IOSAppleIntelligenceStatus(
            route: route,
            readiness: readiness,
            detail: detail(for: route, runtimeReadiness: runtimeReadiness, translationReadiness: readiness),
            isRuntimeVerified: true,
            supportsIOS26RuntimeChecks: true,
            supportsIOS27RuntimeChecks: false
        )
        if route == .privateCloudPro {
            status.supportsIOS27RuntimeChecks = false
        }

        if let index = appleIntelligenceStatuses.firstIndex(where: { $0.route == route }) {
            appleIntelligenceStatuses[index] = status
        } else {
            appleIntelligenceStatuses.append(status)
        }
        translationConfiguration.readiness = readiness
        persistTranslationConfiguration()
    }

    private static func markNeedsRuntimeRefresh(
        _ status: IOSAppleIntelligenceStatus
    ) -> IOSAppleIntelligenceStatus {
        var blocked = status
        blocked.isRuntimeVerified = false
        blocked.supportsIOS27RuntimeChecks = false
        guard status.route == .onDevice else {
            return blocked
        }
        let runtimeIssue = TranslationReadinessIssue(
            kind: .needsRuntimeVerification,
            message: "需要在本设备检查 Apple Intelligence 能力。"
        )
        blocked.readiness = TranslationReadiness(
            issues: [runtimeIssue] + status.readiness.issues.filter { $0.kind != .needsRuntimeVerification }
        )
        if !blocked.detail.contains("需要在本设备检查") {
            blocked.detail = "\(status.detail) 需要在本设备检查。"
        }
        return blocked
    }

    private static func translationExecutionReadiness(
        route: IOSAppleIntelligenceRoute,
        runtimeReadiness: TranslationReadiness
    ) -> TranslationReadiness {
        guard runtimeReadiness.isReady else {
            return runtimeReadiness
        }

        switch route {
        case .onDevice:
            return TranslationReadiness(issues: [
                TranslationReadinessIssue(
                    kind: .needsExecutionAdapter,
                    message: "系统模型已通过检测，但此版本暂不能直接用于字幕翻译。"
                )
            ])
        case .privateCloud, .privateCloudPro:
            return TranslationReadiness(issues: [
                TranslationReadinessIssue(kind: .pccUnavailable)
            ])
        }
    }

    private static func isActiveQueueState(_ state: MobileTaskState) -> Bool {
        switch state {
        case .waiting, .analyzing, .ready, .downloading, .translating, .exporting, .needsForegroundToContinue:
            return true
        case .completed, .failed, .cancelled:
            return false
        }
    }

    private func detail(
        for route: IOSAppleIntelligenceRoute,
        runtimeReadiness: TranslationReadiness,
        translationReadiness: TranslationReadiness
    ) -> String {
        if runtimeReadiness.isReady {
            switch route {
            case .onDevice:
                return "设备检测通过；本地模型暂不能用于字幕翻译。"
            case .privateCloud:
                return "云端能力暂不可用。"
            case .privateCloudPro:
                return "云端 Pro 暂不可用。"
            }
        }

        return translationReadiness.issues.map(\.message).joined(separator: " ")
    }

    public func analyzeMockURL(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else {
            resetAddDownloadSelection()
            addSession = MobileAddSessionSnapshot(
                id: UUID().uuidString,
                input: MobileInputSource(kind: .pastedURL, value: trimmed),
                state: .failed,
                error: .unknown
            )
            return
        }

        let title = url.lastPathComponent.isEmpty ? url.host ?? "移动端视频" : url.lastPathComponent
        addSession = Self.readyAddSession(
            input: MobileInputSource(kind: .pastedURL, value: trimmed, displayName: title),
            sourceURL: trimmed,
            title: title
        )
        configureDefaultDownloadSelection()
    }

    public func analyzeURL(_ value: String) async {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = MobileInputSource(kind: .pastedURL, value: trimmed)
        resetAddDownloadSelection()
        addSession = MobileAddSessionSnapshot(
            id: UUID().uuidString,
            input: input,
            state: .analyzing
        )
        do {
            let candidates = try await mobileParser.resolveCandidates(for: input)
            guard let firstSupported = candidates.first(where: \.isSupportedOnMobile) else {
                addSession = MobileAddSessionSnapshot(
                    id: UUID().uuidString,
                    input: input,
                    state: .unsupported,
                    candidates: candidates,
                    selectedCandidateID: candidates.first?.id,
                    error: .unsupportedOnMobile
                )
                return
            }
            let supportedCandidates = candidates.filter(\.isSupportedOnMobile)
            guard supportedCandidates.count == 1 else {
                addSession = MobileAddSessionSnapshot(
                    id: UUID().uuidString,
                    input: input,
                    state: .candidateSelection,
                    candidates: candidates,
                    selectedCandidateID: firstSupported.id
                )
                return
            }
            let info = try await mobileParser.analyze(candidate: firstSupported)
            addSession = MobileAddSessionSnapshot(
                id: UUID().uuidString,
                input: input,
                state: .ready,
                candidates: candidates,
                selectedCandidateID: firstSupported.id,
                videoInfo: info
            )
            configureDefaultDownloadSelection()
        } catch {
            addSession = MobileAddSessionSnapshot(
                id: UUID().uuidString,
                input: input,
                state: .failed,
                error: .unknown
            )
        }
    }

    public func selectAddCandidate(id: String) async {
        guard addSession.state == .candidateSelection,
              let candidate = addSession.candidates.first(where: { $0.id == id && $0.isSupportedOnMobile }) else {
            return
        }

        resetAddDownloadSelection()
        let currentInput = addSession.input
        let currentCandidates = addSession.candidates
        addSession.selectedCandidateID = candidate.id
        do {
            let info = try await mobileParser.analyze(candidate: candidate)
            addSession = MobileAddSessionSnapshot(
                id: UUID().uuidString,
                input: currentInput,
                state: .ready,
                candidates: currentCandidates,
                selectedCandidateID: candidate.id,
                videoInfo: info
            )
            configureDefaultDownloadSelection()
        } catch {
            addSession = MobileAddSessionSnapshot(
                id: UUID().uuidString,
                input: currentInput,
                state: .failed,
                candidates: currentCandidates,
                selectedCandidateID: candidate.id,
                error: .unknown
            )
        }
    }

    public func importMockFile(named name: String = "Imported clip.mov") {
        addSession = Self.readyAddSession(
            input: MobileInputSource(kind: .importedFile, value: "file://mock/\(name)", displayName: name),
            sourceURL: "file://mock/\(name)",
            kind: .importedFile,
            title: name
        )
        configureDefaultDownloadSelection()
    }

    public func applySharedMockURL(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        addSession = Self.readyAddSession(
            input: MobileInputSource(kind: .sharedURL, value: trimmed),
            sourceURL: trimmed,
            title: "分享的视频"
        )
        configureDefaultDownloadSelection()
    }

    public func selectAddFormat(id: String) {
        guard addSession.videoInfo?.formats.contains(where: { $0.id == id }) == true else {
            return
        }
        selectedAddFormatID = id
    }

    public func toggleAddSubtitle(id: String) {
        guard addSession.videoInfo?.subtitles.contains(where: { $0.id == id }) == true else {
            return
        }
        if let index = selectedAddSubtitleIDs.firstIndex(of: id) {
            selectedAddSubtitleIDs.remove(at: index)
        } else {
            selectedAddSubtitleIDs.append(id)
        }
    }

    public func attachImportedSubtitle(fileURL: URL, languageCode: String = "und") {
        guard addSession.state == .ready,
              var info = addSession.videoInfo,
              let storageDirectoryURL,
              isSupportedSubtitleFile(fileURL),
              let fileName = safeImportedSubtitleFileName(fileURL.lastPathComponent) else {
            return
        }

        let normalizedLanguage = normalizedSubtitleLanguageCode(languageCode)
        let subtitleID = "imported-\(normalizedLanguage)-\(safeSubtitleIdentifierComponent(fileName))"
        let copiedURL = copyImportedSubtitleForAddSession(
            from: fileURL,
            to: storageDirectoryURL,
            subtitleID: subtitleID,
            fileName: fileName
        )
        guard let copiedURL else { return }
        let subtitle = MobileSubtitleChoice(
            id: subtitleID,
            languageCode: normalizedLanguage,
            label: fileName,
            isAutoGenerated: false,
            source: .localFile(copiedURL)
        )

        info.subtitles.removeAll { $0.id == subtitleID }
        info.subtitles.append(subtitle)
        addSession.videoInfo = info
        if !selectedAddSubtitleIDs.contains(subtitleID) {
            selectedAddSubtitleIDs.append(subtitleID)
        }
    }

    public func canAttachImportedSubtitle(toLibraryItem item: MobileLibraryItem) -> Bool {
        guard item.state == .available,
              let taskID = item.sourceTaskID,
              let task = queue.first(where: { $0.id == taskID }) else {
            return false
        }

        return canAttachImportedSubtitle(to: task)
    }

    public func attachImportedSubtitle(
        fileURL: URL,
        toLibraryItemID itemID: String,
        languageCode: String = "und"
    ) async {
        guard let item = library.first(where: { $0.id == itemID }),
              let taskID = item.sourceTaskID else {
            lastLibraryActionStatus = "未找到资料库记录"
            return
        }

        await attachImportedSubtitle(fileURL: fileURL, toTaskID: taskID, languageCode: languageCode)
    }

    public func attachImportedSubtitle(
        fileURL: URL,
        toTaskID taskID: String,
        languageCode: String = "und"
    ) async {
        guard let index = queue.firstIndex(where: { $0.id == taskID }) else {
            lastLibraryActionStatus = "未找到任务"
            return
        }
        guard canAttachImportedSubtitle(to: queue[index]) else {
            lastLibraryActionStatus = "当前记录不能添加字幕"
            return
        }
        guard isSupportedSubtitleFile(fileURL),
              let fileName = safeImportedSubtitleFileName(fileURL.lastPathComponent) else {
            lastLibraryActionStatus = "只支持安全的 SRT 字幕文件"
            return
        }

        let normalizedLanguage = normalizedSubtitleLanguageCode(languageCode)
        let subtitleID = "attached-\(normalizedLanguage)-\(safeSubtitleIdentifierComponent(fileName))"
        let subtitle = MobileSubtitleChoice(
            id: subtitleID,
            languageCode: normalizedLanguage,
            label: fileName,
            isAutoGenerated: false,
            source: .localFile(fileURL)
        )
        guard let artifact = importedSubtitleArtifact(
            from: fileURL,
            subtitle: subtitle,
            taskID: queue[index].id
        ) else {
            lastLibraryActionStatus = "无法添加字幕"
            return
        }

        var artifacts = queue[index].result?.artifacts ?? []
        artifacts.append(artifact)
        queue[index].result = MobileTaskResult(
            artifacts: artifacts,
            primaryArtifactID: queue[index].result?.primaryArtifactID
        )
        queue[index].error = nil
        appendLibraryRecord(from: queue[index])
        lastLibraryActionStatus = "已添加字幕 \(artifact.displayName)"
        lastQueueActionStatus = "已添加字幕 \(queueDisplayName(queue[index]))"
        await persistQueueTask(queue[index])
    }

    public func importVideoFile(fileURL: URL) async {
        guard let storageDirectoryURL, fileURL.isFileURL else {
            rejectImportedVideoFile(
                displayName: "本地视频文件",
                value: "local-import-unavailable",
                state: .failed,
                error: .permissionDenied,
                statusMessage: "无法导入本地视频"
            )
            return
        }

        guard let safeFileName = safeRelocatedLibraryFileName(fileURL.lastPathComponent) else {
            rejectImportedVideoFile(
                displayName: "本地视频文件",
                value: "local-import-unsafe-name",
                state: .unsupported,
                error: .unsupportedOnMobile,
                statusMessage: "无法导入：文件名包含不安全内容"
            )
            return
        }

        guard isSupportedImportedVideoFileName(safeFileName) else {
            rejectImportedVideoFile(
                displayName: safeFileName,
                value: safeFileName,
                state: .unsupported,
                error: .unsupportedOnMobile,
                statusMessage: "只支持 MP4、MOV、M4V 或 WebM 视频"
            )
            return
        }

        guard importStorageChecker.hasEnoughSpaceToImport(
            sourceURL: fileURL,
            storageDirectoryURL: storageDirectoryURL
        ) else {
            rejectImportedVideoFile(
                displayName: safeFileName,
                value: safeFileName,
                state: .failed,
                error: .storageFull,
                statusMessage: "无法导入：设备空间不足"
            )
            return
        }

        let artifact: MobileTaskArtifact
        do {
            artifact = try copyImportedVideoArtifact(
                from: fileURL,
                to: storageDirectoryURL,
                fileName: safeFileName
            )
        } catch ImportedVideoCopyFailure.notRegularFile {
            rejectImportedVideoFile(
                displayName: safeFileName,
                value: safeFileName,
                state: .failed,
                error: .permissionDenied,
                statusMessage: "无法导入：请选择普通视频文件"
            )
            return
        } catch {
            rejectImportedVideoFile(
                displayName: safeFileName,
                value: safeFileName,
                state: .failed,
                error: .permissionDenied,
                statusMessage: "无法导入本地视频"
            )
            return
        }

        let taskID = "import-\(UUID().uuidString)"
        let result = MobileTaskResult(
            artifacts: [artifact],
            primaryArtifactID: artifact.id
        )
        let progress = MobileTaskProgress(
            phase: .downloading,
            completedUnitCount: artifact.byteCount ?? 0,
            totalUnitCount: artifact.byteCount
        )
        let task = MobileTaskSnapshot(
            id: taskID,
            platform: .iOS,
            state: .completed,
            progress: progress,
            downloadSelection: MobileDownloadSelection(
                candidateID: "imported-file",
                formatID: artifact.displayName
            ),
            exportProfile: selectedAddExportProfile,
            capabilities: self.processingCapabilities(for: selectedAddExportProfile),
            backgroundPolicy: MobileBackgroundPolicy(
                execution: .foregroundRequired,
                resumability: .nonResumable,
                limits: [.foregroundRequired, .notResumable]
            ),
            result: result
        )

        addSession = MobileAddSessionSnapshot(
            id: UUID().uuidString,
            input: MobileInputSource(
                kind: .importedFile,
                value: Self.importedFileSourcePlaceholder,
                displayName: artifact.displayName
            ),
            state: .ready,
            candidates: [
                MobileVideoCandidate(
                    id: "imported-file",
                    sourceURL: Self.importedFileSourcePlaceholder,
                    kind: .importedFile,
                    title: artifact.displayName
                )
            ],
            selectedCandidateID: "imported-file",
            videoInfo: MobileVideoInfo(
                candidate: MobileVideoCandidate(
                    id: "imported-file",
                    sourceURL: Self.importedFileSourcePlaceholder,
                    kind: .importedFile,
                    title: artifact.displayName
                ),
                videoID: taskID,
                title: artifact.displayName,
                formats: [
                    MobileFormatChoice(id: artifact.displayName, label: artifact.displayName)
                ]
            )
        )
        resetAddDownloadSelection()
        queue.removeAll { $0.id == taskID }
        queue.insert(task, at: 0)
        appendLibraryRecord(from: task)
        selectedTab = .library
        lastQueueActionStatus = "已导入 \(artifact.displayName)"
        await persistQueueTask(task)
    }

    public func enqueueSelectedVideo() async {
        guard let info = addSession.videoInfo,
              let format = selectedAddFormat(in: info)
        else {
            return
        }

        let taskID = "task-\(info.videoID)"
        let exportProfile = selectedAddExportProfile
        let selectedSubtitles = selectedAddSubtitles(in: info)
        let downloadSelection = MobileDownloadSelection(
            candidateID: info.candidate.id,
            formatID: format.id,
            subtitleIDs: selectedSubtitles
                .filter { !$0.isAutoGenerated }
                .map(\.id),
            autoSubtitleIDs: selectedSubtitles
                .filter(\.isAutoGenerated)
                .map(\.id)
        )
        let subtitleArtifacts = importedSubtitleArtifacts(
            from: selectedSubtitles,
            taskID: taskID
        )
        let task = MobileTaskSnapshot(
            id: taskID,
            platform: .iOS,
            state: .waiting,
            progress: MobileTaskProgress(phase: .waiting),
            downloadSelection: downloadSelection,
            exportProfile: exportProfile,
            capabilities: self.processingCapabilities(for: exportProfile),
            backgroundPolicy: MobileBackgroundPolicy(
                execution: .foregroundRequired,
                resumability: .nonResumable,
                limits: [.foregroundRequired, .notResumable]
            ),
            result: MobileTaskResult(artifacts: [
                MobileTaskArtifact(
                    id: "pending-\(info.videoID)",
                    kind: .metadata,
                    displayName: "\(info.title) · \(format.label)",
                    storageIdentifier: Self.sourceReferenceStorageIdentifier(for: taskID)
                )
            ] + subtitleArtifacts, primaryArtifactID: "pending-\(info.videoID)")
        )
        let sourceURL = info.candidate.sourceURL
        sourceURLByTaskID[taskID] = sourceURL
        queue.removeAll { $0.id == task.id }
        queue.insert(task, at: 0)
        selectedTab = .queue
        await persistQueueTask(task)
        await persistSourceReferenceIfSafe(sourceURL, taskID: taskID)
    }

    public func startDownload(taskID: String) async {
        guard let index = queue.firstIndex(where: { $0.id == taskID }) else {
            lastQueueActionStatus = "未找到任务"
            return
        }
        guard queue[index].availableActions.contains(.startDownload) else {
            lastQueueActionStatus = "当前状态不能开始下载 \(queueDisplayName(queue[index]))"
            return
        }
        guard let sourceURL = sourceURL(for: queue[index]) else {
            queue[index].state = .failed
            queue[index].error = .sourceUnavailableAfterRelaunch
            lastQueueActionStatus = "需要重新添加原链接 \(queueDisplayName(queue[index]))"
            await persistQueueTask(queue[index])
            return
        }
        queue[index].state = .downloading
        queue[index].error = nil
        queue[index].progress = MobileTaskProgress(phase: .downloading, completedUnitCount: 0)
        await persistQueueTask(queue[index])

        let request = downloadRequest(for: queue[index], sourceURL: sourceURL)
        if let backgroundDownloadStarter {
            do {
                let result = try await backgroundDownloadStarter.startBackgroundDownload(request)
                guard let backgroundIndex = queue.firstIndex(where: { $0.id == taskID }) else { return }
                queue[backgroundIndex].state = .downloading
                queue[backgroundIndex].error = nil
                queue[backgroundIndex].progress = result.record.lastProgress
                queue[backgroundIndex].backgroundPolicy = result.record.backgroundPolicy
                var supportedCapabilities = queue[backgroundIndex].capabilities.supportedCapabilities
                if !supportedCapabilities.contains(.backgroundTransfer) {
                    supportedCapabilities.append(.backgroundTransfer)
                }
                queue[backgroundIndex].capabilities = MobileProcessingCapabilities(
                    platform: .iOS,
                    supportedCapabilities: supportedCapabilities,
                    maxRenderHeight: queue[backgroundIndex].capabilities.maxRenderHeight
                )
                lastQueueActionStatus = "已交给系统后台下载 \(queueDisplayName(queue[backgroundIndex]))"
                await persistQueueTask(queue[backgroundIndex])
                return
            } catch {
                lastQueueActionStatus = "后台下载未启动，改为前台下载 \(queueDisplayName(queue[index]))"
            }
        }

        guard let downloadEngine else {
            guard let foregroundIndex = queue.firstIndex(where: { $0.id == taskID }) else { return }
            queue[foregroundIndex].state = .needsForegroundToContinue
            queue[foregroundIndex].error = .unsupportedOnMobile
            lastQueueActionStatus = "此版本暂不能直接下载该任务 \(queueDisplayName(queue[foregroundIndex]))"
            await persistQueueTask(queue[foregroundIndex])
            return
        }

        do {
            let result = try await downloadEngine.download(request) { [weak self] progress in
                Task { @MainActor in
                    await self?.updateDownloadProgress(taskID: taskID, progress: progress)
                }
            }
            guard let completedIndex = queue.firstIndex(where: { $0.id == taskID }) else { return }
            guard queue[completedIndex].state == .downloading else { return }
            queue[completedIndex].state = .completed
            queue[completedIndex].progress = result.primaryArtifact.flatMap { artifact in
                artifact.byteCount.map {
                    MobileTaskProgress(phase: .downloading, completedUnitCount: $0, totalUnitCount: $0)
                }
            } ?? queue[completedIndex].progress
            queue[completedIndex].result = resultByMergingExistingProcessableArtifacts(
                into: result,
                from: queue[completedIndex].result
            )
            queue[completedIndex].error = nil
            appendLibraryRecord(from: queue[completedIndex])
            lastQueueActionStatus = "已完成 \(queueDisplayName(queue[completedIndex]))"
            sourceURLByTaskID[taskID] = nil
            await removeSourceReference(taskID)
            await persistQueueTask(queue[completedIndex])
        } catch let error as MobileTaskError {
            await markDownloadFailed(taskID: taskID, error: error)
        } catch {
            await markDownloadFailed(taskID: taskID, error: .unknown)
        }
    }

    public func applyTranslationResult(_ translation: MobileTranslationResult, toTaskID taskID: String) async {
        translationResultByTaskID[taskID] = translation
    }

    public func restoreQueueFromRepository() async {
        guard let taskRepository else {
            return
        }

        do {
            let storedTasks = try await taskRepository.loadTasks()
            let recoveryOutcomes = try await backgroundTransferRegistry?.loadRecoveryOutcomes() ?? []
            let recoveryOutcomeByTaskID = Dictionary(
                recoveryOutcomes.map { ($0.taskID, $0) },
                uniquingKeysWith: { first, second in
                    first.updatedAt >= second.updatedAt ? first : second
                }
            )
            let storedTaskIDs = Set(storedTasks.map(\.id))
            queue = storedTasks
                .map { task in
                    if let outcome = recoveryOutcomeByTaskID[task.id] {
                        return taskSnapshot(task, applying: outcome)
                    }
                    return restoredTaskSnapshot(task)
                }
                .map(restoreLegacySourceURLIfNeeded)
            await restoreSourceReferences(for: queue)
            for outcome in recoveryOutcomes where storedTaskIDs.contains(outcome.taskID) && outcome.status == .completed {
                await removeSourceReference(outcome.taskID)
            }
            for task in queue where task.state == .completed {
                appendLibraryRecord(from: task)
            }
            for (original, migrated) in zip(storedTasks, queue) where original != migrated {
                await persistQueueTask(migrated)
            }
            for outcome in recoveryOutcomes {
                guard storedTaskIDs.contains(outcome.taskID) else {
                    continue
                }
                try await backgroundTransferRegistry?.removeRecoveryOutcome(
                    transferIdentifier: outcome.transferIdentifier
                )
            }
        } catch {
            lastQueueActionStatus = "恢复队列失败"
        }
    }

    public func performQueueAction(_ action: MobileTaskAction, taskID: String) async {
        guard let index = queue.firstIndex(where: { $0.id == taskID }) else {
            lastQueueActionStatus = "未找到任务"
            return
        }

        guard queue[index].availableActions.contains(action) else {
            lastQueueActionStatus = "当前状态不能执行此操作 \(queueDisplayName(queue[index]))"
            return
        }

        switch action {
        case .startDownload:
            await runActiveQueueTask(taskID: taskID) { [weak self] in
                await self?.startDownload(taskID: taskID)
            }
        case .exportTranslatedSubtitle:
            await runActiveQueueTask(taskID: taskID) { [weak self] in
                await self?.exportTranslatedSubtitle(taskID: taskID)
            }
        case .exportRenderedVideo:
            await runActiveQueueTask(taskID: taskID) { [weak self] in
                await self?.exportRenderedVideo(taskID: taskID)
            }
        case .pause:
            queue[index].state = .waiting
            lastQueueActionStatus = "已暂停 \(queueDisplayName(queue[index]))"
            await persistQueueTask(queue[index])
        case .resume:
            queue[index].state = phaseState(for: queue[index].progress.phase)
            lastQueueActionStatus = "已继续 \(queueDisplayName(queue[index]))"
            await persistQueueTask(queue[index])
        case .cancel:
            let previous = preExportTaskByID[taskID]
            cancelActiveQueueTask(taskID: taskID)
            await removeBackgroundTransfer(taskID: taskID)
            queue[index].state = .cancelled
            queue[index].error = nil
            queue[index].progress = previous?.progress ?? queue[index].progress
            queue[index].result = previous?.result
            queue[index].backgroundPolicy = previous?.backgroundPolicy ?? queue[index].backgroundPolicy
            preExportTaskByID[taskID] = nil
            lastQueueActionStatus = "已取消 \(queueDisplayName(queue[index]))"
            await persistQueueTask(queue[index])
        case .retry:
            queue[index].state = .waiting
            queue[index].error = nil
            queue[index].progress = MobileTaskProgress(phase: .waiting)
            lastQueueActionStatus = "已准备重试 \(queueDisplayName(queue[index]))"
            await persistQueueTask(queue[index])
        case .openAppToContinue:
            if queue[index].backgroundPolicy.resumability == .nonResumable ||
                queue[index].backgroundPolicy.limits.contains(.notResumable) {
                queue[index].state = .needsForegroundToContinue
                queue[index].error = .systemBackgroundLimit
                lastQueueActionStatus = "需要重新开始或重新导出 \(queueDisplayName(queue[index]))"
                await persistQueueTask(queue[index])
                return
            }
            queue[index].state = phaseState(for: queue[index].progress.phase)
            queue[index].error = nil
            queue[index].backgroundPolicy = MobileBackgroundPolicy(execution: .systemManaged, resumability: .resumable)
            lastQueueActionStatus = "已回到前台继续 \(queueDisplayName(queue[index]))"
            await persistQueueTask(queue[index])
        case .openResult:
            await publishQueueResultActionOutcome(.open, for: queue[index])
        case .shareResult:
            await publishQueueResultActionOutcome(.share, for: queue[index])
        case .remove:
            let name = queueDisplayName(queue[index])
            cancelActiveQueueTask(taskID: taskID)
            await removeBackgroundTransfer(taskID: taskID)
            queue.remove(at: index)
            sourceURLByTaskID[taskID] = nil
            preExportTaskByID[taskID] = nil
            lastQueueActionStatus = "已移除 \(name)"
            await removeSourceReference(taskID)
            await removeQueueTask(taskID)
        }
    }

    private func publishQueueResultActionOutcome(
        _ libraryAction: MobileLibraryAction,
        for task: MobileTaskSnapshot
    ) async {
        guard task.state == .completed,
              let result = task.result,
              result.primaryArtifact != nil,
              !result.artifacts.isEmpty else {
            pendingLibraryActionCommand = nil
            lastLibraryActionOutcome = nil
            lastLibraryActionStatus = nil
            lastQueueActionStatus = "没有可用的完成文件 \(queueDisplayName(task))"
            return
        }

        appendLibraryRecord(from: task)
        guard let item = library.first(where: { $0.sourceTaskID == task.id }) else {
            pendingLibraryActionCommand = nil
            lastQueueActionStatus = "没有可用的资料库记录 \(queueDisplayName(task))"
            return
        }

        await performLibraryAction(libraryAction, itemID: item.id)
        selectedTab = .library
    }

    public func performLibraryAction(_ action: MobileLibraryAction, itemID: String) async {
        guard let index = library.firstIndex(where: { $0.id == itemID }) else {
            let outcome = missingLibraryActionOutcome(action: action, itemID: itemID)
            publishLibraryActionOutcome(outcome)
            return
        }

        let item = library[index]
        guard item.availableActions.contains(action) else {
            let outcome = unavailableLibraryActionOutcome(for: action, item: item)
            publishLibraryActionOutcome(outcome)
            return
        }

        let outcome = libraryActionOutcome(for: action, item: item)
        switch action {
        case .deleteRecord:
            let sourceTaskID = item.sourceTaskID
            library.remove(at: index)
            if let sourceTaskID {
                cancelActiveQueueTask(taskID: sourceTaskID)
                preExportTaskByID[sourceTaskID] = nil
                sourceURLByTaskID[sourceTaskID] = nil
                queue.removeAll { $0.id == sourceTaskID }
                await removeBackgroundTransfer(taskID: sourceTaskID)
                await removeSourceReference(sourceTaskID)
                await removeQueueTask(sourceTaskID)
            }
            publishLibraryActionOutcome(outcome)
        case .open, .share, .saveToFiles, .saveToPhotos, .locateFile:
            publishLibraryActionOutcome(outcome)
        }
    }

    public func relocateLibraryFile(itemID: String, pickedFileURL: URL) async {
        guard let index = library.firstIndex(where: { $0.id == itemID }) else {
            let outcome = missingLibraryActionOutcome(action: .locateFile, itemID: itemID)
            publishLibraryActionOutcome(outcome)
            return
        }
        guard let storageDirectoryURL else {
            let item = library[index]
            publishLibraryActionOutcome(actionOutcome(
                .locateFile,
                item: item,
                artifacts: [],
                presentation: .documentPicker,
                status: .failed,
                statusMessage: "无法保存重新定位的文件",
                requiresSystemUI: false
            ))
            return
        }

        var item = library[index]
        guard item.state == .fileMissing,
              let sourceTaskID = item.sourceTaskID,
              let queueIndex = queue.firstIndex(where: { $0.id == sourceTaskID }),
              let existingArtifact = item.artifacts.first,
              let relocatedArtifact = copyRelocatedLibraryArtifact(
                from: pickedFileURL,
                replacing: existingArtifact,
                sourceTaskID: sourceTaskID,
                storageDirectoryURL: storageDirectoryURL
              ) else {
            publishLibraryActionOutcome(actionOutcome(
                .locateFile,
                item: item,
                artifacts: [],
                presentation: .documentPicker,
                status: .failed,
                statusMessage: "无法重新定位文件",
                requiresSystemUI: false
            ))
            return
        }

        item.artifacts = replacingArtifact(existingArtifact.id, in: item.artifacts, with: relocatedArtifact)
        item.state = .available
        library[index] = item

        var task = queue[queueIndex]
        let existingResult = task.result ?? MobileTaskResult(artifacts: [], primaryArtifactID: relocatedArtifact.id)
        task.result = MobileTaskResult(
            artifacts: replacingArtifact(existingArtifact.id, in: existingResult.artifacts, with: relocatedArtifact),
            primaryArtifactID: existingResult.primaryArtifactID ?? relocatedArtifact.id
        )
        task.state = .completed
        task.error = nil
        if let byteCount = relocatedArtifact.byteCount {
            task.progress = MobileTaskProgress(
                phase: relocatedProgressPhase(for: relocatedArtifact),
                completedUnitCount: byteCount,
                totalUnitCount: byteCount
            )
        }
        queue[queueIndex] = task
        await persistQueueTask(task)

        publishLibraryActionOutcome(MobileLibraryActionOutcome(
            action: .locateFile,
            itemID: item.id,
            itemTitle: item.title,
            artifacts: item.artifacts,
            presentation: .documentPicker,
            status: .completed,
            statusMessage: "已重新定位 \(relocatedArtifact.displayName)",
            requiresSystemUI: false,
            completedRecordMutation: true
        ))
    }

    public func consumePendingLibraryActionCommand() -> IOSLibraryActionCommand? {
        defer { pendingLibraryActionCommand = nil }
        return pendingLibraryActionCommand
    }

    public static func preview() -> IOSMobileAppModel {
        IOSMobileAppModel()
    }

    public static func live(
        storageDirectoryURL: URL? = nil,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.local.videodownloader.ios"
    ) -> IOSMobileAppModel {
        live(
            storageDirectoryURL: storageDirectoryURL,
            bundleIdentifier: bundleIdentifier,
            credentialStore: IOSKeychainCredentialStore(),
            importedFileAccessor: IOSImportedFileAccessor(),
            backgroundCompletionConsumer: IOSNoopBackgroundURLSessionCompletionConsumer()
        )
    }

    public static func live(
        storageDirectoryURL: URL? = nil,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.local.videodownloader.ios",
        backgroundCompletionConsumer: any IOSBackgroundURLSessionCompletionConsuming
    ) -> IOSMobileAppModel {
        live(
            storageDirectoryURL: storageDirectoryURL,
            bundleIdentifier: bundleIdentifier,
            credentialStore: IOSKeychainCredentialStore(),
            importedFileAccessor: IOSImportedFileAccessor(),
            backgroundCompletionConsumer: backgroundCompletionConsumer
        )
    }

    static func live(
        storageDirectoryURL: URL?,
        importedFileAccessor: any IOSImportedFileAccessing
    ) -> IOSMobileAppModel {
        live(
            storageDirectoryURL: storageDirectoryURL,
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.local.videodownloader.ios",
            credentialStore: IOSKeychainCredentialStore(),
            importedFileAccessor: importedFileAccessor,
            backgroundCompletionConsumer: IOSNoopBackgroundURLSessionCompletionConsumer()
        )
    }

    static func live(
        storageDirectoryURL: URL?,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.local.videodownloader.ios",
        credentialStore: any SecureCredentialStore,
        importedFileAccessor: any IOSImportedFileAccessing = IOSImportedFileAccessor(),
        backgroundCompletionConsumer: any IOSBackgroundURLSessionCompletionConsuming = IOSNoopBackgroundURLSessionCompletionConsumer()
    ) -> IOSMobileAppModel {
        let storage = storageDirectoryURL ?? liveStorageDirectoryURL()
        let repository = storage.map {
            FileTaskRepository(fileURL: $0.appendingPathComponent("mobile-tasks.json", isDirectory: false))
        }
        let registry = storage.map {
            BackgroundTransferRegistry(fileURL: $0.appendingPathComponent("background-transfers.json", isDirectory: false))
        }
        let sourceReferenceStore = storage.map {
            IOSSourceReferenceStore(fileURL: $0.appendingPathComponent("mobile-source-references.json", isDirectory: false))
        }
        let downloadEngine = storage.flatMap { storageURL -> (any MobileDownloadEngine)? in
            guard let registry else { return nil }
            return IOSMobileDownloadEngine(
                downloadDirectoryURL: storageURL.appendingPathComponent("Downloads", isDirectory: true),
                transferRegistry: registry
            )
        }
        var backgroundURLSessionDownloadDelegate: IOSBackgroundURLSessionDownloadDelegate?
        let backgroundDownloadStarter = storage.flatMap { storageURL -> (any IOSBackgroundDownloadStarting)? in
            guard let registry else { return nil }
            let descriptor = IOSBackgroundURLSessionDescriptor(bundleIdentifier: bundleIdentifier,
                purpose: "downloads"
            )
            let eventHandler = IOSBackgroundTransferEventHandler(
                storageDirectoryURL: storageURL,
                transferRegistry: registry
            )
            let delegate = IOSBackgroundURLSessionDownloadDelegate(
                eventRecorder: eventHandler,
                completionConsumer: backgroundCompletionConsumer
            )
            backgroundURLSessionDownloadDelegate = delegate
            return IOSBackgroundURLSessionDownloadStarter(
                transferRegistry: registry,
                descriptor: descriptor,
                delegate: delegate
            )
        }
        let subtitleProcessor = storage.map { storageURL -> any SubtitleProcessor in
            IOSMobileSubtitleProcessor(storageDirectoryURL: storageURL)
        }
        let renderExporter = storage.map { storageURL -> any RenderExporter in
            IOSMobileRenderExporter(storageDirectoryURL: storageURL)
        }
        #if os(iOS) && canImport(BackgroundTasks)
        let continuedProcessingSubmitter: (any IOSContinuedProcessingTaskSubmitting)?
        let renderRuntimeCapabilities: IOSRenderRuntimeCapabilities
        if #available(iOS 26.0, *) {
            continuedProcessingSubmitter = IOSBackgroundTasksContinuedProcessingSubmitter()
            renderRuntimeCapabilities = IOSRenderRuntimeCapabilities(
                supportsContinuedProcessing: true,
                supportsCheckpointedRender: false,
                continuedProcessingTimeLimitSeconds: 600
            )
        } else {
            continuedProcessingSubmitter = nil
            renderRuntimeCapabilities = IOSRenderRuntimeCapabilities()
        }
        #else
        let continuedProcessingSubmitter: (any IOSContinuedProcessingTaskSubmitting)? = nil
        let renderRuntimeCapabilities = IOSRenderRuntimeCapabilities()
        #endif
        let translationConfiguration = liveTranslationConfiguration(storageDirectoryURL: storage)

        return IOSMobileAppModel(
            addSession: MobileAddSessionSnapshot(id: "add-live"),
            queue: [],
            library: [],
            translationConfiguration: translationConfiguration,
            credentialStore: credentialStore,
            downloadEngine: downloadEngine,
            backgroundDownloadStarter: backgroundDownloadStarter,
            backgroundURLSessionDownloadDelegateForTesting: backgroundURLSessionDownloadDelegate,
            subtitleProcessor: subtitleProcessor,
            renderExporter: renderExporter,
            continuedProcessingSubmitter: continuedProcessingSubmitter,
            continuedProcessingScheduler: IOSContinuedProcessingRenderScheduler(bundleIdentifier: bundleIdentifier),
            renderRuntimeCapabilities: renderRuntimeCapabilities,
            importedFileAccessor: importedFileAccessor,
            storageDirectoryURL: storage,
            taskRepository: repository,
            backgroundTransferRegistry: registry,
            sourceReferenceStore: sourceReferenceStore
        )
    }

    private static func liveTranslationConfiguration(storageDirectoryURL: URL?) -> MobileTranslationConfiguration {
        let fallback = MobileTranslationConfiguration(
            engine: .openAICompatible,
            baseURL: "https://api.openai.com",
            model: nil,
            credential: nil,
            readiness: TranslationReadiness(issues: [
                TranslationReadinessIssue(kind: .needsConfiguration, message: "需要先配置模型并保存 API key。")
            ])
        )
        guard let storageDirectoryURL else {
            return fallback
        }
        guard let store = try? IOSTranslationConfigurationStore(directoryURL: storageDirectoryURL),
              var configuration = try? store.loadConfiguration() else {
            return fallback
        }
        configuration.readiness = persistedReadiness(for: configuration)
        return configuration
    }

    private func runActiveQueueTask(
        taskID: String,
        operation: @escaping @MainActor @Sendable () async -> Void
    ) async {
        guard activeQueueTasksByID[taskID] == nil else {
            lastQueueActionStatus = "任务正在执行"
            return
        }

        let token = UUID()
        let task = Task { @MainActor in
            await operation()
        }
        activeQueueTasksByID[taskID] = ActiveQueueTask(token: token, task: task)
        await task.value
        if activeQueueTasksByID[taskID]?.token == token {
            activeQueueTasksByID[taskID] = nil
        }
    }

    private func cancelActiveQueueTask(taskID: String) {
        activeQueueTasksByID[taskID]?.task.cancel()
    }

    private func removeBackgroundTransfer(taskID: String) async {
        try? await backgroundDownloadStarter?.cancelBackgroundDownload(taskID: taskID)
        try? await backgroundTransferRegistry?.remove(taskID: taskID)
    }

    private static func liveStorageDirectoryURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("MoongateMobile", isDirectory: true)
    }

    private static func sourceReferenceStorageIdentifier(for taskID: String) -> String {
        "mobile-source:\(taskID)"
    }

    private static func readyAddSession(
        input: MobileInputSource,
        sourceURL: String,
        kind: MobileCandidateKind = .hlsStream,
        title: String
    ) -> MobileAddSessionSnapshot {
        let candidate = MobileVideoCandidate(
            id: "candidate-\(abs(sourceURL.hashValue))",
            sourceURL: sourceURL,
            kind: kind,
            title: title
        )
        return MobileAddSessionSnapshot(
            id: UUID().uuidString,
            input: input,
            state: .ready,
            candidates: [candidate],
            selectedCandidateID: candidate.id,
            videoInfo: MobileVideoInfo(
                candidate: candidate,
                videoID: "mobile-\(abs(sourceURL.hashValue))",
                title: title,
                durationSeconds: 94,
                formats: [
                    MobileFormatChoice(id: "1080p", label: "1080p", detail: "移动端推荐", height: 1080),
                    MobileFormatChoice(id: "720p", label: "720p", detail: "省流量", height: 720)
                ],
                subtitles: [
                    MobileSubtitleChoice(id: "en", languageCode: "en", label: "English", isAutoGenerated: false),
                    MobileSubtitleChoice(id: "zh-Hans-auto", languageCode: "zh-Hans", label: "简体中文自动字幕", isAutoGenerated: true)
                ]
            )
        )
    }

    private func queueDisplayName(_ task: MobileTaskSnapshot) -> String {
        task.result?.primaryArtifact?.displayName ?? "未命名视频"
    }

    private func processingCapabilities(
        for exportProfile: MobileExportProfile
    ) -> MobileProcessingCapabilities {
        var supportedCapabilities: [MobileProcessingCapability] = [
            .download,
            .translation,
            .subtitleExport
        ]
        if exportProfile.requiresVideoRender {
            supportedCapabilities.append(.videoRender)
            if continuedProcessingSubmitter != nil,
               renderRuntimeCapabilities.supportsContinuedProcessing {
                supportedCapabilities.append(.backgroundRender)
            }
        }
        return MobileProcessingCapabilities(
            platform: .iOS,
            supportedCapabilities: supportedCapabilities,
            maxRenderHeight: exportProfile.requiresVideoRender ? exportProfile.maxRenderHeight : nil
        )
    }

    private func downloadRequest(for task: MobileTaskSnapshot, sourceURL: String) -> MobileDownloadRequest {
        let selection = task.downloadSelection
        return MobileDownloadRequest(
            id: task.id,
            sourceURL: sourceURL,
            candidateID: selection?.candidateID ?? task.id,
            videoID: task.result?.primaryArtifact?.displayName ?? task.id,
            formatID: selection?.formatID ?? "mp4",
            subtitleIDs: selection?.subtitleIDs ?? [],
            autoSubtitleIDs: selection?.autoSubtitleIDs ?? [],
            exportProfile: task.exportProfile,
            preferredTitle: task.result?.primaryArtifact?.displayName
        )
    }

    private func canAttachImportedSubtitle(to task: MobileTaskSnapshot) -> Bool {
        guard task.state == .completed,
              let result = task.result,
              result.artifacts.contains(where: { $0.kind == .originalMedia }),
              !result.artifacts.contains(where: { $0.kind == .transcript }) else {
            return false
        }

        return task.exportProfile.subtitleMode == .translatedSubtitleFile ||
            task.exportProfile.subtitleMode == .softSubtitle
    }

    private func resetAddDownloadSelection() {
        selectedAddFormatID = nil
        selectedAddSubtitleIDs = []
    }

    private func configureDefaultDownloadSelection() {
        selectedAddFormatID = addSession.videoInfo?.recommendedFormat?.id
        selectedAddSubtitleIDs = []
    }

    private func selectedAddFormat(in info: MobileVideoInfo) -> MobileFormatChoice? {
        if let selectedAddFormatID,
           let format = info.formats.first(where: { $0.id == selectedAddFormatID }) {
            return format
        }
        return info.recommendedFormat
    }

    private func selectedAddSubtitles(in info: MobileVideoInfo) -> [MobileSubtitleChoice] {
        let selectedIDs = Set(selectedAddSubtitleIDs)
        return info.subtitles.filter { selectedIDs.contains($0.id) }
    }

    private func importedSubtitleArtifacts(
        from subtitles: [MobileSubtitleChoice],
        taskID: String
    ) -> [MobileTaskArtifact] {
        subtitles.compactMap { subtitle in
            guard case let .localFile(fileURL) = subtitle.source else {
                return nil
            }
            return importedSubtitleArtifact(from: fileURL, subtitle: subtitle, taskID: taskID)
        }
    }

    private func importedSubtitleArtifact(
        from fileURL: URL,
        subtitle: MobileSubtitleChoice,
        taskID: String
    ) -> MobileTaskArtifact? {
        guard let storageDirectoryURL,
              isSupportedSubtitleFile(fileURL),
              let fileName = safeImportedSubtitleFileName(fileURL.lastPathComponent) else {
            return nil
        }
        let storageFileName = importedSubtitleStorageFileName(
            taskID: taskID,
            subtitleID: subtitle.id,
            fileName: fileName
        )

        let destinationURL = storageDirectoryURL.appendingPathComponent(storageFileName, isDirectory: false)
        let storagePath = storageDirectoryURL.standardizedFileURL.path
        let destinationPath = destinationURL.standardizedFileURL.path
        guard destinationPath.hasPrefix(storagePath + "/") else {
            return nil
        }

        do {
            try IOSAppStoragePolicy.applyDirectoryPolicy(to: storageDirectoryURL)
            if fileURL.standardizedFileURL.path != destinationURL.standardizedFileURL.path {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                if fileURL.standardizedFileURL.path.hasPrefix(storagePath + "/") {
                    try FileManager.default.copyItem(at: fileURL, to: destinationURL)
                } else {
                    try importedFileAccessor.withAccess(to: fileURL) {
                        try FileManager.default.copyItem(at: fileURL, to: destinationURL)
                    }
                }
            }
            try IOSAppStoragePolicy.applyFilePolicy(to: destinationURL)
            return MobileTaskArtifact(
                id: "transcript-\(taskID)-\(subtitle.id)",
                kind: .transcript,
            displayName: subtitle.label,
            storageIdentifier: storageFileName,
                byteCount: storedByteCount(at: destinationURL)
            )
        } catch {
            return nil
        }
    }

    private func copyImportedSubtitleForAddSession(
        from fileURL: URL,
        to storageDirectoryURL: URL,
        subtitleID: String,
        fileName: String
    ) -> URL? {
        let storageFileName = importedSubtitleStorageFileName(
            taskID: "add",
            subtitleID: subtitleID,
            fileName: fileName
        )
        let destinationURL = storageDirectoryURL.appendingPathComponent(storageFileName, isDirectory: false)
        let storagePath = storageDirectoryURL.standardizedFileURL.path
        let destinationPath = destinationURL.standardizedFileURL.path
        guard destinationPath.hasPrefix(storagePath + "/") else {
            return nil
        }

        do {
            try IOSAppStoragePolicy.applyDirectoryPolicy(to: storageDirectoryURL)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            if fileURL.standardizedFileURL.path.hasPrefix(storagePath + "/") {
                try FileManager.default.copyItem(at: fileURL, to: destinationURL)
            } else {
                try importedFileAccessor.withAccess(to: fileURL) {
                    try FileManager.default.copyItem(at: fileURL, to: destinationURL)
                }
            }
            try IOSAppStoragePolicy.applyFilePolicy(to: destinationURL)
            return destinationURL
        } catch {
            return nil
        }
    }

    private enum ImportedVideoCopyFailure: Error {
        case copyFailed
        case notRegularFile
    }

    private func copyImportedVideoArtifact(
        from fileURL: URL,
        to storageDirectoryURL: URL,
        fileName: String
    ) throws -> MobileTaskArtifact {
        let storageIdentifier = importedVideoStorageIdentifier(fileName: fileName)
        let artifactStore = IOSArtifactStore(storageDirectoryURL: storageDirectoryURL)
        guard let destinationURL = try? artifactStore.fileURL(forStorageIdentifier: storageIdentifier) else {
            throw ImportedVideoCopyFailure.copyFailed
        }

        do {
            try IOSAppStoragePolicy.applyDirectoryPolicy(to: destinationURL.deletingLastPathComponent())
            let sourcePath = fileURL.standardizedFileURL.path
            let destinationPath = destinationURL.standardizedFileURL.path
            if sourcePath == destinationPath {
                guard isRegularFile(at: fileURL) else {
                    throw ImportedVideoCopyFailure.notRegularFile
                }
            }
            if sourcePath != destinationPath {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                if sourcePath.hasPrefix(storageDirectoryURL.standardizedFileURL.path + "/") {
                    guard isRegularFile(at: fileURL) else {
                        throw ImportedVideoCopyFailure.notRegularFile
                    }
                    try FileManager.default.copyItem(at: fileURL, to: destinationURL)
                } else {
                    try importedFileAccessor.withAccess(to: fileURL) {
                        guard isRegularFile(at: fileURL) else {
                            throw ImportedVideoCopyFailure.notRegularFile
                        }
                        try FileManager.default.copyItem(at: fileURL, to: destinationURL)
                    }
                }
            }
            try IOSAppStoragePolicy.applyFilePolicy(to: destinationURL)
            return MobileTaskArtifact(
                id: "imported-original-\(safeSubtitleIdentifierComponent(UUID().uuidString))",
                kind: .originalMedia,
                displayName: fileName,
                storageIdentifier: storageIdentifier,
                byteCount: storedByteCount(at: destinationURL)
            )
        } catch let failure as ImportedVideoCopyFailure {
            throw failure
        } catch {
            throw ImportedVideoCopyFailure.copyFailed
        }
    }

    private func isRegularFile(at fileURL: URL) -> Bool {
        (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private func sourceURL(for task: MobileTaskSnapshot) -> String? {
        sourceURLByTaskID[task.id]
    }

    private func persistSourceReferenceIfSafe(_ sourceURL: String, taskID: String) async {
        guard IOSSourceReferenceStore.isPersistableSourceURL(sourceURL) else {
            await removePersistedSourceReference(taskID)
            return
        }

        do {
            try await sourceReferenceStore?.saveSource(sourceURL, forTaskID: taskID)
        } catch {
            lastQueueActionStatus = "保存恢复来源失败 \(taskID)"
        }
    }

    private func restoreSourceReferences(for tasks: [MobileTaskSnapshot]) async {
        guard let sourceReferenceStore else { return }

        do {
            let sources = try await sourceReferenceStore.loadSources()
            let taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
            for (taskID, sourceURL) in sources {
                guard let task = taskByID[taskID] else {
                    try? await sourceReferenceStore.removeSource(forTaskID: taskID)
                    continue
                }
                guard Self.shouldRetainSourceReference(for: task),
                      IOSSourceReferenceStore.isPersistableSourceURL(sourceURL) else {
                    sourceURLByTaskID[taskID] = nil
                    try? await sourceReferenceStore.removeSource(forTaskID: taskID)
                    continue
                }
                sourceURLByTaskID[taskID] = sourceURL
            }
        } catch {
            lastQueueActionStatus = "恢复来源失败"
        }
    }

    private static func shouldRetainSourceReference(for task: MobileTaskSnapshot) -> Bool {
        switch task.state {
        case .completed, .cancelled:
            return false
        case .waiting, .analyzing, .ready, .downloading, .translating, .exporting, .needsForegroundToContinue, .failed:
            return true
        }
    }

    private func removeSourceReference(_ taskID: String) async {
        sourceURLByTaskID[taskID] = nil
        await removePersistedSourceReference(taskID)
    }

    private func removePersistedSourceReference(_ taskID: String) async {
        do {
            try await sourceReferenceStore?.removeSource(forTaskID: taskID)
        } catch {
            lastQueueActionStatus = "清理恢复来源失败 \(taskID)"
        }
    }

    private func libraryActionOutcome(
        for action: MobileLibraryAction,
        item: MobileLibraryItem
    ) -> MobileLibraryActionOutcome {
        let artifacts = preferredArtifacts(for: action, item: item)
        let title = item.title

        switch action {
        case .open:
            return actionOutcome(
                action,
                item: item,
                artifacts: artifacts,
                presentation: artifacts.isEmpty ? .unavailable : .inAppOpen,
                status: artifacts.isEmpty ? .unavailable : .prepared,
                statusMessage: artifacts.first.map { "准备打开 \($0.displayName)" } ?? "没有可打开的文件",
                requiresSystemUI: artifacts.isEmpty == false
            )
        case .share:
            return actionOutcome(
                action,
                item: item,
                artifacts: artifacts,
                presentation: artifacts.isEmpty ? .unavailable : .shareSheet,
                status: artifacts.isEmpty ? .unavailable : .requiresSystemPresentation,
                statusMessage: artifacts.isEmpty ? "没有可分享的文件" : "需要打开系统分享面板",
                requiresSystemUI: artifacts.isEmpty == false
            )
        case .saveToFiles:
            return actionOutcome(
                action,
                item: item,
                artifacts: artifacts,
                presentation: artifacts.isEmpty ? .unavailable : .fileExporter,
                status: artifacts.isEmpty ? .unavailable : .requiresSystemPresentation,
                statusMessage: artifacts.isEmpty ? "没有可存储的文件" : "需要选择保存位置",
                requiresSystemUI: artifacts.isEmpty == false
            )
        case .saveToPhotos:
            return actionOutcome(
                action,
                item: item,
                artifacts: artifacts,
                presentation: artifacts.isEmpty ? .unavailable : .photoLibraryExporter,
                status: artifacts.isEmpty ? .unavailable : .requiresSystemPresentation,
                statusMessage: artifacts.isEmpty ? "没有可存到照片的视频" : "需要授权保存到照片",
                requiresSystemUI: artifacts.isEmpty == false
            )
        case .deleteRecord:
            return actionOutcome(
                action,
                item: item,
                artifacts: [],
                presentation: .confirmationOnly,
                status: .completed,
                statusMessage: "已删除记录 \(title)",
                requiresSystemUI: false,
                completedRecordMutation: true
            )
        case .locateFile:
            return actionOutcome(
                action,
                item: item,
                artifacts: [],
                presentation: .documentPicker,
                status: .requiresSystemPresentation,
                statusMessage: "需要选择文件以重新定位 \(title)",
                requiresSystemUI: true
            )
        }
    }

    private func rejectImportedVideoFile(
        displayName: String,
        value: String,
        state: MobileAddSessionState,
        error: MobileTaskError,
        statusMessage: String
    ) {
        lastQueueActionStatus = statusMessage
        addSession = MobileAddSessionSnapshot(
            id: UUID().uuidString,
            input: MobileInputSource(
                kind: .importedFile,
                value: value,
                displayName: displayName
            ),
            state: state,
            error: error
        )
    }

    private func publishLibraryActionOutcome(_ outcome: MobileLibraryActionOutcome) {
        lastLibraryActionOutcome = outcome
        lastLibraryActionStatus = outcome.statusMessage

        do {
            pendingLibraryActionCommand = try IOSLibraryActionPresenter().command(for: outcome)
        } catch IOSLibraryActionPresenterError.unsafeArtifactReference {
            pendingLibraryActionCommand = nil
            lastLibraryActionOutcome = MobileLibraryActionOutcome(
                action: outcome.action,
                itemID: outcome.itemID,
                itemTitle: outcome.itemTitle,
                artifacts: [],
                presentation: .unavailable,
                status: .failed,
                statusMessage: "文件引用不安全，无法打开系统操作",
                requiresSystemUI: false
            )
            lastLibraryActionStatus = lastLibraryActionOutcome?.statusMessage
        } catch {
            pendingLibraryActionCommand = nil
        }
    }

    private func actionOutcome(
        _ action: MobileLibraryAction,
        item: MobileLibraryItem,
        artifacts: [MobileTaskArtifact],
        presentation: MobileLibraryActionPresentation,
        status: MobileLibraryActionOutcomeStatus,
        statusMessage: String,
        requiresSystemUI: Bool,
        completedRecordMutation: Bool = false
    ) -> MobileLibraryActionOutcome {
        MobileLibraryActionOutcome(
            action: action,
            itemID: item.id,
            itemTitle: item.title,
            artifacts: artifacts,
            presentation: presentation,
            status: status,
            statusMessage: statusMessage,
            requiresSystemUI: requiresSystemUI,
            completedRecordMutation: completedRecordMutation
        )
    }

    private func preferredArtifacts(
        for action: MobileLibraryAction,
        item: MobileLibraryItem
    ) -> [MobileTaskArtifact] {
        switch action {
        case .saveToPhotos:
            return item.artifacts.filter { $0.kind == .renderedVideo || $0.kind == .originalMedia }
        case .share, .saveToFiles:
            return item.artifacts
        case .open:
            if let video = item.artifacts.first(where: { $0.kind == .renderedVideo || $0.kind == .originalMedia }) {
                return [video]
            }
            if let subtitle = item.artifacts.first(where: { $0.kind == .translatedSubtitleFile || $0.kind == .softSubtitle }) {
                return [subtitle]
            }
            return Array(item.artifacts.prefix(1))
        case .deleteRecord, .locateFile:
            return []
        }
    }

    private func unavailableLibraryActionOutcome(
        for action: MobileLibraryAction,
        item: MobileLibraryItem
    ) -> MobileLibraryActionOutcome {
        actionOutcome(
            action,
            item: item,
            artifacts: [],
            presentation: .unavailable,
            status: .unavailable,
            statusMessage: unavailableLibraryActionMessage(for: action, item: item),
            requiresSystemUI: false
        )
    }

    private func missingLibraryActionOutcome(
        action: MobileLibraryAction,
        itemID: String
    ) -> MobileLibraryActionOutcome {
        MobileLibraryActionOutcome(
            action: action,
            itemID: itemID,
            itemTitle: itemID,
            artifacts: [],
            presentation: .unavailable,
            status: .unavailable,
            statusMessage: "未找到记录",
            requiresSystemUI: false
        )
    }

    private func unavailableLibraryActionMessage(
        for action: MobileLibraryAction,
        item: MobileLibraryItem
    ) -> String {
        switch action {
        case .saveToPhotos:
            return "没有可存到照片的视频"
        case .open:
            return "没有可打开的文件"
        case .share:
            return "没有可分享的文件"
        case .saveToFiles:
            return "没有可存储的文件"
        case .locateFile:
            return "当前记录不需要重新定位"
        case .deleteRecord:
            return "当前记录不可删除"
        }
    }

    private func updateDownloadProgress(taskID: String, progress: MobileTaskProgress) async {
        guard let index = queue.firstIndex(where: { $0.id == taskID }) else { return }
        guard queue[index].state == .downloading else { return }
        queue[index].progress = progress
        await persistQueueTask(queue[index])
    }

    private func markDownloadFailed(taskID: String, error: MobileTaskError) async {
        guard let index = queue.firstIndex(where: { $0.id == taskID }) else { return }
        guard queue[index].state == .downloading else { return }
        queue[index].state = .failed
        queue[index].error = error
        lastQueueActionStatus = "下载失败 \(queueDisplayName(queue[index]))"
        await persistQueueTask(queue[index])
    }

    private func exportTranslatedSubtitle(taskID: String) async {
        guard let index = queue.firstIndex(where: { $0.id == taskID }) else {
            lastQueueActionStatus = "未找到任务"
            return
        }
        guard queue[index].state == .completed else {
            await markSubtitleExportFailed(
                taskID: taskID,
                message: "任务完成后才能生成字幕 \(queueDisplayName(queue[index]))"
            )
            return
        }
        guard let subtitleProcessor else {
            await markSubtitleExportFailed(taskID: taskID, message: "此版本暂不能生成该字幕 \(queueDisplayName(queue[index]))")
            return
        }
        guard let sourceSubtitle = queue[index].result?.artifacts.first(where: { $0.kind == .transcript }) else {
            await markSubtitleExportFailed(taskID: taskID, message: "缺少可处理字幕 \(queueDisplayName(queue[index]))")
            return
        }
        let progressBeforeExport = queue[index].progress
        preExportTaskByID[taskID] = queue[index]
        queue[index].state = .translating
        queue[index].error = nil
        queue[index].progress = MobileTaskProgress(phase: .translating, completedUnitCount: 0)
        let displayName = queueDisplayName(queue[index])
        await persistQueueTask(queue[index])

        do {
            let translation = try await translationResult(
                forTaskID: taskID,
                sourceSubtitle: sourceSubtitle
            )
            let artifact = try await subtitleProcessor.process(
                MobileSubtitleProcessingRequest(
                    sourceSubtitle: sourceSubtitle,
                    translation: translation,
                    exportProfile: queue[index].exportProfile
                )
            ) { [weak self] progress in
                Task { @MainActor in
                    await self?.updateSubtitleProgress(taskID: taskID, progress: progress)
                }
            }
            guard let completedIndex = queue.firstIndex(where: { $0.id == taskID }) else { return }
            guard queue[completedIndex].state == .translating else { return }
            var artifacts = queue[completedIndex].result?.artifacts ?? []
            artifacts.removeAll { existing in
                existing.id == artifact.id || existing.kind == artifact.kind
            }
            artifacts.append(artifact)
            queue[completedIndex].state = .completed
            queue[completedIndex].progress = artifact.byteCount.map {
                MobileTaskProgress(phase: .translating, completedUnitCount: $0, totalUnitCount: $0)
            } ?? queue[completedIndex].progress
            queue[completedIndex].result = MobileTaskResult(
                artifacts: artifacts,
                primaryArtifactID: queue[completedIndex].result?.primaryArtifactID ?? artifact.id
            )
            queue[completedIndex].error = nil
            lastQueueActionStatus = artifact.kind == .softSubtitle
                ? "已生成软字幕 \(artifact.displayName)"
                : "已生成字幕 \(artifact.displayName)"
            translationResultByTaskID[taskID] = nil
            preExportTaskByID[taskID] = nil
            appendLibraryRecord(from: queue[completedIndex])
            await persistQueueTask(queue[completedIndex])
        } catch is MobileTranslationProviderError {
            await markSubtitleExportFailed(
                taskID: taskID,
                error: .credentialRequired,
                message: "字幕翻译失败 \(displayName)",
                fallbackProgress: progressBeforeExport,
                requireActiveExport: true
            )
        } catch let error as MobileTaskError {
            await markSubtitleExportFailed(
                taskID: taskID,
                error: error,
                message: "字幕生成失败 \(displayName)",
                fallbackProgress: progressBeforeExport,
                requireActiveExport: true
            )
        } catch {
            await markSubtitleExportFailed(
                taskID: taskID,
                error: .exportFailed,
                message: "字幕生成失败 \(displayName)",
                fallbackProgress: progressBeforeExport,
                requireActiveExport: true
            )
        }
    }

    private func translationResult(
        forTaskID taskID: String,
        sourceSubtitle: MobileTaskArtifact
    ) async throws -> MobileTranslationResult {
        if let translation = translationResultByTaskID[taskID] {
            return translation
        }

        guard let storageDirectoryURL else {
            throw MobileTaskError.exportFailed
        }

        let provider = translationProvider ?? defaultTranslationProvider()
        let sourceURL = try appOwnedSubtitleURL(for: sourceSubtitle.storageIdentifier, in: storageDirectoryURL)
        let raw = try String(contentsOf: sourceURL, encoding: .utf8)
        let context = TranslationContext(
            sourceLanguage: TranslationContext.sourceLanguageIdentifier(fromSubtitleFile: sourceURL),
            targetLanguage: "zh-Hans"
        )
        let request = MobileSubtitleDocument
            .parseSRT(raw)
            .cleanedForTranslation()
            .translationRequest(context: context)
        if Self.canUseSourceSubtitleAsTargetTranslation(context: request.context) {
            return MobileTranslationResult(segments: request.segments)
        }
        let readiness = await provider.readiness(for: request.context)
        guard readiness.isReady else {
            throw MobileTranslationProviderError.missingCredential
        }
        return try await provider.translate(request)
    }

    private func defaultTranslationProvider() -> any MobileTranslationProvider {
        switch translationConfiguration.engine {
        case .appleTranslationLowLatency, .appleTranslationHighFidelity:
            return IOSAppleTranslationMobileProvider(engine: translationConfiguration.engine)
        case .anthropicCompatible,
             .openAICompatible,
             .appleFoundationOnDevice,
             .appleFoundationPCC,
             .appleFoundationCloudPro:
            return APICompatibleMobileTranslationProvider(
                configuration: translationConfiguration,
                credentialStore: credentialStore,
                transport: translationConnectionTransport
            )
        }
    }

    private static func canUseSourceSubtitleAsTargetTranslation(context: TranslationContext) -> Bool {
        guard let sourceLanguage = context.sourceLanguage else {
            return false
        }
        return isSimplifiedChineseLanguage(sourceLanguage)
            && isSimplifiedChineseLanguage(context.targetLanguage)
    }

    private static func isSimplifiedChineseLanguage(_ identifier: String) -> Bool {
        let normalized = identifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        return [
            "zh",
            "zh-cn",
            "zh-hans",
            "cmn",
            "cmn-cn",
            "cmn-hans"
        ].contains(normalized)
    }

    private func appOwnedSubtitleURL(for storageIdentifier: String, in storageDirectoryURL: URL) throws -> URL {
        do {
            return try IOSArtifactStore(storageDirectoryURL: storageDirectoryURL)
                .fileURL(forStorageIdentifier: storageIdentifier)
        } catch IOSArtifactStoreError.unsafeStorageIdentifier {
            throw MobileTaskError.exportFailed
        } catch {
            throw MobileTaskError.exportFailed
        }
    }

    private func updateSubtitleProgress(taskID: String, progress: MobileTaskProgress) async {
        guard let index = queue.firstIndex(where: { $0.id == taskID }) else { return }
        guard queue[index].state == .translating else { return }
        queue[index].progress = progress
        await persistQueueTask(queue[index])
    }

    private func markSubtitleExportFailed(
        taskID: String,
        error: MobileTaskError = .exportFailed,
        message: String,
        fallbackProgress: MobileTaskProgress? = nil,
        requireActiveExport: Bool = false
    ) async {
        guard let index = queue.firstIndex(where: { $0.id == taskID }) else { return }
        guard !requireActiveExport || queue[index].state == .translating else { return }
        if let previous = preExportTaskByID[taskID] {
            queue[index] = previous
            queue[index].error = error
            if let fallbackProgress {
                queue[index].progress = fallbackProgress
            }
        } else if queue[index].result?.primaryArtifact != nil {
            queue[index].state = .completed
            if let fallbackProgress {
                queue[index].progress = fallbackProgress
            }
        } else {
            queue[index].state = .failed
        }
        queue[index].error = error
        if queue[index].state == .completed,
           queue[index].result?.primaryArtifact != nil {
            appendLibraryRecord(from: queue[index])
        }
        lastQueueActionStatus = message
        preExportTaskByID[taskID] = nil
        await persistQueueTask(queue[index])
    }

    private func exportRenderedVideo(taskID: String) async {
        guard let index = queue.firstIndex(where: { $0.id == taskID }) else {
            lastQueueActionStatus = "未找到任务"
            return
        }
        guard queue[index].state != .exporting else {
            lastQueueActionStatus = "正在导出 \(queueDisplayName(queue[index]))"
            return
        }
        guard queue[index].state == .completed else {
            lastQueueActionStatus = renderBlockedMessage(
                for: MobileRenderRequestPlan(status: .blocked, blockedReason: .taskNotCompleted),
                task: queue[index]
            )
            return
        }
        guard let renderExporter else {
            await markRenderExportFailed(taskID: taskID, message: "此版本暂不能导出带字幕视频 \(queueDisplayName(queue[index]))")
            return
        }

        let plan = MobileRenderRequestPlanner().plan(for: queue[index])
        guard plan.status == .ready, let request = plan.request else {
            await markRenderExportFailed(taskID: taskID, message: renderBlockedMessage(for: plan, task: queue[index]))
            return
        }

        let iosRenderPlan = IOSRenderRequestPlanner(
            capabilities: queue[index].capabilities,
            runtime: renderRuntimeCapabilities
        ).plan(request)
        let backgroundPolicy = await backgroundPolicyForRenderExport(
            plan: iosRenderPlan,
            taskID: taskID
        )
        let progressBeforeExport = queue[index].progress
        preExportTaskByID[taskID] = queue[index]
        queue[index].state = .exporting
        queue[index].error = nil
        queue[index].progress = MobileTaskProgress(phase: .exporting, completedUnitCount: 0)
        queue[index].backgroundPolicy = backgroundPolicy
        let displayName = queueDisplayName(queue[index])
        await persistQueueTask(queue[index])
        if backgroundPolicy.execution == .continuedProcessing {
            lastQueueActionStatus = "已交给系统后台导出 \(displayName)"
            return
        }

        do {
            let renderedResult = try await renderExporter.export(request) { [weak self] progress in
                Task { @MainActor in
                    await self?.updateRenderProgress(taskID: taskID, progress: progress)
                }
            }
            guard let completedIndex = queue.firstIndex(where: { $0.id == taskID }) else { return }
            guard queue[completedIndex].state == .exporting else { return }
            let previousPrimaryID = queue[completedIndex].result?.primaryArtifactID
            var artifacts = queue[completedIndex].result?.artifacts ?? []
            artifacts.removeAll { existing in
                renderedResult.artifacts.contains { $0.id == existing.id } ||
                    existing.kind == .renderedVideo
            }
            artifacts.append(contentsOf: renderedResult.artifacts)
            let primaryID = renderedResult.primaryArtifactID ?? previousPrimaryID
            queue[completedIndex].state = .completed
            queue[completedIndex].progress = renderedResult.primaryArtifact?.byteCount.map {
                MobileTaskProgress(phase: .exporting, completedUnitCount: $0, totalUnitCount: $0)
            } ?? queue[completedIndex].progress
            queue[completedIndex].result = MobileTaskResult(
                artifacts: artifacts,
                primaryArtifactID: primaryID
            )
            queue[completedIndex].error = nil
            lastQueueActionStatus = renderedResult.primaryArtifact
                .map { "已导出视频 \($0.displayName)" } ?? "已导出视频 \(displayName)"
            preExportTaskByID[taskID] = nil
            appendLibraryRecord(from: queue[completedIndex])
            await persistQueueTask(queue[completedIndex])
        } catch let error as MobileTaskError {
            await markRenderExportFailed(
                taskID: taskID,
                error: error,
                message: "视频导出失败 \(displayName)",
                fallbackProgress: progressBeforeExport,
                requireActiveExport: true
            )
        } catch {
            await markRenderExportFailed(
                taskID: taskID,
                error: .exportFailed,
                message: "视频导出失败 \(displayName)",
                fallbackProgress: progressBeforeExport,
                requireActiveExport: true
            )
        }
    }

    private func backgroundPolicyForRenderExport(
        plan: IOSRenderPlan,
        taskID: String
    ) async -> MobileBackgroundPolicy {
        guard plan.backgroundPolicy.execution == .continuedProcessing,
              let continuedProcessingSubmitter else {
            return MobileBackgroundPolicy(
                execution: .foregroundRequired,
                resumability: .nonResumable,
                limits: [.foregroundRequired, .notResumable]
            )
        }

        do {
            let descriptor = try continuedProcessingScheduler.makeRequestDescriptor(for: plan, taskID: taskID)
            try await continuedProcessingSubmitter.submit(descriptor)
            return plan.backgroundPolicy
        } catch {
            return MobileBackgroundPolicy(
                execution: .foregroundRequired,
                resumability: .nonResumable,
                limits: [.foregroundRequired, .notResumable]
            )
        }
    }

    private func updateRenderProgress(taskID: String, progress: MobileTaskProgress) async {
        guard let index = queue.firstIndex(where: { $0.id == taskID }) else { return }
        guard queue[index].state == .exporting else { return }
        queue[index].progress = progress
        await persistQueueTask(queue[index])
    }

    private func markRenderExportFailed(
        taskID: String,
        error: MobileTaskError = .exportFailed,
        message: String,
        fallbackProgress: MobileTaskProgress? = nil,
        requireActiveExport: Bool = false
    ) async {
        guard let index = queue.firstIndex(where: { $0.id == taskID }) else { return }
        guard !requireActiveExport || queue[index].state == .exporting else { return }
        if let previous = preExportTaskByID[taskID] {
            queue[index] = previous
            queue[index].error = error
            if let fallbackProgress {
                queue[index].progress = fallbackProgress
            }
        } else if queue[index].result?.primaryArtifact != nil {
            queue[index].state = .completed
            if let fallbackProgress {
                queue[index].progress = fallbackProgress
            }
        } else {
            queue[index].state = .failed
        }
        queue[index].error = error
        if queue[index].state == .completed,
           queue[index].result?.primaryArtifact != nil {
            appendLibraryRecord(from: queue[index])
        }
        lastQueueActionStatus = message
        preExportTaskByID[taskID] = nil
        await persistQueueTask(queue[index])
    }

    private func renderBlockedMessage(
        for plan: MobileRenderRequestPlan,
        task: MobileTaskSnapshot
    ) -> String {
        switch plan.blockedReason {
        case .taskNotCompleted:
            return "任务完成后才能导出视频 \(queueDisplayName(task))"
        case .unsupportedExportProfile:
            return "当前设备不支持这个视频导出设置 \(queueDisplayName(task))"
        case .missingSourceMedia:
            return "缺少原视频，无法导出 \(queueDisplayName(task))"
        case .missingSubtitle:
            return "缺少可烧录字幕，无法导出 \(queueDisplayName(task))"
        case nil:
            return "视频导出尚不可用 \(queueDisplayName(task))"
        }
    }

    private func persistQueueTask(_ task: MobileTaskSnapshot) async {
        do {
            try await taskRepository?.saveTask(sanitizedPersistedTask(task))
        } catch {
            lastQueueActionStatus = "保存队列失败 \(queueDisplayName(task))"
        }
    }

    private func sanitizedPersistedTask(_ task: MobileTaskSnapshot) -> MobileTaskSnapshot {
        guard let result = task.result else {
            return task
        }

        var sanitized = task
        sanitized.result = MobileTaskResult(
            artifacts: result.artifacts.map { sanitizedSourceArtifact($0, taskID: task.id) },
            primaryArtifactID: result.primaryArtifactID
        )
        return sanitized
    }

    private func resultByMergingExistingProcessableArtifacts(
        into downloadResult: MobileTaskResult,
        from existingResult: MobileTaskResult?
    ) -> MobileTaskResult {
        guard let existingResult else {
            return downloadResult
        }

        let retainedArtifacts = existingResult.artifacts.filter { artifact in
            artifact.kind == .transcript || artifact.kind == .translatedSubtitleFile
        }
        guard !retainedArtifacts.isEmpty else {
            return downloadResult
        }

        var artifacts = downloadResult.artifacts
        for artifact in retainedArtifacts where !artifacts.contains(where: { $0.id == artifact.id }) {
            artifacts.append(artifact)
        }
        return MobileTaskResult(
            artifacts: artifacts,
            primaryArtifactID: downloadResult.primaryArtifactID
        )
    }

    private func sanitizedSourceArtifact(_ artifact: MobileTaskArtifact, taskID: String) -> MobileTaskArtifact {
        guard artifact.storageIdentifier.hasPrefix("source:") else {
            return artifact
        }

        var copy = artifact
        copy.storageIdentifier = Self.sourceReferenceStorageIdentifier(for: taskID)
        return copy
    }

    private func copyRelocatedLibraryArtifact(
        from sourceURL: URL,
        replacing artifact: MobileTaskArtifact,
        sourceTaskID: String,
        storageDirectoryURL: URL
    ) -> MobileTaskArtifact? {
        guard sourceURL.isFileURL,
              let fileName = safeRelocatedLibraryFileName(sourceURL.lastPathComponent) else {
            return nil
        }

        let storageIdentifier = relocatedLibraryStorageIdentifier(
            sourceTaskID: sourceTaskID,
            artifactID: artifact.id,
            fileName: fileName
        )
        let artifactStore = IOSArtifactStore(storageDirectoryURL: storageDirectoryURL)
        guard let destinationURL = try? artifactStore.fileURL(forStorageIdentifier: storageIdentifier) else {
            return nil
        }

        do {
            try IOSAppStoragePolicy.applyDirectoryPolicy(to: destinationURL.deletingLastPathComponent())
            let sourcePath = sourceURL.standardizedFileURL.path
            let destinationPath = destinationURL.standardizedFileURL.path
            if sourcePath != destinationPath {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                if sourcePath.hasPrefix(storageDirectoryURL.standardizedFileURL.path + "/") {
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                } else {
                    try importedFileAccessor.withAccess(to: sourceURL) {
                        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                    }
                }
            }
            try IOSAppStoragePolicy.applyFilePolicy(to: destinationURL)
            return MobileTaskArtifact(
                id: artifact.id,
                kind: artifact.kind,
                displayName: fileName,
                storageIdentifier: storageIdentifier,
                byteCount: storedByteCount(at: destinationURL)
            )
        } catch {
            return nil
        }
    }

    private func replacingArtifact(
        _ artifactID: String,
        in artifacts: [MobileTaskArtifact],
        with replacement: MobileTaskArtifact
    ) -> [MobileTaskArtifact] {
        var updated = artifacts.filter { $0.id != artifactID }
        updated.insert(replacement, at: 0)
        return updated
    }

    private func relocatedProgressPhase(for artifact: MobileTaskArtifact) -> MobileTaskPhase {
        switch artifact.kind {
        case .translatedSubtitleFile, .transcript:
            return .translating
        case .renderedVideo:
            return .exporting
        case .originalMedia, .metadata, .softSubtitle:
            return .downloading
        }
    }

    private func safeRelocatedLibraryFileName(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != ".",
              trimmed != "..",
              !trimmed.contains("/"),
              !trimmed.contains("\\") else {
            return nil
        }
        let lowercased = trimmed.lowercased()
        let unsafeMarkers = [
            "access_token",
            "authorization",
            "bearer ",
            "cookie",
            "x-amz-signature",
            "secret_token"
        ]
        guard !unsafeMarkers.contains(where: { lowercased.contains($0) }) else {
            return nil
        }
        return trimmed
    }

    private func relocatedLibraryStorageIdentifier(
        sourceTaskID: String,
        artifactID: String,
        fileName: String
    ) -> String {
        let baseName = (fileName as NSString).deletingPathExtension
        let pathExtension = (fileName as NSString).pathExtension
        let safeName = safeSubtitleIdentifierComponent(baseName)
        let suffix = pathExtension.isEmpty ? "" : ".\(pathExtension.lowercased())"
        return "Downloads/\(safeSubtitleIdentifierComponent(sourceTaskID))-\(safeSubtitleIdentifierComponent(artifactID))-\(safeName)\(suffix)"
    }

    private func safeImportedVideoFileName(_ value: String) -> String? {
        guard let fileName = safeRelocatedLibraryFileName(value) else {
            return nil
        }
        return isSupportedImportedVideoFileName(fileName) ? fileName : nil
    }

    private func isSupportedImportedVideoFileName(_ fileName: String) -> Bool {
        switch fileName.lowercased().split(separator: ".").last {
        case "mp4", "mov", "m4v", "webm":
            return true
        default:
            return false
        }
    }

    private func importedVideoStorageIdentifier(fileName: String) -> String {
        let baseName = (fileName as NSString).deletingPathExtension
        let pathExtension = (fileName as NSString).pathExtension.lowercased()
        let safeName = safeSubtitleIdentifierComponent(baseName)
        let suffix = pathExtension.isEmpty ? "" : ".\(pathExtension)"
        return "Downloads/import-\(safeSubtitleIdentifierComponent(UUID().uuidString))-\(safeName)\(suffix)"
    }

    private func isSupportedSubtitleFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "srt" && url.isFileURL
    }

    private func safeImportedSubtitleFileName(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != ".",
              trimmed != "..",
              !trimmed.contains("/"),
              !trimmed.contains("\\"),
              (trimmed as NSString).pathExtension.lowercased() == "srt" else {
            return nil
        }
        let lowercased = trimmed.lowercased()
        let unsafeMarkers = [
            "access_token",
            "authorization",
            "bearer ",
            "cookie",
            "x-amz-signature",
            "secret_token"
        ]
        guard !unsafeMarkers.contains(where: { lowercased.contains($0) }) else {
            return nil
        }
        return trimmed
    }

    private func importedSubtitleStorageFileName(
        taskID: String,
        subtitleID: String,
        fileName: String
    ) -> String {
        let baseName = (fileName as NSString).deletingPathExtension
        let pathExtension = (fileName as NSString).pathExtension.lowercased()
        return "\(safeSubtitleIdentifierComponent(taskID))-\(safeSubtitleIdentifierComponent(subtitleID))-\(safeSubtitleIdentifierComponent(baseName)).\(pathExtension)"
    }

    private func normalizedSubtitleLanguageCode(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "und" : trimmed
    }

    private func safeSubtitleIdentifierComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "subtitle" : collapsed
    }

    private func storedByteCount(at url: URL) -> Int? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[FileAttributeKey.size] as? NSNumber else {
            return nil
        }
        return size.intValue
    }

    private func removeQueueTask(_ taskID: String) async {
        do {
            try await taskRepository?.removeTask(id: taskID)
        } catch {
            lastQueueActionStatus = "移除队列记录失败"
        }
    }

    private func appendLibraryRecord(from task: MobileTaskSnapshot) {
        guard let result = task.result,
              let primaryArtifact = result.primaryArtifact else {
            return
        }
        let item = MobileLibraryItem(
            id: "library-\(task.id)",
            title: primaryArtifact.displayName,
            createdAt: Date(),
            artifacts: result.artifacts,
            state: libraryState(for: result),
            sourceTaskID: task.id
        )
        library.removeAll { $0.id == item.id || $0.sourceTaskID == task.id }
        library.insert(item, at: 0)
    }

    private func libraryState(for result: MobileTaskResult) -> MobileLibraryState {
        guard let primaryArtifact = result.primaryArtifact else {
            return .fileMissing
        }
        guard let storageDirectoryURL else {
            return .available
        }
        let artifactStore = IOSArtifactStore(storageDirectoryURL: storageDirectoryURL)
        guard let primaryURL = try? artifactStore.fileURL(for: primaryArtifact),
              FileManager.default.fileExists(atPath: primaryURL.path) else {
            return .fileMissing
        }
        return .available
    }

    private func restoredTaskSnapshot(_ task: MobileTaskSnapshot) -> MobileTaskSnapshot {
        guard Self.isRunningWorkState(task.state) else {
            return task
        }

        var restored = task
        restored.state = .needsForegroundToContinue
        restored.error = .systemBackgroundLimit
        let isNonResumable = task.backgroundPolicy.resumability == .nonResumable ||
            task.backgroundPolicy.limits.contains(.notResumable)
        var limits = task.backgroundPolicy.limits.filter { $0 != .systemInterrupted && $0 != .notResumable }
        limits.append(.systemInterrupted)
        if isNonResumable {
            limits.append(.notResumable)
        }
        restored.backgroundPolicy = MobileBackgroundPolicy(
            execution: .systemInterrupted,
            resumability: isNonResumable ? .nonResumable : .resumable,
            systemTimeLimitSeconds: task.backgroundPolicy.systemTimeLimitSeconds,
            limits: limits
        )
        return restored
    }

    private func taskSnapshot(
        _ task: MobileTaskSnapshot,
        applying outcome: BackgroundTransferRecoveryOutcome
    ) -> MobileTaskSnapshot {
        var restored = task
        restored.progress = outcome.progress
        restored.backgroundPolicy = outcome.backgroundPolicy

        switch outcome.status {
        case .completed:
            restored.state = .completed
            restored.result = outcome.result ?? task.result
            restored.error = nil
            sourceURLByTaskID[task.id] = nil
        case .failed:
            restored.state = .failed
            restored.error = outcome.error ?? .unknown
        case .expired:
            restored.state = .needsForegroundToContinue
            restored.error = outcome.error ?? .systemBackgroundLimit
            if !restored.backgroundPolicy.limits.contains(.systemInterrupted) {
                restored.backgroundPolicy.limits.append(.systemInterrupted)
            }
            restored.backgroundPolicy.execution = .systemInterrupted
        }

        return restored
    }

    private func restoreLegacySourceURLIfNeeded(_ task: MobileTaskSnapshot) -> MobileTaskSnapshot {
        guard let result = task.result else {
            return task
        }

        var artifacts = result.artifacts
        var didMigrateSourceURL = false
        for index in artifacts.indices {
            guard artifacts[index].storageIdentifier.hasPrefix("source:") else {
                continue
            }

            artifacts[index] = sanitizedSourceArtifact(artifacts[index], taskID: task.id)
            didMigrateSourceURL = true
        }

        guard didMigrateSourceURL else {
            return task
        }

        var migrated = task
        migrated.result = MobileTaskResult(
            artifacts: artifacts,
            primaryArtifactID: result.primaryArtifactID
        )
        return migrated
    }

    private static func isRunningWorkState(_ state: MobileTaskState) -> Bool {
        switch state {
        case .downloading, .translating, .exporting:
            return true
        case .waiting, .analyzing, .ready, .needsForegroundToContinue, .completed, .failed, .cancelled:
            return false
        }
    }

    private func phaseState(for phase: MobileTaskPhase) -> MobileTaskState {
        switch phase {
        case .waiting:
            return .waiting
        case .analyzing:
            return .analyzing
        case .downloading:
            return .downloading
        case .translating:
            return .translating
        case .exporting:
            return .exporting
        }
    }
}

private struct ActiveQueueTask {
    var token: UUID
    var task: Task<Void, Never>
}

private enum IOSMobilePreviewData {
    static let candidate = MobileVideoCandidate(
        id: "candidate-hls",
        sourceURL: "https://example.com/video.m3u8",
        kind: .hlsStream,
        title: "产品发布片段"
    )

    static let addSession = MobileAddSessionSnapshot(
        id: "add-preview",
        input: MobileInputSource(kind: .pastedURL, value: "https://example.com/video.m3u8"),
        state: .ready,
        candidates: [candidate],
        selectedCandidateID: "candidate-hls",
        videoInfo: MobileVideoInfo(
            candidate: candidate,
            videoID: "launch-clip",
            title: "产品发布片段",
            durationSeconds: 94,
            formats: [
                MobileFormatChoice(id: "1080p", label: "1080p", detail: "HLS", height: 1080),
                MobileFormatChoice(id: "720p", label: "720p", detail: "HLS", height: 720)
            ],
            subtitles: [
                MobileSubtitleChoice(id: "en", languageCode: "en", label: "English", isAutoGenerated: false),
                MobileSubtitleChoice(id: "zh-Hans-auto", languageCode: "zh-Hans", label: "简体中文自动字幕", isAutoGenerated: true)
            ]
        )
    )

    static let translationConfiguration = MobileTranslationConfiguration(
        engine: .openAICompatible,
        baseURL: "https://api.openai.com",
        model: "gpt-5-mini",
        credential: nil,
        readiness: TranslationReadiness(issues: [
            TranslationReadinessIssue(kind: .needsConfiguration, message: "连接 Keychain 后可保存 API key 并测试翻译。")
        ])
    )

    static let appleIntelligenceStatuses: [IOSAppleIntelligenceStatus] = [
        IOSAppleIntelligenceStatus(
            route: .onDevice,
            readiness: TranslationReadiness(issues: [
                TranslationReadinessIssue(kind: .appleIntelligenceUnavailable),
                TranslationReadinessIssue(kind: .modelUnavailable)
            ]),
            detail: "使用 Foundation Models 本地模型；需要 iOS 26+、支持 Apple Intelligence 的设备、已启用系统设置和已就绪模型。"
        ),
        IOSAppleIntelligenceStatus(
            route: .privateCloud,
            readiness: TranslationReadiness(issues: [
                TranslationReadinessIssue(kind: .pccUnavailable)
            ]),
            detail: "Apple Intelligence 云端能力暂不可用；可以先改用 API 兼容引擎。"
        ),
        IOSAppleIntelligenceStatus(
            route: .privateCloudPro,
            readiness: TranslationReadiness(issues: [
                TranslationReadinessIssue(
                    kind: .pccUnavailable,
                    message: "Apple Intelligence Cloud Pro（云端 Pro）当前不可用。"
                )
            ]),
            detail: "云端 Pro 暂不可用；可以先改用 API 兼容引擎。"
        )
    ]

    static let queue: [MobileTaskSnapshot] = [
        MobileTaskSnapshot(
            id: "download-1",
            platform: .iOS,
            state: .downloading,
            progress: MobileTaskProgress(phase: .downloading, completedUnitCount: 42, totalUnitCount: 100),
            exportProfile: MobileExportProfile(subtitleMode: .translatedSubtitleFile),
            capabilities: MobileProcessingCapabilities(
                platform: .iOS,
                supportedCapabilities: [.download, .subtitleExport]
            ),
            backgroundPolicy: MobileBackgroundPolicy(
                execution: .foregroundRequired,
                resumability: .nonResumable,
                limits: [.foregroundRequired, .notResumable]
            )
        ),
        MobileTaskSnapshot(
            id: "render-foreground",
            platform: .iOS,
            state: .needsForegroundToContinue,
            progress: MobileTaskProgress(phase: .exporting, completedUnitCount: 3, totalUnitCount: 8),
            exportProfile: MobileExportProfile(subtitleMode: .burnedInSubtitle, maxRenderHeight: 1080),
            capabilities: MobileProcessingCapabilities(
                platform: .iOS,
                supportedCapabilities: [.subtitleExport, .videoRender],
                maxRenderHeight: 1080
            ),
            backgroundPolicy: MobileBackgroundPolicy(
                execution: .systemInterrupted,
                resumability: .resumable,
                systemTimeLimitSeconds: 30,
                limits: [.systemInterrupted]
            ),
            error: .systemBackgroundLimit
        ),
        MobileTaskSnapshot(
            id: "subtitle-failed",
            platform: .iOS,
            state: .failed,
            exportProfile: MobileExportProfile(subtitleMode: .translatedSubtitleFile),
            error: .credentialRequired
        ),
        MobileTaskSnapshot(
            id: "completed-1",
            platform: .iOS,
            state: .completed,
            exportProfile: MobileExportProfile(subtitleMode: .translatedSubtitleFile),
            result: MobileTaskResult(artifacts: [
                MobileTaskArtifact(
                    id: "completed-video",
                    kind: .renderedVideo,
                    displayName: "产品发布片段.mp4",
                    storageIdentifier: "queue/completed-video.mp4"
                )
            ], primaryArtifactID: "completed-video")
        )
    ]

    static let library: [MobileLibraryItem] = [
        MobileLibraryItem(
            id: "library-1",
            title: "产品发布片段",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            artifacts: [
                MobileTaskArtifact(
                    id: "video",
                    kind: .renderedVideo,
                    displayName: "产品发布片段（中文字幕）.mp4",
                    storageIdentifier: "library/launch-rendered.mp4",
                    byteCount: 24_000_000
                ),
                MobileTaskArtifact(
                    id: "subtitle",
                    kind: .translatedSubtitleFile,
                    displayName: "产品发布片段.zh-Hans.srt",
                    storageIdentifier: "library/launch.zh-Hans.srt",
                    byteCount: 12_400
                )
            ],
            state: .available,
            sourceTaskID: "download-1"
        )
    ]
}

public struct IOSUnsupportedMobileParser: MobileParser {
    public init() {}

    public func resolveCandidates(for input: MobileInputSource) async throws -> [MobileVideoCandidate] {
        let trimmed = input.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = URL(string: trimmed)?.host ?? "移动端暂不支持的来源"
        return [
            MobileVideoCandidate(
                id: "unsupported-\(abs(trimmed.hashValue))",
                sourceURL: trimmed,
                kind: .webPageVideo,
                title: title,
                detail: "手机端目前只支持直接视频文件链接；网页链接可先在桌面端解析。",
                unsupportedReason: .requiresDesktopExtractor
            )
        ]
    }

    public func analyze(candidate: MobileVideoCandidate) async throws -> MobileVideoInfo {
        throw IOSMobileParserError.unsupported
    }
}

private enum IOSMobileParserError: Error {
    case unsupported
}

public struct IOSDirectMediaMobileParser: MobileParser {
    private static let supportedVideoExtensions: Set<String> = ["m4v", "mov", "mp4", "webm"]

    public init() {}

    public func resolveCandidates(for input: MobileInputSource) async throws -> [MobileVideoCandidate] {
        let trimmed = input.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = Self.safeDirectMediaURL(from: trimmed) else {
            return try await IOSUnsupportedMobileParser().resolveCandidates(for: input)
        }

        return [
            MobileVideoCandidate(
                id: "direct-\(abs(trimmed.hashValue))",
                sourceURL: trimmed,
                kind: .directFile,
                title: Self.title(for: url),
                detail: "直接 HTTPS 媒体文件"
            )
        ]
    }

    public func analyze(candidate: MobileVideoCandidate) async throws -> MobileVideoInfo {
        guard candidate.kind == .directFile,
              let url = Self.safeDirectMediaURL(from: candidate.sourceURL) else {
            throw IOSMobileParserError.unsupported
        }

        let fileExtension = url.pathExtension.lowercased()
        return MobileVideoInfo(
            candidate: candidate,
            videoID: "direct-\(abs(candidate.sourceURL.hashValue))",
            title: candidate.title,
            formats: [
                MobileFormatChoice(
                    id: fileExtension,
                    label: fileExtension.uppercased(),
                    detail: "直接文件下载"
                )
            ]
        )
    }

    private static func safeDirectMediaURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == value,
              let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              components.host?.isEmpty == false,
              components.fragment == nil,
              let path = components.percentEncodedPath.removingPercentEncoding,
              supportedVideoExtensions.contains((path as NSString).pathExtension.lowercased()) else {
            return nil
        }
        return components.url
    }

    private static func title(for url: URL) -> String {
        let lastPathComponent = url.deletingPathExtension().lastPathComponent
        if !lastPathComponent.isEmpty {
            return lastPathComponent
        }
        return url.host ?? "直接媒体文件"
    }
}
