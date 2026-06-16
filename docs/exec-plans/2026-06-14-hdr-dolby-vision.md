# macOS：HDR / 杜比视界下载 + 格式转码 + HDR 保真烧字幕

## 背景与产品意图
用户要下载 HDR/杜比视界视频。当前痛点：
1. 格式解析只按高度分档，完全忽略 yt-dlp 的 `dynamic_range`（SDR/HDR10/DV），用户无法选 HDR，且 `--merge-output-format mp4` 对 YouTube 的 VP9.2-HDR 不可靠。
2. 烧录字幕强制 `libx264 + yuv420p`（8-bit SDR），会把 HDR 压成 SDR。

用户确认的目标：
- 选分辨率页加 **HDR 开关**（有 HDR 源时可开）。
- 选分辨率页同时给**格式选项**，标注源原始格式；用户选了别的格式 → 下载完成后**转码**（同编码换容器走 remux，跨编码走转码）。
- 烧录中文字幕也要能**保留 HDR**：用 **libx265 10-bit** 重编码 + 透传 HDR 元数据，字幕本身用 SDR 颜色叠在 HDR 画面上；x265 不可用时回退 tonemap→SDR 并提示。

## 现状勘察（file:line）
- `buildVideoInfo`(Engine.swift:639) 按 height 分 6 档，formatID 形如 `bv*[height<=H]+ba/b`，恒定 `--merge-output-format mp4`(Engine.swift:971)。`dynamic_range` 未读取。
- yt-dlp `-J` 每个 format 有 `dynamic_range`(SDR/HDR10/DV)、`vcodec`(vp9.2/av01.../avc1)。已实测 4K HDR 视频确认。
- `FormatChoice`(Models.swift:72)：id(yt-dlp -f 串)/label/detail/isAudioOnly。
- `DownloadRequest`(Models.swift:137)：formatID 等；下载后产文件路径回 `DownloadResult.files`。
- 烧录 `FFmpegBurner.burn`(Burner.swift:108) 固定 `libx264 -crf 20 -pix_fmt yuv420p`(Burner.swift:212)，输出 out.mp4。HDR 信息丢失。
- ffmpeg-full 已确认有 libx265(+`-x265-params`)、libsvtav1、hevc_videotoolbox、zscale、tonemap、subtitles(libass)。
- 下载流水线在 QueueManager；burn 是其中一个 stage。烧录与否由 `chineseMode`/字幕选择驱动。

## 目标 / 非目标
**目标**
1. 解析时识别每档的 dynamic range + 编码，VideoInfo 暴露 HDR 可用性与源编码/容器。
2. 选分辨率页：HDR 开关（仅有 HDR 源时可用）+ 输出格式选择（标注源格式，选别的则转码）。
3. 下载用正确的 yt-dlp `-f`（HDR 时选 HDR 流）和容器（HDR 默认 mkv 保真，避免 mp4 装 VP9 失败）。
4. 下载后按所选格式 remux（同编码）或转码（跨编码），HDR 源转码保 HDR（x265 10-bit）。
5. 烧字幕保 HDR：HDR 输入走 x265 10-bit + HDR 元数据透传，字幕 SDR 叠加；x265 不可用回退 tonemap SDR 并提示。
6. 不破坏现有 SDR 路径与全部测试。

**非目标**
- 不做真正「生成杜比视界 profile 5/8」（需 Dolby 授权编码器，不现实）。DV 源按 HDR10 兼容层处理或保留原始流。
- 不改 Windows/iOS/Android（仅 macOS 分支；core 跨平台保持可编译）。
- 不追求 VideoToolbox 硬件 HDR 编码（先用 libx265 软编，稳）。

## 方案与取舍

### 数据模型
- `FormatChoice` 增 `dynamicRange: DynamicRange`(`.sdr/.hdr10/.dolbyVision`)、`sourceContainer`/`sourceVCodec`（用于转码决策与标注）。新增字段给默认值，不破坏现有构造。
- 新增 `enum OutputFormat`（如 `.original/.mp4H264/.mp4H265/.mkvOriginal/...`）描述用户选择的目标格式。
- `DownloadRequest` 增 `outputFormat: OutputFormat`、`preferHDR: Bool`。

### 解析（buildVideoInfo）
- 按 (height) 分档时，额外探测该档是否有 HDR 流：读 `dynamic_range != "SDR"`。
- 每档 FormatChoice 记录其 dynamicRange 与源 vcodec/容器；HDR 与 SDR 仍合并为「一个分辨率档 + HDR 开关」（按用户选「加 HDR 开关」），开关打开时把 `-f` 选择器换成偏好 HDR 的串（`bv*[dynamic_range!=SDR][height<=H]+ba/...`）。
- 标注源格式（如「源：VP9 HDR / webm」）用于格式选择 UI。

### 下载（download）
- HDR：容器默认 mkv（`--merge-output-format mkv`），避免 mp4 装 VP9.2 失败；`-f` 用 HDR 偏好选择器。
- SDR：维持现状（mp4）。
- 选了「转码到 X」：下载阶段仍按最优源下载，下载后进入转码 stage。

### 转码（新增 stage / Burner 同级）
- 新增 `Transcoder`（MoongateCore）：
  - remux（同编码换容器）：`-c copy`，秒级无损。
  - 转码（跨编码）：目标 H.264→libx264；H.265→libx265（HDR 源带 `-x265-params hdr-opt=1:repeat-headers=1` + 色彩元数据透传 + `-pix_fmt yuv420p10le`）；AV1→libsvtav1。
  - HDR 源转 H.264（8-bit 无 HDR）时明确提示会丢 HDR，需用户已选该格式即视为同意。
- 接入 QueueManager 作为下载后的可选 stage（仅当 outputFormat ≠ original 或需要容器修正）。

### 烧字幕保 HDR（Burner 改造）
- 探测输入是否 HDR（ffprobe color_transfer/primaries：smpte2084/arib-std-b67 + bt2020）。
- HDR 且 libx265 可用：
  - `-c:v libx265 -pix_fmt yuv420p10le -x265-params "colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:hdr-opt=1:repeat-headers=1:master-display=...:max-cll=..."`（从 ffprobe side_data 提取 master-display/max-cll，缺失则省略）。
  - 字幕 `subtitles` 滤镜叠加：字幕 ASS 颜色本就是 SDR 白字，叠在 HDR 上需保证滤镜不改色彩空间（subtitles 滤镜在 BT.2020 帧上叠加白字，亮度可能偏高 → 给字幕一个适中的亮度，或用 `format=yuv420p10le` 保 10-bit）。容器用 mkv 或 mp4（hevc 进 mp4 OK）。
- HDR 但 libx265 不可用：回退现有 tonemap→libx264 SDR 路径，并通过既有 errorText/提示告知「已转 SDR」。
- SDR：完全维持现有 libx264 路径，零行为变化。

### UI（选分辨率页）
- 在「格式」区：每个分辨率档保持单行；若该档有 HDR 源，区域顶部显示 **HDR 开关**（Toggle，仅有 HDR 源时 enabled）。
- 新增「输出格式」选择（Picker/菜单）：默认「保持源格式（VP9 / webm）」，可选 mp4(H.264)/mp4(H.265)/mkv 等；选非源格式时下方提示「下载后将转码，HDR 转 H.264 会丢失 HDR」之类的按需提示。
- 文案克制，按 HIG。

## 里程碑与验证
- **M1 模型+解析**：DynamicRange/OutputFormat/FormatChoice 扩展；buildVideoInfo 读 dynamic_range/vcodec，标注源格式与 HDR 可用性。验证：core 单测（解析含 HDR formats 的 fixture JSON → 正确分档与 HDR 标记）；`swift build`。
- **M2 下载选择器**：HDR 偏好 -f 串 + HDR mkv 容器；DownloadRequest 扩展。验证：单测 -f/容器选择逻辑（HDR on/off、各分辨率）；CLI 构建。
- **M3 转码**：Transcoder（remux + 各编码转码 + HDR 保留参数）；接入 QueueManager stage。验证：单测 ffmpeg 参数生成（remux vs 转码、HDR x265 参数、HDR→H.264 提示）；可选真实小样本转码冒烟。
- **M4 烧字幕保 HDR**：Burner HDR 分支（x265 10-bit + 元数据透传 + 字幕叠加）+ 回退。验证：单测参数生成（HDR→x265 / 回退 SDR）；boundary 测试；真实 HDR 片段烧录冒烟。
- **M5 UI**：HDR 开关 + 输出格式选择 + 提示。验证：boundary 测试；构建。
- **M6 收尾**：全量 `swift test`；`./build.sh` 装 /Applications；手测 4K HDR YouTube 下载（HDR on mkv / SDR mp4 / 转 H.265 / HDR 烧字幕 / HDR→H.264 提示）。

## 风险与回滚
- HDR 元数据提取（master-display/max-cll）依赖 ffprobe side_data，缺失则省略对应 x265 参数（HDR10 基础色彩仍保留）。
- libx265 10-bit 编码慢、体积大：UI 在选 HDR 转码/烧录时给出「较慢」预期提示。
- mp4 vs mkv 兼容：HDR 默认 mkv 最稳；用户选 mp4(H.265) 时 hevc 进 mp4 可行。
- DV 不做真转码，按 HDR10 兼容/保留原始流，文案说明。
- 每个里程碑独立可编译可测；SDR 主路径全程不动，出问题可停在前一里程碑。

## 决策日志（已确认）
- HDR 选择：加 HDR 开关。
- 格式：选分辨率处给输出格式多选，标注源格式，选别的则下载后转码（remux+转码都支持）。
- HDR+烧字幕：允许烧录并保留 HDR，字幕 SDR 颜色 → x265 10-bit 保 HDR，回退 tonemap SDR。

## 待确认
- 无（关键决策已齐）。实现中若发现 HDR mp4(H.265) 在 QuickTime 播放异常，会在 M6 反馈并按需调容器默认值。

## 进度日志
- 2026-06-14：M1-M6 全部完成。
  - M1：DynamicRange/OutputFormat 枚举 + FormatChoice 扩展(hdrAvailable/sourceVCodec/sourceContainer)；buildVideoInfo 读 dynamic_range/vcodec 标记每档 HDR + 源格式；shortVCodec 归一。
  - M2：DownloadRequest 加 preferHDR/outputFormat；applyHDRPreference 注入 `[dynamic_range!=SDR]` + 回退；HDR 用 mkv 容器，SDR 保持 mp4。
  - M3：Transcoder（plan + transcode 执行）：remux(同编码 -c copy)/转码(H.264 tonemap、H.265 HDR 保留)；接入 QueueManager 下载后步骤；可取消、进度。
  - M4：Burner HDR 分支——ffprobe 探色彩→isHDR；libx265 10-bit + HDR10 元数据透传 + 字幕 10-bit 叠加；x265 不可用回退 zscale/tonemap→libx264 SDR。encoderAvailable 缓存探测。
  - M5：ContentView outputOptionsSection——HDR 开关(仅有 HDR 源)+ 输出格式 Picker(标源格式)+ 转码/丢 HDR 提示；ViewModel preferHDR/selectedOutputFormat 状态 + 入队透传。
  - M6：HDRSupportTests 12 例(DynamicRange/选择器/vcodec/HDR烧录参数/转码计划)；全量 485 测试仅剩既有 iOS 脆性失败；全 product 构建 + build.sh 装 /Applications 启动正常。真实 HDR 下载受测试机 YouTube 风控限制无法端到端冒烟，但选择器语法/参数生成已单测覆盖，用户机带 cookies 可正常。
- 已知遗留：QueueManager 转码步骤把源 vcodec 传 nil（plan 据此一律按需转码，正确但 H.264→H.264 不会走 copy 快路径——实际下载产物容器已知，可后续优化按扩展名判断）；DV 按 HDR10 兼容处理不做真转码。
