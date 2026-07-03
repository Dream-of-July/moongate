import SwiftUI

// Moongate 设计令牌：把散落的间距 / 圆角 / 尺寸 / 线宽魔法数字收敛为一处语义化来源，
// 为后续三栏重构打基础。用 enum 命名空间 + 静态常量（SwiftUI 惯用写法，零运行时开销）。
//
// 取值贴合 macOS HIG（8pt 行内节奏、16-20pt 内容边距、8-12pt 卡片圆角），但本轮的首要
// 目标是「等价收敛、零视觉变化」：所有数值精确取自现有代码，不趁机调整。少数不在 8pt
// 网格上的值（间距 5/10/14、圆角 5）被显式保留并注明「off-grid」，作为待评估的例外，
// 而不是被强行并入网格。
//
// 字号刻意不进 token：一律用系统文本样式（.headline / .body / .caption 等），以吃到
// Dynamic Type 与平台一致性。动画时长同样不在此层。

/// 间距刻度（水平 / 垂直留白、行内间距、内容边距）。
enum Spacing {
    static let xxs: CGFloat = 2         // 微距：贴近元素的顶部留白（展开区、提示行）
    static let xs: CGFloat = 4          // 紧凑：展开信息的行距
    static let rowTitleGap: CGFloat = 5 // off-grid：列表行 / 信息卡「标题—副文」两级行距，保留现值 5
    static let sm: CGFloat = 6          // 小间距：图标按钮组
    static let md: CGFloat = 8          // 行内元素默认节奏
    static let rowGutter: CGFloat = 10  // off-grid：队列行「缩略图—文本」水平间距与行内边距，保留现值 10
    static let lg: CGFloat = 12         // 卡片内边距 / 主要行内间距
    static let emptyStack: CGFloat = 14 // off-grid：空状态图标区纵向节奏，保留现值 14
    static let xl: CGFloat = 16         // 内容区水平边距（HIG 标准，供后续布局使用）
    static let xxl: CGFloat = 20        // 内容区水平边距上限（HIG 标准，供后续布局使用）
    static let xxxl: CGFloat = 32       // 空状态大留白（水平边距）
}

/// 圆角刻度。按实际承载的 UI 元素语义命名。
enum Radius {
    static let thumbnailRow: CGFloat = 5  // off-grid：队列行缩略图，明确保留 5（不并到 6）
    static let thumbnailCard: CGFloat = 8 // 信息卡缩略图
    static let card: CGFloat = 10         // 卡片背景
}

/// 缩略图尺寸。
enum Thumbnail {
    static let cardWidth: CGFloat = 160  // 信息卡缩略图（16:9）
    static let cardHeight: CGFloat = 90
    static let rowWidth: CGFloat = 64     // 队列行缩略图（16:9）
    static let rowHeight: CGFloat = 36
}

/// 极细描边线宽（缩略图 / 卡片从背景「浮起」用）。
enum Stroke {
    static let hairline: CGFloat = 0.5
}
