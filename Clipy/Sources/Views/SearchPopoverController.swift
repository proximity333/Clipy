//
//  SearchPopoverController.swift
//  Clipy
//
//  Created by AI Assistant on 2026/05/17.
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import PINCache
import RealmSwift

protocol SearchPopoverDelegate: AnyObject {
    func searchPopoverDidSelectResult(_ result: SearchPopoverController.ResultItem)
    func searchPopoverDidCancel()
}

// swiftlint:disable type_body_length file_length
final class SearchPopoverController: NSViewController {
    enum FilterTab: Int, CaseIterable {
        case all
        case history
        case favorites

        var title: String {
            switch self {
            case .all: return "全部"
            case .history: return "粘贴历史"
            case .favorites: return "收藏"
            }
        }
    }

    enum ResultItem {
        case clip(CPYClip)
    }

    // MARK: - Properties
    weak var delegate: SearchPopoverDelegate?

    private var clips: [CPYClip]
    private var filteredResults: [ResultItem]
    private var activeTab: FilterTab = .all
    private var searchWindow: SearchWindow?
    private var clickMonitor: Any?
    private(set) var previousActiveApp: NSRunningApplication?

    // 最外层玻璃浮窗。内部依次是拖拽条、搜索卡片与内容区。
    //
    // 整块面板只保留这一层玻璃：Liquid Glass 每多嵌套一层就会把背景再折射一次，
    // 四层 `.clear` 叠在 `.regular` 上会让整个面板发浑。内部区域因此改用无材质的
    // 普通视图，只靠留白与极淡分割线分区。
    private let chromeView = NSView()
    private lazy var chromeCard = GlassCard(hosting: chromeView,
                                            style: .regular,
                                            cornerRadius: GlassMetrics.windowCornerRadius)

    // 搜索栏：唯一的第二层玻璃，用在输入区形成视觉焦点。
    private let searchContainer = NSView()
    private lazy var searchCard = GlassCard(hosting: searchContainer, style: .clear)

    private let searchField = NSSearchField()
    private let tabContainer = NSView()
    private let tabSegmentedControl = NSSegmentedControl()
    private let settingsButton = GlassIconButton(systemSymbolName: "gearshape",
                                                 accessibilityLabel: "设置",
                                                 target: nil,
                                                 action: #selector(openSettings))
    private let resetLayoutButton = GlassIconButton(systemSymbolName: "arrow.counterclockwise",
                                                    accessibilityLabel: "恢复默认布局",
                                                    toolTip: "恢复默认窗口尺寸与分栏位置",
                                                    target: nil,
                                                    action: #selector(resetLayoutToDefault))
    private let dragBar = DragBarView()

    // 内容区：无玻璃。列表、预览、信息栏靠留白和一条细分隔线区分。
    private let contentContainer = NSView()
    private let listContainer = NSView()
    private let previewContainer = NSView()
    private let metaContainer = NSView()
    private let splitDivider = SplitDividerView()

    private static let defaultWindowSize = NSSize(width: 640, height: 420)
    private static let minimumWindowSize = NSSize(width: 480, height: 320)
    private static let maximumWindowSize = NSSize(width: 960, height: 640)
    private static let defaultListWidth: CGFloat = 220

    private var listWidthConstraint: NSLayoutConstraint?
    private var chromeWidthConstraint: NSLayoutConstraint?
    private var chromeHeightConstraint: NSLayoutConstraint?
    private var splitDividerLocation: CGFloat = 220

    private let listTitleLabel = NSTextField(labelWithString: "")
    private let listActionButton = NSButton()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let emptyStateLabel = NSTextField(labelWithString: "未找到匹配的历史记录")

    private let previewImageView = NSImageView()
    private let previewTextScrollView = NSScrollView()
    private let previewTextView = NSTextView()
    private let previewTitleLabel = NSTextField(labelWithString: "")
    private let previewSubtitleLabel = NSTextField(labelWithString: "")
    private var previewImageFixedHeightConstraint: NSLayoutConstraint?
    private var previewImageBottomConstraint: NSLayoutConstraint?
    private var previewImageZeroHeightConstraint: NSLayoutConstraint?
    private var previewTextTopConstraint: NSLayoutConstraint?
    private var previewTextBottomConstraint: NSLayoutConstraint?

    private let deleteButton = GlassIconButton(systemSymbolName: "trash",
                                               accessibilityLabel: "删除",
                                               target: nil,
                                               action: #selector(deleteCurrentItem))
    private let favoriteButton = GlassIconButton(systemSymbolName: "star",
                                                 accessibilityLabel: "收藏",
                                                 toolTip: "收藏/取消收藏",
                                                 target: nil,
                                                 action: #selector(toggleFavorite))

    private let sourceKeyLabel = NSTextField(labelWithString: "来源")
    private let sourceValueLabel = NSTextField(labelWithString: "-")
    private let sourceIconView = NSImageView()

    private let typeKeyLabel = NSTextField(labelWithString: "类型")
    private let typeValueLabel = NSTextField(labelWithString: "-")
    private let sizeKeyLabel = NSTextField(labelWithString: "尺寸")
    private let sizeValueLabel = NSTextField(labelWithString: "-")
    private let quitButton = GlassIconButton(systemSymbolName: "power",
                                             accessibilityLabel: "退出",
                                             target: nil,
                                             action: #selector(quitApplication))

    // MARK: - Initialization
    init(clips: [CPYClip]) {
        self.clips = clips
        self.filteredResults = clips.map(ResultItem.clip)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle
    override func loadView() {
        // 必须给出初始尺寸：整个层级是全 edge 约束，没有任何内在尺寸来源，
        // 从 .zero 起步会让自动布局把窗口收缩成 0x0（面板随之不可见）。
        // 真实的窗口尺寸随后由 `show(at:)` 按用户保存的值设置。
        let rootView = NSView(frame: NSRect(origin: .zero, size: Self.defaultWindowSize))
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.clear.cgColor
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do NOT set preferredContentSize: AppKit turns it into priority-501
        // width/height constraints on the content view, which pin the window
        // size and make every setFrame/setContentSize a no-op.
        setupUI()
        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeDidChange), name: .themeDidChange, object: nil)
        reloadResults(keepSelection: false)
        updateListActionButton()
    }

    // MARK: - Setup
    private func setupUI() {
        setupChromeView()
        setupDragBar()
        setupSearchContainer()
        setupContentContainers()
        setupListView()
        setupPreviewView()
        setupMetaView()
        // Must run before setupConstraints: it adds splitDivider to the
        // hierarchy, and the constraints reference it.
        setupSplitDivider()
        setupConstraints()
    }

    private func setupChromeView() {
        // The window itself is transparent; the outer regular glass is the
        // only backdrop, so it is the single source of the panel's silhouette.
        chromeView.translatesAutoresizingMaskIntoConstraints = false
        chromeCard.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(chromeCard)
    }

    private func setupDragBar() {
        dragBar.translatesAutoresizingMaskIntoConstraints = false
        chromeView.addSubview(dragBar)
    }

    private func setupSearchContainer() {
        searchContainer.translatesAutoresizingMaskIntoConstraints = false
        searchCard.translatesAutoresizingMaskIntoConstraints = false
        chromeView.addSubview(searchCard)

        searchField.placeholderString = "搜索..."
        searchField.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        searchField.sendsSearchStringImmediately = true
        searchField.focusRingType = .none
        searchField.isBordered = false
        searchField.bezelStyle = .roundedBezel
        searchField.borderShape = .capsule
        searchField.drawsBackground = false
        searchField.cell?.usesSingleLineMode = true
        if let cell = searchField.cell as? NSSearchFieldCell {
            cell.searchButtonCell = nil
            cell.cancelButtonCell = nil
        }
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.delegate = self
        searchContainer.addSubview(searchField)

        tabContainer.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.addSubview(tabContainer)

        tabSegmentedControl.segmentCount = 3
        FilterTab.allCases.enumerated().forEach { index, tab in
            tabSegmentedControl.setLabel(tab.title, forSegment: index)
        }
        tabSegmentedControl.selectedSegment = FilterTab.all.rawValue
        tabSegmentedControl.segmentStyle = .capsule
        tabSegmentedControl.target = self
        tabSegmentedControl.action = #selector(tabChanged(_:))
        tabSegmentedControl.translatesAutoresizingMaskIntoConstraints = false
        tabContainer.addSubview(tabSegmentedControl)

        settingsButton.target = self
        settingsButton.action = #selector(openSettings)
        searchContainer.addSubview(settingsButton)

        resetLayoutButton.target = self
        resetLayoutButton.action = #selector(resetLayoutToDefault)
        searchContainer.addSubview(resetLayoutButton)
    }

    private func setupContentContainers() {
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        chromeView.addSubview(contentContainer)

        [listContainer, previewContainer, metaContainer].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentContainer.addSubview($0)
        }
    }

    private func setupListView() {
        listTitleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        listTitleLabel.textColor = .secondaryLabelColor
        listTitleLabel.stringValue = FilterTab.history.title
        listTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        listContainer.addSubview(listTitleLabel)

        listActionButton.bezelStyle = .accessoryBar
        listActionButton.isBordered = false
        listActionButton.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        listActionButton.target = self
        listActionButton.action = #selector(listActionClicked)
        listActionButton.translatesAutoresizingMaskIntoConstraints = false
        listContainer.addSubview(listActionButton)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ClipColumn"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 36
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.focusRingType = .none
        tableView.allowsEmptySelection = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(tableViewDoubleClicked)

        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.verticalScroller = ThinScroller()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        listContainer.addSubview(scrollView)

        emptyStateLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        emptyStateLabel.textColor = .secondaryLabelColor
        emptyStateLabel.alignment = .center
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        listContainer.addSubview(emptyStateLabel)
    }

    private func setupPreviewView() {
        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(previewImageView)

        // Header view with title and delete button
        let headerView = NSView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(headerView)

        previewTitleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        previewTitleLabel.textColor = .secondaryLabelColor
        previewTitleLabel.stringValue = "预览"
        previewTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(previewTitleLabel)

        deleteButton.isHidden = true
        headerView.addSubview(deleteButton)

        favoriteButton.isHidden = true
        headerView.addSubview(favoriteButton)

        previewTextView.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        previewTextView.textColor = .labelColor
        previewTextView.isEditable = false
        previewTextView.isSelectable = false
        previewTextView.isRichText = false
        previewTextView.isVerticallyResizable = true
        previewTextView.isHorizontallyResizable = false
        previewTextView.minSize = NSSize(width: 0, height: 0)
        previewTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        previewTextView.autoresizingMask = [.width]
        previewTextView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        previewTextView.textContainer?.lineBreakMode = .byCharWrapping
        previewTextView.textContainer?.widthTracksTextView = true
        previewTextView.textContainerInset = NSSize(width: 0, height: 2)
        previewTextView.drawsBackground = false

        previewTextScrollView.drawsBackground = false
        previewTextScrollView.borderType = .noBorder
        previewTextScrollView.verticalScroller = ThinScroller()
        previewTextScrollView.hasVerticalScroller = true
        previewTextScrollView.hasHorizontalScroller = false
        previewTextScrollView.autohidesScrollers = true
        previewTextScrollView.scrollerStyle = .overlay
        previewTextScrollView.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(previewTextScrollView)
        previewTextScrollView.documentView = previewTextView

        previewSubtitleLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        previewSubtitleLabel.textColor = .secondaryLabelColor
        previewSubtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(previewSubtitleLabel)
    }

    private func setupMetaView() {
        let labels = [sourceKeyLabel, sourceValueLabel, typeKeyLabel, typeValueLabel, sizeKeyLabel, sizeValueLabel]
        labels.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            metaContainer.addSubview($0)
        }

        sourceIconView.imageScaling = .scaleProportionallyDown
        sourceIconView.translatesAutoresizingMaskIntoConstraints = false
        metaContainer.addSubview(sourceIconView)

        [sourceKeyLabel, typeKeyLabel, sizeKeyLabel].forEach {
            $0.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            $0.textColor = .secondaryLabelColor
        }

        sourceValueLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        sourceValueLabel.textColor = .labelColor
        sourceValueLabel.lineBreakMode = .byTruncatingTail
        sourceValueLabel.maximumNumberOfLines = 1
        sourceValueLabel.cell?.usesSingleLineMode = true
        sourceValueLabel.cell?.wraps = false
        sourceValueLabel.cell?.lineBreakMode = .byTruncatingTail

        [typeValueLabel, sizeValueLabel].forEach {
            $0.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            $0.textColor = .labelColor
        }

        metaContainer.addSubview(quitButton)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate(
            chromeConstraints()
                + searchBarConstraints()
                + contentPanelConstraints()
                + listPanelConstraints()
                + previewPanelConstraints()
                + metaPanelConstraints()
        )
    }

    private func chromeConstraints() -> [NSLayoutConstraint] {
        // NSWindow constrains its content view, and the content view here is
        // constrained back to the window, so neither side has an intrinsic size
        // and AppKit settles on 0x0. Giving the glass card a concrete intrinsic
        // size breaks that cycle and makes the window adopt it. Centre anchors
        // (not edges) keep the size unambiguous while the user drags an edge.
        // These must stay the only *required* size anchors, and must track the window
        // exactly. Every path that changes the window size has to go through
        // `syncChromeSize(to:)` — programmatic `setFrame` does not emit the drag
        // callback, so updating them anywhere else lets the card keep a stale size.
        let width = chromeCard.widthAnchor.constraint(equalToConstant: Self.defaultWindowSize.width)
        let height = chromeCard.heightAnchor.constraint(equalToConstant: Self.defaultWindowSize.height)
        // Dropping these below required lets the window win if it ever disagrees,
        // so a missed sync degrades to a slightly off-sized card rather than a
        // 0x0 collapse.
        width.priority = .defaultHigh
        height.priority = .defaultHigh
        chromeWidthConstraint = width
        chromeHeightConstraint = height
        return [
            chromeCard.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            chromeCard.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            width,
            height,

            // Drag bar at the top of chrome view
            dragBar.topAnchor.constraint(equalTo: chromeView.topAnchor),
            dragBar.leadingAnchor.constraint(equalTo: chromeView.leadingAnchor),
            dragBar.trailingAnchor.constraint(equalTo: chromeView.trailingAnchor),
            dragBar.heightAnchor.constraint(equalToConstant: 18)
        ]
    }

    private func searchBarConstraints() -> [NSLayoutConstraint] {
        [
            searchCard.topAnchor.constraint(equalTo: dragBar.bottomAnchor),
            searchCard.leadingAnchor.constraint(equalTo: chromeView.leadingAnchor, constant: GlassMetrics.panelInset),
            searchCard.trailingAnchor.constraint(equalTo: chromeView.trailingAnchor, constant: -GlassMetrics.panelInset),
            searchCard.heightAnchor.constraint(equalToConstant: 34),

            searchField.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: tabContainer.leadingAnchor, constant: -10),
            searchField.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),

            tabContainer.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -6),
            tabContainer.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            tabContainer.widthAnchor.constraint(equalToConstant: 250),
            tabContainer.heightAnchor.constraint(equalToConstant: 28),

            tabSegmentedControl.leadingAnchor.constraint(equalTo: tabContainer.leadingAnchor, constant: 6),
            tabSegmentedControl.trailingAnchor.constraint(equalTo: tabContainer.trailingAnchor, constant: -6),
            tabSegmentedControl.centerYAnchor.constraint(equalTo: tabContainer.centerYAnchor),

            settingsButton.trailingAnchor.constraint(equalTo: resetLayoutButton.leadingAnchor, constant: -6),
            settingsButton.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            settingsButton.widthAnchor.constraint(equalToConstant: GlassMetrics.iconButtonSide),
            settingsButton.heightAnchor.constraint(equalToConstant: GlassMetrics.iconButtonSide),

            resetLayoutButton.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -10),
            resetLayoutButton.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            resetLayoutButton.widthAnchor.constraint(equalToConstant: GlassMetrics.iconButtonSide),
            resetLayoutButton.heightAnchor.constraint(equalToConstant: GlassMetrics.iconButtonSide)
        ]
    }

    private func contentPanelConstraints() -> [NSLayoutConstraint] {
        [
            contentContainer.topAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: 10),
            contentContainer.leadingAnchor.constraint(equalTo: chromeView.leadingAnchor, constant: GlassMetrics.panelInset),
            contentContainer.trailingAnchor.constraint(equalTo: chromeView.trailingAnchor, constant: -GlassMetrics.panelInset),
            contentContainer.bottomAnchor.constraint(equalTo: chromeView.bottomAnchor, constant: -GlassMetrics.panelInset),

            listContainer.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            listContainer.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            // No extra bottom inset here: the container already reserves the
            // panel inset, and stacking the two left a visibly wide empty band
            // once the cards stopped framing the content.
            listContainer.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            {
                let saved = AppEnvironment.current.defaults.double(forKey: Constants.UserDefaults.searchListWidth)
                let initial = (saved >= 160 && saved <= 480) ? CGFloat(saved) : Self.defaultListWidth
                splitDividerLocation = initial
                let listWidth = listContainer.widthAnchor.constraint(equalToConstant: initial)
                self.listWidthConstraint = listWidth
                return listWidth
            }(),

            // Divider sits between the panels and provides their separation.
            splitDivider.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            splitDivider.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            splitDivider.widthAnchor.constraint(equalToConstant: splitDivider.hitWidth),
            splitDivider.leadingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            splitDivider.trailingAnchor.constraint(equalTo: previewContainer.leadingAnchor),

            previewContainer.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            previewContainer.leadingAnchor.constraint(equalTo: splitDivider.trailingAnchor, constant: 4),
            previewContainer.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            // Height must follow the window instead of being a fixed 288,
            // so the preview fills whatever vertical space is left over.
            // A 1pt gap separates the metadata strip from the preview body. Spacing rather
            // than a drawn line: on glass a rule reads as a hard edge, while a
            // gap groups just as clearly and stays out of the way.
            previewContainer.bottomAnchor.constraint(equalTo: metaContainer.topAnchor, constant: -1),

            metaContainer.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            metaContainer.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            metaContainer.heightAnchor.constraint(equalToConstant: 44),
            metaContainer.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ]
    }

    private func listPanelConstraints() -> [NSLayoutConstraint] {
        [
            listTitleLabel.topAnchor.constraint(equalTo: listContainer.topAnchor, constant: 4),
            listTitleLabel.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor, constant: 8),
            listTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: listActionButton.leadingAnchor, constant: -8),

            listActionButton.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor, constant: -8),
            listActionButton.centerYAnchor.constraint(equalTo: listTitleLabel.centerYAnchor),

            scrollView.topAnchor.constraint(equalTo: listTitleLabel.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor, constant: 2),
            scrollView.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor, constant: -2),
            scrollView.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor, constant: -2),

            emptyStateLabel.centerXAnchor.constraint(equalTo: listContainer.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: listContainer.centerYAnchor)
        ]
    }

    private func previewPanelConstraints() -> [NSLayoutConstraint] {
        [
            // Header view (title + delete button)
            {
                let headerView = previewTitleLabel.superview!
                return headerView.topAnchor.constraint(equalTo: previewContainer.topAnchor, constant: 4)
            }(),
            {
                let headerView = previewTitleLabel.superview!
                return headerView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor, constant: 6)
            }(),
            {
                let headerView = previewTitleLabel.superview!
                return headerView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor, constant: -6)
            }(),
            {
                let headerView = previewTitleLabel.superview!
                return headerView.heightAnchor.constraint(equalToConstant: 20)
            }(),

            previewTitleLabel.leadingAnchor.constraint(equalTo: previewTitleLabel.superview!.leadingAnchor),
            previewTitleLabel.centerYAnchor.constraint(equalTo: previewTitleLabel.superview!.centerYAnchor),

            deleteButton.trailingAnchor.constraint(equalTo: deleteButton.superview!.trailingAnchor),
            deleteButton.centerYAnchor.constraint(equalTo: deleteButton.superview!.centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 20),
            deleteButton.heightAnchor.constraint(equalToConstant: 20),

            favoriteButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -8),
            favoriteButton.centerYAnchor.constraint(equalTo: favoriteButton.superview!.centerYAnchor),
            favoriteButton.widthAnchor.constraint(equalToConstant: 20),
            favoriteButton.heightAnchor.constraint(equalToConstant: 20),

            previewImageView.topAnchor.constraint(equalTo: previewTitleLabel.superview!.bottomAnchor, constant: 6),
            previewImageView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor, constant: 6),
            previewImageView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor, constant: -6),
            {
                let fixedHeight = previewImageView.heightAnchor.constraint(equalToConstant: 140)
                fixedHeight.priority = .defaultHigh
                self.previewImageFixedHeightConstraint = fixedHeight
                return fixedHeight
            }(),
            {
                let pinnedBottom = previewImageView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: -6)
                pinnedBottom.priority = .defaultHigh
                pinnedBottom.isActive = true
                self.previewImageBottomConstraint = pinnedBottom
                return pinnedBottom
            }(),
            {
                let zeroHeight = previewImageView.heightAnchor.constraint(equalToConstant: 0)
                zeroHeight.priority = .defaultHigh
                self.previewImageZeroHeightConstraint = zeroHeight
                return zeroHeight
            }(),

            {
                let constraint = previewTextScrollView.topAnchor.constraint(equalTo: previewImageView.bottomAnchor, constant: 12)
                self.previewTextTopConstraint = constraint
                return constraint
            }(),
            previewTextScrollView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor, constant: 6),
            previewTextScrollView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor, constant: -6),
            {
                let constraint = previewTextScrollView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: -10)
                self.previewTextBottomConstraint = constraint
                return constraint
            }(),

            previewSubtitleLabel.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor, constant: 6),
            previewSubtitleLabel.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor, constant: -6),
            previewSubtitleLabel.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: -6)
        ]
    }

    private func metaPanelConstraints() -> [NSLayoutConstraint] {
        [
            // Meta view: source (key on top, icon+value below) → type → size → quit
            sourceIconView.leadingAnchor.constraint(equalTo: metaContainer.leadingAnchor, constant: 6),
            sourceIconView.topAnchor.constraint(equalTo: sourceValueLabel.topAnchor),
            sourceIconView.widthAnchor.constraint(equalToConstant: 14),
            sourceIconView.heightAnchor.constraint(equalToConstant: 14),

            sourceKeyLabel.topAnchor.constraint(equalTo: metaContainer.topAnchor, constant: 4),
            sourceKeyLabel.leadingAnchor.constraint(equalTo: metaContainer.leadingAnchor, constant: 6),
            sourceValueLabel.topAnchor.constraint(equalTo: sourceKeyLabel.bottomAnchor, constant: 2),
            sourceValueLabel.leadingAnchor.constraint(equalTo: sourceIconView.trailingAnchor, constant: 5),

            typeKeyLabel.topAnchor.constraint(equalTo: metaContainer.topAnchor, constant: 4),
            typeKeyLabel.leadingAnchor.constraint(equalTo: metaContainer.leadingAnchor, constant: 150),
            typeValueLabel.topAnchor.constraint(equalTo: sourceValueLabel.topAnchor),
            typeValueLabel.leadingAnchor.constraint(equalTo: typeKeyLabel.leadingAnchor),

            sizeKeyLabel.topAnchor.constraint(equalTo: metaContainer.topAnchor, constant: 4),
            sizeKeyLabel.leadingAnchor.constraint(equalTo: metaContainer.leadingAnchor, constant: 240),
            sizeValueLabel.topAnchor.constraint(equalTo: sourceValueLabel.topAnchor),
            sizeValueLabel.leadingAnchor.constraint(equalTo: sizeKeyLabel.leadingAnchor),

            quitButton.centerYAnchor.constraint(equalTo: metaContainer.centerYAnchor),
            quitButton.trailingAnchor.constraint(equalTo: metaContainer.trailingAnchor, constant: -6),
            quitButton.widthAnchor.constraint(equalToConstant: 20),
            quitButton.heightAnchor.constraint(equalToConstant: 20)
        ]
    }

    // MARK: - Public Methods
    func show(at location: NSPoint) {
        previousActiveApp = NSWorkspace.shared.frontmostApplication
        // The view hierarchy must exist before it can become the window's
        // contentView; loading it here also lets `defaultWindowSize` drive the
        // very first layout pass.
        loadViewIfNeeded()

        // Restore persisted size, clamped to the window's min/max limits.
        let savedWidth = AppEnvironment.current.defaults.double(forKey: Constants.UserDefaults.searchWindowWidth)
        let savedHeight = AppEnvironment.current.defaults.double(forKey: Constants.UserDefaults.searchWindowHeight)
        let windowWidth = (savedWidth >= Self.minimumWindowSize.width && savedWidth <= Self.maximumWindowSize.width) ? CGFloat(savedWidth) : Self.defaultWindowSize.width
        let windowHeight = (savedHeight >= Self.minimumWindowSize.height && savedHeight <= Self.maximumWindowSize.height) ? CGFloat(savedHeight) : Self.defaultWindowSize.height
        let screen = NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? .zero

        var originX = location.x
        var originY = location.y - windowHeight

        if originX + windowWidth > visibleFrame.maxX {
            originX = visibleFrame.maxX - windowWidth
        }
        if originX < visibleFrame.minX {
            originX = visibleFrame.minX
        }
        if originY < visibleFrame.minY {
            originY = visibleFrame.minY
        }
        if originY + windowHeight > visibleFrame.maxY {
            originY = visibleFrame.maxY - windowHeight
        }

        searchWindow = SearchWindow(contentRect: NSRect(x: originX, y: originY, width: windowWidth, height: windowHeight),
                                    contentView: view)
        searchWindow?.minSize = Self.minimumWindowSize
        searchWindow?.maxSize = Self.maximumWindowSize
        searchWindow?.dragBar = dragBar
        searchWindow?.splitDivider = splitDivider
        // The glass card's intrinsic size is the source of truth for the window
        // size, so start it at the restored size rather than the default.
        syncChromeSize(to: NSSize(width: windowWidth, height: windowHeight))
        searchWindow?.onFrameChanging = { [weak self] size in
            self?.syncChromeSize(to: size)
        }
        searchWindow?.preferredFirstResponder = searchField
        searchWindow?.onFrameDidChange = { [weak self] in
            self?.persistWindowSize()
        }
        searchWindow?.onEscape = { [weak self] in
            self?.delegate?.searchPopoverDidCancel()
            self?.close()
        }
        searchWindow?.onTabNavigation = { [weak self] movesForward in
            self?.selectAdjacentTab(movingForward: movesForward)
        }
        searchWindow?.delegate = self
        NSApp.activate(ignoringOtherApps: true)
        searchWindow?.makeKeyAndOrderFront(nil)
        searchWindow?.setFrame(NSRect(x: originX, y: originY, width: windowWidth, height: windowHeight), display: true)
        // Mark synchronously right after the restored size is applied, so a
        // size change is never recorded before the restore has taken effect.
        searchWindow?.markLayoutReady()
        // Mark synchronously right after the restored size is applied, so a
        // size change is never recorded before the restore has taken effect.
        searchWindow?.markLayoutReady()

        setupClickOutsideMonitor()

        DispatchQueue.main.async { [weak self] in
            self?.searchField.window?.makeFirstResponder(self?.searchField)
        }
    }

    /// Saves the current window size.
    /// - Parameter force: when true, saves regardless of gesture state.
    ///   `windowDidResize` needs the guard because it also fires during window
    ///   setup (which would overwrite the restored size), but closing must
    ///   always save the final size.
    private func persistWindowSize(force: Bool = false) {
        guard let window = searchWindow else { return }
        // `force` is used when closing: the final size must always be stored,
        // even if the window was closed before layout finished.
        if !force && (!window.isLayoutReady || !window.isUserResizing) { return }
        let size = window.frame.size
        AppEnvironment.current.defaults.set(Double(size.width), forKey: Constants.UserDefaults.searchWindowWidth)
        AppEnvironment.current.defaults.set(Double(size.height), forKey: Constants.UserDefaults.searchWindowHeight)
    }

    func close() {
        persistWindowSize(force: true)
        removeClickMonitor()
        searchWindow?.close()
        searchWindow = nil
    }

    private func setupClickOutsideMonitor() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let window = self.searchWindow else { return }
            let location = NSEvent.mouseLocation
            if !window.frame.contains(location) {
                self.delegate?.searchPopoverDidCancel()
                self.close()
            }
        }
    }

    private func removeClickMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    // MARK: - Private Helpers
    /// Keeps the glass card's intrinsic size in step with the window's.
    ///
    /// AppKit sizes this panel from that content, so if the two disagree the card
    /// keeps its old size while the window shrinks to fit it and the contents get
    /// clipped. Every window-size change must funnel through here: the drag
    /// gesture reports via `onFrameChanging`, and programmatic changes (reset
    /// layout, restoring a saved size) call this directly.
    private func syncChromeSize(to size: NSSize) {
        let clamped = NSSize(width: min(max(size.width, Self.minimumWindowSize.width), Self.maximumWindowSize.width),
                             height: min(max(size.height, Self.minimumWindowSize.height), Self.maximumWindowSize.height))
        guard chromeWidthConstraint?.constant != clamped.width || chromeHeightConstraint?.constant != clamped.height else { return }
        chromeWidthConstraint?.constant = clamped.width
        chromeHeightConstraint?.constant = clamped.height
    }

    @objc private func handleThemeDidChange() {
        tableView.reloadData()
    }

    private func reloadResults(keepSelection: Bool) {
        let selectedIdentifier = keepSelection ? selectedResultIdentifier() : nil
        tableView.reloadData()
        emptyStateLabel.isHidden = !filteredResults.isEmpty
        listTitleLabel.stringValue = activeTab == .all ? "全部结果" : activeTab.title

        if filteredResults.isEmpty {
            renderPreview(for: nil)
            return
        }

        if let selectedIdentifier,
           let index = filteredResults.firstIndex(where: { resultIdentifier(for: $0) == selectedIdentifier }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }

        updatePreviewFromSelection()
    }

    private func selectedResult() -> ResultItem? {
        let row = tableView.selectedRow
        guard row >= 0, row < filteredResults.count else { return nil }
        return filteredResults[row]
    }

    private func filter(with searchText: String) {
        filteredResults = results(for: activeTab, searchText: searchText)
        reloadResults(keepSelection: true)
    }

    private func results(for tab: FilterTab, searchText: String) -> [ResultItem] {
        let normalized = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        func matches(_ value: String) -> Bool {
            normalized.isEmpty || value.localizedCaseInsensitiveContains(normalized)
        }

        let historyResults = clips
            .filter { matches($0.title) }
            .map(ResultItem.clip)

        switch tab {
        case .all:
            return historyResults
        case .history:
            return historyResults
        case .favorites:
            return historyResults.filter {
                if case let .clip(clip) = $0 { return clip.isFavorite }
                return false
            }
        }
    }

    private func selectedResultIdentifier() -> String? {
        selectedResult().map(resultIdentifier(for:))
    }

    private func resultIdentifier(for result: ResultItem) -> String {
        switch result {
        case let .clip(clip): return "clip:\(clip.dataHash)"
        }
    }

    private func loadClipData(for clip: CPYClip) -> CPYClipData? {
        guard !clip.dataPath.isEmpty else { return nil }
        return NSKeyedUnarchiver.unarchiveObject(withFile: clip.dataPath) as? CPYClipData
    }

    private func updatePreviewFromSelection() {
        guard let result = selectedResult() else {
            renderPreview(for: nil)
            return
        }
        renderPreview(for: result)
    }

    private func renderPreview(for result: ResultItem?) {
        guard let result else {
            previewImageView.isHidden = true
            previewTextScrollView.isHidden = false
            previewImageFixedHeightConstraint?.isActive = false
            previewImageBottomConstraint?.isActive = false
            previewImageZeroHeightConstraint?.isActive = true
            previewTextView.string = "选择一项查看预览"
            previewTextTopConstraint?.constant = 0
            previewSubtitleLabel.stringValue = ""
            typeValueLabel.stringValue = "-"
            sizeValueLabel.stringValue = "-"
            sourceIconView.image = nil
            sourceValueLabel.stringValue = "-"
            deleteButton.isHidden = true
            favoriteButton.isHidden = true
            return
        }

        deleteButton.isHidden = false
        favoriteButton.isHidden = false

        switch result {
        case let .clip(clip):
            updateFavoriteButton(isFavorite: clip.isFavorite)
            renderClipPreview(for: clip, data: loadClipData(for: clip))
        }
    }

    private func updateFavoriteButton(isFavorite: Bool) {
        favoriteButton.setSymbol(isFavorite ? "star.fill" : "star")
        favoriteButton.contentTintColor = isFavorite ? .systemYellow : .secondaryLabelColor
    }

    @objc private func toggleFavorite() {
        guard case let .clip(clip)? = selectedResult() else { return }
        let dataHash = clip.dataHash
        let realm = try! Realm()
        guard let savedClip = realm.object(ofType: CPYClip.self, forPrimaryKey: dataHash) else { return }
        let newValue = !savedClip.isFavorite
        realm.transaction { savedClip.isFavorite = newValue }
        // The in-memory clips are live objects owned by another Realm instance,
        // so they cannot be written here. Advance them instead.
        if let index = clips.firstIndex(where: { $0.dataHash == dataHash }) {
            clips[index].realm?.refresh()
        }
        updateFavoriteButton(isFavorite: newValue)
        if activeTab == .favorites {
            filter(with: searchField.stringValue)
        }
    }

    private func renderClipPreview(for clip: CPYClip, data: CPYClipData?) {
        guard let data else {
            renderPreview(for: nil)
            return
        }

        let previewImage = previewImage(for: clip, data: data)
        previewImageView.image = previewImage
        previewImageView.isHidden = previewImage == nil

        let previewText = previewText(for: data, image: previewImage)
        let hasImage = previewImage != nil
        let hasText = !previewText.isEmpty
        let imageOnly = hasImage && !hasText

        // Image layout: imageOnly → fill; hasImage+text → fixed 140px; no image → zero height
        previewImageFixedHeightConstraint?.isActive = hasImage && !imageOnly
        previewImageBottomConstraint?.isActive = imageOnly
        previewImageZeroHeightConstraint?.isActive = !hasImage
        previewImageView.imageScaling = imageOnly ? .scaleProportionallyUpOrDown : .scaleProportionallyDown

        previewTextView.string = previewText
        previewTextScrollView.isHidden = imageOnly
        previewTextScrollView.hasVerticalScroller = true
        previewTextScrollView.contentView.scroll(to: .zero)
        previewTextScrollView.reflectScrolledClipView(previewTextScrollView.contentView)
        previewTextTopConstraint?.constant = hasImage ? 12 : 0
        previewTextBottomConstraint?.constant = -6

        previewSubtitleLabel.stringValue = ""
        previewSubtitleLabel.isHidden = true
        typeValueLabel.stringValue = typeLabel(for: data)
        sizeValueLabel.stringValue = previewSizeText(for: data, image: previewImage)

        sourceIconView.image = appIcon(for: clip.sourceBundleIdentifier)
        sourceValueLabel.stringValue = clip.sourceAppName.isEmpty ? "本应用" : clip.sourceAppName
    }

    private func previewImage(for clip: CPYClip, data: CPYClipData) -> NSImage? {
        if let image = PINCache.shared.object(forKey: clip.thumbnailPath) as? NSImage {
            return image
        }

        if let thumbnail = data.thumbnailImage {
            if !clip.thumbnailPath.isEmpty {
                PINCache.shared.setObject(thumbnail, forKey: clip.thumbnailPath)
            }
            return thumbnail
        }

        return data.colorCodeImage
    }

    private func previewText(for data: CPYClipData, image: NSImage?) -> String {
        if image != nil, let fileName = data.fileNames.first {
            let pathExtension = URL(fileURLWithPath: fileName).pathExtension.lowercased()
            let imageFileExtensions = ["jpg", "jpeg", "png", "bmp", "tiff"]
            if imageFileExtensions.contains(pathExtension) {
                return ""
            }
        }

        if !data.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return data.stringValue
        }
        if let fileName = data.fileNames.first {
            return fileName
        }
        if let url = data.URLs.first {
            return url
        }
        if data.PDF != nil {
            return "PDF 内容"
        }
        if data.image != nil || data.thumbnailImage != nil || data.colorCodeImage != nil {
            return ""
        }
        return "无可预览内容"
    }

    private func typeLabel(for data: CPYClipData) -> String {
        let hasText = !data.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if (data.image != nil || data.thumbnailImage != nil) && hasText {
            return "混合内容"
        }
        if data.image != nil || data.thumbnailImage != nil {
            return "图片"
        }
        if !data.fileNames.isEmpty {
            return "文件"
        }
        if !data.URLs.isEmpty {
            return "链接"
        }
        if data.PDF != nil {
            return "PDF"
        }
        return "文本"
    }

    private func previewSizeText(for data: CPYClipData, image: NSImage?) -> String {
        if let image {
            let size = image.size
            return "\(Int(size.width)) x \(Int(size.height))"
        }
        if let fileName = data.fileNames.first,
           let attributes = try? FileManager.default.attributesOfItem(atPath: fileName),
           let fileSize = attributes[.size] as? NSNumber {
            return ByteCountFormatter.string(fromByteCount: fileSize.int64Value, countStyle: .file)
        }
        return "-"
    }

    @objc private func tableViewDoubleClicked() {
        guard let result = selectedResult() else { return }
        delegate?.searchPopoverDidSelectResult(result)
        close()
    }

    @objc private func tabChanged(_ sender: NSSegmentedControl) {
        guard let tab = FilterTab(rawValue: sender.selectedSegment) else { return }
        activeTab = tab
        filter(with: searchField.stringValue)
        updateListActionButton()
    }

    private func selectAdjacentTab(movingForward: Bool) {
        let allTabs = FilterTab.allCases
        guard let currentIndex = allTabs.firstIndex(of: activeTab) else { return }

        let nextIndex: Int
        if movingForward {
            nextIndex = (currentIndex + 1) % allTabs.count
        } else {
            nextIndex = (currentIndex - 1 + allTabs.count) % allTabs.count
        }

        tabSegmentedControl.selectedSegment = allTabs[nextIndex].rawValue
        tabChanged(tabSegmentedControl)
    }

    @objc private func openSettings() {
        delegate?.searchPopoverDidCancel()
        close()
        NSApp.activate(ignoringOtherApps: true)
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.showPreferenceWindow()
        }
    }

    /// Restores the window size and split position to their defaults.
    /// Takes effect immediately and clears the stored values so the next
    /// launch also starts from the defaults.
    @objc private func resetLayoutToDefault() {
        let defaults = AppEnvironment.current.defaults
        defaults.removeObject(forKey: Constants.UserDefaults.searchWindowWidth)
        defaults.removeObject(forKey: Constants.UserDefaults.searchWindowHeight)
        defaults.removeObject(forKey: Constants.UserDefaults.searchListWidth)

        // Split position
        splitDividerLocation = Self.defaultListWidth
        listWidthConstraint?.constant = Self.defaultListWidth

        // Window size, keeping the top-left corner anchored so it grows downward.
        if let window = searchWindow {
            let old = window.frame
            let newOrigin = NSPoint(x: old.minX, y: old.maxY - Self.defaultWindowSize.height)
            // `setFrame` bypasses the drag gesture, so the content's intrinsic
            // size has to be updated explicitly or the card stays at the old
            // size and its contents get clipped.
            syncChromeSize(to: Self.defaultWindowSize)
            window.setFrame(
                NSRect(origin: newOrigin, size: Self.defaultWindowSize),
                display: true,
                animate: false
            )
        }

        contentContainer.layoutSubtreeIfNeeded()
    }

    @objc private func quitApplication() {
        delegate?.searchPopoverDidCancel()
        close()
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.terminate()
        } else {
            NSApp.terminate(nil)
        }
    }

    private func setupSplitDivider() {
        splitDivider.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(splitDivider)

        splitDivider.onDragChanged = { [weak self] proposed in
            self?.updateSplitLocation(proposed)
        }
    }

    private func updateSplitLocation(_ proposed: CGFloat) {
        let containerWidth = contentContainer.bounds.width
        let dividerWidth = splitDivider.hitWidth
        // `proposed` is the divider's leading edge; the list ends there,
        // so the list itself must exclude the divider's own width.
        let listWidth = proposed - dividerWidth
        // Guard against a stale/zero container width during layout: without a
        // floor the clamp below can produce a bogus width that resizes the window.
        let referenceWidth = containerWidth > 0 ? containerWidth : (searchWindow?.frame.width ?? Self.defaultWindowSize.width)
        let maxListWidth = referenceWidth * 0.5 - dividerWidth
        let clamped = max(160, min(listWidth, max(160, maxListWidth)))

        splitDividerLocation = clamped
        listWidthConstraint?.constant = clamped
        contentContainer.layoutSubtreeIfNeeded()
        AppEnvironment.current.defaults.set(Double(clamped), forKey: Constants.UserDefaults.searchListWidth)
    }

    @objc private func deleteCurrentItem() {
        guard let result = selectedResult() else { return }

        switch result {
        case let .clip(clip):
            let index = filteredResults.firstIndex(where: {
                if case .clip(let candidate) = $0 { return candidate.dataHash == clip.dataHash }
                return false
            })
            if let index {
                filteredResults.remove(at: index)
            }
            clips.removeAll { $0.dataHash == clip.dataHash }
            AppEnvironment.current.clipService.delete(with: clip)
            tableView.reloadData()

            if filteredResults.isEmpty {
                renderPreview(for: nil)
            } else if let index {
                let selectIndex = min(index, filteredResults.count - 1)
                tableView.selectRowIndexes(IndexSet(integer: selectIndex), byExtendingSelection: false)
            }
        }
    }

    private func appIcon(for bundleIdentifier: String) -> NSImage {
        if !bundleIdentifier.isEmpty,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }
        return NSImage(named: NSImage.Name("AppIcon")) ?? NSApp.applicationIconImage
    }

    private func updateListActionButton() {
        switch activeTab {
        case .history:
            listActionButton.title = "清空"
            listActionButton.isHidden = false
        case .favorites:
            listActionButton.isHidden = true
        case .all:
            listActionButton.isHidden = true
        }
    }

    @objc private func listActionClicked() {
        switch activeTab {
        case .history:
            delegate?.searchPopoverDidCancel()
            close()
            NSApp.activate(ignoringOtherApps: true)
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.clearAllHistory()
            }
        case .favorites:
            break
        case .all:
            break
        }
    }
}
// swiftlint:enable type_body_length

// MARK: - NSSearchFieldDelegate
extension SearchPopoverController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        filter(with: searchField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(cancelOperation(_:)) {
            delegate?.searchPopoverDidCancel()
            close()
            return true
        }

        if commandSelector == #selector(insertNewline(_:)) {
            guard let result = selectedResult() else { return true }
            delegate?.searchPopoverDidSelectResult(result)
            close()
            return true
        }

        if commandSelector == #selector(insertTab(_:)) {
            selectAdjacentTab(movingForward: true)
            return true
        }

        if commandSelector == #selector(insertBacktab(_:)) {
            selectAdjacentTab(movingForward: false)
            return true
        }

        if commandSelector == #selector(moveDown(_:)) {
            let nextRow = min(tableView.selectedRow + 1, filteredResults.count - 1)
            if nextRow >= 0, !filteredResults.isEmpty {
                tableView.selectRowIndexes(IndexSet(integer: nextRow), byExtendingSelection: false)
                tableView.scrollRowToVisible(nextRow)
                updatePreviewFromSelection()
            }
            return true
        }

        if commandSelector == #selector(moveUp(_:)) {
            let previousRow = max(tableView.selectedRow - 1, 0)
            if previousRow >= 0, !filteredResults.isEmpty {
                tableView.selectRowIndexes(IndexSet(integer: previousRow), byExtendingSelection: false)
                tableView.scrollRowToVisible(previousRow)
                updatePreviewFromSelection()
            }
            return true
        }

        return false
    }
}

// MARK: - NSTableViewDataSource
extension SearchPopoverController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredResults.count
    }
}

// MARK: - NSTableViewDelegate
extension SearchPopoverController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < filteredResults.count else { return nil }

        let result = filteredResults[row]
        let cellIdentifier = NSUserInterfaceItemIdentifier("ClipCell")

        let cell: SearchResultCellView
        if let reusedCell = tableView.makeView(withIdentifier: cellIdentifier, owner: nil) as? SearchResultCellView {
            cell = reusedCell
        } else {
            cell = SearchResultCellView()
            cell.identifier = cellIdentifier
        }

        let title: String
        let image: NSImage?
        switch result {
        case let .clip(clip):
            let data = loadClipData(for: clip)
            let rawTitle = data?.titleText ?? clip.title
            title = rawTitle.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            image = previewImage(for: clip, data: data ?? CPYClipData(image: NSImage(size: .zero)))
        }
        cell.configure(title: title, image: image)

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updatePreviewFromSelection()
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        SearchResultRowView()
    }
}

// MARK: - NSWindowDelegate
extension SearchPopoverController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        persistWindowSize(force: true)
        removeClickMonitor()
        searchWindow = nil
    }

    /// Fires for every resize, so the size is stored even if the final
    /// mouse-up happens outside the window.
    func windowDidResize(_ notification: Notification) {
        // Safety net for the content's intrinsic size. The drag gesture already
        // reports via `onFrameChanging`, but programmatic resizes (reset layout,
        // restoring a saved size) do not, and a stale intrinsic size makes the
        // contents get clipped.
        if let size = notification.object as? NSWindow {
            syncChromeSize(to: size.frame.size)
        }
        persistWindowSize()
    }
}

// MARK: - DragBarView
private final class DragBarView: NSView {
    override var acceptsFirstResponder: Bool { false }
}

// MARK: - SplitDividerView
/// A thin vertical bar between the list and preview panels.
/// It visually separates the panels, owns the resize cursor, and handles dragging.
private final class SplitDividerView: NSView {
    var onDragChanged: ((CGFloat) -> Void)?

    private var isDragging = false
    private var initialMouseX: CGFloat = 0
    private var initialLeading: CGFloat = 0
    private var initialWindowSize: NSSize?

    override var acceptsFirstResponder: Bool { false }
    override var isFlipped: Bool { true }

    /// Fully transparent: it only provides the drag target and its resize cursor.
    /// The panes are told apart by spacing alone — a drawn separator reads as a
    /// hard line across the glass and fights the material.
    var hitWidth: CGFloat { 8 }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        guard let superview else { return }
        isDragging = true
        initialMouseX = NSEvent.mouseLocation.x
        // Track the divider's own leading edge (= list trailing edge).
        initialLeading = frame.minX - superview.bounds.minX
        // Pin the window size for the whole drag so autolayout cannot resize
        // it while the split constraint changes.
        initialWindowSize = window?.frame.size
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let deltaX = NSEvent.mouseLocation.x - initialMouseX
        let proposed = initialLeading + deltaX
        onDragChanged?(proposed)
        // Restore any size autolayout may have applied during the constraint
        // change, so the window never jumps while dragging the divider.
        if let pinned = initialWindowSize, let window, window.frame.size != pinned {
            window.setFrame(NSRect(origin: window.frame.origin, size: pinned), display: false)
        }
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        initialWindowSize = nil
    }
}

// MARK: - SearchWindow
private final class SearchWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    weak var preferredFirstResponder: NSResponder?
    var onEscape: (() -> Void)?
    var onTabNavigation: ((Bool) -> Void)?
    var onFrameDidChange: (() -> Void)?
    /// Fired while the user drags a resize edge, before the frame is applied.
    /// The panel mirrors the size into its content's intrinsic size so AppKit
    /// does not snap the window straight back.
    var onFrameChanging: ((NSSize) -> Void)?
    weak var dragBar: DragBarView?
    weak var splitDivider: SplitDividerView?

    /// True once the restored size has been applied. Before that, autolayout
    /// resizes the window to the content view's default (640x420), and saving
    /// during that window would overwrite the user's stored size.
    private(set) var isLayoutReady = false

    /// True only while the user is actively dragging an edge/corner.
    private(set) var isUserResizing = false

    /// Marks layout as settled so size changes may be persisted.
    func markLayoutReady() {
        isLayoutReady = true
    }

    private let resizeEdgeSize: CGFloat = 6
    private var resizeH: NSRectEdge?
    private var resizeV: NSRectEdge?
    private var isMovingWindow = false
    private var gestureInitialFrame: NSRect = .zero
    private var gestureInitialLoc: NSPoint = .zero
    private var gestureActive = false

    /// A `.titled` window with a hidden title bar rather than a `.borderless`
    /// one. Borderless windows are sized by AppKit from their content's fitting
    /// size, and this panel's hierarchy is all edge constraints, so the window
    /// would collapse to 0x0. A titled window keeps ordinary frame semantics
    /// while `fullSizeContentView` still lets the glass fill the whole window.
    init(contentRect: NSRect, contentView: NSView) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.contentView = contentView
        self.isReleasedWhenClosed = false
        self.level = .floating
        self.isMovable = false
        self.isMovableByWindowBackground = false
        self.hasShadow = true
        self.isOpaque = false
        self.backgroundColor = .clear
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.collectionBehavior = [.transient, .ignoresCycle]

        // The window frame itself is fully transparent; only the outer glass
        // card draws the panel. Clipping still matches so the glass corner
        // radius and the window silhouette never disagree.
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = GlassMetrics.windowCornerRadius
        contentView.layer?.masksToBounds = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor

        contentView.superview?.wantsLayer = true
        contentView.superview?.layer?.cornerRadius = GlassMetrics.windowCornerRadius
        contentView.superview?.layer?.masksToBounds = true
        contentView.superview?.layer?.backgroundColor = NSColor.clear.cgColor

        // Window move/resize are handled explicitly in sendEvent below,
        // so AppKit must not start its own window drag.
        let cursorTracking = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        contentView.addTrackingArea(cursorTracking)
    }

    override func mouseMoved(with event: NSEvent) {
        let loc = event.locationInWindow
        // The split divider owns its own cursor via resetCursorRects;
        // overriding it here would make the resize cursor flicker away.
        if isInSplitDivider(loc) { return }

        let width = frame.size.width
        let height = frame.size.height
        let edge = resizeEdgeSize
        let nearLeft = loc.x <= edge
        let nearRight = loc.x >= width - edge
        let nearBottom = loc.y <= edge
        let nearTop = loc.y >= height - edge
        if (nearLeft || nearRight) && (nearTop || nearBottom) {
            NSCursor.crosshair.set()
        } else if nearLeft || nearRight {
            NSCursor.resizeLeftRight.set()
        } else if nearTop || nearBottom {
            NSCursor.resizeUpDown.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func isInSplitDivider(_ locationInWindow: NSPoint) -> Bool {
        guard let splitDivider else { return false }
        let local = splitDivider.convert(locationInWindow, from: nil)
        return splitDivider.isMousePoint(local, in: splitDivider.bounds)
    }

    private func isInDragBar(_ locationInWindow: NSPoint) -> Bool {
        guard let dragBar else { return false }
        let local = dragBar.convert(locationInWindow, from: nil)
        return dragBar.isMousePoint(local, in: dragBar.bounds)
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 48 {
            let movesForward = !event.modifierFlags.contains(.shift)
            onTabNavigation?(movesForward)
            return
        }

        switch event.type {
        case .leftMouseDown:
            let loc = event.locationInWindow
            let width = frame.size.width
            let height = frame.size.height
            let edge = resizeEdgeSize
            let nearLeft = loc.x <= edge
            let nearRight = loc.x >= width - edge
            let nearBottom = loc.y <= edge
            let nearTop = loc.y >= height - edge

            // The divider can sit within 6pt of the window edge, so it must be
            // checked first; otherwise grabbing it resizes the whole window.
            if isInSplitDivider(loc) {
                break
            }

            if nearLeft || nearRight || nearTop || nearBottom {
                resizeH = nearLeft ? .minX : (nearRight ? .maxX : nil)
                resizeV = nearBottom ? .minY : (nearTop ? .maxY : nil)
                isMovingWindow = false
                isUserResizing = true
                gestureInitialFrame = frame
                // Must be screen coordinates: locationInWindow stays pinned to
                // the same edge while resizing, so its delta would always be 0.
                gestureInitialLoc = NSEvent.mouseLocation
                gestureActive = true
            } else if isInDragBar(loc) {
                resizeH = nil
                resizeV = nil
                isMovingWindow = true
                gestureInitialFrame = frame
                gestureInitialLoc = NSEvent.mouseLocation
                gestureActive = true
            }

        case .leftMouseDragged:
            guard gestureActive else { break }
            let current = NSEvent.mouseLocation
            let deltaX = current.x - gestureInitialLoc.x
            let deltaY = current.y - gestureInitialLoc.y

            if isMovingWindow {
                setFrameOrigin(NSPoint(
                    x: gestureInitialFrame.origin.x + deltaX,
                    y: gestureInitialFrame.origin.y + deltaY
                ))
                return
            }

            var newFrame = gestureInitialFrame
            if let resizeH {
                switch resizeH {
                case .minX:
                    newFrame.origin.x = gestureInitialFrame.origin.x + deltaX
                    newFrame.size.width = gestureInitialFrame.size.width - deltaX
                case .maxX:
                    newFrame.size.width = gestureInitialFrame.size.width + deltaX
                default:
                    break
                }
            }
            if let resizeV {
                switch resizeV {
                case .minY:
                    newFrame.origin.y = gestureInitialFrame.origin.y + deltaY
                    newFrame.size.height = gestureInitialFrame.size.height - deltaY
                case .maxY:
                    newFrame.size.height = gestureInitialFrame.size.height + deltaY
                default:
                    break
                }
            }
            newFrame.size.width = min(max(newFrame.size.width, minSize.width), maxSize.width)
            newFrame.size.height = min(max(newFrame.size.height, minSize.height), maxSize.height)
            if resizeH == .minX {
                newFrame.origin.x = gestureInitialFrame.maxX - newFrame.size.width
            }
            if resizeV == .minY {
                newFrame.origin.y = gestureInitialFrame.maxY - newFrame.size.height
            }
            onFrameChanging?(newFrame.size)
            setFrame(newFrame, display: true)
            return

        case .leftMouseUp:
            if gestureActive {
                gestureActive = false
                isMovingWindow = false
                resizeH = nil
                resizeV = nil
                NSCursor.arrow.set()
                onFrameDidChange?()
                // Clear only after the final save so the last size is kept.
                isUserResizing = false
                return
            }
            isUserResizing = false

        default:
            break
        }

        super.sendEvent(event)

        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            restorePreferredFirstResponder()
        }
    }

    private func restorePreferredFirstResponder() {
        guard isKeyWindow,
              let preferredFirstResponder,
              firstResponder !== preferredFirstResponder,
              fieldEditor(false, for: preferredFirstResponder) !== firstResponder else {
            return
        }

        DispatchQueue.main.async { [weak self, weak preferredFirstResponder] in
            guard let self, self.isKeyWindow, let preferredFirstResponder else { return }
            self.makeFirstResponder(preferredFirstResponder)
        }
    }
}

private final class ThinScroller: NSScroller {
    override static func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        16
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
        drawKnob()
    }

    override func drawKnob() {
        let knobRect = rect(for: .knob).insetBy(dx: 2, dy: 2)
        let radius = knobRect.width / 2
        let knobPath = NSBezierPath(roundedRect: knobRect, xRadius: radius, yRadius: radius)
        NSColor.tertiaryLabelColor.setFill()
        knobPath.fill()
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        NSColor.clear.setFill()
        slotRect.fill()
    }
}

private final class SearchResultRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { true }
        set { _ = newValue }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        // The row sits on glass, so whatever is behind the window bleeds through
        // the fill and a faint wash vanishes against a light backdrop. The tint is
        // carried mostly by opacity rather than by a drawn edge, matching the
        // panel's rule of not putting hard lines on the material.
        let rect = bounds.insetBy(dx: 6, dy: 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSColor.controlAccentColor.withAlphaComponent(0.5).setFill()
        path.fill()
    }

    override func drawBackground(in dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
    }
}

private final class SearchResultCellView: NSTableCellView {
    private let thumbnailView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true

        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = 6
        thumbnailView.layer?.masksToBounds = true
        addSubview(thumbnailView)

        titleField.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        titleField.textColor = .labelColor
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        titleField.cell?.usesSingleLineMode = true
        titleField.cell?.wraps = false
        titleField.cell?.lineBreakMode = .byTruncatingTail
        titleField.isEditable = false
        titleField.isSelectable = false
        addSubview(titleField)

        textField = titleField
        imageView = thumbnailView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, image: NSImage?) {
        titleField.stringValue = title
        thumbnailView.image = image
        thumbnailView.isHidden = image == nil
        needsLayout = true
    }

    override func layout() {
        super.layout()

        let bounds = self.bounds.insetBy(dx: 0, dy: 0)
        let imageSize: CGFloat = thumbnailView.isHidden ? 0 : 20
        let imageSpacing: CGFloat = thumbnailView.isHidden ? 0 : 6
        let textX = bounds.minX + imageSize + imageSpacing
        let textWidth = max(0, bounds.width - imageSize - imageSpacing)

        thumbnailView.frame = NSRect(
            x: bounds.minX,
            y: floor((bounds.height - 20) / 2),
            width: imageSize,
            height: 20
        )

        titleField.frame = NSRect(
            x: textX,
            y: floor((bounds.height - 16) / 2),
            width: textWidth,
            height: 16
        )
    }
}
