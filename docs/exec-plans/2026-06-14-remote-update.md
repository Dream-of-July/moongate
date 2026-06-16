# macOS：远程更新（检测 + 设置内全自动更新）

## 背景与产品意图
App 目前通过 GitHub Releases（公开仓库 Dream-of-July/moongate）以 DMG / Windows 安装器预发布分发，ad-hoc 签名未公证。要让用户在设置「更新」区看到新版并一键更新。

## 用户已确认的决策
- 执行方式：**全自动下载安装**（App 自己下 DMG、挂载、替换自身、重启）。
- 检查时机：**启动静默检查 + 设置里手动检查**。

## 关键技术事实（已核实）
- 发布在 GitHub Releases，全是 prerelease → `/releases/latest` 返回 404，必须用 `/releases?per_page=…` 取列表挑最新。
- macOS 资产名规律：`Moongate-macOS-v<版本>.dmg`（如 v0.3.0）。注意：**目前还没有 v0.4.0 的 macOS DMG release**，也没有 macOS release workflow（只有 windows-release.yml）——这是更新能跑通的前提，需补。
- DMG 布局（make-dmg.sh）：根目录是 `月之门.app` + 指向 /Applications 的软链。
- 版本号当前只硬编码在 build.sh 的 Info.plist（CFBundleShortVersionString=0.4.0）；bundle id `com.moongate.app`。
- 运行时取自身版本/路径：`Bundle.main.infoDictionary["CFBundleShortVersionString"]` 与 `Bundle.main.bundleURL`（目前代码未用 Bundle.main）。
- MoongateCore 已有 URLSession 用法可参考；无现成更新代码、无 Sparkle。
- **自下载文件不带 com.apple.quarantine**：App 用 URLSession 下载的 DMG 挂载后，里面的 .app 复制到 /Applications 不会被 Gatekeeper 拦（区别于浏览器下载）。这使「全自动」对 ad-hoc 签名可行。

## 目标 / 非目标
**目标**
1. MoongateCore 新增 `UpdateChecker`：查 GitHub releases 列表 → 选最新稳定/预发布 → 解析版本、macOS DMG 资产 URL、release notes，与当前版本比较。
2. macOS 新增 `UpdateService`：下载 DMG（带进度）→ 校验 → 挂载 → 取出 .app → 替换 /Applications 中自身 → 重启。
3. SettingsView 新增「更新」区：显示当前版本；有新版时显示版本号 + 更新说明 + 「下载并更新」按钮（带进度）；「检查更新」按钮；最新时显示「已是最新」。
4. 启动静默检查一次，有新版在更新区高亮（不打扰、不弹窗自动下载）。
5. 版本号集中可读（运行时从 Bundle.main 取，不再依赖硬编码常量）。

**非目标**
- 不引入 Sparkle（重、需要签名 feed/EdDSA，与 ad-hoc 分发不匹配）。
- 不做增量/差分更新。
- 不改 Windows/iOS（仅 macOS；UpdateChecker 纯逻辑可跨平台编译，UpdateService 仅 macOS）。
- 不做强制更新/灰度。

## 方案与取舍

### 版本与比较
- 语义版本解析 `SemVer(major,minor,patch)`，容忍前缀 `v`。比较用于「远端 > 本地」。
- 当前版本来自 `Bundle.main`；测试注入用显式参数。

### UpdateChecker（MoongateCore，可测）
- `func checkForUpdate(currentVersion:owner:repo:includePrereleases:) async throws -> UpdateInfo?`
- 拉 `https://api.github.com/repos/<owner>/<repo>/releases?per_page=20`（匿名，公开仓库够用；加 UA 头避免被限流；超时短）。
- 过滤出含 macOS DMG 资产的 release，按版本排序取最高；> 当前则返回 `UpdateInfo{version, notes, dmgURL, assetName}`，否则 nil。
- 纯解析逻辑（给定 JSON → UpdateInfo?）抽成可测函数，喂 fixture JSON 测。

### UpdateService（macOS GUI 层）
- 状态机 `@Published`：idle / checking / upToDate / available(UpdateInfo) / downloading(progress) / installing / failed(reason)。
- 下载：URLSession download task 到临时目录，进度回调。
- 安装（脱离自身进程，避免替换正在运行的 App 失败）：
  - `hdiutil attach -nobrowse -readonly <dmg>` → 找到挂载点里的 `月之门.app`。
  - 写一个临时 shell 脚本：等当前进程退出 → `ditto`/`cp -R` 覆盖 `/Applications/月之门.app` → `xattr -dr com.apple.quarantine`（保险）→ `hdiutil detach` → `open` 新 App。用 `Process` 启动该脚本后调用 `NSApp.terminate`。
  - 校验：bundle id 一致、可执行存在、版本 ≥ 期望，才替换；失败回退提示「去下载页」。
- 安全：只接受 `https://github.com/<owner>/<repo>/releases/download/...` 域名与路径前缀的 DMG URL；拒绝重定向到非 GitHub 主机。下载后校验挂载出的 .app 的 CFBundleIdentifier == 自身。

### UI（SettingsView「更新」区，放在「站点登录」后或顶部）
- 当前版本一行 + 状态：
  - 检查中：转圈。
  - 已最新：「已是最新（vX）」+「检查更新」。
  - 有新版：版本号 + 更新说明（可折叠）+「下载并更新」（下载时进度条 + 可取消）。
  - 失败：原因 + 「去 GitHub 下载」兜底按钮（打开 release 页）。
- 启动静默检查：App onAppear 触发一次 check（失败静默），有新版时更新区出现提示点。

### 发布侧（让更新真能下到东西）
- 现状缺 macOS release workflow。补 `.github/workflows/macos-release.yml`：手动触发，跑 build.sh + make-dmg.sh，产物按 `Moongate-macOS-v<version>.dmg` 命名上传到对应 tag 的 release。（不在 CI 签名/公证，维持 ad-hoc；CI 用 macos runner 跑 actool 可能受限，必要时退化为脚本生成无图标 DMG，或文档说明手动发布步骤。）
- 这一步可作为可选里程碑：核心 App 更新逻辑不依赖它，但没有 v0.4.0 macOS DMG 时「检查更新」会显示已最新或找不到资产——需如实提示。

## 里程碑与验证
- **M1 版本+检查逻辑**：SemVer、UpdateChecker、GitHub JSON 解析。验证：单测（fixture JSON：有新版/已最新/无 macOS 资产/坏数据；版本比较边界 v 前缀）；core 构建。
- **M2 UpdateService 下载+安装**：状态机、下载进度、DMG 挂载/替换脚本、安全校验。验证：单测 URL 白名单校验与安装脚本生成（纯函数）；真实下载一个已存在的 v0.3.0 DMG 冒烟（挂载/校验，不真替换）。
- **M3 设置 UI**：更新区 + 启动静默检查。验证：boundary 测试（更新区按钮/状态、去下载兜底）；App 构建。
- **M4 发布 workflow（可选）**：macos-release.yml + 文档。验证：workflow lint；说明手动发布路径。
- **M5 收尾**：全量 swift test；build.sh 装 /Applications；手测检查更新（对现有 v0.3.0 资产）、下载冒烟、UI 各状态。

## 风险与回滚
- ad-hoc 未公证：自下载 DMG 无 quarantine，可替换；仍给「去 GitHub 下载」兜底。若自替换在某些权限环境失败，UI 明确报错并引导手动。
- 替换正在运行的 App：必须脱离进程用外部脚本在退出后执行，否则覆盖失败。校验 bundle id 防替换错对象。
- 安全：严格校验下载 URL 主机与替换目标，避免被重定向或替换非自身 App。不静默执行任意远端脚本。
- GitHub API 匿名限流（60/h/IP）：检查失败静默 + 手动重试；不频繁轮询（仅启动 1 次 + 手动）。
- 没有 v0.4.0 macOS release 时：如实显示「已是最新」或「未找到 macOS 安装包」，不报错崩。
- 每个里程碑独立可编译可测；UI 不依赖 workflow。

## 决策日志（已确认）
- 全自动下载安装；启动静默检查 + 手动检查。
- 更新源：GitHub Releases API（公开仓库，匿名）。
- 不用 Sparkle，自实现轻量更新。

## 待确认
- 是否现在就补 macOS release workflow（M4）——还是先做 App 内更新逻辑、发布流程你手动管？默认：M4 作为可选，先交付 M1-M3+M5。

## 进度日志
- 2026-06-14：M1-M3+M5 完成（M4 发布 workflow 暂缓，待用户定）。
  - M1：SemVer + UpdateInfo + UpdateChecker（GitHub releases?per_page 列表，挑含 macOS DMG 的最高版本 > 当前）；纯解析 latestMacUpdate 可测。
  - M2：UpdateService（macOS）状态机 idle/checking/upToDate/available/downloading/installing/failed；URLSessionDownloadDelegate 进度；hdiutil 挂载 + bundle id 校验 + 脱离进程替换脚本（等退出→ditto→去 quarantine→重开）+ NSApp.terminate；isTrustedDMGURL/installScript 移到 MoongateCore 可测。
  - M3：SettingsView「更新」区（当前版本/检查更新/各状态/下载并更新进度/GitHub 兜底）；打开设置静默检查一次。
  - M5：12 个更新单测（SemVer/JSON 解析/URL 白名单/脚本顺序）+ boundary；全量 493 测试仅剩既有 iOS 脆性失败；build.sh 装 /Applications 启动正常。
- **关键前提**：当前线上最新 macOS release 是 v0.3.0，App 本地是 0.4.0，所以「检查更新」会显示已最新。要让更新真正生效，需发布一个版本号 > 当前、且带 `*macOS*.dmg` 资产的 GitHub release（M4 workflow 或手动 make-dmg.sh + gh release）。
- 已知遗留：启动检查目前挂在「打开设置」时（非 App 首次启动）；如需 App 一启动就静默检查，可把 check(silent:) 提到 App/ViewModel onAppear。
