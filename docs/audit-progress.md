# Moongate 发布加固 · 审计进度跟踪

跟踪外部审查文档 `moongate_code_review_claude_plan.md` 中各 issue 的修复状态。
分阶段执行（Phase 0–7），每个 Phase 独立可验证、可回滚。

> **重要原则**：本表区分“编译/单元测试通过”与“真机验证通过”。
> `Runtime validation` 列在没有真实 Windows / macOS 机器端到端验证之前，一律标
> `Not validated on real hardware`，**不得**因为编译或单测通过就写成已验证。

---

## 基线（Phase 0）

- **基线分支**：`fix/release-hardening`
- **基线 commit**：`1cb2aa0c`（master HEAD，"fix: release zip dependency temp files before cleanup"）
- **工具链**：
  - Swift 6.3.2 (swiftlang-6.3.2.1.108)，Target arm64-apple-macosx
  - .NET SDK 10.0.300
  - makensis 已安装（本 Phase 未调用）
- **基线深度**：编译验证级（跑测试 + Release 编译；不做 `build.sh` 安装 /Applications，不做 NSIS/DMG/appcast 打包）

| 基线命令 | 结果 | 退出码 |
|---|---|---|
| `swift test --scratch-path ~/Library/Caches/vdl-build` | **288 passed / 0 failed** | 0 |
| `swift build -c release --scratch-path ~/Library/Caches/vdl-build` | **Build complete**（~26s） | 0 |
| `dotnet test windows/Moongate.Win.sln --nologo -v minimal` | **311 passed / 0 failed / 0 skipped** | 0 |
| `dotnet publish MoongateApp.csproj -c Release -r win-x64 --self-contained -p:EnableWindowsTargeting=true` | **publish 成功**（产物 `/tmp/moongate-win-baseline`） | 0 |

**结论**：基线全绿，无既有失败。后续任何 Phase 引入的失败都可与本基线对照判定为新引入。

> 备注：`dotnet test` 还原阶段有 `NU1900`（无法访问 nuget.org 漏洞数据库）警告，属网络/环境，非代码问题，不影响测试结果。

---

## Issue 状态表

字段：Status ∈ {Not started, In progress, Done}；Runtime validation ∈ {Not validated on real hardware, Validated}。

### P0 · 发布阻断级

| Issue ID | Priority | Platform | Status | Files changed | Tests added | Runtime validation | Remaining risk |
|---|---|---|---|---|---|---|---|
| WIN-UPD-001 | P0 | Windows | Done (code) | UpdateService.cs, App.xaml.cs, MainWindow.xaml.cs, SettingsWindow.xaml.cs, installer/installer.nsi, Strings.*.xaml | UpdateCheckerTests, 安装器 makensis 编译通过 | Not validated on real hardware | 队列 preflight + /UPDATEPID 等待 + 专用退出态；helper 进程未引入（用 NSIS 等待 PID 替代），需真机验证覆盖安装 |
| SEC-COOKIE-001 | P0 | Both | Not started | — | — | Not validated on real hardware | WebView 全量 Cookie 导出，未按站点隔离（Phase 2） |
| SEC-CRED-001 | P0 | Both | Not started | — | — | Not validated on real hardware | API Token 明文落盘（Phase 2） |
| WIN-DEP-001 | P0 | Windows | Done (code) | DependencyWindow.xaml(.cs), Dependencies.cs, Strings.*.xaml | DependenciesTests.FormatBytes, i18n 进度测试 | Not validated on real hardware | 加取消按钮/可取消 token/关窗确认/字节+速度进度；断点续传未做 |
| WIN-DEP-002 | P0 | Windows | Done (code) | SettingsWindow.xaml.cs, Dependencies.cs | DependenciesTests.RedownloadAll_NetworkFailure_KeepsExistingBinaries, PlanAll | Not validated on real hardware | 改为 staging 先下后换；SHA-256/PE 架构/能力校验留待 Phase 3 (DEP-WIN-003) |
| DEP-SUPPLY-001 | P0 | Windows | Not started | — | — | Not validated on real hardware | 下载执行未固定/未签名 latest 二进制（Phase 3）；更新器侧已有 SHA-256 |

### P1 · 高优先级

| Issue ID | Priority | Platform | Status | Files changed | Tests added | Runtime validation | Remaining risk |
|---|---|---|---|---|---|---|---|
| SETTINGS-001 | P1 | Both | Not started | — | — | Not validated on real hardware | 登录/依赖跳转忽略设置保存失败 |
| MAC-DEP-001 | P1 | macOS | Not started | — | — | Not validated on real hardware | 卸载误删用户自装 Homebrew 包 |
| PROC-001 | P1 | Both | Not started | — | — | Not validated on real hardware | 暂停乐观更新，失败仍释放并发槽 |
| PROC-MAC-002 | P1 | macOS | Not started | — | — | Not validated on real hardware | 取消可能留下孤儿 ffmpeg 子进程 |
| UPDATE-MAC-001 | P1 | macOS | Not started | — | — | Not validated on real hardware | 显式“静默检查更新”实为 no-op |
| UPDATE-WIN-002 | P1 | Windows | Done (code) | UpdateChecker.cs, Settings.cs, UpdateService.cs | UpdateCheckerTests.SemVer_PrereleasePrecedence / StableChannel_*, SettingsTests.ReceiveBetaUpdates | Not validated on real hardware | SemVer 完整预发布优先级 + 通道过滤；默认 ReceiveBetaUpdates=true（当前发布全是 prerelease，待首个正式版后改默认） |
| LOGIN-WIN-001 | P1 | Windows | Not started | — | — | Not validated on real hardware | 清除全部登录即使失败也显示成功 |
| DATA-WIN-001 | P1 | Windows | Not started | — | — | Not validated on real hardware | 卸载说明遗漏 %APPDATA% 凭证/Cookie |
| DATA-SETTINGS-002 | P1 | Both | Not started | — | — | Not validated on real hardware | 设置损坏静默回默认，无备份/提示 |
| PATH-WIN-001 | P1 | Windows | Not started | — | — | Not validated on real hardware | 文件夹名净化未处理保留设备名 |
| DEP-WIN-003 | P1 | Windows | Not started | — | — | Not validated on real hardware | 依赖“已安装”仅检查文件存在 |
| REL-001 | P1 | Both | Not started | — | — | Not validated on real hardware | 正式包缺平台级签名链 |
| REL-WIN-002 | P1 | Windows | Not started | — | — | Not validated on real hardware | GUI/安装器无真机运行验证 |

### P2 · 中优先级与 UI/UX

| Issue ID | Priority | Platform | Status | Files changed | Tests added | Runtime validation | Remaining risk |
|---|---|---|---|---|---|---|---|
| PARITY-001 | P2 | Windows | Not started | — | — | Not validated on real hardware | 多链接提取比 macOS 脆弱 |
| PARITY-002 | P2 | Windows | Not started | — | — | Not validated on real hardware | 不记住上次下载选项 |
| UX-WIN-001 | P2 | Windows | Not started | — | — | Not validated on real hardware | 设置窗口固定尺寸，高 DPI 不友好 |
| UX-WIN-002 | P2 | Windows | Not started | — | — | Not validated on real hardware | 硬编码浅色主题，高对比弱 |
| UX-WIN-003 | P2 | Windows | Not started | — | — | Not validated on real hardware | 安装器只有简体中文 |
| UX-WIN-004 | P2 | Windows | Not started | — | — | Not validated on real hardware | WebView2 缺失无直接修复入口 |
| REL-WIN-003 | P2 | Windows | Not started | — | — | Not validated on real hardware | 仅发布 x64，ARM 仅模拟 |
| UPDATE-WIN-003 | P2 | Windows | Done (code) | UpdateService.cs, App.xaml.cs | 经现有更新测试覆盖编译 | Not validated on real hardware | 取消/失败即时清理临时目录 + 启动清理 moongate-update-* 残留 |
| UPDATE-WIN-004 | P2 | Windows | Not started | — | — | Not validated on real hardware | 每次开设置新建更新器并静默请求 GitHub |
| UX-QUEUE-001 | P2 | Both | Not started | — | — | Not validated on real hardware | 自动收起队列可能在交互时关闭 |
| DOC-001 | P2 | macOS | Not started | — | — | Not validated on real hardware | README 对 Swift 依赖描述自相矛盾 |

---

## Phase 进度

| Phase | 范围 | 状态 |
|---|---|---|
| Phase 0 | 建立可验证基线 + 本跟踪文档 | **Done**（基线全绿，见上） |
| Phase 1 | Windows 更新与依赖阻断项（WIN-UPD-001、WIN-DEP-001/002、UPDATE-WIN-003/002） | **Done (code)** — dotnet test 321 通过（+10），NSIS 编译通过；覆盖安装/取消下载需真机验证 |
| Phase 2 | 凭证与登录隔离（SEC-CRED-001、SEC-COOKIE-001、LOGIN-WIN-001、DATA-WIN-001） | Not started |
| Phase 3 | 依赖可信度与 macOS Homebrew 边界（DEP-SUPPLY-001、MAC-DEP-001、DEP-WIN-003） | Not started |
| Phase 4 | 队列、暂停、取消可靠性（PROC-001、PROC-MAC-002） | Not started |
| Phase 5 | 设置可靠性与跨平台一致性（SETTINGS-001、DATA-SETTINGS-002、PATH-WIN-001、PARITY-001/002、UPDATE-MAC-001） | Not started |
| Phase 6 | UI/UX 与无障碍 | Not started |
| Phase 7 | 正式发布链路（签名、notarization、stable/beta channel、真机矩阵） | Not started |
