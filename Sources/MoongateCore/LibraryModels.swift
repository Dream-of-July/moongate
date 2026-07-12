import Foundation

// MARK: - Persisted library contracts

/// A safe, portable description of the source page. It deliberately omits
/// credentials, query values, and fragments so `library.json` is never a copy
/// of a browser session or API request.
public struct LibrarySourceDescriptor: Codable, Sendable, Equatable {
    public let urlString: String

    public init?(urlString: String) {
        guard var components = URLComponents(string: urlString),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil else {
            return nil
        }

        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil

        guard let safeURL = components.string else { return nil }
        self.urlString = safeURL
    }

    /// A privacy-sanitized source is only restartable when its path still
    /// identifies the media. For example, stripping `?v=` from YouTube's
    /// `/watch` URL intentionally leaves no safe identifier to replay.
    public var supportsRestart: Bool {
        guard let components = URLComponents(string: urlString) else { return false }
        let path = components.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, path != "/" else { return false }
        let host = components.host?.lowercased() ?? ""
        if host == "youtube.com" || host.hasSuffix(".youtube.com") {
            return path.lowercased() != "/watch"
        }
        return true
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let storedURL = try container.decode(String.self)
        guard let descriptor = Self(urlString: storedURL) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "The library source URL is not a safe HTTP(S) URL."
            )
        }
        self = descriptor
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(urlString)
    }
}

public enum LibraryArtifactRole: String, Codable, Sendable, Equatable, CaseIterable {
    case video
    case sourceSubtitle
    case translatedSubtitle
    case renderedVideo
    case thumbnail
    case other
}

public enum LibraryPathError: LocalizedError, Sendable, Equatable {
    case invalidRelativePath(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRelativePath(let path):
            return "Library artifacts must use a safe relative path: \(path)"
        }
    }
}

/// An output owned by a library version. Only a path relative to the managed
/// downloads directory is persisted; machine-specific absolute paths are not.
public struct LibraryArtifact: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let role: LibraryArtifactRole
    public let relativePath: String
    public let size: Int64?
    public let modifiedAt: Date?

    public init(
        id: UUID = UUID(),
        role: LibraryArtifactRole,
        relativePath: String,
        size: Int64? = nil,
        modifiedAt: Date? = nil
    ) throws {
        let normalizedPath = relativePath.replacingOccurrences(of: "\\", with: "/")
        guard Self.isSafeRelativePath(normalizedPath) else {
            throw LibraryPathError.invalidRelativePath(relativePath)
        }

        self.id = id
        self.role = role
        self.relativePath = normalizedPath
        self.size = size
        self.modifiedAt = modifiedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = try Self(
            id: try container.decode(UUID.self, forKey: .id),
            role: try container.decode(LibraryArtifactRole.self, forKey: .role),
            relativePath: try container.decode(String.self, forKey: .relativePath),
            size: try container.decodeIfPresent(Int64.self, forKey: .size),
            modifiedAt: try container.decodeIfPresent(Date.self, forKey: .modifiedAt)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case relativePath
        case size
        case modifiedAt
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.hasPrefix("~"),
              !path.contains("://"),
              !path.contains("\u{0000}") else {
            return false
        }

        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            return false
        }

        // Reject a Windows drive prefix after normalising backslashes.
        guard path.range(of: "^[A-Za-z]:", options: .regularExpression) == nil else {
            return false
        }

        return true
    }
}

public enum LibraryItemState: String, Codable, Sendable, Equatable, CaseIterable {
    case queued
    case cancelling
    case downloading
    case transcribing
    case translating
    case transcoding
    case burning
    case completed
    case partialSuccess
    case needsAttention
    case interrupted
    case failed
    case cancelled

    /// A queued task has a mutable configuration and has not entered the
    /// processing pipeline yet. Keep it distinct from a paused/running task.
    public var isQueued: Bool {
        self == .queued
    }

    /// A run has started and its processing configuration is immutable until
    /// it reaches a terminal state. `cancelling` remains running until all
    /// child processes and slot pools have actually converged.
    public var isRunning: Bool {
        switch self {
        case .cancelling, .downloading, .transcribing, .translating, .transcoding, .burning:
            return true
        case .queued, .completed, .partialSuccess, .needsAttention, .interrupted, .failed, .cancelled:
            return false
        }
    }

    public var isActive: Bool { isQueued || isRunning }

    public var needsAttention: Bool {
        switch self {
        case .partialSuccess, .needsAttention, .interrupted, .failed:
            return true
        case .queued, .cancelling, .downloading, .transcribing, .translating, .transcoding, .burning, .completed, .cancelled:
            return false
        }
    }
}

public enum LibraryProcessingStage: String, Codable, Sendable, Equatable, CaseIterable {
    case download
    case transcribe
    case translate
    case transcode
    case burning
    case complete
    case recovery
}

/// The durable category of a user-visible processing issue. These values are
/// intentionally stable: the library stores an actionable reason, never a
/// raw transport error or a runtime diagnostic.
public enum ProcessingAttentionKind: String, Codable, Sendable, Equatable, CaseIterable {
    case loginRequired
    case fileMissing
    case capabilityUnavailable
    case interrupted
    case processingFailed
    case needsReview

    fileprivate var defaultTitle: String {
        switch self {
        case .loginRequired: "需要登录"
        case .fileMissing: "找不到文件"
        case .capabilityUnavailable: "需要准备字幕识别"
        case .interrupted: "任务已中断"
        case .processingFailed: "处理失败"
        case .needsReview: "需要重新检查"
        }
    }

    fileprivate var defaultSummary: String {
        switch self {
        case .loginRequired: "请登录后重试。"
        case .fileMissing: "原文件已移动或不可用。"
        case .capabilityUnavailable: "字幕识别尚未准备好。"
        case .interrupted: "上次任务已中断。"
        case .processingFailed: "处理未完成，可重试。"
        case .needsReview: "需要重新检查此任务。"
        }
    }
}

/// A recovery action that is safe to persist and can later be rendered by a
/// workspace without parsing user-facing error text.
public enum ProcessingAttentionAction: String, Codable, Sendable, Equatable, CaseIterable {
    case login
    case locateFile
    case prepareLocalRecognition
    case configureCloudRecognition
    case restart
    case retry
    case review
}

/// A privacy-safe explanation for an item that needs user attention. It only
/// records a stable category, a fixed safe title, a scrubbed human-readable
/// summary, the next action, the affected stage, and a timestamp.
public struct ProcessingAttention: Codable, Sendable, Equatable {
    public let kind: ProcessingAttentionKind
    public let title: String
    public let summary: String
    public let primaryAction: ProcessingAttentionAction
    public let stage: LibraryProcessingStage
    public let occurredAt: Date

    public init(
        kind: ProcessingAttentionKind,
        summary: String? = nil,
        primaryAction: ProcessingAttentionAction,
        stage: LibraryProcessingStage,
        occurredAt: Date = Date()
    ) {
        self.kind = kind
        self.title = kind.defaultTitle
        self.summary = Self.sanitizedSummary(from: summary) ?? kind.defaultSummary
        self.primaryAction = primaryAction
        self.stage = stage
        self.occurredAt = occurredAt
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case title
        case summary
        case primaryAction
        case stage
        case occurredAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: try container.decode(ProcessingAttentionKind.self, forKey: .kind),
            summary: try container.decodeIfPresent(String.self, forKey: .summary),
            primaryAction: try container.decode(ProcessingAttentionAction.self, forKey: .primaryAction),
            stage: try container.decode(LibraryProcessingStage.self, forKey: .stage),
            occurredAt: try container.decodeIfPresent(Date.self, forKey: .occurredAt) ?? Date()
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(title, forKey: .title)
        try container.encode(summary, forKey: .summary)
        try container.encode(primaryAction, forKey: .primaryAction)
        try container.encode(stage, forKey: .stage)
        try container.encode(occurredAt, forKey: .occurredAt)
    }

    /// Runtime status strings are untrusted. The library persists only copy
    /// generated by this type, plus a narrowly validated login-site sentence;
    /// arbitrary process output can contain headers, credentials, or paths.
    static func sanitizedSummary(from rawStatus: String?) -> String? {
        guard let rawStatus else { return nil }
        let normalized = rawStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        let ownedCopy = Set(ProcessingAttentionKind.allCases.map(\.defaultSummary)).union([
            "本地字幕识别尚未准备好。",
            "云端字幕识别尚未准备好。",
        ])
        if ownedCopy.contains(normalized) {
            return normalized
        }

        guard normalized.range(
            of: #"^请登录 [A-Za-z0-9.-]{1,253} 后重试。$"#,
            options: .regularExpression
        ) != nil else {
            return nil
        }
        return normalized
    }
}

/// Converts runtime-only queue state into a durable, privacy-safe recovery
/// record. The classifier deliberately accepts primitive facts so it can be
/// tested without serialising a QueueItem or AppSettings snapshot.
public enum ProcessingAttentionClassifier {
    public static func classify(
        state: LibraryItemState,
        stage: LibraryProcessingStage,
        statusText: String?,
        loginSite: String?,
        isDeferredDraft: Bool,
        usesLocalRecognition: Bool,
        usesCloudRecognition: Bool,
        occurredAt: Date
    ) -> ProcessingAttention? {
        if let loginSite {
            return ProcessingAttention(
                kind: .loginRequired,
                summary: loginSummary(for: loginSite),
                primaryAction: .login,
                stage: stage,
                occurredAt: occurredAt
            )
        }

        switch state {
        case .interrupted:
            return ProcessingAttention(
                kind: .interrupted,
                primaryAction: .restart,
                stage: stage,
                occurredAt: occurredAt
            )
        case .queued:
            // A queued draft remains editable even when its eventual local or
            // cloud capability is not ready. Surface setup only if the person
            // starts it, rather than turning a draft into a failure state.
            _ = isDeferredDraft
            return nil
        case .failed, .partialSuccess:
            if isFileMissingStatus(statusText) {
                return ProcessingAttention(
                    kind: .fileMissing,
                    primaryAction: .locateFile,
                    stage: stage,
                    occurredAt: occurredAt
                )
            }
            if usesLocalRecognition, isCapabilitySetupStatus(statusText) {
                return ProcessingAttention(
                    kind: .capabilityUnavailable,
                    summary: "本地字幕识别尚未准备好。",
                    primaryAction: .prepareLocalRecognition,
                    stage: stage,
                    occurredAt: occurredAt
                )
            }
            if usesCloudRecognition, isCapabilitySetupStatus(statusText) {
                return ProcessingAttention(
                    kind: .capabilityUnavailable,
                    summary: "云端字幕识别尚未准备好。",
                    primaryAction: .configureCloudRecognition,
                    stage: stage,
                    occurredAt: occurredAt
                )
            }
            return ProcessingAttention(
                kind: .processingFailed,
                primaryAction: .retry,
                stage: stage,
                occurredAt: occurredAt
            )
        case .needsAttention:
            return ProcessingAttention(
                kind: .needsReview,
                primaryAction: .review,
                stage: stage,
                occurredAt: occurredAt
            )
        case .cancelling, .downloading, .transcribing, .translating, .transcoding, .burning, .completed, .cancelled:
            return nil
        }
    }

    private static func loginSummary(for rawSite: String) -> String {
        guard let site = safeSiteLabel(rawSite) else { return "请登录后重试。" }
        return "请登录 \(site) 后重试。"
    }

    private static func safeSiteLabel(_ rawSite: String) -> String? {
        let trimmed = rawSite.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 253,
              trimmed.range(of: #"^[A-Za-z0-9.-]+$"#, options: .regularExpression) != nil,
              !trimmed.contains("..") else {
            return nil
        }
        let withoutWWW = trimmed.lowercased().hasPrefix("www.") ? String(trimmed.dropFirst(4)) : trimmed
        return withoutWWW
    }

    private static func isCapabilitySetupStatus(_ statusText: String?) -> Bool {
        guard let statusText else { return false }
        let lowered = statusText.lowercased()
        let markers = [
            "not ready", "needs setup", "setup required", "not configured", "configure",
            "尚未准备", "尚未準備", "未准备", "未準備", "未配置", "未設定", "需要设置", "需要設定", "配置", "設定"
        ]
        return markers.contains(where: lowered.contains)
    }

    private static func isFileMissingStatus(_ statusText: String?) -> Bool {
        guard let statusText else { return false }
        let lowered = statusText.lowercased()
        let markers = [
            "file not found", "missing file", "file moved", "no such file",
            "文件已移动", "文件已移動", "文件缺失", "文件不存在", "找不到文件"
        ]
        return markers.contains(where: lowered.contains)
    }
}

public struct LibraryActualModels: Codable, Sendable, Equatable {
    public var transcription: String?
    public var translation: String?

    public init(transcription: String? = nil, translation: String? = nil) {
        self.transcription = transcription
        self.translation = translation
    }
}

/// A deliberately narrow processing snapshot. It is enough to explain a
/// result and create a later reprocess request, but has no account settings,
/// tokens, cookies, or API credentials.
public struct LibraryProcessingConfiguration: Codable, Sendable, Equatable {
    public var outputFormat: String?
    public var subtitleMode: String?
    public var subtitleSource: String?
    public var transcriptionModel: String?
    public var translationModel: String?
    public var targetLanguage: String?
    public var subtitleStyle: String?
    public var quality: String?

    public init(
        outputFormat: String? = nil,
        subtitleMode: String? = nil,
        subtitleSource: String? = nil,
        transcriptionModel: String? = nil,
        translationModel: String? = nil,
        targetLanguage: String? = nil,
        subtitleStyle: String? = nil,
        quality: String? = nil
    ) {
        self.outputFormat = outputFormat
        self.subtitleMode = subtitleMode
        self.subtitleSource = subtitleSource
        self.transcriptionModel = transcriptionModel
        self.translationModel = translationModel
        self.targetLanguage = targetLanguage
        self.subtitleStyle = subtitleStyle
        self.quality = quality
    }
}

public struct ProcessingSummary: Codable, Sendable, Equatable {
    public var state: LibraryItemState
    public var stage: LibraryProcessingStage
    public var progress: Double
    public var actualModels: LibraryActualModels
    public var configuration: LibraryProcessingConfiguration
    public var attention: ProcessingAttention?
    public var updatedAt: Date

    public init(
        state: LibraryItemState,
        stage: LibraryProcessingStage,
        progress: Double,
        actualModels: LibraryActualModels = .init(),
        configuration: LibraryProcessingConfiguration = .init(),
        attention: ProcessingAttention? = nil,
        updatedAt: Date = Date()
    ) {
        self.state = state
        self.stage = stage
        self.progress = min(max(progress, 0), 1)
        self.actualModels = actualModels
        self.configuration = configuration
        self.attention = attention
        self.updatedAt = updatedAt
    }
}

public struct LibraryVersion: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var number: Int
    public var processing: ProcessingSummary
    public var artifacts: [LibraryArtifact]
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        number: Int,
        processing: ProcessingSummary,
        artifacts: [LibraryArtifact] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.number = number
        self.processing = processing
        self.artifacts = artifacts
        self.createdAt = createdAt
    }
}

public struct LibraryItem: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var title: String
    public var source: LibrarySourceDescriptor?
    /// Sanitized remote thumbnail descriptor. It is optional so a recovered
    /// local file can still be represented without inventing a preview URL.
    public var thumbnail: LibrarySourceDescriptor?
    public var tags: [String]
    public var isPinned: Bool
    public var note: String?
    public var versions: [LibraryVersion]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        source: LibrarySourceDescriptor? = nil,
        thumbnail: LibrarySourceDescriptor? = nil,
        tags: [String] = [],
        isPinned: Bool = false,
        note: String? = nil,
        versions: [LibraryVersion] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.thumbnail = thumbnail
        self.tags = tags
        self.isPinned = isPinned
        self.note = note
        self.versions = versions
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var latestVersion: LibraryVersion? {
        versions.max { lhs, rhs in
            lhs.number == rhs.number ? lhs.createdAt < rhs.createdAt : lhs.number < rhs.number
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case source
        case thumbnail
        case tags
        case isPinned
        case note
        case versions
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            title: try container.decode(String.self, forKey: .title),
            source: try container.decodeIfPresent(LibrarySourceDescriptor.self, forKey: .source),
            thumbnail: try container.decodeIfPresent(LibrarySourceDescriptor.self, forKey: .thumbnail),
            tags: try container.decodeIfPresent([String].self, forKey: .tags) ?? [],
            isPinned: try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false,
            note: try container.decodeIfPresent(String.self, forKey: .note),
            versions: try container.decodeIfPresent([LibraryVersion].self, forKey: .versions) ?? [],
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(),
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(thumbnail, forKey: .thumbnail)
        try container.encode(tags, forKey: .tags)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encode(versions, forKey: .versions)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

public struct LibraryTag: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct LibraryEnvelope: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var tags: [LibraryTag]
    public var items: [LibraryItem]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        tags: [LibraryTag] = [],
        items: [LibraryItem] = []
    ) {
        self.schemaVersion = schemaVersion
        self.tags = tags
        self.items = items
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case tags
        case items
    }

    /// A version-less file is the v0 library shape. The store owns advancing it
    /// to `currentSchemaVersion` after decoding so migration remains explicit.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        tags = try container.decodeIfPresent([LibraryTag].self, forKey: .tags) ?? []
        items = try container.decodeIfPresent([LibraryItem].self, forKey: .items) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(tags, forKey: .tags)
        try container.encode(items, forKey: .items)
    }
}
