# macOS HIG Restructure Confirmation

## Purpose

This document turns the current macOS HIG audit into confirmation-ready work. It is not an implementation spec for a full redesign yet. July should be able to approve, reject, or narrow each decision before broad UI rewrites begin.

## Current State

- Main window is a single `Window` in `Sources/Moongate/App.swift`, defaulting to 560 x 780. `Cmd+,` now opens the existing Settings sheet, but Settings is not yet a dedicated macOS `Settings` scene.
- `Sources/Moongate/ContentView.swift` owns the URL input, parsing states, ready state, error state, and opens Settings, dependency setup, and login as sheets.
- `Sources/Moongate/QueueOverlayView.swift` still overlays the main content area. When expanded it covers the ready/download configuration surface.
- `Sources/Moongate/SettingsView.swift` is a fixed-size sheet with all settings in one grouped form.
- `Sources/Moongate/DependencySetupView.swift` is still a sheet. It now describes Homebrew side effects, but it remains a single-step install surface.
- `Sources/Moongate/LoginWebView.swift` now has compact Back, Reload, Open in Browser controls, loading state, host/path visibility, and target-site cookie readiness. It remains a fixed-size sheet, and cookie export scope/gating is still a product decision.

## HIG Issues To Confirm

### 1. Settings should become a real macOS Settings scene

Current issue:

- Settings are presented as a 480 x 560 sheet from the main workflow, including when opened through `Cmd+,`.
- Translation, dependencies, subtitles, performance, and login status are mixed into one form.
- The sheet is easy to overfill as Apple Intelligence guidance grows.

User impact:

- Settings feel like a task interruption rather than an app-level preference surface.
- Users get the standard `Cmd+,` entry point, but it still opens a workflow sheet instead of a native app-level Settings scene.
- Apple Intelligence onboarding competes with unrelated settings.

Recommended direction:

- Add a `Settings` scene in `MoongateApp`.
- Split settings into sidebar or tabbed pages: General, Translation, Subtitles, Accounts, Dependencies, Advanced.
- Keep cloud translation setup compact: protocol/model picker stays simple.
- Put Apple Intelligence readiness and setup guidance in the Translation page.

Confirmation needed:

- Approve moving Settings out of the main window sheet.
- Approve page grouping names.

### 2. Queue should stop covering the active workflow

Current issue:

- `QueueOverlayView` expands over the whole content area.
- The ready state below contains the selected format, subtitles, subtitle processing, and the "加入队列" action.
- Expanded queue makes the current task disappear instead of coexisting with it.

User impact:

- Users lose context when checking queue progress.
- It feels closer to a modal overlay than a Mac productivity tool.
- Long queues and active configuration compete for the same space.

Recommended direction:

- Replace expanded overlay with a non-covering queue panel.
- Preferred layout: main content on the left, queue panel on the right for widths above roughly 860 px.
- Compact layout: keep a bottom drawer, but cap height and avoid hiding the primary action.
- Preserve the small queue handle for narrow windows and Reduce Motion behavior.

Confirmation needed:

- Approve right-side queue panel as the default desktop layout.
- Approve raising the default window width to support the split layout.

### 3. Dependency install needs a confirmation wizard

Current issue:

- The dependency sheet now states the `brew install` side effect, but the install button still immediately launches the command.
- Install result, command plan, and log are in one surface.

User impact:

- On an enterprise-managed Mac, users need a clearer review step before running Homebrew.
- Install failure handling is readable but not staged.

Recommended direction:

- Convert dependency setup into a small task window or wizard:
  1. Check: installed/missing components.
  2. Review: exact formulas and command to run.
  3. Run: streaming log and cancel.
  4. Result: success, remaining gaps, retry.
- Keep "open brew.sh" as explicit manual guidance when Homebrew is missing. Do not install Homebrew from the app.

Confirmation needed:

- Approve adding a confirmation step before `brew install`.
- Approve wizard/task-window style instead of current single sheet.

### 4. Login WebView needs final login-flow decisions

Current issue:

- `LoginSheet` now has compact Back, Reload, Open in Browser controls, loading state, host/path display, and target-site Cookie readiness.
- It is still a fixed-size sheet rather than a dedicated login task window.
- Cookie readiness is informational; `保存登录信息` remains available even before target-site Cookies are detected, and is disabled only while export is already running.
- Cookie export scope is still broad for downloader compatibility.

User impact:

- Basic navigation recovery is better, but users can still hit embedded-WebView limitations on sites with complex login flows.
- Users may not understand the difference between "current site Cookie detected" and the broader saved Cookie export used by the downloader.

Recommended direction:

- Decide whether the current compact controls are enough, or whether login should become a separate task window.
- Decide whether `保存登录信息` should stay available before target-site Cookies are detected.
- Decide whether cookie export should remain broad or narrow to target-site Cookies.
- Continue not exposing cookie contents in UI or logs.

Confirmation needed:

- Approve keeping the current compact browser controls or expanding into a login task window.
- Approve whether target-cookie readiness should remain informational or gate saving.
- Approve whether cookie export should remain all-cookie export or be narrowed to target-site cookies.

### 5. Main window should support a denser Mac workflow

Current issue:

- Main width is optimized for one narrow column.
- Ready-state content uses stacked sections and repeated card surfaces.
- Queue and task configuration cannot be scanned side by side.

User impact:

- The app feels more like a compact utility sheet than a full Mac client.
- Repeated work, batch paste, and queue monitoring need more horizontal structure.

Recommended direction:

- Default window around 900 x 680 or similar, with a minimum compact fallback.
- Header remains simple: URL field, one prominent parse action, compact paste action, and settings access.
- Body becomes a split workflow:
  - Left: parsing/current video configuration.
  - Right: queue/progress panel.
  - Bottom only for primary action when the current task needs commitment.
- Use standard Mac spacing, restrained materials, and fewer nested card-like surfaces.

Confirmation needed:

- Approve wider default window and split workflow.
- Approve reducing decorative card surfaces in favor of clearer groups/lists.

### 6. Primary actions and app commands need native hierarchy

Current issue:

- `解析链接` is now the only prominent text action in the header, and paste-and-parse is a compact icon-only auxiliary action.
- Settings can now be opened through the App menu and `Cmd+,`, but the visible gear still carries most discovery inside the content area.
- Common workflow commands such as queue visibility and reveal downloads are not represented as Mac toolbar/menu commands.

User impact:

- The parse action hierarchy is cleaner, but the header still carries local workflow controls that could move into a more native toolbar/menu command structure.
- The first screen reads more like a web tool than a Mac app.
- Keyboard-oriented users now get the expected Settings shortcut, but the broader command hierarchy is still thin.

Recommended direction:

- Keep one clear primary action in the URL area: `解析链接`.
- Move secondary actions such as paste-and-parse, Settings, queue, and reveal downloads into toolbar/menu commands.
- If paste remains visible, make it a compact icon or secondary button with precise help text.

Confirmation needed:

- Approve toolbar/menu command direction.
- Approve making `解析链接` the only prominent header action.

### 7. Apple readiness needs higher visual priority

Current issue:

- Settings now has a compact `当前引擎` / `状态` / `首要原因` Apple readiness summary, but it is still embedded in the single Settings sheet rather than a dedicated Translation settings page.
- In the main flow, users encounter readiness only after subtitle translation is selected.
- Apple Translation has a guarded execution path only when runtime requirements are met, including explicit source language, supported OS/runtime, and installed language packs; unavailable states still need clear fallback copy.

User impact:

- The current headline product feature can still look like a secondary warning because it lives inside a dense sheet.
- Users do not immediately know why an Apple engine is unavailable or what to do next.

Recommended direction:

- In the future Translation settings page, preserve the current compact status summary and make it easier to find: selected engine, current readiness, next action, and fallback.
- In the main subtitle-processing area, use the same readiness summary when translation is blocked.
- Keep the copy honest: runtime detection is not a cloud/PCC execution claim, and Apple Translation execution is conditional on the verified local runtime gates.

Confirmation needed:

- Approve moving the existing Apple readiness summary into a dedicated Translation settings surface.
- Approve keeping runtime-gate limitations visible until real-device validation proves the path.

### 8. Native selection and accessibility semantics should replace custom rows gradually

Current issue:

- Candidate and format rows are custom plain buttons.
- Subtitle processing uses hidden labels and radio group styling inside a custom card.
- Queue row actions are icon-only buttons; many are labeled, but roles and keyboard scanning can still be improved.

User impact:

- Keyboard and VoiceOver semantics are weaker than native `List`, `Table`, `Picker`, toolbar, or context menu patterns.
- The UI has more custom card/list surfaces than a Mac utility needs.

Recommended direction:

- Move format/candidate choices toward native selection lists.
- Move secondary queue item actions into context menus or grouped toolbar-style actions where appropriate.
- Keep accessibility labels/help on all icon-only actions.

Confirmation needed:

- Approve gradual migration to native selection/list surfaces.
- Approve using context menus for secondary queue actions.

### 9. Fixed sizes and long implementation copy should be reduced

Current issue:

- Main, Settings, and Dependency surfaces have fixed or narrow default sizes. Login is wider than before, but still fixed-size.
- The most technical API protocol details have moved into disclosure/help copy, but the Settings sheet is still dense and mixes setup, diagnostics, dependencies, subtitles, and accounts.

User impact:

- Large text, small displays, and Chinese copy can crowd the layout.
- Non-technical users still need to scan a dense settings sheet before completing common settings.

Recommended direction:

- Keep protocol details in help/disclosure text and continue shortening the primary form.
- Use shorter primary copy and keep advanced details selectable or expandable.
- Prefer min/ideal/max sizing over fixed sheet sizes where feasible.

Confirmation needed:

- Approve shortening primary settings copy and moving implementation details into disclosures.

## Completed Low-Risk Quick Wins

- Audited icon-only button labels/help for queue, login, and main workflow controls.
- Added loading state to login page navigation.
- Tightened wording where Apple Translation is detected but runtime execution is gated by adapter/readiness constraints.
- Added `informativeText` to close/quit confirmation alerts so the primary and destructive choices are easier to evaluate.
- Moved advanced API protocol details into disclosure/help copy.
- Keep Reduce Motion behavior already added to queue transitions and progress ring.
- Corrected API credential side-effect copy so it names both `拉取模型` and `测试连接` as the user-triggered network actions.
- Clarified the ready-page destination hint: single-file output says `Downloads`, while subtitle/translation/burn-in output says it will use a video-title folder under `Downloads`.
- Tightened destructive login-clear copy so the button and confirmation dialog state that only this App's saved login information is cleared.
- Reduced header action competition by making paste-and-parse a compact icon-only auxiliary button while keeping `解析链接` as the only prominent header text action.
- Made the Apple readiness panel easier to scan with `当前引擎` / `状态` / `首要原因`, while fallback copy stays limited to Anthropic-compatible or OpenAI-compatible engines and does not imply unsupported PCC/Cloud execution.

## Work That Should Wait For July Confirmation

- Replacing the queue overlay with a split layout.
- Moving Settings to a `Settings` scene and changing navigation structure.
- Reworking dependency setup as a multi-step wizard.
- Expanding login WebView into a browser-like task window.
- Raising default window size and reorganizing the ready-state layout.
- Changing cookie export scope or save gating.
- Moving secondary actions into a toolbar/menu command structure.

## Proposed Implementation Phases

### Phase 1: App shell and Settings scene

- Replace the current `Cmd+,`-opened settings sheet with a real `Settings` scene.
- Keep existing settings content initially, split into pages with minimal visual change.
- Update tests around app/settings state where possible.

### Phase 2: Queue and main layout

- Replace full-screen queue overlay with a non-covering queue panel.
- Introduce responsive compact behavior for narrow windows.
- Preserve current queue actions and Reduce Motion behavior.

### Phase 3: Task windows

- Convert dependency setup into a reviewed install wizard.
- Decide whether the existing compact login controls should become a separate task window, and whether target-cookie readiness should gate saving.
- Keep external side effects user-initiated and clearly described.

### Phase 4: Native selection semantics and copy cleanup

- Migrate custom format/candidate rows toward native selection lists.
- Move advanced protocol copy into disclosure/help.
- Review keyboard navigation and VoiceOver semantics after layout changes.

## Acceptance Criteria

- The app still supports the current download, subtitle, translation, queue, dependency, and login flows.
- Apple engines remain honest: no fake PCC/Cloud Pro adapter; Apple Translation claims stay limited to the guarded local subtitle execution path and verified runtime gates.
- No secret, token, cookie, or internal URL is logged or surfaced.
- Settings can be opened through the Mac-standard path.
- Queue progress can be monitored without hiding the current task on normal desktop widths.
- Dependency installation has an explicit review step before running Homebrew.
- Login flow preserves Back, Reload, Open in Browser, loading state, and target-cookie readiness while any task-window or cookie-gating changes remain explicit product decisions.
- The URL header has one prominent parse action, with secondary actions moved to a less competing hierarchy.
- Apple readiness is visible at the Translation settings level, not only as caption text after a blocked action.
- Full Swift package tests and macOS app/CLI builds pass after each implementation phase.
