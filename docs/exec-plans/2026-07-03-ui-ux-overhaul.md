# Moongate UI/UX Overhaul — 多轮迭代 ExecPlan

分支：`ui-ux-overhaul`（从 master `3d57cf9` / 0.8.2）
起始：2026-07-03
授权：七月 `/goal` 全权，自主迭代 10-20 轮，明早验收。

## 1. 背景与产品意图

Moongate 是成熟的 macOS SwiftUI 视频下载+转写+字幕工具（0.8.2 已发布，核心算法已达人类水平、无显著提分空间——见 memory `moongate-082-codereview-release`）。本次目标是**纯产品体验层**朝"苹果原生软件级"重构，不动已调优算法。

北极星（七月明确）：改成 macOS 备忘录式三栏——左列视频列表（标题+进度环，未完成显示半圆进度），右侧预览框+一排功能按钮。分轮推进，不急于一次到位。

## 2. 当前架构（重构起点）

- 单窗口 560×780（App.swift）。ContentView(1815行) = 单栏线性流：header(URL输入) → content 状态机(idle/resolving/analyzing/choosing/ready/failed) → 底部 QueueOverlayView 浮层（收起=右下角进度环把手，展开=铺满）。
- 已有可复用资产：`ProgressRingView`（进度环）、`QueueItemView`（缩略图+标题+进度条+按钮组，已是列表项雏形）、`QueueSectionView`（LazyVStack 列表）、SettingsView 已用 `NavigationSplitView` 三栏范式 + 成套 SF Symbols。
- QueueItem 数据模型丰富：info(VideoInfo 含缩略图/时长/上传者/描述/格式)、resultFiles、resolvedSubtitleSource、完整进度状态。
- 字幕烧录：Burner.makeASS(cues:aspect:)，字号基准 `chineseFontSize=13` 硬编码，按宽高比自适应但用户不可调。

## 3. 目标与非目标

目标：从首启到完成的每条路径，逐轮提升到苹果级 UX。字幕大小/样式/画质调节、下载体验、性能、空/错/载状态、动效、可访问性。
非目标：改核心算法；改发布流程；RS-02 仓库改名（需七月亲授权）。

## 4. 迭代路线（滚动更新）

- **R1 字幕大小调节**（进行中）：新增 `subtitleFontScale` 设置（小/标准/大/特大），贯穿 Settings→AppSettings→Burner.makeASS。用户点名需求，路径已摸清。
- R2+ 待研究 agent（HIG/竞品 + 架构地图）成果并入后细化。候选：ready 页信息层级重排、队列项视觉升级、空状态引导、动效统一、三栏 detail 预览原型。

## 5. 风险与回滚

每轮独立小 commit，可回滚。每轮 `swift build --product Moongate` 验证，涉及 Core 逻辑加/更新单测。

## 6. 进度记录

- 2026-07-03：建分支，摸清架构，绿基线 build 确认。
- R1 启动：字幕大小调节，已派 implementation_worker（spec 含精确 file:line + 设计决策 + 验证要求）。触及文件：Models/Settings/Burner/QueueManager/main.swift/SettingsView + Localization×4 + 新测试。
- R2 候选（ContentView 独立，与 R1 无文件重叠）：emptyState 升级为 HIG 级空状态 + infoCard/cardBackground 原生材质化。待研究 agent HIG 成果并入后细化。

### 真实 bug 发现（七月提供的实际产出样本）
- **语言标签错误（P1）**：Bilibili 中文视频（华为 Mate 80 Pro 评测 BV1F7T46wEyT）本地 ASR 产出 `...local-asr.en.srt`，但内容全是中文。语言标签 `en` 与内容 `zh` 不符。危害：误导用户 + 可能污染下游翻译源语言判断。已派只读诊断 agent 追根因（区分"检测对但标签错" vs "源语言默认成en" vs "detected解析失败fallback en"）。本样本只有源字幕无译文（用户走了直接烧录路径），但标签 bug 需修。
  - 次要观察（不修，算法已定型）：识别有 `九牛二虎之力→9妞二虎之力`、`SoC→So C`、`9030→90 30` 数字拆分等小瑕疵。
