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

## 十、键盘可达性 / 焦点顺序 / 快捷键 / VoiceOver 标签
只读审查主要路径（队列、设置、三栏、字幕预览、失败恢复、添加 sheet）的无鼠标操作与辅助技术可读性。**发现并修 3 个明确低风险缺口，其余确认健康。**

### 10.1 ✅ 已修（3 个低风险缺口）
- **Esc 收起展开的队列浮层**（commit `9409e3d`）：展开的队列是铺满的可关闭面板，此前只能点 chevron 或 Tab 到收起按钮——与 App 内其它可关闭面（add sheet/parse-cancel 都用 `.keyboardShortcut(.cancelAction)`）不一致。加 `.onExitCommand { expanded = false }`（SwiftUI 非-sheet 容器的 Esc 惯例），与 chevron 同动作。守护 `testExpandedQueueOverlayDismissesWithEscape`。
- **删除模型按钮的 VoiceOver 标签**（commit `fb2617a`）：本地-ASR 模型列表两个纯图标 trash 按钮（删除受管模型 / 删除导入模型）只有 `.help(...)`（悬停提示，非 VoiceOver 名字），而同排下载按钮已有 `.accessibilityLabel`。破坏性操作缺 label 会让 VoiceOver 念「未命名按钮」。双按钮补 label（同 key，零新文案）。守护扩展到 Settings boundary test，mutation 验证过。
- **添加 sheet 初始焦点**（commit `e9144f8`）：三栏 add sheet 链接输入框打开时无初始焦点，键盘用户须先 Tab（主界面 URL 框用 `@FocusState` 自动聚焦）。加 `@FocusState + .focused + .onAppear` 聚焦。守护在 `testAddSheetWiresToRealAddTasks`。

### 10.2 确认健康（未改）
- **快捷键齐备且可发现**：Cmd+,（设置）/Cmd+L（聚焦 URL）/Cmd+Shift+V（粘贴解析）都在菜单栏 CommandGroup（可发现）；URL 框 `onSubmit` 回车解析；add sheet cancel/confirm 走 `.cancelAction`/`.defaultAction`。
- **图标按钮 label 覆盖**：队列 iconButton（label+hint，前轮已守护）、三栏 actionButton（Label 可见文字 + accessibilityLabel）、三栏 add「+」/play、Settings 导入头/下载模型、ContentView 粘贴/设置齿轮——均带 label。系统扫描 ContentView/Dependency/Login/Summary/QueueOverlay/SplitLayout 无遗漏的纯图标交互按钮。
- **焦点与可关闭**：主 URL 框 `@FocusState` + Cmd+L 聚焦；队列 handle 是真 Button（Space/Return 激活）带 label+value；失败恢复按钮是文字按钮（天然可聚焦+VoiceOver 可读），primary 用 `.borderedProminent` 体现层级。
- **状态可读性**：sidebar 行 `.accessibilityElement(.combine)` + label(title) + value(statusText)；进度环 ProgressRingView 带 label；失败/取消图标 `.accessibilityHidden`（状态由行 value 承载，不重复念图标）。

### 10.3 记录（非缺陷，未改）
- **更新可用红点** 在设置齿轮上是纯视觉（VoiceOver 不念），但更新状态的主渠道是设置内的更新区（有完整文案）；给齿轮 label 动态附加更新态会让标签随状态变动，收益有限，非本轮低风险项。
- **失败恢复主按钮无 `.defaultAction`（回车触发）**：失败态是铺满页面而非 sheet/dialog，回车在非对话上下文触发主操作不是标准预期，且可能与其它焦点冲突；文字按钮已可 Tab+Space 触发。不加。

### 停机依据（本维度）
键盘/焦点/VoiceOver 三类明确低风险缺口（Esc 收起、删除按钮 label、sheet 初始焦点）已修 + 测试守护。主要交互面的快捷键、图标 label、焦点、状态可读性经代码级审查确认健康。剩余为需权衡的非标准增强（红点播报、页面级回车），非本轮自主项。

## 十一、字幕解析鲁棒性 + 编码边界（parseSRT/parseVTT）
只读审查字幕文件解析的编码/格式边界（BOM、CRLF、非 UTF-8、缺序号、空条、孤块）。**发现并补 1 个 macOS 侧测试覆盖缺口，其余确认健康。**

### 11.1 ✅ 已修：macOS parseSRT/parseVTT 鲁棒性契约无直接测试（commit `7e9dd53`）
- **缺口**：`parseSRT`/`parseVTT`(Translator.swift) 是全下游字幕分析（质量门/时序健康/置信度/翻译）的解析基座，其鲁棒性契约（容忍 BOM、CRLF/裸 CR、缺序号按序补号、显式非连续序号、丢空文本条与无时间行孤块）**只写在源码注释、无直接测试**——易回归且影响面大。
- **修复**：新建 `SubtitleParseRobustnessTests`(9)：BOM 剥离、CRLF 归一、隐式补号、显式序号保留、空条丢弃、点号毫秒、垃圾/空输入、VTT BOM+CRLF。**BOM 测试特意做成可判别**（BOM 后接显式序号 7，若剥离失败会补号成 1 而 fail），mutation 验证过（删 parseSRT 的 BOM 剥离行→fail，恢复→pass）。macOS 775 全绿。
- **跨平台观察（反常方向）**：Windows/C# 侧**本就有**对应测试（`ParseSrt_BomCrlfAndDotMilliseconds_Tolerated`/`_MissingIndexLines_AutoNumbers`/`_EmptyTextEntry_Dropped` + VTT，共 11 绿）——这次是 **macOS 落后于 Windows**，补测后两端持平。与以往「mac 领先、win 留缺口」相反，说明覆盖缺口两个方向都要查。

### 11.2 确认健康（未改）
- **BOM 安全贯穿全链**：所有下游分析（SubtitleTimingHealth/SubtitleQualityScorer/PlatformSubtitleQualityGate/LocalASRConfidence）都经共享 `parseSubtitleCues`→`parseSRT`/`parseVTT`，BOM 在解析入口统一剥离，无各自重复实现的漂移。
- **非 UTF-8 编码优雅降级**：`String(contentsOf:encoding:.utf8)` 对 GBK/Big5/Latin-1 返回 nil → `try?` 兜底为「不可用/空」，**不崩溃**。yt-dlp 产物基本是 UTF-8，非-UTF8 是低频（用户手动导入的老字幕）。真正的编码探测（usedEncoding/逐编码尝试）非平凡、有识别质量回归风险，属需 eval 先行的算法层改进，**非本轮低风险自主项**，记录为增强候选。

### 停机依据（本维度）
macOS 解析器鲁棒性契约已补直接测试（含可判别 BOM 用例 + mutation 验证），两端持平。BOM 安全全链统一、非-UTF8 优雅降级。编码自动探测是需 eval 的算法层改进，不自主做。

## 十二、下载产物命名冲突 / 去重（多次下载同视频 / 重复导入）
只读审查用户点名的场景：同一视频多次下载、重复导入字幕、重跑云端 ASR、导入模型重名——产物文件是否会互相覆盖。**发现并修 1 个明确低风险缺口（重复实现 + 零测试），Windows 侧记录为对等候选。**

### 12.1 ✅ 已修：四处 hand-rolled 去重命名循环收敛 + 补测（commit `b98eb80`）
- **缺口**：macOS 有**四处**等价的「找不冲突文件名 + 序号后缀」循环，全部无测试：`QueueManager.importedSubtitleDestination`（导入字幕，`-<n>`）、`CloudASR.outputURL`（云端 ASR sidecar，`-<n>`）、`SettingsView.uniqueImportedModelDestination`（导入模型，`-<n>`）、`Burner` 输出移动（`（字幕版） <n>`，空格分隔 + 固定 `.mp4`）。任一处回归会**静默覆盖**用户已有产物。
- **修复**：抽 `MoongateCore.UniqueFilename.url(in:stem:ext:separator:fileExists:)` 单一可测来源（`fileExists` 可注入，不碰真实 FS），四处全部改用。**`separator` 参数精确保留各点既有命名**——三个 sidecar 保 `-<n>`，Burner 传 `separator: " "` 保「（字幕版） 2.mp4」既有观感。行为完全不变（全量 783 测试含真实 Burner/CloudASR 输出路径测试全绿；调用点净 -30/+7）。
- **测试**：`UniqueFilenameTests`(8)——无冲突/单次冲突/连续冲突/首个空位填充/空扩展名/空格分隔（mutation 验证守护 Burner 命名）/含点主名保扩展名/结果落在目录内。
- **判断**：逻辑本就正确（序号从 2 起、逐个递增、不覆盖），非行为缺陷；缺口是「四处重复 + 零测试」的可维护性 + 回归风险。属可自主的低风险收敛，符合 [[StageSlotPool/CredentialMasking 下沉 Core]] 的既有模式。

### 12.2 Windows 对等观察（记录，未改）
- Windows/C# 有同类去重循环：`CloudAsr.cs` 内**两份**近乎相同的 `UniqueOutputPath`/`CloudAlignedOutputPath`（`-{index}`）+ `Burner.cs` 的 ` {serial}.mp4`（空格），同样**无冲突/序号测试**。功能与 macOS 等价（同 `-<n>` / ` <n>` 模式）。
- **未本轮做**：C# 侧收敛需跨文件重构（CloudAsr 两份 + Burner）且私有方法需测试缝，风险与本地可验证性权衡下，超出本轮「小步低风险」范围。记录为对等候选：可仿 macOS 抽一个 C# `UniqueFilename` 助手 + 补冲突测试。非需七月决策，是后续可自主的对等收敛项。

### 停机依据（本维度）
macOS 四处去重命名已收敛到单一可测来源 + 8 测试（mutation 验证），行为零变化。Windows 等价逻辑健在但内部重复 + 无测试，记录为可自主的后续对等项（跨文件重构，本轮控制风险未做）。产物覆盖风险在 macOS 侧已被测试守护。

## 十三、翻译分块 / 长文本边界（超长 cue / 输出超限 / 空返回 / 部分失败）
只读审查翻译分块、递归拆分、缺失回补、源回退与部分失败的用户可见结果 + 可复现测试。**补 2 个测试覆盖缺口 + 清 1 处死代码，核心逻辑确认健康。**

### 13.1 ✅ 已补测：输出超限的递归拆分 + 无法拆分的错误路径（commit `f783953`）
- **缺口**：`translateChunk` 在模型报 `reachedOutputLimit` 时对半递归拆（`depth<2 && half>=8`），拆不动时抛本地化的 outputLimitReached。这是长字幕的关键容错，**此前无测试**（既有 fallback 测试只覆盖缺失行/纯标点/源泄漏）。
- **补测**（用既有 `modelSender` 注入缝）：`testChunkSplitsInHalfWhenOutputLimitReached`（30 条整块触顶→两个 15 条半块成功→30 条全回贴无丢条，mutation 验证过：把拆分 guard 改 `depth<0` 会 fail）；`testUnsplittableOutputLimitThrowsLocalizedError`（3 条整块触顶→抛可行动本地化错误而非静默产空）。

### 13.2 ✅ 已清死代码：源泄漏重译后的质量二次评估被丢弃（commit `b4b29b0`）
- 源语言泄漏重译后，`translationQuality` 被重新赋值一次 `TranslationOutputQualityGate.assess(...)`，但该 Verdict **此后从未被读取**——纯函数的死存储（做真实计算却丢弃结果）。删掉重算、`var`→`let`，行为零变化（重译路径的两个既有测试仍绿）。加注释记录：把「重译后仍质量偏低」作为用户提示是需产品决策的 timingWarning 类触发面变更，非本层自动完成。

### 13.3 确认健康（未改）
- **无丢条**：`translateAllCues` 最终装配（Translator.swift:3199-3212）逐 cue 取 `merged[index]`，空则 `usedSourceFallback=true` 落回原文；仍全空才抛 missingTranslatedLine。任何 cue 都不会被静默丢弃。
- **缺失回补**：`repairMissingTranslations` 对残缺 cue 逐条重问，网络异常时落回原文（catch→original），不因单条失败拖垮整块。
- **部分失败可见**：`usedSourceFallback` 逐 cue 传出，双语样式下回退条只显原文；队列层 `partialFailure` + 完成通知「N 个任务需要重试字幕处理」+ 三栏/legacy 的重试字幕按钮（§八已审）——部分失败对用户可见且可操作。
- **分块并行**：3 路在途、全局序号回贴与完成顺序无关、每调度过 gate（暂停/取消），逻辑清晰。
- **源泄漏重试**：`shouldRetrySourceLanguageLeakage` 触发一次更强 advice 重译（既有测试覆盖触发与「重试后仍差则保留」）。

### 停机依据（本维度）
翻译分块的容错主干（递归拆分、缺失回补、源回退、部分失败可见）经代码级审查健康且现补齐了拆分/超限的直接测试；清掉一处死存储让代码诚实。「超长单 cue 无法拆分」已有明确本地化错误（非崩溃/非静默）。把翻译质量做成用户可见提示是需七月决策的触发面变更，记录不自主做。

