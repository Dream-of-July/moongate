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

    public init(
        sourceVersionID: UUID,
        changedFields: Set<ReprocessChangedField>,
        needsTranslation: Bool,
        needsBurn: Bool
    ) {
        self.sourceVersionID = sourceVersionID
        self.changedFields = changedFields
        self.needsTranslation = needsTranslation
        self.needsBurn = needsBurn
    }
}

public enum ReprocessStep: String, Codable, Sendable, Equatable, CaseIterable {
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
        let transcriptionChanges: Set<ReprocessChangedField> = [
            .transcriptionModel,
            .subtitleSource
        ]
        let translationChanges: Set<ReprocessChangedField> = [
            .targetLanguage,
            .translationModel
        ]
        let transcodeChanges: Set<ReprocessChangedField> = [
            .outputFormat,
            .quality
        ]

        var steps: [ReprocessStep] = []

        if !request.changedFields.isDisjoint(with: transcriptionChanges) {
            steps.append(.transcribe)
            if request.needsTranslation {
                steps.append(.translate)
            }
        } else if !request.changedFields.isDisjoint(with: translationChanges) {
            if request.needsTranslation {
                steps.append(.translate)
            }
        } else if !request.changedFields.isDisjoint(with: transcodeChanges) {
            steps.append(.transcode)
        }

        if request.needsBurn,
           !request.changedFields.isEmpty {
            steps.append(.burn)
        }

        return ReprocessPlan(sourceVersionID: request.sourceVersionID, steps: steps)
    }
}
