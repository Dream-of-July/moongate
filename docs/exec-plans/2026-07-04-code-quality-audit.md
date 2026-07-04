# 代码质量只读审查证据（错误文案 / 性能 / 内存）

无需七月决策的只读质量维度审查。结论：**两维度均确认健康，无 P0/P1，无低风险可自主修的代码缺口**。以下为证据，供验收留痕。均未改动任何代码/算法/发布/默认行为。

## 一、错误状态文案一致性 —— 确认健康
**结论**：错误文案有一致的受控本地化机制，无向用户泄漏技术栈的缺陷。

证据：
- `MoongateError.errorDescription`（Models.swift:20-47）对全部 case 提供本地化、可行动文案（`binaryNotFound`/`sniffFailed`/`downloadFailed`/`loginRequired`/`siteCookieRequired`/`translateFailed`/`burnFailed`/`cancelled` 等）。`siteCookieRequired` 是范例——说明"要做什么 + 会自动重试"。
- 主失败路径 `ViewModel.fail()`（ViewModel.swift:1683）先专门处理 `loginRequired`/`siteCookieRequired`/`binaryNotFound`（触发登录/依赖引导），再落 `error.localizedDescription`；对 MoongateError 即受控本地化文案。
- 队列失败 `QueueManager.shortReason()`（:2058）从 translateFailed/burnFailed/downloadFailed 提取受控 reason，else 落 localizedDescription。
- `failedState` UI（ContentView）已两段式：中文主句 headline + 技术详情 disclosure（`L.Failed.technicalDetails`）——原始技术文本落在可折叠详情区，不污染主句。
- 其余 `error.localizedDescription`（Settings 导入/删除、brew 启动失败等）均为系统级操作，展示系统本地化描述可接受，且位于 notice/feedback 次要区域。

判断：非缺陷。受控本地化（MoongateError）+ 系统错误落次要区 + 两段式失败页，是一致且合理的设计。无需改。

## 二、性能 / 内存 —— 确认健康
**结论**：无高频重绘、忙等、明显保留环等性能/内存风险；主要风险点已有既存缓解。

证据：
- **进度更新已节流**（QueueManager.swift:1116 注释 + 逻辑）：进度变化 <1% 不写 items，避免长队列高频 `objectWillChange` 拖累 UI——这是最主要的重绘风暴风险，已缓解。
- **列表懒加载**：展开队列 `QueueSectionView` 用 `LazyVStack`；三栏 sidebar 用 `List`（系统懒加载）——大量任务不会一次性实体化。
- **槽位池非忙等**（StageSlotPool.acquire :96-111）：无空槽时 `await withCheckedContinuation` 挂起（零 CPU），`release()`/`wakeAll()` 在槽位释放时 resume。是正确的 async 信号量，非 `while true` 忙循环。
- **无 Timer/轮询**：唯一持续动画是 SummaryView 的流光/ShimmerText（`TimelineView(.animation)`，尊重 reduce-motion）与空状态一次性淡入——均有界、可被 reduce-motion 关闭。
- **长生命周期 Task 用 `[weak self]`**（QueueManager :518/1247/1328/1369，赋给 `item.task` 的流水线任务）——防保留环。内层 `Task { @MainActor in }`（:568/601/828…）是短暂回主线程更新，即时完成释放，非泄漏源。
- 越界防护已在分支内改善（`appDownloadsDirectory` 从 `[0]` 下标改 `.first ?? fallback`，见对抗审查记录）。

判断：非缺陷。架构在并发、重绘、内存上均稳健。无低风险可自主改的点。

## 停机依据（本两维度）
两维度经代码级证据审查均健康；未发现 P0/P1 或低风险覆盖缺口。真正的性能/内存回归验证需在真机长时间运行 + Instruments 采样（GUI/运行时，本 shell 无法做），建议 Windows VM / 本机手动跑长批量下载时用活动监视器观察——已加入手动 QA 建议范畴。代码静态层面无待修项。

## 三、下载失败引导 / 多语言文案 / 队列并发边界（第二轮只读审查）

### 3.1 多语言文案 —— 确认健康
- **占位符跨三语逐 key 一致**：脚本核验 775 key，`%@`/`%d` 数量三语全一致（0 不一致），三语 key 数相等（775/775/775）——无格式化崩溃/参数错位风险。
- **本分支新增文案自然、无 AI 味、简繁正确**：idleSupportedSites / 字幕大小·位置·颜色 / 预览 / 调整字幕… 逐条复审；zhHans 用简体（颜色/预览），zhHant 用繁體（顏色/預覽），已核验各文件变体正确、无简繁串档。
- 复现：`grep '.<key>:' Strings.{en,zhHans,zhHant}.swift`；占位符核验脚本见 session。

### 3.2 下载失败恢复引导 —— 确认健康
- 队列项失败态按钮按类型分支：`needsLogin != nil` → 登录并重试（`loginAndRetry`）+ 重试 + 删除；一般失败 → 重试 + 删除。
- 主 `failedState`（ContentView）按 `failedNeedsDependency` / `failedNeedsLogin` 上下文给依赖配置 / 登录 / 重试。
- 登录成功后 `retryFailedNeedingLogin` 自动重试该站点失败项。恢复路径完整、可行动（与对抗审查结论一致）。

### 3.3 队列并发边界 —— 健康，但有一处已记录的测试覆盖限制
- **逻辑正确**：pause/resume/cancel、代际（generation）守卫、槽位释放顺序均有源码扫描测试守护（`testPauseDoesNotReleaseTranslationSlot`、`testPauseResumeReportSuccessAndConfirmPauseBeforeReleasingSlot` 等）；`StageSlotPool.acquire` 用 `withCheckedContinuation` 挂起等待、`release/wakeAll` 唤醒，是正确的 async 信号量（非忙等，见第二节）。
- **覆盖限制（已诊断根因，不自主修）**：`StageSlotPool` 这个 async 信号量原语**只有"按检查"和源码扫描测试，没有行为单测**（实际 acquire N / 阻塞 N+1 / release 唤醒）。根因：它位于 `Moongate`（App 可执行 target），而 SwiftPM **可执行 target 无法被其它 target `@testable import`**——这正是队列 boundary 测试读源码文本而非 import 的原因。
  - **✅ 已解决（后续 commit）**：复核依赖后确认这是零逻辑的纯迁移（StageSlotPool 只依赖 TaskControlToken + MoongateError，均已在 MoongateCore；只被 QueueManager 引用），已下沉到 `Sources/MoongateCore/StageSlotPool.swift` 并补 5 个行为单测（`StageSlotPoolTests`）。原判"有回归风险"过度保守——实为可安全自主的关系解耦。build + 725 测试全绿。
  - ~~给七月的可执行建议（非本轮）~~：已自主完成，无需七月决策。

## 四、登录流程 / web 下载批量反馈 —— 确认健康（第三轮只读）
- **登录失败路径覆盖充分**：`MacOSLoginBoundaryTests` 10 个用例覆盖 cookie 导出按站点过滤+写 per-site jar、失败起始 URL 需 jar 可用才重试、导航加载态维护（不误报 cancelled）、cookie 就绪只显存在性、host-only 显示等。失败文案本地化齐（`L.Login.exportFailed`/`noUsableCookiesForPage`/`loadFailed`）。C# 侧 `WindowsLoginCookieExportVerifiesJarMatchesStartUrlBeforeRetrying` 对等。R8 视觉精修未扰动这些逻辑（测试全绿）。无缺口。
- **web 下载批量反馈**：`processBatch` 累计 added/duplicated/failedHosts → `enqueueNotice`（`L.Main.batchAdded/batchDuplicateCount/batchFailedCount`），失败站点展示 `prefix(2)` 有界，逐个 URL 失败不中断整批（catch 累计继续）。取消用 session token 作废陈旧回调。反馈完整、有界、本地化。无缺口。

## 五、本分支新代码测试覆盖收口
- StageSlotPool 行为测试(5)、SplitLayout boundary(5)、VideoThumbnail boundary(2)、颜色继承 guard、双端 fallback 可测化、Windows 三语键集守护——本分支所有实质新代码均有测试守护。
- 正确判为"无需测试"：DesignTokens（20 纯常量，测试即重述定义）、VideoThumbnail 的琐碎视图逻辑（已由 boundary 守护关键行为）。
- 已知不做（真实回归风险，非低风险）：QueueStatusFormatter dedup（QueueItem 深耦 App target，抽取需大迁移）。

## 六、队列持久化 / 退出处理 —— 确认健康（有意的临时队列设计，非缺口）
只读审查"App 重启后队列状态"这一维度：
- **队列是内存态**（`@Published var items = []`，无持久化/恢复）。这是**有意设计**，不是遗漏——退出时有明确的中止确认（App.swift `abortConfirmationMessage`）：仅当有未到终态任务时警告"N 个任务进行中，关闭会全部中止"，用户显式选择"保留任务/中止任务"，**无静默数据丢失**。
- **计数精确**：`openTaskCount = items.filter isOpen`，`isOpen` 干净排除终态（done/failed/cancelled）——确认只对真正进行中的任务警告，不会把已完成项算进去误警。
- **测试守护**：`MacOSAppBoundaryTests.testAbortConfirmationExplainsChoicesWithoutChangingButtonsOrReturnMapping`（按钮 + 返回值映射）+ `MacOSQueueBoundaryTests`（openTaskCount/pausedOpenTaskCount）。
- **判断**：当前行为安全、诚实、已测。**非缺陷**。"重启后恢复下载"是竞品（Downie/Parabolic）有的增强，但需序列化 QueueItem + 可续传部分文件 + 重挂 yt-dlp resume——是**较大功能，属七月的产品路线决策**，不是低风险自主修项。记录为增强候选，不自主做。


## 七、平台特定 URL 解析 / 下载覆盖（B站/YouTube/TikTok）—— 确认健康
只读审查用户点名的平台覆盖维度：
- **平台识别广且有针对性**：`Engine.isNativeExtractorHost` 覆盖 YouTube / Bilibili / TikTok / Douyin / Xiaohongshu——这些被标记为 yt-dlp 原生 extractor，解析失败直接给真实原因而非回退 PageSniffer 显示误导性"页面加载失败"。
- **短链/风控/登录引导到位**：短链覆盖 `vt.tiktok.com` / `v.douyin.com` / `xhslink.com` / `b23.tv`；Bilibili HTTP 412 风控给可操作的中文提示（等待/换网络/别反复登录）；未登录 412 触发登录引导 WebView；per-site cookie 隔离（youtube/bilibili 显式 + 其它 `dynamicKey(forHost:)` 动态）。
- **测试守护**：`LoginDetectionTests.testNativeExtractorHostsIncludeShortVideoSites`（TikTok/Douyin/Xiaohongshu 含短链 + 非平台 host 反例，用 `_testIsNativeExtractorHost` 钩子）、`testBilibili412WithoutSavedCookiesPromptsLogin` / `WithSavedCookiesKeepsRiskControlHint`、`CookieSitesTests`(8)。
- **判断**：平台覆盖思虑周全、测试充分。**非缺陷**。TikTok 无专门 CookieSite 是合理的——靠 yt-dlp 原生支持 + 动态 cookie 隔离，无需硬编码。

## 审查收敛观察（诚实评估）
截至本轮，用户点名的维度（网页下载/平台覆盖、分词器/分段、画质调节、字幕调节/大小、登录到全路径、首次使用、性能、错误状态、i18n、并发、跨平台）已系统审完。近几轮结果从"发现可修缺口"转为"确认健康 + 证据化"，是收敛信号：
- **本分支已修的低风险缺口**（测试守护为主）：StageSlotPool 行为测试、SplitLayout/VideoThumbnail boundary、iconButton a11y label、颜色继承 guard、双端 fallback 可测化、Windows 三语键集守护、语言标签/ai- 前缀双端修复、字幕外观三设置双端对等等。
- **剩余均为需七月决策或有回归风险的项**（已证据化，不自主做）：基准字号 13/15 对齐、Bilibili 探测 port Windows、readability eval 双语口径修正（动基线）、平台字幕可读性提示（动 timingWarning 触发面）、CHANGELOG/发布、三栏设默认、队列持久化/续传、QueueStatusFormatter dedup。
- 停机依据：可自主、可验证、不改现有行为/基线的缺口已基本清空；继续深挖要么触碰上述决策项，要么是边际递减的重复确认。

## 八、三栏 done 态动作对等复核（commit 62-64 新代码审查）
只读复核最新三个 commit（62 画质边界测试 / 63 三栏 done 态动作对齐 legacy / 64 三栏添加反馈条）的正确性与覆盖：
- **✅ 已自主修的覆盖缺口**：commit 63（084768a）给三栏 detail 补了 done 态的 `retrySubtitle`（部分成功）+ `waveform` 本地 ASR 重识别，但未加测试守护——原 `testDetailReusesProgressRingAndRealQueueOperations` 只断言 pause/resume/cancel/retry/remove/reveal。已补 `testDoneStateActionsMatchLegacyQueue` 守护两个新动作 + 其 guard 条件（partialFailure；canRetryWithLocalASR + hasLocalASRGenerator 双重守护）+ 文案 key。SplitLayout 套件 8 绿（原 7）。
- **⚠️ 一处行为差异（需七月定，未自主改）**：**waveform 本地 ASR 重识别按钮的显示条件两端不一致**。
  - **legacy**（QueueSectionView:62-63 → QueueItemView:383）：只要 `canRetryWithLocalASR`（done + 有视频产物）就**显示**按钮，`hasLocalASRGenerator` 仅切换 **hint 文案**（就绪 vs「去设置里配置本地识别」），即未配置本地引擎时按钮仍在，点了引导去配置。
  - **三栏**（SplitLayoutView:649）：额外要求 `queue.hasLocalASRGenerator` 才显示，未配置时**整颗按钮隐藏**。
  - **判断**：三栏行为**UX 上更干净**（不给一颗点了才发现没配置的「死按钮」），但与 commit 63「matches legacy across all stages」的措辞不符，且两端不一致。两种都合理，取舍是产品决策：(a) 统一到 legacy「常显 + 引导配置」——可发现性强，但有一次无效点击；(b) 统一到三栏「配置后才显」——干净，但用户不知道有此功能。**flag 默认关，无用户影响，不自主改**，记录供七月定方向后双端对齐。

## 九、真实用户环境边界（文件权限/磁盘/离线/iCloud/路径）
只读审查用户真实环境的错误处理、文案与覆盖。**发现并修 1 个明确低风险缺口（双端对等），其余确认健康。**

### 9.1 ✅ 已修：磁盘满 / 输出目录不可写的下载失败文案（双端）
- **缺口**：`friendlyDownloadReason`(mac Engine.swift) / `FriendlyDownloadReason`(win Engine.cs) 只分类 403 + 网络（win 另有证书信任），**磁盘满 / 只读卷 / 权限拒绝 / iCloud 优化存储位置** 这类文件系统写入失败落到通用兜底「下载过程中出现错误」+ 一行裸 stderr，用户不知该清理磁盘还是换目录——而这些是高频真实环境。
- **修复**：双端各加两个分类器，**排在网络判断之后**（不吞网络错误）：磁盘满(`No space left`/`Errno 28`/`ENOSPC`/`disk quota`；win `WinError 112`)→引导清理磁盘重试；写权限/只读(`Permission denied`/`Errno 13`/`EACCES`/`read-only file system`/`Errno 30`/`unable to open for writing`/`create directory`；win `WinError 5`/`process cannot access the file`)→引导设置里换输出文件夹重试。裸 EPERM(`errno 1`)故意排除（过宽会误伤）。
- **测试**：mac 新建 `DownloadFailureReasonTests`（6，`friendlyDownloadReason` 此前**零覆盖**，顺带守护了既有 403/网络分支 + 网络 Errno 不被误判为磁盘/权限）；win `EngineParsingTests` +3。**mac 765 + win/C# 809 全绿**。commit `51b9294`。

### 9.2 确认健康（非缺陷，未改）
- **输出目录确定**：`ViewModel.appDownloadsDirectory` 已有 fallback（`urls(for:).first ?? homeDir/Downloads`，防越界崩溃，对抗审查已改）。`sanitizedFolderName` 处理路径分隔符/控制字符/换行/超长截断(80)/Windows 结尾点号——**路径含空格/中文安全**（空格保留、CJK 不动，只去 `/\:\0` 与换行）。
- **目录创建**：`download()` 用 `try? createDirectory`，创建失败虽被静默吞，但随后 yt-dlp 写入必报权限/空间错误 → 现已被 9.1 的分类器兜住成可行动文案。链路完整。
- **analyze 离线/网络**：`friendlyAnalyzeMessage`(mac) / `FriendlyAnalyzeMessage`(win) 已覆盖网络错误 + 无可用清晰度（风控）。analyze 不写盘，磁盘/权限不适用——合理无缺口。
- **依赖缺失**：`binaryNotFound` 用本地化 key + DependencySetupView 专门引导（R8 已精修）；`errorDescription` 全 case 本地化可行动（前几轮 §一/§3.2 已确认）。
- **iCloud dataless 导入字幕**：`importSubtitleFile` 选择时只校验扩展名，实际 `copyItem` 在下载流水线 `appendImportedSubtitleFileIfNeeded`(throws) 里；dataless 文件在 macOS 上 copyItem 通常触发自动下载或抛错（非崩溃），失败经 partialFailure 流程兜底。属边缘场景，无低风险专项修法，不自主做。

### 9.3 平台差异（非缺陷，记录）
- **证书信任错误**：win `FriendlyDownloadReason` 有 `IsCertificateTrustError` 专项分支（企业自签根证书/系统时间错乱），mac 两个函数都无——但 mac 的 SSL 错误被 `isLikelyNetworkError` 的 `"ssl"` 标志兜住，给「网络不稳/检查代理」提示，方向大致对（同样引导查代理），只是不如专项精确。加 mac 证书专项分支需评估 mac SSL 错误形态 + 引入平台特定新分支，非本轮低风险范围，记录供未来对齐。

### 停机依据（本维度）
文件系统写入失败文案是真实高频缺口，已双端对等修复 + 测试。其余环境边界（输出目录/路径含空格中文/analyze 离线/依赖缺失/iCloud 导入）经代码级审查确认已有合理处理或属边缘无低风险修法。证书信任分支是平台差异非缺陷。

