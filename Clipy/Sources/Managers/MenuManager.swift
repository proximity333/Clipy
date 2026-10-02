//
//  MenuManager.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/03/08.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import PINCache
import RealmSwift
import RxCocoa
import RxSwift

// swiftlint:disable file_length
final class MenuManager: NSObject {

    // MARK: - Properties
    // Menus
    fileprivate var clipMenu: NSMenu?
    fileprivate var statusMenu: NSMenu?
    fileprivate var historyMenu: NSMenu?
    // StatusMenu
    fileprivate var statusItem: NSStatusItem?
    // Icon Cache
    fileprivate let folderIcon = Asset.iconFolder.image
    // Other
    fileprivate let disposeBag = DisposeBag()
    fileprivate let kMaxKeyEquivalents = 10
    fileprivate let shortenSymbol = "..."
    // Realm
    fileprivate let realm = try! Realm()
    fileprivate var clipToken: NotificationToken?
    fileprivate var clipPreviewTextByItem = [ObjectIdentifier: String]()
    fileprivate let previewWindowController = MenuTooltipWindowController()
    // Search
    fileprivate var searchPopoverController: SearchPopoverController?
    fileprivate var searchMenuItem: NSMenuItem?
    fileprivate var searchFieldView: SearchFieldView?
    fileprivate var allClips: [CPYClip] = []
    fileprivate var filteredClips: [CPYClip] = []
    fileprivate var isSearching = false
    fileprivate var highlightedMenuItemIndex = -1

    // MARK: - Enum Values
    enum StatusType: Int {
        case none, black, white
    }

    // MARK: - Initialize
    override init() {
        super.init()
        folderIcon.isTemplate = true
        folderIcon.size = NSSize(width: 15, height: 13)
    }

    func setup() {
        bind()
    }

}

// MARK: - Popup Menu
extension MenuManager {
    func toggleSearchPopoverAtMouseLocation() {
        if let popover = searchPopoverController {
            searchPopoverController = nil
            popover.close()
            return
        }

        showSearchPopoverAtMouseLocation()
    }

    func popUpMenu(_ type: MenuType) {
        let menu: NSMenu?
        switch type {
        case .main:
            menu = clipMenu
        case .history:
            menu = historyMenu
        }
        menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    func showSearchPopoverAtMouseLocation() {
        guard searchPopoverController == nil else { return }

        let ascending = !AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.reorderClipsAfterPasting)
        let clips = Array(realm.objects(CPYClip.self)
            .sorted(byKeyPath: #keyPath(CPYClip.updateTime), ascending: ascending))

        let popover = SearchPopoverController(clips: clips)
        popover.delegate = self
        searchPopoverController = popover

        let mouseLocation = NSEvent.mouseLocation
        popover.show(at: mouseLocation)
    }

    func showSearchPopover(relativeTo rect: NSRect, of view: NSView) {
        if let popover = searchPopoverController {
            searchPopoverController = nil
            popover.close()
            return
        }

        let ascending = !AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.reorderClipsAfterPasting)
        let clips = Array(realm.objects(CPYClip.self)
            .sorted(byKeyPath: #keyPath(CPYClip.updateTime), ascending: ascending))

        let popover = SearchPopoverController(clips: clips)
        popover.delegate = self
        searchPopoverController = popover

        let point = view.window?.convertPoint(toScreen: rect.origin) ?? NSEvent.mouseLocation
        popover.show(at: point)
    }

    @objc func showSearchFromMenu() {
        if let button = statusItem?.button {
            let rect = NSRect(x: 0, y: 0, width: button.bounds.width, height: button.bounds.height)
            showSearchPopover(relativeTo: rect, of: button)
        } else {
            showSearchPopoverAtMouseLocation()
        }
    }

}

// MARK: - Binding
private extension MenuManager {
    func bind() {
        // Realm Notification
        clipToken = realm.objects(CPYClip.self)
                        .observe { [weak self] _ in
                            DispatchQueue.main.async { [weak self] in
                                self?.createClipMenu()
                            }
                        }
        // Menu icon
        AppEnvironment.current.defaults.rx.observe(Int.self, Constants.UserDefaults.showStatusItem, retainSelf: false)
            .compactMap { $0 }
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] key in
                self?.changeStatusItem(StatusType(rawValue: key) ?? .black)
            })
            .disposed(by: disposeBag)
        // Sort clips
        AppEnvironment.current.defaults.rx.observe(Bool.self, Constants.UserDefaults.reorderClipsAfterPasting, options: [.new], retainSelf: false)
            .compactMap { $0 }
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] _ in
                guard let wSelf = self else { return }
                wSelf.createClipMenu()
            })
            .disposed(by: disposeBag)
        // Observe change preference settings
        let defaults = AppEnvironment.current.defaults
        var menuChangedObservables = [Observable<Void>]()
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.addClearHistoryMenuItem, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Int.self, Constants.UserDefaults.maxHistorySize, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.showColorPreviewInTheMenu, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        Observable.merge(menuChangedObservables)
            .throttle(.seconds(1), scheduler: MainScheduler.instance)
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] in
                self?.createClipMenu()
            })
            .disposed(by: disposeBag)
    }
}

// MARK: - Menus
private extension MenuManager {
     func createClipMenu() {
        clipPreviewTextByItem.removeAll()
        previewWindowController.hide()

        clipMenu = NSMenu(title: Constants.Application.name)
        statusMenu = NSMenu(title: Constants.Application.name)
        historyMenu = NSMenu(title: Constants.Menu.history)

        clipMenu?.delegate = self
        historyMenu?.delegate = self

        // Add search menu item that triggers popover
        let searchItem = NSMenuItem(title: "搜索...", action: #selector(showSearchFromMenu), keyEquivalent: "f")
        searchItem.keyEquivalentModifierMask = [.command]
        searchItem.target = self
        clipMenu?.addItem(searchItem)
        clipMenu?.addItem(NSMenuItem.separator())

        // Cache all clips for searching
        cacheAllClips()

        // Add history items with filtering support
        addHistoryItems(clipMenu!, clips: isSearching ? filteredClips : allClips)
        addHistoryItems(historyMenu!, clips: isSearching ? filteredClips : allClips)

        if AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.addClearHistoryMenuItem) {
            clipMenu?.addItem(NSMenuItem.separator())
            clipMenu?.addItem(NSMenuItem(title: L10n.clearHistory, action: #selector(AppDelegate.clearAllHistory)))

            historyMenu?.addItem(NSMenuItem.separator())
            historyMenu?.addItem(NSMenuItem(title: L10n.clearHistory, action: #selector(AppDelegate.clearAllHistory)))

            statusMenu?.addItem(NSMenuItem(title: L10n.clearHistory, action: #selector(AppDelegate.clearAllHistory)))
            statusMenu?.addItem(NSMenuItem.separator())
        }

        clipMenu?.addItem(NSMenuItem.separator())
        statusMenu?.addItem(NSMenuItem.separator())

        clipMenu?.addItem(NSMenuItem(title: L10n.preferences, action: #selector(AppDelegate.showPreferenceWindow)))
        clipMenu?.addItem(NSMenuItem.separator())
        clipMenu?.addItem(NSMenuItem(title: L10n.quitClipy, action: #selector(AppDelegate.terminate)))

        statusMenu?.addItem(NSMenuItem(title: L10n.preferences, action: #selector(AppDelegate.showPreferenceWindow)))
        statusMenu?.addItem(NSMenuItem.separator())
        statusMenu?.addItem(NSMenuItem(title: L10n.quitClipy, action: #selector(AppDelegate.terminate)))

        statusItem?.menu = statusMenu
    }

    func menuItemTitle(_ title: String) -> String {
        return title
    }

    func imageMenuItemTitle(_ title: String, image: NSImage?) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = max(font.capHeight, image?.size.height ?? 0)
        paragraphStyle.maximumLineHeight = paragraphStyle.minimumLineHeight

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .baselineOffset: 1
        ]
        let attributed = NSMutableAttributedString(string: "", attributes: attributes)

        if let image {
            let attachment = NSTextAttachment()
            attachment.image = image
            let yOffset = (font.capHeight - image.size.height) / 2
            attachment.bounds = NSRect(x: 0, y: yOffset, width: image.size.width, height: image.size.height)
            attributed.append(NSAttributedString(attachment: attachment))
            attributed.append(NSAttributedString(string: " ", attributes: attributes))
        }

        attributed.append(NSAttributedString(string: title, attributes: attributes))
        return attributed
    }

    func makeSubmenuItem(_ count: Int, start: Int, end: Int, numberOfItems: Int) -> NSMenuItem {
        var count = count
        if start == 0 {
            count -= 1
        }
        var lastNumber = count + numberOfItems
        if end < lastNumber {
            lastNumber = end
        }
        let menuItemTitle = "\(count + 1) - \(lastNumber)"
        return makeSubmenuItem(menuItemTitle)
    }

    func makeSubmenuItem(_ title: String) -> NSMenuItem {
        let subMenu = NSMenu(title: "")
        subMenu.delegate = self
        let subMenuItem = NSMenuItem(title: title, action: nil)
        subMenuItem.submenu = subMenu
        subMenuItem.image = folderIcon
        return subMenuItem
    }

    func trimTitle(_ title: String?) -> String {
        if title == nil { return "" }
        let theString = title!.trimmingCharacters(in: .whitespacesAndNewlines) as NSString

        let aRange = NSRange(location: 0, length: 0)
        var lineStart = 0, lineEnd = 0, contentsEnd = 0
        theString.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: aRange)

        var titleString = (lineEnd == theString.length) ? theString as String : theString.substring(to: contentsEnd)

        var maxMenuItemTitleLength = 20
        if maxMenuItemTitleLength < shortenSymbol.count {
            maxMenuItemTitleLength = shortenSymbol.count
        }

        if titleString.utf16.count > maxMenuItemTitleLength {
            titleString = (titleString as NSString).substring(to: maxMenuItemTitleLength - shortenSymbol.count) + shortenSymbol
        }

        return titleString as String
    }

}

// MARK: - Clips
private extension MenuManager {
    func addHistoryItems(_ menu: NSMenu, clips: [CPYClip]) {
        let maxHistory = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxHistorySize)

        // History title
        let labelItem = NSMenuItem(title: L10n.history, action: nil)
        labelItem.isEnabled = false
        menu.addItem(labelItem)

        for (index, clip) in clips.enumerated() {
            if maxHistory <= index { break }

            let menuItem = makeClipMenuItem(clip, index: index)
            menu.addItem(menuItem)
        }
    }

    func makeClipMenuItem(_ clip: CPYClip, index: Int) -> NSMenuItem {
        let isShowColorCode = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showColorPreviewInTheMenu)

        let primaryPboardType = NSPasteboard.PasteboardType(rawValue: clip.primaryType)
        let clipString = clip.title
        let title = trimTitle(clipString)
        let titleWithMark = menuItemTitle(title)
        let imageOnlyTitle = menuItemTitle("(Image)")
        let fileOnlyTitle = menuItemTitle("(Filenames)")

        let menuItem = NSMenuItem(title: titleWithMark, action: #selector(AppDelegate.selectClipMenuItem(_:)))
        menuItem.representedObject = clip.dataHash
        clipPreviewTextByItem[ObjectIdentifier(menuItem)] = clipString
        menuItem.toolTip = nil

        if primaryPboardType == .deprecatedTIFF {
            menuItem.title = imageOnlyTitle
        } else if primaryPboardType == .deprecatedPDF {
            menuItem.title = menuItemTitle("(PDF)")
        } else if primaryPboardType == .deprecatedFilenames && title.isEmpty {
            menuItem.title = fileOnlyTitle
        }

        if !clip.thumbnailPath.isEmpty && !clip.isColorCode {
            let displayTitle: String
            if primaryPboardType == .deprecatedTIFF {
                displayTitle = title.isEmpty ? "(Image)" : title
            } else if primaryPboardType == .deprecatedFilenames && title.isEmpty {
                displayTitle = "(Filenames)"
            } else {
                displayTitle = title
            }

            let cachedThumbnailPath = clip.thumbnailPath
            let cachedDataPath = clip.dataPath
            PINCache.shared.object(forKeyAsync: cachedThumbnailPath) { [weak self, weak menuItem] _, _, object in
                DispatchQueue.main.async {
                    guard let self, let menuItem else { return }
                    if let image = object as? NSImage {
                        menuItem.image = nil
                        menuItem.attributedTitle = self.imageMenuItemTitle(displayTitle, image: image)
                    } else if !cachedDataPath.isEmpty {
                        // Fallback: regenerate thumbnail from .data file
                        if let data = NSKeyedUnarchiver.unarchiveObject(withFile: cachedDataPath) as? CPYClipData,
                           let thumbnail = data.thumbnailImage {
                            PINCache.shared.setObject(thumbnail, forKey: cachedThumbnailPath)
                            menuItem.image = nil
                            menuItem.attributedTitle = self.imageMenuItemTitle(displayTitle, image: thumbnail)
                        }
                    }
                }
            }
        }
        if !clip.thumbnailPath.isEmpty && clip.isColorCode && isShowColorCode {
            PINCache.shared.object(forKeyAsync: clip.thumbnailPath) { [weak menuItem] _, _, object in
                DispatchQueue.main.async {
                    menuItem?.image = object as? NSImage
                }
            }
        }

        return menuItem
    }
}

// MARK: - Search
private extension MenuManager {
    func cacheAllClips() {
        let ascending = !AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.reorderClipsAfterPasting)
        allClips = Array(realm.objects(CPYClip.self)
            .sorted(byKeyPath: #keyPath(CPYClip.updateTime), ascending: ascending))

        if isSearching {
            filterClips(with: searchFieldView?.searchTextField.stringValue ?? "")
        } else {
            filteredClips = allClips
        }
    }

    func addSearchMenuItem(to menu: NSMenu) {
        let searchItem = NSMenuItem()
        let menuWidth = estimatedMenuWidth(for: menu)

        // Container view with padding
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 36))
        containerView.autoresizingMask = [.width]

        // Search field view
        searchFieldView = SearchFieldView(frame: NSRect(x: 16, y: 4, width: menuWidth - 32, height: 28))
        searchFieldView?.autoresizingMask = [.width]
        searchFieldView?.searchTextField.searchDelegate = self

        if let searchFieldView = searchFieldView {
            containerView.addSubview(searchFieldView)
        }

        searchItem.view = containerView
        menu.addItem(searchItem)
        searchMenuItem = searchItem
    }

    func filterClips(with searchText: String) {
        if searchText.isEmpty {
            filteredClips = allClips
            isSearching = false
        } else {
            filteredClips = allClips.filter { clip in
                clip.title.localizedCaseInsensitiveContains(searchText)
            }
            isSearching = true
        }
    }

    func highlightNextMenuItem() {
        let menu = clipMenu
        let items = menu?.items.filter { $0.isEnabled && !$0.isSeparatorItem && $0.view == nil } ?? []

        highlightedMenuItemIndex = min(highlightedMenuItemIndex + 1, items.count - 1)
        if highlightedMenuItemIndex >= 0 && highlightedMenuItemIndex < items.count {
            // Simulate down arrow key event to highlight next menu item
            let event = NSEvent.keyEvent(with: .keyDown,
                                         location: NSPoint.zero,
                                         modifierFlags: [],
                                         timestamp: 0,
                                         windowNumber: 0,
                                         context: nil,
                                         characters: "",
                                         charactersIgnoringModifiers: "",
                                         isARepeat: false,
                                         keyCode: 125) // Down arrow key code
            if let event = event {
                menu?.performKeyEquivalent(with: event)
            }
        }
    }

    func highlightPreviousMenuItem() {
        let menu = clipMenu
        let items = menu?.items.filter { $0.isEnabled && !$0.isSeparatorItem && $0.view == nil } ?? []

        highlightedMenuItemIndex = max(highlightedMenuItemIndex - 1, 0)
        if highlightedMenuItemIndex >= 0 && highlightedMenuItemIndex < items.count {
            // Simulate up arrow key event to highlight previous menu item
            let event = NSEvent.keyEvent(with: .keyDown,
                                         location: NSPoint.zero,
                                         modifierFlags: [],
                                         timestamp: 0,
                                         windowNumber: 0,
                                         context: nil,
                                         characters: "",
                                         charactersIgnoringModifiers: "",
                                         isARepeat: false,
                                         keyCode: 126) // Up arrow key code
            if let event = event {
                menu?.performKeyEquivalent(with: event)
            }
        }
    }
}

// MARK: - Status Item
private extension MenuManager {
    func changeStatusItem(_ type: StatusType) {
        removeStatusItem()
        if type == .none { return }

        let image: NSImage?
        switch type {
        case .black:
            image = Asset.statusbarMenuBlack.image
        case .white:
            image = Asset.statusbarMenuWhite.image
        case .none: return
        }
        image?.isTemplate = true

        statusItem = NSStatusBar.system.statusItem(withLength: -1)
        statusItem?.image = image
        statusItem?.highlightMode = true
        statusItem?.toolTip = "\(Constants.Application.name)\(Bundle.main.appVersion ?? "")"
        statusItem?.menu = statusMenu
    }

    func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
}

// MARK: - Settings
private extension MenuManager {
    func estimatedMenuWidth(for menu: NSMenu) -> CGFloat {
        let font = NSFont.menuFont(ofSize: 0)
        let longestTitleWidth = menu.items
            .map { item -> CGFloat in
                guard !item.title.isEmpty else { return 0 }
                return ceil((item.title as NSString).size(withAttributes: [.font: font]).width)
            }
            .max() ?? 0

        return max(132, min(220, longestTitleWidth + 28))
    }

    func shouldShowPreview(for fullText: String, displayedTitle: String) -> Bool {
        let normalized = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }

        let trimmed = trimTitle(fullText)
        return trimmed != normalized || displayedTitle.contains(shortenSymbol)
    }

    func isHistoryMenu(_ menu: NSMenu?) -> Bool {
        var currentMenu = menu
        while let menu = currentMenu {
            if menu == historyMenu || menu == clipMenu {
                return true
            }
            currentMenu = menu.supermenu
        }
        return false
    }
}

// MARK: - NSMenuDelegate
extension MenuManager: NSMenuDelegate {
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        guard isHistoryMenu(menu) else {
            previewWindowController.hide()
            return
        }

        guard let item,
              let fullText = clipPreviewTextByItem[ObjectIdentifier(item)] else {
            previewWindowController.hide()
            return
        }

        guard shouldShowPreview(for: fullText, displayedTitle: item.title) else {
            previewWindowController.hide()
            return
        }

        previewWindowController.show(text: fullText,
                                     near: NSEvent.mouseLocation,
                                     estimatedMenuWidth: estimatedMenuWidth(for: menu))
    }

    func menuDidClose(_ menu: NSMenu) {
        previewWindowController.hide()
    }
}

private final class MenuTooltipWindowController {
    private let panel: NSPanel
    private let textField: NSTextField
    private let glass: GlassCard
    private let content: NSView
    private let maxSize = NSSize(width: 360, height: 180)
    private let minSize = NSSize(width: 240, height: 52)
    private let contentInset = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
    private let horizontalGap: CGFloat = 2

    init() {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: minSize),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]

        content = NSView(frame: NSRect(origin: .zero, size: minSize))
        // Regular glass: this is a standalone floating panel, not a card inside
        // one, so it uses the more opaque variant.
        glass = GlassCard(hosting: content, style: .regular, cornerRadius: GlassMetrics.previewCornerRadius)

        textField = NSTextField(wrappingLabelWithString: "")
        textField.frame = NSRect(x: contentInset.left,
                                 y: contentInset.bottom,
                                 width: minSize.width - contentInset.left - contentInset.right,
                                 height: minSize.height - contentInset.top - contentInset.bottom)
        textField.font = NSFont.systemFont(ofSize: 12.5, weight: .regular)
        textField.textColor = .labelColor
        textField.maximumNumberOfLines = 0
        textField.lineBreakMode = .byWordWrapping

        content.addSubview(textField)
        panel.contentView = glass
        panel.orderOut(nil)
    }

    func show(text: String, near point: NSPoint, estimatedMenuWidth: CGFloat) {
        textField.stringValue = text
        layoutWindow(for: text, near: point, estimatedMenuWidth: estimatedMenuWidth)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func layoutWindow(for text: String, near point: NSPoint, estimatedMenuWidth: CGFloat) {
        let maxTextSize = NSSize(width: maxSize.width - contentInset.left - contentInset.right,
                                 height: .greatestFiniteMagnitude)
        let measured = (text as NSString).boundingRect(
            with: maxTextSize,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: textField.font as Any],
            context: nil
        ).integral

        let width = min(max(measured.width + contentInset.left + contentInset.right, minSize.width), maxSize.width)
        let height = min(max(measured.height + contentInset.top + contentInset.bottom, minSize.height), maxSize.height)

        panel.setContentSize(NSSize(width: width, height: height))
        textField.frame = NSRect(x: contentInset.left,
                                 y: contentInset.bottom,
                                 width: width - contentInset.left - contentInset.right,
                                 height: height - contentInset.top - contentInset.bottom)

        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? .zero

        var origin = NSPoint(x: point.x + estimatedMenuWidth + horizontalGap,
                             y: point.y - min(height * 0.55, 26))
        if origin.x + width > visibleFrame.maxX {
            origin.x = point.x - estimatedMenuWidth - width - horizontalGap
        }
        origin.x = max(visibleFrame.minX + 4, min(origin.x, visibleFrame.maxX - width - 4))
        origin.y = max(visibleFrame.minY + 4, min(origin.y, visibleFrame.maxY - height - 4))

        panel.setFrameOrigin(origin)
    }
}

// MARK: - SearchTextFieldDelegate
extension MenuManager: SearchTextFieldDelegate {
    func searchTextFieldDidReceiveEscape(_ textField: SearchTextField) {
        isSearching = false
        textField.stringValue = ""
        highlightedMenuItemIndex = -1
        createClipMenu()
    }

    func searchTextFieldDidReceiveEnter(_ textField: SearchTextField) {
        if !filteredClips.isEmpty {
            let menu = clipMenu
            let items = menu?.items.filter { $0.isEnabled && !$0.isSeparatorItem && $0.view == nil } ?? []

            if highlightedMenuItemIndex >= 0 && highlightedMenuItemIndex < items.count {
                let menuItem = items[highlightedMenuItemIndex]
                if let action = menuItem.action, let target = menuItem.target {
                    NSApp.sendAction(action, to: target, from: menuItem)
                }
            } else if let firstClip = filteredClips.first {
                // Select first clip
                let pasteService = AppEnvironment.current.pasteService
                pasteService.paste(with: firstClip)
            }
        }

        isSearching = false
        textField.stringValue = ""
        highlightedMenuItemIndex = -1
        createClipMenu()
    }

    func searchTextFieldDidReceiveUpArrow(_ textField: SearchTextField) {
        highlightPreviousMenuItem()
    }

    func searchTextFieldDidReceiveDownArrow(_ textField: SearchTextField) {
        highlightNextMenuItem()
    }
}

// MARK: - SearchPopoverDelegate
extension MenuManager: SearchPopoverDelegate {
    func searchPopoverDidSelectResult(_ result: SearchPopoverController.ResultItem) {
        let previousApp = searchPopoverController?.previousActiveApp
        let pasteService = AppEnvironment.current.pasteService
        switch result {
        case let .clip(clip):
            pasteService.paste(with: clip)
        }
        let popover = searchPopoverController
        searchPopoverController = nil
        popover?.close()
        previousApp?.activate(options: [])
    }

    func searchPopoverDidCancel() {
        searchPopoverController = nil
    }
}
