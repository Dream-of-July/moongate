# iOS Native Architecture ExecPlan

## Status

Proposed architecture plus current review-shell baseline for the first iOS implementation slices.

This document is executable input for future iOS workers. The repository now has a SwiftPM `MoongateiOS` review target, a minimal `MoongateiOSApp` host, an iOS Keychain credential adapter, and a pure mobile API-compatible translation provider. It must not be read as proof that a signed installable iOS app bundle, simulator/device scheme, entitlements, background modes, real downloads, or real render workers already exist.

## Background And Product Intent

The repository currently contains a macOS SwiftUI app, shared Swift `MoongateCore`, pure Swift `MoongateMobileCore`, a Swift CLI, an independent Windows C#/WPF implementation, a SwiftPM `MoongateiOS` review shell, and a minimal SwiftPM `MoongateiOSApp` host. There is no signed installable iOS app bundle yet.

The iOS product should be a native phone workflow, not a clone of the desktop window. The user should be able to add a supported media source, choose format/subtitle options, monitor queue work honestly across foreground/background limits, find completed outputs in a Library, and configure translation credentials/readiness in Settings.

Existing mobile contract work in `Sources/MoongateMobileCore/MobileModels.swift` is the starting point. It defines pure mobile models and protocols such as `MobileParser`, `MobileDownloadEngine`, `MobileTranslationProvider`, `SubtitleProcessor`, `RenderExporter`, `TaskRepository`, and `SecureCredentialStore`. iOS workers should implement platform adapters around those contracts instead of pulling desktop `Process`, Homebrew, yt-dlp dependency setup, AppKit, or WebKit-cookie export behavior into mobile UI.

## Current Repository Facts

- `Package.swift` declares `.iOS(.v17)` and `.macOS(.v14)`, has a pure `MoongateMobileCore` target, includes a SwiftPM `MoongateiOS` review target, and includes a minimal `MoongateiOSApp` executable host. The host now starts from `IOSMobileAppModel.live()` rather than preview data. This does not prove simulator/device signing, entitlements, background modes, or App Store/TestFlight readiness.
- `Sources/MoongateCore` contains desktop-capable shared Swift logic. Some files use desktop assumptions such as external tools, local application support paths, and current settings persistence.
- `Sources/Moongate` is the macOS app target and should stay macOS-only.
- `windows/` is a separate native Windows implementation and should not be touched by iOS work.
- `Sources/MoongateMobileCore/MobileModels.swift` is pure Swift/Foundation mobile domain surface and already models Add, task snapshots, capabilities, background limits, Library items, secure credential references, translation config, and mockable service protocols.
- Xcode 26.5 / iPhoneOS 26.5 SDK evidence exists locally for `FoundationModels.framework`, `URLSessionConfiguration.background(withIdentifier:)`, `BGProcessingTaskRequest`, and `BGContinuedProcessingTaskRequest`.
- There is no local iOS 27 SDK evidence. Any iOS 27 language in implementation or UI must be runtime capability detection and future SDK verification, not a compile-time or product promise.

## Goals

- Add a real iOS-native architecture that can be implemented in small, reviewable slices.
- Preserve current macOS and Windows behavior.
- Keep platform-specific implementation outside pure `MoongateMobileCore` mobile contracts unless the code remains Foundation-only and cross-platform safe.
- Provide HIG-aligned Add, Queue, Library, and Settings surfaces.
- Store API keys in Keychain through a `SecureCredentialStore` implementation and keep secrets out of logs, JSON snapshots, tests, screenshots, crash text, and task artifacts.
- Use Apple Translation, Foundation Models, and future Apple Intelligence paths only through explicit readiness adapters and verifiable platform capabilities.
- Treat background transfer/render as system-bounded and interruptible.

## Non-Goals

- Do not port the macOS dependency installer, Homebrew setup, or desktop external-process pipeline into iOS.
- Do not modify macOS SwiftUI files, Windows files, or CLI behavior while creating the iOS shell.
- Do not claim broad yt-dlp desktop site parity on iOS before a compliant mobile parser/download engine proves it.
- Do not bypass DRM, paywalls, login restrictions, platform access controls, App Store policy, MDM policy, or enterprise security controls.
- Do not hardcode API keys, store API keys in `UserDefaults`, or serialize secret values into `MobileTranslationConfiguration`.
- Do not describe iOS background work as unlimited.
- Do not promise iOS 27 APIs until an iOS 27 SDK or official documentation is available and compile/runtime checks are added.

## iOS Product IA

Use SwiftUI with `TabView` for the four top-level surfaces and `NavigationStack` inside each tab. Keep the visual language quiet and native: large titles only where the screen benefits from scanability, standard lists/forms/toolbars, system sheets for choices, confirmation dialogs for destructive actions, and HIG-sized tappable controls.

### Add

Purpose: start a task from a pasted URL, clipboard URL, share extension input, or imported local file.

Primary states:

- Empty: URL field, paste button, import file button, recent clipboard suggestion if permission-safe, and disabled primary action until input validates.
- Analyzing: navigation title remains stable; show inline progress and cancel action.
- Candidate selection: list `MobileVideoCandidate` rows with title, kind, detail, and unsupported reason where applicable.
- Ready: show title/thumbnail if available, format picker, subtitle picker, export profile picker, and Add to Queue primary action.
- Unsupported: show specific `MobileUnsupportedReason` and one next action such as try another source or import file.
- Failed: show `MobileTaskError` bucket, retry, and editable input.

Controls:

- Text field or URL input row with clear button.
- Paste and import icon buttons in toolbar or compact action row.
- Format selection as a sheet/list, not a dense desktop picker.
- Subtitle selection with checkmarks and auto-generated subtitle labeling.
- Export profile segmented/menu control: subtitle file, soft subtitle, burned-in video where capabilities allow.

HIG notes:

- Avoid explaining the whole product on the Add screen.
- Use standard `ShareLink`/document picker flows for imported/exported files where possible.
- Do not expose desktop terms like yt-dlp, ffmpeg, Homebrew, or cookies in the main Add flow.

### Queue

Purpose: make active and pending work observable, controllable, and honest.

Primary states:

- Empty: concise empty state with Add action.
- Waiting/analyzing/downloading/translating/exporting: rows backed by `MobileTaskSnapshot`, phase label, progress, current artifact/export intent, and available actions from `availableActions`.
- Needs foreground: visible state for `MobileTaskState.needsForegroundToContinue` with Open App to Continue and cancel.
- System deferred/interrupted: map `MobileBackgroundPolicy` and `MobileBackgroundLimit` to user-readable state without implying failure.
- Failed/cancelled/completed: retry/remove/open/share actions as applicable.

Controls:

- Pause/resume only when `backgroundPolicy.canResume` and the engine supports it.
- Cancel as a confirmation dialog for active work.
- Retry from failed rows.
- Task detail sheet with source, selected format, subtitles, background policy, artifacts, and diagnostic-safe error bucket.

HIG notes:

- Progress text should fit Dynamic Type and should not jump layout.
- Use system progress views and list row actions; avoid desktop overlay panels.
- If background work may expire, say the app will try to continue, not that it will finish.

### Library

Purpose: show completed outputs and let users open/share/save/delete records.

Primary states:

- Empty: Add action.
- Available: list `MobileLibraryItem` records grouped by date or sorted newest-first.
- File missing: record remains but actions change to locate/delete.
- Permission denied: explain that access must be restored through Files/Photos permission or export again.
- Deleting: row disabled with progress/spinner where needed.

Controls:

- Open, Share, Save to Files, Save to Photos, Delete Record actions from `MobileLibraryItem.availableActions`.
- Search once there are enough records to justify it.
- Detail screen showing artifacts: original media, translated subtitle file, soft subtitle, rendered video, transcript, metadata.

HIG notes:

- Prefer `ShareLink`, `UIDocumentPickerViewController`, and Photos save permission prompts through platform wrappers.
- Deleting a Library record must not silently delete external user-owned files unless the action text and confirmation are explicit.

### Settings

Purpose: configure translation, privacy, storage, background preferences, and diagnostics.

Primary states:

- Translation not configured: choose engine and configure credential/readiness.
- Credential configured: show provider/model/base URL metadata and masked credential state, not the secret.
- Apple readiness unavailable: show concrete readiness issues such as unsupported OS, unsupported language pair, language package needed, Apple Intelligence disabled, device not eligible, or model not ready.
- Storage/background: show current storage usage, export location guidance, Wi-Fi/cellular policy if implemented, and background limitations.
- Diagnostics: local-only sanitized logs/export if future workers add it.

Controls:

- `Form` with sections: Translation, Apple Intelligence, Storage, Background, Privacy, About.
- Secure text entry for API key save/replace flow; no persistent visible token field.
- Test translation / check readiness button only after configuration is syntactically valid.
- Destructive credential deletion with confirmation.

HIG notes:

- Settings should not be a troubleshooting manual.
- Keep sensitive values masked and avoid copying secrets into pasteboard or logs.
- Prefer system terminology: Files, Photos, Background App Refresh, Low Power Mode, Cellular Data.

## Target, Package, And Project Organization

Recommended first structure:

- Keep `MoongateMobileCore` as the shared pure mobile domain and deterministic logic target.
- Add iOS app code under a new directory such as `Sources/MoongateiOS/`.
- Add iOS tests under a new directory such as `Tests/MoongateiOSTests/` if SwiftPM remains the build driver; use an Xcode project/workspace only if SwiftPM cannot express the required app bundle, entitlements, background modes, share extension, or UI test scheme cleanly.
- Keep macOS app code in `Sources/Moongate/` unchanged.
- Keep Windows code in `windows/` unchanged.

Package guidance:

- Do not change the global platform declaration in a way that breaks current macOS builds. If `Package.swift` needs iOS, use additive platform support such as adding `.iOS(...)` while preserving `.macOS(.v14)`, then verify the macOS products still build.
- Gate platform app targets with `#if !os(Windows)` and platform-specific source directories rather than mixing UIKit-only files into `MoongateCore`.
- If app-bundle capabilities require an Xcode project, keep SwiftPM as the source-of-truth for `MoongateCore` where practical and place iOS project files in an iOS-specific directory. Do not migrate the whole repository to a new project layout in the first slice.
- Use a small composition root for iOS, for example `MoongateiOSApp`, `iOSAppContainer`, and protocol-backed services. UI should depend on mobile protocols, not concrete URLSession/BGTask/Keychain classes.

Suggested module boundaries:

- `MoongateMobileCore`: mobile contracts, readiness types, service protocols, and non-secret configuration snapshots.
- `MoongateCore`: desktop-capable core, settings persistence, existing translation/subtitle/download/burn-in behavior, and compatibility re-export of mobile-safe translation types where needed.
- `MoongateiOS`: SwiftUI screens, iOS service implementations, Keychain adapter, URLSession background adapter, BGTask adapter, Files/Photos export adapters, Apple readiness adapters.
- `MoongateiOSTests`: mocks and state tests for view models/service orchestration.
- Future share extension: separate iOS extension target only after the main Add flow works.

## iOS Service Architecture

### MobileParser

Contract: `resolveCandidates(for:)` and `analyze(candidate:)`.

Implementation candidates:

- `DirectMediaMobileParser`: validates direct media URLs and imported files using URL path/MIME hints and lightweight HEAD/metadata where allowed. Network validation must be optional and testable.
- `HLSMobileParser`: recognizes `.m3u8` playlists and extracts basic variants if implemented with a safe parser.
- `WebPageMobileParser`: only if compliant page fetching and parsing are approved; responses must be treated as untrusted input.
- `CompositeMobileParser`: tries supported parsers in order and returns unsupported candidates with `MobileUnsupportedReason` instead of pretending desktop parity.

Do not call desktop yt-dlp or spawn external processes from iOS parser code.

### MobileDownloadEngine

Contract: downloads a `MobileDownloadRequest` and emits `MobileTaskProgress`.

Implementation candidates:

- `URLSessionMobileDownloadEngine`: uses `URLSessionConfiguration.background(withIdentifier:)` for direct files and compatible HLS segment downloads. Persists request/task mapping in `TaskRepository`.
- `ForegroundDownloadEngine`: fallback for imported local files or transfers that cannot use background sessions.
- `ResumableDownloadCoordinator`: owns resume data when the platform provides it and records non-resumable state honestly.

The engine should return `MobileTaskResult` artifacts with app-owned storage identifiers. It must not expose credential-bearing URLs in logs or artifacts.

### MobileTranslationProvider

Contract: `readiness(for:)` and `translate(_:)`.

Implementation candidates:

- `APIKeyTranslationProvider`: OpenAI-compatible and Anthropic-compatible adapter using `MobileTranslationConfiguration` plus `SecureCredentialStore`. Requests should reuse existing request-building semantics where possible, but secrets must come from Keychain at call time.
- `AppleTranslationProvider`: adapter for Apple Translation framework where SDK and runtime support are verified. It should map language availability and package/download readiness into `TranslationReadinessIssue`.
- `FoundationModelsTranslationProvider`: adapter for `FoundationModels.framework` with `SystemLanguageModel.availability`, `supportsLocale`, and model readiness checks. Treat it as local/on-device only unless official APIs say otherwise.
- `UnavailableTranslationProvider`: explicit adapter for future or unsupported modes such as PCC/Cloud Pro when no public app API is verified.

### SubtitleProcessor

Contract: produces subtitle artifacts from source subtitle and translated segments.

Implementation candidates:

- Pure Swift SRT/WebVTT parser/serializer reused or extracted from existing core where it is platform-safe.
- `SubtitleFileProcessor`: writes translated `.srt` or `.vtt` into app-owned storage.
- `SoftSubtitlePackager`: creates sidecar subtitle artifacts or an AVFoundation-compatible package if later proven feasible.

Keep subtitle processing deterministic and unit-tested with fixtures.

### RenderExporter

Contract: exports rendered or packaged media from `MobileRenderRequest`.

Implementation candidates:

- `AVFoundationRenderExporter`: use AVFoundation composition/export where subtitle overlay and target formats are feasible. This must be prototype-verified on fixture media before product commitment.
- `SubtitleFileOnlyRenderExporter`: returns subtitle-file artifacts when render is unsupported or not selected.
- `ForegroundRequiredRenderExporter`: marks tasks as `needsForegroundToContinue` when the export cannot continue safely in background.

Do not assume ffmpeg exists on iOS. Do not add binary render dependencies without explicit product, licensing, size, and App Store review approval.

### TaskRepository

Contract: load/save/remove `MobileTaskSnapshot`.

Implementation candidates:

- `FileTaskRepository`: JSON or SQLite in app container for queue snapshots and Library records; no secret values.
- `ActorTaskRepository`: actor wrapper for serialized access and test determinism.
- Future `SQLiteTaskRepository`: only if query needs justify it.

Repository records should include background session identifiers, task IDs, artifact storage identifiers, and safe error buckets, but never API keys, bearer tokens, cookies, or signed URLs.

### SecureCredentialStore

Contract: save/delete/check/read credentials by `SecureCredentialReference`. `MobileTranslationConfiguration` stores only `SecureCredentialReference`; secret values stay behind the store and are fetched by provider adapters at call time.

Implementation candidate:

- `KeychainCredentialStore`: stores API keys in iOS Keychain using service/account names, `kSecClassGenericPassword`, app access group only if an extension later requires it, and a data protection class appropriate for app use.

The current protocol has `saveCredential`, `deleteCredential`, `hasCredential`, and `credential(for:)`. Tests must continue proving that serialized mobile configuration contains references only, not secret values.

## Apple Intelligence, Foundation Models, And Translation Readiness

Use one readiness model across UI and services:

- `TranslationReadiness.isReady == true`: the selected engine can attempt a translation now.
- `needsConfiguration`: API base/model/credential reference is missing or invalid.
- `needsRuntimeVerification`: SDK/runtime check has not run yet.
- `needsLanguageDownload`: Apple Translation language assets or model assets are not ready.
- `unsupportedLanguagePair`: the selected source/target language pair is unsupported.
- `appleIntelligenceUnavailable`: device, OS, setting, or account state does not allow Apple Intelligence.
- `modelUnavailable`: Foundation model is not ready or not available.
- `pccUnavailable`: no verified public adapter exists for this mode.

Mapping product language to verifiable platform capability:

- "Cloud/API translation": OpenAI-compatible or Anthropic-compatible HTTPS API using a user-provided API key stored in Keychain. This is cloud because the request leaves the device.
- "Local Apple Translation": Apple Translation framework where language pair availability and downloads are verified at runtime. This is not an API-key cloud provider.
- "Local Apple Intelligence/Foundation Models": `FoundationModels.framework` and `SystemLanguageModel` runtime availability on an eligible device with Apple Intelligence enabled and model ready.
- "Cloud Pro", "PCC", or "Private Cloud Compute": product labels must remain unavailable/future unless a public app-facing API is verified. They should map to `appleFoundationPCC` plus `pccUnavailable`, not to a fake network adapter.
- "iOS 27 support": runtime capability detection and future SDK verification only. Do not add compile-time iOS 27 symbols or UI promises without evidence.

Adapter design:

- Create a small `TranslationReadinessChecking` or provider-specific readiness adapter in iOS code.
- Keep Apple framework imports in isolated files guarded with `#if canImport(Translation)` or `#if canImport(FoundationModels)` plus `@available`.
- Return structured readiness issues rather than throwing for expected unavailable states.
- Treat all generated translations as untrusted text for rendering/export escaping.
- Unit-test readiness mapping with fake adapters; compile-test real Apple adapters only in iOS-capable build slices.

## Background Download And Render Architecture

iOS background execution is best effort. The app can request background work; the system can defer, expire, throttle, or terminate it.

### URLSession Background

Use for:

- Direct file downloads.
- Segment downloads where the implementation can map work into background `URLSessionDownloadTask` or safe resumable tasks.
- Relaunch/resume handling through background session identifiers.

Do not use for:

- Arbitrary CPU-heavy rendering.
- Work that requires continuous custom parser execution after every segment unless it is checkpointed.
- Transfers requiring secrets embedded in logs or persistent task descriptions.

Required behavior:

- Persist the mapping between `URLSessionTask.taskIdentifier`, request ID, and `MobileTaskSnapshot`.
- Handle completion, failure, cancellation, authentication challenge, resume data, and app relaunch.
- Move completed files into app-owned storage and publish `MobileTaskArtifact`.

### BGContinuedProcessingTaskRequest

Use on iOS 26+ where available for user-initiated continued processing that has visible progress, such as an export/render task started by the user.

Boundaries:

- It is not a guarantee that work will run to completion.
- The scheduler may reject, queue, defer, or expire work.
- The app must report progress and handle expiration by checkpointing and updating `MobileBackgroundPolicy`.
- Use this for active user-visible continuation, not silent periodic maintenance.

### BGProcessingTaskRequest

Use for:

- Deferrable cleanup, indexing, retry preparation, artifact maintenance, or non-urgent processing.
- Work that can wait for system conditions such as power/network.

Do not use for:

- Immediate user-visible render completion promises.
- Long-running unlimited processing.

Queue mapping:

- If the system accepts background continuation, set policy to `.continuedProcessing` with limits such as `.systemTimeLimit` and `.userVisibleNotificationRequired`.
- If work is deferred, use `.systemDeferred`.
- If expiration fires, persist `.systemInterrupted` or `MobileTaskState.needsForegroundToContinue` depending on resumability.
- If a render cannot checkpoint, mark `.notResumable` and expose cancel/open-app action only.

## Security, Credentials, And Logging

API key rules:

- Store API keys only in Keychain through `SecureCredentialStore`.
- Persist only `SecureCredentialReference` in mobile settings/task records.
- Never put API keys, bearer tokens, cookies, signed URLs, request headers, or raw provider responses into normal logs, JSON snapshots, crash messages, screenshots, or exported diagnostic bundles.
- Use masked display such as configured/not configured or last four characters only if the value is derived safely and never persisted as a secret surrogate.
- Deleting a credential should remove the Keychain item and update any `MobileTranslationConfiguration` references that would otherwise look configured.

Logging rules:

- Use a sanitizer at logging boundaries for URLs, headers, provider request bodies, and errors.
- Log machine-readable error buckets and request IDs instead of raw secrets.
- Redact query parameters by default. Only allowlisted non-sensitive parameters may be shown.
- Unit tests must cover representative redaction cases before diagnostic export is added.

Enterprise-managed computer consideration:

- Do not add code that bypasses MDM, VPN, proxy, DLP, background restrictions, App Store review, or user permission prompts.
- Do not use private APIs.
- Do not weaken TLS validation or certificate checks for provider calls.

## Testing Plan

### Unit Tests

- `MobileModelsTests`: Codable stability, default capabilities, background policy semantics, task actions, Library actions, credential reference serialization.
- Parser tests with local fixtures for direct file, HLS, unsupported web page, unsupported DRM/login-required cases.
- Subtitle tests for SRT/WebVTT parsing, translation segment mapping, escaping, and export profile decisions.
- Repository tests with temporary app-container-like directories and no secret values.
- Keychain adapter tests behind an iOS test target; use test service names and cleanup.
- Translation readiness mapping tests with fake Apple/API adapters.
- Log redaction tests for URLs, headers, API keys, cookies, bearer tokens, and provider errors.

### UI State Tests

- Add: empty, invalid URL, analyzing, candidate selection, ready, unsupported, failed.
- Queue: empty, active phases, paused/resumable, non-resumable, needs foreground, system deferred, failed, completed.
- Library: empty, available, file missing, permission denied, deleting.
- Settings: no credential, credential configured, readiness unavailable, unsupported language pair, model not ready, credential deletion.

### Simulator Tests

- SwiftUI navigation, form validation, mocked services, file import/export UI where simulator supports it.
- Dynamic Type sizes, dark mode, landscape/portrait where relevant, Reduce Motion.
- Background URLSession behavior can be smoke-tested, but simulator is not sufficient for final background claims.

### Real Device Background Tests

- Direct media download: foreground, background, lock screen, app relaunch after completion.
- Network loss and retry/resume.
- Low Power Mode and cellular/Wi-Fi policy if implemented.
- BG continued processing: start render/export, background app, observe progress, expiration, resume/foreground-required state.
- App termination and relaunch recovery.
- Storage full or low-storage behavior if reproducible safely.

### Accessibility Tests

- VoiceOver labels, traits, values, and rotor order for all four tabs.
- Dynamic Type up to accessibility sizes without clipped buttons or overlapping progress text.
- Sufficient contrast in light/dark mode.
- Reduce Motion respected for queue/progress transitions.
- Touch targets meet HIG minimums.

## First Implementation Tasks

Each task is intentionally narrow. Workers must check `git status` before editing and must not modify files outside the listed range.

### Task 1: iOS Target Skeleton With Mock Services

File scope:

- `Package.swift`
- `Sources/MoongateiOS/**`
- `Tests/MoongateiOSTests/**` if needed for state tests

Work:

- Add a minimal iOS SwiftUI app target or document why SwiftPM cannot produce the required app bundle and create the smallest iOS project wrapper.
- Create `MoongateiOSApp`, app container, tab shell, and mock implementations of mobile protocols.
- Do not wire real downloads, Apple frameworks, or background tasks. Keychain wiring now exists only for credential storage and must not be treated as proof that translation connection testing or real downloads are complete.

Validation:

- `swift test --scratch-path /private/tmp/vdl-ios-skeleton-test`
- iOS simulator build command selected by the worker, for example `xcodebuild` against the generated scheme if a project exists.
- `swift build --product Moongate --scratch-path /private/tmp/vdl-macos-regression-build` to prove macOS target still builds.

Must not do:

- Do not edit `Sources/Moongate/**`.
- Do not edit `windows/**`.
- Do not add network calls or dependencies.
- Do not store credentials.

### Task 2: Add Flow State Model And UI

File scope:

- `Sources/MoongateiOS/Add/**`
- `Sources/MoongateiOS/AppContainer/**` only for dependency injection wiring
- `Tests/MoongateiOSTests/Add/**`

Work:

- Implement Add screen/view model against `MobileParser`.
- Cover empty/analyzing/candidate/ready/unsupported/failed states.
- Use mock parser fixtures.

Validation:

- Targeted Add state tests.
- iOS simulator UI smoke test.
- Accessibility inspection for labels and Dynamic Type.

Must not do:

- Do not implement real webpage scraping.
- Do not call desktop parser/process code.
- Do not change shared mobile model names unless the contract is insufficient and tests are updated.

### Task 3: Queue And Repository Shell

File scope:

- `Sources/MoongateiOS/Queue/**`
- `Sources/MoongateiOS/Storage/**`
- `Tests/MoongateiOSTests/Queue/**`
- `Tests/MoongateiOSTests/Storage/**`

Work:

- Implement queue UI from `MobileTaskSnapshot`.
- Add an actor-backed repository implementation using app-container storage with safe JSON or SQLite.
- Persist no secrets.

Validation:

- Repository round-trip tests.
- Queue available-action state tests.
- Log/serialization inspection test proving credential values are absent.

Must not do:

- Do not add real background work yet.
- Do not write outside app-container paths in tests except approved temporary scratch paths.

### Task 4: Keychain Credential Store And Settings UI

File scope:

- `Sources/MoongateiOS/Settings/**`
- `Sources/MoongateiOS/Security/**`
- `Tests/MoongateiOSTests/Settings/**`
- `Tests/MoongateiOSTests/Security/**`

Work:

- Implement `KeychainCredentialStore`.
- Build Settings translation configuration UI with save/replace/delete credential flows.
- Store only `SecureCredentialReference` in persisted config.
- Current status: `IOSKeychainCredentialStore` exists and `IOSMobileAppModel.saveAPIKeyDraft` routes through injected `SecureCredentialStore`; save/replace/delete UX and provider/model/base URL UI are still incomplete.

Validation:

- Keychain adapter tests on iOS-capable test destination.
- Settings state tests.
- Redaction tests for token-like strings.
- Current verified coverage includes model-state tests and source boundary tests on macOS SwiftPM host builds; an iOS-capable Keychain test destination is still open.

Must not do:

- Do not print API keys.
- Do not store tokens in `UserDefaults`, JSON, screenshots, fixtures, or failure messages.
- Do not weaken TLS or add provider network calls in this task.

### Task 5: Translation Readiness Adapters

File scope:

- `Sources/MoongateiOS/Translation/**`
- `Tests/MoongateiOSTests/Translation/**`
- Shared `Sources/MoongateCore/**` only if protocol/readiness contract changes are strictly required

Work:

- Implement fake-testable readiness adapters for API-key engines, Apple Translation, Foundation Models, and unavailable PCC/Cloud Pro.
- Isolate Apple framework imports with `#if canImport(...)` and `@available`.
- Map iOS 27/future states to runtime detection, not compile-time claims.

Validation:

- Readiness mapping unit tests.
- iOS build on simulator/device SDK available to the worker.
- macOS Swift tests if `MoongateCore` changes.

Must not do:

- Do not implement fake PCC/Cloud Pro network translation.
- Do not require cloud credentials for Apple local engines.
- Do not add iOS 27 symbols without SDK evidence.

### Task 6: Background URLSession Download Engine

File scope:

- `Sources/MoongateiOS/Download/**`
- `Sources/MoongateiOS/Background/**`
- `Tests/MoongateiOSTests/Download/**`

Work:

- Implement `URLSessionMobileDownloadEngine` for direct supported downloads.
- Persist background task mapping and completion recovery.
- Map failures/resume data to `MobileTaskSnapshot` and `MobileBackgroundPolicy`.

Validation:

- Unit tests with mocked URL protocol/session wrapper.
- Simulator smoke test.
- Real-device test plan execution before claiming production readiness.

Must not do:

- Do not claim support for arbitrary websites.
- Do not embed credentials in URLs/logs/task descriptions.
- Do not treat background transfer as guaranteed.

### Task 7: Subtitle Processing And Library

File scope:

- `Sources/MoongateiOS/Subtitles/**`
- `Sources/MoongateiOS/Library/**`
- `Tests/MoongateiOSTests/Subtitles/**`
- `Tests/MoongateiOSTests/Library/**`
- Shared `Sources/MoongateCore/**` only for pure subtitle helpers if needed

Work:

- Implement subtitle-file export and Library records.
- Use Files/Share flows through platform adapters.
- Add Library UI states.

Validation:

- Fixture subtitle unit tests.
- Library state tests.
- Manual simulator export/share smoke test.

Must not do:

- Do not delete external user files silently.
- Do not implement burned-in render in this task.

### Task 8: Render Export Prototype And BG Continued Processing

File scope:

- `Sources/MoongateiOS/Render/**`
- `Sources/MoongateiOS/Background/**`
- `Tests/MoongateiOSTests/Render/**`

Work:

- Prototype `AVFoundationRenderExporter` on fixture media.
- Add checkpointing and expiration handling.
- Use `BGContinuedProcessingTaskRequest` on iOS 26+ only where available and appropriate.

Validation:

- Fixture export tests where feasible.
- Real-device background render test.
- Accessibility review for foreground-required state.

Must not do:

- Do not bundle ffmpeg or other binary dependencies without separate approval.
- Do not claim unlimited background rendering.
- Do not mark non-resumable render work as pause/resume capable.

## Risks And Rollback

- iOS parser coverage may be much narrower than desktop. Rollback is to direct-file/import/HLS-only support with clear unsupported states.
- Background rendering may be expired or deferred. Rollback is foreground-only render with `needsForegroundToContinue`.
- Apple Intelligence availability depends on OS, device eligibility, user settings, model readiness, locale, and possibly account/region policy. Rollback is API-key or Apple Translation fallback.
- SwiftPM may not be enough for a fully entitled iOS app and extension setup. Rollback is a small iOS Xcode project wrapper while keeping `MoongateCore` shared.
- Adding iOS platform support to `Package.swift` could accidentally affect macOS builds. Rollback is to isolate the iOS project without broad package changes.
- Latest iOS read-only review keeps iOS No-ship at P0 because the local Xcode wrapper still lacks a signed installable app target with development team, entitlements/capabilities, iOS test scheme, and device/TestFlight proof. `Info.plist` currently permits background task identifiers, but there is no entitlement/runtime validation for BG continued processing, background URLSession relaunch, or Keychain behavior on an iOS-hosted test target.

## Decision Log

- 2026-06-13: Use `MobileModels.swift` protocols as the initial iOS service contract.
- 2026-06-13: Keep iOS code in a new app target/directory and preserve existing macOS target boundaries.
- 2026-06-13: Treat Foundation Models and BG continued processing as iOS 26 SDK-backed capabilities, with runtime checks.
- 2026-06-13: Treat iOS 27 as unverified until SDK or official API evidence exists.
- 2026-06-13: API keys belong in Keychain; mobile persisted config stores references only.
- 2026-06-13: `SecureCredentialStore` now includes a read method for provider adapters; `APICompatibleMobileTranslationProvider` uses injected transport and readable credentials while keeping serialized config reference-only.
- 2026-06-13: Background `URLSession` finish-events handling must wait for pending delegate event persistence. The app delegate completion handler is only safe to consume after the delegate has finished moving the downloaded temp file into app storage and recording completed/failed recovery outcomes.
- 2026-06-13: iOS background/render capability claims require signed app-bundle, entitlement/capability, iOS-hosted test, simulator/device smoke, and real background lifecycle evidence. Source/unit checks around BGTask and URLSession are necessary but are not sufficient to mark the iOS app shippable.
- 2026-06-13: The next minimal iOS validation slice should add an iOS-hosted XCTest target and shared scheme `TestAction` for `IOSKeychainCredentialStore` roundtrip testing before adding entitlement-shaped source files. Without a signed/provisioned target, entitlements remain source shape only and do not prove runtime capability.

## Progress Log

- 2026-06-13: Created this architecture plan from current repository evidence and mobile model contracts.
- 2026-06-13: Added live empty-state iOS app entry, iOS Keychain credential adapter, and pure mobile OpenAI/Anthropic-compatible translation provider tests. Removed production Add-view mock import/share buttons; mock methods remain for tests/preview behavior only.
- 2026-06-13: Closed two quality-review blockers in the iOS shell. The production Add action now routes through `IOSMobileAppModel.analyzeURL(_:)` and an injected `MobileParser`; the live default parser returns an explicit unsupported state until a real parser is implemented, while tests/previews can inject a successful parser or use mock helpers. Credentialed mobile translation providers now reject plaintext HTTP base URLs before request construction, so API keys are not attached to non-HTTPS endpoints.
- 2026-06-13: Revalidated the live iOS storage/download boundary after adding app-owned task/download persistence. Fixed a brittle package-boundary assertion so it accepts normal Swift line wrapping while still requiring `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)`, `FileTaskRepository`, and `IOSMobileDownloadEngine` in `IOSMobileAppModel.live(storageDirectoryURL:)`. Verification passed with `swift test --scratch-path /private/tmp/vdl-package-boundary-green --filter PackageBoundaryTests/testIOSLiveModelUsesAppOwnedStorageForDownloadAndTaskState`, full `swift test --scratch-path /private/tmp/vdl-current-full-swift-test-9` executing 113 tests with 0 failures, `git diff --check`, and product builds for `Moongate`, `moongate-cli`, and `MoongateiOSApp`.
- 2026-06-13: Addressed storage/download quality-review blockers. Queue snapshots now persist immediately and queue mutations synchronize to `TaskRepository`, but raw source URLs are kept only in memory for the current Add -> Download session; persisted metadata artifacts use opaque `mobile-source:<task-id>` references and legacy `source:<url>` values are sanitized before JSON write. The download transport rejects non-2xx HTTP responses before artifact storage, and the download engine validates task IDs before moving files or creating background-transfer records. Added translated-SRT file export foundation through `MobileSubtitleDocument` and `IOSMobileSubtitleProcessor`, limited to app-owned `Subtitles/` storage. Latest verification: `swift test --scratch-path /private/tmp/vdl-current-full-swift-test-10` executed 126 tests with 0 failures; `git diff --check`; and product builds for `Moongate`, `moongate-cli`, and `MoongateiOSApp` using `*-latest-2` scratch paths.
- 2026-06-13: Tightened legacy queue restore secrecy. `restoreQueueFromRepository()` now migrates old metadata artifacts containing `source:<url>` to `mobile-source:<task-id>` and persists the cleaned task back without rehydrating signed URLs into memory, so old signed URLs are scrubbed from `mobile-tasks.json`; restored tasks without a current in-memory source fail explicitly before calling the download engine. Queue progress updates remain in memory while terminal states (`completed`, `failed`, cancellation/removal) synchronize to `TaskRepository`, avoiding stale progress snapshots overwriting final state. Verification: `swift test --scratch-path /private/tmp/vdl-ios-model-current-serial-3 --filter IOSMobileAppModelTests` executed 42 tests with 0 failures.
- 2026-06-13: Final blocker-review revalidation passed for the current iOS/storage/subtitle/translation state. `FileTaskRepositoryTests`, `TranslationSettingsTests`, `IOSMobileDownloadEngineTests`, and `IOSMobileSubtitleProcessorTests` passed together with 43 tests and 0 failures; full `swift test --scratch-path /private/tmp/vdl-current-full-swift-test-12` passed 140 tests with 0 failures. SwiftPM host/product builds passed for `MoongateiOSApp`, `Moongate`, and `moongate-cli` using `*-final-current` scratch paths after the known local Swift/clang module-cache escalation. `git diff --check` passed, and the production-source secret scan over `Sources` plus Android main sources had no hits. Android Gradle validation remains blocked because this checkout has no Gradle wrapper and no local `gradle`.
- 2026-06-13: Fresh handoff revalidation before final summary. Full `swift test --scratch-path /private/tmp/vdl-current-full-swift-test-14` passed 140 tests with 0 failures. `git diff --check` passed. Production-source secret scan over `Sources` plus Android main sources had no hits for sentinel secrets, signed-URL markers, access tokens, common API key patterns, or AWS key IDs. SwiftPM product builds passed for `MoongateiOSApp`, `Moongate`, and `moongate-cli` using `*-final-current-2` scratch paths after the known local Swift/clang module-cache escalation. Android validation remains blocked: `test -x android/gradlew` returned `no-wrapper`, and `command -v gradle` returned no path.
- 2026-06-13: Continued Task 7 Library presentation closure. Added `IOSLibraryActionPresenter` to map `MobileLibraryActionOutcome` into explicit iOS system-action commands, `IOSArtifactStore` to resolve only app-owned artifact references, and one-shot `pendingLibraryActionCommand` consumption in `IOSMobileAppModel` so system UI presentation is driven by command state rather than status strings. `IOSLibraryView` now consumes that command for `ShareLink`, `.fileExporter`, and quick-look presentation while keeping Photos save and locate-file as honest unresolved platform steps. Verification passed with the targeted Library presentation tests, `swift test --scratch-path /private/tmp/vdl-ios-library-presentation-tests-2 --filter MoongateiOSTests` (82 tests, 0 failures), full `swift test --scratch-path /private/tmp/vdl-full-after-library-presentation` (168 tests, 0 failures), and `git diff --check`. Refined production-source secret scanning found no sentinel secrets, signed source URLs, bearer values, OpenAI-style keys, or AWS key IDs; broader `access_token` hits were defensive sanitizer literals.
- 2026-06-13: Closed the latest iOS Library and cloud-translation safety slice. `IOSLibraryView` no longer relies on status-only text or a no-op quick-look shim: app-owned artifacts are resolved through `IOSArtifactStore`, share goes through `ShareLink`, file export uses `.fileExporter`, destructive delete requires a confirmation dialog, and iOS open uses a `QLPreviewController` bridge behind `#if os(iOS)`. Cloud API-key references are scoped to the active cloud engine and endpoint host, and changing either endpoint or engine clears the current credential reference until the user saves a key for that new scope. `URLSessionMobileTranslationTransport` defaults to an ephemeral session with no URL cache, no cookie storage, no credential storage, and `.reloadIgnoringLocalCacheData`. Verification passed with `swift test --scratch-path /private/tmp/vdl-library-security-targets-2 --filter 'IOSMobileAppModelTests/testChangingCloudTranslationEndpointOrEngineRequiresCredentialReconfirmation|PackageBoundaryTests/testIOSMobileTranslationTransportDefaultsToEphemeralNoCacheSession|IOSArtifactStoreTests|IOSLibraryActionPresenterTests|PackageBoundaryTests/testIOSLibraryUsesSystemPresentationInsteadOfStatusOnlyActions'` (7 tests, 0 failures), `swift test --scratch-path /private/tmp/vdl-ios-tests-library-security --filter MoongateiOSTests` (82 tests, 0 failures), full `swift test --scratch-path /private/tmp/vdl-full-library-security` (168 tests, 0 failures), and SwiftPM product builds for `MoongateiOSApp`, `Moongate`, and `moongate-cli` using `/private/tmp/vdl-*-library-security` scratch paths after the known local module-cache escalation.
- 2026-06-13: Added render planning pre-work before Task 8 runtime implementation. `MobileRenderRequestPlanner` now turns completed burned-in subtitle tasks into a `MobileRenderRequest` only when source media, translated subtitle artifacts, and render capabilities are present, and otherwise returns structured blocked reasons. Soft subtitle artifacts are blocked until an explicit conversion path exists. `IOSRenderRequestPlanner` maps those requests to iOS execution policy: foreground-required for unavailable renderer/packager/height cases, and `.continuedProcessing` only when injected runtime evidence says continued processing and checkpointing are available. This does not implement `AVFoundationRenderExporter`, `BGContinuedProcessingTaskRequest`, entitlements, checkpoint files, or real background render execution. Verification passed with `swift test --scratch-path /private/tmp/vdl-mobile-render-request-green --filter MobileModelsTests` (25 tests, 0 failures), `swift test --scratch-path /private/tmp/vdl-ios-render-planner-recheck --filter IOSRenderRequestPlannerTests` (5 tests, 0 failures), `swift test --scratch-path /private/tmp/vdl-ios-render-slice-ios-tests --filter MoongateiOSTests` (87 tests, 0 failures), full `swift test --scratch-path /private/tmp/vdl-render-planner-full` (178 tests, 0 failures), and a production-source secret scan over `Sources`, Android main sources, and `Scripts` with no hits.
- 2026-06-13: Added the first local Xcode app-bundle wrapper under `ios/` without replacing the SwiftPM iOS shell. The wrapper contains `ios/MoongateiOSApp.xcodeproj`, `ios/MoongateiOS/Info.plist`, a native `@main` app entry hosting `MoongateIOSRootView`, and `Scripts/build-ios-xcode.sh`. Signing remains disabled (`CODE_SIGNING_ALLOWED=NO`, manual signing, no development team), no `UIBackgroundModes` are declared, and the helper only builds locally with `xcodebuild`; it does not install, create an ipa, or contact Apple Developer provisioning services. Verification passed with targeted red/green `PackageBoundaryTests`, `zsh Scripts/build-ios-xcode.sh simulator`, and `zsh Scripts/build-ios-xcode.sh device` after local Xcode/SwiftPM cache/CoreSimulator sandbox escalation. Full revalidation also passed with `swift test --jobs 1 --scratch-path /private/tmp/vdl-final-after-ios-xcode-wrapper-2` (197 tests, 0 failures), SwiftPM product builds for `MoongateiOSApp`, `Moongate`, and `moongate-cli`, and `git diff --check`. This is unsigned simulator/device SDK app-bundle build proof only, not simulator launch, signed device install, signed archive, TestFlight, or App Store readiness.
- 2026-06-13: Post-handoff revalidation updated the Android settings boundary assertion used by the iOS package-boundary suite. The old assertion prohibited password input because it assumed Android secure storage was absent; the current contract now requires ephemeral non-saveable API-key draft state, masked credential entry, Keystore-backed save, and clearing the in-memory draft after save. This keeps the cross-platform secret boundary aligned with the Android Keystore adapter without adding any iOS render/runtime behavior. Verification passed with `swift test --jobs 1 --scratch-path /private/tmp/vdl-android-settings-boundary-green-2 --filter PackageBoundaryTests/testAndroidSettingsKeepsAPIKeyDraftEphemeralAndSavesThroughKeystore` (1 test, 0 failures), `swift test --jobs 1 --scratch-path /private/tmp/vdl-android-data-boundary-after-test-contract-3 --filter AndroidDataBoundaryTests` (10 tests, 0 failures), `swift test --jobs 1 --scratch-path /private/tmp/vdl-render-planner-review-ios-tests-final-2 --filter MoongateiOSTests` (96 tests, 0 failures), full `swift test --jobs 1 --scratch-path /private/tmp/vdl-render-planner-review-full-final` (197 tests, 0 failures), `git diff --check`, and a production-source credential-pattern scan over `Sources`, Android main sources, and `Scripts` with no hits.
- 2026-06-13: Final local revalidation for this continuation passed after the Xcode wrapper and Android settings boundary changes. Fresh verification in the current checkout: `swift test --jobs 1 --scratch-path /private/tmp/vdl-final-current-full-swift-test` (197 tests, 0 failures), `swift build --product MoongateiOSApp --scratch-path /private/tmp/vdl-final-current-ios-app-build`, `swift build --product Moongate --scratch-path /private/tmp/vdl-final-current-macos-build`, `swift build --product moongate-cli --scratch-path /private/tmp/vdl-final-current-cli-build`, `Scripts/build-ios-xcode.sh simulator`, `git diff --check`, and a narrow token-shape scan over production/source plan paths with no file hits. SwiftPM and Xcode builds needed local Swift/clang/Xcode cache access outside the workspace; no dependency download or signing/provisioning was performed. Android Gradle validation remains blocked because `android/gradlew` is absent and `command -v gradle` returns no local Gradle. The mobile work is still No-ship for product claims: no signed iOS archive, no simulator/device install or launch proof, no real background transfer/resume QA, no real AVFoundation render execution, no Android APK build/test/runtime validation, and no production Android parser/downloader/renderer proof.
- 2026-06-13: Added the first local simulator launch-smoke helper as the next gate after unsigned app-bundle build. `Scripts/run-ios-simulator-smoke.sh` builds the local Xcode simulator app, then uses `xcrun simctl install`, `launch`, and `terminate` against an already booted simulator; it does not run UI automation, create or erase simulators, install to a physical device, create an ipa, contact Apple Developer services, download dependencies, or use provisioning updates. Verification passed with `swift test --jobs 1 --scratch-path /private/tmp/vdl-green-ios-smoke-script-boundary-4 --filter PackageBoundaryTests/testIOSSimulatorSmokeScriptInstallsAndLaunchesLocalAppBundleOnly`, targeted render/export tests, full `swift test --jobs 1 --scratch-path /private/tmp/vdl-full-after-simulator-smoke-script` (209 tests, 0 failures), `zsh -n Scripts/run-ios-simulator-smoke.sh`, `git diff --check`, and `zsh Scripts/build-ios-xcode.sh simulator`. A real smoke attempt is still unproven: `zsh Scripts/run-ios-simulator-smoke.sh` exited 66 because no simulator was booted, and two explicit attempts to boot an existing iPhone 17 simulator failed with CoreSimulatorService `NSPOSIXErrorDomain Code=53`. Do not claim simulator launch/install until this script succeeds.
- 2026-06-13: Wired the iOS Queue render-export action into the live app model. Completed burned-in subtitle tasks now expose `MobileTaskAction.exportRenderedVideo` only when the task has source media, translated subtitle artifacts, render capability, and no existing rendered-video artifact. Soft subtitle artifacts are deliberately excluded until conversion exists. `IOSMobileAppModel.live(storageDirectoryURL:)` now creates `IOSMobileRenderExporter`, `performQueueAction` routes `.exportRenderedVideo`, and successful exports merge the rendered artifact, make it the primary result, append a Library record, and persist the completed task. This is queue orchestration over the AVFoundation exporter boundary; it still is not real fixture/device render QA or background render execution. Verification passed with targeted red/green coverage for `IOSMobileAppModelTests/testExportingRenderedVideoUsesRenderExporterUpdatesQueueAndLibrary`, targeted boundary coverage for `PackageBoundaryTests/testIOSLiveModelWiresRenderExporterAndQueueRenderAction`, the full `swift test --jobs 1 --scratch-path /private/tmp/vdl-full-after-render-action` suite (208 tests, 0 failures), SwiftPM product builds for `MoongateiOSApp`, `Moongate`, and `moongate-cli` using `/private/tmp/vdl-*-after-render-action` scratch paths after local Swift/clang module-cache escalation, `git diff --check`, and a narrow real-secret shape scan with no hits. Android Gradle validation remains blocked because `android/gradlew` is absent and `command -v gradle` returns no local Gradle.
- 2026-06-13: Follow-up iOS Queue UX pass exposed the highest-priority row action as a visible `Button` while keeping secondary actions in the overflow menu. Priority order is start download, export rendered video, export translated subtitle, foreground continue, retry, open result, then share result. This directly addresses the review finding that Queue primary actions were hidden in a generic menu, without changing the model action path or claiming simulator/device UI proof. Verification passed with red/green `PackageBoundaryTests/testIOSQueueRowsExposePrimaryActionOutsideOverflowMenu`, `swift test --jobs 1 --scratch-path /private/tmp/vdl-ios-primary-queue-ios-tests --filter MoongateiOSTests` (107 tests, 0 failures), full `swift test --jobs 1 --scratch-path /private/tmp/vdl-ios-primary-queue-full` (209 tests, 0 failures), and `git diff --check`.
- 2026-06-13: Closed a quality-review blocker in render-export orchestration. Repeatedly triggering `.exportRenderedVideo` while a task is already `.exporting` now reports the in-progress state and returns without re-planning or marking the task failed, so the first export completion can still merge the rendered artifact and update Library. Red verification first reproduced the bug with `swift test --jobs 1 --scratch-path /private/tmp/vdl-red-repeat-render-export --filter IOSMobileAppModelTests/testRepeatedRenderExportDoesNotOverwriteActiveExportCompletion` (1 test, 7 failures), then green verification passed with `/private/tmp/vdl-green-repeat-render-export`, render action targeted tests under `/private/tmp/vdl-render-action-targets-after-repeat-fix` (4 tests, 0 failures), `MoongateiOSTests` under `/private/tmp/vdl-ios-tests-after-repeat-render-fix` (108 tests, 0 failures), full `swift test --jobs 1 --scratch-path /private/tmp/vdl-full-after-repeat-render-fix` (210 tests, 0 failures), and SwiftPM product builds for `MoongateiOSApp`, `Moongate`, and `moongate-cli` using `/private/tmp/vdl-*-after-repeat-render-fix` scratch paths after local Swift/clang module-cache escalation. `git diff --check` passed, a narrow real-secret shape scan had no hits, and Android Gradle validation is still blocked by the missing wrapper/local Gradle.
- 2026-06-13: Added an iOS background-transfer recovery contract without claiming real background relaunch. `BackgroundTransferRegistry` now persists `BackgroundTransferRecoveryOutcome` values for completed, failed, and expired transfer outcomes. `IOSMobileAppModel.restoreQueueFromRepository()` applies matched outcomes before conservative active-task fallback: completed outcomes restore completed Queue state and Library records; failed outcomes restore failed state; expired outcomes restore `needsForegroundToContinue`; unmatched outcomes remain in the registry for a later restore. Verification passed with `swift test --jobs 1 --scratch-path /private/tmp/vdl-bg-recovery-targets --filter 'BackgroundTransferRegistryTests|IOSMobileAppModelTests/testRestoringQueueAppliesCompletedBackgroundTransferOutcomeBeforeForegroundFallback|IOSMobileAppModelTests/testRestoringQueueAppliesFailedAndExpiredBackgroundTransferOutcomesWithoutDroppingUnmatchedOutcomes'` (6 tests, 0 failures), `swift test --jobs 1 --scratch-path /private/tmp/vdl-bg-recovery-ios-tests --filter MoongateiOSTests` (112 tests, 0 failures), full `swift test --jobs 1 --scratch-path /private/tmp/vdl-bg-recovery-full` (217 tests, 0 failures), and `git diff --check`. Real `URLSession` background delegate/relaunch, simulator install, device background QA, and BG continued-processing runtime proof remain open.
- 2026-06-13: Added a small iOS background-transfer event handler slice and kept render action visibility aligned with actual render planning. `IOSBackgroundTransferEventHandler` can now turn completed system temp files into app-owned original-media artifacts and can record failed or expired download outcomes without deleting registry evidence; expired outcomes are marked system-interrupted/non-resumable so restore keeps them foreground-bound. `MobileTaskSnapshot.availableActions` and the Android domain parity slice now expose burned-in `exportRenderedVideo` only when a translated subtitle artifact exists; soft subtitle artifacts remain blocked until an explicit conversion path exists. Verification: red `swift test --jobs 1 --scratch-path /private/tmp/vdl-red-mobile-action-soft-subtitle --filter MobileModelsTests/testCompletedBurnedInTasksExposeRenderActionOnlyWithTranslatedSubtitleArtifact` first hit a compile blocker from newly added background handler tests; after adding handler APIs, `swift test --jobs 1 --scratch-path /private/tmp/vdl-ios-bg-handler-after-fix-serial --filter IOSBackgroundTransferEventHandlerTests` passed (2 tests, 0 failures), `swift test --jobs 1 --scratch-path /private/tmp/vdl-mobile-models-after-bg-handler-serial --filter MobileModelsTests` passed (30 tests, 0 failures), and `swift test --jobs 1 --scratch-path /private/tmp/vdl-android-boundary-after-bg-handler-serial --filter AndroidDataBoundaryTests` passed (15 tests, 0 failures). Three concurrent Swift test commands briefly failed with `input file ... was modified during the build`; the fix was to run SwiftPM verification sequentially. This still does not prove real background delegate relaunch, simulator/device background QA, or fixture AVFoundation output dimensions.
- 2026-06-13: Revalidated the background-transfer event handler against the current tree with sequential SwiftPM checks. `IOSBackgroundTransferEventHandlerTests` passed for completed/failed/expired events, the full `MoongateiOSTests` suite passed, and full `swift test --jobs 1 --scratch-path /private/tmp/vdl-bg-event-full-current` passed 232 tests with 0 failures. `git diff --check` passed. Production-source credential-pattern scanning over `Sources`, Android main sources, `Scripts`, and `ios` had no hits for the checked key/token/private-key shapes. Android Gradle validation remains blocked by missing `android/gradlew` and missing PATH `gradle`; no network, wrapper generation, or dependency install was attempted. The open runtime gates remain unchanged: actual `URLSession` background relaunch, simulator/device launch, signed install, and real-device background QA are not proven.
- 2026-06-13: Added the iOS Add ready export-profile picker and connected it to queue creation. The Add screen now exposes only the two currently meaningful choices, `字幕文件` and `带字幕视频`, through a native SwiftUI `Picker`; soft subtitles remain hidden until the packager/conversion path is real. `IOSMobileAppModel` now keeps `selectedAddExportProfile` and uses it when creating the queued task, adding `.videoRender` capability only for burned-in exports while preserving foreground-required/non-resumable policy. Unsupported and failed Add copy was simplified so the UI no longer exposes desktop-parser wording or raw error enum values. Verification included the expected red failure for missing `selectedAddExportProfile`, green targeted `swift test --jobs 1 --scratch-path /private/tmp/vdl-green-ios-add-export-picker-2 --filter 'IOSMobileAppModelTests/testJoiningQueueUsesSelectedBurnedInExportProfileAndRenderCapability|PackageBoundaryTests/testIOSAddReadyStateExposesNativeExportPickerWithoutSoftSubtitleNoise'` (2 tests, 0 failures), `swift test --jobs 1 --scratch-path /private/tmp/vdl-ios-tests-after-add-export-picker --filter MoongateiOSTests` (127 tests, 0 failures), full `swift test --jobs 1 --scratch-path /private/tmp/vdl-full-after-ios-add-export-picker` (240 tests, 0 failures), and `swift build --product MoongateiOSApp --scratch-path /private/tmp/vdl-ios-app-after-add-export-picker`. `git diff --check` passed. A strict credential-pattern scan over the changed mobile source/test/docs scope had no hits after excluding test-ID false positives such as `task-subtitle-*`. Android Gradle validation remains blocked: `android/gradlew` is absent and PATH `gradle` is unavailable.
- 2026-06-13: Revalidated the current source-reference, Apple Translation provider, and iOS app-host state. A stale/concurrent Swift test session had reported source URL failures, but fresh targeted coverage passed for signed current-session downloads and plain HTTPS source restoration. The only current code change in this slice was a Swift 6 XCTest fix: `FileTaskRepositoryTests` now awaits `IOSSourceReferenceStore.loadSources()` before asserting, avoiding async work inside XCTest autoclosures. Verification passed with the targeted source-reference tests (3 tests, 0 failures), `swift test --jobs 1 --scratch-path /private/tmp/vdl-ios-tests-after-source-repro-2 --filter MoongateiOSTests` (127 tests, 0 failures), full `swift test --jobs 1 --scratch-path /private/tmp/vdl-full-after-ios-source-fix` (240 tests, 0 failures), `git diff --check`, SwiftPM product builds for `MoongateiOSApp`, `Moongate`, and `moongate-cli` after local Swift/clang module-cache sandbox escalation, `zsh Scripts/build-ios-xcode.sh all` after local Xcode/CoreSimulator/cache sandbox escalation, and a production-source credential-pattern scan over `Sources`, Android main sources, `Scripts`, and `ios` with no hits. Actual simulator install/launch remains unproven: `zsh Scripts/run-ios-simulator-smoke.sh` safe-failed with exit 66 because no simulator was booted.
- 2026-06-13: Added iOS Add ready format/subtitle selection and verified it carries the selected format and manual/auto subtitle ids into queued download requests. `IOSMobileAppModel` owns selected Add format/subtitle state, `MoongateIOSRootView` exposes a native format picker and subtitle toggles, and the queued task uses `MobileDownloadSelection` instead of silently taking defaults. Verification passed with `swift test --jobs 1 --scratch-path /private/tmp/vdl-format-subtitle-green-2 --filter IOSMobileAppModelTests/testJoiningQueueUsesSelectedFormatAndSubtitleChoicesForDownloadRequest` and the focused iOS suite.
- 2026-06-13: Advanced the simulator smoke gate from helper-only to one successful local install/launch proof. `Scripts/run-ios-simulator-smoke.sh` now supports `VDL_IOS_SIMULATOR_BOOT_IF_NEEDED=1` to boot an existing available simulator without creating or erasing devices. Running `VDL_IOS_SIMULATOR_BOOT_IF_NEEDED=1 zsh Scripts/run-ios-simulator-smoke.sh` booted an existing simulator, built the unsigned simulator bundle, installed and launched `com.local.videodownloader.ios`, returned a pid, and terminated the app. This remains simulator smoke only: no signing, ipa export, physical-device install, TestFlight/App Store readiness, UI automation, or background QA is proven.
- 2026-06-13: Repaired the current Android Add URL boundary gate that was failing because no-credential assertions scanned the entire Android Settings-bearing source files. The assertion now slices only `AndroidAddUrlPlanner`, `withStagedDirectUrl`, and the Add URL callback, so Settings can keep explicit API-key/Keystore coverage while Add URL staging remains offline and credential-free. Verification passed with `swift test --jobs 1 --scratch-path /private/tmp/vdl-android-boundary-after-add-url-scope --filter AndroidDataBoundaryTests` (21 tests, 0 failures), the import hash regression test, full `swift test --jobs 1 --scratch-path /private/tmp/vdl-full-after-android-boundary-scope-final` (252 tests, 0 failures), and `git diff --check`. Android Gradle validation remains blocked: no `android/gradlew` and no PATH `gradle`.
- 2026-06-13: Added and verified an idempotency guard for completed iOS background-transfer events. `IOSBackgroundTransferEventHandler.recordCompletedDownload` no longer deletes the existing app-owned artifact before a replacement file is safely available; it stages the system temp file beside the destination and uses `FileManager.replaceItemAt` so a missing replacement cannot remove the prior stored artifact. Verification included the expected red failure for `IOSBackgroundTransferEventHandlerTests/testCompletedBackgroundDownloadDoesNotDeleteStoredArtifactWhenReplacementIsMissing`, then green `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-green-bg-handler-idempotency --filter IOSBackgroundTransferEventHandlerTests/testCompletedBackgroundDownloadDoesNotDeleteStoredArtifactWhenReplacementIsMissing` (1 test, 0 failures), `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-bg-handler-after-idempotency --filter IOSBackgroundTransferEventHandlerTests` (3 tests, 0 failures), and `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-ios-tests-after-bg-idempotency --filter MoongateiOSTests` (130 tests, 0 failures). This is event-handler unit coverage only; real `URLSession` relaunch, completion-handler drain, lock/kill/network-loss recovery, simulator launch, signed install, and device background QA remain unproven.
- 2026-06-13: Read-only iOS and UX reviews reconfirmed No-ship status for the requested release goal. At the time of review, live downloads still used foreground `URLSession.shared.download(from:)` rather than a background `URLSessionDownloadDelegate` path, and live downloaded tasks only produced `.originalMedia`, so transcript/subtitle translation and burned-in render actions were not reachable from the real live Add -> Download path without test-only fixture artifacts. Later slices added a foreground sidecar SRT path and a background URLSession starter path, so this review is no longer current for those two points. The remaining high-risk iOS gaps still stand: real background relaunch/resume QA, UI-only Photos save, potential rotated-video render geometry bugs, Files export reading large videos fully into memory, signed/device/TestFlight validation, and visual/accessibility QA.

- 2026-06-13: Added the first foreground iOS live subtitle-source slice. The Add screen can import a local `.srt` sidecar through the system file importer, `IOSMobileAppModel.attachImportedSubtitle(fileURL:languageCode:)` immediately copies safe SRT files into app-owned storage, rejects unsafe or secret-like filenames, auto-selects the imported sidecar subtitle, converts the selected local sidecar into a `.transcript` artifact when queueing, and preserves processable subtitle artifacts when the completed download result arrives from the foreground download engine. This makes translated-subtitle export and burned-in render reachable from a production Add -> Download path when the user provides a local SRT sidecar. Verification passed with focused sidecar tests, full `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-ios-tests-after-sidecar-2 --filter MoongateiOSTests` (138 tests, 0 failures), `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-core-boundary-after-sidecar --filter AndroidDataBoundaryTests` (26 tests, 0 failures), and `git diff --check`. This remains No-ship for release claims: no remote subtitle URL fetcher, no real background URLSession executor, no signed/device proof, no Android APK/Gradle proof, and no production burn-in QA.
- 2026-06-13: Tightened iOS recovery cleanup for source references. `IOSMobileAppModel.restoreSourceReferences(for:)` now removes persisted source references for terminal queue tasks (`completed` and `cancelled`) plus orphaned task IDs while retaining retryable failed/waiting work, so completed Library records do not keep direct HTTPS source URLs in `mobile-source-references.json` after app relaunch. Added `IOSMobileAppModelTests/testRestoringQueuePrunesSourceReferencesForTerminalTasks`, covering completed/cancelled/orphaned cleanup, retryable source restoration, and removal after a successful retry download. Verification passed with `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-ios-source-ref-prune-target --filter IOSMobileAppModelTests/testRestoringQueuePrunesSourceReferencesForTerminalTasks`, `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-ios-appmodel-source-ref-prune --filter IOSMobileAppModelTests` (69 tests, 0 failures), and full `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-full-after-ios-source-ref-prune-2` (282 tests, 0 failures). This is persistence/recovery hygiene only; real background `URLSession` delegate relaunch, signed/device proof, and real-device background QA remain open.
- 2026-06-13: Added iOS non-secret cloud translation configuration persistence. `IOSTranslationConfigurationStore` stores `MobileTranslationConfiguration` as `mobile-translation-configuration.json` under app-owned storage; `IOSMobileAppModel.live(storageDirectoryURL:)` restores that file and recomputes readiness, while cloud engine/endpoint/model edits, API-key save/clear/failure, and Apple route readiness changes persist the current non-secret snapshot. The API key secret still only goes through `SecureCredentialStore`; the JSON stores `SecureCredentialReference` metadata only. Verification followed red/green: the new relaunch test first failed because `live` had no injectable credential-store path, then passed with `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-ios-config-after-live-overload --filter IOSMobileAppModelTests/testLiveModelPersistsNonSecretCloudTranslationConfigurationAcrossLaunches`; `IOSMobileAppModelTests` also passed with `/private/tmp/vdl-ios-app-model-after-config` (71 tests, 0 failures), and `PackageBoundaryTests/testIOSLiveModelUsesAppOwnedStorageForDownloadAndTaskState` passed with `/private/tmp/vdl-ios-live-boundary-after-overload`. This closes the reviewed persistence gap only; it does not prove real provider connectivity, Apple Intelligence execution, or device runtime behavior.
- 2026-06-13: Added the first iOS background-download launcher source/test slice. `IOSBackgroundDownloadLauncher` starts HTTPS-only background `URLSession` download tasks through an injectable session, rejects unsafe task IDs before touching the session or registry, computes app-owned `downloads/<task-id>.<extension>` storage identifiers, records a `.backgroundTransfer`/`.resumable` transfer record before `resume()`, and uses `IOSBackgroundURLSessionDescriptor.makeConfiguration()` rather than `URLSession.shared`. Verification passed with `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-bg-launcher-integrated-rerun-a --filter IOSBackgroundDownloadLauncherTests` (4 tests, 0 failures) after one transient SwiftPM `/private/tmp` build DB/object-rename failure on the prior scratch path. This is launch-contract coverage only; real background delegate relaunch, completion-handler drain, network-loss recovery, simulator/device background QA, entitlements, and signed install remain open.
- 2026-06-13: Connected the background startup contract to the live iOS model through `IOSBackgroundURLSessionDownloadStarter`. The starter creates no-cache background `URLSessionDownloadTask` requests through an injectable session, writes `task.taskDescription = "ios.download.<taskID>"`, records `BackgroundTransferRecord` before `resume()`, and rejects non-HTTPS URLs or unsafe task IDs before creating work. `IOSMobileAppModel.startDownload(taskID:)` now tries the background starter first, leaves successful background starts in `.downloading` with `.backgroundTransfer` / `.resumable` policy and `.systemDeferred` limit, adds `.backgroundTransfer` capability, persists the task, and falls back to the foreground download engine only when the starter fails. `IOSMobileAppModel.live(storageDirectoryURL:credentialStore:)` wires app-owned storage, `BackgroundTransferRegistry`, `IOSBackgroundTransferEventHandler`, `IOSBackgroundURLSessionDownloadDelegate`, `IOSNoopBackgroundURLSessionCompletionConsumer`, and the starter. Verification before this plan update passed targeted background/live tests (16 tests, 0 failures), `MoongateiOSTests` (158 tests, 0 failures), and full Swift tests (300 tests, 0 failures). This proves source/model orchestration only; real `URLSession` relaunch, completion-handler drain, cancellation/resume-data, device background QA, and signed install remain open.
- 2026-06-13: Current light revalidation after the background-startup handoff passed `git diff --check`, `zsh -n Scripts/build-android-local.sh`, and production-source credential-pattern scans over `Sources`, Android main sources, `Scripts`, and `ios` with no real key/token/private-key shapes. `Scripts/build-android-local.sh` still safe-fails with exit 66 because no `android/gradlew` and no PATH `gradle` exist; no download, wrapper generation, dependency install, SDK install, or global tool install was attempted.
- 2026-06-13: Closed the current iOS Files-import, Photos-save, and background completion-handler source/test slice. Imported sidecar subtitles now copy through `IOSImportedFileAccessor` so Files-provider URLs can use security-scoped access during the copy. `IOSPhotoLibrarySaveHandler` resolves only app-owned artifacts, rejects unsafe/token-bearing references without echoing paths or secrets, maps permission/save failures to user-facing statuses, and `IOSSystemPhotoLibraryExporter` requests add-only Photos authorization before creating a video resource. `IOSLibraryView` now routes `.saveToPhotos` through that handler instead of stopping at a status string, and `ios/MoongateiOS/Info.plist` declares `NSPhotoLibraryAddUsageDescription` for saving exported videos. The live model now accepts an injected `IOSBackgroundURLSessionCompletionConsuming`, exposes its background URLSession delegate under `@testable`, and the native app host injects `IOSBackgroundURLSessionCompletionRegistry.shared`, so delegate finish events can drain the stored app-delegate completion handler instead of always using the noop consumer. Verification passed with the security-scoped import test, `IOSPhotoLibraryExporterTests` (3 tests, 0 failures), Photos package-boundary checks, `IOSBackgroundURLSessionDownloadDelegateTests` (4 tests, 0 failures), `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-ios-tests-after-photos-bg-fresh --filter MoongateiOSTests` (173 tests, 0 failures), and `git diff --check`. This is still not a ship claim: real Photos permission/save on a device, true background URLSession relaunch, system task cancellation, resume-data behavior, signed install, TestFlight, and real-device background QA remain unproven.
- 2026-06-13: Revalidated the current iOS Photos and background-completion work from a stable project-local scratch path. `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-full-after-photo-save-stable` passed 316 tests with 0 failures, after earlier stale/concurrent SwiftPM attempts had failed from file-mtime or scratch/cache state rather than stable source failures. Focused checks also passed for `IOSPhotoLibraryExporterTests`, the Photos Info.plist and RootView system-handler boundary checks, `IOSBackgroundURLSessionDownloadDelegateTests/testLiveModelWiresInjectedBackgroundCompletionConsumer`, and the `MoongateiOSTests` suite (172 tests, 0 failures). `git diff --check` and `zsh -n Scripts/build-android-local.sh` passed; `Scripts/build-android-local.sh` still safe-failed with exit 66 because no Gradle wrapper or PATH Gradle exists. `zsh Scripts/build-ios-xcode.sh simulator` and `zsh Scripts/build-ios-xcode.sh device` both passed after approved local Xcode/Swift/clang cache access, proving unsigned simulator/device SDK app-bundle builds only. Production-source credential scanning over `Sources`, Android main sources, `Scripts`, `ios`, `Package.swift`, and `README.md` had no hits; test-only sentinel strings were intentionally excluded from the production-source conclusion. No signing, install, dependency download, SDK install, wrapper generation, or system setting change was performed. Real Photos permission/save runtime, real background relaunch/resume/cancel, signed install/TestFlight, visual/a11y QA, and fixture/device matrix remain open.
- 2026-06-13: Closed the current iOS background-cancel and Files-export compile gate. `IOSBackgroundURLSessionDownloadStarter.cancelBackgroundDownload(taskID:)` cancels matching `URLSessionDownloadTask` instances by `taskDescription` without deleting the registry record itself, and `IOSMobileAppModel` cancels the system transfer before dropping recovery records on both cancel and remove actions. `IOSBackgroundURLSessionDownloadStarterTests` now uses a synchronous locked helper outside async bodies, avoiding the Swift 6 `NSLock` async-context warning. `IOSLibraryView` now passes an `IOSExportFile: Transferable` with `FileRepresentation` / `SentTransferredFile` to `.fileExporter`, so Save to Files compiles without wrapping large media into memory. Verification followed red/green for `PackageBoundaryTests/testIOSLibrarySaveToFilesDoesNotReadWholeArtifactIntoMemory`, then passed `IOSBackgroundURLSessionDownloadStarterTests` (4 tests, 0 failures), the cancel/remove background model tests, `IOSMobileAppModelTests` (76 tests, 0 failures), `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-ios-tests-after-cancel-photos-bg-final-2 --filter MoongateiOSTests` (179 tests, 0 failures), `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-android-boundary-final --filter AndroidDataBoundaryTests` (30 tests, 0 failures), and `git diff --check`. This still does not prove real device background relaunch/resume/cancel, real Photos save, signing, TestFlight, Android APK/Gradle, or visual/accessibility QA.
- 2026-06-13: Added relaunch-safe source restoration for vetted public direct HTTPS media URLs without putting raw source URLs into ordinary task JSON. `IOSSourceReferenceStore.isPersistableSourceURL` now accepts only exact `https` direct media paths with supported extensions, no user/password, no query, no fragment, and no token/signature/credential markers. `IOSMobileAppModel.restoreQueueFromRepository()` now restores safe source references into memory for active/retryable tasks, prunes terminal, orphan, and unsafe references, and removes the reference after a successful download. Missing non-restorable sources now use `MobileTaskError.sourceUnavailableAfterRelaunch` with a recovery-specific Queue message instead of collapsing into `unsupportedOnMobile`. Verification included the expected red failure for `FileTaskRepositoryTests/testSourceReferenceStorePersistsOnlySafeDirectHTTPSMediaSources` and `IOSMobileAppModelTests/testSafeDirectHTTPSQueuedSourceRestoresFromDedicatedSourceReferenceStore`, then green `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-ios-source-restore-green-3 --filter 'FileTaskRepositoryTests/testSourceReferenceStorePersistsOnlySafeDirectHTTPSMediaSources|IOSMobileAppModelTests/testSafeDirectHTTPSQueuedSourceRestoresFromDedicatedSourceReferenceStore|IOSQueueRecoveryPresenterTests/testPresenterExplainsMissingSourceAfterRelaunchWithoutCallingItUnsupported'` (3 tests, 0 failures), and `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-ios-appmodel-source-suite-2 --filter 'FileTaskRepositoryTests|IOSMobileAppModelTests|IOSQueueRecoveryPresenterTests|MobileModelsTests'` (115 tests, 0 failures). This is repository/model-level restoration only; it does not prove real `URLSession` background relaunch, resume-data behavior, physical-device background execution, signing, or TestFlight/App Store readiness.
- 2026-06-13: Revalidated the Files-export implementation with the stricter large-artifact boundary. `IOSExportFile: Transferable` now uses `FileRepresentation` plus `SentTransferredFile`, and `PackageBoundaryTests/testIOSLibrarySaveToFilesDoesNotReadWholeArtifactIntoMemory` asserts the RootView uses `.fileExporter(item: exportFile, ...)` without `Data(contentsOf: fileURL)` or `FileWrapper(regularFileWithContents:)`. Verification passed with `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-ios-save-files-transferable-target --filter PackageBoundaryTests/testIOSLibrarySaveToFilesDoesNotReadWholeArtifactIntoMemory` (1 test, 0 failures), `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-ios-tests-after-save-files-transferable --filter MoongateiOSTests` (179 tests, 0 failures), and full `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-full-after-ios-save-files-transferable` (322 tests, 0 failures). `git diff --check`, `zsh -n Scripts/build-android-local.sh`, a production-source credential scan over `Sources`, Android main sources, `Scripts`, `ios`, `Package.swift`, and `README.md`, and `zsh Scripts/build-ios-xcode.sh simulator` also passed; the Android helper still safe-failed with exit 66 because no wrapper/local Gradle exists. This is source/test and unsigned simulator-build evidence only, not real Files picker runtime proof with very large videos.
- 2026-06-13: Revalidated the Queue/Library empty-state actionability gate. `IOSQueueView` and `IOSLibraryView` use native `ContentUnavailableView` action slots with `.borderedProminent` buttons that route empty Queue to Add and empty Library to Queue. Added `PackageBoundaryTests/testIOSQueueAndLibraryEmptyStatesExposePrimaryRecoveryActions`, observed the expected RED failure before the dedicated empty-state views were present, then passed the targeted test and `MoongateiOSTests` (185 tests, 0 failures). This is source/unit verification of empty-state actionability only; visual layout, Dynamic Type screenshots, and VoiceOver runtime QA remain open.
- 2026-06-13: Tightened the iOS Queue recovery message for restored tasks without an available source URL. The mobile core now carries the non-user-fixable `sourceUnavailableAfterRelaunch` error bucket, `IOSMobileAppModel.startDownload(taskID:)` uses it when no source URL is available after restore, and `IOSQueueRecoveryPresenter` explains that the original link was not retained after relaunch for privacy instead of calling the task unsupported on mobile. Signed-source and legacy-source tests were updated to expect this bucket while continuing to assert that signed URLs, tokens, and legacy `source:<url>` values are scrubbed from JSON. Verification passed with targeted source-recovery tests, the full `MoongateiOSTests` suite (186 tests, 0 failures), and `git diff --check`. This is source/unit copy and error-classification proof only; real app relaunch UX, simulator/device visual QA, VoiceOver, and encrypted source-restoration design remain open.
- 2026-06-13: Revalidated continued-processing render identifier round-tripping after the handler tests exposed an ambiguous encoded-prefix contract. `IOSContinuedProcessingRenderScheduler` now uses `encoded-hex-<utf8-hex>` for unsafe task IDs, while `IOSContinuedProcessingTaskHandler` decodes only that exact prefix and treats raw IDs like `encoded-6162` as ordinary task IDs. Verification passed with `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-ios-handler-final --filter 'IOSContinuedProcessingTaskHandlerTests|IOSContinuedProcessingRenderSchedulerTests|PackageBoundaryTests/testIOSContinuedProcessingTaskHandlerKeepsPureSourceSeamAndGuardedAdapter'` (9 tests, 0 failures). This proves the source/unit identifier seam only; real `BGContinuedProcessingTask` launch, progress UI, expiration timing, render execution, signing, and device QA remain open.
- 2026-06-13: Confirmed the active Codex goal is already the full mobile-native delivery goal from the external plan, so no duplicate goal was created. Handoff verification after the continued-processing runner slice passed `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-android-boundary-after-cp-runner --filter AndroidDataBoundaryTests` (39 tests, 0 failures), `zsh -n Scripts/build-android-local.sh`, and `git diff --check`. `Scripts/build-android-local.sh` still safe-failed with exit 66 because no `android/gradlew` and no PATH `gradle` are available; no wrapper generation, dependency download, SDK install, global tool install, external network access, signing, or provisioning was attempted. `df -h .` reported about 6.3 GiB free, which is enough for light checks but still risky for repeated broad SwiftPM/Xcode scratch builds.
- 2026-06-13: Fixed a continued-processing render expiration race at the source/unit layer. `IOSContinuedProcessingRenderTaskRunner` now re-reads the persisted task after `RenderExporter.export` returns and before saving final success or failure. If the system expiration handler already persisted `needsForegroundToContinue` with `systemBackgroundLimit`, the runner returns that interrupted task and does not merge rendered artifacts or overwrite it as `completed`. RED verification first failed with `IOSContinuedProcessingRenderTaskRunnerTests/testCompletedRenderDoesNotOverwriteExpiredPersistedTask`; GREEN verification passed that test, the 17-test continued-processing targeted suite, and `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-ios-tests-after-cp-expiration --filter MoongateiOSTests` (200 tests, 0 failures). This still does not prove real BGTaskScheduler launch, device expiration timing, progress notification behavior, signing, or TestFlight readiness.
- 2026-06-13: Aligned iOS subtitle source path handling with `IOSArtifactStore`. `IOSMobileSubtitleProcessor` and `IOSMobileAppModel` now resolve source transcript identifiers through the same app-owned relative-path validator used by Library/render flows, so `Subtitles/source.en.srt` and case-normalized app-owned subdirectories work, while `source:...`, URLs, absolute paths, traversal, and secret-bearing identifiers are still rejected before file reads or translation requests. Verification included expected RED failures for `IOSMobileSubtitleProcessorTests/testReadsSourceSubtitleFromAppOwnedSubdirectoryIdentifier` and `testRejectsSourceReferenceIdentifierEvenWhenMatchingFileExists`, then green targeted processor tests, green AppModel path/security tests, and `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-ios-tests-after-subtitle-path --filter MoongateiOSTests` (206 tests, 0 failures). This is source/unit proof only; real Files-provider sidecar runtime, visual QA, signed install, and device background behavior remain open.
- 2026-06-13: Closed the current iOS API-key replace/delete UX and credential-cleanup slice. `IOSMobileAppModel.deleteAPIKey()` now provides an explicit destructive action, empty `saveAPIKeyDraft` routes through deletion, and cloud endpoint/engine scope changes schedule best-effort deletion of the previous credential reference instead of only clearing visible model state. Settings now uses user-facing copy for saved/unsaved key state, exposes save vs replace labels, and requires a confirmation dialog before deleting the API key; production Settings no longer exposes implementation wording such as Keychain, secure reference, ordinary settings, or queue records in the credential status area. Verification passed with the focused credential target (5 tests, 0 failures), `IOSMobileAppModelTests` (90 tests, 0 failures), `PackageBoundaryTests` (49 tests, 0 failures), and the full `MoongateiOSTests` suite (222 tests, 0 failures). `git diff --check` passed; `zsh -n Scripts/build-android-local.sh` passed; `Scripts/build-android-local.sh` still safe-failed with exit 66 because no `android/gradlew` and no PATH `gradle` exist. This remains source/unit and UI-contract coverage only; real provider connectivity, signed/device runtime, and Android APK validation remain open.
- 2026-06-13: Ran three read-only subagent reviews for the current iOS, Android, and mobile UX state. iOS review confirmed the native SwiftUI/service-layer skeleton is substantial but still No-ship without signing, device runtime, real background scheduling, and real Apple Intelligence/Translation execution evidence; it specifically flagged native-host/plist/project background identifiers that still assumed the local bundle id. Android review confirmed a real Compose/Material 3 multi-module skeleton with foreground direct HTTPS download, SAF import, Keystore credential storage, and JSON task persistence, but no APK/runtime proof because no Gradle wrapper or PATH Gradle exists; WorkManager/background, translation execution, subtitle processing, local model, and render remain incomplete. UX review confirmed both platforms use native component families but leak implementation language and have user-visible polish gaps; next UX slice should remove engineering terms from production UI and align the product name.
- 2026-06-13: Configured iOS background identifiers from the running/build bundle instead of hardcoding the local id through the native host path. `IOSMobileAppModel.live(...)` now accepts `bundleIdentifier` and uses it for background URLSession descriptors plus continued-processing render schedulers; `ios/MoongateiOS/MoongateiOSApp.swift` derives the continued-processing registration pattern from `Bundle.main.bundleIdentifier`; `Info.plist` permits `$(PRODUCT_BUNDLE_IDENTIFIER).render.*`; the Xcode target routes `PRODUCT_BUNDLE_IDENTIFIER` through `VDL_IOS_BUNDLE_IDENTIFIER`; and both local Xcode build/simulator smoke helpers pass that build setting. A small macOS compile-gate fix in `Sources/Moongate/ViewModel.swift` avoided Swift 6 pattern/let-shadowing failures encountered while compiling the package. Verification passed with `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-green-ios-bundle-identifiers --filter 'IOSBackgroundURLSessionDownloadDelegateTests/testLiveModelUsesInjectedBundleIdentifierForBackgroundDownloadSession|PackageBoundaryTests/testIOSBackgroundIdentifiersAreDerivedFromBundleConfiguration|PackageBoundaryTests/testIOSXcodeAppHostRegistersContinuedProcessingLaunchHandler|PackageBoundaryTests/testIOSSimulatorSmokeScriptInstallsAndLaunchesLocalAppBundleOnly|PackageBoundaryTests/testIOSXcodeBuildScriptUsesLocalProjectAndDocumentsRemainingGates'` (5 tests, 0 failures), `git diff --check`, `zsh -n Scripts/build-ios-xcode.sh`, `zsh -n Scripts/run-ios-simulator-smoke.sh`, and `zsh -n Scripts/build-android-local.sh`. `Scripts/build-android-local.sh` still safe-failed with exit 66: no `android/gradlew`, no PATH Gradle, and no dependency download or wrapper generation was attempted. This remains source/static proof only; it does not prove signed install, real BGTaskScheduler launch, real URLSession relaunch, or device QA.

- 2026-06-13: Tightened the Apple Translation readiness boundary after review. `IOSRuntimeReadinessEvaluator` now matches the mobile Apple execution adapter gates: Apple Translation requires `iOS/macOS 26`, high-fidelity requires `26.4`, and readiness requires an explicit source language instead of guessing from sample text. Added `PackageBoundaryTests/testIOSAppleTranslationReadinessCannotClaimReadyBelowExecutionRuntime` so future changes cannot report readiness below the execution runtime. Also documented the mobile no-ship state in `README.md` and kept desktop `MoongateCore` out of public library products while preserving the target for macOS/CLI/tests. Verification passed with the focused package-boundary run (`5 tests, 0 failures`), `git diff --check`, `zsh -n Scripts/build-android-local.sh`, and Android safe-fail exit 66. This is source/static proof only; it does not prove real Apple Translation execution, language package download UX, signed/device install, TestFlight, or physical-device background/runtime behavior.
- 2026-06-13: Closed the iOS background URLSession completion-timing blocker at the source/unit layer. `IOSBackgroundURLSessionDownloadDelegate` now uses `IOSBackgroundURLSessionPendingEventDrain` so `finishEvents(forSessionIdentifier:)` marks the session finished but defers consuming the captured app-delegate completion handler until pending `didFinishDownloadingTo` / `didCompleteWithError` file moves and recovery-outcome writes have finished. Added `enqueueFinishedDownload(...)` and `enqueueTaskFailure(...)` seams so the timing is unit-testable without a real background relaunch. RED verification first failed on the missing `enqueueFinishedDownload` API; GREEN verification passed the targeted regression, the affected 14-test background suite, `git diff --check`, Android script syntax, and the offline Android build gate safe-fail. This is still not device/background QA: real relaunch, lock-screen/network-loss, resume-data, app kill, signed install, and physical-device background execution remain open.
- 2026-06-13: Latest read-only iOS technical review found the current iOS implementation still No-ship. P0: the Xcode host has no signing team/entitlements/capabilities/iOS test action, so app install, Keychain, BackgroundTasks, and App Store/TestFlight readiness are not proven. P0: continued-processing registration/submission is only source-level; project capabilities and real system acceptance/expiration/progress behavior are unverified. P1: background URLSession recovery has unit glue but no real lifecycle proof for relaunch, progress, resume-data, HTTP status validation, auth challenge, lock screen, or app kill. P1: Keychain adapter lacks iOS-hosted roundtrip tests. P2: AVFoundation burn-in render still needs a broader device media matrix. No code was changed by the reviewer.
- 2026-06-13: Follow-up read-only iOS project review identified the smallest next source slice: create `ios/MoongateiOSAppTests/IOSKeychainCredentialStoreIntegrationTests.swift`, add a hosted XCTest target to `ios/MoongateiOSApp.xcodeproj`, and add shared-scheme `TestAction` for the app host. The test should use synthetic service/account names, clean up before/after, and verify save/has/read/delete/has-false through real `SecItem` APIs inside an iOS-hosted process. This can prove Xcode test-host wiring and simulator Keychain roundtrip, but not signing, provisioning, Keychain Sharing/access groups, physical-device behavior, BGTask acceptance, or TestFlight/App Store readiness.

## Final Validation Checklist

- [x] Unsigned local Xcode simulator app-bundle build passes with `zsh Scripts/build-ios-xcode.sh simulator` after local Xcode/SwiftPM cache/CoreSimulator sandbox escalation. This does not launch, install, sign, or create an ipa.
- [x] Unsigned local Xcode device SDK app-bundle build passes with `zsh Scripts/build-ios-xcode.sh device` after local Xcode/SwiftPM cache sandbox escalation. This does not prove physical-device installation or signing.
- [x] Local simulator launch-smoke helper exists and is covered by `PackageBoundaryTests/testIOSSimulatorSmokeScriptInstallsAndLaunchesLocalAppBundleOnly`.
- [x] Actual simulator install/launch smoke has one local success with `VDL_IOS_SIMULATOR_BOOT_IF_NEEDED=1 zsh Scripts/run-ios-simulator-smoke.sh`, which booted an existing simulator, installed the unsigned local bundle, launched `com.local.videodownloader.ios`, and terminated it. This is not signing, physical-device, TestFlight/App Store, UI automation, or background-runtime proof.
- [x] SwiftPM iOS host product builds on macOS. Latest: `swift build --product MoongateiOSApp --scratch-path /private/tmp/vdl-ios-host-build-latest`.
- [x] SwiftPM iOS host product builds on macOS after storage/download hardening. Latest: `swift build --product MoongateiOSApp --scratch-path /private/tmp/vdl-ios-host-build-latest-2`.
- [x] Existing macOS `Moongate` target still builds. Latest: `swift build --product Moongate --scratch-path /private/tmp/vdl-macos-build-5`.
- [x] Existing macOS `Moongate` target still builds after latest mobile storage/download changes. Latest: `swift build --product Moongate --scratch-path /private/tmp/vdl-macos-build-latest`.
- [x] Existing CLI target still builds after latest mobile storage/download changes. Latest: `swift build --product moongate-cli --scratch-path /private/tmp/moongate-cli-build-latest`.
- [x] `swift test --scratch-path /private/tmp/vdl-full-swift-test-4` passes after shared core changes (95 tests, 0 failures).
- [x] `swift test --scratch-path /private/tmp/vdl-current-full-swift-test-9` passes after the storage/download and package-boundary updates (113 tests, 0 failures).
- [x] `swift test --scratch-path /private/tmp/vdl-current-full-swift-test-10` passes after source-secrecy, HTTP-status, path-boundary, and subtitle-file updates (126 tests, 0 failures).
- [x] `swift test --scratch-path /private/tmp/vdl-ios-model-current-serial-3 --filter IOSMobileAppModelTests` passes after legacy source URL restore migration and queue persistence hardening (42 tests, 0 failures).
- [x] `swift test --scratch-path /private/tmp/vdl-review-blocker-targets --filter FileTaskRepositoryTests --filter TranslationSettingsTests --filter IOSMobileDownloadEngineTests --filter IOSMobileSubtitleProcessorTests` passes after final blocker-review fixes (43 tests, 0 failures).
- [x] `swift test --scratch-path /private/tmp/vdl-current-full-swift-test-12` passes after final blocker-review fixes (140 tests, 0 failures).
- [x] `swift test --scratch-path /private/tmp/vdl-current-full-swift-test-14` passes after handoff revalidation (140 tests, 0 failures).
- [x] `swift test --scratch-path /private/tmp/vdl-ios-library-presentation-tests-2 --filter MoongateiOSTests` passes after Library presentation command/store updates (82 tests, 0 failures).
- [x] `swift test --scratch-path /private/tmp/vdl-full-after-library-presentation` passes after Library presentation command/store updates (168 tests, 0 failures).
- [x] `swift test --scratch-path /private/tmp/vdl-library-security-targets-2 --filter 'IOSMobileAppModelTests/testChangingCloudTranslationEndpointOrEngineRequiresCredentialReconfirmation|PackageBoundaryTests/testIOSMobileTranslationTransportDefaultsToEphemeralNoCacheSession|IOSArtifactStoreTests|IOSLibraryActionPresenterTests|PackageBoundaryTests/testIOSLibraryUsesSystemPresentationInsteadOfStatusOnlyActions'` passes after Library/system-presentation and cloud-credential-scope hardening (7 tests, 0 failures).
- [x] `swift test --scratch-path /private/tmp/vdl-ios-tests-library-security --filter MoongateiOSTests` passes after the current iOS safety slice (82 tests, 0 failures).
- [x] `swift test --scratch-path /private/tmp/vdl-full-library-security` passes after the current iOS safety slice (168 tests, 0 failures).
- [x] `swift test --scratch-path /private/tmp/vdl-ios-render-planner-target --filter IOSRenderRequestPlannerTests` passes for render request planning policy (5 tests, 0 failures).
- [x] `swift test --scratch-path /private/tmp/vdl-final-render-planner-full` passes after render planner revalidation (178 tests, 0 failures).
- [x] `swift test --scratch-path /private/tmp/vdl-mobile-render-request-green --filter MobileModelsTests` passes after core render-request planner pre-work (25 tests, 0 failures).
- [x] `swift test --scratch-path /private/tmp/vdl-ios-render-planner-recheck --filter IOSRenderRequestPlannerTests` passes after iOS render policy planner pre-work (5 tests, 0 failures).
- [x] `swift test --scratch-path /private/tmp/vdl-ios-render-slice-ios-tests --filter MoongateiOSTests` passes after current render planning pre-work (87 tests, 0 failures).
- [x] `swift test --scratch-path /private/tmp/vdl-render-planner-full` passes after current render planning pre-work (178 tests, 0 failures).
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-android-settings-boundary-green-2 --filter PackageBoundaryTests/testAndroidSettingsKeepsAPIKeyDraftEphemeralAndSavesThroughKeystore` passes after Android settings boundary contract update (1 test, 0 failures).
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-android-data-boundary-after-test-contract-3 --filter AndroidDataBoundaryTests` passes after current Android boundary revalidation (10 tests, 0 failures).
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-render-planner-review-ios-tests-final-2 --filter MoongateiOSTests` passes after current post-handoff verification (96 tests, 0 failures).
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-render-planner-review-full-final` passes after current post-handoff verification (197 tests, 0 failures).
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-green-render-appmodel --filter IOSMobileAppModelTests/testExportingRenderedVideoUsesRenderExporterUpdatesQueueAndLibrary` passes after the iOS queue render action implementation (1 test, 0 failures).
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-render-boundary-green --filter PackageBoundaryTests/testIOSLiveModelWiresRenderExporterAndQueueRenderAction` passes after live render-exporter wiring (1 test, 0 failures).
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-ios-tests-render-action --filter MoongateiOSTests` passes after render action wiring (106 tests, 0 failures).
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-full-after-render-action` passes after render action wiring (208 tests, 0 failures).
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-ios-primary-queue-action-green --filter PackageBoundaryTests/testIOSQueueRowsExposePrimaryActionOutsideOverflowMenu` passes after Queue primary action exposure (1 test, 0 failures).
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-ios-primary-queue-ios-tests --filter MoongateiOSTests` passes after Queue primary action exposure (107 tests, 0 failures).
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-ios-primary-queue-full` passes after Queue primary action exposure (209 tests, 0 failures).
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-red-repeat-render-export --filter IOSMobileAppModelTests/testRepeatedRenderExportDoesNotOverwriteActiveExportCompletion` failed before the repeat-render guard (1 test, 7 expected failures).
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-green-repeat-render-export --filter IOSMobileAppModelTests/testRepeatedRenderExportDoesNotOverwriteActiveExportCompletion` passes after the repeat-render guard (1 test, 0 failures).
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-render-action-targets-after-repeat-fix --filter 'IOSMobileAppModelTests/testExportingRenderedVideoUsesRenderExporterUpdatesQueueAndLibrary|IOSMobileAppModelTests/testRepeatedRenderExportDoesNotOverwriteActiveExportCompletion|PackageBoundaryTests/testIOSLiveModelWiresRenderExporterAndQueueRenderAction|PackageBoundaryTests/testIOSQueueRowsExposePrimaryActionOutsideOverflowMenu'` passes after repeat-render fix (4 tests, 0 failures).
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-ios-tests-after-repeat-render-fix --filter MoongateiOSTests` passes after repeat-render fix (108 tests, 0 failures).
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-full-after-repeat-render-fix` passes after repeat-render fix (210 tests, 0 failures).
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-bg-recovery-targets --filter 'BackgroundTransferRegistryTests|IOSMobileAppModelTests/testRestoringQueueAppliesCompletedBackgroundTransferOutcomeBeforeForegroundFallback|IOSMobileAppModelTests/testRestoringQueueAppliesFailedAndExpiredBackgroundTransferOutcomesWithoutDroppingUnmatchedOutcomes'` passes after background recovery outcome wiring (6 tests, 0 failures).
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-bg-recovery-ios-tests --filter MoongateiOSTests` passes after background recovery outcome wiring (112 tests, 0 failures).
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-bg-recovery-full` passes after background recovery outcome wiring (217 tests, 0 failures).
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-ios-bg-handler-after-fix-serial --filter IOSBackgroundTransferEventHandlerTests` passes after background event handler completed/failed/expired outcome recording (2 tests, 0 failures).
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-mobile-models-after-bg-handler-serial --filter MobileModelsTests` passes after render action visibility was kept translated-subtitle-only for burned-in export (30 tests, 0 failures).
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-android-boundary-after-bg-handler-serial --filter AndroidDataBoundaryTests` passes after Android render/export domain parity and the iOS background handler compile fix (15 tests, 0 failures).
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-bg-event-repro --filter IOSBackgroundTransferEventHandlerTests` passes in the current checkout (2 tests, 0 failures).
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-bg-event-ios-tests --filter MoongateiOSTests` passes in the current checkout (120 tests, 0 failures).
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-bg-event-full-current` passes in the current checkout (232 tests, 0 failures).
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-green-ios-add-export-picker-2 --filter 'IOSMobileAppModelTests/testJoiningQueueUsesSelectedBurnedInExportProfileAndRenderCapability|PackageBoundaryTests/testIOSAddReadyStateExposesNativeExportPickerWithoutSoftSubtitleNoise'` passes after Add export-profile picker wiring (2 tests, 0 failures).
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-ios-tests-after-add-export-picker --filter MoongateiOSTests` passes after Add export-profile picker wiring (127 tests, 0 failures).
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-full-after-ios-add-export-picker` passes after Add export-profile picker wiring (240 tests, 0 failures).
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-source-reference-repro --filter 'IOSMobileAppModelTests/testPlainHTTPSQueuedSourceRestoresAfterRelaunchWithoutPersistingURLInTaskJSON|IOSMobileAppModelTests/testFailedSignedSourceURLDoesNotPersistSecretInTaskJSON|IOSMobileAppModelTests/testQueuedSignedSourceURLCanDownloadButIsNotPersistedInTaskJSON'` passes after source-reference revalidation (3 tests, 0 failures).
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-ios-tests-after-source-repro-2 --filter MoongateiOSTests` passes after the Swift 6 XCTest autoclosure fix (127 tests, 0 failures).
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-full-after-ios-source-fix` passes after the latest iOS source-reference revalidation (240 tests, 0 failures).
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-format-subtitle-green-2 --filter IOSMobileAppModelTests/testJoiningQueueUsesSelectedFormatAndSubtitleChoicesForDownloadRequest` passes after Add format/subtitle selection wiring.
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-android-boundary-after-add-url-scope --filter AndroidDataBoundaryTests` passes after scoping Add URL no-network/no-credential assertions to Add URL code paths (21 tests, 0 failures).
- [x] `swift test --jobs 1 --scratch-path /private/tmp/vdl-full-after-android-boundary-scope-final` passes after the latest Add URL boundary repair (252 tests, 0 failures).
- [x] `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-bg-handler-after-idempotency --filter IOSBackgroundTransferEventHandlerTests` passes after the completed-background-download replacement idempotency fix (3 tests, 0 failures).
- [x] `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-ios-tests-after-bg-idempotency --filter MoongateiOSTests` passes after the current background event-handler and Add-selection state revalidation (130 tests, 0 failures).
- [x] `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-ios-tests-after-cancel-photos-bg-final-2 --filter MoongateiOSTests` passes after background cancel and Files-export compile-gate fixes (179 tests, 0 failures).
- [x] `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-android-boundary-final --filter AndroidDataBoundaryTests` passes after the current iOS changes (30 tests, 0 failures).
- [x] Current `git diff --check` passes after background cancel and Files-export compile-gate fixes.
- [x] `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-ios-appmodel-source-suite-2 --filter 'FileTaskRepositoryTests|IOSMobileAppModelTests|IOSQueueRecoveryPresenterTests|MobileModelsTests'` passes after relaunch-safe source-reference restoration (115 tests, 0 failures).
- [x] `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-ios-save-files-transferable-target --filter PackageBoundaryTests/testIOSLibrarySaveToFilesDoesNotReadWholeArtifactIntoMemory` passes after the stricter Save to Files Transferable boundary (1 test, 0 failures).
- [x] `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-ios-tests-after-save-files-transferable --filter MoongateiOSTests` passes after the Save to Files Transferable implementation (179 tests, 0 failures).
- [x] `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-full-after-ios-save-files-transferable` passes after the Save to Files Transferable implementation (322 tests, 0 failures).
- [x] `zsh Scripts/build-ios-xcode.sh simulator` passes after local Xcode/CoreSimulator/cache escalation; this proves an unsigned simulator SDK app-bundle build only, not runtime launch, signing, device install, or TestFlight.
- [x] `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-ios-empty-state-green --filter PackageBoundaryTests/testIOSQueueAndLibraryEmptyStatesExposePrimaryRecoveryActions` passes after adding dedicated Queue/Library empty-state primary actions (1 test, 0 failures).
- [x] `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-ios-empty-state-ios-tests --filter MoongateiOSTests` passes after the Queue/Library empty-state UX gate (185 tests, 0 failures).
- [x] `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-ios-scheduler-after-loop --filter IOSContinuedProcessingRenderSchedulerTests` passes after stabilizing the continued-processing request descriptor scheduler source. The fix keeps the current descriptor-only contract and replaces a `CharacterSet`/chain-inference sanitizer with an explicit loop so SwiftPM reliably compiles the source under Swift 6.3. This remains scheduler descriptor coverage only, not BGTask runtime submission or device background QA.
- [x] Product build revalidation passes with `swift build --product MoongateiOSApp --scratch-path /private/tmp/vdl-ios-host-build-after-source-fix`, `swift build --product Moongate --scratch-path /private/tmp/vdl-macos-build-after-source-fix`, and `swift build --product moongate-cli --scratch-path /private/tmp/moongate-cli-build-after-source-fix` after local Swift/clang module-cache escalation.
- [x] `zsh Scripts/build-ios-xcode.sh all` passes after local Xcode/CoreSimulator/cache escalation; this proves unsigned simulator/device SDK app-bundle builds only, not launch, install, signing, or ipa export.
- [x] Current production-source credential-pattern scan over `Sources`, Android main sources, `Scripts`, and `ios` has no hits after the latest source-reference revalidation.
- [x] Current `git diff --check` passes after background event handler revalidation.
- [x] Current production-source credential-pattern scan over `Sources`, Android main sources, `Scripts`, and `ios` has no hits for checked key/token/private-key shapes.
- [x] Current Android Gradle availability recheck stayed blocked without downloads: `android/gradlew` is absent and PATH `gradle` is unavailable.
- [x] Product build revalidation passes with `swift build --product MoongateiOSApp --scratch-path /private/tmp/vdl-ios-host-library-security`, `swift build --product Moongate --scratch-path /private/tmp/vdl-macos-library-security`, and `swift build --product moongate-cli --scratch-path /private/tmp/moongate-cli-library-security`.
- [x] Product build revalidation passes with `swift build --product MoongateiOSApp --scratch-path /private/tmp/vdl-ios-app-final-render-planner`, `swift build --product Moongate --scratch-path /private/tmp/vdl-macos-final-render-planner`, and `swift build --product moongate-cli --scratch-path /private/tmp/moongate-cli-final-render-planner`.
- [x] Product build revalidation passes with `swift build --product MoongateiOSApp --scratch-path /private/tmp/vdl-ios-host-build-final-current-2`, `swift build --product Moongate --scratch-path /private/tmp/vdl-macos-build-final-current-2`, and `swift build --product moongate-cli --scratch-path /private/tmp/moongate-cli-build-final-current-2`.
- [x] Product build revalidation passes with `swift build --product MoongateiOSApp --scratch-path /private/tmp/vdl-ios-app-after-render-action`, `swift build --product Moongate --scratch-path /private/tmp/vdl-macos-after-render-action`, and `swift build --product moongate-cli --scratch-path /private/tmp/moongate-cli-after-render-action` after local Swift/clang module-cache escalation.
- [x] Product build revalidation passes with `swift build --product MoongateiOSApp --scratch-path /private/tmp/vdl-ios-app-after-repeat-render-fix`, `swift build --product Moongate --scratch-path /private/tmp/vdl-macos-after-repeat-render-fix`, and `swift build --product moongate-cli --scratch-path /private/tmp/moongate-cli-after-repeat-render-fix` after local Swift/clang module-cache escalation.
- [x] `swift build --product MoongateiOSApp --scratch-path /private/tmp/vdl-ios-app-after-add-export-picker` passes after Add export-profile picker wiring.
- [x] Targeted UI state tests cover live empty iOS app state and production-view mock-action absence.
- [x] Targeted Add tests cover the live unsupported parser path and injected parser success path without production mock fabrication.
- [x] Keychain/model tests prove no API key is persisted in ordinary mobile settings serialization and the Keychain adapter does not fall back to UserDefaults/files.
- [x] Redaction tests cover token/header/provider-error cases and reject plaintext HTTP credential endpoints.
- [x] iOS Settings credential UX boundary passes with `PackageBoundaryTests/testIOSSettingsExposesCredentialReplaceAndDeleteInUserLanguage`; the source contract requires save/replace labels, destructive delete confirmation, user-facing saved/unsaved copy, and no production credential-status copy leaking Keychain/reference/ordinary-settings/queue-record implementation terms.
- [x] iOS model credential cleanup passes with `IOSMobileAppModelTests/testChangingCloudTranslationScopeDeletesPreviousCredentialReference` and `IOSMobileAppModelTests/testDeletingAPIKeyUsesExplicitModelActionAndMarksConfigurationIncomplete`; changing cloud endpoint/engine deletes the previous credential reference best-effort, and explicit deletion marks translation configuration incomplete.
- [x] Full current iOS source/unit suite after the credential UX slice passes with `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-ios-suite-after-credential-delete --filter MoongateiOSTests` (222 tests, 0 failures).
- [x] iOS background identifier configuration boundary passes with `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-green-ios-bundle-identifiers --filter 'IOSBackgroundURLSessionDownloadDelegateTests/testLiveModelUsesInjectedBundleIdentifierForBackgroundDownloadSession|PackageBoundaryTests/testIOSBackgroundIdentifiersAreDerivedFromBundleConfiguration|PackageBoundaryTests/testIOSXcodeAppHostRegistersContinuedProcessingLaunchHandler|PackageBoundaryTests/testIOSSimulatorSmokeScriptInstallsAndLaunchesLocalAppBundleOnly|PackageBoundaryTests/testIOSXcodeBuildScriptUsesLocalProjectAndDocumentsRemainingGates'` (5 tests, 0 failures).
- [x] `git diff --check` passes after iOS queue render action wiring.
- [x] Narrow real-secret shape scan over `Sources`, Android main sources, `Scripts`, `ios`, and exec plans has no hits after iOS queue render action wiring.
- [x] Full current Swift verification passes after the Android Sharesheet and iOS scheduler compile-gate slice: `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-full-after-share-extractor-2` (270 tests, 0 failures). `git diff --check` passed, and a production-source credential-pattern scan over `Sources`, `Tests`, Android main sources, `ios`, `Scripts`, docs, `Package.swift`, and `README.md` found no hits for the checked key/token/private-key shapes.
- [ ] Android Gradle validation passes. Current blocker: `android/gradlew` is absent and `command -v gradle` returns no local Gradle.
- [x] Latest Android static boundary revalidation passes with `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-android-boundary-after-cp-runner --filter AndroidDataBoundaryTests` (39 tests, 0 failures).
- [x] Latest Android local build gate remains safe and offline: `zsh -n Scripts/build-android-local.sh` passes and `Scripts/build-android-local.sh` exits 66 when no existing Gradle is available.
- [x] Latest `git diff --check` passes after the continued-processing runner handoff verification.
- [x] Continued-processing runner expiration race regression passes with `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-ios-cp-runner-expiration-green-2 --filter IOSContinuedProcessingRenderTaskRunnerTests/testCompletedRenderDoesNotOverwriteExpiredPersistedTask`.
- [x] Continued-processing targeted suite passes with `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-ios-cp-runner-expiration-suite --filter 'IOSContinuedProcessingRenderTaskRunnerTests|IOSContinuedProcessingTaskCoordinatorTests|IOSContinuedProcessingTaskHandlerTests|IOSContinuedProcessingRenderSchedulerTests|PackageBoundaryTests/testIOSXcodeAppHostRegistersContinuedProcessingLaunchHandler|PackageBoundaryTests/testIOSContinuedProcessingTaskHandlerKeepsPureSourceSeamAndGuardedAdapter|PackageBoundaryTests/testIOSContinuedProcessingSchedulerIsGuardedBehindIOS26BackgroundTasksAPI'` (17 tests, 0 failures).
- [x] iOS source/unit suite passes after the expiration-race fix with `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-ios-tests-after-cp-expiration --filter MoongateiOSTests` (200 tests, 0 failures).
- [x] Final light gates after the expiration-race fix: `git diff --check`, `zsh -n Scripts/build-android-local.sh`, and `Scripts/build-android-local.sh` safe-fail exit 66 passed. Disk was about 1.2 GiB free afterward, so future broad SwiftPM/Xcode runs should start with approved scratch cleanup.
- [x] iOS background URLSession completion-timing regression passes with `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-ios-bg-urlsession-red --filter IOSBackgroundURLSessionDownloadDelegateTests/testBackgroundSessionCompletionWaitsForPendingFinishedDownloadOutcome` (1 test, 0 failures).
- [x] iOS background URLSession affected suite passes with `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-ios-bg-urlsession-red --filter 'IOSBackgroundURLSessionDownloadDelegateTests|IOSBackgroundURLSessionDownloadStarterTests|IOSBackgroundTransferEventHandlerTests|PackageBoundaryTests/testIOSBackgroundURLSessionDelegateUsesBackgroundNoCacheBoundary'` (14 tests, 0 failures).
- [x] Live iOS Add -> Download path can produce a transcript artifact from an imported local SRT sidecar without test-only fixture setup, making translated subtitle export and burned-in render reachable from that production foreground flow. Remote subtitle URL download remains open.
- [ ] iOS background download has real background `URLSession` device QA evidence. Source now has the live background start path, recovery/event-handler contracts, injected app-delegate completion consumer, and pending-event drain for completion timing, but no real relaunch/resume, resume-data, lock-screen/network-loss, app-kill, signed install, or physical-device proof.
- [ ] iOS native Xcode project has signing, entitlements/capabilities, and an iOS-hosted test scheme proving Keychain and background registration on a simulator/device target.
- [ ] Minimal next slice: add an iOS-hosted XCTest target and shared-scheme TestAction that runs a synthetic `IOSKeychainCredentialStore` save/read/delete roundtrip in the app host. This should precede entitlement/capability claims.
- [ ] Real-device background tests cover URLSession, BG continued processing expiration, app relaunch, network loss, and resume.
- [ ] Accessibility pass covers VoiceOver, Dynamic Type, dark mode, Reduce Motion, and touch targets.
