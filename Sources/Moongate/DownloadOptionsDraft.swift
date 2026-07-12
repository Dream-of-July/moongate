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

    var title: String {
        switch self {
        case .none: "不处理"
        case .original: "保留原字幕"
        case .translatedFile: "翻译字幕"
        case .embeddedTranslation: "嵌入字幕"
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

    var title: String {
        switch self {
        case .automatic: "自动选择"
        case .local: "本机识别"
        case .cloud: "云端识别"
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
    var recognitionChoice: DownloadRecognitionChoice
    var targetLanguage: String
    var subtitleStyle: SubtitleStyle
    var localModelID: String?
    var translationModel: String?

    /// Preserves an existing automatic policy (for example, prefer platform
    /// captions) rather than silently changing a user's saved default.
    private var automaticSubtitleSourcePolicy: SubtitleSourcePolicy

    init(configuration: QueuedProcessingConfiguration) {
        quality = configuration.quality
        outputFormat = configuration.outputFormat
        subtitleOutcome = Self.outcome(for: configuration.subtitleMode)
        recognitionChoice = Self.recognitionChoice(for: configuration.subtitleSourcePolicy)
        targetLanguage = configuration.targetLanguage
        subtitleStyle = configuration.subtitleStyle
        localModelID = configuration.transcriptionModel
        translationModel = configuration.translationModel
        automaticSubtitleSourcePolicy = configuration.subtitleSourcePolicy
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

        let sourcePolicy: SubtitleSourcePolicy = switch recognitionChoice {
        case .automatic: automaticPolicyForAutomaticChoice
        case .local: .forceLocalASR
        case .cloud: .cloudASR
        }

        return QueuedProcessingConfiguration(
            quality: quality,
            outputFormat: outputFormat,
            subtitleMode: subtitleMode,
            subtitleSourcePolicy: sourcePolicy,
            targetLanguage: targetLanguage,
            transcriptionModel: showsRecognitionOptions && recognitionChoice == .local ? localModelID : nil,
            translationModel: showsTranslationOptions ? translationModel : nil,
            subtitleStyle: subtitleStyle
        )
    }

    private var automaticPolicyForAutomaticChoice: SubtitleSourcePolicy {
        switch automaticSubtitleSourcePolicy {
        case .forceLocalASR, .preferLocalASR, .compareLocalASR, .cloudASR:
            .autoBest
        case .autoBest, .preferPlatform, .forcePlatform, .importedFile:
            automaticSubtitleSourcePolicy
        }
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
}
