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

