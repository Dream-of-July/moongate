"""Moongate 字幕质量 **可量化测试标准** — 四维 scorecard。

本模块把"字幕好不好"拆成四个可独立打分（0-100）、可分别设 ≥80 门禁的维度：

1. recognition  识别准确率  —— Whisper/平台字幕把语音转成文字转得对不对
2. segmentation 分段/分词准确率 —— 切句切词的位置对不对（含声学停顿校验）
3. translation  翻译准确率  —— 译文是否忠实、通顺、一致
4. source_decision 源决策正确率 —— "用平台字幕 / 本地 Whisper / 云端"选得对不对

设计原则（与七月 2026-06-29 的指示一致）：
- **可计算部分自动算**：词级置信度（来自 whisper words.json）、结构健康度（镜像
  `PlatformSubtitleQualityGate`）、分段边界 F1 / 强边界召回（`segmentation.py`）、声学停顿
  一致性（`vad.py` 能量 VAD = "看音频波谱"）、有人工参考时的 CER/WER。
- **语义部分由 agent/LLM 裁判补**：识别/翻译的"是否真的对、是否通顺"由 agent 实际读输出、
  必要时对照在线人工字幕后，写入 `agent_*_judge.json`，本模块合并其分数。
- 某个分量缺失时按存在的分量**重新归一**，绝不用占位假分充数；纯结构无语义裁判时翻译分**封顶**，
  诚实标注"需 LLM 裁判才能认证 ≥80"。

所有 rubric 常量集中在 `RUBRIC` 顶部，便于校准。打分函数是纯函数（无 I/O），文件扫描在 CLI 层。
"""

from __future__ import annotations

import math
import re
from dataclasses import dataclass, field
from statistics import mean
from typing import Any, Dict, List, Optional, Sequence

from .srt import Cue
from .viewing_quality import (
    normalized_language_code,
    source_quality_report,
    is_cjk_language,
    weak_boundary_candidates,
    preview_rows,
)


# ---------------------------------------------------------------------------
# Rubric constants (single place to calibrate the standard)
# ---------------------------------------------------------------------------

EXCELLENT_GATE = 80.0  # 七月要求：各维 ≥80 视为优秀

PUNCT_RE = re.compile(r"[\s\.,!?;:'\"()\[\]{}<>~`@#$%^&*_+=|\\/。，！？；：、（）【】「」『』《》…—–·♪♫\-]")


@dataclass(frozen=True)
class _Rubric:
    # --- recognition: confidence (from words.json word probabilities) ---
    confidence_min_words: int = 24          # 少于此词数视为不可评（与 LocalASRConfidence 一致）
    confidence_floor_prob: float = 0.60     # avg_prob<=此值 → 0 分
    confidence_ceiling_prob: float = 0.95   # avg_prob>=此值 → 100 分（封顶前）
    confidence_low_prob: float = 0.50       # 单词低置信阈值
    confidence_low_ratio_free: float = 0.10 # 低置信词占比超出此值才扣分
    confidence_low_ratio_penalty: float = 120.0
    confidence_low_ratio_penalty_cap: float = 35.0

    # --- recognition / structural health penalties (镜像 SubtitleQualityScorer) ---
    bad_scalar_penalty: float = 200.0
    bad_scalar_penalty_cap: float = 45.0
    repetition_penalty: float = 70.0
    repetition_penalty_cap: float = 35.0
    romaji_loop_penalty: float = 50.0
    romaji_loop_penalty_cap: float = 30.0
    cjk_latin_leak_penalty: float = 60.0
    cjk_latin_leak_penalty_cap: float = 30.0
    low_unique_penalty: float = 40.0

    # --- recognition component weights (renormalized over present components) ---
    w_reference: float = 0.50
    w_confidence: float = 0.25
    w_structural: float = 0.25
    # 有 LLM 裁判(实际读过输出)时让它**主导**——它是真值,whisper 自信度只是代理,绝不能让
    # "自信乱码"(如 BLACKPINK avg_prob 0.85 却错)靠置信度把分数抬过门。
    w_llm_recognition: float = 0.70

    # --- segmentation ---
    seg_w_strong_recall: float = 0.40
    seg_w_aligned_f1: float = 0.30
    seg_w_coverage: float = 0.20
    seg_w_count_ratio: float = 0.10
    seg_acoustic_tolerance_s: float = 0.40   # cue onset 距声学停顿/语音起点的容忍窗
    seg_internal_long_cue_penalty: float = 40.0
    seg_internal_long_cue_multiplier: float = 200.0  # long_cue_ratio→扣分系数(单点校准,与上方 cap 配合)
    seg_internal_weak_boundary_penalty: float = 8.0    # 每个悬空/词中断候选
    seg_internal_weak_boundary_cap: float = 40.0
    # segmentation 分量权重：声学+内生（whisper 可达）优先于参考（whisper-vs-人工结构性封顶~0.65）
    seg_w_acoustic_when_present: float = 0.40
    seg_w_internal_base: float = 0.35
    seg_w_reference_when_present: float = 0.25

    # --- translation ---
    translation_structural_only_cap: float = 75.0  # 无 LLM 裁判时翻译分封顶（不可认证优秀）
    translation_empty_penalty: float = 60.0
    translation_repeat_penalty: float = 45.0
    translation_romaji_leak_penalty: float = 50.0
    translation_count_mismatch_penalty: float = 30.0
    translation_count_mismatch_threshold: float = 0.50  # 仅惩罚"严重"数目失配；LLM 重分段(如 43→29)是合法的
    w_llm_translation: float = 0.70  # 有 LLM 裁判时主导


RUBRIC = _Rubric()


# ---------------------------------------------------------------------------
# Small numeric helpers
# ---------------------------------------------------------------------------

def _clamp(value: float, low: float = 0.0, high: float = 100.0) -> float:
    return max(low, min(high, value))


def _linear_map(value: float, in_lo: float, in_hi: float, out_lo: float, out_hi: float) -> float:
    if in_hi <= in_lo:
        return out_lo
    t = (value - in_lo) / (in_hi - in_lo)
    return out_lo + _clamp(t, 0.0, 1.0) * (out_hi - out_lo)


def _weighted(components: Dict[str, Optional[float]], weights: Dict[str, float]) -> Optional[float]:
    """Weighted mean over the components that are present (not None), renormalized."""
    present = {k: v for k, v in components.items() if v is not None}
    if not present:
        return None
    total_w = sum(weights.get(k, 0.0) for k in present)
    if total_w <= 0:
        return mean(present.values())
    return sum(v * weights.get(k, 0.0) for k, v in present.items()) / total_w


def levenshtein(a: Sequence[Any], b: Sequence[Any]) -> int:
    if a == b:
        return 0
    if not a:
        return len(b)
    if not b:
        return len(a)
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, start=1):
        current = [i]
        for j, cb in enumerate(b, start=1):
            cost = 0 if ca == cb else 1
            current.append(min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost))
        previous = current
    return previous[-1]


def _normalize_for_cer(text: str) -> str:
    return PUNCT_RE.sub("", text)


def _normalize_for_wer(text: str) -> List[str]:
    return [t for t in PUNCT_RE.sub(" ", text.lower()).split() if t]


def reference_similarity_score(
    candidate_text: str,
    reference_text: str,
    *,
    language_code: Optional[str],
) -> Optional[float]:
    """CER (CJK) / WER (Latin) → 0-100 similarity. None when either side is empty."""
    cjk = is_cjk_language(language_code)
    if cjk:
        cand = _normalize_for_cer(candidate_text)
        ref = _normalize_for_cer(reference_text)
        if not ref:
            return None
        err = levenshtein(list(cand), list(ref)) / max(1, len(ref))
    else:
        cand_t = _normalize_for_wer(candidate_text)
        ref_t = _normalize_for_wer(reference_text)
        if not ref_t:
            return None
        err = levenshtein(cand_t, ref_t) / max(1, len(ref_t))
    return _clamp((1.0 - err) * 100.0)


# ---------------------------------------------------------------------------
# Dimension result
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class DimensionScore:
    name: str
    score: Optional[float]               # None = 不可评（无任何分量）
    components: Dict[str, Optional[float]] = field(default_factory=dict)
    notes: List[str] = field(default_factory=list)
    capped: bool = False                 # 是否因缺语义裁判而被封顶
    verified: bool = False               # 是否有"金标准"分量(人工参考/LLM裁判/声学/场景真值)支撑；
                                         # 纯置信度+结构的高分是"健康但未验证"——自信乱码可能假性通过

    @property
    def passes(self) -> bool:
        return self.score is not None and self.score >= EXCELLENT_GATE

    @property
    def verified_pass(self) -> bool:
        return self.passes and self.verified


# ---------------------------------------------------------------------------
# 1. Recognition
# ---------------------------------------------------------------------------

def confidence_from_words(words: Sequence[Dict[str, Any]]) -> Optional[Dict[str, float]]:
    probs = [float(w.get("probability", 0.0)) for w in words if "probability" in w]
    if len(probs) < RUBRIC.confidence_min_words:
        return None
    avg = mean(probs)
    low_ratio = sum(1 for p in probs if p < RUBRIC.confidence_low_prob) / len(probs)
    return {"word_count": float(len(probs)), "avg_probability": avg, "low_conf_ratio": low_ratio}


def _confidence_score(stats: Optional[Dict[str, float]]) -> Optional[float]:
    if not stats:
        return None
    base = _linear_map(stats["avg_probability"], RUBRIC.confidence_floor_prob, RUBRIC.confidence_ceiling_prob, 0.0, 100.0)
    excess = max(0.0, stats["low_conf_ratio"] - RUBRIC.confidence_low_ratio_free)
    penalty = min(RUBRIC.confidence_low_ratio_penalty_cap, excess * RUBRIC.confidence_low_ratio_penalty)
    return _clamp(base - penalty)


def _structural_recognition_score(report) -> float:
    value = 100.0
    value -= min(RUBRIC.bad_scalar_penalty_cap, report.bad_scalar_ratio * RUBRIC.bad_scalar_penalty)
    value -= min(RUBRIC.repetition_penalty_cap, report.adjacent_identical_ratio * RUBRIC.repetition_penalty)
    value -= min(RUBRIC.romaji_loop_penalty_cap, report.romanized_loop_token_ratio * RUBRIC.romaji_loop_penalty)
    if report.cjk_language and report.visible_scalar_count >= 6:
        leak = max(0.0, report.latin_scalar_ratio - 0.10)
        value -= min(RUBRIC.cjk_latin_leak_penalty_cap, leak * RUBRIC.cjk_latin_leak_penalty)
    if report.cue_count >= 12 and report.unique_cue_text_ratio <= 0.25:
        value -= RUBRIC.low_unique_penalty * (0.25 - report.unique_cue_text_ratio) / 0.25
    return _clamp(value)


def recognition_score(
    *,
    candidate_cues: Sequence[Cue],
    language_code: Optional[str],
    words: Optional[Sequence[Dict[str, Any]]] = None,
    reference_text: Optional[str] = None,
    llm_accuracy_score: Optional[float] = None,
) -> DimensionScore:
    notes: List[str] = []
    report = source_quality_report(
        candidate_cues,
        requested_language_code=language_code,
        subtitle_language_code=language_code,
    )
    structural = _structural_recognition_score(report)

    conf_stats = confidence_from_words(words) if words else None
    confidence = _confidence_score(conf_stats)
    if words and confidence is None:
        notes.append("confidence:tooFewWords")

    ref_score: Optional[float] = None
    if reference_text:
        candidate_text = "\n".join(c.text for c in candidate_cues)
        ref_score = reference_similarity_score(candidate_text, reference_text, language_code=language_code)
        if ref_score is None:
            notes.append("reference:empty")

    components: Dict[str, Optional[float]] = {
        "reference": ref_score,
        "confidence": confidence,
        "structural": structural,
        "llm": llm_accuracy_score,
    }
    weights = {
        "reference": RUBRIC.w_reference,
        "confidence": RUBRIC.w_confidence,
        "structural": RUBRIC.w_structural,
        "llm": RUBRIC.w_llm_recognition,
    }
    score = _weighted(components, weights)
    if score is None:
        notes.append("recognition:noComponents")
    if report.reasons:
        notes.append("structuralReasons:" + ",".join(report.reasons))
    verified = ref_score is not None or llm_accuracy_score is not None
    if not verified:
        notes.append("unverified:needsReferenceOrLLM")
    return DimensionScore("recognition", score, components, notes, verified=verified)


# ---------------------------------------------------------------------------
# 2. Segmentation
# ---------------------------------------------------------------------------

def acoustic_boundary_agreement(
    cue_onsets: Sequence[float],
    speech_segments: Sequence[Dict[str, float]],
    *,
    tolerance: float = RUBRIC.seg_acoustic_tolerance_s,
) -> Optional[float]:
    """每个 cue 起点落在某个语音段边界（起或止）附近的比例 → 0-100。

    语音段边界来自能量 VAD（`vad.py`）。cue 起点贴近语音段起点=切在了说话开始处（好）；
    落在语音段**内部、远离任何边界**=很可能切在了词中（坏）。这就是用"音频波谱"判断分词。"""
    if not cue_onsets or not speech_segments:
        return None
    edges: List[float] = []
    for seg in speech_segments:
        edges.append(float(seg["start"]))
        edges.append(float(seg["end"]))
    edges.sort()
    if not edges:
        return None
    hits = 0
    for onset in cue_onsets:
        nearest = min(edges, key=lambda e: abs(e - onset))
        if abs(nearest - onset) <= tolerance:
            hits += 1
    return _clamp(hits / len(cue_onsets) * 100.0)


def _internal_segmentation_score(
    cues: Sequence[Cue],
    *,
    language_code: Optional[str],
) -> float:
    if not cues:
        return 0.0
    value = 100.0
    report = source_quality_report(
        cues, requested_language_code=language_code, subtitle_language_code=language_code
    )
    if report.long_cue_ratio > 0:
        value -= min(RUBRIC.seg_internal_long_cue_penalty, report.long_cue_ratio * RUBRIC.seg_internal_long_cue_multiplier)
    rows = preview_rows(cues, [], preview_seconds=float("inf"))
    weak = weak_boundary_candidates(rows, language_code=language_code)
    if cues:
        density = len(weak) / len(cues)
        value -= min(RUBRIC.seg_internal_weak_boundary_cap, density * 100.0 * RUBRIC.seg_internal_weak_boundary_penalty / 8.0)
    return _clamp(value)


def segmentation_score(
    *,
    candidate_cues: Sequence[Cue],
    language_code: Optional[str],
    reference_report: Optional[Dict[str, Any]] = None,
    speech_segments: Optional[Sequence[Dict[str, float]]] = None,
) -> DimensionScore:
    notes: List[str] = []
    internal = _internal_segmentation_score(candidate_cues, language_code=language_code)

    acoustic: Optional[float] = None
    if speech_segments:
        onsets = [c.start for c in candidate_cues]
        acoustic = acoustic_boundary_agreement(onsets, speech_segments)
        if acoustic is None:
            notes.append("acoustic:unavailable")

    # 人工参考的边界 F1 只作信息备注，**不计入分数也不算验证**：whisper 的切句风格天然不同于
    # 人工字幕(已证实结构性封顶~0.65,风格差异非缺陷),拿它当门会让分段永远不达标。公正的外部验证
    # 是声学一致性(切点落在真实停顿)。
    if reference_report:
        strong = float(reference_report.get("strong_boundary_recall", 0.0))
        aligned = float(reference_report.get("aligned_boundary_f1", reference_report.get("boundary_f1", 0.0)))
        notes.append(f"refInfo:strongRecall={strong:.2f},alignedF1={aligned:.2f}(notScored,styleCapped)")

    components: Dict[str, Optional[float]] = {
        "acoustic": acoustic,
        "internal": internal,
    }
    weights = {
        "acoustic": RUBRIC.seg_w_acoustic_when_present,
        "internal": RUBRIC.seg_w_internal_base,
    }
    score = _weighted(components, weights)
    verified = acoustic is not None
    if not verified:
        notes.append("unverified:needsAcoustic")
    return DimensionScore("segmentation", score, components, notes, verified=verified)


# ---------------------------------------------------------------------------
# 3. Translation
# ---------------------------------------------------------------------------

def _structural_translation_score(
    source_cues: Sequence[Cue],
    translated_cues: Sequence[Cue],
) -> float:
    if not translated_cues:
        return 0.0
    value = 100.0
    texts = [c.text.strip() for c in translated_cues]
    non_empty = [t for t in texts if t]
    empty_ratio = 1.0 - (len(non_empty) / len(texts) if texts else 0.0)
    value -= min(RUBRIC.translation_empty_penalty, empty_ratio * RUBRIC.translation_empty_penalty * 2.0)

    repeats = sum(1 for a, b in zip(non_empty, non_empty[1:]) if a == b)
    if len(non_empty) > 1:
        repeat_ratio = repeats / (len(non_empty) - 1)
        if repeat_ratio >= 0.20:
            value -= RUBRIC.translation_repeat_penalty

    romaji_leaks = sum(1 for t in non_empty if re.search(r"\b(?:ni|nani|dare|carano|ana|me|ani)\b", t, re.I))
    if non_empty and romaji_leaks / len(non_empty) >= 0.05:
        value -= RUBRIC.translation_romaji_leak_penalty

    if source_cues:
        diff = abs(len(translated_cues) - len(source_cues)) / max(1, len(source_cues))
        if diff > RUBRIC.translation_count_mismatch_threshold:
            value -= min(RUBRIC.translation_count_mismatch_penalty, diff * RUBRIC.translation_count_mismatch_penalty)
    return _clamp(value)


def translation_score(
    *,
    source_cues: Sequence[Cue],
    translated_cues: Sequence[Cue],
    llm_translation_score: Optional[float] = None,
) -> DimensionScore:
    notes: List[str] = []
    structural = _structural_translation_score(source_cues, translated_cues)
    capped = False
    if llm_translation_score is None:
        score = min(structural, RUBRIC.translation_structural_only_cap)
        if structural > RUBRIC.translation_structural_only_cap:
            capped = True
            notes.append("cappedNeedsLLMJudge")
    else:
        score = _weighted(
            {"llm": llm_translation_score, "structural": structural},
            {"llm": RUBRIC.w_llm_translation, "structural": 1.0 - RUBRIC.w_llm_translation},
        )
    return DimensionScore(
        "translation",
        score,
        {"structural": structural, "llm": llm_translation_score},
        notes,
        capped=capped,
        verified=llm_translation_score is not None,
    )


# ---------------------------------------------------------------------------
# 4. Source decision
# ---------------------------------------------------------------------------

def predicted_decision_for_gate(
    *,
    platform_usable: Optional[bool],
    platform_available: bool,
    local_asr_available: bool,
    cloud_available: bool,
    manual_available: bool = False,
) -> str:
    """Python 侧的决策镜像（M1 落地后由 Swift/C# `SubtitleSourceDecisionEngine` 取代为真值）。"""
    if manual_available:
        return "manual"
    if platform_available and platform_usable:
        return "platform"
    if local_asr_available:
        return "localASR"
    if cloud_available:
        return "cloudASR"
    if platform_available:
        return "platform"   # 不可用但无更好选择 → 沿用并提示
    return "none"


def source_decision_score(scenarios: Sequence[Dict[str, Any]]) -> DimensionScore:
    """对带"已知正确答案"的场景集打分：决策正确率 → 0-100。"""
    if not scenarios:
        return DimensionScore("source_decision", None, {}, ["noScenarios"])
    correct = 0
    failures: List[str] = []
    for sc in scenarios:
        predicted = predicted_decision_for_gate(
            platform_usable=sc.get("platform_usable"),
            platform_available=bool(sc.get("platform_available", False)),
            local_asr_available=bool(sc.get("local_asr_available", False)),
            cloud_available=bool(sc.get("cloud_available", False)),
            manual_available=bool(sc.get("manual_available", False)),
        )
        expected = sc.get("expected_decision")
        if predicted == expected:
            correct += 1
        else:
            failures.append(f"{sc.get('id', '?')}:exp={expected},got={predicted}")
    score = correct / len(scenarios) * 100.0
    notes = [f"{correct}/{len(scenarios)} correct"]
    if failures:
        notes.append("failures:" + "; ".join(failures[:8]))
    return DimensionScore("source_decision", score, {"accuracy": score}, notes, verified=True)


# ---------------------------------------------------------------------------
# Aggregation + render
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class SampleScorecard:
    sample_id: str
    language_code: str
    category: str
    dimensions: Dict[str, DimensionScore]


def suite_summary(samples: Sequence[SampleScorecard], source_decision: Optional[DimensionScore]) -> Dict[str, Any]:
    dim_names = ["recognition", "segmentation", "translation"]
    per_dim: Dict[str, Any] = {}
    for name in dim_names:
        dims = [s.dimensions[name] for s in samples if name in s.dimensions and s.dimensions[name].score is not None]
        scored = [d.score for d in dims]
        verified = [d.score for d in dims if d.verified]
        per_dim[name] = {
            "mean": round(mean(scored), 1) if scored else None,
            "scored_samples": len(scored),
            "verified_samples": len(verified),
            "verified_mean": round(mean(verified), 1) if verified else None,
            "pass_count": sum(1 for v in scored if v >= EXCELLENT_GATE),
            "verified_pass_count": sum(1 for d in dims if d.verified_pass),
            # 真正达标 = 已验证样本均分≥80 且验证覆盖足够(≥60%样本有金标准支撑)
            "passes_gate": bool(verified)
            and mean(verified) >= EXCELLENT_GATE
            and len(verified) >= max(1, int(0.6 * len(scored))),
            "passes_gate_unverified": bool(scored) and mean(scored) >= EXCELLENT_GATE,
        }
    if source_decision is not None:
        per_dim["source_decision"] = {
            "mean": round(source_decision.score, 1) if source_decision.score is not None else None,
            "scored_samples": 1 if source_decision.score is not None else 0,
            "verified_samples": 1 if source_decision.verified else 0,
            "verified_mean": round(source_decision.score, 1) if source_decision.score is not None else None,
            "pass_count": 1 if source_decision.passes else 0,
            "verified_pass_count": 1 if source_decision.verified_pass else 0,
            "passes_gate": source_decision.verified_pass,
            "passes_gate_unverified": source_decision.passes,
        }
    overall_means = [d["mean"] for d in per_dim.values() if d["mean"] is not None]
    return {
        "excellent_gate": EXCELLENT_GATE,
        "sample_count": len(samples),
        "dimensions": per_dim,
        "overall_mean": round(mean(overall_means), 1) if overall_means else None,
        "all_dimensions_pass": all(d["passes_gate"] for d in per_dim.values()) if per_dim else False,
        "all_dimensions_pass_unverified": all(d["passes_gate_unverified"] for d in per_dim.values()) if per_dim else False,
    }


def render_markdown(samples: Sequence[SampleScorecard], summary: Dict[str, Any]) -> str:
    lines = ["# Moongate 字幕质量 Scorecard", ""]
    lines.append(f"门禁：各维 ≥ {summary['excellent_gate']:.0f} 分（优秀）。样本数：{summary['sample_count']}。")
    lines.append("")
    lines.append("## 汇总")
    lines.append("")
    lines.append("| 维度 | 均分 | 已评 | 已验证 | 验证均分 | ≥80 | 门禁(验证) |")
    lines.append("|---|---:|---:|---:|---:|---:|:---:|")
    label = {
        "recognition": "识别 recognition",
        "segmentation": "分段 segmentation",
        "translation": "翻译 translation",
        "source_decision": "源决策 source_decision",
    }
    for name, data in summary["dimensions"].items():
        mark = "✅" if data["passes_gate"] else "❌"
        mean_str = f"{data['mean']:.1f}" if data["mean"] is not None else "—"
        vmean_str = f"{data['verified_mean']:.1f}" if data.get("verified_mean") is not None else "—"
        lines.append(
            f"| {label.get(name, name)} | {mean_str} | {data['scored_samples']} | "
            f"{data.get('verified_samples', 0)} | {vmean_str} | {data['pass_count']} | {mark} |"
        )
    overall = f"{summary['overall_mean']:.1f}" if summary["overall_mean"] is not None else "—"
    lines.append("")
    lines.append(f"**总体均分：{overall}　全维达标(经验证)：{'是 ✅' if summary['all_dimensions_pass'] else '否 ❌'}**")
    lines.append("")
    lines.append("> 门禁口径：仅当有金标准分量（人工参考 / LLM 裁判 / 声学 / 场景真值）支撑、且验证覆盖 ≥60% 样本时才算达标。")
    lines.append("> 纯置信度+结构的高分标为「未验证」——自信乱码可能假性通过，需 agent 补 LLM 裁判或人工字幕对照。")
    lines.append("")
    lines.append("## 逐样本")
    lines.append("")
    lines.append("| sample | 语言 | 类型 | 识别 | 分段 | 翻译 |")
    lines.append("|---|---|---|---:|---:|---:|")
    for s in samples:
        def cell(name: str) -> str:
            dim = s.dimensions.get(name)
            if dim is None or dim.score is None:
                return "—"
            flag = "·封顶" if dim.capped else ""
            return f"{dim.score:.0f}{flag}"
        lines.append(
            f"| {s.sample_id} | {s.language_code} | {s.category} | "
            f"{cell('recognition')} | {cell('segmentation')} | {cell('translation')} |"
        )
    lines.append("")
    return "\n".join(lines) + "\n"
