import Foundation

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Distinct product-facing kinds of software or system assets used by Moongate.
/// These never collapse local-ASR prerequisites into ordinary dependency repair.
public enum ComponentKind: String, Codable, CaseIterable, Sendable {
    case downloadToolchain
    case asrRuntime
    case whisperModel
    case voiceActivityDetector
    case appleLanguagePack
}

public enum ComponentCapability: String, Codable, CaseIterable, Sendable {
    case mediaDownload
    case mediaProcessing
    case localSpeechRecognition
    case voiceActivityDetection
    case systemTranslation
}

/// The authority that provides a component. This is separate from install policy
/// so callers cannot accidentally offer generic repair for an app-managed runtime.
public enum ComponentSource: String, Codable, CaseIterable, Sendable {
    case existingDependencySetup
    case projectGitHubRelease
    case existingASRModelDownloader
    case appleSystem
}

public enum ComponentInstallPolicy: String, Codable, CaseIterable, Sendable {
    case existingDependencySetup
    case onDemandUserConsent
    case existingManagedInstaller
    case systemManaged
}

public enum ComponentReadinessStatus: String, Codable, CaseIterable, Sendable {
    case unknown
    case ready
    case missing
    case unavailable
    case corrupted
}

public struct ComponentReadiness: Codable, Equatable, Sendable {
    public let status: ComponentReadinessStatus
    public let detail: String?

    public init(status: ComponentReadinessStatus, detail: String? = nil) {
        self.status = status
        self.detail = detail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public static var unknown: ComponentReadiness { ComponentReadiness(status: .unknown) }

    public static func ready(detail: String? = nil) -> ComponentReadiness {
        ComponentReadiness(status: .ready, detail: detail)
    }

    public static func missing(detail: String? = nil) -> ComponentReadiness {
        ComponentReadiness(status: .missing, detail: detail)
    }

    public var isReady: Bool { status == .ready }
}

/// Immutable catalog metadata plus the latest known readiness snapshot.
public struct Component: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let kind: ComponentKind
    public let capabilities: [ComponentCapability]
    public let source: ComponentSource
    public let installPolicy: ComponentInstallPolicy
    public let isOptional: Bool
    public let sizeBytes: Int64?
    public let version: String?
    public let readiness: ComponentReadiness

    public init(
        id: String,
        displayName: String,
        kind: ComponentKind,
        capabilities: [ComponentCapability],
        source: ComponentSource,
        installPolicy: ComponentInstallPolicy,
        isOptional: Bool,
        sizeBytes: Int64? = nil,
        version: String? = nil,
        readiness: ComponentReadiness = .unknown
    ) {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.kind = kind
        self.capabilities = capabilities
        self.source = source
        self.installPolicy = installPolicy
        self.isOptional = isOptional
        self.sizeBytes = sizeBytes
        self.version = version?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.readiness = readiness
    }

    public func replacingReadiness(with readiness: ComponentReadiness) -> Component {
        Component(
            id: id,
            displayName: displayName,
            kind: kind,
            capabilities: capabilities,
            source: source,
            installPolicy: installPolicy,
            isOptional: isOptional,
            sizeBytes: sizeBytes,
            version: version,
            readiness: readiness
        )
    }
}

public struct ComponentCatalog: Sendable {
    public let components: [Component]
    private let componentsByID: [String: Component]

    public init(components: [Component]) {
        self.components = components
        self.componentsByID = components.reduce(into: [:]) { result, component in
            if result[component.id] == nil {
                result[component.id] = component
            }
        }
    }

    public func component(id: String) -> Component? {
        componentsByID[id]
    }

    /// No concrete runtime URL is embedded here. A release-specific manifest is
    /// injected only after a project-controlled Release asset exists.
    public static func moongate(
        runtimeLocator: ASRRuntimeLocator = ASRRuntimeLocator(),
        whisperModels: ASRModelManifest = .recommendedWhisperCpp,
        vadModels: ASRModelManifest = .recommendedWhisperCppVAD,
        modelReadiness: [String: ComponentReadiness] = [:],
        vadReadiness: [String: ComponentReadiness] = [:]
    ) -> ComponentCatalog {
        var components: [Component] = [
            Component(
                id: "download.toolchain",
                displayName: "Download tools",
                kind: .downloadToolchain,
                capabilities: [.mediaDownload, .mediaProcessing],
                source: .existingDependencySetup,
                installPolicy: .existingDependencySetup,
                isOptional: false,
                readiness: .unknown
            ),
            Component(
                id: "asr.runtime.whisper-cpp",
                displayName: "Local ASR runtime",
                kind: .asrRuntime,
                capabilities: [.localSpeechRecognition],
                source: .projectGitHubRelease,
                installPolicy: .onDemandUserConsent,
                isOptional: true,
                readiness: asrRuntimeReadiness(locator: runtimeLocator)
            ),
        ]

        components.append(contentsOf: whisperModels.models.map { model in
            Component(
                id: "asr.model.\(model.id)",
                displayName: model.displayName,
                kind: .whisperModel,
                capabilities: [.localSpeechRecognition],
                source: .existingASRModelDownloader,
                installPolicy: .existingManagedInstaller,
                isOptional: true,
                sizeBytes: model.sizeBytes,
                readiness: modelReadiness[model.id] ?? .unknown
            )
        })
        components.append(contentsOf: vadModels.models.map { model in
            Component(
                id: "asr.vad.\(model.id)",
                displayName: model.displayName,
                kind: .voiceActivityDetector,
                capabilities: [.voiceActivityDetection],
                source: .existingASRModelDownloader,
                installPolicy: .existingManagedInstaller,
                isOptional: true,
                sizeBytes: model.sizeBytes,
                readiness: vadReadiness[model.id] ?? .unknown
            )
        })
        components.append(
            Component(
                id: "apple.translation.language-pack",
                displayName: "Apple translation language pack",
                kind: .appleLanguagePack,
                capabilities: [.systemTranslation],
                source: .appleSystem,
                installPolicy: .systemManaged,
                isOptional: true,
                readiness: .unknown
            )
        )
        return ComponentCatalog(components: components)
    }

    public static func asrRuntimeReadiness(locator: ASRRuntimeLocator) -> ComponentReadiness {
        guard let runtime = locator.locate() else {
            return .missing(detail: "No verified local ASR runtime was found.")
        }
        return .ready(detail: "Verified \(runtime.provider) runtime at \(runtime.executableURL.path)")
    }
}

public struct ComponentOperationProgress: Codable, Equatable, Sendable {
    public let completedUnitCount: Int64
    public let totalUnitCount: Int64?

    public init(completedUnitCount: Int64, totalUnitCount: Int64? = nil) {
        self.completedUnitCount = max(0, completedUnitCount)
        self.totalUnitCount = totalUnitCount.map { max(0, $0) }
    }
}

public enum ComponentOperationState: Equatable, Sendable {
    case idle(ComponentReadiness)
    case refreshing
    case installing(ComponentOperationProgress?)
    case cancelling
    case failed(String)
    case cancelled

    public var isInFlight: Bool {
        switch self {
        case .refreshing, .installing, .cancelling:
            true
        case .idle, .failed, .cancelled:
            false
        }
    }
}

public enum ComponentOperationCoordinatorError: Error, Equatable, Sendable {
    case unknownComponent(String)
    case operationAlreadyInProgress(String)
    case retryNotAvailable(String)
}

/// Side-effect boundary for the state machine. Tests inject an in-memory client;
/// production wiring injects concrete installers when user consent is present.
/// A successful `install` return is the irreversible commit point: callers must
/// return only after any atomic publish has completed, and a late cancellation
/// then reports the committed readiness instead of a misleading cancellation.
public protocol ComponentOperationClient: Sendable {
    func install(
        _ component: Component,
        progress: @escaping @Sendable (ComponentOperationProgress) -> Void
    ) async throws -> ComponentReadiness

    func refreshReadiness(for component: Component) async throws -> ComponentReadiness
}

public actor ComponentOperationCoordinator {
    private struct RunningOperation {
        let token: UUID
        let task: Task<Void, Never>
    }

    private let catalog: ComponentCatalog
    private let client: any ComponentOperationClient
    private var statesByID: [String: ComponentOperationState]
    private var operationsByID: [String: RunningOperation] = [:]

    public init(catalog: ComponentCatalog, client: any ComponentOperationClient) {
        self.catalog = catalog
        self.client = client
        self.statesByID = catalog.components.reduce(into: [:]) { result, component in
            if result[component.id] == nil {
                result[component.id] = .idle(component.readiness)
            }
        }
    }

    public func state(for componentID: String) -> ComponentOperationState? {
        statesByID[componentID]
    }

    /// Starts an install and returns once the state becomes `.installing`.
    public func install(_ componentID: String) throws {
        let component = try componentForOperation(componentID)
        guard operationsByID[componentID] == nil else {
            throw ComponentOperationCoordinatorError.operationAlreadyInProgress(componentID)
        }
        startInstall(component)
    }

    public func retry(_ componentID: String) throws {
        let component = try componentForOperation(componentID)
        guard operationsByID[componentID] == nil else {
            throw ComponentOperationCoordinatorError.operationAlreadyInProgress(componentID)
        }
        guard let state = statesByID[componentID] else {
            throw ComponentOperationCoordinatorError.unknownComponent(componentID)
        }
        let retryIsAllowed: Bool
        switch state {
        case .failed, .cancelled:
            retryIsAllowed = true
        case .idle, .refreshing, .installing, .cancelling:
            retryIsAllowed = false
        }
        guard retryIsAllowed else {
            throw ComponentOperationCoordinatorError.retryNotAvailable(componentID)
        }
        startInstall(component)
    }

    public func refresh(_ componentID: String) throws {
        let component = try componentForOperation(componentID)
        guard operationsByID[componentID] == nil else {
            throw ComponentOperationCoordinatorError.operationAlreadyInProgress(componentID)
        }
        let token = UUID()
        statesByID[componentID] = .refreshing
        let client = client
        let task = Task.detached { [weak self, client, component, token] in
            do {
                try Task.checkCancellation()
                let readiness = try await client.refreshReadiness(for: component)
                try Task.checkCancellation()
                await self?.finishRefresh(componentID: component.id, token: token, readiness: readiness)
            } catch is CancellationError {
                await self?.finishCancellation(componentID: component.id, token: token)
            } catch {
                if Task.isCancelled {
                    await self?.finishCancellation(componentID: component.id, token: token)
                } else {
                    await self?.finishFailure(
                        componentID: component.id,
                        token: token,
                        message: Self.message(for: error)
                    )
                }
            }
        }
        operationsByID[componentID] = RunningOperation(token: token, task: task)
    }

    /// Marks cancellation in progress until the injected client has unwound.
    @discardableResult
    public func cancel(_ componentID: String) -> Bool {
        guard let operation = operationsByID[componentID] else { return false }
        statesByID[componentID] = .cancelling
        operation.task.cancel()
        return true
    }

    public func waitForOperation(_ componentID: String) async {
        guard let task = operationsByID[componentID]?.task else { return }
        await task.value
    }

    private func componentForOperation(_ componentID: String) throws -> Component {
        guard let component = catalog.component(id: componentID) else {
            throw ComponentOperationCoordinatorError.unknownComponent(componentID)
        }
        return component
    }

    private func startInstall(_ component: Component) {
        let token = UUID()
        statesByID[component.id] = .installing(nil)
        let client = client
        let task = Task.detached { [weak self, client, component, token] in
            do {
                try Task.checkCancellation()
                let readiness = try await client.install(component) { [weak self] progress in
                    Task {
                        await self?.recordProgress(componentID: component.id, token: token, progress: progress)
                    }
                }
                await self?.finishInstall(componentID: component.id, token: token, readiness: readiness)
            } catch is CancellationError {
                await self?.finishCancellation(componentID: component.id, token: token)
            } catch {
                if Task.isCancelled {
                    await self?.finishCancellation(componentID: component.id, token: token)
                } else {
                    await self?.finishFailure(
                        componentID: component.id,
                        token: token,
                        message: Self.message(for: error)
                    )
                }
            }
        }
        operationsByID[component.id] = RunningOperation(token: token, task: task)
    }

    private func recordProgress(
        componentID: String,
        token: UUID,
        progress: ComponentOperationProgress
    ) {
        guard operationsByID[componentID]?.token == token else { return }
        guard case .installing = statesByID[componentID] else { return }
        statesByID[componentID] = .installing(progress)
    }

    private func finishInstall(
        componentID: String,
        token: UUID,
        readiness: ComponentReadiness
    ) {
        guard operationsByID[componentID]?.token == token else { return }
        operationsByID[componentID] = nil
        statesByID[componentID] = .idle(readiness)
    }

    private func finishRefresh(
        componentID: String,
        token: UUID,
        readiness: ComponentReadiness
    ) {
        guard operationsByID[componentID]?.token == token else { return }
        operationsByID[componentID] = nil
        if statesByID[componentID] == .cancelling {
            statesByID[componentID] = .cancelled
            return
        }
        statesByID[componentID] = .idle(readiness)
    }

    private func finishCancellation(componentID: String, token: UUID) {
        guard operationsByID[componentID]?.token == token else { return }
        operationsByID[componentID] = nil
        statesByID[componentID] = .cancelled
    }

    private func finishFailure(componentID: String, token: UUID, message: String) {
        guard operationsByID[componentID]?.token == token else { return }
        operationsByID[componentID] = nil
        if statesByID[componentID] == .cancelling {
            statesByID[componentID] = .cancelled
            return
        }
        statesByID[componentID] = .failed(message)
    }

    private nonisolated static func message(for error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription?.nilIfEmpty {
            return localized
        }
        return error.localizedDescription.nilIfEmpty ?? String(describing: error)
    }
}

/// The manifest used only for an on-demand runtime download. It is separate from
/// `ASRRuntimeBundleManifest`, which describes an already-staged local runtime
/// and deliberately rejects download URLs.
public enum ASRRuntimeDownloadManifestError: Error, Equatable, Sendable {
    case emptyManifest
    case missingRequiredField(String)
    case untrustedDownloadURL(String)
    case invalidExecutableRelativePath(String)
    case invalidSHA256(String)
    case noCompatibleAsset(platform: String, architecture: String)
}

public struct ASRRuntimeDownloadManifest: Codable, Equatable, Sendable {
    public let assets: [ASRRuntimeDownloadAsset]

    public init(assets: [ASRRuntimeDownloadAsset]) throws {
        guard !assets.isEmpty else { throw ASRRuntimeDownloadManifestError.emptyManifest }
        self.assets = assets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(assets: container.decode([ASRRuntimeDownloadAsset].self, forKey: .assets))
    }

    public func assetForCurrentRuntime(
        platform: String = ASRRuntimeLocator.currentPlatform,
        architecture: String = ASRRuntimeLocator.currentArchitecture
    ) throws -> ASRRuntimeDownloadAsset {
        if let asset = assets.first(where: {
            $0.platform.caseInsensitiveCompare(platform) == .orderedSame
                && $0.architecture.caseInsensitiveCompare(architecture) == .orderedSame
        }) {
            return asset
        }
        throw ASRRuntimeDownloadManifestError.noCompatibleAsset(
            platform: platform,
            architecture: architecture
        )
    }
}

public struct ASRRuntimeDownloadAsset: Codable, Equatable, Sendable {
    /// Constants form an allowlist only. They do not define a downloadable
    /// production asset; a concrete Release URL must arrive via injected data.
    public static let trustedReleaseHost = "github.com"
    public static let trustedReleaseOwner = "Dream-of-July"
    public static let trustedReleaseRepository = "moongate"

    public let provider: String
    public let platform: String
    public let architecture: String
    public let version: String
    public let downloadURL: URL
    public let executableRelativePath: String
    /// Digest of the executable materialized at `executableRelativePath`.
    public let sha256: String
    public let license: String
    public let sourceDescription: String

    public init(
        provider: String,
        platform: String,
        architecture: String,
        version: String,
        downloadURL: URL,
        executableRelativePath: String,
        sha256: String,
        license: String,
        sourceDescription: String
    ) throws {
        self.provider = try Self.required(provider, field: "provider")
        self.platform = try Self.required(platform, field: "platform")
        self.architecture = try Self.required(architecture, field: "architecture")
        self.version = try Self.required(version, field: "version")
        try Self.validateTrustedReleaseURL(downloadURL)
        self.downloadURL = downloadURL
        self.executableRelativePath = try Self.validatedRelativePath(executableRelativePath)
        self.sha256 = try Self.validatedSHA256(sha256)
        self.license = try Self.required(license, field: "license")
        self.sourceDescription = try Self.required(sourceDescription, field: "sourceDescription")
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case platform
        case architecture
        case version
        case downloadURL = "downloadUrl"
        case executableRelativePath
        case sha256
        case license
        case sourceDescription
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            provider: container.decode(String.self, forKey: .provider),
            platform: container.decode(String.self, forKey: .platform),
            architecture: container.decode(String.self, forKey: .architecture),
            version: container.decode(String.self, forKey: .version),
            downloadURL: container.decode(URL.self, forKey: .downloadURL),
            executableRelativePath: container.decode(String.self, forKey: .executableRelativePath),
            sha256: container.decode(String.self, forKey: .sha256),
            license: container.decode(String.self, forKey: .license),
            sourceDescription: container.decode(String.self, forKey: .sourceDescription)
        )
    }

    public func executableURL(relativeTo runtimeDirectoryURL: URL) -> URL {
        executableRelativePath
            .split(separator: "/")
            .reduce(runtimeDirectoryURL) { url, component in
                url.appendingPathComponent(String(component), isDirectory: false)
            }
    }

    public func runtimeBundleInfo() throws -> ASRRuntimeBundleInfo {
        try ASRRuntimeBundleInfo(
            provider: provider,
            platform: platform,
            architecture: architecture,
            version: version,
            executableRelativePath: executableRelativePath,
            sha256: sha256,
            license: license,
            sourceDescription: sourceDescription
        )
    }

    private static func required(_ value: String, field: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ASRRuntimeDownloadManifestError.missingRequiredField(field)
        }
        return trimmed
    }

    private static func validateTrustedReleaseURL(_ url: URL) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.caseInsensitiveCompare("https") == .orderedSame,
              components.host?.caseInsensitiveCompare(trustedReleaseHost) == .orderedSame,
              components.port == nil,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            throw ASRRuntimeDownloadManifestError.untrustedDownloadURL(url.absoluteString)
        }

        let path = components.percentEncodedPath
        guard path.hasPrefix("/") else {
            throw ASRRuntimeDownloadManifestError.untrustedDownloadURL(url.absoluteString)
        }
        let parts = path.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 6,
              parts.allSatisfy({ Self.isSafeReleasePathSegment($0) }),
              String(parts[0]).caseInsensitiveCompare(trustedReleaseOwner) == .orderedSame,
              String(parts[1]).caseInsensitiveCompare(trustedReleaseRepository) == .orderedSame,
              parts[2].caseInsensitiveCompare("releases") == .orderedSame,
              parts[3].caseInsensitiveCompare("download") == .orderedSame else {
            throw ASRRuntimeDownloadManifestError.untrustedDownloadURL(url.absoluteString)
        }
    }

    /// Release tags and project-owned asset names intentionally use a narrow,
    /// canonical ASCII subset. Rejecting all percent encodings avoids a server or
    /// intermediary normalizing `%2e%2e` / double-encoded traversal after this
    /// allowlist has accepted the URL.
    private static func isSafeReleasePathSegment(_ segment: Substring) -> Bool {
        guard !segment.isEmpty, segment != ".", segment != ".." else { return false }
        return segment.utf8.allSatisfy { byte in
            (48...57).contains(byte)       // 0-9
                || (65...90).contains(byte) // A-Z
                || (97...122).contains(byte) // a-z
                || byte == 45               // -
                || byte == 46               // .
                || byte == 95               // _
                || byte == 43               // +
        }
    }

    private static func validatedRelativePath(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("/"),
              !trimmed.contains("\\"),
              !trimmed.contains(":"),
              !trimmed.contains("\u{0}") else {
            throw ASRRuntimeDownloadManifestError.invalidExecutableRelativePath(value)
        }
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ASRRuntimeDownloadManifestError.invalidExecutableRelativePath(value)
        }
        return trimmed
    }

    private static func validatedSHA256(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hexDigits = CharacterSet(charactersIn: "0123456789abcdef")
        guard trimmed.count == 64,
              trimmed.unicodeScalars.allSatisfy({ hexDigits.contains($0) }) else {
            throw ASRRuntimeDownloadManifestError.invalidSHA256(value)
        }
        return trimmed
    }
}

/// The transport is injected. It must materialize the manifest's expected
/// executable under the supplied staging directory; this foundation deliberately
/// ships no network transport before a real Release asset is published.
public protocol ASRRuntimeDownloadClient: Sendable {
    func downloadRuntime(
        _ asset: ASRRuntimeDownloadAsset,
        into stagingDirectoryURL: URL,
        progress: @escaping @Sendable (ComponentOperationProgress) -> Void
    ) async throws
}

public enum ASRRuntimeDownloadInstallerError: Error, Equatable, Sendable {
    case unsafeStagedExecutable(String)
}

/// Stages, verifies, and atomically publishes a runtime. The published static
/// manifest contains no download URL and is the only form accepted by the
/// existing runtime locator.
public struct ASRRuntimeDownloadInstaller: Sendable {
    public let manifest: ASRRuntimeDownloadManifest
    public let destinationDirectoryURL: URL
    private let downloadClient: any ASRRuntimeDownloadClient

    public init(
        manifest: ASRRuntimeDownloadManifest,
        destinationDirectoryURL: URL,
        downloadClient: any ASRRuntimeDownloadClient
    ) {
        self.manifest = manifest
        self.destinationDirectoryURL = destinationDirectoryURL.standardizedFileURL
        self.downloadClient = downloadClient
    }

    @discardableResult
    public func installCurrentRuntime(
        progress: @escaping @Sendable (ComponentOperationProgress) -> Void = { _ in }
    ) async throws -> ASRRuntimeInfo {
        let asset = try manifest.assetForCurrentRuntime()
        try Task.checkCancellation()

        let fileManager = FileManager.default
        let parentDirectory = destinationDirectoryURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        let stagingDirectory = parentDirectory.appendingPathComponent(
            ".\(destinationDirectoryURL.lastPathComponent).staging-\(UUID().uuidString)",
            isDirectory: true
        )

        do {
            try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: false)
            try Task.checkCancellation()
            try await downloadClient.downloadRuntime(asset, into: stagingDirectory, progress: progress)
            try Task.checkCancellation()

            let runtime = try asset.runtimeBundleInfo()
            let stagedRuntimeInfo = try Self.verifiedStagedRuntimeInfo(
                runtime,
                stagingDirectory: stagingDirectory,
                fileManager: fileManager
            )
            let stagedManifest = try ASRRuntimeBundleManifest(runtimes: [runtime])
            let stagedManifestURL = stagingDirectory.appendingPathComponent(
                ASRRuntimeLocator.runtimeManifestFileName,
                isDirectory: false
            )
            try ASRJSON.makeEncoder().encode(stagedManifest).write(to: stagedManifestURL, options: .atomic)
            try Task.checkCancellation()

            try Self.atomicallyInstall(
                stagingDirectory: stagingDirectory,
                destinationDirectory: destinationDirectoryURL,
                fileManager: fileManager
            )
            return stagedRuntimeInfo.relocated(from: stagingDirectory, to: destinationDirectoryURL)
        } catch {
            if fileManager.fileExists(atPath: stagingDirectory.path) {
                try? fileManager.removeItem(at: stagingDirectory)
            }
            throw error
        }
    }

    private static func atomicallyInstall(
        stagingDirectory: URL,
        destinationDirectory: URL,
        fileManager: FileManager
    ) throws {
        if fileManager.fileExists(atPath: destinationDirectory.path) {
            // Keep an old verified runtime in place until the candidate directory
            // has a verified executable and a static locator manifest.
            _ = try fileManager.replaceItemAt(
                destinationDirectory,
                withItemAt: stagingDirectory,
                backupItemName: nil,
                options: []
            )
        } else {
            // A sibling staging directory is on the same volume; rename is atomic.
            try fileManager.moveItem(at: stagingDirectory, to: destinationDirectory)
        }
    }

    private static func verifiedStagedRuntimeInfo(
        _ runtime: ASRRuntimeBundleInfo,
        stagingDirectory: URL,
        fileManager: FileManager
    ) throws -> ASRRuntimeInfo {
        let executable = runtime.executableURL(relativeTo: stagingDirectory)
        guard !containsSymbolicLink(
            from: stagingDirectory,
            relativePath: runtime.executableRelativePath,
            fileManager: fileManager
        ) else {
            throw ASRRuntimeDownloadInstallerError.unsafeStagedExecutable(runtime.executableRelativePath)
        }

        let resolvedStagingDirectory = stagingDirectory.resolvingSymlinksInPath().standardizedFileURL
        let resolvedExecutable = executable.resolvingSymlinksInPath().standardizedFileURL
        guard isLocated(resolvedExecutable, inside: resolvedStagingDirectory) else {
            throw ASRRuntimeDownloadInstallerError.unsafeStagedExecutable(runtime.executableRelativePath)
        }
        return try runtime.verifiedRuntimeInfo(relativeTo: stagingDirectory)
    }

    private static func containsSymbolicLink(
        from root: URL,
        relativePath: String,
        fileManager: FileManager
    ) -> Bool {
        if (try? fileManager.destinationOfSymbolicLink(atPath: root.path)) != nil {
            return true
        }
        var candidate = root
        for component in relativePath.split(separator: "/") {
            candidate.appendPathComponent(String(component), isDirectory: false)
            if (try? fileManager.destinationOfSymbolicLink(atPath: candidate.path)) != nil {
                return true
            }
        }
        return false
    }

    private static func isLocated(_ url: URL, inside root: URL) -> Bool {
        let path = normalizedPath(url)
        let rootPath = normalizedPath(root)
        return path.hasPrefix(rootPath + "/")
    }

    private static func normalizedPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}

private extension ASRRuntimeInfo {
    func relocated(from stagingDirectory: URL, to destinationDirectory: URL) -> ASRRuntimeInfo {
        let stagingPath = stagingDirectory.standardizedFileURL.path
        let executablePath = executableURL.standardizedFileURL.path
        guard executablePath.hasPrefix(stagingPath + "/") else { return self }
        let relativePath = String(executablePath.dropFirst(stagingPath.count + 1))
        return ASRRuntimeInfo(
            provider: provider,
            executableURL: destinationDirectory.appendingPathComponent(relativePath, isDirectory: false)
        )
    }
}
