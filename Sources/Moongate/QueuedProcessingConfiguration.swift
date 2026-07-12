import Foundation
import MoongateCore

/// The editable configuration attached to a task before it enters the queue
/// pipeline. It deliberately contains no credentials; task-only model and
/// language overrides are applied to an in-memory AppSettings snapshot only
/// when the task is created or updated.
struct QueuedProcessingConfiguration: Equatable, Sendable {
    var quality: String
    var outputFormat: OutputFormat
    var subtitleMode: ChineseSubtitleMode
    var subtitleSourcePolicy: SubtitleSourcePolicy
    var targetLanguage: String
    var transcriptionModel: String?
    var translationModel: String?
    var subtitleStyle: SubtitleStyle

    init(
        quality: String = "best",
        outputFormat: OutputFormat = .original,
        subtitleMode: ChineseSubtitleMode = .off,
        subtitleSourcePolicy: SubtitleSourcePolicy = .autoBest,
        targetLanguage: String = "zh-Hans",
        transcriptionModel: String? = nil,
        translationModel: String? = nil,
        subtitleStyle: SubtitleStyle = .bilingual
    ) {
        self.quality = quality
        self.outputFormat = outputFormat
        self.subtitleMode = subtitleMode
        self.subtitleSourcePolicy = subtitleSourcePolicy
        self.targetLanguage = targetLanguage
        self.transcriptionModel = Self.nonEmpty(transcriptionModel)
        self.translationModel = Self.nonEmpty(translationModel)
        self.subtitleStyle = subtitleStyle
    }

    static func defaults(from settings: AppSettings) -> Self {
        let subtitleMode = settings.lastSubtitleMode
            .flatMap(ChineseSubtitleMode.init(rawValue:)) ?? .off
        let sourcePolicy: SubtitleSourcePolicy
        switch settings.subtitleRecognitionMode {
        case .alwaysLocal:
            sourcePolicy = .forceLocalASR
        case .platformOnly:
            sourcePolicy = .forcePlatform
        case .automatic:
            sourcePolicy = .autoBest
        }
        let translationModel = settings.translationFollowsDefault
            ? settings.aiModel : settings.translationModel
        return Self(
            quality: "best",
            outputFormat: settings.lastOutputFormat ?? .original,
            subtitleMode: subtitleMode,
            subtitleSourcePolicy: sourcePolicy,
            targetLanguage: settings.translationTargetLanguage,
            transcriptionModel: settings.localASRModelID,
            translationModel: translationModel,
            subtitleStyle: settings.subtitleStyle
        )
    }

    func applying(to settings: AppSettings) -> AppSettings {
        var snapshot = settings
        snapshot.translationTargetLanguage = targetLanguage
        snapshot.subtitleStyle = subtitleStyle
        if let transcriptionModel {
            snapshot.localASRModelID = transcriptionModel
        }
        if let translationModel {
            snapshot.translationModel = translationModel
            snapshot.translationFollowsDefault = false
        }
        return snapshot
    }

    var libraryConfiguration: LibraryProcessingConfiguration {
        LibraryProcessingConfiguration(
            outputFormat: outputFormat.rawValue,
            subtitleSource: librarySubtitleSource?.rawValue,
            transcriptionModel: transcriptionModel,
            translationModel: translationModel,
            targetLanguage: targetLanguage,
            subtitleStyle: subtitleStyle.rawValue,
            quality: quality
        )
    }

    private var librarySubtitleSource: SubtitleSourceKind? {
        switch subtitleSourcePolicy {
        case .forceLocalASR, .preferLocalASR, .compareLocalASR:
            .localASR
        case .cloudASR:
            .cloudASR
        case .importedFile:
            .importedFile
        case .forcePlatform, .preferPlatform:
            .platformAuto
        case .autoBest:
            nil
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

/// A link plus its editable pre-run configuration. It becomes a stable queue
/// record only after source resolution/analyse succeeds.
struct DownloadDraft: Identifiable, Equatable, Sendable {
    let id: UUID
    let sourceURL: String
    var configuration: QueuedProcessingConfiguration

    init(id: UUID = UUID(), sourceURL: String, configuration: QueuedProcessingConfiguration) {
        self.id = id
        self.sourceURL = sourceURL
        self.configuration = configuration
    }
}

/// The immutable runtime boundary created by QueueManager.start(id:). It is
/// intentionally in-memory: it may contain a credential-bearing AppSettings
/// snapshot, so it must never be written into LibraryEnvelope/library.json.
struct ProcessingSnapshot: Sendable {
    let request: DownloadRequest
    let mode: ChineseSubtitleMode
    let settings: AppSettings
    let skipDownload: Bool
    let initialFiles: [URL]
}
