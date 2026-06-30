# Moongate UX ASR Productization ExecPlan

## Background And Product Intent

This plan implements the recommendations from `/Users/xianjingheng/Downloads/moongate_v2_ux_asr_fix_package`.

The product goal is to turn Moongate's subtitle recognition experience from an engineer-facing configuration surface into a consumer-grade product flow. Ordinary users should think in terms of:

- Use platform subtitles when they are good.
- Generate subtitles locally when subtitles are missing or poor.
- Choose standard vs more accurate recognition.
- Understand when audio leaves the device.
- Manage installable components in one place.

They should not need to understand VAD, sidecar runtimes, model paths, runtime paths, ffmpeg paths, whisper-cli paths, API cost warnings, or manually managed model files.

## Current Repository Understanding

Current working branch: `codex/ux-asr-productization`.

Current branch head after branch integration: `81bb740 Refine Moongate release and sync workflows`.

Remote reality, checked through GitHub API because SSH fetch failed:

- Remote `master` is `4a217a58c7f6acd1bf49487561b9a3ec8ab42169`.
- Remote `master` is a merge of `feature/language-first-subtitle-source`.
- Local tracking `origin/master` is stale at `fd44844`.
- Local branch `feature/language-first-subtitle-source` already contains the remote side's 5 commits and can be used as the merge source.

Git integration completed with:

```bash
git merge --ff-only feature/language-first-subtitle-source
```

The branch now includes the remote-complete `feature/language-first-subtitle-source` line. Local `origin/master` remains stale at `fd44844`, so use `feature/language-first-subtitle-source` / GitHub remote evidence as the current remote-complete baseline until fetch is refreshed.

Existing uncommitted work before this plan:

- `build.sh` has an existing app bundle metadata fix:
  - adds `CFBundleInfoDictionaryVersion`
  - adds `NSPrincipalClass`
  - writes `Contents/PkgInfo`
- Treat this as pre-existing user/worktree work and preserve it.

## Branch Audit

Keep / merge:

- `feature/language-first-subtitle-source`
  - 5 commits ahead of local `master`.
  - Already merged into remote `master`.
  - Large but coherent: subtitle source resolver, subtitle quality gates, local ASR confidence, Cloud ASR scaffolding/tests, cross-platform parity, queue/UI polishing, release docs.
  - Action: fast-forward or merge into `codex/ux-asr-productization` before productization edits.

Already absorbed or obsolete:

- `codex/v0.8-local-asr` and `codex/ja-lyrics-specialization`
  - No commits ahead of local master.
  - Already part of the v0.8 line.
- `codex/subtitle-segmenter-parity`
  - No commits ahead of local master.
- `feat/0.7.2-asr-resegment`
  - No commits ahead of local master.
- `fix/release-hardening`
  - No commits ahead of local master.
- `codex/macos-pkg-updater-on-v07`
  - No commits ahead of local master.
- `macOS`, `iOS/Android`, `codex/macos-pkg-updater-0.7`
  - Older product lines; do not merge directly.

Do not merge directly:

- `codex/v07-desktop-i18n-onboarding`
  - Direct branch diff would delete or revert a large amount of current v0.8 code, tests, docs, tools, and Windows surfaces.
  - Two unique old commits were inspected:
    - `638b542 Burn rendering: wider subtitles, smaller translation font, 96% opacity`
    - `67aa94b Sentence-aware subtitle re-segmentation for auto-captions`
  - The burn rendering change is already present in current `master` (`Burner.swift` has 13pt Chinese font, 2.5% horizontal margin, `chineseAlphaHex = "0A"`, and matching tests).
  - The old LLM resegmentation idea overlaps with later subtitle source/quality/ASR work and should not be cherry-picked wholesale.

## Requirements From GPT5.6 Pro Package

### Phase 1: Settings UX And Information Architecture

- Rename the visible settings pane from `本地语音识别` to `字幕识别`.
- Default settings UI shows ordinary user concepts only:
  - Recognition mode: automatic, always local, platform only.
  - Recognition quality: standard, more accurate.
  - Component status: offline subtitle recognition, voice boundary detection package, high-quality recognition component.
- Hide technical path fields behind `高级`, collapsed by default.
- Default UI must not show:
  - `VAD`
  - `sidecar`
  - `runtime path`
  - `model path`
  - `API cost`
  - `ffmpeg path`
  - `whisper-cli path`
- Cloud ASR must be hidden from stable UI or marked experimental until fully implemented.
- Keep old settings compatibility unless a migration is explicit.
- Add or update Chinese, Traditional Chinese, and English copy.

### Phase 2: Components, Storage, And Onboarding

- First-launch onboarding should distinguish:
  - required components: video download and processing tools
  - recommended components: offline subtitle recognition package
  - optional advanced components: high-quality local recognition
- Components and storage should manage:
  - video download tool
  - video processing tool
  - offline recognition engine
  - standard recognition model
  - voice boundary detection package
  - high-quality recognition component
- App-managed models/assets belong under App Support.
- Homebrew/global tools must not share remove/delete logic with app-managed models.
- Installation must support progress, cancel, retry, readable errors, temp download, checksum validation, and atomic move.

### Phase 3: VAD / Voice Boundary Detection

- Existing `ASRRequest.vadEnabled` is currently present but intentionally not wired to whisper.cpp argv.
- Add an app-managed VAD model path/settings contract.
- Only emit `--vad -vm <vad-model-path>` when:
  - VAD is enabled,
  - the model path is present,
  - the file exists and passes the chosen asset validation.
- Missing VAD must not fail local ASR.
- Preserve CJK anti-repetition and timing protections.
- Important repository-specific risk: previous docs record that whisper.cpp built-in Silero VAD may compress recognition into speech-only time and break subtitle time alignment. Treat VAD as a quality enhancer behind an explicit safe gate until real-time-axis QA proves it.

### Phase 4: High-Quality Recognition And Cloud ASR

- Ordinary UI says `更准确` / `高质量识别组件`.
- `sidecar` appears only in advanced UI as `自定义识别程序`.
- Add a `测试识别程序` flow before accepting custom executable/model settings.
- Cloud ASR:
  - default off
  - no upload before explicit confirmation
  - clear privacy and provider billing copy
  - cancellation, retry, and explainable errors
  - no fake SRT if the provider cannot provide time alignment

## Existing Code Findings

### macOS Settings

- `Sources/Moongate/SettingsView.swift` has a `SettingsPane.localSpeech` side pane and a `localSpeechSection`.
- The current ordinary local speech section exposes `whisper.cpp`, `whisper-cli`, model catalog, model import, and model delete flows.
- `SettingsView` already has model install progress through `ASRModelInstaller`.
- Existing tests assert that path text fields are not shown in the basic local ASR UI, but user-facing strings still expose technical language.
- After merging `feature/language-first-subtitle-source`, the baseline becomes more urgent:
  - the ordinary local speech section includes `LocalASRVADStatusView`;
  - precise mode exposes sidecar runtime and model path fields directly;
  - Cloud ASR exposes enablement, base URL, model, credential, and consent controls directly in the same ordinary pane.
- Therefore Phase 1 must not be treated as only a copy tweak. It must restructure the pane so VAD/sidecar/cloud implementation controls move into Components, Storage, Advanced, or Experimental surfaces.

### Settings Persistence

- `Sources/MoongateCore/Settings.swift` stores:
  - `localASREnabled`
  - `localASRRuntimePath`
  - `localASRModelPath`
  - `localASRModelID`
- Preserve these for compatibility.
- Add new user-intent fields separately, for example:
  - subtitle recognition mode
  - local recognition quality
  - VAD asset path/id
  - custom high-quality recognizer path/model path if needed

### Components And Assets

- `Sources/MoongateCore/DependencySetup.swift` handles Homebrew/global dependencies.
- `ASRModelManifest`, `ASRModelStore`, `ASRModelCatalog`, and `ASRModelInstaller` already provide most app-managed model asset mechanics for whisper models.
- Do not turn VAD into a Homebrew component.
- Prefer adding an app-managed asset abstraction only if it reduces real duplication between whisper model, VAD model, and high-quality recognition component.

### ASR Command Planner

- `ASRRequest.vadEnabled` defaults to true and is codable.
- The command planner intentionally does not emit `--vad`.
- Add `vadModelPath` as an optional contract rather than overloading `vadEnabled`.
- Mirror Swift and Windows behavior.

## Target Architecture

Use a three-layer model:

1. User intent:
   - recognition mode
   - quality
   - local/cloud preference
2. Capability readiness:
   - platform subtitles available
   - offline recognition ready
   - voice boundary package installed
   - high-quality component installed
   - cloud recognizer configured and confirmed
3. Implementation:
   - yt-dlp
   - ffmpeg/ffprobe
   - whisper-cli/runtime
   - whisper model
   - VAD model
   - sidecar/custom recognizer
   - cloud provider

Only layers 1 and 2 should appear in ordinary UI.

## Milestones

### Milestone 0: Branch Integration

- [x] Retry `git merge --ff-only feature/language-first-subtitle-source` once git approval is available.
- [x] Confirm `git log --oneline --decorate -5` includes the remote master merge/work.
- [x] Confirm `build.sh` pre-existing metadata change remains.
- [x] Run `git diff --stat` and record the final starting point.

### Milestone 1: Phase 1 Settings Productization

- [x] Add settings enums for subtitle recognition mode and local recognition quality while preserving legacy fields.
- [x] Rename visible local speech pane to `字幕识别`.
- [x] Rework `localSpeechSection` into:
  - header copy
  - recognition mode picker/cards
  - quality picker/cards
  - component status rows
  - links to Components and Storage
  - collapsed Advanced disclosure
- [x] After `feature/language-first-subtitle-source` is merged, move these existing controls out of the ordinary pane:
  - `LocalASRVADStatusView` into component status / Components and Storage
  - sidecar runtime/model path fields into Advanced as custom recognition program settings
  - Cloud ASR base URL/model/token/consent into Experimental or Advanced unless the full Cloud ASR gate passes
- [x] Replace ordinary copy in Simplified Chinese, Traditional Chinese, and English.
- [x] Update macOS settings boundary/localizer tests.
- [x] Keep default local ASR disabled unless existing settings already enabled it.

### Milestone 2: Components And Storage

- [x] Move model catalog/install UI out of the ordinary recognition settings into Components and Storage.
- [x] Group components into video tools, subtitle recognition, AI/summary.
- [x] Add one-click recommended component install flow for the current recommended offline recognition package.
- [x] Ensure app-managed model deletion never touches Homebrew/global tools.
- [x] Update onboarding copy and flow to present required vs recommended components.
- [x] Update storage accounting for VAD/high-quality recognition assets.

### Milestone 3: VAD Asset And Command Contract

- [x] Add VAD model settings fields with compatible decoding defaults.
- [x] Add an app-managed VAD asset surface using import, App Support storage, delete, status, and storage accounting.
- [x] Add `vadModelPath` to Swift ASR request contracts.
- [x] Mirror `vadModelPath` in Windows ASR request contracts where the feature exists.
- [x] Update command planner tests:
  - no path -> no `--vad`
  - missing path -> no `--vad`
  - existing path -> `--vad -vm <path>`
- [x] Gate default subtitle path so VAD does not break timing until real sample QA passes.
- [x] Add explicit QA note for time-axis preservation.

### Milestone 4: High-Quality Recognition

- [x] Hide `sidecar` from ordinary UI.
- [x] Surface `高质量识别组件` in ordinary component status and keep custom program details in Advanced.
- [x] Put custom executable/model path under Advanced only.
- [x] Add `测试识别程序` dry-run check.
- [x] Add readable local validation errors.
- [x] Add tests for custom recognizer readiness and UI boundaries.

### Milestone 5: Cloud ASR Gate

- [x] Audit current Cloud ASR implementation after merging `feature/language-first-subtitle-source`.
- [x] Keep Cloud ASR out of stable ordinary UI unless all package acceptance criteria are proven.
- [x] If shown, label it experimental and require explicit consent.
- [x] Add privacy/provider billing copy.
- [x] Add tests that no Cloud ASR generator is created before confirmation.

### Milestone 6: Cross-Platform Parity And Verification

- [x] Mirror user-facing settings and ASR contracts in Windows where the feature exists.
- [x] Run focused Swift tests.
- [x] Run focused Windows core tests if local dotnet environment permits.
- [x] Run `git diff --check`.
- [x] Build macOS app or run the narrowest build command that covers changed files.
- [x] Manually QA settings default UI for forbidden technical terms.

## Validation Commands

Start narrow:

```bash
swift test --filter ASRContractsTests
swift test --filter MacOSSettingsBoundaryTests
swift test --filter LocalizerTests
swift test --filter DependencySetupTests
git diff --check
```

Then broader:

```bash
swift test
zsh -n build.sh
zsh -n build-windows.sh
dotnet test windows/Moongate.Win.sln --nologo -v quiet
```

If SwiftPM cache or sandbox issues appear, prefer the repo's known scratch-path pattern:

```bash
swift test --scratch-path /private/tmp/moongate-swiftpm-productization
```

## Risks And Decisions

- Do not merge old branches wholesale unless they are proven ahead and compatible.
- Do not delete local or remote branches as part of this work.
- Do not rename internal ASR symbols just to make UI copy nicer.
- Do not ship Cloud ASR as stable UI unless upload, privacy, cost, cancellation, retry, error taxonomy, and timing alignment are proven.
- Do not default-enable local ASR, VAD, or cloud ASR on upgrade.
- Do not use whisper.cpp `--vad` blindly; the repository contains prior evidence that it can break subtitle timing.

## Progress Log

- 2026-06-28: Read GPT5.6 Pro package and extracted Phase 1-4 requirements.
- 2026-06-28: Created branch `codex/ux-asr-productization`.
- 2026-06-28: Found pre-existing `build.sh` metadata/PkgInfo change and marked it as preserved user/worktree work.
- 2026-06-28: Remote SSH fetch failed, but GitHub API confirmed remote `master` at `4a217a58`, with `feature/language-first-subtitle-source` merged.
- 2026-06-28: Classified old branches; only `feature/language-first-subtitle-source` needs integration before implementation.
- 2026-06-28: Attempted fast-forward merge; blocked by Codex approval/usage limit, not by repository conflict.
- 2026-06-28: Completed read-only code exploration of settings UI, ASR assets, VAD command contract, and branch state.
- 2026-06-28: Read the `feature/language-first-subtitle-source` versions of `SettingsView.swift`, `Settings.swift`, `CloudASR.swift`, and `SubtitleSourceResolver.swift`; confirmed that the remote-complete line adds useful subtitle quality/Cloud ASR infrastructure but also exposes VAD/sidecar/cloud settings in ordinary UI, which Phase 1 must productize.
- 2026-06-28: Fast-forwarded `feature/language-first-subtitle-source` into `codex/ux-asr-productization`; current branch head is `81bb740`.
- 2026-06-28: Productized the settings pane as `字幕识别`: ordinary UI now exposes recognition mode, quality, component readiness, and component management actions; technical path/cloud controls live under collapsed Advanced.
- 2026-06-28: Moved local ASR model catalog/install/import UI into Components and Storage and updated onboarding to distinguish required, recommended, and optional components.
- 2026-06-28: Added `subtitleRecognitionMode`, `localRecognitionQuality`, and explicit `localASRVADModelPath` settings with backward-compatible decoding.
- 2026-06-28: Changed VAD command behavior so whisper.cpp receives `--vad -vm <path>` only when VAD is enabled and an explicit existing VAD model path is present; missing VAD falls back to ordinary recognition.
- 2026-06-28: Removed the unused implicit VAD model locator to prevent accidental reintroduction of runtime-directory guessing.
- 2026-06-28: Added custom recognition program dry-run validation in Advanced, with trilingual readable status messages.
- 2026-06-28: Added a one-click recommended recognition component action for the current offline package and covered Cloud ASR consent gating.
- 2026-06-28: Focused Swift validation passed: `swift test --scratch-path /private/tmp/moongate-swiftpm-productization --filter 'CloudASRTests|ASRContractsTests|TranslationSettingsTests|MacOSSettingsBoundaryTests|MacOSViewModelBoundaryTests|MacOSContentBoundaryTests|LocalizerTests'` executed 335 tests with 0 failures.
- 2026-06-28: Mirrored the explicit VAD path contract in Windows (`LocalAsrVadModelPath`, `AsrRequest.VadModelPath`, `--vad -vm` only for explicit existing paths) and removed the Windows implicit VAD locator.
- 2026-06-28: Focused Windows validation passed: `dotnet test windows/MoongateCore.Tests/MoongateCore.Tests.csproj --nologo -v quiet --filter 'FullyQualifiedName~AsrContractsTests|FullyQualifiedName~SettingsTests|FullyQualifiedName~WindowsSettingsSurfaceTests'` passed 181 tests. NuGet vulnerability metadata lookup warned because `https://api.nuget.org/v3/index.json` was unreachable.
- 2026-06-28: Added VAD model import/delete into App Support under the recognition component surface, included the VAD store in storage accounting, and made "delete all ASR models" clear the managed VAD path.
- 2026-06-28: Re-ran focused Swift validation after VAD storage changes; 335 tests passed with 0 failures.
- 2026-06-28: Re-ran focused Windows validation; 181 tests passed with 0 failures. NuGet vulnerability metadata lookup still warned because `https://api.nuget.org/v3/index.json` was unreachable.
- 2026-06-28: `git diff --check` passed with no whitespace errors.
- 2026-06-28: Static UI QA confirmed forbidden technical controls/strings are contained in collapsed Advanced or Components surfaces, while the default recognition pane exposes mode, quality, status, and management actions.

## Completion Checklist

- [x] Remote-complete branch work integrated.
- [x] Ordinary settings UI no longer exposes forbidden technical terms.
- [x] Components and Storage owns installable recognition assets for the current offline recognition model package.
- [x] Onboarding separates required and recommended components.
- [x] VAD has a persisted explicit path, App Support managed import/delete surface, storage accounting, and safe argv gate.
- [x] High-quality recognition is productized and sidecar remains advanced-only.
- [x] Cloud ASR is hidden from ordinary UI, experimental in Advanced, and gated with consent tests.
- [x] Swift and Windows contracts remain compatible.
- [x] Focused tests and build checks pass or failures are clearly explained.
