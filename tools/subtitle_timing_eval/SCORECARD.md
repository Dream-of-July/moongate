# Moongate 字幕质量 · 可量化测试标准（Scorecard）

把"字幕好不好"拆成四个可独立打分（0–100）、可分别设 **≥80 分（优秀）门禁**的维度，并区分
**「未验证」**（仅靠模型自信度+结构启发式）与**「已验证」**（有人工参考 / LLM 裁判 / 声学 /
场景真值支撑）。门禁只认**已验证**分数——因为"自信乱码"会让纯置信度高分假性通过。

代码：`subtitle_timing_eval/scorecard.py`（纯函数，222 单测）。运行器：`run_scorecard_baseline.py`。

---

## 四个维度

### 1. recognition 识别准确率
语音→文字转得对不对。分量（缺失则按存在分量重新归一）：
- **confidence**（自动）：来自 whisper `words.json` 的词级 `probability`，镜像 `LocalASRConfidence`
  （avg_prob 映射 + 低置信词占比惩罚；<24 词不可评）。
- **structural**（自动）：镜像 `PlatformSubtitleQualityGate` 的乱码/重复/罗马音泄漏/CJK 拉丁混入/低唯一率惩罚。
- **reference**（金标准）：存在人工 `*.clean.srt` 时算 CER（CJK 字符级）/ WER（拉丁词级）相似度。
- **llm**（金标准）：agent 读输出、必要时对照在线人工字幕后写入 `agent_recognition_judge.json` 的 `accuracyScore`。
- `verified` = 有 reference 或 llm。纯 confidence+structural 标 `unverified:needsReferenceOrLLM`。

### 2. segmentation 分段/分词准确率
切句切词的位置对不对。
- **internal**（自动）：过长 cue 比例 + 悬空助词/词中断候选密度（`weak_boundary_candidates`）惩罚。
- **acoustic**（金标准）：能量 VAD（`vad.py`，即"看音频波谱"）求语音段边界，统计 cue 起点落在
  语音段起/止 ±0.4s 的比例。切点贴边=切在说话起止处（好）；落段中远离边界=很可能切在词中（坏）。
- 人工参考边界 F1 **只作信息备注、不计分也不算验证**：whisper 切句风格天然异于人工字幕，已证实
  结构性封顶 ~0.65（风格差异非缺陷），拿它当门会让分段永远不达标。
- `verified` = 有 acoustic。
- ⚠️ **音乐例外**：连续音乐会被能量 VAD 整段当"语音"，cue 起点落段中→声学分偏低且不公正。
  音乐类分段以 **agent LLM 裁判**为准（见 runbook），声学分仅供演讲/对白/动漫参考。

### 3. translation 翻译准确率
- **structural**（自动）：空译文/重复译文/罗马音泄漏/严重 cue 数失配（阈值 0.5，重分段 43→29 合法不罚）惩罚。
- **llm**（金标准，主导 0.7）：agent 写入 `agent_translation_judge.json` 的 `score`（忠实度+通顺+一致+逐字保留）。
- 无 LLM 裁判时翻译分**封顶 75**（`cappedNeedsLLMJudge`）——结构无法认证语义优秀。

### 4. source_decision 源决策正确率
"用平台字幕 / 本地 Whisper / 云端"选得对不对。
- 对 `source_decision_scenarios.json`（带已知正确答案的可执行规格）打分，决策正确率→0–100。
- M0 用 Python 镜像 `predicted_decision_for_gate`；**M1 落地后，Swift/C# `SubtitleSourceDecisionEngine`
  必须在同一份场景上得同样结果**（交叉校验实现符合规格）。
- `verified` = True（场景真值）。

---

## 门禁口径

某维"达标"当且仅当：**已验证样本均分 ≥80** 且**验证覆盖 ≥60% 已评样本**。
`all_dimensions_pass` 要求四维全部经验证达标。同时输出 `*_unverified` 口径供对照（看自动floor）。

---

## 运行

```bash
cd tools/subtitle_timing_eval
python3 -m unittest discover -s tests -p "test_*.py"          # 222 测试
python3 run_scorecard_baseline.py                             # 扫缓存,产 scorecard.json/.md
python3 run_scorecard_baseline.py --acoustic                  # 额外算声学(需 ffmpeg,演讲类才公正)
python3 run_scorecard_baseline.py --roots ted_school_creativity_en italian_talk_public_it
```
产物：`artifacts/subtitle_timing_eval/scorecard/scorecard.{json,md}`。

---

## Agent 评分 Runbook（语义维度由 agent 补金标准，七月免手工标注）

对每个要认证 ≥80 的样本：
1. **找在线人工字幕**：能找到官方/字幕组人工字幕→存为 `<dir>/*.clean.srt`，识别维度自动算 CER/WER（已验证）。
2. **识别 LLM 裁判**（无人工参考或需复核时）：实际读 `local-asr.<lang>.srt`，按语言通顺性+内容合理性
   判断转写对不对（重点抓"自信乱码"：置信度高但听错，如青花瓷/BLACKPINK）。写
   `<dir>/agent_recognition_judge.json`：`{"accuracyScore": 0-100, "issues":[...], "notes":"..."}`。
3. **翻译 LLM 裁判**：读 `translated.srt` 对 final source，判断忠实/通顺/术语人物一致/歌词逐字保留。写
   `<dir>/agent_translation_judge.json`：`{"score": 0-100, "adequacy":..,"fluency":..,"issues":[...]}`。
4. **分段**：演讲/对白/动漫看声学分；音乐看 LLM 裁判（断句是否落在乐句/语义边界、有无词中断）。
5. 重跑 `run_scorecard_baseline.py` 合并裁判，看 `scorecard.md` 的「门禁(验证)」列。

判分尺度：90+ 几乎无误可直接用；80–89 个别小错不碍理解；60–79 多处错或断句碎；<60 乱码/错源/不可用。
保守诚实：宁可标低并写明原因，绝不为凑分放水。

---

## 当前基线（2026-06-29，缓存 49 样本；详见 scorecard.md）

| 维度 | 未验证均分 | 已验证均分 | 说明 |
|---|---:|---:|---|
| recognition | ~87 | ~75 | 自动 floor 虚高；有人工参考处真实 ~75，未达 80 |
| segmentation | ~91 | 演讲 ~74 / 音乐 ~45 | 声学验证；演讲可冲，音乐需 LLM 裁判 |
| translation | 73.6(封顶) | — | 全部待 agent LLM 裁判 |
| source_decision | 100 | 100 | 规格自洽；M1 引擎须交叉达标 |

**结论**：四维框架就位、可量化、能区分好坏（已知乱码样本全落低分区）。冲 80 的真实工作量在
线 B（识别）/ 线 A（源决策）/ agent 逐样本 LLM 裁判（识别+翻译）。
