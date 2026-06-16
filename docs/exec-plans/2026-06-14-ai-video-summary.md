# macOS：AI 视频内容总结 + AI 设置统一化

## 背景与产品意图
用户在「选分辨率/准备下载」页常常担心下错视频。要在该页加一个 **AI 总结视频内容** 功能，让用户下载前先确认这是不是想要的视频。

同时把设置里的「翻译服务」升级成统一的 **AI 设置**：有一份「默认 AI 配置」，翻译和总结各是一个独立开关，可「跟随默认」或「单独配置」，避免重复填同一套 API。

附带：依赖配置窗里的「删除依赖」按钮改成红色警示色（已实现，待最终验证）。

## 关键决策（已与用户确认）
- 总结数据源：**优先字幕**（总结时现拉一次 `yt-dlp --skip-download` 字幕文本），拿不到则回退 `标题+视频简介`。
- 引擎选择：统一成「AI 设置」——共享默认配置 + 翻译/总结各自「跟随默认 or 单独配置」两个独立开关。
- Apple Translation 引擎只能翻译、不能生成文本，**不能用于总结**；选它做总结时给出明确不可用提示，不假装可用。

## 现状勘察（file:line）
- 翻译 LLM 调用全在 `Translator.swift`：`sendConfiguredMessage`(271)、`sendAnthropicMessage`(420)、`sendOpenAIResponse`(521)、`sendFoundationModelsMessage`(309)、`ModelReply`(266)。均按 `settings.translationEngine/BaseURL/Model/AuthToken` 工作，无字幕专属逻辑，可复用做总结。`testTranslationConnection`(637) 是现成的 public 包装范例。
- `AppSettings`(Settings.swift:6) 自定义 `init(from:)`(78) 全用 `decodeIfPresent ?? 默认`，新增字段迁移安全；`CodingKeys`(73)。
- `VideoInfo`(Models.swift:105) 无 `description`；`Engine.buildVideoInfo`(561) 未解析 `json["description"]`（yt-dlp JSON 实际含此字段）。ViewModel 有两处手动重建 VideoInfo（292、416）。
- 字幕正文目前只在 `Engine.download()`(860) 随视频落地；无「只取字幕文本」入口，但可复用 `runYtDlpJSON` 的进程封装 + cookie 注入 + `parseSRT`(Translator.swift:19)/`cleanCues`(119) 新增轻量抓取。
- Ready 页在 `ContentView.readyState`(270)；`infoCard`(702)。设置翻译区在 `SettingsView.translationSection`(185)。
- 删除按钮已改红色：`DependencySetupView.swift:247`（`.tint(.red)`+`.foregroundStyle(.red)`），已编译通过。

## 目标 / 非目标
**目标**
1. 删除依赖按钮红色警示（已做）。
2. Ready 页新增「AI 总结内容」：按需生成，结果就地展示，含 idle/running/done/failed 状态。
3. 设置统一为「AI 设置」：默认配置 + 翻译开关（跟随/单独）+ 总结开关（跟随/单独）。
4. 总结数据源优先字幕、回退简介；Apple Translation 引擎做总结时明确不可用。
5. 迁移零回归：老用户的翻译配置行为完全不变。

**非目标**
- 不把总结做成下载流水线的固定 stage（按需触发即可）。
- 不改 Windows/Android/iOS 侧（仅 macOS 分支；core 改动保持跨平台可编译）。
- 暂不强求 CLI 总结子命令（可选，列为 M5 可选项）。

## 方案与取舍

### 设置数据模型（三槽位，加法式，迁移安全）
在 `AppSettings` 新增：
- 默认槽：`aiEngine, aiBaseURL, aiModel, aiAuthToken`
- 翻译槽开关：`translationFollowsDefault: Bool = true`（沿用现有 `translation*` 作为「单独配置翻译」的覆盖存储）
- 总结槽：`summaryFollowsDefault: Bool = true` + `summaryEngine, summaryBaseURL, summaryModel, summaryAuthToken`

新增计算属性 `effectiveTranslationConfig` / `effectiveSummaryConfig` → 返回 `LLMEndpointConfig{engine,baseURL,model,authToken}`：跟随默认时取 ai*，否则取各自覆盖槽。

**迁移**：`init(from:)` 里 ai* 缺键时用现有 `translation*` 值播种，`translationFollowsDefault` 默认 true → 有效翻译配置 = ai* = 旧 translation 值，行为完全不变。所有新字段 `decodeIfPresent ?? 默认`。

取舍：相比直接把 `translation*` 重命名为 `ai*`（会大改 CLI/测试/工厂），加法式三槽位churn 更小、迁移更稳，代价是多 10 个字段。

### LLM 调用重构（Translator.swift 内部，受控）
引入 `struct LLMEndpointConfig`（engine/baseURL/model/authToken），把 `sendAnthropicMessage/sendOpenAIResponse/sendConfiguredMessage` 从「读 settings」改为「读 config」。翻译路径传 `effectiveTranslationConfig`，总结传 `effectiveSummaryConfig`。新增 `public func summarizeVideo(...)`，内部调 `sendConfiguredMessage(config:...)`。保持对外行为不变。

### 字幕文本抓取（Engine.swift）
新增 `public func fetchSubtitleText(url:preferredLang:control:) async throws -> String?`：`yt-dlp --skip-download --write-subs --write-auto-subs --convert-subs srt` 到临时目录 → `parseSRT`+`cleanCues` → 拼成纯文本（截断到合理长度）。复用进程/cookie 封装。最佳努力：无字幕返回 nil，不抛错；登录墙走现有 `detectLoginRequired`。

### 总结生成
`summarizeVideo(info:subtitleText:config:control:)`：组 system（"用简体中文，3-5 句概括视频主要内容，帮助用户判断是否是想要的视频，不要编造"）+ user（标题/作者/时长 + 字幕文本或简介）。`maxTokens` 给足（~1500）。engine 不能生成文本（Apple Translation 各档）时抛明确错误。

### UI
- **设置**：`translationSection` → 重构为 `aiSection`（标题「AI 设置」）。默认配置块（engine/baseURL/model/token + 拉取模型 + 测试连接，绑 ai*）。翻译子区：Toggle「单独配置翻译」off=跟随；on 显示覆盖字段。总结子区：Toggle「单独配置总结」off=跟随；on 显示覆盖字段 + Apple Translation 不可总结提示。Apple readiness 块按使用 Apple 引擎的槽位显示。
- **Ready 页**：`infoCard` 下方加「AI 总结内容」按钮 + 结果卡片（SummaryState）。总结不可用（未配置/引擎不能生成）时按钮禁用并给原因。

### ViewModel
`@Published private(set) var summaryState: SummaryState`（idle/running/done(String)/failed(String)）、`summaryTask: Task<Void,Never>?`、`func summarizeCurrentVideo()`：抓快照 settings + 当前 VideoInfo，先 fetchSubtitleText 回退 description，再 summarizeVideo；错误 pattern-match `MoongateError.translateFailed`。仿现有 readiness/connection-test 模式。

## 里程碑与验证
- **M1 核心数据模型**：AppSettings 三槽位 + effective 计算属性 + LLMEndpointConfig 重构 + 迁移。验证：`swift test --filter TranslationSettingsTests`，新增迁移 round-trip + effective 解析用例；`swift build`。
- **M2 总结核心**：VideoInfo.description（+Engine 解析 +2 处重建点）；Engine.fetchSubtitleText；summarizeVideo + 引擎守卫。验证：core 单测（prompt 组装、Apple 引擎守卫、description 透传）；`swift build --product moongate-cli`。
- **M3 设置 UI**：aiSection 重构 + 两个跟随开关。验证：更新 MacOSSettingsBoundaryTests；`swift build --product Moongate`。
- **M4 Ready 页总结 UI + ViewModel**：按钮+结果卡片+SummaryState。验证：boundary 测试覆盖按钮存在/禁用门控；构建。
- **M5 收尾**：删除按钮红色最终验证；全量 `swift test`；`./build.sh` 装 /Applications；手测总结 happy/无字幕/未配置/Apple引擎/取消。可选 CLI 总结。

## 风险与回滚
- 迁移回归：M1 必须有「老 translation 配置 → 有效翻译配置不变」round-trip 测试兜底。
- Boundary 测试是源码字符串断言，UI 重构会动多条——逐条按新结构更新（之前已处理过同类）。
- `--skip-download` 可能遇登录墙/耗时：总结按需触发、可取消、失败回退简介，不阻塞下载主流程。
- Apple Translation 不能总结：UI/core 双重守卫，诚实提示。
- 每个里程碑独立可编译可测；任一里程碑出问题可停在前一个稳定点。

## 决策日志
- 数据源「优先字幕、现拉、回退简介」：用户确认。
- 引擎「统一 AI 设置 + 翻译/总结独立开关 + 跟随默认」：用户确认。
- 删除按钮红色：用户要求，已实现。

## 待确认
- CLI 是否需要总结子命令（M5 可选，默认先不做）。

## 进度日志
- 2026-06-14：M1-M5 全部完成。
  - M1：AppSettings 加 ai*/summary* 三槽位 + translationFollowsDefault/summaryFollowsDefault + effectiveTranslation/SummaryConfig + LLMEndpointConfig + canGenerateText；迁移零回归（旧 translation 配置播种默认 AI 配置）。+4 测试。
  - M2：VideoInfo.description（Engine 解析 + 2 处重建点透传）；Engine.fetchSubtitleText（yt-dlp --skip-download，复用 parseSRT/cleanCues）；public summarizeVideo + Apple 引擎守卫。+1 测试。
  - M3：SettingsView 翻译区 → 「AI 设置」默认槽（编辑 ai*）+「AI 总结」区（summaryFollowsDefault 开关 + 单独配置编辑器 + Apple 引擎不可总结提示）；测试/拉模型按 effective 配置发请求。更新 5 条 boundary 断言。
  - M4：ViewModel.summaryState/summarizeCurrentVideo/resetSummary（字幕优先回退简介、可取消、Apple 守卫）；ContentView ready 页 summarySection 四态 UI。+1 boundary 测试。
  - M5：删除按钮红色（.tint(.red)+.foregroundStyle(.red)）；全量 468 测试仅剩 1 个既有 iOS 脆性失败；全 product 构建通过；build.sh 装 /Applications 启动正常无新崩溃。
- 附带本轮：粘贴按钮改胶囊（.buttonBorderShape(.capsule)）；build.sh 安装目标改 /Applications。
- 已知遗留：ViewModel.dependenciesReady 仍是主线程同步 check()（不在视图事务，不崩）；iOS PackageBoundaryTests 脆性断言失败（iOS 分支，与本次无关）。
