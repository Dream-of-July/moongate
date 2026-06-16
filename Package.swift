// swift-tools-version: 5.10
import PackageDescription

// GUI（SwiftUI/AppKit/WebKit）仅 macOS；Windows 上只构建核心库与 CLI。
var packageProducts: [Product] = [
    .library(name: "MoongateMobileCore", targets: ["MoongateMobileCore"]),
    .executable(name: "moongate-cli", targets: ["moongate-cli"]),
]

var packageTargets: [Target] = [
    // 移动端纯契约：不得依赖桌面 Process/Homebrew/AppKit/Windows 实现。
    .target(name: "MoongateMobileCore", path: "Sources/MoongateMobileCore"),
    // 核心逻辑：链接嗅探 + yt-dlp 封装 + 翻译 + 烧录，可被 App 和 CLI 共用
    .target(name: "MoongateCore", dependencies: ["MoongateMobileCore"], path: "Sources/MoongateCore"),
    // 命令行工具：跨平台（macOS / Windows），不开 GUI 也能走全流程
    .executableTarget(
        name: "moongate-cli",
        dependencies: ["MoongateCore"],
        path: "Sources/moongate-cli"
    ),
    .testTarget(
        name: "MoongateCoreTests",
        dependencies: ["MoongateCore", "MoongateMobileCore"],
        path: "Tests/MoongateCoreTests"
    ),
]

#if os(macOS)
packageProducts.append(
    .library(name: "MoongateiOS", targets: ["MoongateiOS"])
)

packageProducts.append(
    .executable(name: "MoongateiOSApp", targets: ["MoongateiOSApp"])
)

packageProducts.append(
    .executable(name: "Moongate", targets: ["Moongate"])
)

packageTargets.append(
    // iOS 首版 reviewable shell：只依赖移动端纯契约和 mock 状态，不复用桌面 Process/Homebrew UI。
    .target(
        name: "MoongateiOS",
        dependencies: ["MoongateMobileCore"],
        path: "Sources/MoongateiOS"
    )
)

packageTargets.append(
    // iOS App host：只组合 iOS shell，后续由 Xcode/iOS 工程接入签名、权限和 entitlements。
    .executableTarget(
        name: "MoongateiOSApp",
        dependencies: ["MoongateiOS"],
        path: "Sources/MoongateiOSApp"
    )
)

packageTargets.append(
    .testTarget(
        name: "MoongateiOSTests",
        dependencies: ["MoongateiOS", "MoongateMobileCore"],
        path: "Tests/MoongateiOSTests"
    )
)

packageTargets.append(
    // SwiftUI 图形界面 App（仅 macOS）
    .executableTarget(
        name: "Moongate",
        dependencies: ["MoongateCore"],
        path: "Sources/Moongate"
    )
)
#endif

let package = Package(
    name: "Moongate",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: packageProducts,
    targets: packageTargets
)
