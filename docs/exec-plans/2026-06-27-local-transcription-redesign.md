# Local Transcription Path Redesign

## Background And Product Intent

Moongate local subtitle quality is still bottlenecked by raw ASR mistakes, bad language guesses, and Whisper loop collapses on CJK/music samples. A temporary SenseVoiceSmall/FunASR POC on the first 90 seconds of the Gunjo sample showed fast CPU runtime after setup, but model/dependency cost and text quality were not clearly better than whisper.cpp. SenseVoice should therefore be an eval candidate, not the default app backend.

## Current Repository Understanding

- macOS local ASR contract and whisper.cpp parser live in `Sources/MoongateCore/ASR.swift`.
- Windows mirrors the same contract in `windows/MoongateCore/Asr.cs`.
- Transcript quality warning logic lives in `Sources/MoongateCore/LocalASRConfidence.swift` and `windows/MoongateCore/LocalAsrConfidence.cs`.
- Viewing-quality eval gates live in `tools/subtitle_timing_eval/subtitle_timing_eval/viewing_quality.py`.
- ASR eval engines are routed through `tools/subtitle_timing_eval/subtitle_timing_eval/asr.py`, `pipeline.py`, and `cli.py`.

## Goals

- Keep `whisper.cpp` as the production default.
- Add `sensevoice-funasr` only as an experimental eval engine.
- Make the ASR transcript schema carry backend, segments, raw text, diagnostics, and quality summary.
- Prevent cache reuse across backend/model/language/VAD/timestamp semantics.
- Detect confident repetition-loop collapses and low-diversity CJK transcripts earlier.

## Non-Goals

- Do not expose SenseVoice in normal app settings yet.
- Do not replace whisper.cpp or add cloud ASR.
- Do not ship FunASR model/runtime inside the app in this iteration.

## Approach

- Add `ASRBackendKind` / `AsrBackendKind` and extend transcript cache entries with backend identity.
- Write whisper.cpp parser diagnostics into `ASRTranscript` / `AsrTranscript`.
- Fold repetition-loop and low-diversity checks into local ASR quality summaries.
- Add FunASR/SenseVoice parsing and CLI routing under the subtitle timing eval tool only.
- Add viewing-quality blockers for non-adjacent repetition loops.

## Milestones And Validation

- Swift ASR contract and confidence tests pass.
- Windows ASR contract tests pass.
- Python eval unit tests pass without requiring the SenseVoice model.
- Later manual eval should compare Whisper default, Whisper improved settings, and SenseVoice on Gunjo, the Pornhub Japanese sample, and zh/yue/ko music samples.

## Expected File Changes

- `Sources/MoongateCore/ASR.swift`
- `Sources/MoongateCore/LocalASRConfidence.swift`
- `windows/MoongateCore/Asr.cs`
- `windows/MoongateCore/LocalAsrConfidence.cs`
- `tools/subtitle_timing_eval/subtitle_timing_eval/asr.py`
- `tools/subtitle_timing_eval/subtitle_timing_eval/pipeline.py`
- `tools/subtitle_timing_eval/subtitle_timing_eval/cli.py`
- Related Swift/C#/Python tests.

## Risks And Rollback

- Risk: extra transcript fields change cache JSON shape. Mitigation: legacy decode defaults keep old payloads readable.
- Risk: loop detection over-flags repeated choruses. Mitigation: tests require high dominance/low diversity, and healthy repeated lyrics remain usable.
- Risk: SenseVoice dependencies are heavy. Mitigation: eval-only path raises an installation hint and is not reachable from app UI.

## Decision Record

- 2026-06-27: Keep whisper.cpp as default; SenseVoice/FunASR remains eval-only until real samples prove better text accuracy and deployability.
- 2026-06-27: Cache identity now includes backend and timestamp/VAD/context semantics to avoid stale `.local-asr.en.srt` style collisions.
- 2026-06-27: Quality summaries now treat repetition-loop collapse as low quality even when token probabilities are high.

## Progress

- 2026-06-27: Added ASR transcript backend/schema diagnostics across Swift and Windows.
- 2026-06-27: Added CJK repetition-loop quality detection across Swift and Windows.
- 2026-06-27: Added `sensevoice-funasr` eval engine parsing/routing.
- 2026-06-27: Added viewing-quality non-adjacent repetition blocker.

## Final Validation Checklist

- [x] Python unittest suite for subtitle timing eval parser/viewing-quality.
- [x] Swift `ASRContractsTests|LocalASRConfidenceTests`.
- [x] Windows `AsrContractsTests`.
- [ ] Full `tools/subtitle_timing_eval/run_viewing_quality_suite.py --suite songs30`.
- [ ] Manual SRT inspection on at least two windows per language group.
