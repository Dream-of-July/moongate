import SwiftUI

/// 统一的视频缩略图内容视图。
///
/// 三态一致：成功显示图片（`scaledToFill` 裁切填充），加载中显示轻量 `ProgressView`，
/// 失败 / 无 URL 显示 `film` 占位。相比过去「加载时就闪 film 占位」的写法，加载态改用
/// 进度指示，避免有缩略图的视频先闪一下「无缩略图」的观感（HIG progressive-loading）。
///
/// 尺寸由调用方用 `.frame(...)` 决定（各处缩略图大小不同），本组件只负责内容、裁切与
/// 统一的 0.5pt hairline 描边。占位图标大小、圆角、进度环尺寸通过参数定制。
struct VideoThumbnail: View {
    /// 缩略图 URL；为 nil 时直接显示 film 占位。
    let url: URL?
    /// 圆角半径，默认信息卡缩略图规格。
    var cornerRadius: CGFloat = Radius.thumbnailCard
    /// film 占位图标大小；默认 `.body`（等价于不设 font 的原生行为）。
    var placeholderFont: Font = .body
    /// 加载中 ProgressView 的控件尺寸。
    var progressControlSize: ControlSize = .small

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .empty where url != nil:
                // 有 URL 且加载中：轻量进度指示，避免立刻闪现 film 占位。
                Rectangle()
                    .fill(.quaternary)
                    .overlay(ProgressView().controlSize(progressControlSize))
            default:
                // 失败 / 无 URL：film 占位。
                Rectangle()
                    .fill(.quaternary)
                    .overlay(
                        Image(systemName: "film")
                            .font(placeholderFont)
                            .foregroundStyle(.tertiary)
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        // 极细描边让缩略图从背景「浮起」，light/dark 两种模式下都能形成清晰边界。
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: Stroke.hairline)
        )
    }
}
