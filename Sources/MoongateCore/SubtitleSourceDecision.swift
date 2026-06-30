import Foundation

public enum SubtitleASRTrigger: String, Codable, Equatable, Sendable {
    case never
    case fallbackOnly
    case explicitCompare
    case explicitForce
}

public enum SubtitleSourceDecisionCandidateStatus: String, Codable, Equatable, Sendable {
    case selected
    case backup
    case notUsed
    case unavailable
}

public enum SubtitleSourceDecisionReason: String, Codable, Equatable, Sendable {
    case importedSubtitleExplicit
    case manualMatchesVideoLanguage
    case manualMatchesUserLanguage
    case manualMatchesInferredLanguage
    case platformSubtitleMatchesVideoLanguage
    case platformSubtitleMatchesUserLanguage
    case platformSubtitleMatchesInferredLanguage
    case platformAutoMatchesVideoLanguage
    case platformAutoMatchesUserLanguage
    case platformAutoMatchesInferredLanguage
    case targetLanguageSubtitleNotSource
    case manualLanguageMismatch
    case platformLanguageMismatch
    case localRecognitionFallbackOnly
    case localRecognitionForced
    case compareRequested
    case cloudRecognitionForced
    case cloudRecognitionUnavailable
    case noTrustedPlatformSubtitle
    case noUsableSubtitleSource
}

public enum SubtitleSourceLanguageEvidence: String, Codable, Equatable, Sendable {
    case userPreference
    case metadata
    case titleScript
    case unavailable
}

public enum SubtitleSourceLanguageConfidence: String, Codable, Equatable, Sendable {
    case high
    case medium
    case low
    case unknown
}

public struct SubtitleSourceDecisionCandidateReport: Equatable, Sendable {
    public let trackID: String
    public let sourceKind: SubtitleSourceKind
    public let languageCode: String
    public let label: String
    public let status: SubtitleSourceDecisionCandidateStatus
    public let reason: SubtitleSourceDecisionReason

    public init(
        trackID: String,
        sourceKind: SubtitleSourceKind,
        languageCode: String,
        label: String,
        status: SubtitleSourceDecisionCandidateStatus,
        reason: SubtitleSourceDecisionReason
    ) {
        self.trackID = trackID
        self.sourceKind = sourceKind
        self.languageCode = languageCode
        self.label = label
        self.status = status
        self.reason = reason
    }
}

public struct SubtitleSourceDecisionReport: Equatable, Sendable {
    public let selectedTrack: SubtitleChoice?
    public let candidateReports: [SubtitleSourceDecisionCandidateReport]
    public let asrTrigger: SubtitleASRTrigger
    public let userFacingReason: SubtitleSourceDecisionReason
    public let diagnosticReason: SubtitleSourceDecisionReason
    public let sourceLanguageCode: String?
    public let sourceLanguageEvidence: SubtitleSourceLanguageEvidence
    public let sourceLanguageConfidence: SubtitleSourceLanguageConfidence

    public init(
        selectedTrack: SubtitleChoice?,
        candidateReports: [SubtitleSourceDecisionCandidateReport],
        asrTrigger: SubtitleASRTrigger,
        userFacingReason: SubtitleSourceDecisionReason,
        diagnosticReason: SubtitleSourceDecisionReason,
        sourceLanguageCode: String?,
        sourceLanguageEvidence: SubtitleSourceLanguageEvidence,
        sourceLanguageConfidence: SubtitleSourceLanguageConfidence
    ) {
        self.selectedTrack = selectedTrack
        self.candidateReports = candidateReports
        self.asrTrigger = asrTrigger
        self.userFacingReason = userFacingReason
        self.diagnosticReason = diagnosticReason
        self.sourceLanguageCode = sourceLanguageCode
        self.sourceLanguageEvidence = sourceLanguageEvidence
        self.sourceLanguageConfidence = sourceLanguageConfidence
    }
}

public enum SubtitleSourceDecision {
    private struct Selection {
        let track: SubtitleChoice?
        let reason: SubtitleSourceDecisionReason
        let asrTrigger: SubtitleASRTrigger
    }

    public static func decide(
        videoTitle: String,
        detectedLanguageCode: String?,
        targetLanguageCode: String?,
        preferredSourceLanguageCode: String?,
        sourcePolicy: SubtitleSourcePolicy,
        choices: [SubtitleChoice],
        localASRAvailable: Bool,
        cloudASRAvailable: Bool
    ) -> SubtitleSourceDecisionReport {
        let explicitSourceLanguage = normalizedExplicitSourceLanguage(preferredSourceLanguageCode)
        let metadataLanguage = normalizedLanguage(detectedLanguageCode)
        let titleLanguage = explicitSourceLanguage == nil && metadataLanguage == nil
            ? normalizedLanguage(SubtitleLanguageRecommender.inferredLocalASRLanguageCode(title: videoTitle))
            : nil
        let sourceLanguageCode = explicitSourceLanguage ?? metadataLanguage ?? titleLanguage
        let sourceLanguageEvidence: SubtitleSourceLanguageEvidence
        let sourceLanguageConfidence: SubtitleSourceLanguageConfidence
        if explicitSourceLanguage != nil {
            sourceLanguageEvidence = .userPreference
            sourceLanguageConfidence = .high
        } else if metadataLanguage != nil {
            sourceLanguageEvidence = .metadata
            sourceLanguageConfidence = .high
        } else if titleLanguage != nil {
            sourceLanguageEvidence = .titleScript
            sourceLanguageConfidence = .low
        } else {
            sourceLanguageEvidence = .unavailable
            sourceLanguageConfidence = .unknown
        }

        let targetLanguage = normalizedLanguage(targetLanguageCode)
        let selection = selectTrack(
            choices: choices,
            sourceLanguageCode: sourceLanguageCode,
            sourceLanguageEvidence: sourceLanguageEvidence,
            targetLanguageCode: targetLanguage,
            sourcePolicy: sourcePolicy,
            localASRAvailable: localASRAvailable,
            cloudASRAvailable: cloudASRAvailable
        )
        let reports = candidateReports(
            choices: choices,
            selected: selection.track,
            selectedReason: selection.reason,
            sourceLanguageCode: sourceLanguageCode,
            targetLanguageCode: targetLanguage,
            localASRAvailable: localASRAvailable,
            cloudASRAvailable: cloudASRAvailable
        )
        return SubtitleSourceDecisionReport(
            selectedTrack: selection.track,
            candidateReports: reports,
            asrTrigger: selection.asrTrigger,
            userFacingReason: selection.reason,
            diagnosticReason: selection.reason,
            sourceLanguageCode: sourceLanguageCode,
            sourceLanguageEvidence: sourceLanguageEvidence,
            sourceLanguageConfidence: sourceLanguageConfidence
        )
    }

    private static func selectTrack(
        choices: [SubtitleChoice],
        sourceLanguageCode: String?,
        sourceLanguageEvidence: SubtitleSourceLanguageEvidence,
        targetLanguageCode: String?,
        sourcePolicy: SubtitleSourcePolicy,
        localASRAvailable: Bool,
        cloudASRAvailable: Bool
    ) -> Selection {
        switch sourcePolicy {
        case .importedFile:
            if let imported = firstTrack(
                in: choices,
                sourceLanguageCode: sourceLanguageCode,
                targetLanguageCode: targetLanguageCode,
                kinds: [.importedFile]
            ) {
                return Selection(track: imported, reason: .importedSubtitleExplicit, asrTrigger: .never)
            }
        case .forceLocalASR:
            if let local = firstLocalASR(in: choices, sourceLanguageCode: sourceLanguageCode) {
                return Selection(track: local, reason: .localRecognitionForced, asrTrigger: .explicitForce)
            }
        case .cloudASR:
            if cloudASRAvailable,
               let cloud = firstTrack(
                in: choices,
                sourceLanguageCode: sourceLanguageCode,
                targetLanguageCode: targetLanguageCode,
                kinds: [.cloudASR]
               ) {
                return Selection(track: cloud, reason: .cloudRecognitionForced, asrTrigger: .explicitForce)
            }
            return Selection(track: nil, reason: .cloudRecognitionUnavailable, asrTrigger: .never)
        case .forcePlatform:
            if let platform = firstPlatformTrack(
                in: choices,
                sourceLanguageCode: sourceLanguageCode,
                targetLanguageCode: targetLanguageCode,
                allowAnyLanguageFallback: true
            ) {
                return Selection(
                    track: platform,
                    reason: reasonForPlatformSelection(platform, evidence: sourceLanguageEvidence),
                    asrTrigger: .never
                )
            }
        case .preferLocalASR:
            if localASRAvailable,
               let local = firstLocalASR(in: choices, sourceLanguageCode: sourceLanguageCode) {
                return Selection(track: local, reason: .localRecognitionForced, asrTrigger: .explicitForce)
            }
        case .compareLocalASR:
            if let auto = firstAutoTrack(
                in: choices,
                sourceLanguageCode: sourceLanguageCode,
                targetLanguageCode: targetLanguageCode,
                allowAnyLanguageFallback: true
            ) {
                return Selection(track: auto, reason: .compareRequested, asrTrigger: .explicitCompare)
            }
            if let local = firstLocalASR(in: choices, sourceLanguageCode: sourceLanguageCode) {
                return Selection(track: local, reason: .compareRequested, asrTrigger: .explicitForce)
            }
        case .autoBest, .preferPlatform:
            break
        }

        if sourcePolicy == .preferPlatform,
           let platform = firstPlatformTrack(
            in: choices,
            sourceLanguageCode: sourceLanguageCode,
            targetLanguageCode: targetLanguageCode,
            allowAnyLanguageFallback: true
           ) {
            return Selection(
                track: platform,
                reason: reasonForPlatformSelection(platform, evidence: sourceLanguageEvidence),
                asrTrigger: platform.sourceKind == .platformAuto ? .fallbackOnly : .never
            )
        }

        if let manual = firstTrack(
            in: choices,
            sourceLanguageCode: sourceLanguageCode,
            targetLanguageCode: targetLanguageCode,
            kinds: [.manual]
        ) {
            return Selection(
                track: manual,
                reason: reasonForManualSelection(evidence: sourceLanguageEvidence),
                asrTrigger: .never
            )
        }
        if let official = firstTrack(
            in: choices,
            sourceLanguageCode: sourceLanguageCode,
            targetLanguageCode: targetLanguageCode,
            kinds: [.hlsManifest]
        ) {
            return Selection(
                track: official,
                reason: reasonForPlatformSelection(official, evidence: sourceLanguageEvidence),
                asrTrigger: .never
            )
        }
        if let auto = firstAutoTrack(
            in: choices,
            sourceLanguageCode: sourceLanguageCode,
            targetLanguageCode: targetLanguageCode,
            allowAnyLanguageFallback: sourceLanguageCode == nil
        ) {
            return Selection(
                track: auto,
                reason: reasonForPlatformSelection(auto, evidence: sourceLanguageEvidence),
                asrTrigger: .fallbackOnly
            )
        }
        if localASRAvailable,
           let local = firstLocalASR(in: choices, sourceLanguageCode: sourceLanguageCode) {
            return Selection(track: local, reason: .noTrustedPlatformSubtitle, asrTrigger: .fallbackOnly)
        }
        return Selection(track: nil, reason: .noUsableSubtitleSource, asrTrigger: .never)
    }

    private static func firstPlatformTrack(
        in choices: [SubtitleChoice],
        sourceLanguageCode: String?,
        targetLanguageCode: String?,
        allowAnyLanguageFallback: Bool
    ) -> SubtitleChoice? {
        firstTrack(
            in: choices,
            sourceLanguageCode: sourceLanguageCode,
            targetLanguageCode: targetLanguageCode,
            kinds: [.manual, .hlsManifest, .platformAuto],
            allowAnyLanguageFallback: allowAnyLanguageFallback
        )
    }

    private static func firstAutoTrack(
        in choices: [SubtitleChoice],
        sourceLanguageCode: String?,
        targetLanguageCode: String?,
        allowAnyLanguageFallback: Bool
    ) -> SubtitleChoice? {
        let eligible = choices.enumerated().filter { _, track in
            track.sourceKind == .platformAuto
                && !isTargetLanguageOnly(track, sourceLanguageCode: sourceLanguageCode, targetLanguageCode: targetLanguageCode)
                && (sourceLanguageCode == nil || languageMatches(track, sourceLanguageCode: sourceLanguageCode))
        }
        if let exact = eligible.sorted(by: autoTrackSort).first?.element { return exact }
        guard allowAnyLanguageFallback else { return nil }
        return choices.enumerated().filter { _, track in
            track.sourceKind == .platformAuto
                && !isTargetLanguageOnly(track, sourceLanguageCode: sourceLanguageCode, targetLanguageCode: targetLanguageCode)
        }.sorted(by: autoTrackSort).first?.element
    }

    private static func firstTrack(
        in choices: [SubtitleChoice],
        sourceLanguageCode: String?,
        targetLanguageCode: String?,
        kinds: Set<SubtitleSourceKind>,
        allowAnyLanguageFallback: Bool = false
    ) -> SubtitleChoice? {
        let exact = choices.first { track in
            kinds.contains(track.sourceKind)
                && !isTargetLanguageOnly(track, sourceLanguageCode: sourceLanguageCode, targetLanguageCode: targetLanguageCode)
                && (sourceLanguageCode == nil || languageMatches(track, sourceLanguageCode: sourceLanguageCode))
        }
        if let exact { return exact }
        guard allowAnyLanguageFallback else { return nil }
        return choices.first { track in
            kinds.contains(track.sourceKind)
                && !isTargetLanguageOnly(track, sourceLanguageCode: sourceLanguageCode, targetLanguageCode: targetLanguageCode)
        }
    }

    private static func firstLocalASR(
        in choices: [SubtitleChoice],
        sourceLanguageCode: String?
    ) -> SubtitleChoice? {
        if let sourceLanguageCode,
           let exact = choices.first(where: {
            $0.sourceKind == .localASR && normalizedLanguage($0.languageCode) == sourceLanguageCode
           }) {
            return exact
        }
        return choices.first { $0.sourceKind == .localASR }
    }

    private static func candidateReports(
        choices: [SubtitleChoice],
        selected: SubtitleChoice?,
        selectedReason: SubtitleSourceDecisionReason,
        sourceLanguageCode: String?,
        targetLanguageCode: String?,
        localASRAvailable: Bool,
        cloudASRAvailable: Bool
    ) -> [SubtitleSourceDecisionCandidateReport] {
        choices.map { track in
            let status: SubtitleSourceDecisionCandidateStatus
            let reason: SubtitleSourceDecisionReason
            if track.id == selected?.id {
                status = .selected
                reason = selectedReason
            } else if track.sourceKind == .localASR {
                status = localASRAvailable ? .backup : .unavailable
                reason = .localRecognitionFallbackOnly
            } else if track.sourceKind == .cloudASR {
                status = cloudASRAvailable ? .backup : .unavailable
                reason = cloudASRAvailable ? .cloudRecognitionForced : .cloudRecognitionUnavailable
            } else if isTargetLanguageOnly(track, sourceLanguageCode: sourceLanguageCode, targetLanguageCode: targetLanguageCode) {
                status = .notUsed
                reason = .targetLanguageSubtitleNotSource
            } else if isPlatformKind(track.sourceKind),
                      sourceLanguageCode != nil,
                      languageMatches(track, sourceLanguageCode: sourceLanguageCode) {
                status = .backup
                reason = track.sourceKind == .manual
                    ? .manualMatchesVideoLanguage
                    : .platformAutoMatchesVideoLanguage
            } else if track.sourceKind == .manual {
                status = .notUsed
                reason = .manualLanguageMismatch
            } else {
                status = .notUsed
                reason = .platformLanguageMismatch
            }
            return SubtitleSourceDecisionCandidateReport(
                trackID: track.id,
                sourceKind: track.sourceKind,
                languageCode: track.languageCode,
                label: track.label,
                status: status,
                reason: reason
            )
        }
    }

    private static func reasonForManualSelection(
        evidence: SubtitleSourceLanguageEvidence
    ) -> SubtitleSourceDecisionReason {
        switch evidence {
        case .userPreference:
            return .manualMatchesUserLanguage
        case .metadata:
            return .manualMatchesVideoLanguage
        case .titleScript:
            return .manualMatchesInferredLanguage
        case .unavailable:
            return .manualMatchesInferredLanguage
        }
    }

    private static func reasonForPlatformSelection(
        _ track: SubtitleChoice,
        evidence: SubtitleSourceLanguageEvidence
    ) -> SubtitleSourceDecisionReason {
        let isAuto = track.sourceKind == .platformAuto
        switch evidence {
        case .userPreference:
            return isAuto ? .platformAutoMatchesUserLanguage : .platformSubtitleMatchesUserLanguage
        case .metadata:
            return isAuto ? .platformAutoMatchesVideoLanguage : .platformSubtitleMatchesVideoLanguage
        case .titleScript, .unavailable:
            return isAuto ? .platformAutoMatchesInferredLanguage : .platformSubtitleMatchesInferredLanguage
        }
    }

    private static func isPlatformKind(_ kind: SubtitleSourceKind) -> Bool {
        kind == .manual || kind == .platformAuto || kind == .hlsManifest
    }

    private static func isTargetLanguageOnly(
        _ track: SubtitleChoice,
        sourceLanguageCode: String?,
        targetLanguageCode: String?
    ) -> Bool {
        guard let targetLanguageCode,
              normalizedLanguage(track.languageCode) == targetLanguageCode else { return false }
        return sourceLanguageCode != targetLanguageCode
    }

    private static func languageMatches(
        _ track: SubtitleChoice,
        sourceLanguageCode: String?
    ) -> Bool {
        guard let sourceLanguageCode else { return false }
        return normalizedLanguage(track.languageCode) == sourceLanguageCode
    }

    private static func normalizedExplicitSourceLanguage(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "auto" else { return nil }
        return normalizedLanguage(trimmed)
    }

    private static func normalizedLanguage(_ value: String?) -> String? {
        let normalized = LanguageCatalog.normalize(value)
        return normalized.isEmpty ? nil : normalized
    }

    private static func autoTrackSort(
        lhs: (offset: Int, element: SubtitleChoice),
        rhs: (offset: Int, element: SubtitleChoice)
    ) -> Bool {
        let lhsOrig = isOriginalAutoVariant(lhs.element) ? 0 : 1
        let rhsOrig = isOriginalAutoVariant(rhs.element) ? 0 : 1
        if lhsOrig != rhsOrig { return lhsOrig < rhsOrig }
        return lhs.offset < rhs.offset
    }

    private static func isOriginalAutoVariant(_ track: SubtitleChoice) -> Bool {
        let code = track.languageCode.lowercased()
        if code.contains("-orig") { return true }
        if track.variant?.lowercased().contains("orig") == true { return true }
        return track.metadata["isOrig"] == "true" || track.metadata["ytDlpIsOriginal"] == "true"
    }
}
