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

- **R1 字幕大小调节 ✅ f865d0f**：SubtitleFontScale(小/标准/大/特大=0.82/1.0/1.24/1.5×)贯穿全链，standard=1.0保兼容。同commit收尾Bilibili字幕登录提示WIP。
- **R2 空状态+信息卡 ✅ caafa4a**：emptyState HIG级首屏(层级+支持平台提示+动效尊重reduce-motion)，infoCard缩略图浮起+monospacedDigit，cardBackground描边两模式。
- **R3 队列项视觉 ✅ be65cf2**：缩略图0.5pt描边统一+标题body/medium层级，零逻辑改动。
- **R4 语言标签bug修复（进行中）**：yt-dlp错报language:en污染链(Engine.swift:1044→detectedLanguageCode→源语言auto回落→产物命名)。A层修复(不动算法)：命名关口用ScriptDetector.profile校正,内容脚本与标签强矛盾时用真实语言覆盖。改ASR.swift+新测试。
- **R5 design token层（进行中）**：新建DesignTokens.swift(Spacing/Radius/Thumbnail/Stroke贴合HIG),等价替换ContentView+QueueItemView魔法数字(零视觉变化),为三栏重构铺垫。
- R6+ HIG三栏主线：单列→NavigationSplitView两栏 / 队列浮层→sidebar主列表 / 进度环画进列表行。大重构,分步推进(详见 memory moongate-hig-3pane-research)。

### R7+ 候选池（按 HIG 优先级 + 独立性）
- **R6 三栏原型（进行中）**：SplitLayoutView.swift，feature-flag `experimental.splitLayout` 默认off。左sidebar列表(缩略图+标题+ProgressRingView进度环)+右detail(预览框+播放overlay+功能按钮)。复用QueueManager操作。不破坏现有ContentView。
- R7 候选(独立文件,与R6可能ContentView冲突需错开)：字幕样式实时预览 inspector(P3,CapCut式,九宫格锚点+相对档位+preset)｜统一loading/failed/需登录状态视觉(P3,ContentView)｜DependencySetupView/LoginWebView 采用design token+视觉精修(独立文件)｜SettingsView 视觉精修与token化｜Parabolic式"添加任务"对话框(P2)｜choosingState多视频选择页卡片化(ContentView)。
- 原则：ContentView 已被R2/R5/R6反复触及,后续避免继续churn它,优先独立文件轮次;三栏成熟后再考虑切换默认。

### 已提交轮次汇总
- R1 f865d0f 字幕大小 / R2 caafa4a 空状态+信息卡 / R3 be65cf2 队列项 / R4 e39ec29 语言标签bug修复 / R5 9922757 design token / R6 d8341b0 三栏原型(feature-flag)
- **R7 字幕位置调节（进行中）**：SubtitlePosition(底部/顶部,assAlignment 2/8)照R1模式贯穿 Models/Settings/Burner(ASS Style Alignment)/QueueManager/CLI/SettingsView+三语+BurnerAssTests。默认bottom保兼容。
- R8 候选：DependencySetupView token化+视觉精修(20个硬编码值,不需新文案,与R7零冲突)｜LoginWebView同｜字幕样式实时预览inspector。

### 已提交 R1-R8 + 进行中
- R1 f865d0f 字幕大小 / R2 caafa4a 空状态 / R3 be65cf2 队列项 / R4 e39ec29 语言bug / R5 9922757 token / R6 d8341b0 三栏原型 / R7 ef4f7c1 字幕位置 / R8 0bc1fca 首次使用路径(依赖+登录)精修
- **R9 字幕样式实时预览（进行中）**：SettingsView styleSection 加 SubtitleStylePreview(16:9深色模拟视频,按style/fontScale/position实时渲染双语示例字幕,CapCut式WYSIWYG),闭合字幕调节反馈环。仅SettingsView+本地化。
- R10+ 候选：三栏原型完善(statusText/添加流程)｜loading/failed状态统一(ContentView,慎churn)｜SettingsView 全量token化｜画质选择清晰度(formatRows)｜choosingState卡片化。

### R10-R12
- R10 `7ed73ee`：修R8遗漏的测试回归(MacOSDependencyBoundaryTests字面量锚点)。全量713测试绿检查点。**教训:改View源码必跑对应boundary测试**。
- R11 `38b7393`：QueueOverlayView+QueueSectionView token化+handle描边/阴影克制微调。MacOSQueueBoundaryTests 20绿。
- **R12 加载/选择/失败状态统一（进行中）**：loadingState/choosingState/failedState 向emptyState视觉语言看齐(三级层级+hierarchical图标+token+呼吸感)。仅ContentView,跑MacOSContentBoundaryTests验证。
- 关键流程:每轮改View源码→跑对应Boundary测试(MacOS{Content,Queue,Dependency,Login,ViewModel,App}BoundaryTests扫描源码字面量)。
- R12 `40e3298`：loadingState/choosingState/failedState 统一到emptyState视觉语言(三级层级+hierarchical图标+token)。MacOSContentBoundaryTests 17绿。
- **R13 三栏原型状态完善（进行中）**：SplitLayoutView detail statusText复用QueueItemView丰富逻辑(下载%·速度·剩余/ASR三子阶段/翻译烧录转码%/暂停/部分成功/failed)+detail进度条+sidebar行状态,复用L.Queue.*文案。让三栏原型可真实评估。
- R13 `8cb53b1` 完成 / R14 `1ce16d6` 设置画质区行对齐修复(styleSection已理想不改) / **R15(进行中)** onboarding首启引导步骤指示器增强+token(第一体验),MacOSContentBoundaryTests验证。
- 剩余候选:网页下载/性能(偏core慎)｜画质选择已够｜三栏"添加"真实流程(需先做ViewModel快速添加能力,是产品决策非小切片,暂缓)。

### R16-R18 + 里程碑
- R16 sidebar按状态分Section(进行中/已完成+计数) / R17 键盘快捷键(New Download Cmd+L, Paste&Parse Cmd+Shift+V)
- **Release build 里程碑**：17轮后 `swift build -c release --product Moongate` 干净通过(exit 0,无error/warning)——所有UI改动release-ready。
- R18(进行中):readyState配置页token采用收尾(补完token覆盖,零视觉变化)。

### R18-R27（突破20轮,持续找真问题）
- R18 配置页token收尾+Layout.readableContentWidth / R19 验收总结文档 / R20 choosingState maxWidth统一 + **运行时验证里程碑**(隔离app打包启动稳定=首次运行时验证) / R21 三栏"添加"真实化(addTasks复用processBatch+add sheet) / R22 字幕预览a11y / R23 三栏detail加载态 / R24 抽VideoThumbnail共享组件(3处) / R25 去emptyDetailSubtitle尾句号 / R26 字幕颜色白/黄(+预览) / R27 ready页深链到字幕外观设置(requiresBurnIn时→subtitles pane)。
- 累积:716测试全绿(多检查点),debug&release build绿,CLI正常,0警告,Dynamic Type无隐患,文案自然。核心缺口已系统覆盖,继续找边际真问题。

## 5. 风险与回滚

每轮独立小 commit，可回滚。每轮 `swift build --product Moongate` 验证，涉及 Core 逻辑加/更新单测。

## 6. 进度记录

- 2026-07-03：建分支，摸清架构，绿基线 build 确认。
- R1 启动：字幕大小调节，已派 implementation_worker（spec 含精确 file:line + 设计决策 + 验证要求）。触及文件：Models/Settings/Burner/QueueManager/main.swift/SettingsView + Localization×4 + 新测试。
- R2 候选（ContentView 独立，与 R1 无文件重叠）：emptyState 升级为 HIG 级空状态 + infoCard/cardBackground 原生材质化。待研究 agent HIG 成果并入后细化。

### 真实 bug 发现（七月提供的实际产出样本）
- **语言标签错误（P1）**：Bilibili 中文视频（华为 Mate 80 Pro 评测 BV1F7T46wEyT）本地 ASR 产出 `...local-asr.en.srt`，但内容全是中文。语言标签 `en` 与内容 `zh` 不符。危害：误导用户 + 可能污染下游翻译源语言判断。已派只读诊断 agent 追根因（区分"检测对但标签错" vs "源语言默认成en" vs "detected解析失败fallback en"）。本样本只有源字幕无译文（用户走了直接烧录路径），但标签 bug 需修。
  - 次要观察（不修，算法已定型）：识别有 `九牛二虎之力→9妞二虎之力`、`SoC→So C`、`9030→90 30` 数字拆分等小瑕疵。
