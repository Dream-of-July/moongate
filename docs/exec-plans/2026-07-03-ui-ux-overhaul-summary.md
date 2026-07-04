# UI/UX Overhaul 分支总结（ui-ux-overhaul）

面向 七月 的验收索引。分支从 master `3d57cf9`（0.8.2 已发布）建，2026-07-03 一夜自主迭代。**只做产品体验层，未动已到人类水平的核心算法（ASR/分段/翻译/时序），未动发布流程。**

## 一句话
把 Moongate 的界面朝"苹果原生软件级"推进了 35 个 commit：补齐用户可调的字幕**大小/位置/颜色 + 实时预览**，修了一个真实的语言标签 bug（并同步到 Windows），搭建了你想要的"备忘录式三栏"**可运行且能自洽添加视频**的原型，统一了全界面视觉语言 + design token 层，**把新加的字幕功能与语言修复对等到了 Windows/C# 端**，并经一次对抗性代码审查修掉了唯一的真 bug。

## 如何验收
- 全部改动在本分支，35 个 commit（`git log master..HEAD`），每个独立、可回滚、带说明。
- 验证：`swift build`（debug + release 均绿）、`swift test`（**719 全绿**，多检查点）、Windows/C# `dotnet test`（**802 全绿**，本机 dotnet 10 可跑 MoongateCore；WPF App 项目本机可编译，MoongateApp.Tests 需 Windows VM）、每轮跑对应 boundary 测试。0 编译警告。
- **三栏原型预览**（默认关闭，不影响现有界面）：`defaults write com.moongate.app experimental.splitLayout -bool YES` 后重启 App，即见左列表（含进度环）+ 右预览/功能按钮；左上"+"可粘贴链接直接添加。关掉用 `-bool NO`。
- **待你决策的项**见 `2026-07-03-ui-ux-overhaul.md` 末尾：基准字号(13 vs 15)/alpha 两端对齐（改动会影响现有用户既有烧录，属设计取舍）、Bilibili 字幕探测 port 到 Windows、CHANGELOG/发布注记、三栏是否设默认。
- **注意**：GUI 像素级视觉未在本机自动验证（shell 无 accessibility 权限截不到窗口，但分支 release 包实测启动稳定无崩溃）——建议你启动 App 直观检查空状态、字幕预览（设置→字幕样式，四控件实时预览）、三栏原型。

## 各轮做了什么（35 commit）

### 用户点名的功能（新增能力）
- **字幕大小可调**（R1）：设置里小/标准/大/特大，标准=原行为。
- **字幕位置可调**（R7）：底部/顶部。
- **字幕样式实时预览**（R9）：设置里一个 16:9 预览，随大小/位置/双语样式实时变化（CapCut 式所见即所得）。
- **键盘快捷键**（R17）：新建下载 Cmd+L、粘贴并解析 Cmd+Shift+V。

### 真实 bug 修复
- **语言标签错误**（R4）：你给的样本——中文视频产出被标 `.en`。根因是 yt-dlp 错报语言污染整条链；在产物命名关口用脚本检测校正（内容是中文就标中文），不动识别算法。
- **测试回归修复**（R10）：R8 的 token 化打破了两个源码扫描测试的字面量锚点，已修（行为断言全保留）。

### 北极星：备忘录式三栏（可运行原型，feature-flag 隔离）
- **搭建**（R6）：NavigationSplitView 两栏，左 sidebar 列表（缩略图+标题+进度环）、右 detail（预览框+播放+功能按钮），复用现有队列组件。
- **状态生产级**（R13）：detail/sidebar 显示真实的下载%·速度·剩余、ASR 子阶段、翻译/烧录进度、完成/失败等。
- **按状态分组**（R16）：sidebar 分"进行中/已完成"两个 Section（带计数），更像备忘录。

### 视觉体系统一（苹果级打磨）
- **空/加载/选择/失败状态**（R2/R12）：统一的三级文案层级 + hierarchical 图标 + 呼吸感 + 出现动效（尊重减弱动态效果）。
- **队列项 / 队列浮层**（R3/R11）：缩略图描边、标题层级、handle 描边/阴影贴原生。
- **首次使用路径**（R8/R15）：依赖安装 + 登录页视觉精修（登录 cookie 状态图标化）、首启引导步骤指示器三态增强。
- **design token 层**（R5/R14/R18）：新建 `DesignTokens.swift`（Spacing/Radius/Thumbnail/Stroke/Layout），全界面等价采用，消除散落的魔法数字，为后续统一维护打基础。

## 后续方向 / 待你决策（已不含早期占位——三栏"添加"已真实化、maxWidth 已统一）
- **基准字号/alpha 两端对齐**：macOS ASS 基准 13pt / alpha 0A vs Windows 15pt / 全不透明。同选"标准"两端绝对字号不同——削弱"跨平台一致"。对齐需改一端基准=改动该端现有用户既有烧录（行为变更），选 13 还是 15 是设计取舍，交你定。
- **Bilibili 字幕探测 + 登录提示** port 到 Windows：macOS 有（master 遗留 WIP），Windows 缺失。完整功能，属跨平台路线决策。
- **三栏设为默认**：需先把 onboarding/依赖/登录等 sheet 接入三栏路径（目前只在 legacy 路径）。
- **CHANGELOG / 发布注记**：本分支改动尚未写入 CHANGELOG（发布消息由你把控，未擅自 bump 版本）。
- 未触及：网页下载健壮性、性能（偏核心，风险高，未在本轮范围）；Bilibili 探针可选加 bvid 缓存防批量风控。

## 不碰的事（遵守约束）
核心算法、发布流程、RS-02 仓库改名（需你亲自授权）。所有跨平台 core 改动已本机 dotnet 验证；WPF 运行时行为与真实烧录效果建议 Windows VM 最终确认。
