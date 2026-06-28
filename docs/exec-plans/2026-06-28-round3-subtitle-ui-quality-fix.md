# Round 3 Subtitle UI And Quality Fix ExecPlan

## Background And Product Intent

This plan implements `/Users/xianjingheng/Downloads/moongate_round3_subtitle_ui_code_review`.
The review says the previous direction drifted toward an engineering control panel and over-fitted quality rules. The product intent is to recover a consumer-grade subtitle flow:

- Users choose the subtitle result they want.
- Moongate explains the source-language evidence honestly.
- Moongate chooses the best subtitle source without exposing internal policy names in the main flow.
- Source subtitle quality gates never receive the translation target language as source evidence.
- Low-confidence subtitles warn and preserve files; only severe blockers fail the pipeline.

## Current Repository Understanding

Current branch: `codex/ux-asr-productization`.

Uncommitted work before this plan:

- `Sources/MoongateCore/TranslationOutputQualityGate.swift`
- `Sources/MoongateCore/Translator.swift`
- `Tests/MoongateCoreTests/ConfiguredTranslatorFallbackTests.swift`
- `Tests/MoongateCoreTests/TranslationSettingsTests.swift`
- `windows/MoongateCore.Tests/TranslatorTests.cs`
- `windows/MoongateCore/TranslationOutputQualityGate.cs`
- `windows/MoongateCore/Translator.cs`

These changes are the previous English leakage retry fix. They are not automatically accepted by this plan; they must be reconciled with Round 3 Phase 3, especially the requirement that likely untranslated English should warn/retry but should not discard the downloaded video.

Relevant existing files:

- Ready page UI: `Sources/Moongate/ContentView.swift`
- Ready state/request construction: `Sources/Moongate/ViewModel.swift`
- Language recommendation: `Sources/MoongateCore/SubtitleLanguageRecommender.swift`
- Subtitle policy and candidate models: `Sources/MoongateCore/SubtitleSourcePolicy.swift`
- Source scorer/resolver: `Sources/MoongateCore/SubtitleQualityScorer.swift`, `Sources/MoongateCore/SubtitleSourceResolver.swift`
- Pipeline source resolution: `Sources/Moongate/QueueManager.swift`
- Platform quality gate: `Sources/MoongateCore/PlatformSubtitleQualityGate.swift`
- Translation output quality gate: `Sources/MoongateCore/TranslationOutputQualityGate.swift`
- Windows mirrors: `windows/MoongateCore/*.cs`, `windows/MoongateApp/*`

## Goals

- Phase 1: Ready page shows `字幕输出`, `原声语言`, `字幕来源` as separate sections; normal UI avoids `sourcePolicy`, `platformAuto`, `localASR`, `compareLocalASR`, and language codes.
- Phase 2: Replace raw language-code recommendation with a catalog-backed recommendation carrying evidence, confidence, rarity, and auto-select safety.
- Phase 3: Rename and enforce source/candidate/target language boundaries; normal English/Chinese tech mixed subtitles do not fail; likely untranslated output retries at most once and then warns instead of losing the task.
- Phase 4: Make `autoBest` a fast two-stage source strategy; nil local/cloud ASR candidates are unusable; production scorer removes sample-specific phrase lists.
- Keep Swift and Windows behavior aligned where mirror code exists.

## Non-Goals

- Do not add new ASR engines, cloud providers, or model downloads in this round.
- Do not expose all world languages on the main Ready page.
- Do not promote rare languages into the main recommendation unless the evidence is high-confidence or user-selected.
- Do not make source-quality low confidence a fatal failure unless the subtitle is empty, unparsable, timeline-broken, or local ASR has a severe repeated loop.

## Milestones

### Milestone 0: Evidence And Safety Baseline

- [x] Read all 10 files in the Round 3 review package.
- [x] Inspect current branch and uncommitted previous translation leakage changes.
- [x] Confirm `.agent/PLANS.md` is absent and create this plan under `docs/exec-plans`.
- [x] Collect subagent read-only reports for UI/language, quality gate, and resolver/pipeline.
- [x] Run focused RED tests that encode the Round 3 failures before implementation.

### Milestone 1: Ready Page UI And Copy

- [x] Split Ready page subtitle controls into three sections: output, source language, source.
- [x] Replace the raw source-language menu with a consumer-facing summary plus `更改...`.
- [x] Add `SourceLanguagePickerSheet` with common languages, search, and advanced manual code entry.
- [x] Keep technical source policy controls under Advanced only.
- [x] Update Simplified Chinese, Traditional Chinese, and English localization copy.
- [x] Add boundary tests that assert main Ready UI does not expose technical policy names.

### Milestone 2: Language Catalog And Recommendation Confidence

- [x] Add `LanguageCatalog` for normalization, display names, aliases, common languages, and rare-language checks.
- [x] Add or replace recommendation output with evidence/confidence/rarity/should-auto-select metadata.
- [x] Prevent low-confidence rare languages such as `si` from becoming the main auto recommendation.
- [x] Preserve user explicit source-language selection without polluting global defaults.
- [x] Mirror pure logic and tests in Windows where applicable.

### Milestone 3: Source/Target Language Boundary And Translation Output Handling

- [x] Rename source subtitle gate parameters to `requestedSourceLanguageCode` and `candidateLanguageCode`.
- [x] Add tests proving `targetLanguageCode = zh-Hans` is never passed into `PlatformSubtitleQualityGate`.
- [x] Keep English auto captions usable when source/candidate are `en`.
- [x] Allow Chinese translations containing technical English tokens.
- [x] Change translated-output source leakage from fatal discard to retry-once plus warning/preserved output where the queue can continue.
- [x] Mirror Windows translation and quality gate behavior.

### Milestone 4: Resolver, AutoBest, And Scorer Cleanup

- [x] Change nil local/cloud ASR candidate score to `0`, verdict `.unusable`, reason `pendingGeneration` or `missingFile`.
- [x] Remove production hardcoded sample phrases from `SubtitleQualityScorer`.
- [x] Replace phrase-specific production scoring with generic features: short CJK cue fragmentation, repeated n-grams, low information density, script mismatch, sound-effect dominance.
- [x] Implement Fast Auto Best:
  - manual/official subtitles are used directly;
  - good platform auto captions are used without local ASR;
  - weak/unusable platform auto captions generate local ASR only when local ASR is available;
  - resolver compares only existing files;
  - low confidence completes with warning instead of failing.
- [x] Add Swift and Windows tests listed in `04_regression_test_plan.md`.

## Risks And Rollback

- UI changes can accidentally alter request construction. Mitigation: keep `DownloadRequest` compatibility tests and add explicit request-boundary tests.
- Quality thresholds can become overfit again. Mitigation: tests should assert generic reasons and scan production scorer for banned sample phrases.
- Translation leakage changes touch previous uncommitted work. Mitigation: keep focused translator tests and queue tests separate; do not revert user/worktree changes blindly.
- Windows parity may lag because WPF UI and C# core are separate. Mitigation: mirror pure logic first and document any UI-only follow-up explicitly.

Rollback: revert this plan's patches; previous compatibility fields remain intact.

## Decision Record

- 2026-06-28: Round 3 review package supersedes the earlier local assumption that source-language leakage should be a fatal translator error. The new target is retry/warn/preserve, with fatal only for severe structural blockers.
- 2026-06-28: `autoBest` should not always run local ASR. It should fast-accept good platform subtitles and only generate ASR for low-quality platform sources or explicit compare modes.
- 2026-06-28: Resolver only selects existing candidates. Generation belongs to `QueueManager`/pipeline.

## Progress Log

- 2026-06-28: Read `00_README.md`, `01_best_product_decision.md`, `02_code_review_findings.md`, `03_codex_master_prompt.md`, `04_regression_test_plan.md`, `05_copy_for_user_visible_ui.md`, and all four `codex_prompts/phase*.md` files.
- 2026-06-28: Confirmed current code still has Round 3 issues: Ready source language is inside source section, `SubtitleQualityScorer` treats nil local/cloud ASR as usable, scorer contains hardcoded sample phrases, and `shouldPrepareLocalASRSource` does not implement Fast Auto Best.
- 2026-06-28: Added `LanguageCatalog` on Swift and Windows; language recommendation now carries evidence, confidence, rarity, and auto-select safety.
- 2026-06-28: Reworked Ready page into separate `字幕输出`, `原声语言`, and `字幕来源` sections. Source language now uses a summary row plus searchable sheet; source policy remains in Advanced.
- 2026-06-28: Renamed platform quality-gate source/candidate parameters, added target-language contamination regression tests, and changed translated-output leakage handling to retry once and preserve output instead of fatal discard.
- 2026-06-28: Updated scorer/resolver so missing local/cloud ASR candidates are unusable, removed hardcoded production sample phrases, and implemented Fast Auto Best in Swift and Windows queue pipelines.
- 2026-06-28: Focused validation passed:
  - `swift test --scratch-path /private/tmp/moongate-round3-ui-boundary --filter MacOSContentBoundaryTests`
  - `swift test --scratch-path /private/tmp/moongate-round3-focused --filter 'MacOSViewModelBoundaryTests|SubtitleLanguageRecommenderTests|SubtitleSourceResolverTests|PlatformSubtitleQualityGateTests/testHealthyAutoCaptionUsable'`
  - `swift test --scratch-path /private/tmp/moongate-round3-gate --filter 'PlatformSubtitleQualityGateTests|SubtitleSourceResolverTests'`
  - `swift test --scratch-path /private/tmp/moongate-round3-translation --filter 'ConfiguredTranslatorFallbackTests|TranslationSettingsTests/testTranslationOutputDetectsSourceLanguageLeakage'`
  - `swift test --scratch-path /private/tmp/moongate-round3-queue --filter 'MacOSQueueBoundaryTests|SubtitleSourceResolverTests'`
  - `dotnet test windows/MoongateCore.Tests/MoongateCore.Tests.csproj --nologo -v quiet --filter 'FullyQualifiedName~SubtitleLanguageRecommenderTests|FullyQualifiedName~SubtitleSourceResolverTests'`
  - `dotnet test windows/MoongateCore.Tests/MoongateCore.Tests.csproj --nologo -v quiet --filter 'FullyQualifiedName~PlatformSubtitleQualityGateTests|FullyQualifiedName~SubtitleSourceResolverTests'`
  - `dotnet test windows/MoongateCore.Tests/MoongateCore.Tests.csproj --nologo -v normal --filter 'FullyQualifiedName~Translate_PreservesOutputWhenSourceLanguageLeakageRetryStillLooksBad|FullyQualifiedName~Translate_RetriesOnceWhenEnglishSourceLeakageIsDetected|FullyQualifiedName~TranslationQuality_AllowsChineseTechTranslationWithEnglishTerms'`
  - `dotnet test windows/MoongateCore.Tests/MoongateCore.Tests.csproj --nologo -v quiet --filter 'FullyQualifiedName~AutoBestKeepsGoodEnglishPlatformCaptionWithoutRunningAsr|FullyQualifiedName~AutoCaptionLowQualityFallsBackToLocalAsr|FullyQualifiedName~CompareLocalAsrPolicyGeneratesLocalAsrEvenWhenAutoCaptionIsUsable|FullyQualifiedName~CompareLocalAsrPolicyChoosesHigherScoredLocalAsrEvenWhenPlatformUsable|FullyQualifiedName~LowQualityButLocalAsrUnavailableDoesNotCrash|FullyQualifiedName~PrimaryPlatformSubtitleTrackUsesPlatformFileEvenWhenLocalAsrFileExists'`
- 2026-06-28: Full validation passed:
  - `swift test --scratch-path /private/tmp/moongate-round3-full-swift` passed 632 tests.
  - `dotnet test windows/MoongateCore.Tests/MoongateCore.Tests.csproj --nologo -v quiet` passed 728 tests with NU1900 vulnerability-feed warnings because `api.nuget.org` was unavailable.
  - `git diff --check` passed.
- 2026-06-28: Installed `/Applications/月之门.app` with `MOONGATE_BUILD_NUMBER=8006 ./build.sh`; verified `CFBundleShortVersionString=0.8.0`, `CFBundleVersion=8006`, executable bit, and `codesign --verify --deep --strict --verbose=2`.

## Final Validation Checklist

- [x] Focused Swift tests for language recommendation, Ready UI boundaries, platform gate, scorer/resolver, and translator output handling pass.
- [x] Focused Windows core tests for mirrored recommender/gate/scorer/resolver/translator behavior pass.
- [x] Broader Swift test slice passes.
- [x] Windows core test slice passes.
- [x] `git diff --check` passes.
- [x] Installed macOS app is rebuilt and verified only after code/test validation.
