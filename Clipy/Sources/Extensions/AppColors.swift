import Cocoa

/// 偏好设置界面的强调色与文字色。
///
/// 这几个颜色只需要跟随系统外观和强调色，因此全部基于 AppKit 语义色实现，
/// 不再像以前那样为明暗两套外观各写一份固定 RGB —— 玻璃材质的可读性高度依赖
/// 系统自动选出的文字颜色，语义色是唯一能保证对比度的来源。
enum AppColors {

    /// 品牌蓝，用于选中态。跟随系统的强调色深浅。
    static let clipy = NSColor.controlAccentColor

    /// 主要文字颜色。
    static let title = NSColor.labelColor

    /// 次要文字颜色（未选中的标签、说明文字）。
    static let tabTitle = NSColor.secondaryLabelColor

    /// 窗口背景。玻璃材质自带底色，这里只作为无玻璃时的兜底。
    static let windowBackground = NSColor.windowBackgroundColor

    /// 禁用态文字。
    static let disabledText = NSColor.tertiaryLabelColor
}
