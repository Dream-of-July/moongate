import Foundation
import MoongateCore

/// The result a person wants from subtitles. This deliberately avoids exposing
/// recognizer names or pipeline stages in the normal download flow.
enum DownloadSubtitleOutcome: String, CaseIterable, Identifiable, Sendable {
    case none
    case original
    case translatedFile
    case embeddedTranslation

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .none: L.Download.subtitleResultNone
        case .original: L.Download.subtitleResultOriginal
        case .translatedFile: L.Download.subtitleResultTranslated
        case .embeddedTranslation: L.Download.subtitleResultEmbedded
        }
    }
}

/// A deliberately small, human-facing choice. Exact models remain an
/// advanced option and are only carried through when a person asks for one.
enum DownloadRecognitionChoice: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case local
    case cloud

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .automatic: L.Download.recognitionAutomatic
        case .local: L.Download.recognitionLocal
        case .cloud: L.Download.recognitionCloud
        }
    }
}

/// Presentation-layer draft for a new download. It translates concise outcome
/// choices into the stable, queue-owned configuration without changing the
/// existing processing contract.
struct DownloadOptionsDraft: Equatable, Sendable {
    var quality: String
    var outputFormat: OutputFormat
    var subtitleOutcome: DownloadSubtitleOutcome
    var recognitionChoice: DownloadRecognitionChoice {
        didSet {
            subtitleSourcePolicy = Self.policy(for: recognitionChoice)
        }
    }
    var targetLanguage: String
    var subtitleStyle: SubtitleStyle
    var localModelID: String?
    var translationModel: String?

    /// Keeps the exact queue-level policy until a person explicitly changes
    /// the advanced recognition choice. This preserves distinctions such as
    /// prefer-local versus force-local when reopening a queued task.
    private var subtitleSourcePolicy: SubtitleSourcePolicy

    init(configuration: QueuedProcessingConfiguration) {
        quality = configuration.quality
        outputFormat = configuration.outputFormat
        subtitleOutcome = Self.outcome(for: configuration.subtitleMode)
        subtitleSourcePolicy = configuration.subtitleSourcePolicy
        recognitionChoice = Self.recognitionChoice(for: configuration.subtitleSourcePolicy)
        targetLanguage = configuration.targetLanguage
        subtitleStyle = configuration.subtitleStyle
        localModelID = configuration.transcriptionModel
        translationModel = configuration.translationModel
    }

    static func defaults(from settings: AppSettings) -> Self {
        Self(configuration: .defaults(from: settings))
    }

    var showsTranslationOptions: Bool {
        subtitleOutcome == .translatedFile || subtitleOutcome == .embeddedTranslation
    }

    /// `true` only after the person explicitly moves beyond automatic subtitle
    /// selection. The normal flow never needs to explain ASR runtimes/models.
    var showsRecognitionOptions: Bool {
        showsTranslationOptions && recognitionChoice != .automatic
    }

    var usesCustomRecognition: Bool {
        get { recognitionChoice != .automatic }
        set { recognitionChoice = newValue ? .local : .automatic }
    }

    mutating func useAutomaticRecognition() {
        recognitionChoice = .automatic
    }

    func queuedConfiguration() -> QueuedProcessingConfiguration {
        let subtitleMode: ChineseSubtitleMode = switch subtitleOutcome {
        case .none: ChineseSubtitleMode.off
        case .original: .burnOriginal
        case .translatedFile: .srtOnly
        case .embeddedTranslation: .burnIn
        }

        return QueuedProcessingConfiguration(
            quality: quality,
            outputFormat: outputFormat,
            subtitleMode: subtitleMode,
            subtitleSourcePolicy: subtitleSourcePolicy,
            targetLanguage: targetLanguage,
            transcriptionModel: showsRecognitionOptions && recognitionChoice == .local ? localModelID : nil,
            translationModel: showsTranslationOptions ? translationModel : nil,
            subtitleStyle: subtitleStyle
        )
    }

    private static func outcome(for mode: ChineseSubtitleMode) -> DownloadSubtitleOutcome {
        switch mode {
        case .off: .none
        case .srtOnly: .translatedFile
        case .burnIn: .embeddedTranslation
        case .burnOriginal: .original
        }
    }

    private static func recognitionChoice(for policy: SubtitleSourcePolicy) -> DownloadRecognitionChoice {
        switch policy {
        case .forceLocalASR, .preferLocalASR, .compareLocalASR: .local
        case .cloudASR: .cloud
        case .autoBest, .preferPlatform, .forcePlatform, .importedFile: .automatic
        }
    }

    private static func policy(for recognitionChoice: DownloadRecognitionChoice) -> SubtitleSourcePolicy {
        switch recognitionChoice {
        case .automatic: .autoBest
        case .local: .forceLocalASR
        case .cloud: .cloudASR
        }
    }
}
