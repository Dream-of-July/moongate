# Android Native Architecture Implementation Plan

> **For Android workers:** implement this plan task-by-task. Keep Android work isolated from the existing macOS SwiftUI, Swift `MoongateCore`, and Windows WPF code. Do not modify Swift, Windows, iOS docs, or desktop build files unless a parent task explicitly expands scope.

**Status:** In progress / No-ship
**Date:** 2026-06-13
**Owner:** android_architect implementation slice
**Goal:** Define an executable Android-native architecture for the video downloader mobile product, matching iOS product behavior while using Android platform conventions.
**Architecture:** Build a new Android Gradle project beside the existing desktop/mobile shared planning work. Mirror the Swift `MobileModels.swift` concepts as Kotlin domain models and interfaces; do not bridge to or depend on the Swift runtime. Use Material 3 with Jetpack Compose, Kotlin coroutines, WorkManager, scoped storage, Android Keystore-backed credentials, and clearly bounded background execution.
**Tech Stack:** Gradle Kotlin DSL, Kotlin, Jetpack Compose, Material 3, AndroidX Lifecycle, Room or DataStore, WorkManager, Media3/ExoPlayer where preview is needed, Android Keystore, EncryptedSharedPreferences or encrypted DataStore, SAF/Document Picker, MediaStore, Android Sharesheet.

---

## Context

The current repository contains:

- macOS SwiftUI app code under `Sources/Moongate`.
- Shared Swift core code under `Sources/MoongateCore`.
- Windows C#/WPF code outside the Android scope.
- An Android Gradle Kotlin DSL skeleton under `android/` with `:core:domain` pure Kotlin models, service interfaces, unit tests, and a Compose `:app` mock shell. This checkout has no Gradle wrapper, so Android build/test validation is still unproven.
- A Swift mobile-core target, `Sources/MoongateMobileCore/`, that defines platform-neutral mobile concepts such as Add, Queue, Library, Settings surfaces, mobile task state, background policy, artifacts, translation configuration, and service protocols.

Android must mirror those mobile concepts in Kotlin because Android cannot depend on the Swift runtime. The Kotlin model names may stay close to the Swift names for product parity, but platform code should be idiomatic Kotlin and Android-first.

User requirements:

- Android follows Material Design, specifically Material 3.
- Android supports both local translation model download and cloud/API-key translation.
- Android supports background download and render work where the OS allows it.
- Android product behavior stays consistent with iOS at the product layer: Add, Queue, Library, Settings; same task states; same user-visible limitations; same artifact concepts.

## Goals

- Create an Android-native architecture that future workers can implement without touching macOS or Windows code.
- Keep product IA consistent with mobile shared concepts: Add, Queue, Library, Settings.
- Define Kotlin domain/service interfaces for parser, downloader, translation, subtitles, render/export, repository, and credential storage.
- Specify API key and local model paths with secure storage and readiness state.
- Specify background download/render limits honestly. Android can improve resilience, but cannot guarantee unlimited background execution.
- Define storage, sharing, and MediaStore behavior under scoped storage.
- Provide the first implementation tasks with file scope, validation commands, and explicit non-goals.

## Non-Goals

- Do not treat the current Android `:app` mock shell as a production app. It should remain explicit about unimplemented download, render, file import, API-key storage, and local-model execution until platform adapters are added and verified.
- Do not change Swift source, Swift tests, Package.swift, iOS docs, Windows files, or desktop behavior.
- Do not introduce shared Swift/Kotlin code generation in the first Android slice.
- Do not promise unrestricted background execution.
- Do not store API keys in plaintext preferences, logs, analytics, crash reports, or task records.
- Do not require global dependencies or system-level tooling changes.

## Android Product IA

### Top-Level Navigation

Use a Material 3 `NavigationBar` on compact screens and a `NavigationRail` on larger screens. The four destinations are:

- **Add:** Create a new download task from a pasted URL, clipboard URL, Android Sharesheet input, or imported file.
- **Queue:** Track active, waiting, paused, failed, and completed tasks that still need user action.
- **Library:** Browse completed artifacts and perform open, share, save, locate, or delete actions.
- **Settings:** Configure translation, model storage, download/render constraints, permissions, and diagnostics.

The destination names mirror Swift `MobileSurface` values: `add`, `queue`, `library`, `settings`.

### Material 3 Style

- Use Material 3 color roles and dynamic color when available.
- Use `Scaffold`, `TopAppBar`, `NavigationBar`, `NavigationRail`, `FloatingActionButton`, `SnackbarHost`, `ModalBottomSheet`, `AlertDialog`, `LinearProgressIndicator`, `AssistChip`, `FilterChip`, `ListItem`, and `Card` only for repeated item containers.
- Keep screen hierarchy utilitarian and task-focused. This is an operational download tool, not a marketing surface.
- Prefer native icons from Material Icons for actions such as add, paste, share, download, pause, retry, delete, folder, key, storage, and model.
- Support dark theme, dynamic type/font scale, TalkBack labels, and large touch targets.
- Avoid explanatory walls of text. Use clear labels, concise helper text, and actionable error copy.

### Add Screen

Primary controls:

- URL text field with paste affordance.
- Analyze primary button.
- Import file secondary action via Android document picker.
- Shared URL entry point from Android Sharesheet.
- Candidate list when multiple candidates are detected.
- Format picker and subtitle picker after analysis.
- Export profile selector: translated subtitle file, soft subtitle, burned-in subtitle, or no subtitles.
- Add to queue primary action once request is valid.

States:

- `idle`: Empty URL field, paste/import actions visible.
- `analyzing`: Disable inputs, show progress or indeterminate indicator.
- `candidateSelection`: Show supported and unsupported candidates with reasons.
- `ready`: Show title, duration, thumbnail if available, format/subtitle/export controls.
- `unsupported`: Show reason and limited next actions.
- `failed`: Show retry and editable input.

Mobile mappings:

- `MobileInputSource` -> Kotlin `MobileInputSource`.
- `MobileAddSessionState` -> Kotlin `MobileAddSessionState`.
- `MobileVideoCandidate`, `MobileVideoInfo`, `MobileFormatChoice`, `MobileSubtitleChoice` mirror Swift names.

### Queue Screen

Primary controls:

- Task list grouped by active, waiting, blocked, and done.
- Per-task progress, current phase, and background policy note when needed.
- Actions based on task state: pause, resume, cancel, retry, open app to continue, open result, share result, remove.
- Filter chips for all, active, failed, completed.

States:

- Empty: no queued tasks; primary action routes to Add.
- Active: show progress by phase: analyzing, downloading, translating, exporting.
- Waiting: show queued position if known.
- Needs foreground: show `Open app to continue` and explain system limit briefly.
- Failed: show user-fixable errors differently from non-fixable platform limits.
- Completed: keep visible until the user opens, shares, or removes it.

Mobile mappings:

- `MobileTaskSnapshot`, `MobileTaskState`, `MobileTaskProgress`, `MobileTaskAction`, `MobileBackgroundPolicy`, `MobileTaskError`.

### Library Screen

Primary controls:

- List/grid of completed `MobileLibraryItem` entries.
- Artifact detail bottom sheet with file type, size, created date, and actions.
- Search/filter by title and artifact type when the library grows.
- Empty state with route to Add.

Actions:

- Open with in-app preview or Android intent.
- Share through Android Sharesheet.
- Save to user-selected document location through SAF.
- Save video to Photos/Videos through MediaStore.
- Locate missing file through document picker when possible.
- Delete app record and optionally app-owned files after confirmation.

States:

- `available`: all relevant actions enabled.
- `fileMissing`: offer locate file and delete record.
- `permissionDenied`: offer save/copy flow or permission repair.
- `deleting`: disable actions and show progress.

Mobile mappings:

- `MobileLibraryItem`, `MobileLibraryState`, `MobileLibraryAction`, `MobileTaskArtifact`.

### Settings Screen

Sections:

- Translation: provider selection, API-key status, local model status, target language defaults.
- Local models: downloadable model list, readiness, download/delete actions, storage use.
- Download and rendering: Wi-Fi-only toggle, require charging for render toggle, maximum render height, storage threshold.
- Storage: app-owned download location, export behavior, cache cleanup.
- Permissions: notification permission, storage/document access explanations, battery optimization prompt only when user action is appropriate.
- Diagnostics: app version, worker state, last failure category, no secrets.

Controls:

- Use switches for binary constraints.
- Use segmented controls/dropdowns for provider and export defaults.
- Use buttons for model download/delete and API key update/remove.
- Use inline status chips: ready, missing key, model downloading, model unavailable, blocked by storage, blocked by network, blocked by battery.

## Android Project Organization

Create Android files under a new top-level `android/` directory so desktop platforms remain untouched.

Recommended structure:

```text
android/
  settings.gradle.kts
  build.gradle.kts
  gradle/libs.versions.toml
  app/
    build.gradle.kts
    src/main/AndroidManifest.xml
    src/main/java/com/videodownloader/app/MoongateApplication.kt
    src/main/java/com/videodownloader/app/MainActivity.kt
    src/test/java/com/videodownloader/app/
    src/androidTest/java/com/videodownloader/app/
  core/domain/
    build.gradle.kts
    src/main/java/com/videodownloader/core/domain/model/
    src/main/java/com/videodownloader/core/domain/service/
    src/test/java/com/videodownloader/core/domain/
  core/data/
    build.gradle.kts
    src/main/java/com/videodownloader/core/data/repository/
    src/main/java/com/videodownloader/core/data/credentials/
    src/main/java/com/videodownloader/core/data/storage/
    src/test/java/com/videodownloader/core/data/
  core/worker/
    build.gradle.kts
    src/main/java/com/videodownloader/core/worker/
    src/test/java/com/videodownloader/core/worker/
  feature/add/
    build.gradle.kts
    src/main/java/com/videodownloader/feature/add/
  feature/queue/
    build.gradle.kts
    src/main/java/com/videodownloader/feature/queue/
  feature/library/
    build.gradle.kts
    src/main/java/com/videodownloader/feature/library/
  feature/settings/
    build.gradle.kts
    src/main/java/com/videodownloader/feature/settings/
  testing/
    build.gradle.kts
    src/main/java/com/videodownloader/testing/
```

Module responsibilities:

- `:app`: Activity, navigation graph, app theme, dependency wiring.
- `:core:domain`: Pure Kotlin models, errors, service interfaces, no Android dependencies unless unavoidable.
- `:core:data`: Room/DataStore repositories, credential store, storage adapters, provider implementations.
- `:core:worker`: WorkManager workers, foreground notification coordination, task orchestration.
- `:feature:add`: Add screen UI state, Compose UI, Add view model.
- `:feature:queue`: Queue screen UI state, Compose UI, Queue view model.
- `:feature:library`: Library screen UI state, Compose UI, Library view model.
- `:feature:settings`: Settings screen UI state, Compose UI, Settings view model.
- `:testing`: fake repositories, fake workers, fake translation providers, Compose test helpers.

Coexistence rules:

- Do not modify root `Package.swift` for Android work.
- Do not move Swift or Windows files.
- Android Gradle files live under `android/`; root-level CI integration requires a separate parent-approved task.
- Kotlin domain models mirror Swift mobile models by concept, not by binary dependency.
- If a future worker adds generated model synchronization, it must be optional and must not make Android builds require Swift tooling.

## Kotlin Domain and Service Architecture

Place pure model types in `android/core/domain/src/main/java/com/videodownloader/core/domain/model/`.

Recommended Kotlin style:

- Use `data class` for value types.
- Use `enum class` for finite state.
- Use `sealed interface` only when states need attached data; otherwise prefer enums to stay close to Swift `Codable` enums.
- Use `kotlinx.coroutines.flow.Flow` for observable task streams.
- Use `suspend` functions for async service calls.
- Use stable `String` IDs. Do not expose Android `Uri` directly from pure domain models; wrap app-owned storage references as strings and translate at the storage adapter boundary.

Core service interfaces should start in `android/core/domain/src/main/java/com/videodownloader/core/domain/service/MobileServices.kt` or split into one file per interface if the file grows.

```kotlin
package com.videodownloader.core.domain.service

import com.videodownloader.core.domain.model.MobileAddSessionSnapshot
import com.videodownloader.core.domain.model.MobileDownloadRequest
import com.videodownloader.core.domain.model.MobileInputSource
import com.videodownloader.core.domain.model.MobileRenderRequest
import com.videodownloader.core.domain.model.MobileSubtitleProcessingRequest
import com.videodownloader.core.domain.model.MobileTaskProgress
import com.videodownloader.core.domain.model.MobileTaskResult
import com.videodownloader.core.domain.model.MobileTaskSnapshot
import com.videodownloader.core.domain.model.MobileTranslationRequest
import com.videodownloader.core.domain.model.MobileTranslationResult
import com.videodownloader.core.domain.model.MobileVideoCandidate
import com.videodownloader.core.domain.model.MobileVideoInfo
import com.videodownloader.core.domain.model.SecureCredentialReference
import com.videodownloader.core.domain.model.TranslationContext
import com.videodownloader.core.domain.model.TranslationReadiness
import kotlinx.coroutines.flow.Flow

interface Parser {
    suspend fun resolveCandidates(input: MobileInputSource): List<MobileVideoCandidate>
    suspend fun analyze(candidate: MobileVideoCandidate): MobileVideoInfo
}

interface DownloadEngine {
    suspend fun download(
        request: MobileDownloadRequest,
        onProgress: suspend (MobileTaskProgress) -> Unit
    ): MobileTaskResult
}

interface TranslationProvider {
    suspend fun readiness(context: TranslationContext): TranslationReadiness
    suspend fun translate(request: MobileTranslationRequest): MobileTranslationResult
}

interface SubtitleProcessor {
    suspend fun process(
        request: MobileSubtitleProcessingRequest,
        onProgress: suspend (MobileTaskProgress) -> Unit
    ): com.videodownloader.core.domain.model.MobileTaskArtifact
}

interface RenderExporter {
    suspend fun export(
        request: MobileRenderRequest,
        onProgress: suspend (MobileTaskProgress) -> Unit
    ): MobileTaskResult
}

interface TaskRepository {
    fun observeTasks(): Flow<List<MobileTaskSnapshot>>
    suspend fun loadTasks(): List<MobileTaskSnapshot>
    suspend fun saveTask(snapshot: MobileTaskSnapshot)
    suspend fun removeTask(id: String)
}

interface SecureCredentialStore {
    suspend fun saveCredential(
        secret: String,
        reference: SecureCredentialReference
    ): SecureCredentialReference

    suspend fun deleteCredential(reference: SecureCredentialReference)
    suspend fun hasCredential(reference: SecureCredentialReference): Boolean
}
```

Service boundaries:

- `Parser`: URL/import analysis only. It should classify unsupported inputs with user-visible reasons rather than throwing generic failures.
- `DownloadEngine`: network/media download and resumable file transfer. It should emit progress and return artifact references, not raw file handles.
- `TranslationProvider`: local model and cloud/API providers share one interface. Provider selection happens outside callers.
- `SubtitleProcessor`: parse, align, translate, and export subtitle artifacts.
- `RenderExporter`: produces rendered video or soft subtitle artifacts. Rendering should be cancellable and checkpointed when possible.
- `TaskRepository`: source of truth for queue snapshots and terminal task records.
- `SecureCredentialStore`: stores only credential material. Domain records store only `SecureCredentialReference`.

## API Key and Local Model Paths

### API Key Path

Use Android Keystore-backed encryption:

- Store API keys through `SecureCredentialStore`.
- Use Android Keystore for key material.
- Use `EncryptedSharedPreferences` or encrypted DataStore for encrypted secret values.
- Store only a `SecureCredentialReference` in task/config records.
- Never log API keys, bearer headers, decrypted model tokens, or provider responses that may echo secrets.
- Settings should show credential status as present/missing and an optional user-provided display name, not the key value.
- Removing a provider credential must delete the encrypted secret and mark affected translation configuration as not ready.

Settings states:

- No key: provider selectable but translation readiness is blocked with `credentialRequired`.
- Key saved: provider readiness can be checked.
- Key invalid: show provider-specific failure without showing response bodies containing sensitive data.
- Key removed: queued translation work should pause or fail with a user-fixable credential error.

### Local Model Path

Local translation models are a first-class provider path:

- Track model catalog metadata: model ID, language pair, version, byte size, checksum if available, license/source display name, installed path reference, readiness.
- Download models only from approved provider endpoints in a later implementation task. This architecture document does not authorize network access.
- Store model files in app-owned storage unless the user explicitly exports them.
- Delete model files through Settings and update readiness atomically.
- Verify downloaded model size/checksum before marking ready.
- Make readiness query cheap and deterministic: no hidden network call in `readiness()`.

Model readiness states should include:

- `ready`
- `notDownloaded`
- `downloading(progress)`
- `blockedByNetwork`
- `blockedByBattery`
- `blockedByStorage`
- `corruptOrVersionMismatch`
- `providerUnavailable`

Constraints:

- Respect Wi-Fi-only setting for model downloads when enabled.
- Allow download only when storage threshold is satisfied.
- Defer large model downloads when battery saver is active or charging is required by user settings.
- Provide delete action even when model is corrupt.
- Do not start model downloads silently from a task unless the user opted into automatic model downloads.

## Background Download and Rendering

Android background execution is system-bounded. The app can use the right APIs to improve reliability, but it must not promise infinite background downloading or rendering.

Recommended architecture:

- Use WorkManager for durable, deferrable task orchestration.
- Use expedited work only for truly user-initiated short work and only within quota.
- Use a Foreground Service through WorkManager foreground support for user-visible long-running downloads/renders.
- Use Android 14 user-initiated data transfer job APIs only when the implementation targets and validates the applicable API level and behavior.
- Show notifications for active foreground work with cancel action.
- Persist checkpoints so interrupted work can resume or fail cleanly.
- Map system interruptions to `MobileBackgroundPolicy` and `MobileTaskState.needsForegroundToContinue` where user action is required.

Use boundaries:

- Download work: WorkManager + foreground notification when active and long-running; resume partial files where the source supports range requests or segment manifests.
- Render work: WorkManager + foreground notification; require charging or unmetered constraints if user settings demand them; checkpoint outputs when encoder pipeline supports it.
- Translation work: WorkManager for batched subtitles; foreground only when long-running and user-visible.
- Parser analysis: usually foreground or short WorkManager work; do not run arbitrary web extraction forever in background.

Constraints:

- WorkManager can be delayed by Doze, app standby buckets, battery saver, quota, network constraints, and OEM behavior.
- Foreground services require user-visible notifications and are subject to Android version-specific service type restrictions.
- The app cannot guarantee work continues after force stop, severe resource pressure, revoked notification permission, lost network, or OEM task killing.
- When background limits block work, the UI must show a recoverable state instead of pretending progress is still active.

Notifications:

- Active work notification shows title, phase, progress when known, and cancel.
- Completed notification opens Library item.
- Failed notification opens task detail with retry or repair action.
- Notification text must not include secrets, full private URLs when avoidable, or provider response bodies.

## Files, Storage, and Sharing

Use Android scoped storage by default.

App-owned storage:

- Temporary downloads, partial segments, subtitle intermediates, render scratch files, and model files stay in app-owned directories.
- Clean orphaned partial files with a cautious cleanup job that only touches app-owned Android files.
- Store artifact metadata in Room or DataStore, but keep file bytes in the file system.

User-selected storage:

- Use Storage Access Framework document picker for importing source files and exporting artifacts to user-selected locations.
- Persist URI permissions only when necessary and only for user-selected documents/trees.
- Store durable URI references carefully; handle permission revocation as `permissionDenied`.

MediaStore:

- Save rendered videos or original media to `MediaStore.Video` when the user chooses `saveToPhotos` / gallery-visible save.
- Use pending rows during write and mark complete only after success.
- Save subtitle files through SAF unless a future product decision defines a media collection behavior for text tracks.

Sharing:

- Use Android Sharesheet (`ACTION_SEND` / `ACTION_SEND_MULTIPLE`) with `content://` URIs from a `FileProvider` or SAF/MediaStore URI.
- Grant temporary read permissions for shared artifacts.
- Prefer sharing final artifacts, not app-private partial files.

Opening:

- For video preview, use Media3/ExoPlayer in-app where useful.
- For unsupported artifact types, use external intent with a chooser.
- Handle no-app-available as a user-visible error.

## Testing Plan

### Unit Tests

Run in Android project once created:

```bash
cd android
./gradlew :core:domain:testDebugUnitTest
./gradlew :core:data:testDebugUnitTest
./gradlew :core:worker:testDebugUnitTest
```

Coverage:

- Domain state mapping: available actions for task and library states.
- Background policy mapping: interrupted/deferred/foreground-required states.
- Credential store contract with fake encrypted backend.
- Model readiness transitions.
- Repository save/load/remove behavior.
- Parser unsupported reason mapping.
- Subtitle and render request validation.

### Compose UI State Tests

Run:

```bash
cd android
./gradlew :feature:add:testDebugUnitTest
./gradlew :feature:queue:testDebugUnitTest
./gradlew :feature:library:testDebugUnitTest
./gradlew :feature:settings:testDebugUnitTest
```

Coverage:

- Add screen states: idle, analyzing, candidate selection, ready, unsupported, failed.
- Queue action visibility by task state.
- Library action visibility by artifact and file state.
- Settings provider states for missing key, key saved, model ready, model downloading, model blocked.

### Instrumentation Tests

Run on emulator or device:

```bash
cd android
./gradlew connectedDebugAndroidTest
```

Coverage:

- Navigation between Add, Queue, Library, Settings.
- Document picker result handling with fake content URI.
- Sharesheet incoming URL intent.
- Notification permission flow where applicable.
- Encrypted credential presence check without printing secrets.

### Real-Device Background Tests

Run manually on at least one recent physical Android device:

- Start a large download, lock screen, verify foreground notification progress.
- Start render, background the app, verify notification and cancellation.
- Enable battery saver, verify constrained work becomes deferred or needs foreground.
- Switch from Wi-Fi to cellular with Wi-Fi-only enabled, verify pause/defer state.
- Reboot during a queued task, verify task repository restores a safe state.
- Force stop app, verify the product does not claim guaranteed continuation.
- Revoke notification permission, verify user-visible repair state.

### Accessibility and Visual QA

Manual QA:

- TalkBack can announce destination tabs, task rows, progress, and action buttons.
- Dark theme and dynamic color have sufficient contrast.
- Font scale 1.3x and 2.0x do not truncate primary actions.
- Landscape and tablet widths use `NavigationRail` or adaptive layout.
- Error states are actionable and do not expose sensitive URLs, keys, or logs.

## First Implementation Tasks

Each task is intentionally scoped for one Android worker. Do not broaden scope inside a task.

### Task 1: Scaffold Isolated Android Gradle Project

Files:

- Create: `android/settings.gradle.kts`
- Create: `android/build.gradle.kts`
- Create: `android/gradle/libs.versions.toml`
- Create: `android/app/build.gradle.kts`
- Create: `android/app/src/main/AndroidManifest.xml`
- Create: `android/app/src/main/java/com/videodownloader/app/MainActivity.kt`
- Create: `android/app/src/main/java/com/videodownloader/app/MoongateApplication.kt`

Validation command:

```bash
cd android
./gradlew :app:assembleDebug
```

Expected result:

- Android debug APK builds.
- Existing Swift and Windows files are unchanged.

Do not:

- Modify root `Package.swift`.
- Move existing files.
- Add CI or root build integration.
- Install global Gradle or Android tools.
- Add networking, downloader, parser, or translation implementation.

### Task 2: Add Kotlin Domain Models and Service Interfaces

Files:

- Create: `android/core/domain/build.gradle.kts`
- Create: `android/core/domain/src/main/java/com/videodownloader/core/domain/model/MobileModels.kt`
- Create: `android/core/domain/src/main/java/com/videodownloader/core/domain/service/MobileServices.kt`
- Create: `android/core/domain/src/test/java/com/videodownloader/core/domain/MobileModelsTest.kt`

Validation command:

```bash
cd android
./gradlew :core:domain:testDebugUnitTest
```

Expected result:

- Kotlin models compile without Android UI dependencies.
- Tests verify task available actions, library actions, export profile render requirement, and background policy limitations.

Do not:

- Depend on Swift `MoongateCore`.
- Add Android UI types to pure domain models.
- Store credentials in model classes.
- Implement real network or file downloads.

### Task 3: Build Material 3 App Shell and Navigation

Files:

- Modify: `android/app/build.gradle.kts`
- Modify: `android/app/src/main/java/com/videodownloader/app/MainActivity.kt`
- Create: `android/app/src/main/java/com/videodownloader/app/ui/AppNavigation.kt`
- Create: `android/app/src/main/java/com/videodownloader/app/ui/AppTheme.kt`
- Create: `android/feature/add/build.gradle.kts`
- Create: `android/feature/add/src/main/java/com/videodownloader/feature/add/AddScreen.kt`
- Create: `android/feature/queue/build.gradle.kts`
- Create: `android/feature/queue/src/main/java/com/videodownloader/feature/queue/QueueScreen.kt`
- Create: `android/feature/library/build.gradle.kts`
- Create: `android/feature/library/src/main/java/com/videodownloader/feature/library/LibraryScreen.kt`
- Create: `android/feature/settings/build.gradle.kts`
- Create: `android/feature/settings/src/main/java/com/videodownloader/feature/settings/SettingsScreen.kt`

Validation command:

```bash
cd android
./gradlew :app:assembleDebug
```

Expected result:

- App launches into Add.
- Bottom navigation or navigation rail exposes Add, Queue, Library, Settings.
- Screens are placeholder-functional with Material 3 structure and no dead buttons that claim unsupported behavior.

Do not:

- Implement download, render, or translation flows.
- Add decorative landing pages.
- Add marketing copy.
- Read clipboard automatically without user action.

### Task 4: Add Queue Repository and Worker Orchestration Skeleton

Files:

- Create: `android/core/data/build.gradle.kts`
- Create: `android/core/data/src/main/java/com/videodownloader/core/data/repository/TaskRepositoryImpl.kt`
- Create: `android/core/data/src/test/java/com/videodownloader/core/data/repository/TaskRepositoryImplTest.kt`
- Create: `android/core/worker/build.gradle.kts`
- Create: `android/core/worker/src/main/java/com/videodownloader/core/worker/MobileTaskWorker.kt`
- Create: `android/core/worker/src/main/java/com/videodownloader/core/worker/MobileTaskScheduler.kt`
- Create: `android/core/worker/src/test/java/com/videodownloader/core/worker/MobileTaskSchedulerTest.kt`

Validation command:

```bash
cd android
./gradlew :core:data:testDebugUnitTest :core:worker:testDebugUnitTest
```

Expected result:

- Tasks can be saved, observed, updated, and removed through fake/local storage.
- Scheduler maps task requests into WorkManager work specs with constraints.
- Worker skeleton returns explicit unsupported/not-implemented states until real services exist.

Do not:

- Claim unlimited background execution.
- Start real network work.
- Write outside app-owned test directories.
- Delete arbitrary files.

### Task 5: Add Secure Credential Store and Translation Settings State

Files:

- Create: `android/core/data/src/main/java/com/videodownloader/core/data/credentials/AndroidSecureCredentialStore.kt`
- Create: `android/core/data/src/test/java/com/videodownloader/core/data/credentials/AndroidSecureCredentialStoreTest.kt`
- Modify: `android/feature/settings/src/main/java/com/videodownloader/feature/settings/SettingsScreen.kt`
- Create: `android/feature/settings/src/main/java/com/videodownloader/feature/settings/TranslationSettingsState.kt`
- Create: `android/feature/settings/src/test/java/com/videodownloader/feature/settings/TranslationSettingsStateTest.kt`

Validation command:

```bash
cd android
./gradlew :core:data:testDebugUnitTest :feature:settings:testDebugUnitTest
```

Expected result:

- API key flow stores only encrypted secret material.
- UI state shows present/missing/invalid without exposing key value.
- Removing a credential updates readiness.

Do not:

- Log API keys.
- Save API keys in Room task records or plaintext DataStore.
- Add real provider calls.
- Print decrypted credentials in tests.

### Task 6: Add Local Model Manager State

Files:

- Create: `android/core/data/src/main/java/com/videodownloader/core/data/model/LocalModelManager.kt`
- Create: `android/core/data/src/main/java/com/videodownloader/core/data/model/LocalModelCatalog.kt`
- Create: `android/core/data/src/test/java/com/videodownloader/core/data/model/LocalModelManagerTest.kt`
- Modify: `android/feature/settings/src/main/java/com/videodownloader/feature/settings/SettingsScreen.kt`
- Create: `android/feature/settings/src/test/java/com/videodownloader/feature/settings/LocalModelSettingsStateTest.kt`

Validation command:

```bash
cd android
./gradlew :core:data:testDebugUnitTest :feature:settings:testDebugUnitTest
```

Expected result:

- Model readiness supports not downloaded, downloading, ready, blocked, corrupt, and delete states.
- Wi-Fi, battery, and storage constraints are represented before real download starts.

Do not:

- Download model files in this task.
- Contact external model registries.
- Store models outside app-owned storage.
- Hide corrupt model state.

### Task 7: Add Storage, SAF, MediaStore, and Sharing Adapters

Files:

- Create: `android/core/data/src/main/java/com/videodownloader/core/data/storage/ArtifactStorage.kt`
- Create: `android/core/data/src/main/java/com/videodownloader/core/data/storage/AndroidArtifactStorage.kt`
- Create: `android/core/data/src/test/java/com/videodownloader/core/data/storage/ArtifactStorageTest.kt`
- Modify: `android/feature/library/src/main/java/com/videodownloader/feature/library/LibraryScreen.kt`
- Create: `android/feature/library/src/test/java/com/videodownloader/feature/library/LibraryActionStateTest.kt`

Validation command:

```bash
cd android
./gradlew :core:data:testDebugUnitTest :feature:library:testDebugUnitTest
```

Expected result:

- Artifact actions distinguish app-owned file, SAF export, MediaStore save, and Sharesheet share.
- Permission denied and file missing states are represented.

Do not:

- Request broad external storage permissions.
- Write directly to arbitrary filesystem paths.
- Share app-private file paths.
- Delete user-selected files without explicit confirmation.

### Task 8: Add Real-Device Background QA Checklist to Android Docs

Files:

- Create: `android/docs/background-qa.md`

Validation command:

```bash
cd android
./gradlew :app:assembleDebug
```

Expected result:

- Documented manual QA cases cover lock screen, Doze/battery saver, Wi-Fi-only, notification permission, reboot, and force stop.
- The app build still passes.

Do not:

- Add claims that tests cannot verify.
- Change production code in this documentation-only task.
- Use external services or credentials.

## Risk Register

- **Android background limits:** WorkManager and foreground services improve reliability but do not guarantee uninterrupted work. Mitigation: user-visible states, resumable checkpoints, notification repair path.
- **Parser parity:** Desktop extraction may rely on tools unavailable on Android. Mitigation: classify unsupported inputs explicitly and avoid promising desktop parity for every source.
- **Render performance:** Burned-in subtitle rendering can be slow and battery-intensive. Mitigation: max render height, charging constraints, foreground notification, cancel/resume where possible.
- **Credential handling:** Cloud translation requires secrets. Mitigation: Keystore-backed encrypted storage, reference-only domain records, no secret logging.
- **Model storage size:** Local models can be large. Mitigation: readiness state, storage checks, explicit download/delete, app-owned storage cleanup.
- **Scoped storage complexity:** SAF/MediaStore URI permissions can be revoked. Mitigation: represent `permissionDenied` and `fileMissing` as normal library states.
- **Redirect safety:** Foreground and background direct downloads must not silently follow redirects from a vetted direct media URL to a credential-bearing, query/fragment, userinfo, or non-media URL. Mitigation: disable `HttpURLConnection` automatic redirects and validate the final connection URL before reading response bytes.
- **Direct-link credential leakage:** Add URL staging must not accept credential-bearing media URLs such as `https://user:pass@...` or signed query/fragment links. Mitigation: parse with `java.net.URI` before staging, reject missing host, query, fragment, and URI userinfo, and keep unsupported webpage handling separate from credential rejection.

## Rollback Strategy

- Android work is isolated under `android/`; rollback can remove Android-only changes without touching macOS or Windows.
- Keep each implementation task independently reviewable and commit-sized.
- If a task requires touching existing Swift, Windows, root build, or CI files, stop and ask the parent agent to expand scope.

## Progress Log

- 2026-06-13: Android `:app` now defaults to `AndroidAppState.live()` so first launch is empty rather than sample/mock data. `AndroidAppState.sample()` remains for Compose preview and tests. User-facing live copy avoids internal prototype wording, while Gradle build/test validation remains blocked because this checkout has no `android/gradlew` and no local `gradle` command.
- 2026-06-13: Current verification rechecked Android tooling and did not run Gradle: `test -x android/gradlew` returned `no-wrapper`, and `command -v gradle` returned no path. No dependency download or wrapper generation was attempted under the enterprise-managed computer rules.
- 2026-06-13: Rechecked Android tooling during mobile verification closure. `test -x android/gradlew && echo has-wrapper || echo no-wrapper` returned `no-wrapper`; `command -v gradle || true` returned no path. Android Gradle build/tests remain blocked, and no wrapper generation or dependency download was attempted.
- 2026-06-13: Rechecked Android tooling after the iOS storage/download hardening pass. `test -x android/gradlew && echo has-wrapper || echo no-wrapper` still returned `no-wrapper`, and `command -v gradle || true` returned no path. Android Gradle build/tests remain unrun; no wrapper generation, dependency download, or external network access was attempted.
- 2026-06-13: Tightened the Android Material shell state contract after read-only architecture and UX subagent review. `AndroidAppState.live()` now exposes domain-level `AndroidActionState` for Add URL parsing, file import, API-key save, local-model download, and background capability statuses. `MainActivity` renders those action states via disabled Material buttons and status chips instead of click-local unsupported copy; Queue and Library empty states now include a real CTA that routes back to Add. Added Swift-side static boundary coverage because Android Gradle remains unavailable. Verification passed with `swift test --scratch-path /private/tmp/vdl-android-shell-state-test-2 --filter AndroidDataBoundaryTests` (5 tests, 0 failures), and a targeted scan of `MainActivity.kt`, `AndroidAppModels.kt`, and `AndroidDataBoundaryTests.swift` showed no production `MainActivity` hits for the removed dead-end copy patterns `当前版本暂不支持`, `mock 产物`, or `此版本暂不支持保存密钥`.
- 2026-06-13: Closed the latest Android data-boundary review item without adding network or Gradle downloads. `JsonTaskRepository` now sanitizes every legacy `storageIdentifier.startsWith("source:")` artifact to `mobile-source:<task-id>` before JSON persistence, instead of limiting cleanup to metadata artifacts. `JsonTaskRepositoryTest.kt` now covers original-media, transcript, and metadata artifacts carrying a signed URL, and `AndroidDataBoundaryTests` statically rejects reintroducing an `artifact.kind == MobileArtifactKind.METADATA` sanitizer gate. Verification passed with `swift test --scratch-path /private/tmp/vdl-android-boundary-source-sanitize --filter AndroidDataBoundaryTests/testAndroidTaskRepositorySanitizesLegacySourceURLArtifactsBeforePersistence` (1 test, 0 failures) and full `swift test --scratch-path /private/tmp/vdl-full-library-security` (168 tests, 0 failures). Android Gradle unit tests remain unrun because `android/gradlew` is absent and no local `gradle` command is available.
- 2026-06-13: Added Android render/export domain parity without Gradle, network, or platform adapters. `MobileTaskAction` now includes `exportTranslatedSubtitle` and `exportRenderedVideo`; completed tasks expose subtitle export only when a transcript exists without a translated subtitle, and expose rendered-video export only for burned-in profiles with render capability, original media, translated subtitle, and no existing rendered video. Added pure-domain `MobileRenderRequestPlanner.kt` with `notRequired`, `ready`, and structured blocked reasons (`taskNotCompleted`, `unsupportedExportProfile`, `missingSourceMedia`, `missingSubtitle`). The planner intentionally rejects `SOFT_SUBTITLE` as a burned-in input until a conversion path exists. Added Kotlin source tests as future Gradle-test coverage and Swift static boundary tests to enforce the source contract. Verification: red `swift test --jobs 1 --scratch-path /private/tmp/vdl-red-android-render-domain-boundary --filter AndroidDataBoundaryTests` failed before implementation; green `swift test --jobs 1 --scratch-path /private/tmp/vdl-green-android-render-domain-boundary --filter AndroidDataBoundaryTests` passed (15 tests, 0 failures), and `swift test --jobs 1 --scratch-path /private/tmp/vdl-android-boundary-after-bg-handler-serial --filter AndroidDataBoundaryTests` passed after the iOS background-handler compile fix (15 tests, 0 failures). Android Gradle/APK/runtime validation is still blocked by missing `android/gradlew` and missing local `gradle`.
- 2026-06-13: Added the first Add URL -> Queue staging slice without network, credentials, or platform downloader work. `AndroidAddUrlPlanner.stageDirectUrl(input:)` trims direct `http`/`https` inputs, rejects unsupported schemes with an Add-screen error, and stages a `QUEUED` `AndroidDownloadItem` that explicitly says it is waiting for the download service and has not parsed or downloaded. `MoongateApp` owns the `AndroidAppState` mutation, while `MoongateShell` only calls `onDirectUrlStaged` and navigates to Queue, keeping Compose state scope clear. Verification passed with `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-green-android-add-url-planner --filter 'AndroidDataBoundaryTests/testAndroidAddUrlPlannerStagesDirectHTTPURLWithoutNetworkOrCredentials|AndroidDataBoundaryTests/testAndroidAddUrlButtonAppendsQueueItemAndNavigatesToQueue|AndroidDataBoundaryTests/testAndroidSliceDoesNotDependOnGeneratedGradleWrapper'` (3 tests, 0 failures) and `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-android-boundary-after-add-url --filter AndroidDataBoundaryTests` (21 tests, 0 failures). Android Gradle/APK/runtime validation remains blocked by missing `android/gradlew` and missing local `gradle`; no wrapper generation, dependency download, network request, or credential access was attempted.
- 2026-06-13: Read-only Android and UX reviews confirmed the app is still No-ship and identified the highest-value near-term UX blocker: Queue and Library actions were rendered as status chips instead of actual controls. This slice converted Queue/Library primary actions to `PrimaryActionButton`, secondary actions to `OutlinedButton`, and wired enabled local state actions so queued items can be removed from the in-memory queue and Library records can be deleted from the in-memory library. Unsupported start/open/share/download actions remain disabled rather than pretending platform adapters exist. It also repaired the Kotlin `AndroidAppStateTest` source contract so the current Add ready-flow test matches the live Add URL staging behavior. Verification included the expected red failures for `AndroidDataBoundaryTests/testAndroidKotlinDomainTestsMatchLiveAddUrlStagingContract` and `AndroidDataBoundaryTests/testAndroidQueueAndLibraryRenderActionsAsButtonsNotStatusPills`, then green `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-green-android-kotlin-test-contract --filter AndroidDataBoundaryTests/testAndroidKotlinDomainTestsMatchLiveAddUrlStagingContract` (1 test, 0 failures), `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-green-android-action-buttons --filter AndroidDataBoundaryTests/testAndroidQueueAndLibraryRenderActionsAsButtonsNotStatusPills` (1 test, 0 failures), and `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-android-boundary-after-action-buttons --filter AndroidDataBoundaryTests` (24 tests, 0 failures). Android Gradle/APK/runtime validation remains blocked by missing `android/gradlew` and missing local `gradle`.
- 2026-06-13: Improved Android Sharesheet URL staging while keeping the implementation source/static only. Added `AndroidSharedText.kt` with `String.firstSharedHttpUrl()` to extract the first surrounding `http`/`https` URL from shared text and reject unsupported schemes. `MainActivity.sharedHttpUrl()` now uses that extractor instead of requiring the entire shared text to be only a URL; it still filters to `ACTION_SEND` + `text/plain`, does not persist raw text, and does not touch network, WorkManager, credentials, logs, or preferences. Added Kotlin source tests for the future Gradle suite and Swift static boundary coverage. Verification passed with `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-android-share-extractor-green-2 --filter AndroidDataBoundaryTests/testAndroidSharesheetExtractsFirstHTTPURLFromSharedText` (1 test, 0 failures), `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-android-boundary-after-share --filter AndroidDataBoundaryTests` (26 tests, 0 failures), and full `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-full-after-share-extractor-2` (270 tests, 0 failures). `git diff --check` and a production-source credential-pattern scan had no hits. Android Gradle/APK/runtime validation remains blocked by missing `android/gradlew` and missing local `gradle`; no wrapper generation, dependency download, network request, or credential access was attempted.
- 2026-06-13: Added Android Library typed artifact actions and SAF/system-intent source wiring without claiming runtime APK readiness. `AndroidActionState` now carries `AndroidLibraryAction` for open, share, save-copy, and delete-record actions, so Library behavior no longer depends on matching Chinese button labels. `MainActivity` now preserves the imported document `contentUri`, routes enabled Library actions through `handleLibraryAction`, opens verified files with `ACTION_VIEW`, shares via `ACTION_SEND` chooser, and starts a `CreateDocument("*/*")` save-copy flow that copies bytes through `ContentResolver` streams. Delete remains an in-memory record removal. Verification included a red failure for `AndroidDataBoundaryTests/testAndroidLibraryScreenConnectsVerifiedFilesToSystemIntents`, then green `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-green-android-library-intents-2 --filter AndroidDataBoundaryTests/testAndroidLibraryScreenConnectsVerifiedFilesToSystemIntents` (1 test, 0 failures), `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-abli4 --filter AndroidDataBoundaryTests` (29 tests, 0 failures), and `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-ios-after-android-library-intents --filter MoongateiOSTests` (139 tests, 0 failures). A full Android Gradle build/test, APK install, Compose runtime, and real SAF/intent QA remain blocked by missing `android/gradlew` and missing local `gradle`; no wrapper generation, dependency download, network request, or credential access was attempted.
- 2026-06-13: Added a narrow Android foreground direct-HTTPS download slice without adding WorkManager, foreground services, notifications, new Gradle dependencies, or credential/network setup beyond the app's runtime `INTERNET` permission. `AndroidDownloadItem` now keeps `sourceUrlForDownload` as a `@Transient` in-memory field so queued direct-media tasks can expose an enabled foreground `开始` action without serializing the raw source URL into task JSON. `MainActivity` wires Queue primary action to `AndroidForegroundDirectDownloader`, which rejects blank, non-HTTPS, query, and fragment URLs, runs blocking IO under `Dispatchers.IO`, uses `HttpURLConnection` with `GET`, writes only under `File(context.filesDir, "downloads")`, and records a completed queue item plus Library row via `withDownloadedFile`. Queue copy now says foreground download; background download/render remains a separate unimplemented slice. Verification included the expected red failure for `AndroidDataBoundaryTests/testAndroidDirectHTTPSDownloadUsesAppOwnedForegroundAdapter`, then green `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-android-direct-download-final-target --filter AndroidDataBoundaryTests/testAndroidDirectHTTPSDownloadUsesAppOwnedForegroundAdapter` (1 test, 0 failures), `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-android-direct-download-final-suite --filter AndroidDataBoundaryTests` (30 tests, 0 failures), `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-ios-after-android-direct-download --filter MoongateiOSTests` (143 tests, 0 failures), and `git diff --check` (0 findings). The first full Android boundary run hit `/private/tmp` `No space left on device`; only `/private/tmp/vdl-*` SwiftPM scratch directories were deleted after approval, restoring `/private/tmp` to 9.7GiB free before rerunning. Android Gradle/APK/runtime validation remains blocked by missing `android/gradlew` and missing local `gradle`; no wrapper generation, dependency download, APK install, emulator/device run, or real external URL download QA was attempted.
- 2026-06-13: Closed the Android app-owned file sharing/open gap found in read-only review while keeping the app No-ship. `AndroidForegroundDirectDownloader` now returns FileProvider `content://` storage URIs for app-owned downloads, and Library open/share/save-copy all route through `Context.exportableLibraryUri(item)` instead of handing raw `file://` or arbitrary strings to external intents. The helper accepts existing `content://` SAF/FileProvider URIs, converts only canonical legacy files whose `Path` starts inside `filesDir/downloads` to `${packageName}.files`, rejects other `file://` paths, and adds `ClipData.newUri(...)` plus read grants for open/share intent propagation. Verification included an expected red failure for `AndroidDataBoundaryTests/testAndroidLibraryScreenConnectsVerifiedFilesToSystemIntents` (9 failures before implementation), a second red failure after tightening the boundary test around Kotlin `File` path checking (1 failure), then green `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-green-android-library-uri-target --filter AndroidDataBoundaryTests/testAndroidLibraryScreenConnectsVerifiedFilesToSystemIntents` (1 test, 0 failures), `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-green-android-direct-download-target --filter AndroidDataBoundaryTests/testAndroidDirectHTTPSDownloadUsesAppOwnedForegroundAdapter` (1 test, 0 failures), and `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-android-boundary-after-fileprovider-retry --filter AndroidDataBoundaryTests` (30 tests, 0 failures). One earlier full-suite run with a different scratch path failed with SwiftPM `/private/tmp` build database/output-file-map I/O errors during concurrent verification; the serial rerun passed. Android Gradle/APK/runtime validation remains blocked by missing `android/gradlew` and missing local `gradle`; no wrapper generation, dependency download, APK install, emulator/device run, or real intent-grant/file-open QA was attempted.
- 2026-06-13: Added the first `:core:worker` WorkManager orchestration skeleton without claiming background runtime readiness. The Android settings file now declares `:core:worker`, the version catalog declares `androidx.work:work-runtime-ktx`, and `AndroidBackgroundWorkScheduler` can describe/enqueue a constrained `OneTimeWorkRequest` for a task ID. `AndroidDownloadWorker` deliberately returns `UnsupportedNotImplemented` / `Result.failure()` and performs no network, rendering, credential access, file deletion, or unlimited-background claim. A future Gradle unit-test source file documents the descriptor contract, but it has not been executed because Gradle is unavailable. Verification included an expected red failure for `AndroidDataBoundaryTests/testAndroidWorkerModuleDeclaresBoundedWorkManagerSkeletonWithoutNetworkImplementation` after tightening the boundary, green `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-worker-contract-green --filter AndroidDataBoundaryTests/testAndroidWorkerModuleDeclaresBoundedWorkManagerSkeletonWithoutNetworkImplementation` (1 test, 0 failures), `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-worker-android-boundary --filter AndroidDataBoundaryTests` (31 tests, 0 failures), `test -x android/gradlew && echo has-wrapper || echo no-wrapper` returning `no-wrapper`, and `command -v gradle || true` returning no path. No dependency download, wrapper generation, APK build, emulator/device run, or real background work QA was attempted.
- 2026-06-13: Tightened foreground direct-download cancellation in the Android Compose shell. `MoongateShell` now keeps a per-task `downloadJobs` map, cancels an existing foreground download job before starting a duplicate for the same queue item, removes the job on success/failure, treats `CancellationException` as cancellation rather than a network failure snackbar, and cancels the running job before removing a queue item. Verification followed TDD: `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-android-cancel-red --filter AndroidDataBoundaryTests/testAndroidRemovingActiveForegroundDownloadCancelsRunningCoroutine` failed first with the expected missing Job/cancel assertions, then `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-android-cancel-green --filter AndroidDataBoundaryTests/testAndroidRemovingActiveForegroundDownloadCancelsRunningCoroutine` passed (1 test, 0 failures), and `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-android-boundary-after-cancel --filter AndroidDataBoundaryTests` passed (33 tests, 0 failures). `git diff --check` and `zsh -n Scripts/build-android-local.sh` passed; `Scripts/build-android-local.sh` still safe-failed with exit 66 because no Gradle wrapper or PATH Gradle exists. This is source/static-boundary proof only; Android APK/runtime cancellation, partial-file behavior under coroutine cancellation, notification cancellation, WorkManager cancellation, and real-device QA remain open.
- 2026-06-13: Added and revalidated Android foreground direct-download byte-progress plumbing at the source/static-boundary layer. The foreground downloader exposes copied-byte and optional total-byte progress back to the Compose shell, and queue state derives a bounded in-progress percentage or byte-count label without marking the task complete early. Verification passed with `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-android-boundary-final --filter AndroidDataBoundaryTests` (36 tests, 0 failures), `zsh -n Scripts/build-android-local.sh`, `git diff --check`, and `Scripts/build-android-local.sh` safe-failing with exit 66 because no `android/gradlew` and no PATH `gradle` exist. No wrapper generation, dependency download, SDK install, APK build, emulator/device run, or real external URL download QA was attempted.
- 2026-06-13: Closed the Android app-owned Library file-delete and destructive-action confirmation source/static slice while keeping Android No-ship. App-owned completed downloads with `android-owned:` storage now surface `DELETE_FILE`, imported/content records keep `DELETE_RECORD`, and `deleteAppOwnedLibraryFile` deletes only canonical files under `filesDir/downloads` before removing the record. Queue and Library destructive actions stage an `AlertDialog`, then confirm through undo-capable snackbar helpers; confirmed Queue deletion cancels any active foreground download job. Verification passed with the red/green file-delete tests, `AndroidDataBoundaryTests/testAndroidRemovingActiveForegroundDownloadCancelsRunningCoroutine`, `AndroidDataBoundaryTests/testAndroidDestructiveQueueAndLibraryActionsRequireConfirmationAndOfferUndo`, and `swift test --jobs 1 --disable-index-store --scratch-path /private/tmp/vdl-android-boundary-final-subtitle-path --filter AndroidDataBoundaryTests` (42 tests, 0 failures). `zsh -n Scripts/build-android-local.sh` and `git diff --check` passed; `Scripts/build-android-local.sh` still safe-failed with exit 66 because no Gradle wrapper or PATH Gradle exists. No wrapper generation, dependency download, APK install, emulator/device run, or real FileProvider/delete/undo runtime QA was attempted.
- 2026-06-13: Closed the follow-up Android direct-download lifecycle review blockers at the source/static boundary. Active foreground-download rows now expose an enabled `取消` primary action that stages the same destructive confirmation path; undoing that cancellation restores the task as queued rather than a zombie downloading row. Foreground download completion now records `android-owned:<filename>` in app state and task snapshots, so same-session Library rows expose `DELETE_FILE`; FileProvider `content://` URIs are created only at open/share/save boundaries. Library delete undo now restores both the Library row and corresponding completed Queue projection so persistence can be re-saved. Verification followed TDD: `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-android-lifecycle-red --filter AndroidDataBoundaryTests/testAndroidDirectDownloadLifecycleActionsRemainReachableAndRestorable` failed first with 13 expected failures, then `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-android-lifecycle-green-target-2 --filter AndroidDataBoundaryTests/testAndroidDirectDownloadLifecycleActionsRemainReachableAndRestorable` passed (1 test, 0 failures), and `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-android-lifecycle-boundary-2 --filter AndroidDataBoundaryTests` passed (43 tests, 0 failures). `git diff --check` and `zsh -n Scripts/build-android-local.sh` passed; `Scripts/build-android-local.sh` safe-failed exit 66 because no `android/gradlew` and no PATH `gradle` exist. No wrapper generation, dependency download, APK install, emulator/device run, or real Android runtime QA was attempted.
- 2026-06-13: Added Android Add-screen local subtitle import and export-mode selection at the source/static boundary. `MainActivity` now has a separate subtitle document picker using text/subtitle MIME types instead of reusing the video picker, and imported subtitles update the current Add ready-state as sanitized manual subtitle choices without serializing raw `content://` URIs or token-bearing values. `AndroidAddReadyState` now carries `AndroidAddExportMode` for user-facing `字幕文件` and `带字幕视频` choices, maps those choices into `MobileExportProfile`, and queues preserve the selected `exportProfile` for later subtitle/render workers. The UI intentionally does not expose soft-subtitle wording until there is an Android conversion/runtime path. Verification followed TDD: `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-android-subtitle-import-red-3 --filter AndroidDataBoundaryTests/testAndroidAddScreenImportsLocalSubtitlesAndPreservesExportMode` failed first with 23 expected missing-contract failures; a follow-up sync guard failed with `.build/vdl-android-subtitle-import-sync-red`; then `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-android-subtitle-import-green-target-2 --skip MoongateiOSTests --filter AndroidDataBoundaryTests/testAndroidAddScreenImportsLocalSubtitlesAndPreservesExportMode` passed (1 test, 0 failures), and `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-android-subtitle-import-boundary-3 --skip MoongateiOSTests --filter AndroidDataBoundaryTests` passed (45 tests, 0 failures). `git diff --check` and `zsh -n Scripts/build-android-local.sh` passed; `Scripts/build-android-local.sh` safe-failed exit 66 because no `android/gradlew` and no PATH `gradle` exist. A non-skipped Swift test attempt is currently blocked by an unrelated existing `Tests/MoongateiOSTests/IOSMobileAppModelTests.swift` compile error around `renderExporter` argument ordering; Kotlin/Gradle tests, APK install, Compose runtime, real document picker behavior, subtitle parsing, translation, and render/export execution remain unverified.
- 2026-06-13: Closed the follow-up Android queue export no-ship review findings at the source/static boundary. `MoongateShell` no longer mutates the owning `currentAppState` directly for completed queue subtitle/render export actions; the owning `MoongateApp` now injects `onTranslatedSubtitleExportRequested` and `onRenderExportRequested` callbacks and persists the queue item after state mutation, and the Compose preview callsite now supplies those callbacks too. Completed queue secondary actions no longer expose a reachable but handlerless `分享` button; share remains a typed Library action where file intent handling exists. `AndroidDownloadItem.taskSnapshot()` now sanitizes restored/imported artifact storage identifiers before persistence, preserving only safe `android-owned:`, `android-import:`, and hex `android-content:` payloads and downgrading token-bearing or URL-like values to a hash-based `android-sanitized:<opaque>` value that does not include the raw task id. A quality-review pass found and then this slice fixed a missing preview callback pair, one Kotlin trailing-comma syntax blocker, and the unsafe raw-task-id sanitizer fallback. Added Kotlin test source for the no-op share and sensitive-storage cases, plus Swift boundary tests that guard the callback scope, preview callsite, and sanitizer contract. Verification passed with targeted `swift test --scratch-path /private/tmp/vdl-android-queue-fix --filter AndroidDataBoundaryTests/testAndroidCompletedQueueExportActionsAreTypedAndReachable` (1 test, 0 failures), targeted `swift test --scratch-path /private/tmp/vdl-android-queue-fix --filter AndroidDataBoundaryTests/testAndroidDirectHTTPSDownloadUsesAppOwnedForegroundAdapter` (1 test, 0 failures), and full `swift test --scratch-path /private/tmp/vdl-android-queue-fix` (413 tests, 0 failures). `Scripts/build-android-local.sh` still safe-failed with exit 66 because no `android/gradlew` and no PATH `gradle` exist; no wrapper generation, dependency download, SDK install, global tool install, APK build, emulator/device run, or real export runtime QA was attempted.
- 2026-06-13: Addressed Android Add-screen hierarchy feedback at the source/static boundary. `AddScreen` now renders the local video import card before the direct-link card; live `AndroidAppState` copy uses `导入视频` / `选择视频文件`, and direct-link copy uses `直链` with explicit HTTPS direct media file limitations. Future Kotlin `AndroidAppStateTest` source was updated to match this contract. The same verification pass also updated Android worker boundary tests to the current architecture: WorkManager input still carries only opaque `work_handle`, and `AndroidBackgroundDownloadHandoffStore` may persist strictly validated queryless HTTPS direct-media handoff data, not arbitrary source URLs or credentials. Verification passed with full Swift/source coverage (`swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-full-after-add-priority`, 419 tests, 0 failures), Android source-boundary coverage (`swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-android-boundary-after-add-priority --filter AndroidDataBoundaryTests`, 52 tests, 0 failures), and package-boundary coverage (`swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-full-after-add-priority --filter PackageBoundaryTests`, 59 tests, 0 failures). `zsh -n Scripts/build-android-local.sh`, `Scripts/build-android-local.sh` safe-fail exit 66, `git diff --check`, and a credential-pattern scan also passed. Android Gradle/APK/runtime validation remains blocked by missing `android/gradlew` and missing PATH `gradle`; no wrapper generation, dependency download, APK install, emulator/device run, or real document-picker/direct-link QA was attempted.

- 2026-06-13: Revalidated the Android no-ship build boundary after README/package updates. `README.md` now explicitly states that Android is a no-ship WIP surface, that `Scripts/build-android-local.sh` only uses an existing `android/gradlew` or PATH `Gradle`, and that missing Gradle means a safe exit rather than any wrapper download or install. Verification passed with `zsh -n Scripts/build-android-local.sh` and `Scripts/build-android-local.sh` returning exit 66 with the message that no wrapper/local Gradle exists. The focused Swift package-boundary run also passed and keeps the README no-ship text under test. Android Gradle/APK/runtime, Compose runtime, notification permission flow, real WorkManager worker body, progress/result persistence, cancellation/retry, TalkBack/font-scale QA, and device QA remain open.
- 2026-06-13: Revalidated the current worker-body source/static boundary after handoff. `AndroidDownloadWorker` still starts foreground notification first, resolves runtime through `AndroidDownloadWorkerRuntimeRegistry.runtime(applicationContext)`, runs only the opaque WorkManager `work_handle`, maps runtime completion/block/failure to bounded WorkManager results, and keeps construction of the no-backup handoff store, app-owned JSON task repository, and app-owned direct HTTPS downloader in the registry rather than the worker file. The live coordinator still defaults `notificationFlowAvailable=false` and `downloadWorkerRuntimeAvailable=false`, so the production path remains gated off. Verification passed with `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-android-worker-runtime-red --filter AndroidDataBoundaryTests/testAndroidWorkerModuleDeclaresBoundedWorkManagerSkeletonWithoutNetworkImplementation`, `git diff --check`, and `zsh -n Scripts/build-android-local.sh`; `Scripts/build-android-local.sh` safe-failed exit 66 because no `android/gradlew` and no PATH `gradle` are available. No wrapper download, dependency install, SDK install, global tool install, APK build, emulator/device run, credential inspection, or external network access was attempted.
- 2026-06-13: Collected four read-only review agents before the next slice. Android technical review kept Android no-ship because there is still no Gradle/APK/runtime proof, live background gates remain off, foreground direct download still needs redirect hardening, and translation/render/local-model execution remains placeholder-level. UX review identified the highest-value immediate blocker: live Settings exposed unavailable local translation as a disabled primary action with implementation copy. Verification review confirmed Android build results cannot be inferred from the safe exit-66 gate. iOS review found no P0 but flagged URLSession background completion timing as a future P1. No agents edited files, installed dependencies, or used network.
- 2026-06-13: Closed the Android live Settings local-translation UX blocker at the source/static boundary. `AndroidLocalTranslationModel.mockDefault()` was replaced on the live default path with `unavailableDefault()`, using user-facing `本机翻译` copy and the message `本机翻译当前不可用。可先使用云端 API 翻译。`. `SettingsScreen` now renders local translation as a status row with `当前不可用` instead of disabled `下载模型` / delete primary buttons, while keeping the pure `AndroidLocalModelPlanner` state machine and future Kotlin tests for eventual download/delete support. RED verification first failed on `AndroidDataBoundaryTests/testAndroidLiveSettingsShowsUnavailableLocalTranslationAsStatusNotDeadControls`; GREEN verification then passed. Full Android source/static boundary verification passed once during the slice with `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-android-settings-red --filter AndroidDataBoundaryTests` (54 tests, 0 failures). After a final status-label wording tweak, the targeted Settings test passed again with `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-android-settings-status-green --filter AndroidDataBoundaryTests/testAndroidLiveSettingsShowsUnavailableLocalTranslationAsStatusNotDeadControls`. `git diff --check`, `zsh -n Scripts/build-android-local.sh`, and `Scripts/build-android-local.sh` safe-fail exit 66 passed. No wrapper download, dependency install, SDK install, global tool install, APK build, emulator/device run, or external network access was attempted. Disk ended around 1.5 GiB free, so broader reruns should wait for approved scratch cleanup.
- 2026-06-13: Closed the Android foreground direct-download redirect-safety P1 at the source/static boundary. `AndroidForegroundDirectDownloader` now sets `connection.instanceFollowRedirects = false` and checks `connection.url` with `isSafeForegroundDirectMediaUrl()` before reading bytes, so a server response cannot silently redirect an initially queryless HTTPS direct media URL to a credential-bearing, query/fragment, userinfo, non-HTTPS, or non-media final URL. RED verification first failed with four missing redirect/final-URL assertions in `AndroidDataBoundaryTests/testAndroidDirectHTTPSDownloadUsesAppOwnedForegroundAdapter`; GREEN verification passed that targeted test and full `AndroidDataBoundaryTests` (54 tests, 0 failures). `git diff --check`, `zsh -n Scripts/build-android-local.sh`, and `Scripts/build-android-local.sh` safe-fail exit 66 also passed. No Gradle wrapper generation, dependency download, SDK install, global tool install, APK build, emulator/device run, real external URL request, credential access, or network QA was attempted.
- 2026-06-13: Closed the Android Add URL credentialed-direct-media entry gap at the source/static boundary. `AndroidAddUrlPlanner.stageDirectUrl` now parses direct-link input with `java.net.URI`, requires HTTPS plus a host, rejects query/fragment links with the existing signed-link copy, rejects `uri.rawUserInfo` before queueing, and checks media extension only from `uri.path`. `AndroidAppStateTest.kt` includes a future Gradle test for `https://user:pass@cdn.example.com/video.mp4`, while Swift boundary tests assert the URI-based contract and no-network/no-credential Add planner path. Verification followed the corrected RED/GREEN target: `AndroidDataBoundaryTests/testAndroidLiveAddDoesNotFabricateReadyMediaForGenericWebPages` failed first on the missing URI/userinfo assertions, then passed with `AndroidDataBoundaryTests/testAndroidAddUrlPlannerStagesDirectHTTPSMediaURLWithoutNetworkOrCredentials`; the current combined run passed `AndroidDataBoundaryTests` plus related iOS/translation compile gates (57 tests, 0 failures). `git diff --check` and `zsh -n Scripts/build-android-local.sh` passed; `Scripts/build-android-local.sh` still safe-failed exit 66 because no `android/gradlew` and no PATH `gradle` are available. No wrapper generation, dependency download, SDK install, APK build, emulator/device run, real URL request, credential access, or external network access was attempted.
- 2026-06-13: Added the Android Add domain session-state slice at the source/static boundary. `AndroidAppState` now exposes `addSessionState: MobileAddSessionState`, live state starts at `IDLE`, successful vetted direct-media staging moves to `READY`, malformed input stays `FAILED`, and query/fragment/userinfo/generic web rejections move to `UNSUPPORTED` while clearing any prior `addReadyState`. Kotlin test source now covers the six Material Add states and direct-link state transitions; Swift boundary coverage enforces the Android domain contract. Verification followed TDD: `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-android-add-state-red --filter AndroidDataBoundaryTests/testAndroidAddDomainExposesFullMaterialAddStateMachine` first failed with 6 expected missing-contract failures, then passed after implementation (1 test, 0 failures). This does not complete the Compose Add UI state machine, Gradle/JVM execution, APK runtime, TalkBack/font-scale QA, or real parser/downloader validation.
- 2026-06-13: Closed the Android Settings API-key deletion parity gap at the source/static boundary after read-only Android review. `SettingsScreen` now exposes an enabled `移除 API key` action only when a credential reference is configured, calls `credentialStore.deleteCredential(AndroidTranslationCredentialReference)`, clears the password draft/status through Compose state, and notifies the owning app through `onAPIKeyReferenceCleared`. `AndroidAppState.withoutAPIKeyReference()` clears only the credential reference while preserving the current Add, Queue, Library, local-model, notification, and background readiness state instead of rebuilding `AndroidAppState.live(...)`. Future Kotlin test source covers navigation/task preservation, and Swift static boundary coverage locks the delete path against `rememberSaveable` secret draft state and empty-string credential saves. Verification followed TDD: `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-android-api-key-delete-red --filter AndroidDataBoundaryTests/testAndroidSettingsDeletesAPIKeyThroughKeystoreWithoutDroppingAppState` first failed with 9 expected missing-contract failures, then the same targeted test passed with `.build/vdl-android-api-key-delete-green` (1 test, 0 failures), and `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-android-api-key-delete-boundary --filter AndroidDataBoundaryTests` passed (57 tests, 0 failures). `git diff --check`, `zsh -n Scripts/build-android-local.sh`, and `Scripts/build-android-local.sh` safe-fail exit 66 also passed. This does not prove Android APK/runtime, actual Keystore deletion on device, Compose runtime behavior, Gradle/JVM tests, notification/runtime WorkManager behavior, or mobile ship readiness.
- 2026-06-13: Follow-up quality review found no blocker for the API-key deletion slice. The non-blocking fixes were applied immediately: `SettingsScreen` now deletes `appState.settings.apiKeyReference` instead of a hard-coded reference, and the future Kotlin domain test explicitly preserves `backgroundRuntimeReadiness` / notification permission across `withoutAPIKeyReference()`. Verification passed with `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-android-api-key-delete-review-fix --filter 'AndroidDataBoundaryTests/testAndroidSettingsDeletesAPIKeyThroughKeystoreWithoutDroppingAppState|AndroidDataBoundaryTests/testAndroidSettingsSavesAPIKeyThroughKeystoreWithoutSaveableSecretState|AndroidDataBoundaryTests/testAndroidSettingsStateTracksCredentialReferenceWithoutSecretValue'` (3 tests, 0 failures).
- 2026-06-13: Closed the Android Add/direct-download extension drift found during review at the source/static boundary. `AndroidAddUrlPlanner.supportedDirectMediaExtensions` now matches the current foreground/background downloader safety gates (`mp4`, `mov`, `m4v`, `webm`) instead of accepting audio/MKV links that would be queueable but fail immediately in the downloader. The unsupported copy now says Android direct links currently support `.mp4`, `.mov`, `.m4v`, or `.webm`, and future Kotlin test source covers `.mp3` rejection before queueing. Verification followed TDD: `swift test --jobs 1 --disable-index-store --scratch-path .build/vdl-android-direct-extension-red --filter AndroidDataBoundaryTests/testAndroidLiveAddDoesNotFabricateReadyMediaForGenericWebPages` first failed with 7 expected extension/copy/test-source failures, then passed with `.build/vdl-android-direct-extension-green` (1 test, 0 failures). This does not add audio support; it keeps Android direct-link UX honest until media parsing/downloader support expands and is runtime verified.

## Final Verification Checklist for Future Android Workers

- Android project builds from `android/` without modifying existing desktop builds. Current blocker: no Gradle wrapper/local Gradle.
- Kotlin domain model tests cover action/state parity with `MobileModels.swift` concepts.
- Kotlin domain source now includes render/export action and planner parity, but the Kotlin tests are not executable until Gradle is available.
- Add local-subtitle import and export-mode selection are covered by Swift source/static boundary tests and Kotlin test source, but Kotlin tests, Compose runtime state restoration, real Android document picker import, subtitle parsing, translation, and burned-in render/export execution are not executable until Gradle/APK/device validation is available.
- Kotlin repository tests include signed-URL cleanup for non-metadata artifacts. Source coverage has been added, but Gradle execution is still blocked by missing wrapper/local Gradle.
- `:core:worker` now has a bounded WorkManager skeleton in source/static coverage, but the worker fails by design and does not implement download, render, notifications, cancellation, or persistence. Kotlin worker tests are present as future Gradle coverage only.
- Compose UI exposes Add, Queue, Library, Settings with Material 3 components.
- Compose live shell reads domain action states for Add/import/API key/background status and does not hard-code click-local unsupported copy in production UI. Local translation is currently a status-only Settings row until real model download/inference is implemented and runtime verified.
- Add first screen now prioritizes local video import in source/static coverage (`导入视频` before `直链`), while direct links are explicitly limited to HTTPS direct media files. This still needs Compose runtime, font-scale, TalkBack, and real document-picker validation once APK execution is available.
- Add URL currently stages only URI-validated HTTPS direct media inputs, including the first URL extracted from Android Sharesheet text, into Add ready-state and then Queue selection by source/static boundary only. Generic web pages are rejected instead of fabricated, query/fragment/userinfo links are rejected before queueing, direct-link extensions are limited to the same `.mp4/.mov/.m4v/.webm` set enforced by the current downloaders, and the domain now exposes explicit `MobileAddSessionState` transitions for idle/ready/unsupported/failed. It does not analyze sites, render every Add UI state in Compose, run WorkManager, or prove APK/runtime behavior.
- Queue direct-media items now have a foreground-only `HttpURLConnection` app-owned download adapter in source/static coverage. It rejects initial query/fragment/userinfo URLs, disables automatic redirects, validates the final connection URL before reading bytes, writes under `filesDir/downloads`, records `android-owned:` storage identifiers in app/task state, converts those identifiers to FileProvider `content://` URIs only at open/share/save boundaries, reports byte progress into queue state, and the Compose shell cancels the active coroutine when the queue item is removed. It still lacks APK/runtime validation, cancellation cleanup proof on device, runtime progress rendering proof, resume/range support, background execution, persistence after relaunch, and real external download QA.
- Queue/Library actions are now actual Material buttons in source/static coverage, and enabled local remove/delete actions mutate in-memory state. Library open/share/save-copy source paths route through typed actions, Android intents, SAF copy helpers, and a FileProvider-safe URI normalization helper, but they still do not prove runtime Compose behavior, persistence, downloader cancellation, APK execution, chooser availability, real-device intent grants, or file permission behavior.
- API key storage uses Keystore-backed encryption and never logs secrets. Source/static coverage now includes both save/update and delete-state parity, but real Android Keystore runtime deletion still needs APK/device validation.
- Local model readiness and deletion work without hidden network calls.
- Background worker states are honest about OS limitations.
- Storage and sharing use scoped storage, SAF, MediaStore, and Sharesheet correctly.
- Real-device background QA has been run before claiming background behavior is production-ready.
