# macOS Apple Intelligence Translation And HIG ExecPlan

## Background And Product Intent

July wants the macOS client to evolve as a polished native Mac app, with the main agent acting as product owner and integrator while subagents work on bounded slices. The feature goal has two tracks:

- Add Apple translation engine choices: Apple Translation, local Apple Intelligence/Foundation Models, future local Apple Intelligence variants, and cloud/PCC/Cloud Pro options with honest availability gates.
- Audit the current UI against macOS HIG and, after July confirms direction, optimize the interface toward a quieter, more elegant, smoother native workflow.

The app runs on an enterprise-managed computer. Implementation must avoid secret exposure, system policy bypasses, unconfirmed cloud claims, and dependency installation without clear confirmation.

## Current Repository Understanding

- `Sources/MoongateCore/Settings.swift` owns persisted translation settings, including the shared `TranslationEngine`, `TranslationContext`, and `TranslationReadiness` contract.
- `Sources/MoongateCore/Translator.swift` owns SRT parsing/cleaning and translation routing. Anthropic/OpenAI-compatible engines use the cloud path, Apple Translation low-latency/high-fidelity use the guarded subtitle executor path when runtime requirements are met, Foundation on-device uses the guarded Foundation Models path, and direct LLM message/model-list calls still reject Apple engines.
- `Sources/Moongate/ContentView.swift` owns the main single-window workflow and opens Settings, dependency setup, and login as sheets.
- `Sources/Moongate/SettingsView.swift` owns the current sheet-based settings form and cloud model fetch/test flow.
- `Sources/Moongate/QueueOverlayView.swift` and `QueueSectionView.swift` implement a bottom overlay queue that can cover the main task content.
- `Sources/Moongate/DependencySetupView.swift` can run `brew install` for missing dependencies from inside a sheet.
- `Sources/Moongate/LoginWebView.swift` wraps `WKWebView`, exports cookies for downloader compatibility, and now has compact Back, Reload, Open in Browser controls, loading state, host/path display, and target-site cookie readiness. Cookie export scope and save gating remain product decisions.
- `Package.swift` has a macOS 14 package baseline; Apple-only frameworks must be isolated with conditional imports and availability checks.

## Platform Evidence

- Local toolchain: Xcode 26.5, Swift 6.3.2, macOS SDK 26.5.
- `Translation.framework` exists in the local macOS SDK. `LanguageAvailability` is available from iOS 18/macOS 15 and exposes `status(...)`; `TranslationSession` is available from iOS 18/macOS 15 and exposes `translate`, batch translation, and `prepareTranslation`. macOS 26 adds `isReady`, `canRequestDownloads`, and `cancel`; macOS 26.4 adds `TranslationSession.Strategy.highFidelity` and `.lowLatency`.
- `FoundationModels.framework` exists in the local macOS SDK. `SystemLanguageModel` is available from iOS 26/macOS 26/visionOS 26. Availability can be `.available` or `.unavailable(.deviceNotEligible/.appleIntelligenceNotEnabled/.modelNotReady)`. It exposes `supportedLanguages`, `supportsLocale`, `contextSize`, `LanguageModelSession`, `Generable`, and structured generation support.
- No verified iOS 27/macOS 27 SDK is present in this environment. Future OS support must be expressed as runtime capability detection and copy, not as a compile-time claim.
- No public third-party running adapter for Apple Intelligence Cloud Pro/PCC has been verified yet. Until official evidence proves otherwise, PCC/Cloud Pro must remain an unavailable/gated product state, not a working translator.

## Goals

- Preserve the existing Anthropic-compatible and OpenAI-compatible settings flow and model picker.
- Add a stable engine model that can represent Apple Translation low latency/high fidelity, Foundation on-device, and Cloud/PCC/Cloud Pro without requiring API tokens.
- Add readiness surfaces so the UI can explain: missing cloud config, unsupported OS, unsupported language pair, language package not installed, Apple Intelligence off, device not eligible, model not ready, and PCC/Cloud Pro unavailable.
- Implement only adapters backed by verified public APIs and keep unsupported/future engines honest.
- Create a macOS HIG issue inventory and implement low-risk polish immediately only when it does not preempt larger confirmed design decisions.
- Prepare the larger UI restructure for July confirmation: Settings scene, non-covering queue panel, dependency confirmation wizard, richer login window, and Reduce Motion support.

## Non-Goals

- Do not claim iOS 27/macOS 27-specific implementation without an SDK or official docs.
- Do not implement a fake PCC/Cloud Pro translator.
- Do not download Apple language packs, install dependencies, or make network calls without an explicit user action.
- Do not move secrets into logs, tests, docs, screenshots, or PR text.
- Do not redesign the whole UI before July confirms the larger HIG direction.
- Do not remove the existing cloud translation behavior.

## Suggested Architecture

### Core

- Keep `TranslationProvider` for legacy CLI/API compatibility.
- Use `TranslationEngine` as the product-facing choice.
- Add `TranslationEngine.DisplayMetadata` or computed properties for label, detail, availability family, and whether it needs cloud credentials.
- Add `TranslationReadinessEvaluator` protocol and a default evaluator that can be unit-tested without Apple frameworks.
- Add Apple framework adapters in separate files:
  - `AppleTranslationSupport.swift` behind `#if canImport(Translation)`.
  - `AppleFoundationModelsSupport.swift` behind `#if canImport(FoundationModels)`.
- Keep MoongateCore buildable on macOS 14 and Windows by guarding imports and unavailable symbols.

### UI

- Short term: make `SettingsView` engine-aware, showing credential fields only for compatible API engines and showing clear Apple readiness rows for Apple engines.
- Larger confirmed direction: move Settings to `Settings` scene with `Cmd+,`; split pages into General, Translation, Subtitles, Accounts, Dependencies, Advanced.
- Replace `QueueOverlayView` with a non-covering side panel or split layout after July confirms direction.
- Replace dependency one-click install with an install-plan wizard.
- Preserve the completed compact login browser controls and target-cookie readiness while deferring any larger login task-window or cookie-gating decision.
- Respect Reduce Motion for queue transitions and progress ring animation.

## Milestones

### M1: Core Engine And Readiness Contract

- Finish `TranslationEngine`, context, readiness issue taxonomy, and settings migration.
- Add tests for migration, cloud config requirements, Apple readiness issue mapping, and Codable stability.
- Keep unsupported Apple engines from silently entering the existing LLM request path.

### M2: Apple Translation / Foundation Gating

- Add framework-isolated support files.
- Implement readiness checks using verified public symbols.
- For Apple Translation, expose language availability and preparation state. If direct app-created `TranslationSession` proves safe in CLI/core, add an adapter; otherwise route the actual session through a macOS UI host.
- For Foundation Models, add local availability mapping and a gated adapter only after a compile-tested skeleton proves the API can be used from this target.
- Keep PCC/Cloud Pro as gated unavailable until public adapter evidence exists.

### M3: Settings Translation UI

- Add engine picker and Apple readiness copy.
- Show setup guidance for no local Apple Intelligence: supported Mac/system requirement, System Settings path, model/language download action, and fallback to Apple Translation/API-compatible engines.
- Preserve the existing two-protocol simple cloud model picker.

### M4: HIG Quick Wins

- Rename misleading buttons.
- Add Reduce Motion support.
- Add accessibility labels/values for URL input, queue handle, and progress ring.
- Make error details collapsible.

### M5: Larger HIG Restructure After Confirmation

- Settings scene.
- Non-covering queue panel.
- Dependency install wizard.
- Login task-window and cookie-gating decisions; compact browser controls already exist.
- Window sizing and toolbar cleanup.

## Subagent Work Plan

- `docs_researcher`: verify Apple official docs for Translation, FoundationModels, and PCC/Cloud Pro boundaries.
- `codebase_explorer`: map current data flow, risks, and non-overlapping implementation slices.
- `ux_reviewer`: produce HIG audit and recommended confirmation points.
- `core_worker`: own `Sources/MoongateCore/Settings.swift`, new Apple support files, and `Tests/MoongateCoreTests/TranslationSettingsTests.swift`.
- `ui_worker`: own `Sources/Moongate/SettingsView.swift` and App/Content changes needed for engine UI.
- `hig_worker`: own quick wins in queue, dependency, login, and error presentation after core changes are stable.
- `test_engineer`: run focused Swift tests/builds and identify missing verification.
- `quality_reviewer`: final read-only review before claiming completion.

## Risks And Rollback

- Apple APIs may require UI-hosted translation tasks or newer OS behavior; rollback is to readiness-only product support for those engines.
- Foundation Models only exists on eligible devices with Apple Intelligence enabled and model ready; UI must offer fallback rather than dead-end.
- PCC/Cloud Pro public API may not exist for third-party apps; rollback is explicit unavailable state.
- Settings migration touches persisted config; tests must prove legacy provider JSON still decodes correctly.
- UI restructure can be large; keep quick wins separate from confirmed large changes.

## Decision Log

- 2026-06-13: Treat current goal as active; do not narrow it to only core settings.
- 2026-06-13: Use subagents for codebase, UX, and docs/API research; main agent keeps scope, review, and integration.
- 2026-06-13: Create a macOS-specific ExecPlan instead of editing the existing mobile plan.
- 2026-06-13: Do not implement Cloud Pro/PCC runtime adapter without official public API evidence.
- 2026-06-13: Keep the product-facing translation engine picker broad enough for Apple engines; interpret the "two protocol" constraint as applying to API-compatible credential/model configuration only.

## Progress Log

- 2026-06-13: Implemented the Chinese-source subtitle readiness-gate bugfix slice. `startDownload()` now checks translation readiness only when the selected Chinese subtitle mode requires translation and the chosen source subtitle is not already `zh*`; Chinese source subtitles show the direct-use/burn-in no-translation prompt before Apple/API setup guidance. QueueManager's existing skip-translation behavior, burn-original behavior, dependency checks, network/API code, and broader HIG layout were left unchanged.
- 2026-06-13: Read user-supplied plan and current worktree.
- 2026-06-13: Spawned read-only codebase, UX, and docs/API subagents.
- 2026-06-13: UX review completed; top risks are sheet-based Settings, covering queue overlay, one-click dependency install, weak login browser controls, and missing Reduce Motion.
- 2026-06-13: Local SDK evidence collected for Translation.framework and FoundationModels.framework.
- 2026-06-13: Settings dependency component rows now expose combined VoiceOver semantics with component label and installed-state value only, without adding hints or changing dependency behavior.
- 2026-06-13: Added the shared engine/readiness model, Settings UI engine picker, CLI `--engine`, and runtime gates so Apple engines are visible but cannot start a fake translation job.
- 2026-06-13: Applied HIG quick wins for dependency wording, queue overlay motion/accessibility, login browser affordances, and reduced-motion behavior.
- 2026-06-13: Final quality review flagged a possible stale PCC display-label test. Current production/test labels are consistent and `TranslationSettingsTests` passed after a serial rerun.
- 2026-06-13: Added a shared async runtime-readiness contract plus a macOS app evaluator. The evaluator reads `Translation.framework` language availability and `FoundationModels.SystemLanguageModel.default.availability` behind `canImport` and `#available` guards, without triggering downloads.
- 2026-06-13: Connected `appleFoundationOnDevice` to a guarded `FoundationModels` translation path in `MoongateCore`. Apple Translation remains blocked even when language availability is installed because a `TranslationSession` execution adapter has not been proven and wired into the subtitle chunk path. PCC/Cloud Pro remains unavailable.
- 2026-06-13: Implemented additional HIG quick wins: clearer "粘贴并解析" action, failed-page technical details disclosure, Apple readiness icon/copy cleanup, queue progress accessibility values, and explicit Homebrew install side-effect copy.
- 2026-06-13: Restored full package tests by completing the mobile API-compatible translation provider contract and actor-safe test helpers. This was required because the current worktree includes mobile/iOS package targets and tests.
- 2026-06-13: Addressed quality-review blockers: `AppSettings.save()` now creates a missing first-run settings file and forces final POSIX `0600`; mobile API-compatible translation now parses real OpenAI Responses and Anthropic Messages JSON, rejects plain HTTP before attaching credentials, and avoids the official Anthropic `Authorization` header.
- 2026-06-13: Re-ran fresh targeted and full validation after the fixes. Full Swift package tests now execute 94 XCTest cases with zero failures; macOS app and CLI product builds complete under sandbox escalation for Swift module-cache writes only.
- 2026-06-13: Consolidated Apple Translation setup guidance into the shared `MoongateMobileCore` API, removed duplicate guidance/onboarding definitions, and kept macOS system-settings URL handling inside `SettingsView`. The guidance now covers missing execution adapters without exposing platform URLs in the shared Codable model.
- 2026-06-13: Re-ran fresh validation after guidance consolidation. Full Swift package tests now execute 113 XCTest cases with zero failures; macOS app and CLI product builds complete under sandbox escalation for Swift module-cache writes only.
- 2026-06-13: Added a confirmation-ready macOS HIG restructure audit in `docs/design/macos-hig-restructure-confirmation.md`. The main unconfirmed restructuring decisions are Settings scene, non-covering queue panel, dependency install wizard, login browser controls/cookie readiness, toolbar/action hierarchy, and wider split main layout.
- 2026-06-13: Read-only Apple Translation adapter review found a narrow possible execution path only for macOS 26+ with an explicit source language and installed language packs via `TranslationSession(installedSource:target:)` / `translations(from:)`. The current subtitle translation path does not yet pass source language into the translator, so Apple Translation execution remains blocked until that contract is added and adapter behavior is compile-tested. PCC/Cloud Pro still has no public runtime evidence and remains unavailable.
- 2026-06-13: Completed the subtitle source-language context contract. `QueueManager` passes the selected subtitle language into `TranslationContext`, `SubtitleTranslator` remains source-compatible for legacy conformers through `ContextualSubtitleTranslator`, and `ViewModel` scopes runtime readiness cache entries to their exact translation context so non-ready states fall back to target-only readiness.
- 2026-06-13: Re-ran fresh validation after the source-language contract fixes. `TranslationSettingsTests` executes 34 tests with zero failures, full Swift package tests execute 140 tests with zero failures, macOS app and CLI product builds complete under sandbox escalation for Swift module-cache writes only, and `git diff --check` passes.
- 2026-06-13: Addressed final review risks. Apple Translation installed-language readiness now reports `needsExecutionAdapter` so setup guidance routes users to a fallback instead of repeated runtime refresh, `AppSettings.load()` migrates settings and cookies from the legacy `视频下载器` support directory into `月之门`, and CLI subtitle translation infers source language from `*.lang.srt` filenames for future Apple Translation execution.
- 2026-06-13: Re-ran fresh validation after review-risk fixes. `TranslationSettingsTests` executes 36 tests with zero failures, full Swift package tests execute 149 tests with zero failures, macOS app and CLI product builds complete under sandbox escalation for Swift module-cache writes only, and `git diff --check` passes. One immediately prior full-test attempt failed before running tests because SwiftPM reported `AndroidDataBoundaryTests.swift` was modified during build; a clean scratch-path rerun passed.
- 2026-06-13: Implemented the minimal Apple Translation execution adapter slice in `MoongateCore`. Apple Translation low-latency/high-fidelity subtitle translation now routes through an internal executor abstraction, preserves global cue numbering through `clientIdentifier`, keeps existing bilingual/chinese-only SRT writing behavior, and gates the default executor to explicit source language, non-empty target language, installed language packs, macOS/iOS 26+, and macOS/iOS 26.4+ for high fidelity. Runtime readiness now returns ready for executable installed-language Apple Translation states while keeping missing source language not ready. PCC remains unavailable.
- 2026-06-13: Closed the Apple Translation adapter review risks. `listTranslationModels(settings:)` now rejects Apple/non-cloud engines before credential, URL, or network work; Apple Translation tests cover pre-cancel and pause/resume gates before executor invocation; shared guidance copy now describes conditional runtime execution instead of stale always-blocked behavior; and direct `sendConfiguredMessage` still blocks Apple Translation engines outside the subtitle execution path. Full Swift package validation passes 197 XCTest cases. Product builds pass after sandbox escalation only for Swift/clang module-cache writes.
- 2026-06-13: Added a focused macOS Settings boundary test and minimal Settings sheet UI for Apple Translation source-language readiness. Apple Translation low-latency/high-fidelity now expose a UI-only source language picker and build readiness with `TranslationContext(sourceLanguage:targetLanguage:)`; Foundation/PCC readiness stays target-only.
- 2026-06-13: Main-thread integration tightened the macOS Settings boundary test so the negative assertion is scoped to `appleTranslationReadinessContext()` instead of the whole file. Fresh validation passed for the boundary test, translation settings tests, the macOS app product build, full serial package tests, and whitespace diff checks. One earlier targeted settings-test attempt failed before tests because `/private/tmp` ran out of space while SwiftPM wrote module-cache artifacts; reusing the already-built scratch path avoided extra temporary output and passed.
- 2026-06-13: Strengthened the macOS Settings boundary test after read-only quality review so it also checks Apple Translation picker visibility, Foundation/PCC hidden-source behavior, and the exact readiness context passed to the runtime evaluator. While rerunning full validation, fixed an unrelated Android static boundary assertion that still required a specific Compose component name instead of the product boundary: Android UI should render domain `AndroidActionState` instead of click-only unsupported copy. Final serial package validation now passes 217 XCTest cases with zero failures.
- 2026-06-13: Implemented a narrow HIG quick win for the login WebView sheet. The sheet now shows a visible page-loading state driven by `WKNavigationDelegate`, clears loading on finish/failure/cancelled navigations, and keeps cookie export behavior unchanged. A read-only quality review found no Critical or Important issues; remaining Minor risks are source-inspection-only tests and possible loading flicker in unusual overlapping-navigation callback ordering.
- 2026-06-13: Re-ran fresh validation after the login WebView loading-state quick win. `MacOSLoginBoundaryTests` passed 3 XCTest cases, `TranslationSettingsTests` passed 38 XCTest cases, full serial package validation passed 232 XCTest cases, the macOS app product build completed after sandbox escalation only for Swift/clang module-cache writes, and whitespace diff checks passed. This stayed within low-risk HIG scope and did not implement full browser toolbar, external browser opening, target-cookie readiness, or cookie export changes.
- 2026-06-13: Added a low-risk login loading accessibility refinement. The login sheet's page-loading spinner now announces "页面加载中" while preserving visible copy, `WKNavigationDelegate` behavior, save/cancel buttons, cookie export scope, cookie content visibility, and target-cookie readiness behavior. A read-only quality review found no issues; remaining risk is source-boundary testing rather than runtime VoiceOver automation.
- 2026-06-13: Implemented a main-flow Apple setup guidance quick win. When subtitle translation is selected and the current Apple engine is not ready, the ready-state subtitle section now shows the shared `AppleTranslationSetupGuidance` title, numbered steps, a short App Settings action summary, and a `去设置` button. API-compatible engines keep the compact one-line readiness prompt. The main flow does not open System Settings directly, save or rewrite settings, switch engines, download language/model assets, or expose cookie/token details.
- 2026-06-13: Read-only review found no Critical issues for the main-flow guidance. The one Important ambiguity was that the initial action summary could be read as opening macOS System Settings directly; the copy was tightened to say it opens App Settings to view system-side steps, and the boundary test now guards against `NSWorkspace`, `saveSettings()`, direct `model.settings =`, token/auth-token, and cookie references in the main-flow guidance helper. Fresh validation passed the new content boundary test, settings boundary test, translation settings tests, full serial package tests, macOS app product build, and whitespace checks.
- 2026-06-13: Implemented a low-risk close/quit confirmation HIG quick win. The active-task abort confirmation now includes `NSAlert.informativeText` explaining that "保留任务，继续下载" cancels the close/quit action and preserves the queue, while "终止任务并关闭" cancels unfinished queue tasks and does not actively delete already completed generated files. Button order and `.alertSecondButtonReturn` mapping were preserved.
- 2026-06-13: Fresh targeted validation passed for `MacOSAppBoundaryTests`, `MacOSContentBoundaryTests`, and `TranslationSettingsTests`; the macOS app product build passed after sandbox escalation only for Swift/clang module-cache writes. A full serial package test attempt did not complete because the managed machine had only about 1.3 GiB free under `/private/tmp` and SwiftPM failed near the end with `stat error: No such file or directory`; no source compile error was present in the successful targeted builds. No cleanup was performed without explicit approval.
- 2026-06-13: Implemented a narrow Settings HIG quick win for cloud credential copy. The always-visible API credential help now stays short and non-technical, while Anthropic/OpenAI implementation details (`ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, DeepSeek mapping, Responses API, Bearer guidance) live behind `DisclosureGroup("高级说明")`. No token/cookie display, save behavior, or network behavior was added.
- 2026-06-13: A read-only quality review flagged the broad `TranslationEngine.allCases` picker as violating a two-protocol Settings interpretation. Main-thread review treated that as a scope/context mismatch: the active product goal requires Apple engine choices in Settings, while the two-protocol constraint applies to API-compatible cloud configuration. Added a focused boundary test proving the credential/help surface remains limited to `TranslationProvider.anthropic` and `.openai`, and that Apple/PCC engines use the separate readiness surface.
- 2026-06-13: Implemented a low-risk ContentView accessibility quick win. The icon-only Settings button now has an explicit accessibility label, candidate rows combine their custom row contents with a video-selection hint, and format rows expose a combined label, selection hint, and "已选择/未选择" accessibility value. This did not change parsing, download, queue, settings-save, or translation behavior.
- 2026-06-13: A read-only quality review for the accessibility slice flagged older Apple guidance and error-disclosure changes in `ContentView.swift` as out of scope. Main-thread review treated those findings as baseline/context mismatch because those changes were earlier HIG/Apple guidance slices already recorded above. The reviewer confirmed the requested gear/candidate/format accessibility additions are present and aligned.
- 2026-06-13: Implemented a low-risk Settings Apple readiness guidance polish. The Apple readiness section now exposes a combined accessibility label/value for the current readiness state and adds a short fallback line telling users they can temporarily use Anthropic-compatible or OpenAI-compatible engines when local Apple capabilities are unavailable. This did not add language/model downloads, network behavior, settings persistence, or new system side effects.
- 2026-06-13: Main-thread review rejected an implementation workaround that converted `appleTranslationReadinessContext()` into a closure property only to satisfy source-inspection tests. The code was restored to a normal helper function and the test helper now matches declarations more precisely.
- 2026-06-13: A read-only quality review for the Settings readiness polish flagged `NSWorkspace` and runtime-readiness evaluation in `SettingsView.swift` as violating the round scope. Main-thread review treated those as baseline/context mismatch because those behaviors belong to earlier Settings Apple readiness work already recorded above; the new polish only added state accessibility and fallback copy.
- 2026-06-13: Implemented a low-risk subtitle-processing accessibility quick win. The `Picker("字幕处理")` radio group now exposes an explicit accessibility label, a dynamic hint for the disabled/no-subtitle state versus the selectable state, and the selected subtitle-processing mode as its accessibility value. Visible UI, options, disabled logic, Apple guidance, translation readiness, download, queue, and settings behavior were unchanged.
- 2026-06-13: Implemented a low-risk queue clear-action copy/accessibility quick win. The queue header button now says `清除已结束任务` and exposes help plus an accessibility hint explaining that it only removes completed, failed, or cancelled tasks from the queue and does not delete downloaded files. The `queue.clearFinished()` behavior, visibility condition, queue layout, and file operations were unchanged.
- 2026-06-13: While validating the queue quick win, Swift test compilation exposed an unrelated duplicate `attachImportedSubtitle(fileURL:languageCode:)` declaration in `IOSMobileAppModel.swift`. Removed the older less strict duplicate and kept the existing validated `.srt`-checked implementation so SwiftPM tests can compile. The focused iOS imported-subtitle test passed after the cleanup.
- 2026-06-13: Implemented a low-risk subtitle Toggle accessibility quick win. Subtitle rows now expose a readable accessibility label that distinguishes auto-generated subtitles, a hint explaining that selected subtitles can be downloaded or used for Chinese subtitle processing, and an explicit selected/unselected accessibility value. Visible subtitle UI, subtitle binding, selected ID storage, download, translation, and queue behavior were unchanged.
- 2026-06-13: While validating the subtitle Toggle slice, Swift test compilation exposed an unrelated `IOSContinuedProcessingRenderScheduler.safeIdentifierComponent` compile issue in the current iOS worktree. Replaced the brittle chained sanitizer expression with an explicit ASCII component loop; existing scheduler tests still prove `../task with spaces` maps to `task-with-spaces` and non-eligible render plans are rejected.
- 2026-06-13: Implemented a low-risk dependency setup accessibility quick win. Dependency component rows now combine their status content into one accessibility element with component purpose and installed/missing value, the Homebrew install log is labeled, and the installing progress indicator exposes a clear label. The Homebrew command, install flow, buttons, and external side effects were unchanged.
- 2026-06-13: Read-only quality review approved the dependency setup accessibility slice with no Critical, Important, or Minor findings. The remaining test gap is that the boundary test is source-structure based rather than a real macOS accessibility tree or VoiceOver automation check, which is acceptable for this quick win.
- 2026-06-13: Implemented a low-risk parsing progress accessibility quick win. The header parse button's busy spinner now announces "正在解析", and the full-page parsing progress indicator announces the current batch status or "正在解析". Visible copy, parsing, cancel, download, queue, settings, dependency, and login behavior were unchanged.
- 2026-06-13: Read-only quality review approved the parsing progress accessibility slice with no Critical, Important, or Minor findings. The remaining test gap is that the boundary test is source-structure based rather than runtime VoiceOver automation.
- 2026-06-13: Implemented a low-risk Settings API progress accessibility quick win. The model-list fetch spinner now announces "正在拉取模型", and the connection-test spinner now announces "正在测试连接". Visible copy, `fetchModels()`, `runConnectionTest()`, network/API/credential handling, settings save behavior, and Apple readiness behavior were unchanged.
- 2026-06-13: Read-only quality review approved the Settings API progress accessibility slice with no Critical, Important, or Minor findings. The remaining test gap is that the boundary test is source-structure based rather than runtime SwiftUI accessibility tree verification.
- 2026-06-13: Implemented a low-risk queue row action accessibility quick win. Queue item icon buttons now expose action-specific hints for pause/resume/cancel/retry/reveal/remove, including non-destructive remove copy and subtitle-retry scope. Button order, visible labels, queue callbacks, file operations, and queue behavior were unchanged.
- 2026-06-13: Read-only quality review approved the queue row action hint slice with no Critical, Important, or Minor findings. The remaining test gap is that the boundary test is source-structure based rather than runtime SwiftUI accessibility tree verification.
- 2026-06-13: Implemented a low-risk Settings login cleanup copy quick win. The destructive login-clear action is now visibly scoped to this app: the outer button says "清除本 App 登录信息", the confirmation dialog says "清除本 App 保存的登录信息？", and the destructive confirmation says "清除登录信息". The shared help text clarifies that only this app's saved site login is cleared, browser/system accounts are not signed out, and restricted videos require re-login. `clearAllLogins()`, cookie clearing, WebKit data clearing, login buttons, settings save behavior, translation behavior, disabled logic, and dialog roles were unchanged.
- 2026-06-13: Read-only quality review approved the Settings login cleanup copy slice with no Critical, Important, or Minor findings. The reviewer noted broad Apple/API Settings diffs already present in the active product goal, but found no issue in this login-copy slice. Sensitive keyword scan hits were static existing copy/tests, not credential or cookie-value exposure; the remaining test limitation is source-text boundary coverage rather than runtime VoiceOver verification.
- 2026-06-13: Implemented a low-risk LoginSheet save-action copy quick win. The "保存登录信息" button now exposes the same app-scoped save explanation through help and accessibility hint, clarifying that saved login data stays in this app for downloader use and Cookie contents are not displayed in the UI. `exportCookies()`, cookie export scope, `NetscapeCookieFile.write`, `WKWebsiteDataStore`, save/cancel behavior, target-cookie readiness, and WebView delegate behavior were unchanged by this slice.
- 2026-06-13: Read-only quality review initially flagged prior loading/delegate work as out of scope, then approved after the main thread clarified that loading state was the pre-existing baseline from an earlier quick win. The remaining limitation is source-boundary testing rather than runtime SwiftUI accessibility tree verification.
- 2026-06-13: Implemented a low-risk Settings Apple setup action help quick win. Apple setup guidance buttons now expose matching Help and accessibility hints that describe each action's side effects: refresh only rechecks readiness, System Settings actions require user-controlled downloads/enabling, and fallback only switches the current settings draft to Anthropic-compatible. No network, credential, cookie, settings-save, automatic download, or system-setting mutation behavior was added by this slice. A read-only quality review found no Critical, Important, or Minor findings.
- 2026-06-13: Restored the current iOS test-target compile path after it blocked macOS-focused verification. Added a Photo Library save handler seam that resolves only app-owned safe artifacts, uses guarded PhotoKit add-only authorization when available, and keeps unsafe/permission/failure messages redacted. The iOS root view now routes Save to Photos through that handler instead of stopping at a status string. Also fixed the imported-subtitle security-scoped access path so external Files Provider copies start/stop access once, and added the missing multiple-candidate parser test helper. `MoongateiOSTests` now compiles again; XCTest execution on this managed Mac is still blocked by system policy rejecting the generated ad-hoc test bundle.
- 2026-06-13: Implemented a low-risk LoginSheet browser-control HIG slice. The login sheet now exposes compact Back, Reload, and Open in Browser controls; Back/Reload are routed through an in-app `WKWebView` command binding, and Open in Browser only runs from explicit user action. The sheet also shows target-site Cookie presence as a coarse status without exposing cookie names, values, counts, or domain lists, while `保存登录信息` continues to export the existing all-cookie file for downloader use. The visible current-page label now shows host/path only instead of full redirect URLs with query or fragment data.
- 2026-06-13: Tightened main-flow Apple setup CTA semantics. The `去设置` action in Apple setup guidance now has matching Help and accessibility hint explaining that it opens App Settings to view system-side steps and does not directly open System Settings, download language packs, save configuration, or switch translation engines.
- 2026-06-13: Added a minimal macOS-standard Settings command. The App menu Settings entry now uses `CommandGroup(replacing: .appSettings)` with `Cmd+,` and opens the existing settings sheet through `model.showSettings = true`; it does not introduce a new `Settings` scene or move SettingsView out of the current sheet yet.
- 2026-06-13: Re-checked the previous `IOSContinuedProcessingTaskCoordinator` SwiftPM blocker before making further edits. The current worktree now contains the coordinator production type, actor-safe test assertions, and the required background/action enum cases; targeted coordinator tests and `MacOSAppBoundaryTests` both pass, so no additional code fix was needed for that old blocker.
- 2026-06-13: Restored the broader SwiftPM test path after a newer iOS continued-processing handler test introduced a real missing production seam. Added `IOSContinuedProcessingSystemTask` plus `IOSContinuedProcessingTaskHandler`, with strict render-task identifier parsing, explicit `encoded-hex-` decoding for unsafe task identifiers, progress mirroring, expiration-to-foreground persistence, and an iOS 26+ `BGContinuedProcessingTask` adapter behind `#if os(iOS) && canImport(BackgroundTasks)`. Also removed a duplicated Android boundary-test fragment that had escaped the test class and blocked all Swift test compilation.
- 2026-06-13: Implemented a low-risk Header parse-action HIG quick win. The main parse button now says `解析链接` and exposes matching Help/accessibility hint text explaining that it parses the current video links in the input field; paste-and-parse, parse invocation, disabled state, prominent style, loading spinner, queue, settings, download, and translation behavior were unchanged.
- 2026-06-13: Strengthened shared Apple Intelligence onboarding guidance for local-unavailable states. `appleFoundationOnDevice` now tells users to confirm Mac/system eligibility, enable Apple Intelligence in System Settings under user control, wait for local model readiness without automatic app-side model changes, and use an API-compatible fallback when local capability is not available.
- 2026-06-13: Fixed a quality-review blocker in batch link processing. `processBatch(_:)` no longer blocks all batch work on translation readiness before a concrete subtitle source is known; it now waits until each video is analyzed and an automatic subtitle source is selected, skips the readiness gate for `zh*` source subtitles, and checks non-Chinese sources with a per-item `TranslationContext(sourceLanguage:targetLanguage:)` so Apple Translation readiness does not fall back to an empty source context. `QueueManager` skip-translation behavior, PCC/Cloud Pro gating, dependency checks, and network/API behavior were unchanged.
- 2026-06-13: Fixed the ready-page `startDownload()` runtime-readiness boundary after review. The production path already awaited runtime readiness with the selected subtitle source language; the failing source-boundary test was corrected to assert the async function signature instead of looking for `async` inside the function body. Focused macOS ViewModel, Content, Login, and Translation settings tests pass.
- 2026-06-13: Implemented a low-risk LoginSheet save-action readiness polish. The save button now exposes current site-cookie readiness as an accessibility value and branches its Help/accessibility hint so users know whether the current site Cookie has been detected before saving. Cookie export behavior, cookie filtering, WebView storage, save/cancel actions, and external browser behavior were unchanged.
- 2026-06-13: Closed the ready-page async readiness no-ship review finding. `startDownload()` now snapshots session, selected format/subtitles, mode, settings, and candidate before awaiting runtime readiness, revalidates the same ready item after the await, and enqueues with the same settings snapshot used for readiness. Batch processing now also passes `currentSettings` into runtime readiness so readiness and queue enqueue use the same translation configuration. Dependency checks run before runtime readiness on the ready-page path, matching the batch path priority.
- 2026-06-13: Calibrated the macOS HIG confirmation document against the current app state. It now records that `Cmd+,` opens the existing Settings sheet, Login already has compact browser controls/loading/cookie-readiness feedback, several quick wins are complete, and the remaining broad restructure decisions still need July confirmation.
- 2026-06-13: Implemented a low-risk Dependency Setup side-effect help quick win. The `打开 brew.sh`, `重新检测`, and `用 Homebrew 安装缺失组件` actions now expose Help and accessibility hints that describe whether they open an external website, only recheck local dependency state, or run `brew install` and may download formulas/dependencies. Button actions, Homebrew URL, install command, disabled logic, and layout behavior were unchanged.
- 2026-06-13: Addressed read-only quality review feedback for the Dependency Setup/HIG documentation slice. The HIG confirmation phases and acceptance criteria no longer describe existing `Cmd+,` or login browser controls as future work, and the dependency boundary test now also locks the Homebrew URL, `installer.refresh()`, `installer.install()`, and `installer.isRunning` disabled boundaries. The visible Homebrew formula summary was treated as pre-existing dependency-side-effect copy from the dirty worktree, not a new change in this help/hint slice.
- 2026-06-13: Tightened Settings API credential side-effect copy. The always-visible credential summary now says credentials stay in local settings and are sent to the user-entered service address only when the user clicks `拉取模型` or `测试连接`; it no longer says credentials are not sent before connection testing. Source-boundary tests now also prove this summary stays visible outside `高级说明`, while advanced protocol details remain behind the disclosure and the API credential surface stays separate from Apple/PCC readiness.
- 2026-06-13: Implemented a low-risk ready-page destination copy quick win. The footer below `加入队列` now distinguishes single-output downloads from subtitle/translation/burn-in multi-file output: single output says it saves to `Downloads`, while multi-file output says it will use a sanitized video-title folder under `Downloads`. The folder gate mirrors `startDownload()` by filtering selected subtitle ids through the current `VideoInfo.subtitles` before checking `!chosen.isEmpty || model.chineseMode != .off`; stale subtitle ids therefore do not produce misleading folder copy. Download behavior, `ViewModel.destinationDirectory`, queue behavior, subtitle selection, Apple readiness, and cloud/API settings were unchanged.
- 2026-06-13: The first read-only spec review found the initial destination footer gate was too broad because it used raw `selectedSubtitleIDs`. The implementer corrected the helper to mirror `startDownload()`'s `chosen` filtering, strengthened the source-boundary test, and a final read-only quality review found no Critical, Important, or Minor issues. Remaining risk is that this is source-boundary coverage rather than a runtime SwiftUI visual/VoiceOver check.
- 2026-06-13: Implemented a low-risk header action hierarchy quick win. Paste-and-parse is now a compact icon-only auxiliary button with `doc.on.clipboard`, precise Help, accessibility label, and accessibility hint, while still calling `model.pasteAndParse()` and staying disabled during parsing. The visible primary parse action remains `解析链接`, with existing prominence, parse invocation, loading spinner, queue, settings, download, Apple readiness, and translation behavior unchanged.
- 2026-06-13: Read-only review initially found the header action test did not fully cover `.disabled(model.isParsing)` or icon-only paste behavior. The implementer strengthened the source-boundary test to inspect only the paste button fragment, require the disabled state and accessibility copy, and reject visible `Label(` / `Text("粘贴...")` constructs in that fragment. Final read-only quality review found no Critical, Important, or Minor issues; remaining risk is source-boundary coverage rather than rendered macOS layout/VoiceOver proof.
- 2026-06-13: Implemented the remaining low-risk Settings Apple readiness copy polish. The readiness panel now shows a compact `当前引擎` / `状态` / `首要原因` summary, removes the repeated `中文字幕翻译状态` copy, keeps fallback copy limited to Anthropic-compatible or OpenAI-compatible engines, and clarifies that the fallback button changes only the current settings draft until the user clicks `完成`. No automatic download, system settings mutation, network action, credential/cookie exposure, or PCC/Cloud execution claim was added.
- 2026-06-13: The first read-only quality review for the Apple readiness summary recommended no-ship because fallback copy still mentioned returning to an Apple engine and the fallback action help did not explicitly describe draft-only/save-on-done behavior. The implementer tightened both strings, strengthened source-boundary tests for forbidden PCC/Cloud wording and duplicate status copy, and a final read-only quality review found no Critical or Important issues. Remaining risk is source-boundary coverage rather than rendered SwiftUI/VoiceOver verification.
- 2026-06-13: Strengthened the local Apple Intelligence model-unavailable onboarding guidance. When `.appleFoundationOnDevice` reports `.modelUnavailable`, shared setup guidance now points users to `系统设置 > Apple Intelligence 与 Siri` to check model preparation, states that the App will not automatically download or replace models, keeps the API-compatible fallback, and offers the user-controlled System Settings action before `重新检测`. PCC/Cloud Pro remains unavailable and no runtime/network/system side effect was added.
- 2026-06-13: Synced the macOS Settings action help with the explicit Apple Intelligence onboarding path. The `.openAppleIntelligenceSettings` help/accessibility copy now names `系统设置 > Apple Intelligence 与 Siri`, says the user can view or enable Apple Intelligence and model readiness there, and keeps the App-side no automatic download/model replacement/system-setting mutation boundary. The action behavior and generic System Settings URL were unchanged.
- 2026-06-13: Added a narrow shared-model slice for Apple Intelligence Cloud Pro. `TranslationEngine` now has a distinct `.appleFoundationCloudPro` / `cloud-pro` value with the `apple-foundation-cloud-pro` CLI alias, while `.appleFoundationPCC` keeps the ordinary PCC/cloud label. Both Apple cloud engines stay credential-free but unavailable: no legacy provider, no cloud configuration fields, mobile `.runtimeEntitlement`, `.usesCloudService == true`, `.pccUnavailable` readiness, no model-list network call, and no direct LLM/mobile/Apple Translation executor path. iOS route mapping now distinguishes `.privateCloud -> .appleFoundationPCC` and `.privateCloudPro -> .appleFoundationCloudPro`. Credential UI remains limited to OpenAI-compatible and Anthropic-compatible protocols.
- 2026-06-13: Closed the Cloud Pro credential-surface review blocker. iOS now rejects API key saving and connection testing before credential reference creation, provider construction, transport calls, or credential-store writes when a non API-compatible Apple engine is selected. Selecting Cloud Pro after a saved OpenAI-compatible API key now clears the model credential reference and schedules cleanup of the old API-compatible reference. Cloud Pro static readiness copy now names Cloud Pro/云端 Pro instead of falling back to the generic Private Cloud Compute message.
- 2026-06-14: Resumed the active Apple Translation/Foundation/PCC/Cloud Pro and HIG goal after context transition. Re-ran the previously reported iOS simulator smoke boundary failure; both the single smoke seed test and the full `MoongateiOSTests.PackageBoundaryTests` target now pass, and a read-only test review found the scanned seed/session snippets do not contain `UIPasteboard`, `UserDefaults`, `Keychain`, or `URLSession`. The earlier failure is treated as stale checkout/cache or source-boundary drift, not as a current Cloud Pro credential-surface regression.
- 2026-06-14: Calibrated this ExecPlan and `docs/design/macos-hig-restructure-confirmation.md` against the current implementation. The documents now state that Apple Translation has a guarded local subtitle execution adapter, Login has compact browser controls/loading/target-cookie readiness, Apple readiness has a `当前引擎` / `状态` / `首要原因` summary, and API protocol details live behind disclosure/help copy. PCC/Cloud Pro remain unavailable/gated, and broad HIG restructuring remains waiting for July confirmation.
- 2026-06-14: Tightened the main-flow Apple setup fallback guidance. When subtitle translation is blocked by an Apple engine readiness issue, the ready-state guidance now also tells users they can switch in App Settings to Anthropic-compatible or OpenAI-compatible engines to continue. This is copy-only guidance: it does not save settings, switch engines, open System Settings, download language/model assets, or touch credentials/cookies.
- 2026-06-14: Added a compact main-flow Apple readiness summary to the ready-page setup guidance. When an Apple engine blocks subtitle translation, the same local workflow now shows `当前引擎` / `状态` / `首要原因` before the setup steps and API-compatible fallback copy. This remains presentation-only: it does not save settings, switch engines, open System Settings, download language/model assets, or touch credentials/cookies.
- 2026-06-14: Implemented a low-risk queue header accessibility quick win. The existing queue header now exposes a combined VoiceOver summary with total task count, open task count, and all-paused/all-ended states while preserving the current overlay layout, clear-finished action, collapse action, queue item actions, file operations, and download behavior.
- 2026-06-14: Clarified the Dependency Setup close action during Homebrew installs. While install is running, the close button now says `取消安装并关闭` and its Help/accessibility hint explains that it terminates the current Homebrew install process but does not automatically roll back already completed Homebrew changes. The Homebrew command, install flow, refresh behavior, external website action, dependency state, and model completion behavior were unchanged.

## Final Validation Checklist

- [x] `swift test --filter MacOSSettingsBoundaryTests --jobs 1 --scratch-path .build/vdl-settings-dependency-a11y-check` failed before implementation on the new Settings dependency accessibility boundary test and passed after implementation.
- [x] `swift test --filter TranslationSettingsTests --scratch-path /private/tmp/vdl-macos-ai-test-final-serial`
- [x] `swift test --scratch-path /private/tmp/vdl-macos-ai-full-test-final-serial`
- [x] `swift test --filter TranslationSettingsTests --scratch-path /private/tmp/vdl-runtime-contract-test`
- [x] `swift test --scratch-path /private/tmp/vdl-runtime-full-test-serial-3`
- [x] `swift build --product moongate-cli --scratch-path /private/tmp/vdl-macos-ai-cli-build-final`
- [x] `swift build --product Moongate --scratch-path /private/tmp/vdl-macos-ai-app-build-final`
- [x] `swift build --product moongate-cli --scratch-path /private/tmp/vdl-runtime-cli-build-final`
- [x] `swift build --product Moongate --scratch-path /private/tmp/vdl-runtime-app-build-final`
- [x] `swift test --filter MobileTranslationProviderTests --scratch-path /private/tmp/vdl-target-mobile-provider-20260613c`
- [x] `swift test --filter TranslationSettingsTests --scratch-path /private/tmp/vdl-target-settings-20260613a`
- [x] `swift test --filter IOSMobileAppModelTests --scratch-path /private/tmp/vdl-target-ios-model-20260613a`
- [x] `swift test --scratch-path /private/tmp/vdl-runtime-full-test-fresh-20260613b`
- [x] `swift build --product Moongate --scratch-path /private/tmp/vdl-runtime-app-build-fresh-20260613a`
- [x] `swift build --product moongate-cli --scratch-path /private/tmp/vdl-runtime-cli-build-fresh-20260613a`
- [x] `swift test --filter TranslationSettingsTests --scratch-path /private/tmp/vdl-guidance-main-target-20260613a`
- [x] `swift test --scratch-path /private/tmp/vdl-guidance-main-full-20260613a`
- [x] `swift build --product Moongate --scratch-path /private/tmp/vdl-guidance-main-app-20260613a`
- [x] `swift build --product moongate-cli --scratch-path /private/tmp/vdl-guidance-main-cli-20260613a`
- [x] `swift test --filter TranslationSettingsTests --scratch-path /private/tmp/vdl-source-context-final-settings-20260613a`
- [x] `swift test --scratch-path /private/tmp/vdl-source-context-final-full-20260613a`
- [x] `swift build --product Moongate --scratch-path /private/tmp/vdl-source-context-final-app-20260613a`
- [x] `swift build --product moongate-cli --scratch-path /private/tmp/vdl-source-context-final-cli-20260613a`
- [x] `swift test --filter TranslationSettingsTests --scratch-path /private/tmp/vdl-review-risk-settings-20260613a`
- [x] `swift test --scratch-path /private/tmp/vdl-review-risk-full-20260613b`
- [x] `swift build --product Moongate --scratch-path /private/tmp/vdl-review-risk-app-20260613a`
- [x] `swift build --product moongate-cli --scratch-path /private/tmp/vdl-review-risk-cli-20260613a`
- [x] `git diff --check`
- [x] `swift test --filter AppleTranslationExecutorTests --scratch-path /private/tmp/vdl-apple-translation-adapter-final-executor-20260613b`
- [x] `swift test --filter TranslationSettingsTests --scratch-path /private/tmp/vdl-apple-translation-adapter-final-settings-20260613b`
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-apple-translation-adapter-final-full-serial-20260613c`
- [x] `swift build --product Moongate --scratch-path /private/tmp/vdl-apple-translation-adapter-final-app-20260613b`
- [x] `swift build --product moongate-cli --scratch-path /private/tmp/vdl-apple-translation-adapter-final-cli-20260613b`
- [x] `swift test --filter MacOSSettingsBoundaryTests --scratch-path /private/tmp/vdl-macos-settings-boundary-green-20260613a`
- [x] `swift test --filter MacOSSettingsBoundaryTests --jobs 1 --scratch-path /private/tmp/vdl-macos-settings-boundary-main-serial-20260613a`
- [x] `swift test --filter TranslationSettingsTests --jobs 1 --scratch-path /private/tmp/vdl-macos-settings-boundary-main-serial-20260613a`
- [x] `swift test --filter AndroidDataBoundaryTests/testAndroidLiveShellUsesDomainActionStateInsteadOfClickOnlyUnsupportedCopy --jobs 1 --scratch-path /private/tmp/vdl-macos-settings-boundary-main-serial-20260613a`
- [x] `swift build --product Moongate --scratch-path /private/tmp/vdl-macos-settings-boundary-main-serial-20260613a`
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-macos-settings-boundary-main-serial-20260613a`
- [x] `swift test --filter MacOSLoginBoundaryTests --jobs 1 --scratch-path /private/tmp/vdl-macos-login-loading-boundary-20260613a`
- [x] `swift test --filter TranslationSettingsTests --jobs 1 --scratch-path /private/tmp/vdl-macos-login-loading-boundary-20260613a`
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-macos-login-loading-boundary-20260613a`
- [x] `swift build --product Moongate --scratch-path /private/tmp/vdl-macos-login-loading-boundary-20260613a`
- [x] `rg -n '[[:blank:]]$' Sources/Moongate/LoginWebView.swift Tests/MoongateCoreTests/MacOSLoginBoundaryTests.swift docs/exec-plans/2026-06-13-macos-apple-intelligence-hig.md`
- [x] `swift test --filter MacOSLoginBoundaryTests/testTopBarShowsLoadingStateWithoutCookieDetails --jobs 1 --scratch-path /private/tmp/vdl-macos-login-loading-accessibility-20260613a` failed before implementation and passed after implementation.
- [x] `swift test --filter MacOSLoginBoundaryTests --jobs 1 --scratch-path /private/tmp/vdl-macos-login-loading-accessibility-20260613a`
- [x] `swift build --product Moongate --scratch-path /private/tmp/vdl-macos-content-guidance-full-20260613c`
- [x] `git diff --check`
- [x] `rg -n '[[:blank:]]$' Sources/Moongate/LoginWebView.swift Tests/MoongateCoreTests/MacOSLoginBoundaryTests.swift docs/exec-plans/2026-06-13-macos-apple-intelligence-hig.md`
- [x] `swift test --filter MacOSContentBoundaryTests --jobs 1 --scratch-path /private/tmp/vdl-macos-content-guidance-20260613b`
- [x] `swift test --filter TranslationSettingsTests --jobs 1 --scratch-path /private/tmp/vdl-macos-content-guidance-20260613b`
- [x] `swift test --filter MacOSSettingsBoundaryTests --jobs 1 --scratch-path /private/tmp/vdl-macos-content-guidance-20260613b`
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-macos-content-guidance-full-20260613c`
- [x] `swift build --product Moongate --scratch-path /private/tmp/vdl-macos-content-guidance-full-20260613c`
- [x] `rg -n '[[:blank:]]$' Sources/Moongate/ContentView.swift Tests/MoongateCoreTests/MacOSContentBoundaryTests.swift docs/exec-plans/2026-06-13-macos-apple-intelligence-hig.md`
- [x] `swift test --filter MacOSAppBoundaryTests --jobs 1 --scratch-path /private/tmp/vdl-macos-content-guidance-full-20260613c`
- [x] `swift test --filter MacOSContentBoundaryTests --jobs 1 --scratch-path /private/tmp/vdl-macos-content-guidance-full-20260613c`
- [x] `swift test --filter TranslationSettingsTests --jobs 1 --scratch-path /private/tmp/vdl-macos-content-guidance-full-20260613c`
- [x] `swift build --product Moongate --scratch-path /private/tmp/vdl-macos-content-guidance-full-20260613c`
- [ ] `swift test --jobs 1 --scratch-path /private/tmp/vdl-macos-content-guidance-full-20260613c` after close-confirmation change. Attempted, but did not complete due SwiftPM scratch/stat failure on low `/private/tmp` free space.
- [x] `swift test --filter MacOSSettingsBoundaryTests --jobs 1 --scratch-path /private/tmp/vdl-macos-content-guidance-full-20260613c`
- [x] `swift test --filter TranslationSettingsTests --jobs 1 --scratch-path /private/tmp/vdl-macos-content-guidance-full-20260613c`
- [x] `swift build --product Moongate --scratch-path /private/tmp/vdl-macos-content-guidance-full-20260613c`
- [x] `rg -n '[[:blank:]]$' Sources/Moongate/SettingsView.swift Tests/MoongateCoreTests/MacOSSettingsBoundaryTests.swift docs/exec-plans/2026-06-13-macos-apple-intelligence-hig.md`
- [x] `swift test --filter MacOSContentBoundaryTests/testCustomSelectionRowsExposeAccessibilitySemantics --jobs 1 --scratch-path /private/tmp/vdl-macos-content-guidance-full-20260613c` failed before implementation and passed after implementation.
- [x] `swift test --filter MacOSContentBoundaryTests --jobs 1 --scratch-path /private/tmp/vdl-macos-content-guidance-full-20260613c`
- [x] `swift test --filter MacOSSettingsBoundaryTests --jobs 1 --scratch-path /private/tmp/vdl-macos-content-guidance-full-20260613c`
- [x] `swift test --filter TranslationSettingsTests --jobs 1 --scratch-path /private/tmp/vdl-macos-content-guidance-full-20260613c`
- [x] `swift build --product Moongate --scratch-path /private/tmp/vdl-macos-content-guidance-full-20260613c`
- [x] `rg -n '[[:blank:]]$' Sources/Moongate/ContentView.swift Tests/MoongateCoreTests/MacOSContentBoundaryTests.swift docs/exec-plans/2026-06-13-macos-apple-intelligence-hig.md`
- [x] `swift test --filter MacOSSettingsBoundaryTests/testAppleReadinessPanelExposesStateAndFallbackSemantics --jobs 1 --scratch-path /private/tmp/vdl-macos-content-guidance-full-20260613c` failed before implementation and passed after implementation.
- [x] `swift test --filter MacOSSettingsBoundaryTests --jobs 1 --scratch-path /private/tmp/vdl-macos-content-guidance-full-20260613c`
- [x] `swift test --filter TranslationSettingsTests --jobs 1 --scratch-path /private/tmp/vdl-macos-content-guidance-full-20260613c`
- [x] `swift test --filter MacOSContentBoundaryTests --jobs 1 --scratch-path /private/tmp/vdl-macos-content-guidance-full-20260613c`
- [x] `swift build --product Moongate --scratch-path /private/tmp/vdl-macos-content-guidance-full-20260613c`
- [x] `rg -n '[[:blank:]]$' Sources/Moongate/SettingsView.swift Tests/MoongateCoreTests/MacOSSettingsBoundaryTests.swift docs/exec-plans/2026-06-13-macos-apple-intelligence-hig.md`
- [x] `swift test --filter MacOSContentBoundaryTests/testChineseSubtitleProcessingPickerHasAccessibleState --jobs 1 --scratch-path /private/tmp/vdl-macos-content-guidance-full-20260613c` failed before implementation and passed after implementation.
- [x] `swift test --filter MacOSContentBoundaryTests --jobs 1 --scratch-path /private/tmp/vdl-macos-content-guidance-full-20260613c`
- [x] `swift test --filter TranslationSettingsTests --jobs 1 --scratch-path /private/tmp/vdl-macos-content-guidance-full-20260613c`
- [x] `swift build --product Moongate --scratch-path /private/tmp/vdl-macos-content-guidance-full-20260613c`
- [x] `rg -n '[[:blank:]]$' Sources/Moongate/ContentView.swift Tests/MoongateCoreTests/MacOSContentBoundaryTests.swift docs/exec-plans/2026-06-13-macos-apple-intelligence-hig.md`
- [x] `swift test --filter MacOSQueueBoundaryTests/testClearFinishedQueueActionExplainsNonDestructiveScope --jobs 1 --scratch-path /private/tmp/vdl-macos-queue-boundary-20260613a` failed before implementation and passed after implementation.
- [x] `swift test --filter MacOSQueueBoundaryTests --jobs 1 --scratch-path /private/tmp/vdl-macos-queue-boundary-20260613a`
- [x] `swift test --filter IOSMobileAppModelTests/testLiveDirectURLCanAttachImportedSubtitleBeforeJoiningQueue --jobs 1 --scratch-path /private/tmp/vdl-macos-queue-boundary-20260613a`
- [x] `swift build --product Moongate --scratch-path /private/tmp/vdl-macos-queue-boundary-20260613a`
- [x] `git diff --check`
- [x] `rg -n 'cookie|token|secret' Tests/MoongateCoreTests/MacOSQueueBoundaryTests.swift Sources/Moongate/QueueSectionView.swift`
- [x] `rg -n '[[:blank:]]$' Sources/Moongate/QueueSectionView.swift Tests/MoongateCoreTests/MacOSQueueBoundaryTests.swift Sources/MoongateiOS/IOSMobileAppModel.swift docs/exec-plans/2026-06-13-macos-apple-intelligence-hig.md`
- [x] `swift test --filter MacOSContentBoundaryTests/testSubtitleRowsExposeManualAndAutoGeneratedAccessibilitySemantics --jobs 1 --scratch-path /private/tmp/vdl-macos-subtitle-accessibility-20260613a` failed before implementation after the iOS scheduler compile blocker was fixed.
- [x] `swift test --filter MacOSContentBoundaryTests/testSubtitleRowsExposeManualAndAutoGeneratedAccessibilitySemantics --jobs 1 --scratch-path /private/tmp/vdl-macos-content-guidance-full-20260613c`
- [x] `swift test --filter MacOSContentBoundaryTests --jobs 1 --scratch-path /private/tmp/vdl-macos-content-guidance-full-20260613c`
- [x] `swift test --filter IOSContinuedProcessingRenderSchedulerTests --jobs 1 --scratch-path /private/tmp/vdl-macos-subtitle-accessibility-20260613a`
- [x] `swift build --product Moongate --scratch-path /private/tmp/vdl-macos-content-guidance-full-20260613c`
- [x] `git diff --check`
- [x] `rg -n '[[:blank:]]$' Sources/Moongate/ContentView.swift Tests/MoongateCoreTests/MacOSContentBoundaryTests.swift Sources/MoongateiOS/IOSContinuedProcessingRenderScheduler.swift docs/exec-plans/2026-06-13-macos-apple-intelligence-hig.md`
- [x] `swift test --filter MacOSDependencyBoundaryTests/testDependencySetupSheetExposesAccessibleStatusSemantics --jobs 1 --scratch-path /private/tmp/vdl-macos-dependency-accessibility-20260613a` failed before implementation and passed after implementation.
- [x] `swift test --filter MacOSDependencyBoundaryTests --jobs 1 --scratch-path /private/tmp/vdl-macos-dependency-accessibility-20260613a`
- [x] `swift build --product Moongate --scratch-path /private/tmp/vdl-macos-content-guidance-full-20260613c`
- [x] `git diff --check`
- [x] `rg -n '[[:blank:]]$' Sources/Moongate/DependencySetupView.swift Tests/MoongateCoreTests/MacOSDependencyBoundaryTests.swift docs/exec-plans/2026-06-13-macos-apple-intelligence-hig.md`
- [x] `swift test --filter MacOSContentBoundaryTests/testParsingProgressIndicatorsExposeAccessibleLabels --jobs 1 --scratch-path /private/tmp/vdl-macos-parsing-progress-accessibility-20260613a` failed before implementation and passed after implementation.
- [x] `swift test --filter MacOSContentBoundaryTests --jobs 1 --scratch-path /private/tmp/vdl-macos-parsing-progress-accessibility-20260613a`
- [x] `swift build --product Moongate --scratch-path /private/tmp/vdl-macos-content-guidance-full-20260613c`
- [x] `git diff --check`
- [x] `rg -n '[[:blank:]]$' Sources/Moongate/ContentView.swift Tests/MoongateCoreTests/MacOSContentBoundaryTests.swift docs/exec-plans/2026-06-13-macos-apple-intelligence-hig.md`
- [x] `swift test --filter MacOSSettingsBoundaryTests/testAPITranslationProgressIndicatorsExposeAccessibleLabels --jobs 1 --scratch-path /private/tmp/vdl-macos-settings-progress-accessibility-20260613a` failed before implementation and passed after implementation.
- [x] `swift test --filter MacOSSettingsBoundaryTests --jobs 1 --scratch-path /private/tmp/vdl-macos-settings-progress-accessibility-20260613a`
- [x] `swift build --product Moongate --scratch-path /private/tmp/vdl-macos-content-guidance-full-20260613c`
- [x] `git diff --check`
- [x] `rg -n '[[:blank:]]$' Sources/Moongate/SettingsView.swift Tests/MoongateCoreTests/MacOSSettingsBoundaryTests.swift docs/exec-plans/2026-06-13-macos-apple-intelligence-hig.md`
- [x] `swift test --filter MacOSQueueBoundaryTests/testQueueItemActionsExposeSideEffectAccessibilityHints --jobs 1 --scratch-path /private/tmp/vdl-macos-queue-action-hints-20260613a` failed before implementation and passed after implementation.
- [x] `swift test --filter MacOSQueueBoundaryTests --jobs 1 --scratch-path /private/tmp/vdl-macos-queue-action-hints-20260613a`
- [x] `swift build --product Moongate --scratch-path /private/tmp/vdl-macos-queue-action-hints-20260613a`
- [x] `git diff --check -- Sources/Moongate/QueueItemView.swift Tests/MoongateCoreTests/MacOSQueueBoundaryTests.swift docs/exec-plans/2026-06-13-macos-apple-intelligence-hig.md`
- [x] `rg -n '[[:blank:]]$' Sources/Moongate/QueueItemView.swift Tests/MoongateCoreTests/MacOSQueueBoundaryTests.swift docs/exec-plans/2026-06-13-macos-apple-intelligence-hig.md`
- [x] `rg -n 'token|cookie|secret|Authorization|ANTHROPIC_AUTH_TOKEN' Sources/Moongate/QueueItemView.swift Tests/MoongateCoreTests/MacOSQueueBoundaryTests.swift`
- [x] `swift test --filter MacOSSettingsBoundaryTests/testClearLoginActionExplainsAppScopedSideEffects --jobs 1 --scratch-path /private/tmp/vdl-macos-settings-clear-login-copy-20260613a` failed before implementation and passed after implementation.
- [x] `swift test --filter MacOSSettingsBoundaryTests --jobs 1 --scratch-path /private/tmp/vdl-macos-settings-clear-login-copy-20260613a`
- [x] `swift build --product Moongate --scratch-path /private/tmp/vdl-macos-settings-clear-login-copy-20260613a`
- [x] `git diff --check -- Sources/Moongate/SettingsView.swift Tests/MoongateCoreTests/MacOSSettingsBoundaryTests.swift docs/exec-plans/2026-06-13-macos-apple-intelligence-hig.md`
- [x] `rg -n '[[:blank:]]$' Sources/Moongate/SettingsView.swift Tests/MoongateCoreTests/MacOSSettingsBoundaryTests.swift docs/exec-plans/2026-06-13-macos-apple-intelligence-hig.md`
- [x] `rg -n 'token|cookie|secret|Authorization|ANTHROPIC_AUTH_TOKEN' Sources/Moongate/SettingsView.swift Tests/MoongateCoreTests/MacOSSettingsBoundaryTests.swift`
- [x] `swift test --filter MacOSLoginBoundaryTests/testSaveLoginActionExplainsAppScopedCookieExportWithoutCookieDetails --jobs 1 --scratch-path /private/tmp/vdl-macos-login-save-help-20260613a` failed before implementation and passed after implementation.
- [x] `swift test --filter MacOSLoginBoundaryTests --jobs 1 --scratch-path /private/tmp/vdl-macos-login-save-help-20260613a`
- [x] `swift build --product Moongate --scratch-path /private/tmp/vdl-macos-login-save-help-20260613a`
- [x] `git diff --check -- Sources/Moongate/LoginWebView.swift Tests/MoongateCoreTests/MacOSLoginBoundaryTests.swift docs/exec-plans/2026-06-13-macos-apple-intelligence-hig.md`
- [x] `rg -n '[[:blank:]]$' Sources/Moongate/LoginWebView.swift Tests/MoongateCoreTests/MacOSLoginBoundaryTests.swift docs/exec-plans/2026-06-13-macos-apple-intelligence-hig.md`
- [x] `rg -n 'token|secret|Authorization|ANTHROPIC_AUTH_TOKEN|Cookie|cookie' Sources/Moongate/LoginWebView.swift Tests/MoongateCoreTests/MacOSLoginBoundaryTests.swift`
- [x] `swift test --filter MacOSSettingsBoundaryTests/testAppleSetupActionButtonsExposeSideEffectHelp --jobs 1 --scratch-path /private/tmp/vdl-macos-settings-apple-action-help-20260613a` failed before implementation and passed after implementation.
- [x] `swift build --target MoongateCoreTests --scratch-path /private/tmp/vdl-macos-settings-apple-action-help-vdlcoretests-20260613a`
- [x] `swift build --product Moongate --scratch-path /private/tmp/vdl-macos-settings-apple-action-help-app-20260613a`
- [x] `git diff --check -- Sources/Moongate/SettingsView.swift Tests/MoongateCoreTests/MacOSSettingsBoundaryTests.swift docs/exec-plans/2026-06-13-macos-apple-intelligence-hig.md`
- [x] `rg -n '[[:blank:]]$' Sources/Moongate/SettingsView.swift Tests/MoongateCoreTests/MacOSSettingsBoundaryTests.swift docs/exec-plans/2026-06-13-macos-apple-intelligence-hig.md`
- [x] `rg -n 'token|cookie|secret|Authorization|ANTHROPIC_AUTH_TOKEN' Sources/Moongate/SettingsView.swift Tests/MoongateCoreTests/MacOSSettingsBoundaryTests.swift`
- [x] `swift test --filter MacOSLoginBoundaryTests --jobs 1 --scratch-path .build/vdl-login-boundary`
- [x] `swift test --filter MacOSContentBoundaryTests/testChineseSubtitleRowsUsesAppleGuidanceOnlyForAppleEngines --jobs 1 --scratch-path .build/vdl-content-guidance-boundary`
- [x] `git diff --check -- Sources/Moongate/ContentView.swift Tests/MoongateCoreTests/MacOSContentBoundaryTests.swift Sources/Moongate/LoginWebView.swift Tests/MoongateCoreTests/MacOSLoginBoundaryTests.swift`
- [x] `rg -n '[[:blank:]]$' Sources/Moongate/ContentView.swift Tests/MoongateCoreTests/MacOSContentBoundaryTests.swift Sources/Moongate/LoginWebView.swift Tests/MoongateCoreTests/MacOSLoginBoundaryTests.swift`
- [x] `swift test --filter MacOSAppBoundaryTests --jobs 1 --scratch-path .build/vdl-app-settings-command-boundary`
- [x] `swift build --product Moongate --scratch-path .build/vdl-app-settings-command-boundary`
- [x] `git diff --check -- Sources/Moongate/App.swift Tests/MoongateCoreTests/MacOSAppBoundaryTests.swift`
- [x] `rg -n '[[:blank:]]$' Sources/Moongate/App.swift Tests/MoongateCoreTests/MacOSAppBoundaryTests.swift`
- [x] `swift test --filter IOSContinuedProcessingTaskCoordinatorTests --jobs 1 --scratch-path .build/vdl-ios-continued-coordinator-check`
- [x] `swift test --filter MacOSAppBoundaryTests --jobs 1 --scratch-path .build/vdl-macos-app-boundary-check`
- [x] `swift test --filter IOSContinuedProcessingTaskHandlerTests --jobs 1 --scratch-path .build/vdl-ios-task-handler-check`
- [x] `swift test --filter MacOSAppBoundaryTests --jobs 1 --scratch-path .build/vdl-ios-task-handler-check`
- [x] `swift test --filter PackageBoundaryTests/testIOSContinuedProcessingTaskHandlerKeepsPureSourceSeamAndGuardedAdapter --jobs 1 --scratch-path .build/vdl-ios-task-handler-check`
- [x] `git diff --check -- Sources/MoongateiOS/IOSContinuedProcessingTaskHandler.swift Tests/MoongateCoreTests/AndroidDataBoundaryTests.swift Tests/MoongateiOSTests/IOSContinuedProcessingTaskHandlerTests.swift docs/exec-plans/2026-06-13-macos-apple-intelligence-hig.md`
- [x] `rg -n '[[:blank:]]$' Sources/MoongateiOS/IOSContinuedProcessingTaskHandler.swift Tests/MoongateCoreTests/AndroidDataBoundaryTests.swift Tests/MoongateiOSTests/IOSContinuedProcessingTaskHandlerTests.swift docs/exec-plans/2026-06-13-macos-apple-intelligence-hig.md`
- [x] `swift test --filter MacOSContentBoundaryTests --jobs 1 --scratch-path .build/vdl-header-parse-action-check`
- [x] `git diff --check -- Sources/Moongate/ContentView.swift Tests/MoongateCoreTests/MacOSContentBoundaryTests.swift docs/exec-plans/2026-06-13-macos-apple-intelligence-hig.md`
- [ ] `swift test --filter MacOSSettingsBoundaryTests --jobs 1 --scratch-path /private/tmp/vdl-macos-settings-apple-action-help-main-20260613c` attempted, but did not complete because SwiftPM compiled the unrelated `MoongateiOSTests` target first and failed on current iOS test-target drift / file-modified-during-build errors in `Tests/MoongateiOSTests/IOSMobileAppModelTests.swift`. The focused macOS Settings test and `MoongateCoreTests` target build passed.
- [x] `swift test --filter IOSPhotoLibraryExporterTests --jobs 1 --scratch-path .build/vdl-ios-target-compile-20260613a` passed 3 tests before later system-policy bundle-load failures appeared on rebuilt artifacts.
- [x] `swift build --target MoongateiOSTests --scratch-path .build/vdl-ios-target-compile-20260613a`
- [x] `codesign --verify --verbose=4 .build/vdl-ios-target-compile-20260613a/arm64-apple-macosx/debug/MoongatePackageTests.xctest/Contents/MacOS/MoongatePackageTests` diagnosed the managed-Mac XCTest execution blocker as an invalid ad-hoc bundle signature: `code has no resources but signature indicates they must be present`.
- [ ] `swift test --filter IOSPhotoLibraryExporterTests --jobs 1 --scratch-path .build/vdl-ios-target-compile-20260613a` currently rebuilds successfully but execution is blocked by system policy: `MoongatePackageTests.xctest ... library load denied by system policy`.
- [ ] `swift test --filter IOSMobileAppModelTests/testImportedSubtitleUsesSecurityScopedAccessWhenCopyingFromFilesProvider --jobs 1 --scratch-path .build/vdl-ios-target-compile-20260613a` currently cannot execute for the same generated XCTest bundle-load policy reason; `MoongateiOSTests` target compilation now passes.
- [x] Legacy Anthropic/OpenAI-compatible settings still decode and route correctly.
- [x] Apple engines do not require cloud tokens and surface readiness reasons.
- [x] Unsupported/future Apple engines cannot start a fake translation job.
- [x] Foundation on-device uses `FoundationModels` only when the module exists, the OS is available, and the model reports available.
- [x] Apple Translation and PCC/Cloud Pro do not claim end-to-end translation support before execution adapters are proven.
- [x] Settings persistence creates missing settings file and tightens final permissions to `0600`.
- [x] Mobile API-compatible translation parses real provider JSON and does not send credentials over plain HTTP.
- [x] Apple setup guidance has a single shared API surface and covers missing execution adapters without leaking macOS-only URLs into `MoongateMobileCore`.
- [x] App settings and login cookies migrate from the legacy `视频下载器` support directory to `月之门` instead of appearing lost after the app rename.
- [x] CLI subtitle translation passes inferred source language from `*.lang.srt` filenames when available.
- [x] UI communicates Apple Intelligence setup without claiming automatic install when only system settings can do it.
- [x] HIG quick wins are reviewed against Reduce Motion and accessibility.
- [x] HIG restructure confirmation document exists for July review before broad UI rewrites.
- [x] Subtitle translation path passes an explicit source language into the translation context for future Apple Translation execution.
- [x] Apple Translation execution adapter is implemented only for verified macOS/iOS 26+ installed-language cases, with high-fidelity gated to 26.4+ and fake-executor unit coverage for the subtitle chunk path.
- [x] Apple/non-cloud engines cannot call the cloud model-list endpoint.
- [x] Apple Translation subtitle execution honors pre-cancelled and paused `TaskControlToken` gates before executor invocation.
- [x] macOS Settings Apple Translation readiness uses an explicit UI-selected source language while Foundation/PCC readiness remains target-only.
- [x] Android static boundary test tracks domain action-state usage without overfitting to a specific Compose component name.
- [x] Login WebView sheet shows page-loading feedback without changing cookie export semantics or exposing cookie details.
- [x] Main subtitle workflow shows Apple setup guidance when an Apple engine is not ready, while API-compatible engines keep the compact cloud-configuration prompt.
- [x] Main subtitle workflow guidance does not directly open System Settings, save settings, switch engines, download assets, or expose cookie/token values.
- [x] Close/quit confirmation explains both choices with informative text while preserving the destructive button mapping.
- [x] Custom candidate and format selection rows expose explicit accessibility semantics without changing selection behavior.
- [x] Settings Apple readiness section exposes a readable accessibility state and a clear API-compatible fallback path for machines without local Apple capability.
- [x] Subtitle-processing radio group exposes a readable accessibility label, hint, and selected value without changing visible UI or behavior.
- [x] Queue clear-finished action communicates that it removes queue records only and does not delete downloaded files.
- [x] Subtitle selection checkboxes expose manual versus auto-generated semantics and selected state to assistive technologies.
- [x] Queue item icon actions expose action-specific accessibility hints, including non-destructive remove and scoped subtitle retry.
- [x] Settings login cleanup explains app-scoped side effects before clearing saved site login data.
- [x] Login save action explains app-scoped cookie export without displaying cookie contents.
- [x] Login recovery supports Back, Reload, Open in Browser, and target-site Cookie presence without changing cookie export semantics or displaying full redirect query/fragment data.
- [x] Main Apple setup CTA explains App Settings-only side effects and does not imply automatic system changes, downloads, saving, or engine switching.
- [x] Settings can be opened through the Mac-standard App Settings command and `Cmd+,` while still using the existing sheet until the larger Settings scene restructure is confirmed.
- [x] `swift test --filter TranslationSettingsTests/testAppleFoundationSetupGuidanceExplainsIntelligenceAndModelReadiness --jobs 1 --scratch-path .build/vdl-apple-intelligence-onboarding-check` failed before implementation on the new guidance steps and passed after implementation; `swift test --filter TranslationSettingsTests --jobs 1 --scratch-path .build/vdl-apple-intelligence-onboarding-check` and scoped `git diff --check` passed.
- [x] `swift test --filter 'MacOSContentBoundaryTests|MacOSViewModelBoundaryTests' --jobs 1 --scratch-path .build/vdl-chinese-source-readiness-gate-check`
- [x] `swift test --filter TranslationSettingsTests --jobs 1 --scratch-path .build/vdl-chinese-source-readiness-gate-check`
- [x] `git diff --check -- Sources/Moongate/ViewModel.swift Sources/Moongate/ContentView.swift Tests/MoongateCoreTests/MacOSContentBoundaryTests.swift Tests/MoongateCoreTests/MacOSViewModelBoundaryTests.swift docs/exec-plans/2026-06-13-macos-apple-intelligence-hig.md`
- [x] Review-fix: added a regression case for `.appleFoundationOnDevice` readiness containing only `.appleIntelligenceUnavailable`, then updated Apple setup guidance so the steps still include the API-compatible fallback copy without adding engine-switching side effects. The focused regression failed on the missing fallback step before the fix and passed after it; `swift test --filter TranslationSettingsTests --jobs 1 --scratch-path .build/vdl-apple-intelligence-onboarding-review-fix` also passed 39 tests.
- [x] Batch review-fix: `swift test --filter MacOSViewModelBoundaryTests --jobs 1 --scratch-path .build/vdl-batch-chinese-source-gate-check` failed before implementation on the missing batch per-item gate/context boundary and passed after implementation with 2 tests.
- [x] `swift test --filter 'MacOSContentBoundaryTests|MacOSViewModelBoundaryTests|TranslationSettingsTests' --jobs 1 --scratch-path .build/vdl-batch-chinese-source-gate-check` passed 47 tests with zero failures.
- [x] `swift build --product Moongate --scratch-path .build/vdl-batch-chinese-source-gate-check` passed after sandbox escalation for Swift/clang module-cache writes only.
- [x] `git diff --check -- Sources/Moongate/ViewModel.swift Tests/MoongateCoreTests/MacOSViewModelBoundaryTests.swift Sources/MoongateMobileCore/TranslationModels.swift Tests/MoongateCoreTests/TranslationSettingsTests.swift Sources/Moongate/ContentView.swift Tests/MoongateCoreTests/MacOSContentBoundaryTests.swift docs/exec-plans/2026-06-13-macos-apple-intelligence-hig.md`
- [x] Sensitive keyword scan for the batch/onboarding slice only found static placeholder tokens, session variable names, and existing safety/cookie/PCC copy; no credential values were printed.
- [x] `swift test --filter MacOSViewModelBoundaryTests/testStartDownloadAwaitsRuntimeReadinessForNonChineseSourceSubtitles --jobs 1 --scratch-path .build/vdl-start-download-runtime-readiness-check-2` passed after the boundary-test fix.
- [x] `swift test --filter MacOSViewModelBoundaryTests --jobs 1 --scratch-path .build/vdl-start-download-runtime-readiness-check-2`
- [x] `swift test --filter 'MacOSContentBoundaryTests|MacOSViewModelBoundaryTests|TranslationSettingsTests' --jobs 1 --scratch-path .build/vdl-start-download-runtime-readiness-check-2` passed 48 tests with zero failures.
- [x] `swift build --product Moongate --scratch-path .build/vdl-start-download-runtime-readiness-check-2` passed after sandbox escalation for Swift/clang module-cache writes only.
- [x] `swift test --filter MacOSLoginBoundaryTests/testSaveLoginActionExplainsAppScopedCookieExportWithoutCookieDetails --jobs 1 --scratch-path .build/vdl-login-cookie-readiness-copy-check` failed before implementation on missing readiness-specific save help/value and passed after implementation.
- [x] `swift test --filter MacOSLoginBoundaryTests --jobs 1 --scratch-path .build/vdl-login-cookie-readiness-copy-check`
- [x] `swift test --filter 'MacOSContentBoundaryTests|MacOSViewModelBoundaryTests|MacOSLoginBoundaryTests|TranslationSettingsTests' --jobs 1 --scratch-path .build/vdl-login-cookie-readiness-copy-check` passed 57 tests with zero failures.
- [x] `swift build --product Moongate --scratch-path .build/vdl-login-cookie-readiness-copy-check` passed after sandbox escalation for Swift/clang module-cache writes only.
- [x] Reviewer-fix red check: `swift test --filter MacOSViewModelBoundaryTests --jobs 1 --scratch-path .build/vdl-start-download-snapshot-review-fix-2` failed on the new snapshot/settings assertions before implementation.
- [x] `swift test --filter MacOSViewModelBoundaryTests --jobs 1 --scratch-path .build/vdl-start-download-snapshot-review-fix-2`
- [x] `swift test --filter 'MacOSContentBoundaryTests|MacOSViewModelBoundaryTests|MacOSLoginBoundaryTests|TranslationSettingsTests' --jobs 1 --scratch-path .build/vdl-start-download-snapshot-review-fix-2` passed 57 tests with zero failures.
- [x] `swift build --product Moongate --scratch-path .build/vdl-start-download-snapshot-review-fix-2` passed after sandbox escalation for Swift/clang module-cache writes only.
- [x] Dependency setup side-effect help red check: `swift test --scratch-path .build/vdl-dependency-side-effect-help-check --filter MacOSDependencyBoundaryTests/testDependencySetupSideEffectButtonsExposeHelpAndAccessibilityHints --jobs 1` failed before implementation on the missing Help/accessibility hints.
- [x] `swift test --filter MacOSDependencyBoundaryTests/testDependencySetupSideEffectButtonsExposeHelpAndAccessibilityHints --jobs 1` passed 1 test with zero failures after implementation.
- [x] `swift test --filter MacOSDependencyBoundaryTests --jobs 1` passed 2 tests with zero failures after implementation.
- [x] `swift test --filter 'MacOSDependencyBoundaryTests|MacOSLoginBoundaryTests|MacOSAppBoundaryTests' --jobs 1` passed 13 tests with zero failures after the Dependency Setup help and HIG document calibration slice.
- [x] Review-fix validation: `swift test --filter MacOSDependencyBoundaryTests --jobs 1` passed 2 tests with zero failures after adding URL/action/disabled source-boundary assertions.
- [x] Review-fix validation: `swift test --filter 'MacOSDependencyBoundaryTests|MacOSLoginBoundaryTests|MacOSAppBoundaryTests' --jobs 1` passed 13 tests with zero failures after the HIG document stale-work cleanup.
- [x] `swift build --product Moongate` passed after sandbox escalation for Swift/clang module-cache writes only. The first sandboxed attempt failed on `~/.cache/clang/ModuleCache: Operation not permitted`.
- [x] `git diff --check -- Sources/Moongate/DependencySetupView.swift Tests/MoongateCoreTests/MacOSDependencyBoundaryTests.swift docs/design/macos-hig-restructure-confirmation.md docs/exec-plans/2026-06-13-macos-apple-intelligence-hig.md`
- [x] `rg -n '[[:blank:]]$' Sources/Moongate/DependencySetupView.swift Tests/MoongateCoreTests/MacOSDependencyBoundaryTests.swift docs/design/macos-hig-restructure-confirmation.md docs/exec-plans/2026-06-13-macos-apple-intelligence-hig.md` found no trailing whitespace.
- [x] Read-only quality review initially recommended no-ship because of stale HIG phase/acceptance wording and missing dependency action-boundary assertions. Those two findings were addressed in `docs/design/macos-hig-restructure-confirmation.md` and `Tests/MoongateCoreTests/MacOSDependencyBoundaryTests.swift`. The formula-summary finding was not reverted because that visible Homebrew side-effect summary was already present in the dirty dependency sheet before this help/hint slice.
- [x] Settings credential copy red check: `swift test --filter MoongateCoreTests.MacOSSettingsBoundaryTests/testAPICredentialCopyNamesOnlyUserTriggeredNetworkActions` failed before implementation because the old summary still said credentials were not sent before connection testing.
- [x] `swift test --filter MacOSSettingsBoundaryTests/testAPICredentialCopyNamesOnlyUserTriggeredNetworkActions --jobs 1` passed 1 test with zero failures after implementation.
- [x] `swift test --filter MacOSSettingsBoundaryTests --jobs 1` passed 10 tests with zero failures after implementation and review-test strengthening.
- [x] `swift test --filter 'MacOSSettingsBoundaryTests|TranslationSettingsTests' --jobs 1` passed 49 tests with zero failures, covering the Settings boundary plus Apple/API engine readiness contract.
- [x] `swift build --product Moongate` passed after sandbox escalation for Swift/clang module-cache writes only. The first sandboxed attempt failed on `~/.cache/clang/ModuleCache: Operation not permitted`.
- [x] `git diff --check -- Sources/Moongate/SettingsView.swift Tests/MoongateCoreTests/MacOSSettingsBoundaryTests.swift`
- [x] `rg -n '[[:blank:]]$' Sources/Moongate/SettingsView.swift Tests/MoongateCoreTests/MacOSSettingsBoundaryTests.swift` found no trailing whitespace.
- [x] Sensitive keyword scan for the Settings credential copy slice found only static copy/test terms such as `ANTHROPIC_AUTH_TOKEN`, `Bearer`, cookie status names, and `API key`; no credential values were printed.
- [x] `swift test --filter MacOSSettingsBoundaryTests/testClearLoginActionExplainsAppScopedSideEffects --jobs 1` passed 1 test with zero failures after narrowing the visible/destructive login-clear copy.
- [x] `swift test --filter MacOSSettingsBoundaryTests --jobs 1` passed 10 tests with zero failures after the Settings login-clear copy slice.
- [x] `swift test --filter 'MacOSSettingsBoundaryTests|MacOSLoginBoundaryTests' --jobs 1` passed 19 tests with zero failures, covering Settings copy plus related login boundaries.
- [x] `swift test --filter 'MacOSSettingsBoundaryTests|TranslationSettingsTests' --jobs 1` passed 49 tests with zero failures, covering Settings copy plus Apple/API translation settings boundaries.
- [x] `swift build --product Moongate` passed after sandbox escalation for Swift/clang module-cache writes only. The first sandboxed attempt failed on `~/.cache/clang/ModuleCache: Operation not permitted`.
- [x] `git diff --check -- Sources/Moongate/SettingsView.swift Tests/MoongateCoreTests/MacOSSettingsBoundaryTests.swift`
- [x] `rg -n '[[:blank:]]$' Sources/Moongate/SettingsView.swift Tests/MoongateCoreTests/MacOSSettingsBoundaryTests.swift` found no trailing whitespace.
- [x] Sensitive keyword scan for the Settings login-clear copy slice found only static copy/test terms such as `ANTHROPIC_AUTH_TOKEN`, `Bearer`, cookie status names, and `API key`; no credential or cookie values were printed.
- [x] Current-turn handoff validation after updating this ExecPlan: `git diff --check -- Sources/Moongate/SettingsView.swift Tests/MoongateCoreTests/MacOSSettingsBoundaryTests.swift docs/exec-plans/2026-06-13-macos-apple-intelligence-hig.md`
- [x] Current-turn handoff validation after updating this ExecPlan: `rg -n '[[:blank:]]$' Sources/Moongate/SettingsView.swift Tests/MoongateCoreTests/MacOSSettingsBoundaryTests.swift docs/exec-plans/2026-06-13-macos-apple-intelligence-hig.md` found no trailing whitespace.
- [x] Current-turn handoff validation after updating this ExecPlan: `swift test --filter 'MacOSSettingsBoundaryTests|MacOSLoginBoundaryTests' --jobs 1` passed 19 tests with zero failures.
- [x] Current-turn read-only quality review of the ExecPlan update found no Critical, Important, or Minor issues; remaining risk is source-boundary coverage rather than runtime SwiftUI/VoiceOver automation.
- [x] Ready destination footer red check: `swift test --filter MacOSContentBoundaryTests/testReadyFooterCopyDistinguishesSingleAndMultiFileDestinations --jobs 1` failed before implementation on the old hard-coded `~/Downloads` footer, and failed again after review-test strengthening until the helper mirrored `startDownload()`'s filtered `chosen` subtitle boundary.
- [x] `swift test --filter MacOSContentBoundaryTests/testReadyFooterCopyDistinguishesSingleAndMultiFileDestinations --jobs 1` passed 1 test with zero failures after the filtered-destination helper fix.
- [x] `swift test --filter MacOSContentBoundaryTests --jobs 1` passed 7 tests with zero failures after the ready destination footer slice.
- [x] `swift test --filter MacOSViewModelBoundaryTests --jobs 1` passed 3 tests with zero failures after the ready destination footer slice.
- [x] `git diff --check -- Sources/Moongate/ContentView.swift Tests/MoongateCoreTests/MacOSContentBoundaryTests.swift`
- [x] `rg -n '[[:blank:]]$' Sources/Moongate/ContentView.swift Tests/MoongateCoreTests/MacOSContentBoundaryTests.swift` found no trailing whitespace.
- [x] Final read-only quality review for the ready destination footer slice found no Critical, Important, or Minor issues after the filtered subtitle boundary fix.
- [x] Header action hierarchy red check: `swift test --filter MacOSContentBoundaryTests/testParseButtonExposesClearPrimaryActionAndAccessibleHelp --jobs 1` failed before implementation on the old visible competing paste action and missing icon-only accessibility assertions; it later failed again after review-test strengthening until the test allowed accessibility labels while rejecting visible `Label(` / `Text("粘贴...")` constructs in the paste button fragment.
- [x] `swift test --filter MacOSContentBoundaryTests/testParseButtonExposesClearPrimaryActionAndAccessibleHelp --jobs 1` passed 1 test with zero failures after the icon-only paste button and strengthened source-boundary test.
- [x] `swift test --filter MacOSContentBoundaryTests --jobs 1` passed 7 tests with zero failures after the header action hierarchy slice.
- [x] `git diff --check -- Sources/Moongate/ContentView.swift Tests/MoongateCoreTests/MacOSContentBoundaryTests.swift`
- [x] `rg -n '[[:blank:]]$' Sources/Moongate/ContentView.swift Tests/MoongateCoreTests/MacOSContentBoundaryTests.swift` found no trailing whitespace.
- [x] Final read-only quality review for the header action hierarchy slice found no Critical, Important, or Minor issues after the disabled-state and icon-only source-boundary test fix.
- [x] Apple readiness summary red checks: `swift test --filter MoongateCoreTests.MacOSSettingsBoundaryTests/testAppleReadinessPanelShowsScannableEngineStatusSummary --jobs 1` failed before implementation on the missing scannable summary, then failed again after review-test strengthening until fallback copy removed Apple/PCC/Cloud ambiguity and the duplicate `中文字幕翻译状态` block was removed. `swift test --filter MoongateCoreTests.MacOSSettingsBoundaryTests/testAppleSetupActionButtonsExposeSideEffectHelp --jobs 1` also failed before the review fix on the old fallback action help.
- [x] `swift test --filter MoongateCoreTests.MacOSSettingsBoundaryTests --jobs 1` passed 11 tests with zero failures after the Apple readiness copy polish and review fix.
- [x] `swift test --filter MoongateCoreTests.TranslationSettingsTests --jobs 1` passed 39 tests with zero failures after the Apple readiness copy polish and review fix.
- [x] `git diff --check -- Sources/Moongate/SettingsView.swift Tests/MoongateCoreTests/MacOSSettingsBoundaryTests.swift`
- [x] Final read-only quality review for the Apple readiness copy polish found no Critical or Important issues; remaining risk is source-boundary coverage rather than rendered SwiftUI accessibility-tree or click-lifecycle testing.
- [x] Apple Foundation model-unavailable onboarding red check: `swift test --filter MoongateCoreTests.TranslationSettingsTests/testAppleFoundationModelUnavailableGuidanceOpensSettingsBeforeRefresh --jobs 1` failed before implementation on the missing System Settings model-readiness action/path and passed after implementation; after review, it failed on the too-generic `系统设置` wording until the guidance specified `系统设置 > Apple Intelligence 与 Siri`.
- [x] `swift test --filter MoongateCoreTests.TranslationSettingsTests/testAppleFoundationModelUnavailableGuidanceOpensSettingsBeforeRefresh --jobs 1` passed 1 test with zero failures after the explicit path fix.
- [x] `swift test --filter MoongateCoreTests.TranslationSettingsTests --jobs 1` passed 40 tests with zero failures after the explicit path fix.
- [x] `git diff --check -- Sources/MoongateMobileCore/TranslationModels.swift Tests/MoongateCoreTests/TranslationSettingsTests.swift`
- [x] `rg -n '[[:blank:]]$' Sources/MoongateMobileCore/TranslationModels.swift Tests/MoongateCoreTests/TranslationSettingsTests.swift` found no trailing whitespace.
- [x] Final read-only quality review for the Apple Foundation model-unavailable onboarding slice found no Critical or Important issues; remaining risk is that UI-level system-settings routing and rendered guidance were not exercised in this slice.
- [x] Settings action help red check: `swift test --filter MoongateCoreTests.MacOSSettingsBoundaryTests/testAppleSetupActionButtonsExposeSideEffectHelp --jobs 1` failed before implementation on the missing `系统设置 > Apple Intelligence 与 Siri` help/accessibility copy and passed after implementation.
- [x] `swift test --filter MoongateCoreTests.MacOSSettingsBoundaryTests --jobs 1` passed 11 tests with zero failures after the Settings action help copy sync.
- [x] Read-only quality review for the Settings action help copy sync found no Critical or Important issues. The reviewer suggested binding the source-boundary assertions to the `.openAppleIntelligenceSettings` case specifically; the test was strengthened accordingly without changing production behavior.
- [x] Review-fix validation: `swift test --filter MoongateCoreTests.MacOSSettingsBoundaryTests/testAppleSetupActionButtonsExposeSideEffectHelp --jobs 1` passed after the case-specific source-boundary assertion.
- [x] `git diff --check -- Sources/Moongate/SettingsView.swift Tests/MoongateCoreTests/MacOSSettingsBoundaryTests.swift`
- [x] `rg -n '[[:blank:]]$' Sources/Moongate/SettingsView.swift Tests/MoongateCoreTests/MacOSSettingsBoundaryTests.swift` found no trailing whitespace.
- [x] Cloud Pro shared-model red check: `swift test --filter MoongateCoreTests.TranslationSettingsTests/testAppleFoundationCloudEnginesStayBlockedUntilPublicRuntimeIsAvailable --jobs 1` failed before implementation because `TranslationEngine` had no `.appleFoundationCloudPro` case.
- [x] Cloud Pro shared-model validation: `swift test --filter MoongateCoreTests.TranslationSettingsTests --jobs 1` passed 41 tests with zero failures.
- [x] Cloud Pro mobile validation: `swift test --filter MoongateCoreTests.MobileModelsTests/testMobileTranslationConfigurationClassifiesCredentialAndRuntimeNeeds --jobs 1` passed 1 test with zero failures.
- [x] Cloud Pro iOS validation: `swift test --filter MoongateiOSTests.IOSMobileAppModelTests/testAppleIntelligenceRoutesCoverLocalCloudAndCloudProWithoutClaimingAvailability --jobs 1`, `swift test --filter MoongateiOSTests.IOSMobileAppModelTests/testAppleIntelligenceRoutesMapCloudAndCloudProToDistinctSharedEngines --jobs 1`, and `swift test --filter MoongateiOSTests.IOSMobileAppModelTests/testRefreshingPCCRouteRemainsUnavailableWithoutIOS27RuntimeClaim --jobs 1` passed with zero failures.
- [x] Credential surface validation for Cloud Pro slice: `swift test --filter MoongateCoreTests.MacOSSettingsBoundaryTests/testCloudCredentialSurfaceStaysLimitedToAPICompatibleProviders --jobs 1` passed 1 test with zero failures.
- [x] Cloud Pro iOS credential-surface red checks: `swift test --filter MoongateiOSTests.IOSMobileAppModelTests --jobs 1` failed before the review fix because Cloud Pro API key save created `translation.appleFoundationCloudPro...` credential references, Cloud Pro connection testing showed API-compatible setup copy, and Cloud Pro static readiness did not expose Cloud Pro-specific copy. A later focused red check, `swift test --filter MoongateiOSTests.IOSMobileAppModelTests/testSelectingCloudProClearsExistingAPICompatibleCredentialReference --jobs 1`, failed before the cleanup fix because switching from a saved OpenAI-compatible credential to Cloud Pro left the old credential reference in the model.
- [x] Cloud Pro iOS credential-surface validation: `swift test --filter MoongateiOSTests.IOSMobileAppModelTests --jobs 1` passed 102 tests with zero failures after the API-key save, connection-test, static-readiness, and old-credential cleanup fixes.
- [x] Cloud Pro shared validation after review fixes: `swift test --filter MoongateCoreTests.TranslationSettingsTests --jobs 1` passed 42 tests with zero failures; `swift test --filter MoongateCoreTests.MobileModelsTests/testMobileTranslationConfigurationClassifiesCredentialAndRuntimeNeeds --jobs 1` passed 1 test with zero failures; `swift test --filter MoongateCoreTests.MacOSSettingsBoundaryTests/testCloudCredentialSurfaceStaysLimitedToAPICompatibleProviders --jobs 1` passed 1 test with zero failures; `git diff --check` passed.
- [x] Resume validation on 2026-06-14: `swift test --filter MoongateiOSTests.PackageBoundaryTests/testIOSSimulatorSmokeCanSeedAddCandidateSelectionForVisualReviewOnly --jobs 1` passed 1 test with zero failures.
- [x] Resume validation on 2026-06-14: `swift test --filter MoongateiOSTests.PackageBoundaryTests --jobs 1` passed 70 tests with zero failures.
- [x] Resume validation on 2026-06-14: `swift test --filter MoongateiOSTests.IOSMobileAppModelTests/testIOSRuntimeReadinessEvaluatorUsesDistinctPCCAndCloudProMessages --jobs 1` passed 1 test with zero failures.
- [x] Resume validation on 2026-06-14: `swift test --filter MoongateCoreTests.TranslationSettingsTests/testAppleFoundationCloudEnginesStayBlockedUntilPublicRuntimeIsAvailable --jobs 1` passed 1 test with zero failures.
- [x] Resume validation on 2026-06-14: `git diff --check` passed after the documentation calibration.
- [x] Main-flow fallback red/green on 2026-06-14: `swift test --filter MacOSContentBoundaryTests/testAppleSetupGuidanceShowsAPICompatibleFallbackWithoutChangingSettings --jobs 1` failed before implementation on the missing fallback text/helper and passed after implementation.
- [x] Main-flow fallback validation on 2026-06-14: `swift test --filter MacOSContentBoundaryTests --jobs 1` passed 8 tests with zero failures, `swift test --filter TranslationSettingsTests --jobs 1` passed 42 tests with zero failures, `swift test --filter MacOSSettingsBoundaryTests/testAppleReadinessPanelShowsScannableEngineStatusSummary --jobs 1` passed 1 test with zero failures, and `git diff --check` passed.
- [x] Main-flow fallback build validation on 2026-06-14: `swift build --product Moongate --jobs 1` failed inside the sandbox because Swift/clang tried to write `~/.cache/clang/ModuleCache`; the same command passed after approved sandbox escalation for local build cache writes only.
- [x] Main-flow Apple readiness summary red/green on 2026-06-14: `swift test --filter MacOSContentBoundaryTests/testAppleSetupGuidanceShowsScannableReadinessSummaryWithoutSideEffects --jobs 1` failed before implementation on the missing summary helper/call and passed after implementation.
- [x] Main-flow Apple readiness summary validation on 2026-06-14: `swift test --filter MacOSContentBoundaryTests --jobs 1` passed 9 tests with zero failures, `swift test --filter MacOSSettingsBoundaryTests --jobs 1` passed 11 tests with zero failures, and `swift test --filter TranslationSettingsTests --jobs 1` passed 42 tests with zero failures.
- [x] Main-flow Apple readiness summary build/check validation on 2026-06-14: `git diff --check -- Sources/Moongate/ContentView.swift Tests/MoongateCoreTests/MacOSContentBoundaryTests.swift docs/exec-plans/2026-06-13-macos-apple-intelligence-hig.md` passed, trailing-whitespace scan found no matches, and `swift build --product Moongate --jobs 1` passed after sandbox escalation for Swift/clang module-cache writes only. The sandboxed build attempt failed on `~/.cache/clang/ModuleCache: Operation not permitted`.
- [x] Main-flow Apple readiness summary read-only quality review on 2026-06-14 found no Critical or Important issues. Minor residual gaps: source-string boundary tests cannot prove rendered SwiftUI/VoiceOver behavior or every future indirect side-effect helper, and Cloud Pro/PCC availability wording still needs runtime/visual scenario checks before claiming real-device validation.
- [x] Queue header accessibility red/green on 2026-06-14: `swift test --filter MacOSQueueBoundaryTests/testQueueHeaderExposesReadableTaskSummaryWithoutChangingActions --jobs 1` failed before implementation on the missing header accessibility summary/helper and passed after implementation.
- [x] Queue header accessibility validation on 2026-06-14: `swift test --filter MacOSQueueBoundaryTests --jobs 1` passed 3 tests with zero failures, and `swift test --filter MacOSContentBoundaryTests --jobs 1` passed 9 tests with zero failures.
- [x] Queue header accessibility build/check validation on 2026-06-14: `git diff --check -- Sources/Moongate/QueueSectionView.swift Tests/MoongateCoreTests/MacOSQueueBoundaryTests.swift docs/exec-plans/2026-06-13-macos-apple-intelligence-hig.md` passed, trailing-whitespace scan found no matches, and `swift build --product Moongate --jobs 1` passed after sandbox escalation for Swift/clang module-cache writes only. The sandboxed build attempt failed on `~/.cache/clang/ModuleCache: Operation not permitted`.
- [x] Dependency Setup close-action red/green on 2026-06-14: `swift test --filter MacOSDependencyBoundaryTests/testDependencySetupCloseButtonExplainsInstallCancellationScope --jobs 1` failed before implementation on the missing install-running close copy/help helper and passed after implementation.
- [x] Dependency Setup close-action validation on 2026-06-14: `swift test --filter MacOSDependencyBoundaryTests --jobs 1` passed 3 tests with zero failures, and `swift test --filter 'MacOSDependencyBoundaryTests|MacOSLoginBoundaryTests|MacOSAppBoundaryTests' --jobs 1` passed 14 tests with zero failures.
- [x] Dependency Setup close-action build/check validation on 2026-06-14: `git diff --check -- Sources/Moongate/DependencySetupView.swift Tests/MoongateCoreTests/MacOSDependencyBoundaryTests.swift docs/exec-plans/2026-06-13-macos-apple-intelligence-hig.md` passed, trailing-whitespace scan found no matches, and `swift build --product Moongate --jobs 1` passed after sandbox escalation for Swift/clang module-cache writes only. The sandboxed build attempt failed on `~/.cache/clang/ModuleCache: Operation not permitted`.
- [ ] Earlier parallel verification attempts with separate scratch paths failed for environment reasons before exercising this change: one build overlapped with another SwiftPM build and reported a file-modified-during-build error; another ran out of disk space while compiling unrelated iOS tests. The project had about 105 MB free at that point. Only this turn's `.build/vdl-dependency-side-effect-help-check*` generated scratch directories were removed to recover space before the successful sequential reruns.
- [ ] Larger HIG restructure has explicit July confirmation before broad UI rewrites.

Note: the product builds required sandbox escalation because SwiftPM attempted to write the normal clang module cache under `~/.cache/clang/ModuleCache`. No dependency installation or network access was performed. Later full-package validation attempts are sensitive to the machine's low `/private/tmp` free space; prefer reusing an existing scratch path or freeing space only after July confirms. At the end of the Apple Foundation model-unavailable onboarding slice, the project volume had about 296 MiB free, so full package or product builds were intentionally not rerun.
