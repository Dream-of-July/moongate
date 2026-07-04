# 分段/可读性只读 EVAL（用 App 自带评测框架跑真实样本）

用项目自带的 `tools/subtitle_timing_eval` 的 `evaluate_readability`（语言感知阈值：CJK max_cps 11，拉丁 max_cps 21，取自 TED/Netflix 字幕规范；检测 too_fast / flash_too_short / lingers_too_long / too_long_to_fit / weak_boundary / orphan / overlap）对本机真实样本做只读评测。**未改算法、未改阈值、未改任何输出。**

## 结论先行
- **local-ASR 产出分段质量优秀**：华为(zh) 99% cue 达标（中位 CPS 6.0），群青(ja) 100% 达标——印证"local-ASR 已人类水平分段"在真实样本上成立。
- **一处真实信号 + 一处度量口径缺陷**：英文平台字幕/译文倾向长行+快节奏；但直接用单语阈值 + 对双语文件把两行字符都计入，会**高估**问题。两者都需 eval 口径修正后才能下结论，非本轮自主改。

## 数据（3 样本）
| 样本 | cues | 语言 | 中位CPS | 达标率 | 主要 flag |
|---|---|---|---|---|---|
| 华为(local-asr) | 469 | zh-Hans | 6.0 | **99%** | 个位数(3 too_fast/1 flash/1 weak) |
| 群青(local-asr) | 56 | ja | 3.1 | **100%** | 无 |
| Spotify(平台/译文) | 392 | en(双语文件) | 18.4 | 8% | 329 too_long_to_fit / 115 too_fast |

## 关键辨析（避免误导性结论）
1. **Spotify 的 8% 是被高估的**：该文件是 `.en.zh-Hans` **双语**（中文译文 + 英文原文两行），`evaluate_readability` 把两行字符都计入单条 cue 时长算 CPS，且用单语 `max_chars_per_line` 判 too_long——对双语 cue 是**度量口径不匹配**。真实**烧录**输出用 ASS 双语两级字号（译文正常、原文 80%），显示预算问题被缓解。故 8% 不代表用户实际观感那么差。
2. **但底层信号仍真实**：英文语音的平台字幕/译文本就倾向长行、语速快（CPS 高）。而 App 目前对平台字幕的质量检测（`SubtitleTimingHealth` 只测 <0.25s 闪现 cue；`PlatformSubtitleQualityGate` 测 coverage/garbled/language）**不覆盖 too_fast/too_long 这类可读性问题**——一个"可读但分段糟"的平台字幕会静默通过所有门，用户烧出来难读，且无"建议改用 local-ASR"的提示（该提示目前只由闪现 cue 触发）。

## 判断与建议（非本轮自主改）
- **local-ASR 分段无需改**：客观达标 99-100%。
- **两个候选增强（需 eval 先行，属算法/体验层改动，交七月）**：
  1. `evaluate_readability` 增加**双语 cue 感知**（分行按各自语言/字号阈值判，而非合并计数）——先修度量口径，否则任何基于它的产品判断都会偏。属评测工具改进，风险低但需验证不破坏现有 baseline。
  2. 若要让用户在"平台字幕可读性差"时得到提示：扩展 `SubtitleTimingHealth` 或质量门，除闪现外也识别持续 too_fast/too_long，触发温和的"建议 local-ASR 重识别"。但这会**改变 timingWarning 的触发面**（更多项显示提示），需 eval 调阈值避免对英文内容过度告警（英文 CPS 天然偏高）——是用户可见行为变更，需七月定。

## 停机依据（本维度）
分段质量在 local-ASR 路径客观达标；平台字幕可读性提示是有价值但需 eval 先行的行为变更，非低风险自主项。度量口径（双语）缺陷已识别并记录。字幕分段核心（算法层）已有充分测试（SubtitleTimingPlannerTests / SubtitleTimingHealthTests）+ eval 框架，非本次体验层范围。

## 复现
```bash
cd tools/subtitle_timing_eval && python3 -c "
import sys; sys.path.insert(0,'.')
from subtitle_timing_eval.srt import parse_srt
from subtitle_timing_eval.readability import evaluate_readability
cues=parse_srt(open('<SRT路径>',encoding='utf-8').read())
print(evaluate_readability(cues,'x',language='zh-Hans')['median_reading_speed_cps'])
"
```
