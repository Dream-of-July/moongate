import Foundation

#if !os(Windows)
/// macOS 依赖体检与一键安装支持：缺 yt-dlp/ffmpeg/deno 时 GUI 弹引导，
/// 经 Homebrew 安装；Homebrew 不存在时引导用户先装（绝不静默 curl|bash）。
public enum DependencySetup {

    public struct Component: Identifiable, Equatable {
        /// 展示名 = 二进制名
        public let id: String
        /// brew 公式名
        public let formula: String
        /// 一句话用途
        public let purpose: String
        public let isInstalled: Bool
        /// 是否属于普通下载链路的必需组件。
        public let isRequired: Bool
        /// 检测到的可执行文件路径；nil 表示未安装或不是本机可探测路径。
        public let installPath: String?

        public init(
            id: String,
            formula: String,
            purpose: String,
            isInstalled: Bool,
            isRequired: Bool,
            installPath: String? = nil
        ) {
            self.id = id
            self.formula = formula
            self.purpose = purpose
            self.isInstalled = isInstalled
            self.isRequired = isRequired
            self.installPath = installPath
        }
    }

    /// 依赖体检。ffmpeg 与 Burner 同口径：必须带 subtitles/libass 渲染能力；
    /// JS 运行时 deno/node 任一即可（yt-dlp 解 YouTube n-challenge 需要）。
    public static func check() -> [Component] {
        let ytDlpPath = find("yt-dlp")
        let subtitleRendererFfmpegPath = FFmpegBurner.locateSubtitleRendererFFmpeg()
        let jsRuntimePath = find("deno") ?? find("node")
        return components(
            ytDlpInstalled: ytDlpPath != nil,
            subtitleRendererFfmpegInstalled: subtitleRendererFfmpegPath != nil,
            jsRuntimeInstalled: jsRuntimePath != nil,
            ytDlpPath: ytDlpPath,
            subtitleRendererFfmpegPath: subtitleRendererFfmpegPath,
            jsRuntimePath: jsRuntimePath
        )
    }

    internal static func components(
        ytDlpInstalled: Bool,
        subtitleRendererFfmpegInstalled: Bool,
        jsRuntimeInstalled: Bool,
        ytDlpPath: String? = nil,
        subtitleRendererFfmpegPath: String? = nil,
        jsRuntimePath: String? = nil
    ) -> [Component] {
        [
            Component(
                id: "yt-dlp", formula: "yt-dlp",
                purpose: CoreL10n.t(L.Dependency.purposeYtDlp),
                isInstalled: ytDlpInstalled,
                isRequired: true,
                installPath: ytDlpPath
            ),
            Component(
                id: "ffmpeg", formula: "ffmpeg-full",
                purpose: CoreL10n.t(L.Dependency.purposeFfmpeg),
                isInstalled: subtitleRendererFfmpegInstalled,
                isRequired: true,
                installPath: subtitleRendererFfmpegPath
            ),
            Component(
                id: "deno", formula: "deno",
                purpose: CoreL10n.t(L.Dependency.purposeDeno),
                isInstalled: jsRuntimeInstalled,
                isRequired: true,
                installPath: jsRuntimePath
            ),
        ]
    }

    public static func missing(from components: [Component]) -> [Component] {
        components.filter { !$0.isInstalled }
    }

    public static func missingRequired(from components: [Component]) -> [Component] {
        components.filter { $0.isRequired && !$0.isInstalled }
    }

    public static func missingOptional(from components: [Component]) -> [Component] {
        components.filter { !$0.isRequired && !$0.isInstalled }
    }

    public static func needsSetup(_ components: [Component]) -> Bool {
        !missingRequired(from: components).isEmpty
    }

    public static var missing: [Component] { missingRequired(from: check()) }

    /// Homebrew 可执行路径（Apple Silicon / Intel 双位置）。
    public static func brewPath() -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func find(_ name: String) -> String? {
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
            let path = dir + "/" + name
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

}
#endif
