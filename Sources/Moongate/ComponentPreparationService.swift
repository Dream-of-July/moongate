import Foundation
#if canImport(MoongateCore)
import MoongateCore
#endif

/// UI-neutral actions. They intentionally name a concrete operation rather
/// than exposing a catch-all "repair" action.
public enum ComponentPreparationOperation: String, CaseIterable, Hashable, Sendable {
    case refresh
    case installRuntime
    case installManagedModel
    case removeManagedRuntime
    case removeManagedModel
    case openExistingDependencySetup
    case openSystemSettings
}

/// A Sendable value copy of the existing download-chain check. This lets the
/// preparation center run its inspection away from SwiftUI's render path.
public struct ComponentPreparationToolchainEntry: Equatable, Sendable {
    public let id: String
    public let formula: String
    public let purpose: String
    public let isInstalled: Bool
    public let isRequired: Bool
    public let installationURL: URL?

    public init(
        id: String,
        formula: String,
        purpose: String,
        isInstalled: Bool,
        isRequired: Bool,
        installationURL: URL? = nil
    ) {
        self.id = id
        self.formula = formula
        self.purpose = purpose
        self.isInstalled = isInstalled
        self.isRequired = isRequired
        self.installationURL = installationURL
    }
}

public typealias ComponentPreparationToolchainInspector = @Sendable () -> [ComponentPreparationToolchainEntry]

/// A renderable component snapshot. `component` retains the platform-neutral
/// catalog contract while this type adds local-storage and allowed-action data.
public struct ComponentPreparationItem: Identifiable, Equatable, Sendable {
    public let component: Component
    public let sourceDetail: String
    public let actualDiskUsageBytes: Int64?
    public let storageURL: URL?
    public let failureReason: String?
    public let allowedOperations: [ComponentPreparationOperation]

    public init(
        component: Component,
        sourceDetail: String,
        actualDiskUsageBytes: Int64? = nil,
        storageURL: URL? = nil,
        failureReason: String? = nil,
        allowedOperations: [ComponentPreparationOperation]
    ) {
        self.component = component
        self.sourceDetail = sourceDetail
        self.actualDiskUsageBytes = actualDiskUsageBytes
        self.storageURL = storageURL
        self.failureReason = failureReason ?? Self.defaultFailureReason(for: component.readiness)
        self.allowedOperations = allowedOperations
    }

    public var id: String { component.id }
    public var displayName: String { component.displayName }
    public var kind: ComponentKind { component.kind }
    public var source: ComponentSource { component.source }
    public var installPolicy: ComponentInstallPolicy { component.installPolicy }
    public var capabilities: [ComponentCapability] { component.capabilities }
    public var isOptional: Bool { component.isOptional }
    public var declaredSizeBytes: Int64? { component.sizeBytes }
    public var version: String? { component.version }
    public var readiness: ComponentReadiness { component.readiness }

    private static func defaultFailureReason(for readiness: ComponentReadiness) -> String? {
        switch readiness.status {
        case .unavailable, .corrupted:
            readiness.detail
        case .unknown, .ready, .missing:
            nil
        }
    }
}

public struct ComponentPreparationSnapshot: Equatable, Sendable {
    public let items: [ComponentPreparationItem]
    public let refreshedAt: Date

    public init(items: [ComponentPreparationItem], refreshedAt: Date = Date()) {
        self.items = items
        self.refreshedAt = refreshedAt
    }

    public func item(id: String) -> ComponentPreparationItem? {
        items.first { $0.id == id }
    }
}

/// The preparation center is shared by onboarding and Settings, but has no UI
/// dependency. Managed model checks happen in a utility task and are cached by
/// file fingerprint so large models are not repeatedly hashed by view updates.
public actor ComponentPreparationService {
    private let configuration: ComponentPreparationConfiguration
    private var modelStatusCache: [ComponentPreparationModelCacheKey: ComponentPreparationCachedModelStatus] = [:]
    private var latestSnapshot: ComponentPreparationSnapshot?

    public init(
        runtimeDirectoryURL: URL? = nil,
        runtimeLocator: ASRRuntimeLocator? = nil,
        runtimeDownloadManifest: ASRRuntimeDownloadManifest? = nil,
        whisperManifest: ASRModelManifest = .recommendedWhisperCpp,
        vadManifest: ASRModelManifest = .recommendedWhisperCppVAD,
        whisperModelStoreURL: URL? = nil,
        vadModelStoreURL: URL? = nil,
        toolchainInspector: ComponentPreparationToolchainInspector? = nil
    ) {
        let supportDirectory = AppSettings.supportDirectory
        let resolvedRuntimeDirectory = (runtimeDirectoryURL ?? supportDirectory
            .appendingPathComponent("asr", isDirectory: true)
            .appendingPathComponent("runtime", isDirectory: true))
            .standardizedFileURL
        let resolvedWhisperStore = (whisperModelStoreURL ?? supportDirectory
            .appendingPathComponent("asr", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true))
            .standardizedFileURL
        let resolvedVADStore = (vadModelStoreURL ?? supportDirectory
            .appendingPathComponent("asr", isDirectory: true)
            .appendingPathComponent("vad", isDirectory: true))
            .standardizedFileURL
        var runtimeSearchURLs = [resolvedRuntimeDirectory]
        let configuredRuntimePath = AppSettings.load(readCredentials: false)
            .localASRRuntimePath
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !configuredRuntimePath.isEmpty {
            runtimeSearchURLs.append(URL(fileURLWithPath: configuredRuntimePath))
        }
        if let bundledRuntimeURL = Bundle.main.resourceURL?
            .appendingPathComponent("asr", isDirectory: true)
            .appendingPathComponent("runtime", isDirectory: true) {
            runtimeSearchURLs.append(bundledRuntimeURL)
            runtimeSearchURLs.append(bundledRuntimeURL.appendingPathComponent("bin", isDirectory: true))
        }
        let resolvedRuntimeLocator = runtimeLocator ?? ASRRuntimeLocator(
            extraSearchURLs: runtimeSearchURLs
        )

        self.configuration = ComponentPreparationConfiguration(
            runtimeDirectoryURL: resolvedRuntimeDirectory,
            runtimeLocator: resolvedRuntimeLocator,
            runtimeDownloadManifest: runtimeDownloadManifest,
            whisperManifest: whisperManifest,
            vadManifest: vadManifest,
            whisperModelStoreURL: resolvedWhisperStore,
            vadModelStoreURL: resolvedVADStore,
            toolchainInspector: toolchainInspector ?? Self.defaultToolchainInspector
        )
    }

    /// Gives the UI a stable last result without another checksum pass.
    public func cachedSnapshot() -> ComponentPreparationSnapshot? {
        latestSnapshot
    }

    /// Call after an installer or user-managed file operation completes.
    public func invalidateReadinessCache() {
        modelStatusCache.removeAll()
        latestSnapshot = nil
    }

    /// Performs a cache-aware readiness refresh outside the UI actor.
    public func refresh() async -> ComponentPreparationSnapshot {
        let configuration = configuration
        let cache = modelStatusCache
        let result = await Task.detached(priority: .utility) {
            ComponentPreparationSnapshotBuilder.build(
                configuration: configuration,
                modelStatusCache: cache
            )
        }.value
        modelStatusCache = result.modelStatusCache
        latestSnapshot = result.snapshot
        return result.snapshot
    }

    private static let defaultToolchainInspector: ComponentPreparationToolchainInspector = {
        #if !os(Windows)
        DependencySetup.check().map {
            ComponentPreparationToolchainEntry(
                id: $0.id,
                formula: $0.formula,
                purpose: $0.purpose,
                isInstalled: $0.isInstalled,
                isRequired: $0.isRequired,
                installationURL: $0.installPath.map { URL(fileURLWithPath: $0) }
            )
        }
        #else
        []
        #endif
    }
}

private struct ComponentPreparationConfiguration: Sendable {
    let runtimeDirectoryURL: URL
    let runtimeLocator: ASRRuntimeLocator
    let runtimeDownloadManifest: ASRRuntimeDownloadManifest?
    let whisperManifest: ASRModelManifest
    let vadManifest: ASRModelManifest
    let whisperModelStoreURL: URL
    let vadModelStoreURL: URL
    let toolchainInspector: ComponentPreparationToolchainInspector
}

private struct ComponentPreparationModelCacheKey: Hashable, Sendable {
    let role: String
    let modelID: String
    let expectedSHA256: String
}

private struct ComponentPreparationFileFingerprint: Equatable, Sendable {
    let exists: Bool
    let sizeBytes: Int64?
    let modifiedAt: TimeInterval?

    init(url: URL, fileManager: FileManager = .default) {
        guard fileManager.fileExists(atPath: url.path) else {
            exists = false
            sizeBytes = nil
            modifiedAt = nil
            return
        }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        exists = true
        if let fileSize = values?.fileSize {
            sizeBytes = Int64(fileSize)
        } else {
            sizeBytes = nil
        }
        modifiedAt = values?.contentModificationDate?.timeIntervalSince1970
    }
}

private struct ComponentPreparationCachedModelStatus: Sendable {
    let fingerprint: ComponentPreparationFileFingerprint
    let status: ASRModelStatus
}

private struct ComponentPreparationRefreshResult: Sendable {
    let snapshot: ComponentPreparationSnapshot
    let modelStatusCache: [ComponentPreparationModelCacheKey: ComponentPreparationCachedModelStatus]
}

private enum ComponentPreparationSnapshotBuilder {
    static func build(
        configuration: ComponentPreparationConfiguration,
        modelStatusCache: [ComponentPreparationModelCacheKey: ComponentPreparationCachedModelStatus]
    ) -> ComponentPreparationRefreshResult {
        var cache = modelStatusCache
        var items: [ComponentPreparationItem] = [
            toolchainItem(using: configuration.toolchainInspector()),
            runtimeItem(configuration: configuration),
        ]
        items.append(contentsOf: managedModelItems(
            manifest: configuration.whisperManifest,
            storeURL: configuration.whisperModelStoreURL,
            role: "whisper",
            kind: .whisperModel,
            capability: .localSpeechRecognition,
            cache: &cache
        ))
        items.append(contentsOf: managedModelItems(
            manifest: configuration.vadManifest,
            storeURL: configuration.vadModelStoreURL,
            role: "vad",
            kind: .voiceActivityDetector,
            capability: .voiceActivityDetection,
            cache: &cache
        ))
        items.append(appleLanguagePackItem())
        return ComponentPreparationRefreshResult(
            snapshot: ComponentPreparationSnapshot(items: items),
            modelStatusCache: cache
        )
    }

    private static func toolchainItem(
        using entries: [ComponentPreparationToolchainEntry]
    ) -> ComponentPreparationItem {
        let missingRequired = entries.filter { $0.isRequired && !$0.isInstalled }
        let readiness: ComponentReadiness
        if entries.isEmpty {
            readiness = .unknown
        } else if missingRequired.isEmpty {
            readiness = .ready(detail: "Existing dependency setup reports all required download tools available.")
        } else {
            readiness = .missing(
                detail: "Missing required download tools: \(missingRequired.map(\.id).joined(separator: ", "))."
            )
        }
        let installedURLs = entries.compactMap { entry in
            entry.isInstalled ? entry.installationURL : nil
        }
        let diskUsage = installedURLs.reduce(Int64(0)) { $0 + (fileSize(at: $1) ?? 0) }
        let component = Component(
            id: "download.toolchain",
            displayName: "Download tools",
            kind: .downloadToolchain,
            capabilities: [.mediaDownload, .mediaProcessing],
            source: .existingDependencySetup,
            installPolicy: .existingDependencySetup,
            isOptional: false,
            readiness: readiness
        )
        return ComponentPreparationItem(
            component: component,
            sourceDetail: "Existing dependency setup",
            actualDiskUsageBytes: installedURLs.isEmpty ? nil : diskUsage,
            storageURL: installedURLs.count == 1 ? installedURLs.first : nil,
            allowedOperations: [.refresh, .openExistingDependencySetup]
        )
    }

    private static func runtimeItem(
        configuration: ComponentPreparationConfiguration
    ) -> ComponentPreparationItem {
        if let runtime = configuration.runtimeLocator.locate() {
            let isManaged = isLocated(runtime.executableURL, inside: configuration.runtimeDirectoryURL)
            let readinessDetail = isManaged
                ? "Verified \(runtime.provider) runtime at \(runtime.executableURL.path)"
                : "Detected external \(runtime.provider) runtime at \(runtime.executableURL.path)"
            let component = Component(
                id: "asr.runtime.whisper-cpp",
                displayName: "Local ASR runtime",
                kind: .asrRuntime,
                capabilities: [.localSpeechRecognition],
                source: .projectGitHubRelease,
                installPolicy: .onDemandUserConsent,
                isOptional: true,
                readiness: .ready(detail: readinessDetail)
            )
            return ComponentPreparationItem(
                component: component,
                sourceDetail: isManaged
                    ? "Verified app-managed runtime"
                    : "External runtime; managed by its existing installation",
                actualDiskUsageBytes: fileSize(at: runtime.executableURL),
                storageURL: runtime.executableURL,
                // Runtime removal has no production operation handler yet.
                // Do not expose a destructive control until it can validate
                // the managed path and show a real confirmation.
                allowedOperations: [.refresh]
            )
        }

        if let asset = compatibleRuntimeAsset(from: configuration.runtimeDownloadManifest) {
            let component = Component(
                id: "asr.runtime.whisper-cpp",
                displayName: "Local ASR runtime",
                kind: .asrRuntime,
                capabilities: [.localSpeechRecognition],
                source: .projectGitHubRelease,
                installPolicy: .onDemandUserConsent,
                isOptional: true,
                version: asset.version,
                readiness: .missing(detail: "A compatible project-controlled runtime release is available on demand.")
            )
            return ComponentPreparationItem(
                component: component,
                sourceDetail: "\(asset.sourceDescription): \(asset.downloadURL.absoluteString)",
                storageURL: configuration.runtimeDirectoryURL,
                allowedOperations: [.refresh, .installRuntime]
            )
        }

        let platform = ASRRuntimeLocator.currentPlatform
        let architecture = ASRRuntimeLocator.currentArchitecture
        let component = Component(
            id: "asr.runtime.whisper-cpp",
            displayName: "Local ASR runtime",
            kind: .asrRuntime,
            capabilities: [.localSpeechRecognition],
            source: .projectGitHubRelease,
            installPolicy: .onDemandUserConsent,
            isOptional: true,
            readiness: ComponentReadiness(
                status: .unavailable,
                detail: "No compatible project-controlled runtime release is configured for \(platform) / \(architecture)."
            )
        )
        return ComponentPreparationItem(
            component: component,
            sourceDetail: "Project-controlled release manifest is not available for this Mac.",
            allowedOperations: [.refresh]
        )
    }

    private static func managedModelItems(
        manifest: ASRModelManifest,
        storeURL: URL,
        role: String,
        kind: ComponentKind,
        capability: ComponentCapability,
        cache: inout [ComponentPreparationModelCacheKey: ComponentPreparationCachedModelStatus]
    ) -> [ComponentPreparationItem] {
        let store = ASRModelStore(directoryURL: storeURL)
        return manifest.models.map { model in
            let installedURL = store.installedURL(for: model)
            let fingerprint = ComponentPreparationFileFingerprint(url: installedURL)
            let key = ComponentPreparationModelCacheKey(
                role: role,
                modelID: model.id,
                expectedSHA256: model.sha256.lowercased()
            )
            let status: ASRModelStatus
            let readiness: ComponentReadiness
            if let cached = cache[key], cached.fingerprint == fingerprint {
                status = cached.status
                readiness = modelReadiness(status)
            } else {
                do {
                    status = try store.status(for: model)
                    cache[key] = ComponentPreparationCachedModelStatus(
                        fingerprint: fingerprint,
                        status: status
                    )
                    readiness = modelReadiness(status)
                } catch {
                    let component = Component(
                        id: componentID(for: model, kind: kind),
                        displayName: model.displayName,
                        kind: kind,
                        capabilities: [capability],
                        source: .existingASRModelDownloader,
                        installPolicy: .existingManagedInstaller,
                        isOptional: true,
                        sizeBytes: model.sizeBytes,
                        readiness: ComponentReadiness(status: .unavailable, detail: error.localizedDescription)
                    )
                    return ComponentPreparationItem(
                        component: component,
                        sourceDetail: "\(model.sourceDescription) · \(model.license)",
                        actualDiskUsageBytes: fileSize(at: installedURL),
                        storageURL: installedURL,
                        allowedOperations: [.refresh]
                    )
                }
            }

            let component = Component(
                id: componentID(for: model, kind: kind),
                displayName: model.displayName,
                kind: kind,
                capabilities: [capability],
                source: .existingASRModelDownloader,
                installPolicy: .existingManagedInstaller,
                isOptional: true,
                sizeBytes: model.sizeBytes,
                readiness: readiness
            )
            return ComponentPreparationItem(
                component: component,
                sourceDetail: "\(model.sourceDescription) · \(model.license)",
                actualDiskUsageBytes: fileSize(at: status.installedURL),
                storageURL: status.installedURL,
                allowedOperations: allowedOperations(for: status)
            )
        }
    }

    private static func appleLanguagePackItem() -> ComponentPreparationItem {
        let component = Component(
            id: "apple.translation.language-pack",
            displayName: "Apple translation language pack",
            kind: .appleLanguagePack,
            capabilities: [.systemTranslation],
            source: .appleSystem,
            installPolicy: .systemManaged,
            isOptional: true,
            readiness: .unknown
        )
        return ComponentPreparationItem(
            component: component,
            sourceDetail: "Managed by macOS",
            allowedOperations: [.refresh, .openSystemSettings]
        )
    }

    private static func compatibleRuntimeAsset(
        from manifest: ASRRuntimeDownloadManifest?
    ) -> ASRRuntimeDownloadAsset? {
        guard let manifest else { return nil }
        return try? manifest.assetForCurrentRuntime()
    }

    private static func modelReadiness(_ status: ASRModelStatus) -> ComponentReadiness {
        switch status.state {
        case .installed:
            .ready(detail: "Verified managed model at \(status.installedURL.path)")
        case .notInstalled:
            .missing(detail: "This managed model is not installed.")
        case .badHash:
            ComponentReadiness(status: .corrupted, detail: "The managed model failed SHA-256 verification.")
        case .insufficientDiskSpace:
            ComponentReadiness(status: .unavailable, detail: "Not enough free storage to install this managed model.")
        }
    }

    private static func allowedOperations(for status: ASRModelStatus) -> [ComponentPreparationOperation] {
        switch status.state {
        case .installed:
            [.refresh, .removeManagedModel]
        case .notInstalled:
            [.refresh, .installManagedModel]
        case .badHash:
            [.refresh, .installManagedModel, .removeManagedModel]
        case .insufficientDiskSpace:
            [.refresh]
        }
    }

    private static func componentID(for model: ASRModelInfo, kind: ComponentKind) -> String {
        switch kind {
        case .whisperModel:
            "asr.model.\(model.id)"
        case .voiceActivityDetector:
            "asr.vad.\(model.id)"
        case .downloadToolchain, .asrRuntime, .appleLanguagePack:
            model.id
        }
    }

    private static func fileSize(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize else {
            return nil
        }
        return Int64(fileSize)
    }

    private static func isLocated(_ url: URL, inside root: URL) -> Bool {
        let path = normalizedPath(url)
        let rootPath = normalizedPath(root)
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }

    private static func normalizedPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}
