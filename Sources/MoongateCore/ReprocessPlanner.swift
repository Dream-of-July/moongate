import Foundation

public enum ReprocessChangedField: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case subtitleMode
    case subtitleStyle
    case targetLanguage
    case translationModel
    case transcriptionModel
    case subtitleSource
    case outputFormat
    case quality
}

public struct ReprocessRequest: Codable, Sendable, Equatable {
    public let sourceVersionID: UUID
    public let changedFields: Set<ReprocessChangedField>
    public let needsTranslation: Bool
    public let needsBurn: Bool
    /// Stored raw values keep the planner platform-neutral while still
    /// allowing it to distinguish a real mode change from a style tweak.
    public let subtitleMode: String?
    public let previousSubtitleMode: String?
    /// The Inspector uses the real source kind to distinguish an ASR request
    /// from selecting an already available manual/imported subtitle.
    public let subtitleSource: SubtitleSourceKind?
    /// `original` means a fresh source download is required: a completed
    /// transcoded version cannot reconstruct the original container/codec.
    public let outputFormat: OutputFormat?

    public init(
        sourceVersionID: UUID,
        changedFields: Set<ReprocessChangedField>,
        needsTranslation: Bool,
        needsBurn: Bool,
        subtitleMode: String? = nil,
        previousSubtitleMode: String? = nil,
        subtitleSource: SubtitleSourceKind? = nil,
        outputFormat: OutputFormat? = nil
    ) {
        self.sourceVersionID = sourceVersionID
        self.changedFields = changedFields
        self.needsTranslation = needsTranslation
        self.needsBurn = needsBurn
        self.subtitleMode = subtitleMode
        self.previousSubtitleMode = previousSubtitleMode
        self.subtitleSource = subtitleSource
        self.outputFormat = outputFormat
    }

    /// Planning must use the user's edited Inspector draft, not the previous
    /// completed version. This keeps a nil → value subtitle/translation change
    /// from becoming an empty processing chain.
    public init(
        sourceVersionID: UUID,
        changedFields: Set<ReprocessChangedField>,
        configuration: LibraryProcessingConfiguration,
        previousConfiguration: LibraryProcessingConfiguration? = nil
    ) {
        let requestedMode = SubtitleModeSemantics(rawValue: configuration.subtitleMode)
        self.init(
            sourceVersionID: sourceVersionID,
            changedFields: changedFields,
            needsTranslation: requestedMode?.needsTranslation
                ?? (configuration.targetLanguage != nil || configuration.translationModel != nil),
            needsBurn: requestedMode?.needsBurn ?? (configuration.subtitleStyle != nil),
            subtitleMode: configuration.subtitleMode,
            previousSubtitleMode: previousConfiguration?.subtitleMode,
            subtitleSource: configuration.subtitleSource.flatMap(SubtitleSourceKind.init(rawValue:)),
            outputFormat: configuration.outputFormat.flatMap(OutputFormat.init(rawValue:))
        )
    }
}

private enum SubtitleModeSemantics: String {
    case off
    case srtOnly
    case burnIn
    case burnOriginal

    init?(rawValue: String?) {
        guard let rawValue else { return nil }
        self.init(rawValue: rawValue)
    }

    var needsTranslation: Bool {
        self == .srtOnly || self == .burnIn
    }

    var needsBurn: Bool {
        self == .burnIn || self == .burnOriginal
    }
}

public enum ReprocessStep: String, Codable, Sendable, Equatable, CaseIterable {
    /// Refreshes the selected source quality into the isolated version folder.
    /// It intentionally calls the download engine rather than pretending a
    /// local transcode can restore source quality or the original format.
    case refreshVideo
    case transcribe
    case translate
    case transcode
    case burn
}

public struct ReprocessPlan: Codable, Sendable, Equatable {
    public let sourceVersionID: UUID
    public let outputVersionID: UUID
    public let steps: [ReprocessStep]
    public let createsNewVersion: Bool

    public init(
        sourceVersionID: UUID,
        outputVersionID: UUID = UUID(),
        steps: [ReprocessStep],
        createsNewVersion: Bool = true
    ) {
        self.sourceVersionID = sourceVersionID
        self.outputVersionID = outputVersionID
        self.steps = steps
        self.createsNewVersion = createsNewVersion
    }
}

/// Maps Inspector changes to the smallest safe processing chain. A completed
/// version is immutable; every plan has a new output version id so no existing
/// artifacts are overwritten.
public enum ReprocessPlanner {
    public static func plan(for request: ReprocessRequest) -> ReprocessPlan {
        let transcriptionChanges: Set<ReprocessChangedField> = [.transcriptionModel]
        let translationChanges: Set<ReprocessChangedField> = [
            .targetLanguage,
            .translationModel
        ]

        var steps: [ReprocessStep] = []
        // The Inspector represents "使用默认" as nil. For a completed
        // transcoded artifact, its execution meaning is the app default of
        // `.original`, not "keep the previous transcode". Normalising here
        // keeps the planner and ViewModel's request construction aligned.
        let requestedOutputFormat = request.outputFormat ?? .original
        let requestedSubtitleMode = SubtitleModeSemantics(rawValue: request.subtitleMode)
        let previousSubtitleMode = SubtitleModeSemantics(rawValue: request.previousSubtitleMode)
        let removesRenderedSubtitles = request.changedFields.contains(.subtitleMode)
            && previousSubtitleMode?.needsBurn == true
            && requestedSubtitleMode?.needsBurn == false
        let refreshesSourceQuality = request.changedFields.contains(.quality)
            || (request.changedFields.contains(.outputFormat) && requestedOutputFormat == .original)
            || removesRenderedSubtitles
        // A fresh source refresh still needs an output conversion when the
        // saved/output draft asks for a non-original container or codec.
        let transcodesIsolatedVideo = !refreshesSourceQuality
            && request.changedFields.contains(.outputFormat)
        let transcodesRefreshedVideo = refreshesSourceQuality
            && requestedOutputFormat != .original
        let usesSubtitles = request.needsTranslation || request.needsBurn
        let subtitleSourceNeedsASR: Bool
        switch request.subtitleSource {
        case .localASR, .cloudASR:
            subtitleSourceNeedsASR = usesSubtitles && request.changedFields.contains(.subtitleSource)
        default:
            subtitleSourceNeedsASR = false
        }
        let shouldTranscribe = usesSubtitles
            && (!request.changedFields.isDisjoint(with: transcriptionChanges)
                || subtitleSourceNeedsASR)
        let shouldTranslate = request.needsTranslation
            && (!request.changedFields.isDisjoint(with: translationChanges)
                || shouldTranscribe
                || request.changedFields.contains(.subtitleSource)
                || request.changedFields.contains(.subtitleMode))

        if refreshesSourceQuality {
            steps.append(.refreshVideo)
        }
        if transcodesIsolatedVideo || transcodesRefreshedVideo {
            steps.append(.transcode)
        }
        if shouldTranscribe {
            steps.append(.transcribe)
        }
        if shouldTranslate {
            steps.append(.translate)
        }

        if request.needsBurn,
           !request.changedFields.isEmpty {
            steps.append(.burn)
        }

        return ReprocessPlan(sourceVersionID: request.sourceVersionID, steps: steps)
    }
}
