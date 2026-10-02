//
//  CPYPreferencesWindowController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/02/25.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa

final class CPYPreferencesWindowController: NSWindowController {

    // MARK: - Properties
    static let sharedController = CPYPreferencesWindowController(windowNibName: "CPYPreferencesWindowController")
    @IBOutlet private weak var toolBar: NSView!
    // ViewController
    private let viewController = [CPYGeneralPreferenceViewController(nibName: "CPYGeneralPreferenceViewController", bundle: nil),
                                  NSViewController(nibName: "CPYMenuPreferenceViewController", bundle: nil),
                                  CPYTypePreferenceViewController(nibName: "CPYTypePreferenceViewController", bundle: nil),
                                  CPYExcludeAppPreferenceViewController(nibName: "CPYExcludeAppPreferenceViewController", bundle: nil),
                                  CPYShortcutsPreferenceViewController(nibName: "CPYShortcutsPreferenceViewController", bundle: nil),
                                  CPYUpdatesPreferenceViewController(nibName: "CPYUpdatesPreferenceViewController", bundle: nil)]
    // Liquid Glass
    private var windowGlass: GlassCard?
    /// Replaces the six icon buttons from the xib with one segmented control.
    private let tabControl = NSSegmentedControl()

    /// xib 里的标签，按标签页顺序排列。
    ///
    /// 直接复用而不是查 L10n：这些标题本来就定义在 xib 中并随界面一起本地化，
    /// 其中「Exclude」在 Localizable.strings 里并没有对应的 key，新增 key 会让
    /// 这个界面的文案来源分裂到两处。
    @IBOutlet private weak var generalTextField: NSTextField!
    @IBOutlet private weak var menuTextField: NSTextField!
    @IBOutlet private weak var typeTextField: NSTextField!
    @IBOutlet private weak var excludeTextField: NSTextField!
    @IBOutlet private weak var shortcutsTextField: NSTextField!
    @IBOutlet private weak var updatesTextField: NSTextField!

    // MARK: - Window Life Cycle
    override func windowDidLoad() {
        super.windowDidLoad()
        self.window?.collectionBehavior = .canJoinAllSpaces
        setupGlassBackdrop()
        setupTabControl()
        self.window?.titlebarAppearsTransparent = true
        selectTab(0)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(self)
    }
}

// MARK: - Liquid Glass
private extension CPYPreferencesWindowController {
    /// 在 xib 内容视图的最底层插入一层 regular 玻璃作为窗口背景。
    ///
    /// xib 有多语言版本（Base/de/it/ja/zh-Hans），改布局需要同步五份，因此玻璃层
    /// 完全在代码里注入。这里只把玻璃插到最底层，**不搬动 xib 的任何视图** ——
    /// 那些视图是 `translatesAutoresizingMaskIntoConstraints = NO` 且靠约束定位的，
    /// 一旦换父视图就要重写它们的约束。玻璃作为同级的最底层兄弟视图即可正确
    /// 覆盖在内容之下，无需重排层级。
    func setupGlassBackdrop() {
        guard let contentView = window?.contentView else { return }

        // The content view must stay transparent for the glass to show through.
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor

        let glass = GlassCard(hosting: NSView(frame: .zero),
                              style: .regular,
                              cornerRadius: GlassMetrics.windowCornerRadius)
        glass.translatesAutoresizingMaskIntoConstraints = false

        // Below every existing subview, so all xib content draws on top of it.
        contentView.addSubview(glass, positioned: .below, relativeTo: contentView.subviews.first)
        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: contentView.topAnchor),
            glass.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            glass.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        windowGlass = glass
    }

    /// 用一个分段控件替换 xib 里的六块图标按钮。
    ///
    /// 六个独立的玻璃按钮每个 50x56pt，视觉重量过大，且各自的 PNG 图标是为浅色
    /// 背景绘制的、在深色玻璃上对比度不足。分段控件由系统绘制，跟随外观与强调色，
    /// 也不需要为每种语言维护一套图标。
    func setupTabControl() {
        // The xib toolbar (buttons, icons, labels, separator) is replaced wholesale.
        toolBar.subviews.forEach { $0.removeFromSuperview() }
        toolBar.translatesAutoresizingMaskIntoConstraints = false

        let labels = [generalTextField, menuTextField, typeTextField,
                      excludeTextField, shortcutsTextField, updatesTextField].compactMap { $0 }
        tabControl.segmentCount = labels.count
        for (index, label) in labels.enumerated() {
            tabControl.setLabel(label.stringValue, forSegment: index)
        }
        tabControl.segmentStyle = .capsule
        tabControl.trackingMode = .selectOne
        tabControl.selectedSegment = 0
        tabControl.target = self
        tabControl.action = #selector(tabControlChanged(_:))
        tabControl.translatesAutoresizingMaskIntoConstraints = false
        tabControl.setAccessibilityLabel(L10n.preferences)
        toolBar.addSubview(tabControl)

        NSLayoutConstraint.activate([
            tabControl.topAnchor.constraint(equalTo: toolBar.topAnchor),
            tabControl.centerXAnchor.constraint(equalTo: toolBar.centerXAnchor),
            tabControl.bottomAnchor.constraint(equalTo: toolBar.bottomAnchor, constant: -10),
            // Let the control size itself from its labels rather than hard-coding a
            // width, so translated titles of differing length still fit.
            tabControl.leadingAnchor.constraint(greaterThanOrEqualTo: toolBar.leadingAnchor, constant: 16),
            tabControl.trailingAnchor.constraint(lessThanOrEqualTo: toolBar.trailingAnchor, constant: -16)
        ])
    }
}

// MARK: - Actions
extension CPYPreferencesWindowController {
    @objc private func tabControlChanged(_ sender: NSSegmentedControl) {
        selectTab(sender.selectedSegment)
    }
}

// MARK: - NSWindow Delegate
extension CPYPreferencesWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let viewController = viewController[2] as? CPYTypePreferenceViewController {
            AppEnvironment.current.defaults.set(viewController.storeTypes, forKey: Constants.UserDefaults.storeTypes)
            AppEnvironment.current.defaults.synchronize()
        }
        if let window = window, !window.makeFirstResponder(window) {
            window.endEditing(for: nil)
        }
        NSApp.deactivate()
    }
}

// MARK: - Layout
private extension CPYPreferencesWindowController {
    func selectTab(_ index: Int) {
        guard viewController.indices.contains(index) else { return }
        tabControl.selectedSegment = index
        switchView(index)
    }

    func switchView(_ index: Int) {
        guard let contentView = window?.contentView else { return }
        let newView = viewController[index].view
        // Remove current views without toolbar. The injected glass is skipped
        // too, otherwise it would be removed along with the panels.
        contentView.subviews.forEach { view in
            if view != toolBar && view !== windowGlass {
                view.removeFromSuperview()
            }
        }
        // Resize view
        let frame = window!.frame
        var newFrame = window!.frameRect(forContentRect: newView.frame)
        newFrame.origin = frame.origin
        newFrame.origin.y += frame.height - newFrame.height - toolBar.frame.height
        newFrame.size.height += toolBar.frame.height
        window?.setFrame(newFrame, display: true)
        contentView.addSubview(newView)
    }
}
