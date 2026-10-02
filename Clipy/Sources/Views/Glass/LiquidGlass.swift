//
//  LiquidGlass.swift
//  Clipy
//
//  Liquid Glass 基础设施：全 App 共享的玻璃度量、容器与控件样式。
//
//

import Cocoa

// MARK: - Metrics

/// 全 App 共享的玻璃视觉度量。
///
/// 圆角与内边距集中在这里定义，避免每个视图各写一套数值，
/// 也是让浮窗、卡片、按钮之间保持同心圆角关系的前提。
enum GlassMetrics {
    /// 顶层浮窗圆角（搜索面板、菜单内容预览浮窗）。
    static let windowCornerRadius: CGFloat = 18
    /// 浮窗内卡片圆角。
    static let cardCornerRadius: CGFloat = 16
    /// 菜单内容预览浮窗的圆角，比主面板略小。
    static let previewCornerRadius: CGFloat = 12
    /// 浮窗内容与边缘的留白。
    ///
    /// 8pt 而非更宽的值：内容区已不再由卡片框住，留白过大时面板边缘会显出一圈
    /// 空荡的玻璃，把内容挤到中间。
    static let panelInset: CGFloat = 8
    /// 玻璃图标按钮的边长。
    static let iconButtonSide: CGFloat = 24
}

// MARK: - GlassCard

/// 一块 Liquid Glass 面板：玻璃材质负责背景与圆角，`content` 是它的内容。
///
/// 布局上有两个要点：
///
/// 1. 内容通过 `NSGlassEffectView.contentView` 进入玻璃内部，由 AppKit 内部的
///    holder 承载并自动铺满 `bounds`。因此**不能**再把内容手动
///    `addSubview` 到玻璃上，否则会与系统的 holder 争抢层级。
/// 2. 内容自动铺满，所以内容自身的约束都相对内容视图本身书写，不要再对
///    内容加相对本视图的定位约束，否则会与系统的铺满约束冲突。
final class GlassCard: NSView {

    /// 渲染玻璃材质的系统视图。需要换样式或色调时改它。
    let glass: NSGlassEffectView

    /// 玻璃内部的内容视图，始终与 `GlassCard` 等大。
    let content: NSView

    /// - Parameters:
    ///   - content: 放进玻璃里的内容视图。
    ///   - style: `.regular` 用于最外层浮窗与独立浮窗，`.clear` 用于嵌在浮窗内的卡片。
    ///   - cornerRadius: 玻璃圆角。
    ///   - tintColor: 玻璃色调，`nil` 表示不着色。
    ///   - interactive: 是否对悬停/按下做出视觉反馈（macOS 27+）。
    init(hosting content: NSView,
         style: NSGlassEffectView.Style = .clear,
         cornerRadius: CGFloat = GlassMetrics.cardCornerRadius,
         tintColor: NSColor? = nil,
         interactive: Bool = false) {
        self.content = content
        glass = NSGlassEffectView()
        super.init(frame: .zero)

        glass.style = style
        glass.cornerRadius = cornerRadius
        glass.tintColor = tintColor
        if #available(macOS 27.0, *) {
            glass.effectIsInteractive = interactive
        }

        // Both flags matter. Without `glass` opting into Auto Layout the edge
        // constraints below are silently ignored, so the glass keeps its 0x0
        // initial frame — and because the content is laid out *inside* the
        // glass, that collapses the content too (everything piles up at 0,0).
        glass.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView = content

        addSubview(glass)
        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - GlassContainer

/// 把若干玻璃卡片包进一个 `NSGlassEffectContainerView`。
///
/// 系统据此对相邻且相似的玻璃做合并渲染，省掉重复的材质采样。
/// `spacing` 为 0 表示不做主动合并，只做批处理，适合有间隙的卡片布局。
final class GlassContainer: NSView {

    let container: NSGlassEffectContainerView

    init(hosting content: NSView) {
        container = NSGlassEffectContainerView()
        super.init(frame: .zero)

        container.spacing = 0
        container.translatesAutoresizingMaskIntoConstraints = false
        container.contentView = content
        addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - GlassIconButton

/// 玻璃图标按钮：系统玻璃外观 + 圆形边框 + SF Symbol。
///
/// 替代过去 `bezelStyle = .texturedRounded` + `isBordered = false` 的组合，
/// 后者在 macOS 26 上是旧式浮雕描边，与玻璃语言不搭。
final class GlassIconButton: NSButton {

    /// SF Symbol 的无障碍描述，切换图标时复用。
    private let symbolLabel: String

    init(systemSymbolName: String, accessibilityLabel: String, toolTip: String? = nil, target: AnyObject?, action: Selector) {
        symbolLabel = accessibilityLabel
        super.init(frame: .zero)
        self.image = NSImage(systemSymbolName: systemSymbolName, accessibilityDescription: accessibilityLabel)
        self.imagePosition = .imageOnly
        self.target = target
        self.action = action
        self.toolTip = toolTip
        configureGlassStyle()
    }

    required init?(coder: NSCoder) {
        symbolLabel = ""
        super.init(coder: coder)
        configureGlassStyle()
    }

    private func configureGlassStyle() {
        bezelStyle = .glass
        borderShape = .circle
        isBordered = true
        contentTintColor = .secondaryLabelColor
        translatesAutoresizingMaskIntoConstraints = false
    }

    /// 切换 SF Symbol，用于同一按钮在不同状态下换图标（如收藏 / 取消收藏）。
    func setSymbol(_ systemSymbolName: String) {
        image = NSImage(systemSymbolName: systemSymbolName, accessibilityDescription: symbolLabel)
    }
}
