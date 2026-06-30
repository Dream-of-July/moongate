import Foundation

public enum SubtitleSourceResolver {
    public static func resolve(_ request: SubtitleResolutionRequest) -> ResolvedSubtitleSource? {
        let requestedLanguage = normalizedLanguage(from: request.languageIntent)
        let candidates = filterByLanguage(request.candidates, requestedLanguage: requestedLanguage)
        guard !candidates.isEmpty else { return nil }

        // 评估 + 择优统一委托给 SubtitleSourceDecisionEngine（门每候选只跑一次、tie-break 单一口径）。
        let assessments = candidates.map {
            SubtitleSourceDecisionEngine.assess(
                candidate: $0,
                requestedSourceLanguageCode: requestedLanguage,
                videoDurationSeconds: request.videoDurationSeconds
            )
        }
        let selectableIDs = Set(candidates.compactMap { $0.fileURL == nil ? nil : $0.id })
        guard !selectableIDs.isEmpty,
              let winnerID = SubtitleSourceDecisionEngine.choose(
                policy: request.sourcePolicy,
                assessments: assessments,
                selectableIDs: selectableIDs
              ),
              let winner = assessments.first(where: { $0.candidateID == winnerID }),
              let selected = candidates.first(where: { $0.id == winnerID }) else {
            return nil
        }

        return ResolvedSubtitleSource(
            languageCode: selected.languageCode,
            selectedFile: selected.fileURL ?? URL(fileURLWithPath: ""),
            selectedKind: selected.kind,
            qualityVerdict: PlatformSubtitleQualityGate.Verdict(
                usable: winner.verdict >= .usable,
                reasons: [],
                report: winner.report ?? .empty
            ),
            sourceQualityVerdict: winner.verdict,
            usedLocalASRFallback: selected.kind == .localASR
                && candidates.contains { $0.kind != .localASR },
            fallbackReasons: [],
            candidateReports: assessments.map { assessment in
                SubtitleSourceCandidateReport(
                    sourceKind: assessment.kind,
                    languageCode: assessment.languageCode,
                    available: candidates.contains { $0.id == assessment.candidateID && $0.fileURL != nil },
                    selected: assessment.candidateID == winnerID,
                    usable: assessment.verdict >= .usable,
                    qualityVerdict: assessment.verdict,
                    reasons: assessment.reasons
                )
            }
        )
    }

    private static func normalizedLanguage(from intent: SourceLanguageIntent) -> String? {
        switch intent {
        case .automatic:
            return nil
        case .language(let code):
            let normalized = SubtitleLanguageChoice.normalizedLanguageCode(code)
            return normalized.isEmpty ? nil : normalized
        }
    }

    private static func filterByLanguage(
        _ candidates: [SubtitleSourceCandidate],
        requestedLanguage: String?
    ) -> [SubtitleSourceCandidate] {
        guard let requestedLanguage else { return candidates }
        let exact = candidates.filter {
            SubtitleLanguageChoice.normalizedLanguageCode($0.languageCode) == requestedLanguage
        }
        return exact.isEmpty ? candidates : exact
    }
}
