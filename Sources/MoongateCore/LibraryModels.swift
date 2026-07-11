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

    public var isActive: Bool {
        switch self {
        case .queued, .downloading, .transcribing, .translating, .transcoding, .burning:
            return true
        case .completed, .partialSuccess, .needsAttention, .interrupted, .failed, .cancelled:
            return false
        }
    }

    public var needsAttention: Bool {
        switch self {
        case .partialSuccess, .needsAttention, .interrupted, .failed:
            return true
        case .queued, .downloading, .transcribing, .translating, .transcoding, .burning, .completed, .cancelled:
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
    public var subtitleSource: String?
    public var transcriptionModel: String?
    public var translationModel: String?
    public var targetLanguage: String?
    public var subtitleStyle: String?
    public var quality: String?

    public init(
        outputFormat: String? = nil,
        subtitleSource: String? = nil,
        transcriptionModel: String? = nil,
        translationModel: String? = nil,
        targetLanguage: String? = nil,
        subtitleStyle: String? = nil,
        quality: String? = nil
    ) {
        self.outputFormat = outputFormat
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
    public var updatedAt: Date

    public init(
        state: LibraryItemState,
        stage: LibraryProcessingStage,
        progress: Double,
        actualModels: LibraryActualModels = .init(),
        configuration: LibraryProcessingConfiguration = .init(),
        updatedAt: Date = Date()
    ) {
        self.state = state
        self.stage = stage
        self.progress = min(max(progress, 0), 1)
        self.actualModels = actualModels
        self.configuration = configuration
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
    public static let currentSchemaVersion = 1

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
