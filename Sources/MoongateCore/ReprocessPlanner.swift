import Foundation

public enum ReprocessChangedField: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
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
        subtitleSource: SubtitleSourceKind? = nil,
        outputFormat: OutputFormat? = nil
    ) {
        self.sourceVersionID = sourceVersionID
        self.changedFields = changedFields
        self.needsTranslation = needsTranslation
        self.needsBurn = needsBurn
        self.subtitleSource = subtitleSource
        self.outputFormat = outputFormat
    }

    /// Planning must use the user's edited Inspector draft, not the previous
    /// completed version. This keeps a nil → value subtitle/translation change
    /// from becoming an empty processing chain.
    public init(
        sourceVersionID: UUID,
        changedFields: Set<ReprocessChangedField>,
        configuration: LibraryProcessingConfiguration
    ) {
        self.init(
            sourceVersionID: sourceVersionID,
            changedFields: changedFields,
            needsTranslation: configuration.targetLanguage != nil || configuration.translationModel != nil,
            needsBurn: configuration.subtitleStyle != nil,
            subtitleSource: configuration.subtitleSource.flatMap(SubtitleSourceKind.init(rawValue:)),
            outputFormat: configuration.outputFormat.flatMap(OutputFormat.init(rawValue:))
        )
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
        let refreshesSourceQuality = request.changedFields.contains(.quality)
            || (request.changedFields.contains(.outputFormat) && requestedOutputFormat == .original)
        // A fresh source refresh still needs an output conversion when the
        // saved/output draft asks for a non-original container or codec.
        let transcodesIsolatedVideo = !refreshesSourceQuality
            && request.changedFields.contains(.outputFormat)
        let transcodesRefreshedVideo = refreshesSourceQuality
            && requestedOutputFormat != .original
        let subtitleSourceNeedsASR: Bool
        switch request.subtitleSource {
        case .localASR, .cloudASR:
            subtitleSourceNeedsASR = request.changedFields.contains(.subtitleSource)
        default:
            subtitleSourceNeedsASR = false
        }
        let shouldTranscribe = !request.changedFields.isDisjoint(with: transcriptionChanges)
            || subtitleSourceNeedsASR
        let shouldTranslate = request.needsTranslation
            && (!request.changedFields.isDisjoint(with: translationChanges)
                || shouldTranscribe
                || request.changedFields.contains(.subtitleSource))

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
