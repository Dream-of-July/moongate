#!/usr/bin/env python3
"""Moongate 字幕质量 scorecard — 基线运行器。

扫描 `artifacts/subtitle_timing_eval` 下的缓存样本，对每个样本自动计算可计算的分量
（识别置信度/结构健康度、分段内生质量+可选声学一致性、翻译结构、有人工 .clean.srt 时的
CER/WER 与分段参考），合并 agent 写入的语义裁判（`agent_recognition_judge.json` /
`agent_translation_judge.json`，若存在），并对 `source_decision_scenarios.json` 跑源决策正确率，
最后产出 `scorecard.json` + `scorecard.md`。

用法：
  python3 run_scorecard_baseline.py                      # 默认扫 artifacts/subtitle_timing_eval
  python3 run_scorecard_baseline.py --acoustic           # 额外用能量 VAD 做声学边界校验(需 ffmpeg,较慢)
  python3 run_scorecard_baseline.py --roots viewing_quality viewing_quality_songs30
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/subtitle_timing_eval"))

from subtitle_timing_eval import scorecard as sc  # noqa: E402
from subtitle_timing_eval.srt import Cue, parse_srt  # noqa: E402
from subtitle_timing_eval.segmentation import evaluate_segmentation  # noqa: E402
from subtitle_timing_eval.viewing_quality import load_subtitle_cues, normalized_language_code  # noqa: E402

DEFAULT_ARTIFACTS = ROOT / "artifacts/subtitle_timing_eval"
CANDIDATE_GLOBS = ["local-asr.*.srt", "local-asr*.srt", "*.local-asr.*.srt"]
LANG_RE = re.compile(r"local-asr(?:\.\d+-\d+)?\.([a-z]{2,3})(?:\s+\d+)?\.srt$", re.I)
WINDOW_RE = re.compile(r"(\d+)-(\d+)")


def _clean(name: str) -> bool:
    # 跳过 macOS iCloud 的 " 2" 重复副本
    return " 2." not in name and " 3." not in name


def pick_candidate(sample_dir: Path) -> Optional[Path]:
    found: List[Path] = []
    for pattern in CANDIDATE_GLOBS:
        found.extend(sample_dir.glob(pattern))
    found = [p for p in dict.fromkeys(found) if p.is_file() and p.stat().st_size > 0 and _clean(p.name)]
    if not found:
        return None
    # 优先无窗口的 local-asr.<lang>.srt，其次最新
    found.sort(key=lambda p: (("-" in p.stem), -p.stat().st_mtime))
    return found[0]


def parse_language(candidate: Path, sample_dir: Path) -> Optional[str]:
    m = LANG_RE.search(candidate.name)
    if m:
        return normalized_language_code(m.group(1))
    return None


def parse_window(name: str) -> Optional[Tuple[float, float]]:
    m = WINDOW_RE.search(name)
    if not m:
        return None
    return float(m.group(1)), float(m.group(2))


def find_human_reference(sample_dir: Path, language: Optional[str]) -> Optional[Path]:
    candidates = [p for p in sorted(sample_dir.glob("*.clean.srt")) if p.is_file() and _clean(p.name)]
    if language:
        lang_match = [p for p in candidates if f".{language}." in p.name or f".{language}.clean" in p.name]
        if lang_match:
            return lang_match[0]
    return candidates[0] if candidates else None


def find_words(sample_dir: Path, window: Optional[Tuple[float, float]]) -> Optional[List[Dict[str, Any]]]:
    patterns = ["local-asr.words.json"]
    if window:
        wtag = f"{int(window[0])}-{int(window[1])}"
        patterns += [f"asr_words.{wtag}.whisper-cpp.json", f"asr_words.{wtag}.json"]
    patterns += ["*.words.json"]
    for pattern in patterns:
        for path in sorted(sample_dir.glob(pattern)):
            if not _clean(path.name) or "seg" in path.name:
                continue
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            words = data.get("words") if isinstance(data, dict) else data
            if isinstance(words, list) and words and any("probability" in w for w in words if isinstance(w, dict)):
                return words
    return None


def find_translated(sample_dir: Path, source_path: Optional[Path] = None) -> Optional[Path]:
    for name in ["translated.srt", "translated.zh-Hans.srt", "translated.zh.srt"]:
        path = sample_dir / name
        if path.is_file() and path.stat().st_size > 0:
            # 防陈旧:译文若早于其源(源已重新生成)则视为过期产物,不计分——避免拿旧乱码源的译文
            # 污染翻译认证(实测群青/浮夸 translated.srt 比重生成的 local-asr 旧 2-5 小时)。
            if source_path is not None and path.stat().st_mtime < source_path.stat().st_mtime:
                print(f"[stale translation skipped] {sample_dir.name}: translated older than source", file=sys.stderr)
                return None
            return path
    return None


def load_agent_judge(sample_dir: Path, name: str) -> Optional[Dict[str, Any]]:
    path = sample_dir / name
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def _judge_score(judge: Optional[Dict[str, Any]], key: str) -> Optional[float]:
    if not judge:
        return None
    value = judge.get(key)
    if isinstance(value, (int, float)):
        return float(value)
    # pass/blocking 形式回退：pass 且无 blocking → 90，有 blocking → 40
    if isinstance(judge.get("pass"), bool):
        blocking = judge.get("blockingIssues") or []
        return 40.0 if blocking else (90.0 if judge["pass"] else 50.0)
    return None


def clip_cues(cues: List[Cue], window: Optional[Tuple[float, float]]) -> List[Cue]:
    if not window:
        return cues
    lo, hi = window
    return [c for c in cues if c.end > lo and c.start < hi]


def maybe_speech_segments(sample_dir: Path, enable: bool) -> Optional[List[Dict[str, float]]]:
    if not enable:
        return None
    wav = None
    for name in ["local-asr.wav"]:
        path = sample_dir / name
        if path.is_file() and _clean(path.name):
            wav = path
            break
    if wav is None:
        wavs = [p for p in sorted(sample_dir.glob("*.wav")) if _clean(p.name) and "whisper-cpp" not in p.name]
        wav = wavs[0] if wavs else None
    if wav is None:
        return None
    try:
        from subtitle_timing_eval.vad import detect_speech_file
        payload = detect_speech_file(str(wav), str(sample_dir / "scorecard.speech.json"))
        return payload.get("segments")
    except Exception as exc:  # noqa: BLE001 - acoustic is best-effort
        print(f"[acoustic skipped] {sample_dir.name}: {exc}", file=sys.stderr)
        return None


def score_sample(sample_dir: Path, *, acoustic: bool) -> Optional[sc.SampleScorecard]:
    candidate = pick_candidate(sample_dir)
    if candidate is None:
        return None
    language = parse_language(candidate, sample_dir)
    window = parse_window(candidate.name)
    candidate_cues = load_subtitle_cues(candidate)
    if not candidate_cues:
        return None

    words = find_words(sample_dir, window)
    rec_judge = load_agent_judge(sample_dir, "agent_recognition_judge.json")

    reference_path = find_human_reference(sample_dir, language)
    reference_text: Optional[str] = None
    reference_seg_report: Optional[Dict[str, Any]] = None
    if reference_path:
        ref_cues = clip_cues(load_subtitle_cues(reference_path), window)
        if ref_cues:
            reference_text = "\n".join(c.text for c in ref_cues)
            reference_seg_report = evaluate_segmentation(
                candidate_cues, ref_cues, sample_dir.name,
                window_start=window[0] if window else None,
                window_end=window[1] if window else None,
            )

    recognition = sc.recognition_score(
        candidate_cues=candidate_cues,
        language_code=language,
        words=words,
        reference_text=reference_text,
        llm_accuracy_score=_judge_score(rec_judge, "accuracyScore"),
    )

    segmentation = sc.segmentation_score(
        candidate_cues=candidate_cues,
        language_code=language,
        reference_report=reference_seg_report,
        speech_segments=maybe_speech_segments(sample_dir, acoustic),
    )

    translated = find_translated(sample_dir, source_path=candidate)
    translation: Optional[sc.DimensionScore] = None
    if translated:
        tr_judge = load_agent_judge(sample_dir, "agent_translation_judge.json")
        translation = sc.translation_score(
            source_cues=candidate_cues,
            translated_cues=load_subtitle_cues(translated),
            llm_translation_score=_judge_score(tr_judge, "score"),
        )

    dimensions = {"recognition": recognition, "segmentation": segmentation}
    if translation is not None:
        dimensions["translation"] = translation
    return sc.SampleScorecard(
        sample_id=sample_dir.name,
        language_code=language or "unknown",
        category=_infer_category(sample_dir.name),
        dimensions=dimensions,
    )


def _infer_category(name: str) -> str:
    low = name.lower()
    if any(t in low for t in ["song", "yoasobi", "ado", "lyric", "gunjou", "lemon", "gurenge", "music", "mv", "jpop"]):
        return "music"
    if any(t in low for t in ["anime", "animation", "koupen"]):
        return "anime"
    if any(t in low for t in ["ted", "talk", "lecture", "tutorial", "interview", "self_study"]):
        return "talk"
    if "vlog" in low:
        return "vlog"
    return "other"


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the Moongate subtitle quality scorecard baseline.")
    parser.add_argument("--artifacts", type=Path, default=DEFAULT_ARTIFACTS)
    parser.add_argument("--roots", nargs="*", help="Only score these subdirectories (names under --artifacts).")
    parser.add_argument("--acoustic", action="store_true", help="Also compute energy-VAD acoustic boundary agreement (needs ffmpeg).")
    parser.add_argument("--scenarios", type=Path, default=ROOT / "tools/subtitle_timing_eval/source_decision_scenarios.json")
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_ARTIFACTS / "scorecard")
    args = parser.parse_args()

    if args.roots:
        sample_dirs = [args.artifacts / r for r in args.roots]
    else:
        sample_dirs = [p for p in sorted(args.artifacts.iterdir()) if p.is_dir()]
        # 也下钻一层(viewing_quality/<song> 这种嵌套)
        nested: List[Path] = []
        for d in sample_dirs:
            if pick_candidate(d) is None:
                nested.extend([c for c in sorted(d.iterdir()) if c.is_dir()])
        sample_dirs.extend(nested)

    samples: List[sc.SampleScorecard] = []
    for sample_dir in sample_dirs:
        if not sample_dir.is_dir():
            continue
        try:
            result = score_sample(sample_dir, acoustic=args.acoustic)
        except Exception as exc:  # noqa: BLE001 - one bad sample shouldn't kill the suite
            print(f"[scorecard error] {sample_dir.name}: {exc}", file=sys.stderr)
            continue
        if result is not None:
            samples.append(result)

    # 嵌套扫描可能让同一 sample_id 出现多次(如 viewing_quality/<song> 与 songs30/<song>)；
    # 按 sample_id 去重,保留维度更全(含翻译)的那条。严格 `>` 确保平分时保留先见者(sample_dirs 已排序→确定性)。
    def _richness(s: sc.SampleScorecard) -> int:
        return len(s.dimensions) + sum(1 for d in s.dimensions.values() if d.verified)
    deduped: Dict[str, sc.SampleScorecard] = {}
    for s in samples:
        existing = deduped.get(s.sample_id)
        if existing is None or _richness(s) > _richness(existing):
            deduped[s.sample_id] = s
    samples = sorted(deduped.values(), key=lambda s: s.sample_id)

    scenarios: List[Dict[str, Any]] = []
    if args.scenarios.is_file():
        scenarios = json.loads(args.scenarios.read_text(encoding="utf-8")).get("scenarios", [])
    source_decision = sc.source_decision_score(scenarios) if scenarios else None

    summary = sc.suite_summary(samples, source_decision)
    args.out_dir.mkdir(parents=True, exist_ok=True)
    payload = {
        "summary": summary,
        "source_decision": {
            "score": source_decision.score if source_decision else None,
            "notes": source_decision.notes if source_decision else [],
        },
        "samples": [
            {
                "sample_id": s.sample_id,
                "language_code": s.language_code,
                "category": s.category,
                "dimensions": {
                    name: {
                        "score": dim.score,
                        "components": dim.components,
                        "capped": dim.capped,
                        "notes": dim.notes,
                    }
                    for name, dim in s.dimensions.items()
                },
            }
            for s in samples
        ],
    }
    (args.out_dir / "scorecard.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (args.out_dir / "scorecard.md").write_text(sc.render_markdown(samples, summary), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    print(f"\nwrote {args.out_dir / 'scorecard.json'}")
    print(f"wrote {args.out_dir / 'scorecard.md'}")


if __name__ == "__main__":
    main()
