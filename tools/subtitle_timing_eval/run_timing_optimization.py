#!/usr/bin/env python3
"""Whisper 时序 + 分段优化 harness — 多样本 A/B。

对所有"同时有人工 .clean.srt + whisper 词级 json"的样本,用 moongate-cli 从词级时间戳重新生成
源 SRT(指定 timing-profile),再用 reference-metrics(时序)+ segmentation(分段)对比人工字幕打分,
按语言聚合。这是时序/分段调参的"秤":改 Swift/C# 参数 + rebuild 后重跑本脚本看 before/after。

用法:
  python3 run_timing_optimization.py                 # 全部样本,speech 档
  python3 run_timing_optimization.py --samples tedx_nagoyau_happiness_ja ted_school_creativity_en
  python3 run_timing_optimization.py --label after   # 标注本次为 after,与上次 before 对比
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from statistics import mean
from typing import Any, Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "artifacts/subtitle_timing_eval"
CLI = Path.home() / "Library/Caches/vdl-build/arm64-apple-macosx/debug/moongate-cli"
EVAL = ROOT / "tools/subtitle_timing_eval"

WINDOW_RE = re.compile(r"(\d+)-(\d+)")
LANG_RE = re.compile(r"\.([a-z]{2,3}(?:-[A-Za-z]{2,4})?)(?:-orig)?\.clean\.srt$")


def _clean(name: str) -> bool:
    return " 2." not in name and " 3." not in name


def normalize_lang(code: str) -> str:
    low = code.lower()
    if low.startswith("zh") or low in {"cmn", "zho", "yue"} or low.startswith("yue"):
        return "yue" if "hk" in low or low.startswith("yue") else "zh"
    if low.startswith("ja"):
        return "ja"
    if low.startswith("ko"):
        return "ko"
    return low.split("-")[0]


def timing_profile_for(lang: str, sample_dir_name: str) -> str:
    low = sample_dir_name.lower()
    music = any(t in low for t in ["song", "music", "lyric", "mv", "jpop"])
    anime = "anime" in low or "animation" in low
    if music and lang == "ja":
        return "japaneseLyrics"
    if music:
        return "lyrics"
    if anime:
        return "anime"
    return "speech"


def find_human_ref(sample_dir: Path) -> Optional[Path]:
    cands = [p for p in sorted(sample_dir.glob("*.clean.srt")) if _clean(p.name)]
    return cands[0] if cands else None


def find_words(sample_dir: Path) -> Optional[Tuple[Path, Optional[Tuple[int, int]]]]:
    """优先选窗口最大、非 seg、非 double-whisper-cpp 的词级 json。"""
    cands: List[Path] = []
    for pat in ["asr_words*.json", "local-asr.words.json"]:
        cands.extend(sorted(sample_dir.glob(pat)))
    scored: List[Tuple[int, Path, Optional[Tuple[int, int]]]] = []
    for p in cands:
        if not _clean(p.name) or "seg" in p.name or "whisper-cpp.whisper-cpp" in p.name:
            continue
        try:
            d = json.loads(p.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        words = d.get("words") if isinstance(d, dict) else d
        if not (isinstance(words, list) and words):
            continue
        m = WINDOW_RE.search(p.name)
        window = (int(m.group(1)), int(m.group(2))) if m else None
        span = (window[1] - window[0]) if window else 0
        scored.append((span, p, window))
    if not scored:
        return None
    scored.sort(key=lambda x: x[0], reverse=True)
    return scored[0][1], scored[0][2]


def regen_srt(words_path: Path, lang: str, profile: str, out_path: Path, file_name: str) -> bool:
    cmd = [
        str(CLI), "local-asr-srt",
        "--asr-words", str(words_path),
        "--language", lang,
        "--out", str(out_path),
        "--file-name", file_name,
        "--timing-profile", profile,
    ]
    try:
        subprocess.run(cmd, check=True, capture_output=True, text=True)
        return out_path.is_file()
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"[regen failed] {words_path.parent.name}: {exc}", file=sys.stderr)
        return False


def score_timing(candidate: Path, reference: Path, window: Optional[Tuple[int, int]], out: Path) -> Optional[Dict[str, Any]]:
    cmd = [
        sys.executable, "-m", "subtitle_timing_eval.cli", "reference-metrics",
        "--candidate", str(candidate),
        "--reference", str(reference),
        "--sample-id", candidate.parent.name,
        "--out", str(out),
    ]
    if window:
        cmd += ["--candidate-offset-seconds", str(window[0]),
                "--window-start-seconds", str(window[0]),
                "--window-end-seconds", str(window[1])]
    env = {"PYTHONPATH": str(EVAL)}
    try:
        subprocess.run(cmd, check=True, capture_output=True, text=True, cwd=str(EVAL),
                       env={**__import__("os").environ, **env})
        return json.loads(out.read_text(encoding="utf-8")).get("summary")
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError) as exc:
        print(f"[timing score failed] {candidate.parent.name}: {exc}", file=sys.stderr)
        return None


def score_segmentation(candidate: Path, reference: Path, window: Optional[Tuple[int, int]]) -> Optional[Dict[str, Any]]:
    sys.path.insert(0, str(EVAL))
    from subtitle_timing_eval.srt import parse_srt, Cue
    from subtitle_timing_eval.segmentation import evaluate_segmentation
    cand = parse_srt(candidate.read_text(encoding="utf-8"))
    if window:
        cand = [Cue(c.index, c.start + window[0], c.end + window[0], c.text) for c in cand]
    ref = parse_srt(reference.read_text(encoding="utf-8"))
    ws = window[0] if window else None
    we = window[1] if window else None
    return evaluate_segmentation(cand, ref, candidate.parent.name, window_start=ws, window_end=we)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--samples", nargs="*")
    ap.add_argument("--label", default="run")
    ap.add_argument("--out-dir", type=Path, default=ARTIFACTS / "timing_opt")
    args = ap.parse_args()

    if args.samples:
        dirs = [ARTIFACTS / s for s in args.samples]
    else:
        dirs = [d for d in sorted(ARTIFACTS.iterdir()) if d.is_dir()]

    args.out_dir.mkdir(parents=True, exist_ok=True)
    tmp = args.out_dir / "tmp"
    tmp.mkdir(exist_ok=True)

    rows: List[Dict[str, Any]] = []
    for d in dirs:
        if not d.is_dir():
            continue
        ref = find_human_ref(d)
        wfound = find_words(d)
        if ref is None or wfound is None:
            continue
        words_path, window = wfound
        m = LANG_RE.search(ref.name)
        lang = normalize_lang(m.group(1)) if m else "unknown"
        profile = timing_profile_for(lang, d.name)
        out_srt = tmp / f"{d.name}.{args.label}.srt"
        if not regen_srt(words_path, lang, profile, out_srt, d.name):
            continue
        timing = score_timing(out_srt, ref, window, tmp / f"{d.name}.timing.json")
        seg = score_segmentation(out_srt, ref, window)
        if timing is None or seg is None:
            continue
        rows.append({
            "sample": d.name, "lang": lang, "profile": profile,
            "accepted_ratio": round(timing.get("accepted_ratio", 0), 3),
            "p90_start_ms": round(timing.get("p90_abs_start_error_ms", 0)),
            "p90_end_ms": round(timing.get("p90_abs_end_error_ms", 0)),
            "early_cutoff": timing.get("early_cutoff_count", 0),
            "seg_aligned_f1": round(seg.get("aligned_boundary_f1", 0), 3),
            "seg_strong_recall": round(seg.get("strong_boundary_recall", 0), 3),
            "seg_count_ratio": round(seg.get("segment_count_ratio", 0), 3),
            "seg_offset_ms": round(seg.get("systematic_offset_ms", 0)),
        })

    # aggregate
    def agg(items: List[Dict[str, Any]], key: str) -> Optional[float]:
        vals = [r[key] for r in items if isinstance(r.get(key), (int, float))]
        return round(mean(vals), 3) if vals else None

    by_lang: Dict[str, List[Dict[str, Any]]] = {}
    for r in rows:
        by_lang.setdefault(r["lang"], []).append(r)

    summary = {
        "label": args.label,
        "sample_count": len(rows),
        "overall": {k: agg(rows, k) for k in ["accepted_ratio", "p90_start_ms", "p90_end_ms", "early_cutoff", "seg_aligned_f1", "seg_strong_recall", "seg_count_ratio", "seg_offset_ms"]},
        "by_lang": {lang: {k: agg(items, k) for k in ["accepted_ratio", "p90_start_ms", "seg_aligned_f1", "seg_strong_recall"]} for lang, items in sorted(by_lang.items())},
        "samples": rows,
    }
    out_json = args.out_dir / f"timing_opt.{args.label}.json"
    out_json.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary["overall"], ensure_ascii=False, indent=2))
    print(f"\nby_lang:")
    for lang, v in summary["by_lang"].items():
        print(f"  {lang:4} n={len(by_lang[lang])}  accepted={v['accepted_ratio']}  p90_start={v['p90_start_ms']}ms  seg_f1={v['seg_aligned_f1']}  strong={v['seg_strong_recall']}")
    print(f"\nwrote {out_json}")


if __name__ == "__main__":
    main()
