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
