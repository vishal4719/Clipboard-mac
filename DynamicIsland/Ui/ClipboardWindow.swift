import AppKit

// MARK: - ClipboardWindow

class ClipboardWindow: NSPanel {
    
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var ocrObserver: NSObjectProtocol?
    private var currentTab: Tab = .clipboard
    
    private var tabButtons: [Tab: HoverButton] = [:]
    private var tabIndicator: CALayer?
    private var tabSegment: NSView?
    private var headerHeight: CGFloat = 54
    private let windowWidth: CGFloat = 400
    private let windowHeight: CGFloat = 560
    private let searchFieldHeight: CGFloat = 32
    private let searchFieldPadding: CGFloat = 10
    private var glassRoot: NSVisualEffectView?
    
    // Pinning State
    private var isPinned: Bool = false
    private var pinButton: HoverIconButton?
    
    // Search & keyboard navigation state (clipboard tab)
    private var searchField: NSSearchField?
    private var searchQuery: String = ""
    private var displayedClipboardItems: [ClipboardItem] = []
    private var clipboardRowViews: [NSClickableView] = []
    private var clipboardScrollView: NSScrollView?
    private var clipboardListView: FlippedView?
    private var highlightedIndex: Int = 0
    
    // Inline Apple Intelligence panel state
    private var aiOverlay: NSView?
    private var aiResultTextView: NSTextView?
    private var aiSpinner: NSProgressIndicator?
    private var aiTask: Task<Void, Never>?
    private var aiInputText: String = ""
    private var aiCurrentAction: AIAction = .summarize
    private var aiCustomPrompt: String = ""
    private var aiResultText: String = ""
    private var aiPasteButton: NSButton?
    private var aiCopyButton: NSButton?
    private var aiRegenButton: NSButton?
    private var aiSaveButton: NSButton?
    private var aiTitleLabel: NSTextField?
    private var aiPromptField: NSTextField?
    private var aiActionButtons: [AIAction: NSButton] = [:]
    /// Invalidates in-flight UI updates when the user switches actions quickly.
    private var aiRunToken = UUID()
    
    enum Tab: Int {
        case clipboard = 0
        case tray = 1
        case emoji = 2
    }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 560),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        setupWindow()
        setupContent()
        setupClickMonitor()
        setupOCRObserver()
        setupAppearanceObserver()
        registerForDraggedTypes([.fileURL])
    }

    private func setupAppearanceObserver() {
        // Re-apply glass chrome when the user flips System Settings appearance.
        DistributedNotificationCenter.default.addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshGlassChrome()
        }
    }

    private func refreshGlassChrome() {
        guard let root = glassRoot else { return }
        LiquidGlass.applyChrome(to: root, bounds: root.bounds)
        // Rebuild visible content so adaptive colors refresh.
        if let contentView = self.contentView {
            // Keep header; rebuild body
            updateContent(in: contentView)
        }
    }
    
    private func setupOCRObserver() {
        ocrObserver = NotificationCenter.default.addObserver(
            forName: .clipboardOCRDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.currentTab == .clipboard else { return }
            // OCR finished for one of the items; refresh the visible list so its
            // preview text + indicator + searchability all reflect the new text.
            self.refreshClipboardList()
        }
    }
    
    private func setupWindow() {
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.isFloatingPanel = true
        self.becomesKeyOnlyIfNeeded = false
        self.hasShadow = true
        self.styleMask.insert(.fullSizeContentView)
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isMovableByWindowBackground = true
        // Follow System Settings — do NOT force dark.
        self.appearance = nil
    }
    
    // MARK: - Content (liquid-glass background)
    
    private func setupContent() {
        let bounds = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)
        
        let visualEffectView = NSVisualEffectView(frame: bounds)
        LiquidGlass.applyChrome(to: visualEffectView, bounds: bounds)
        glassRoot = visualEffectView
        self.contentView = visualEffectView
        
        createHeader(in: visualEffectView)
        updateContent(in: visualEffectView)
    }
    
    // MARK: - Header
    
    private func createHeader(in container: NSView) {
        let headerY = windowHeight - headerHeight
        let header = NSView(frame: NSRect(x: 0, y: headerY, width: windowWidth, height: headerHeight))
        header.wantsLayer = true
        header.identifier = NSUserInterfaceItemIdentifier("clippy.header")
        container.addSubview(header)
        
        // Hairline divider under the header
        let divider = CALayer()
        divider.frame = CGRect(x: 16, y: 0, width: windowWidth - 32, height: LiquidGlass.hairline)
        divider.backgroundColor = LiquidGlass.separator.cgColor
        header.layer?.addSublayer(divider)
        
        // Logo (rounded glass tile)
        let logo = NSImageView(frame: NSRect(x: 16, y: (headerHeight - 26) / 2, width: 26, height: 26))
        logo.image = NSImage(named: "AppIcon") ?? NSImage(systemSymbolName: "doc.on.clipboard.fill", accessibilityDescription: "Logo")
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.wantsLayer = true
        logo.layer?.cornerRadius = 7
        logo.layer?.cornerCurve = .continuous
        logo.layer?.masksToBounds = true
        logo.layer?.borderWidth = LiquidGlass.hairline
        logo.layer?.borderColor = LiquidGlass.wellStroke.cgColor
        header.addSubview(logo)
        
        // Title
        let title = NSTextField(labelWithString: "Clippy")
        title.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        title.textColor = LiquidGlass.primaryText
        title.frame = NSRect(x: 50, y: (headerHeight - 18) / 2, width: 100, height: 18)
        header.addSubview(title)
        
        // Segmented tab control – glass well
        let segmentWidth: CGFloat = 114
        let segmentHeight: CGFloat = 30
        let segmentX: CGFloat = windowWidth - 16 - 68 - 8 - segmentWidth
        let segmentY: CGFloat = (headerHeight - segmentHeight) / 2
        let segment = NSView(frame: NSRect(x: segmentX, y: segmentY, width: segmentWidth, height: segmentHeight))
        LiquidGlass.styleWell(segment, corner: LiquidGlass.controlCorner)
        header.addSubview(segment)
        tabSegment = segment
        
        // Sliding indicator (pill behind selected tab)
        let inset: CGFloat = 3
        let tabW = (segmentWidth - inset * 2) / 3
        let indicator = CALayer()
        indicator.frame = CGRect(
            x: inset + CGFloat(currentTab.rawValue) * tabW,
            y: inset,
            width: tabW,
            height: segmentHeight - inset * 2
        )
        indicator.backgroundColor = LiquidGlass.pillFill.cgColor
        indicator.cornerRadius = 7
        indicator.cornerCurve = .continuous
        indicator.borderColor = LiquidGlass.pillStroke.cgColor
        indicator.borderWidth = LiquidGlass.hairline
        // Soft shadow for the floating pill
        indicator.shadowColor = NSColor.black.withAlphaComponent(0.18).cgColor
        indicator.shadowOpacity = 1
        indicator.shadowRadius = 3
        indicator.shadowOffset = CGSize(width: 0, height: -0.5)
        segment.layer?.addSublayer(indicator)
        tabIndicator = indicator
        
        // Tab buttons
        addTabButton(symbolName: "list.bullet", tab: .clipboard, in: segment, x: inset, width: tabW, height: segmentHeight - inset * 2)
        addTabButton(symbolName: "tray", tab: .tray, in: segment, x: inset + tabW, width: tabW, height: segmentHeight - inset * 2)
        addTabButton(symbolName: "face.smiling", tab: .emoji, in: segment, x: inset + tabW * 2, width: tabW, height: segmentHeight - inset * 2)
        
        // Pin button
        let pinBtn = HoverIconButton(frame: NSRect(x: windowWidth - 16 - 68, y: (headerHeight - 28) / 2, width: 28, height: 28))
        pinBtn.symbolName = "pin"
        pinBtn.symbolPointSize = 12
        pinBtn.symbolWeight = .semibold
        pinBtn.normalTint = LiquidGlass.iconMuted
        pinBtn.hoverTint = LiquidGlass.iconPrimary
        pinBtn.hoverBackground = LiquidGlass.rowHover
        pinBtn.toolTip = "Pin window"
        pinBtn.target = self
        pinBtn.action = #selector(toggleWindowPin)
        pinBtn.applySymbol()
        header.addSubview(pinBtn)
        self.pinButton = pinBtn
        
        // Trash button
        let clearBtn = HoverIconButton(frame: NSRect(x: windowWidth - 16 - 28, y: (headerHeight - 28) / 2, width: 28, height: 28))
        clearBtn.symbolName = "trash"
        clearBtn.symbolPointSize = 12
        clearBtn.symbolWeight = .semibold
        clearBtn.normalTint = LiquidGlass.iconMuted
        clearBtn.hoverTint = NSColor.systemRed
        clearBtn.hoverBackground = NSColor.systemRed.withAlphaComponent(0.14)
        clearBtn.toolTip = "Clear all"
        clearBtn.target = self
        clearBtn.action = #selector(clearAllClicked)
        clearBtn.applySymbol()
        header.addSubview(clearBtn)
    }
    
    private func addTabButton(symbolName: String, tab: Tab, in segment: NSView, x: CGFloat, width: CGFloat, height: CGFloat) {
        let yOffset: CGFloat = 3
        let button = HoverButton(frame: NSRect(x: x, y: yOffset, width: width, height: height))
        button.title = ""
        let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(cfg)
        button.bezelStyle = .inline
        button.isBordered = false
        button.wantsLayer = true
        button.imageScaling = .scaleProportionallyDown
        button.setIsSelected(tab == currentTab, animated: false)
        button.target = self
        button.action = #selector(tabButtonClicked(_:))
        button.tag = tab.rawValue
        segment.addSubview(button)
        tabButtons[tab] = button
    }
    
    @objc private func tabButtonClicked(_ sender: NSButton) {
        let newTab = Tab(rawValue: sender.tag) ?? .clipboard
        switchToTab(newTab)
    }
    
    @objc private func clearAllClicked() {
        if currentTab == .clipboard {
            ClipboardManager.shared.clearAll()
            highlightedIndex = 0
            refreshClipboardList()
            return
        } else if currentTab == .tray {
            TrayManager.shared.clearAll()
        }
        if let contentView = self.contentView {
            updateContent(in: contentView)
        }
    }
    
    @objc private func toggleWindowPin() {
        isPinned.toggle()
        pinButton?.symbolName = isPinned ? "pin.fill" : "pin"
        pinButton?.normalTint = isPinned ? NSColor.systemYellow : LiquidGlass.iconMuted
        pinButton?.hoverTint = isPinned ? NSColor.systemYellow : LiquidGlass.iconPrimary
        pinButton?.applySymbol()
        pinButton?.refreshAppearance()
    }
    
    func switchToTab(_ tab: Tab) {
        let previousTab = currentTab
        currentTab = tab
        // Drop any inline AI panel when leaving the clipboard tab
        if previousTab == .clipboard, tab != .clipboard, isAIInlineVisible {
            aiTask?.cancel()
            aiOverlay?.removeFromSuperview()
            aiOverlay = nil
            aiResultTextView = nil
            aiSpinner = nil
            aiCopyButton = nil
            aiPasteButton = nil
            aiRegenButton = nil
            aiSaveButton = nil
            aiTitleLabel = nil
            aiActionButtons.removeAll()
        }
        
        // Animate the pill indicator
        if let indicator = tabIndicator, let segment = tabSegment {
            let inset: CGFloat = 3
            let tabW = (segment.bounds.width - inset * 2) / 3
            let newFrame = CGRect(
                x: inset + CGFloat(tab.rawValue) * tabW,
                y: inset,
                width: tabW,
                height: segment.bounds.height - inset * 2
            )
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.22)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            indicator.frame = newFrame
            CATransaction.commit()
        }
        
        for (tabType, button) in tabButtons {
            button.setIsSelected(tabType == tab, animated: true)
        }
        
        if previousTab != tab, let contentView = self.contentView {
            updateContent(in: contentView)
        }
    }
    
    // MARK: - Content area
    
    private func updateContent(in container: NSView) {
        // Remove old content (keep the header at the top of the window)
        let headerThreshold: CGFloat = windowHeight - headerHeight
        container.subviews.forEach { view in
            if view.frame.origin.y < headerThreshold {
                view.removeFromSuperview()
            }
        }
        
        switch currentTab {
        case .clipboard:
            showClipboardContent(in: container)
        case .tray:
           showTrayContent(in: container)
        case .emoji:
           showEmojiContent(in: container)
        }
    }
    
    private var contentRegionHeight: CGFloat { windowHeight - headerHeight - footerHeight }
    private let footerHeight: CGFloat = 30
    
    private func showClipboardContent(in container: NSView) {
        // Search field at the top of the content area
        let searchY = windowHeight - headerHeight - searchFieldPadding - searchFieldHeight
        let search = makeSearchField()
        search.frame = NSRect(
            x: 12,
            y: searchY,
            width: windowWidth - 24,
            height: searchFieldHeight
        )
        search.stringValue = searchQuery
        container.addSubview(search)
        searchField = search
        
        // Scroll view for the list, sized to fit between the footer and the search field
        let listTop = searchY - searchFieldPadding
        let listHeight = listTop - footerHeight
        let scrollView = makeScrollView(y: footerHeight, height: listHeight)
        let listView = FlippedView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: 0))
        scrollView.documentView = listView
        container.addSubview(scrollView)
        clipboardScrollView = scrollView
        clipboardListView = listView
        
        // Footer with dynamic hint text
        container.addSubview(makeFooter(text: "↑↓ navigate  ·  ⏎ paste  ·  ⌘1-9 quick paste  ·  esc"))
        
        // Render the list (initial)
        refreshClipboardList()
        
        // Auto-focus the search field so users can just start typing
        DispatchQueue.main.async { [weak self, weak search] in
            guard let self = self, let search = search else { return }
            self.makeFirstResponder(search)
        }
    }
    
    /// Builds a styled NSSearchField that fits the liquid-glass UI.
    private func makeSearchField() -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Search clipboard…"
        field.font = NSFont.systemFont(ofSize: 13)
        field.textColor = LiquidGlass.primaryText
        field.delegate = self
        field.bezelStyle = .roundedBezel
        field.focusRingType = .none
        field.wantsLayer = true
        field.drawsBackground = false
        LiquidGlass.styleWell(field, corner: LiquidGlass.chipCorner)
        if let cell = field.cell as? NSSearchFieldCell {
            cell.searchButtonCell?.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
            cell.searchButtonCell?.imageScaling = .scaleProportionallyDown
            cell.cancelButtonCell?.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
            cell.placeholderAttributedString = NSAttributedString(
                string: "Search clipboard…",
                attributes: [
                    .foregroundColor: LiquidGlass.tertiaryText,
                    .font: NSFont.systemFont(ofSize: 13)
                ]
            )
        }
        return field
    }
    
    // MARK: - Filtering & list rendering
    
    /// Returns the items that should be visible given the current search query.
    /// Pinned items always appear first, regardless of recency.
    private func filteredClipboardItems() -> [ClipboardItem] {
        let allItems = ClipboardManager.shared.items
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered: [ClipboardItem]
        if query.isEmpty {
            filtered = allItems
        } else {
            filtered = allItems.filter { item in
                item.searchableText.lowercased().contains(query)
            }
        }
        // Pinned first, then preserve relative order within each group.
        return filtered.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned && !b.isPinned }
            return false
        }
    }
    
    /// Re-renders the clipboard list view from scratch using current search/filter state.
    /// Cheap because the list is bounded (max ~15 items).
    private func refreshClipboardList() {
        guard let listView = clipboardListView else { return }
        
        // Clear previous rows
        listView.subviews.forEach { $0.removeFromSuperview() }
        clipboardRowViews.removeAll(keepingCapacity: true)
        
        let items = filteredClipboardItems()
        displayedClipboardItems = items
        
        if items.isEmpty {
            // Empty state, sized to fit inside the list view
            let isSearchEmpty = !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let empty = makeEmptyState(
                iconName: isSearchEmpty ? "magnifyingglass" : "doc.on.clipboard",
                title: isSearchEmpty ? "No matches" : "No clipboard history",
                subtitle: isSearchEmpty ? "Try a different search term" : "Copy anything to get started"
            )
            // Recenter empty state inside the actual list view bounds
            let listHeight = clipboardScrollView?.frame.height ?? 0
            empty.frame.origin = NSPoint(
                x: empty.frame.origin.x,
                y: max(0, (listHeight - empty.frame.height) / 2)
            )
            listView.frame.size.height = max(listHeight, empty.frame.height)
            listView.addSubview(empty)
            return
        }
        
        var y: CGFloat = 8
        let rowHeight: CGFloat = 44
        
        for (index, item) in items.enumerated() {
            let row = createClipboardItemView(item: item, index: index, yPosition: y)
            row.frame.size.height = rowHeight
            listView.addSubview(row)
            if let clickable = row as? NSClickableView {
                clipboardRowViews.append(clickable)
            }
            y += rowHeight + 4
        }
        
        listView.frame.size.height = y + 8
        clipboardScrollView?.documentView = listView
        listView.scroll(NSPoint(x: 0, y: 0))
        
        // Re-apply highlight (clamped)
        highlightedIndex = min(highlightedIndex, max(0, items.count - 1))
        applyHighlight()
    }
    
    // MARK: - Highlight & paste actions
    
    private func applyHighlight() {
        for (i, view) in clipboardRowViews.enumerated() {
            view.setHighlighted(i == highlightedIndex)
        }
    }
    
    private func moveHighlight(by delta: Int) {
        guard !displayedClipboardItems.isEmpty else { return }
        let count = displayedClipboardItems.count
        highlightedIndex = (highlightedIndex + delta + count) % count
        applyHighlight()
        scrollHighlightedIntoView()
    }
    
    private func scrollHighlightedIntoView() {
        guard highlightedIndex < clipboardRowViews.count,
              let scrollView = clipboardScrollView else { return }
        let row = clipboardRowViews[highlightedIndex]
        let frameInList = row.frame
        // Slight vertical padding so the row isn't flush against the edge
        let padded = frameInList.insetBy(dx: 0, dy: -8)
        clipboardListView?.scrollToVisible(padded)
        _ = scrollView // silence unused
    }
    
    private func pasteHighlighted() {
        guard highlightedIndex < displayedClipboardItems.count else { return }
        pasteClipboardItem(displayedClipboardItems[highlightedIndex])
    }
    
    private func pasteItemAtVisibleIndex(_ index: Int) {
        guard index >= 0, index < displayedClipboardItems.count else { return }
        pasteClipboardItem(displayedClipboardItems[index])
    }
    
    private func clearSearch() {
        searchQuery = ""
        searchField?.stringValue = ""
        highlightedIndex = 0
        refreshClipboardList()
    }
    
    private func showTrayContent(in container: NSView) {
        let items = TrayManager.shared.items
        
        let dropZone = DropZoneNSView(frame: NSRect(x: 0, y: footerHeight, width: windowWidth, height: contentRegionHeight))
        dropZone.onFilesDropped = { [weak self] urls in
            for url in urls {
                TrayManager.shared.addFile(url)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard let self = self, let contentView = self.contentView else { return }
                self.updateContent(in: contentView)
            }
        }
        container.addSubview(dropZone)
        
        if items.isEmpty {
            let empty = makeEmptyState(
                iconName: "tray.and.arrow.down",
                title: "Tray is empty",
                subtitle: "Drop files anywhere to store them"
            )
            empty.frame.origin.y = (contentRegionHeight - empty.frame.height) / 2
            dropZone.addSubview(empty)
        } else {
            let listView = FlippedView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: contentRegionHeight))
            dropZone.addSubview(listView)
            
            var y: CGFloat = 8
            let rowHeight: CGFloat = 44
            
            for (index, item) in items.prefix(12).enumerated() {
                let row = createTrayItemView(item: item, index: index, yPosition: y)
                row.frame.size.height = rowHeight
                row.frame.origin = NSPoint(x: 0, y: y)
                listView.addSubview(row)
                y += rowHeight + 4
            }
        }
        
        container.addSubview(makeFooter(text: "Click to copy  ·  Drop files anywhere"))
    }

    private func showEmojiContent(in container: NSView) {
        let scrollView = makeScrollView(y: footerHeight, height: contentRegionHeight)
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        
        let categories = EmojiManager.shared.categories
        let listView = FlippedView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: 1000))
        
        var currentY: CGFloat = 12
        let itemSize: CGFloat = 32
        let spacing: CGFloat = 4
        let columns = 9
        let startX: CGFloat = 14
        
        for category in categories {
            let header = NSTextField(labelWithString: category.name.uppercased())
            header.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
            header.textColor = LiquidGlass.tertiaryText
            header.frame = NSRect(x: 16, y: currentY, width: windowWidth - 32, height: 14)
            listView.addSubview(header)
            
            currentY += 22
            
            var col = 0
            for emoji in category.emojis {
                let btn = HoverEmojiButton(frame: NSRect(
                    x: startX + CGFloat(col) * (itemSize + spacing),
                    y: currentY,
                    width: itemSize,
                    height: itemSize
                ))
                btn.title = emoji
                btn.font = NSFont.systemFont(ofSize: 20)
                btn.bezelStyle = .inline
                btn.isBordered = false
                btn.wantsLayer = true
                btn.layer?.cornerRadius = 7
                btn.layer?.cornerCurve = .continuous
                btn.target = self
                btn.action = #selector(emojiClicked(_:))
                listView.addSubview(btn)
                
                col += 1
                if col >= columns {
                    col = 0
                    currentY += itemSize + spacing
                }
            }
            
            if col != 0 {
                currentY += itemSize + spacing
            }
            currentY += 12
        }
        
        listView.frame.size.height = currentY
        scrollView.documentView = listView
        listView.scroll(NSPoint(x: 0, y: 0))
        container.addSubview(scrollView)
    }

    @objc private func emojiClicked(_ sender: NSButton) {
        let emoji = sender.title
        NSApp.hide(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            PasteManager.shared.pasteString(emoji)
        }
    }
    
    // MARK: - Click monitor
    
    private func setupClickMonitor() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self = self else { return }
            if self.isPinned { return }
            let clickLocation = NSEvent.mouseLocation
            if !NSPointInRect(clickLocation, self.frame) {
                self.close()
            }
        }
        
        // Local key monitor – handles ESC + ⌘1-⌘9 quick paste even when the
        // search field has focus (the search field swallows arrow keys / return,
        // so we route those via the NSSearchFieldDelegate methods instead).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            
            // ESC: close AI panel first, then clear search, then close window
            if event.keyCode == 53 {
                if self.isAIInlineVisible {
                    self.closeAIInline()
                    return nil
                }
                if self.currentTab == .clipboard,
                   !self.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.clearSearch()
                    return nil
                }
                self.close()
                return nil
            }
            
            // ⌘1–⌘9 quick paste (clipboard tab only)
            if event.modifierFlags.contains(.command),
               !event.modifierFlags.contains(.shift),
               !event.modifierFlags.contains(.option),
               self.currentTab == .clipboard,
               let chars = event.charactersIgnoringModifiers,
               chars.count == 1,
               let digit = Int(chars), (1...9).contains(digit) {
                self.pasteItemAtVisibleIndex(digit - 1)
                return nil
            }
            
            return event
        }
    }
    
    override func close() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let observer = ocrObserver {
            NotificationCenter.default.removeObserver(observer)
            ocrObserver = nil
        }
        // Cancel any in-flight AI streaming so it doesn't keep generating
        // tokens after the window is gone.
        aiTask?.cancel()
        aiTask = nil
        super.close()
    }
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    
    // MARK: - Drag entry (window-level)
    
    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        switchToTab(.tray)
        return .copy
    }
    
    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return false
        }
        for url in urls {
            TrayManager.shared.addFile(url)
        }
        if let contentView = self.contentView {
            updateContent(in: contentView)
        }
        return true
    }
    
    // MARK: - Item paste / copy
    
    fileprivate func pasteClipboardItem(_ item: ClipboardItem) {
        // Principle: paste what the row visually shows.
        // For image rows with OCR text, the row displays the recognized text –
        // so the primary action pastes that text. The original image stays
        // accessible via the row's menu ("Paste as Image").
        NSApp.hide(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            PasteManager.shared.pasteItemSmart(item)
        }
    }
    
    fileprivate func copyTrayItem(_ item: TrayItem) {
        NSApp.hide(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            TrayManager.shared.copyToClipboard(item)
            PasteManager.shared.simulateCmdV()
        }
    }
}

// MARK: - NSSearchFieldDelegate (live filter + key handling)

extension ClipboardWindow: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField else { return }
        searchQuery = field.stringValue
        highlightedIndex = 0
        refreshClipboardList()
    }
    
    /// Catch arrow keys / Return / Esc inside the search field so they navigate
    /// the list instead of moving the caret or beeping.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            moveHighlight(by: 1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            moveHighlight(by: -1)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            pasteHighlighted()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                clearSearch()
            } else {
                close()
            }
            return true
        default:
            return false
        }
    }
}

// MARK: - Item Rows

extension ClipboardWindow {
    
    func createClipboardItemView(item: ClipboardItem, index: Int, yPosition: CGFloat) -> NSView {
        let rowWidth: CGFloat = windowWidth - 20
        let rowHeight: CGFloat = 44
        let row = NSClickableView(frame: NSRect(x: 10, y: yPosition, width: rowWidth, height: rowHeight))
        row.wantsLayer = true
        row.layer?.cornerRadius = LiquidGlass.rowCorner
        row.layer?.cornerCurve = .continuous
        
        row.onClick = { [weak self] in
            self?.pasteClipboardItem(item)
        }
        
        // Leading icon (small monochrome SF Symbol)
        let iconSize: CGFloat = 18
        let iconX: CGFloat = 12
        let iconY: CGFloat = (rowHeight - iconSize) / 2
        
        if item.isImage, let image = item.nsImage() {
            let thumb = NSImageView(frame: NSRect(x: iconX - 2, y: (rowHeight - 24) / 2, width: 24, height: 24))
            thumb.image = image
            thumb.imageScaling = .scaleProportionallyUpOrDown
            thumb.wantsLayer = true
            thumb.layer?.cornerRadius = 6
            thumb.layer?.cornerCurve = .continuous
            thumb.layer?.masksToBounds = true
            thumb.layer?.borderWidth = LiquidGlass.hairline
            thumb.layer?.borderColor = LiquidGlass.thumbBorder.cgColor
            row.addSubview(thumb)
        } else {
            let symbol = NSImageView(frame: NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize))
            let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            symbol.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)?.withSymbolConfiguration(cfg)
            symbol.contentTintColor = LiquidGlass.iconMuted
            symbol.imageAlignment = .alignCenter
            row.addSubview(symbol)
        }
        
        let titleX: CGFloat = iconX + iconSize + 12
        var trailingReservation: CGFloat = 62
        let displayTitle: String
        if item.isImage {
            if item.hasOCRText, let ocr = item.ocrText {
                displayTitle = ocr.replacingOccurrences(of: "\n", with: " ")
                trailingReservation += 18
            } else {
                displayTitle = "Image"
            }
        } else {
            displayTitle = item.preview
        }
        let titleW: CGFloat = rowWidth - titleX - trailingReservation
        let titleLabel = NSTextField(labelWithString: displayTitle)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        titleLabel.textColor = LiquidGlass.primaryText
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.frame = NSRect(x: titleX, y: (rowHeight - 18) / 2, width: titleW, height: 18)
        row.addSubview(titleLabel)
        
        if item.isImage && item.hasOCRText {
            let badge = NSImageView(frame: NSRect(x: titleX + titleW + 4, y: (rowHeight - 12) / 2, width: 14, height: 14))
            let cfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            badge.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: "Text detected")?
                .withSymbolConfiguration(cfg)
            badge.contentTintColor = NSColor.controlAccentColor
            badge.imageAlignment = .alignCenter
            badge.toolTip = "Text detected – right-click to Copy as Text"
            row.addSubview(badge)
        }
        
        if item.isPinned {
            let pin = NSImageView(frame: NSRect(x: rowWidth - 56, y: (rowHeight - 12) / 2, width: 12, height: 12))
            let cfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            pin.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinned")?.withSymbolConfiguration(cfg)
            pin.contentTintColor = NSColor.systemYellow
            pin.imageAlignment = .alignCenter
            row.addSubview(pin)
        } else if index < 9 {
            let chip = NSTextField(labelWithString: "\(index + 1)")
            chip.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
            chip.textColor = LiquidGlass.tertiaryText
            chip.alignment = .center
            chip.frame = NSRect(x: rowWidth - 56, y: (rowHeight - 14) / 2, width: 16, height: 14)
            row.addSubview(chip)
        }
        
        let menuButton = HoverIconButton(frame: NSRect(x: rowWidth - 34, y: (rowHeight - 26) / 2, width: 26, height: 26))
        menuButton.symbolName = "ellipsis"
        menuButton.symbolPointSize = 12
        menuButton.symbolWeight = .semibold
        menuButton.normalTint = LiquidGlass.iconMuted
        menuButton.hoverTint = LiquidGlass.iconPrimary
        menuButton.hoverBackground = LiquidGlass.rowHover
        menuButton.applySymbol()
        menuButton.target = self
        menuButton.action = #selector(showItemMenu(_:))
        menuButton.tag = index
        row.addSubview(menuButton)
        
        return row
    }
    
    func createTrayItemView(item: TrayItem, index: Int, yPosition: CGFloat) -> NSView {
        let rowWidth: CGFloat = windowWidth - 20
        let rowHeight: CGFloat = 44
        let row = DraggableTrayItemView(frame: NSRect(x: 10, y: yPosition, width: rowWidth, height: rowHeight))
        row.wantsLayer = true
        row.layer?.cornerRadius = LiquidGlass.rowCorner
        row.layer?.cornerCurve = .continuous
        row.trayItem = item
        
        row.onClick = { [weak self] in
            self?.copyTrayItem(item)
        }
        
        let iconX: CGFloat = 12
        let iconSize: CGFloat = 22
        let iconY: CGFloat = (rowHeight - iconSize) / 2
        
        if item.isImage, let image = item.nsImage() {
            let thumb = NSImageView(frame: NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize))
            thumb.image = image
            thumb.imageScaling = .scaleProportionallyUpOrDown
            thumb.wantsLayer = true
            thumb.layer?.cornerRadius = 6
            thumb.layer?.cornerCurve = .continuous
            thumb.layer?.masksToBounds = true
            thumb.layer?.borderWidth = LiquidGlass.hairline
            thumb.layer?.borderColor = LiquidGlass.thumbBorder.cgColor
            row.addSubview(thumb)
        } else if item.type == .file {
            let icon = NSImageView(frame: NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize))
            icon.imageScaling = .scaleProportionallyUpOrDown
            if let fileURL = item.getFileURL() {
                icon.image = NSWorkspace.shared.icon(forFile: fileURL.path)
            } else {
                let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
                icon.image = NSImage(systemSymbolName: "doc.fill", accessibilityDescription: nil)?.withSymbolConfiguration(cfg)
                icon.contentTintColor = LiquidGlass.iconMuted
            }
            row.addSubview(icon)
        } else {
            let symbol = NSImageView(frame: NSRect(x: iconX + 2, y: (rowHeight - 18) / 2, width: 18, height: 18))
            let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            symbol.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)?.withSymbolConfiguration(cfg)
            symbol.contentTintColor = LiquidGlass.iconMuted
            symbol.imageAlignment = .alignCenter
            row.addSubview(symbol)
        }
        
        let titleX: CGFloat = iconX + iconSize + 12
        let titleW: CGFloat = rowWidth - titleX - 60
        let title = NSTextField(labelWithString: item.name)
        title.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        title.textColor = LiquidGlass.primaryText
        title.lineBreakMode = .byTruncatingTail
        title.frame = NSRect(x: titleX, y: (rowHeight - 18) / 2, width: titleW, height: 18)
        row.addSubview(title)
        
        if item.isPinned {
            let pin = NSImageView(frame: NSRect(x: rowWidth - 56, y: (rowHeight - 12) / 2, width: 12, height: 12))
            let cfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            pin.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinned")?.withSymbolConfiguration(cfg)
            pin.contentTintColor = NSColor.systemYellow
            pin.imageAlignment = .alignCenter
            row.addSubview(pin)
        }
        
        let menuButton = HoverIconButton(frame: NSRect(x: rowWidth - 34, y: (rowHeight - 26) / 2, width: 26, height: 26))
        menuButton.symbolName = "ellipsis"
        menuButton.symbolPointSize = 12
        menuButton.symbolWeight = .semibold
        menuButton.normalTint = LiquidGlass.iconMuted
        menuButton.hoverTint = LiquidGlass.iconPrimary
        menuButton.hoverBackground = LiquidGlass.rowHover
        menuButton.applySymbol()
        menuButton.target = self
        menuButton.action = #selector(showTrayItemMenu(_:))
        menuButton.tag = index
        row.addSubview(menuButton)
        
        return row
    }
    
    // MARK: - Item context menu
    
    @objc fileprivate func showItemMenu(_ sender: NSButton) {
        let index = sender.tag
        // The menu button's tag indexes into the *displayed* (filtered) list,
        // so the menu always operates on the same item the user sees.
        let items = displayedClipboardItems.isEmpty ? ClipboardManager.shared.items : displayedClipboardItems
        guard index < items.count else { return }
        let item = items[index]
        
        let menu = NSMenu()
        
        if item.isImage && item.hasOCRText {
            // Primary action mirrors what the row visually shows: paste the text.
            let pasteText = NSMenuItem(title: "Paste as Text", action: #selector(menuCopyOCRText(_:)), keyEquivalent: "")
            pasteText.target = self
            pasteText.representedObject = item
            pasteText.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: nil)
            menu.addItem(pasteText)
            
            // The original image remains one click away.
            let pasteImage = NSMenuItem(title: "Paste as Image", action: #selector(menuPasteImage(_:)), keyEquivalent: "")
            pasteImage.target = self
            pasteImage.representedObject = item
            pasteImage.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
            menu.addItem(pasteImage)
            
            menu.addItem(NSMenuItem.separator())
            
            // Copy variants (place on clipboard without auto-pasting)
            let copyText = NSMenuItem(title: "Copy Text to Clipboard", action: #selector(menuCopyOCRTextToClipboard(_:)), keyEquivalent: "")
            copyText.target = self
            copyText.representedObject = item
            menu.addItem(copyText)
            
            let copyImage = NSMenuItem(title: "Copy Image to Clipboard", action: #selector(menuCopyItem(_:)), keyEquivalent: "")
            copyImage.target = self
            copyImage.representedObject = item
            menu.addItem(copyImage)
        } else if item.isImage {
            // Image present but OCR hasn't run yet
            let copyImage = NSMenuItem(title: "Copy to Clipboard", action: #selector(menuCopyItem(_:)), keyEquivalent: "")
            copyImage.target = self
            copyImage.representedObject = item
            menu.addItem(copyImage)
            
            let runOcr = NSMenuItem(title: "Detect Text", action: #selector(menuRunOCR(_:)), keyEquivalent: "")
            runOcr.target = self
            runOcr.representedObject = item
            runOcr.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: nil)
            menu.addItem(runOcr)
        } else {
            // Plain text item
            let copyItem = NSMenuItem(title: "Copy to Clipboard", action: #selector(menuCopyItem(_:)), keyEquivalent: "")
            copyItem.target = self
            copyItem.representedObject = item
            menu.addItem(copyItem)
        }
        
        // Apple Intelligence submenu — only show for items that have text
        // (plain text rows, or image rows with successful OCR).
        if AppleIntelligenceProvider.shared.isPotentiallyAvailable,
           let textForAI = aiInputText(for: item), !textForAI.isEmpty {
            menu.addItem(NSMenuItem.separator())
            let aiItem = NSMenuItem(title: "Apple Intelligence", action: nil, keyEquivalent: "")
            aiItem.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
            aiItem.submenu = buildAISubmenu(for: textForAI)
            menu.addItem(aiItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        let pinTitle = item.isPinned ? "Unpin" : "Pin"
        let pinItem = NSMenuItem(title: pinTitle, action: #selector(menuPinItem(_:)), keyEquivalent: "")
        pinItem.target = self
        pinItem.representedObject = item
        menu.addItem(pinItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let deleteItem = NSMenuItem(title: "Delete", action: #selector(menuDeleteItem(_:)), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.representedObject = item
        menu.addItem(deleteItem)
        
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: sender)
    }
    
    /// Pastes the OCR text and auto-types ⌘V into the previous app.
    @objc fileprivate func menuCopyOCRText(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ClipboardItem,
              let ocr = item.ocrText, !ocr.isEmpty else { return }
        NSApp.hide(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            PasteManager.shared.pasteString(ocr)
        }
    }
    
    /// Just copies the OCR text to the clipboard (no auto-paste).
    @objc fileprivate func menuCopyOCRTextToClipboard(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ClipboardItem,
              let ocr = item.ocrText, !ocr.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(ocr, forType: .string)
        ClipboardManager.shared.acknowledgeSelfWrite()
    }
    
    /// Pastes the original image (auto-types ⌘V).
    @objc fileprivate func menuPasteImage(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ClipboardItem else { return }
        NSApp.hide(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            PasteManager.shared.pasteItem(item)
            PasteManager.shared.simulateCmdV()
        }
    }
    
    @objc fileprivate func menuRunOCR(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ClipboardItem else { return }
        ClipboardManager.shared.ensureOCR(for: item)
    }
    
    // MARK: - Apple Intelligence Submenu

    /// Returns the text the AI should operate on for a given clipboard item.
    /// For text items: the original string. For image items: the OCR result.
    /// Returns nil if there's no usable text.
    private func aiInputText(for item: ClipboardItem) -> String? {
        if item.isImage {
            guard let ocr = item.ocrText else { return nil }
            let trimmed = ocr.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        switch item.content {
        case .text(let s):
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case .image:
            return nil
        }
    }

    private func buildAISubmenu(for text: String) -> NSMenu {
        let submenu = NSMenu()
        for action in AIAction.allCases where action != .custom {
            let item = NSMenuItem(title: action.title, action: #selector(menuRunAI(_:)), keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: action.symbolName, accessibilityDescription: action.title)
            item.representedObject = AIInvocation(text: text, action: action)
            submenu.addItem(item)
        }
        submenu.addItem(NSMenuItem.separator())
        let custom = NSMenuItem(title: "Custom Prompt…", action: #selector(menuRunCustomAI(_:)), keyEquivalent: "")
        custom.target = self
        custom.image = NSImage(systemSymbolName: AIAction.custom.symbolName, accessibilityDescription: "Custom Prompt")
        custom.representedObject = text
        submenu.addItem(custom)
        return submenu
    }

    @objc fileprivate func menuRunAI(_ sender: NSMenuItem) {
        guard let invocation = sender.representedObject as? AIInvocation else { return }
        showAIInline(text: invocation.text, action: invocation.action, customPrompt: invocation.customPrompt)
    }

    @objc fileprivate func menuRunCustomAI(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        guard let prompt = askForCustomPrompt(defaultText: aiCustomPrompt) else { return }
        showAIInline(text: text, action: .custom, customPrompt: prompt)
    }

    /// Simple modal asking the user for a freeform AI instruction.
    private func askForCustomPrompt(defaultText: String = "") -> String? {
        let alert = NSAlert()
        alert.messageText = "Custom Prompt"
        alert.informativeText = "Tell Apple Intelligence what to do with this clipboard text."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Run")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "e.g. Turn this into a short tweet"
        field.stringValue = defaultText
        field.isEditable = true
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Inline AI Panel

    /// Builds and displays an overlay panel inside the clipboard window that
    /// streams the result of an Apple Intelligence action. The clipboard list
    /// underneath is preserved so closing the panel returns the user there.
    private func showAIInline(text: String, action: AIAction, customPrompt: String? = nil) {
        guard let container = self.contentView else { return }

        // Cancel anything currently in flight so we never have two streams.
        aiTask?.cancel()
        aiOverlay?.removeFromSuperview()

        aiInputText = text
        aiCurrentAction = action
        aiCustomPrompt = customPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        aiResultText = ""

        // Overlay covers the content area between the header and footer.
        let overlayY = footerHeight
        let overlayH = windowHeight - headerHeight - footerHeight
        let overlay = NSView(frame: NSRect(x: 0, y: overlayY, width: windowWidth, height: overlayH))
        overlay.wantsLayer = true
        container.addSubview(overlay)
        aiOverlay = overlay

        // Frosted base layer — uses the system's vibrant material so the
        // panel feels native and (more importantly) fully blocks the list
        // underneath.
        let frosted = NSVisualEffectView(frame: overlay.bounds)
        frosted.autoresizingMask = [.width, .height]
        frosted.material = .hudWindow
        frosted.blendingMode = .withinWindow
        frosted.state = .active
        frosted.wantsLayer = true
        overlay.addSubview(frosted)

        // Dark tint on top to lift contrast for the streaming text
        let tint = NSView(frame: overlay.bounds)
        tint.autoresizingMask = [.width, .height]
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        overlay.addSubview(tint)

        // Hairline accent stroke at the very top so it visually separates
        // from the search field above.
        let topStroke = NSView(frame: NSRect(x: 0, y: overlayH - 0.5, width: windowWidth, height: 0.5))
        topStroke.autoresizingMask = [.width, .minYMargin]
        topStroke.wantsLayer = true
        topStroke.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        overlay.addSubview(topStroke)

        // Top bar: back button + sparkles icon + action title + spinner
        let topBarH: CGFloat = 38
        let topBar = NSView(frame: NSRect(x: 0, y: overlayH - topBarH, width: windowWidth, height: topBarH))
        overlay.addSubview(topBar)

        let backBtn = HoverIconButton(frame: NSRect(x: 8, y: (topBarH - 26) / 2, width: 26, height: 26))
        let backImg = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        backBtn.image = backImg
        backBtn.imagePosition = .imageOnly
        backBtn.contentTintColor = .white.withAlphaComponent(0.9)
        backBtn.target = self
        backBtn.action = #selector(closeAIInline)
        topBar.addSubview(backBtn)

        let sparklesIV = NSImageView(frame: NSRect(x: 38, y: (topBarH - 14) / 2, width: 14, height: 14))
        sparklesIV.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        sparklesIV.contentTintColor = NSColor.controlAccentColor
        topBar.addSubview(sparklesIV)

        let titleLbl = NSTextField(labelWithString: action == .custom ? "Custom Prompt" : action.title)
        titleLbl.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLbl.textColor = .white
        titleLbl.frame = NSRect(x: 56, y: (topBarH - 16) / 2, width: 220, height: 16)
        topBar.addSubview(titleLbl)
        aiTitleLabel = titleLbl

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.frame = NSRect(x: windowWidth - 8 - 16, y: (topBarH - 16) / 2, width: 16, height: 16)
        topBar.addSubview(spinner)
        aiSpinner = spinner

        // Action chip strip — switch actions without leaving the panel
        let chipBarH: CGFloat = 34
        let chipBarY = overlayH - topBarH - chipBarH
        let chipScroll = NSScrollView(frame: NSRect(x: 0, y: chipBarY, width: windowWidth, height: chipBarH))
        chipScroll.drawsBackground = false
        chipScroll.hasHorizontalScroller = false
        chipScroll.hasVerticalScroller = false
        chipScroll.horizontalScrollElasticity = .allowed
        chipScroll.scrollerStyle = .overlay
        let chipDoc = FlippedView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: chipBarH))
        chipScroll.documentView = chipDoc
        overlay.addSubview(chipScroll)

        aiActionButtons.removeAll()
        var chipX: CGFloat = 10
        for chipAction in AIAction.allCases {
            let chip = NSButton(title: chipAction.shortTitle, target: self, action: #selector(aiChipTapped(_:)))
            chip.bezelStyle = .rounded
            chip.controlSize = .mini
            chip.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            chip.setButtonType(.pushOnPushOff)
            chip.identifier = NSUserInterfaceItemIdentifier(chipAction.rawValue)
            chip.state = (chipAction == action) ? .on : .off
            chip.sizeToFit()
            let w = max(chip.frame.width + 8, 44)
            chip.frame = NSRect(x: chipX, y: (chipBarH - 22) / 2, width: w, height: 22)
            chipDoc.addSubview(chip)
            aiActionButtons[chipAction] = chip
            chipX += w + 4
        }
        chipDoc.frame.size.width = max(windowWidth, chipX + 6)

        // Custom prompt field (shown for Custom action; hidden otherwise)
        let promptBarH: CGFloat = 30
        let promptBarY = chipBarY - promptBarH
        let promptField = NSTextField(frame: NSRect(x: 12, y: promptBarY + 4, width: windowWidth - 24, height: 22))
        promptField.placeholderString = "Your prompt — e.g. Turn this into a tweet"
        promptField.font = NSFont.systemFont(ofSize: 12)
        promptField.stringValue = aiCustomPrompt
        promptField.isEditable = true
        promptField.isBordered = true
        promptField.bezelStyle = .roundedBezel
        promptField.focusRingType = .none
        promptField.target = self
        promptField.action = #selector(aiCustomPromptSubmitted(_:))
        promptField.isHidden = (action != .custom)
        overlay.addSubview(promptField)
        aiPromptField = promptField

        // Bottom action bar: Save / Copy / Paste / Open Full / Re-run
        let actionBarH: CGFloat = 46
        let actionBar = NSView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: actionBarH))
        overlay.addSubview(actionBar)

        let divider = NSView(frame: NSRect(x: 12, y: actionBarH - 0.5, width: windowWidth - 24, height: 0.5))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        actionBar.addSubview(divider)

        let copyBtn = makeAIBarButton(title: "Copy", symbol: "doc.on.doc", action: #selector(aiCopyTapped))
        let pasteBtn = makeAIBarButton(title: "Paste", symbol: "arrow.down.doc", action: #selector(aiPasteTapped), accent: true)
        let saveBtn = makeAIBarButton(title: "Save", symbol: "plus.rectangle.on.folder", action: #selector(aiSaveTapped))
        let fullBtn = makeAIBarButton(title: "Full", symbol: "arrow.up.left.and.arrow.down.right", action: #selector(aiOpenFullTapped))
        let regenBtn = makeAIBarButton(title: "Re-run", symbol: "arrow.clockwise", action: #selector(aiRegenerateTapped))

        let buttonStack = NSStackView(views: [regenBtn, fullBtn, saveBtn, copyBtn, pasteBtn])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 5
        buttonStack.alignment = .centerY
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        actionBar.addSubview(buttonStack)
        NSLayoutConstraint.activate([
            buttonStack.trailingAnchor.constraint(equalTo: actionBar.trailingAnchor, constant: -8),
            buttonStack.leadingAnchor.constraint(greaterThanOrEqualTo: actionBar.leadingAnchor, constant: 8),
            buttonStack.centerYAnchor.constraint(equalTo: actionBar.centerYAnchor),
        ])

        copyBtn.isEnabled = false
        pasteBtn.isEnabled = false
        saveBtn.isEnabled = false
        regenBtn.isEnabled = false
        aiCopyButton = copyBtn
        aiPasteButton = pasteBtn
        aiSaveButton = saveBtn
        aiRegenButton = regenBtn

        // Result scroll view fills the middle (leave room for prompt bar when Custom is active)
        let promptReserve: CGFloat = (action == .custom) ? promptBarH : 0
        let resultY = actionBarH + 4
        let resultH = overlayH - topBarH - chipBarH - promptReserve - actionBarH - 8
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 12, y: resultY, width: windowWidth - 24, height: resultH)
        scroll.identifier = NSUserInterfaceItemIdentifier("aiResultScroll")
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 8
        scroll.layer?.cornerCurve = .continuous
        if let tv = scroll.documentView as? NSTextView {
            tv.font = NSFont.systemFont(ofSize: 13)
            tv.isEditable = false
            tv.isRichText = false
            tv.textColor = .white
            tv.drawsBackground = false
            tv.textContainerInset = NSSize(width: 6, height: 6)
            aiResultTextView = tv
        }
        overlay.addSubview(scroll)

        // Subtle entrance animation
        overlay.alphaValue = 0
        overlay.layer?.transform = CATransform3DMakeTranslation(0, 6, 0)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            overlay.animator().alphaValue = 1
        }
        let slide = CABasicAnimation(keyPath: "transform")
        slide.fromValue = CATransform3DMakeTranslation(0, 6, 0)
        slide.toValue = CATransform3DIdentity
        slide.duration = 0.18
        slide.timingFunction = CAMediaTimingFunction(name: .easeOut)
        overlay.layer?.add(slide, forKey: "slidein")
        overlay.layer?.transform = CATransform3DIdentity

        startAIStream(text: text, action: action, customPrompt: customPrompt)
    }

    private func makeAIBarButton(title: String, symbol: String, action: Selector, accent: Bool = false) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.bezelStyle = .rounded
        btn.controlSize = .small
        btn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .medium))
        btn.imagePosition = .imageLeading
        btn.imageScaling = .scaleProportionallyDown
        if accent { btn.bezelColor = NSColor.controlAccentColor }
        return btn
    }

    private func startAIStream(text: String, action: AIAction, customPrompt: String? = nil) {
        aiTask?.cancel()
        aiTask = nil

        let runToken = UUID()
        aiRunToken = runToken
        aiCurrentAction = action
        if let customPrompt {
            aiCustomPrompt = customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        aiTitleLabel?.stringValue = action == .custom ? "Custom Prompt" : action.title
        aiPromptField?.isHidden = (action != .custom)
        if action == .custom {
            aiPromptField?.stringValue = aiCustomPrompt
        }
        for (a, btn) in aiActionButtons {
            btn.state = (a == action) ? .on : .off
        }
        layoutAIResultArea(for: action)

        aiResultText = ""
        aiResultTextView?.string = "…"
        aiSpinner?.startAnimation(nil)
        aiCopyButton?.isEnabled = false
        aiPasteButton?.isEnabled = false
        aiSaveButton?.isEnabled = false
        aiRegenButton?.isEnabled = false

        let availability = AppleIntelligenceProvider.shared.currentAvailability()
        guard availability.isUsable else {
            aiSpinner?.stopAnimation(nil)
            aiResultTextView?.string = "⚠️  \(availability.headline)\n\n\(availability.hint)"
            aiRegenButton?.isEnabled = true
            return
        }

        if action == .custom, aiCustomPrompt.isEmpty {
            aiSpinner?.stopAnimation(nil)
            aiResultTextView?.string = "✏️ Type your prompt above and press Return (or Re-run)."
            aiRegenButton?.isEnabled = true
            makeFirstResponder(aiPromptField)
            return
        }

        let runAction = action
        let runText = text
        let runCustom = (action == .custom) ? aiCustomPrompt : nil

        aiTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let stream = AppleIntelligenceProvider.shared.stream(
                    runAction,
                    on: runText,
                    customPrompt: runCustom
                )
                for try await update in stream {
                    if Task.isCancelled { return }
                    await MainActor.run {
                        guard self.aiRunToken == runToken else { return }
                        self.aiResultText = update.text
                        self.aiResultTextView?.string = update.text
                        if update.isFinal {
                            self.aiResultTextView?.scrollToEndOfDocument(nil)
                        }
                    }
                }
            } catch {
                if Task.isCancelled { return }
                if let aiErr = error as? AIError, case .cancelled = aiErr { return }
                let message = (error as? AIError)?.errorDescription ?? error.localizedDescription
                await MainActor.run {
                    guard self.aiRunToken == runToken else { return }
                    self.aiResultTextView?.string = "⚠️  \(message)"
                    self.aiResultText = ""
                }
            }
            await MainActor.run {
                guard self.aiRunToken == runToken else { return }
                self.aiSpinner?.stopAnimation(nil)
                let hasText = !self.aiResultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && self.aiResultText != "…"
                self.aiCopyButton?.isEnabled = hasText
                self.aiPasteButton?.isEnabled = hasText
                self.aiSaveButton?.isEnabled = hasText
                self.aiRegenButton?.isEnabled = true
            }
        }
    }

    /// Shrink / grow the result scroll view when the custom prompt field appears.
    private func layoutAIResultArea(for action: AIAction) {
        guard let overlay = aiOverlay,
              let scroll = overlay.subviews.first(where: { $0.identifier?.rawValue == "aiResultScroll" })
        else { return }
        let topBarH: CGFloat = 38
        let chipBarH: CGFloat = 34
        let promptBarH: CGFloat = 30
        let actionBarH: CGFloat = 46
        let overlayH = overlay.bounds.height
        let promptReserve: CGFloat = (action == .custom) ? promptBarH : 0
        let resultY = actionBarH + 4
        let resultH = overlayH - topBarH - chipBarH - promptReserve - actionBarH - 8
        scroll.frame = NSRect(x: 12, y: resultY, width: windowWidth - 24, height: max(60, resultH))
        if let prompt = aiPromptField {
            prompt.frame.origin.y = overlayH - topBarH - chipBarH - promptBarH + 4
        }
    }

    @objc private func closeAIInline() {
        aiRunToken = UUID()
        aiTask?.cancel()
        aiTask = nil
        guard let overlay = aiOverlay else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            overlay.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.aiOverlay?.removeFromSuperview()
            self?.aiOverlay = nil
            self?.aiResultTextView = nil
            self?.aiSpinner = nil
            self?.aiCopyButton = nil
            self?.aiPasteButton = nil
            self?.aiRegenButton = nil
            self?.aiSaveButton = nil
            self?.aiTitleLabel = nil
            self?.aiPromptField = nil
            self?.aiActionButtons.removeAll()
            // Restore search-field focus so typing keeps working
            if let s = self?.searchField {
                self?.makeFirstResponder(s)
            }
        })
    }

    @objc private func aiChipTapped(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,
              let action = AIAction(rawValue: id) else { return }
        if action == .custom {
            // Ask for a prompt if we don't have one yet; otherwise reuse & re-run.
            if aiCustomPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let prompt = askForCustomPrompt() {
                    startAIStream(text: aiInputText, action: .custom, customPrompt: prompt)
                }
            } else {
                startAIStream(text: aiInputText, action: .custom, customPrompt: aiCustomPrompt)
            }
            return
        }
        guard action != aiCurrentAction || aiTask == nil else { return }
        startAIStream(text: aiInputText, action: action)
    }

    @objc private func aiCustomPromptSubmitted(_ sender: NSTextField) {
        let prompt = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            NSSound.beep()
            return
        }
        startAIStream(text: aiInputText, action: .custom, customPrompt: prompt)
    }

    @objc private func aiCopyTapped() {
        let result = aiResultText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(result, forType: .string)
        ClipboardManager.shared.acknowledgeSelfWrite()
        aiCopyButton?.title = "Copied"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.aiCopyButton?.title = "Copy"
        }
    }

    @objc private func aiPasteTapped() {
        let result = aiResultText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return }
        NSApp.hide(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            PasteManager.shared.pasteString(result)
        }
    }

    @objc private func aiSaveTapped() {
        let result = aiResultText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return }
        // Push into history without touching the system pasteboard, so we
        // don't steal whatever the user currently has copied.
        ClipboardManager.shared.addAIResult(result)
        aiSaveButton?.title = "Saved"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.aiSaveButton?.title = "Save"
            self?.refreshClipboardList()
        }
    }

    @objc private func aiOpenFullTapped() {
        let text = aiInputText
        let action = aiCurrentAction
        let custom = aiCustomPrompt
        closeAIInline()
        // Slight delay so the inline panel finishes its fade before the
        // standalone window pops up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            AIDemoWindow.show(prefillText: text, autoRun: action, customPrompt: custom)
        }
    }

    @objc private func aiRegenerateTapped() {
        if aiCurrentAction == .custom, let field = aiPromptField {
            let typed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !typed.isEmpty { aiCustomPrompt = typed }
        }
        startAIStream(text: aiInputText, action: aiCurrentAction, customPrompt: aiCustomPrompt)
    }

    private var isAIInlineVisible: Bool { aiOverlay != nil }

    @objc fileprivate func showTrayItemMenu(_ sender: NSButton) {
        let index = sender.tag
        let items = TrayManager.shared.items
        guard index < items.count else { return }
        let item = items[index]
        
        let menu = NSMenu()
        
        let copyItem = NSMenuItem(title: "Copy to Clipboard", action: #selector(menuCopyItem(_:)), keyEquivalent: "c")
        copyItem.target = self
        copyItem.representedObject = item
        menu.addItem(copyItem)
        
        let pinTitle = item.isPinned ? "Unpin" : "Pin"
        let pinItem = NSMenuItem(title: pinTitle, action: #selector(menuPinItem(_:)), keyEquivalent: "p")
        pinItem.target = self
        pinItem.representedObject = item
        menu.addItem(pinItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let deleteItem = NSMenuItem(title: "Delete", action: #selector(menuDeleteItem(_:)), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.representedObject = item
        menu.addItem(deleteItem)
        
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: sender)
    }

    @objc private func menuCopyItem(_ sender: NSMenuItem) {
        if let item = sender.representedObject as? ClipboardItem {
            PasteManager.shared.pasteItem(item)
        } else if let item = sender.representedObject as? TrayItem {
            TrayManager.shared.copyToClipboard(item)
        }
    }
    
    @objc private func menuPinItem(_ sender: NSMenuItem) {
        if let item = sender.representedObject as? ClipboardItem {
            ClipboardManager.shared.togglePin(for: item)
            if currentTab == .clipboard {
                refreshClipboardList()
                return
            }
        } else if let item = sender.representedObject as? TrayItem {
            TrayManager.shared.togglePin(for: item)
        }
        if let contentView = self.contentView { updateContent(in: contentView) }
    }
    
    @objc private func menuDeleteItem(_ sender: NSMenuItem) {
        if let item = sender.representedObject as? ClipboardItem {
            ClipboardManager.shared.deleteItem(item)
            if currentTab == .clipboard {
                refreshClipboardList()
                return
            }
        } else if let item = sender.representedObject as? TrayItem {
            TrayManager.shared.removeItem(item)
        }
        if let contentView = self.contentView { updateContent(in: contentView) }
    }
}

// MARK: - Shared UI factories

extension ClipboardWindow {
    
    fileprivate func makeScrollView(y: CGFloat, height: CGFloat) -> NSScrollView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: y, width: windowWidth, height: height))
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.automaticallyAdjustsContentInsets = false
        let clipView = NSClipView()
        clipView.drawsBackground = false
        scrollView.contentView = clipView
        return scrollView
    }
    
    fileprivate func makeEmptyState(iconName: String, title: String, subtitle: String) -> NSView {
        let containerWidth: CGFloat = 260
        let containerHeight: CGFloat = 120
        let container = NSView(frame: NSRect(
            x: (windowWidth - containerWidth) / 2,
            y: (contentRegionHeight - containerHeight) / 2 + footerHeight,
            width: containerWidth,
            height: containerHeight
        ))
        
        let tileSize: CGFloat = 48
        let tile = NSView(frame: NSRect(x: (containerWidth - tileSize) / 2, y: containerHeight - tileSize, width: tileSize, height: tileSize))
        tile.wantsLayer = true
        tile.layer?.cornerRadius = 14
        tile.layer?.cornerCurve = .continuous
        tile.layer?.backgroundColor = LiquidGlass.emptyTileFill.cgColor
        tile.layer?.borderWidth = LiquidGlass.hairline
        tile.layer?.borderColor = LiquidGlass.wellStroke.cgColor
        container.addSubview(tile)
        
        let icon = NSImageView(frame: tile.bounds)
        let cfg = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        icon.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?.withSymbolConfiguration(cfg)
        icon.contentTintColor = LiquidGlass.secondaryText
        icon.imageAlignment = .alignCenter
        tile.addSubview(icon)
        
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = LiquidGlass.primaryText
        titleLabel.alignment = .center
        titleLabel.frame = NSRect(x: 0, y: containerHeight - tileSize - 26, width: containerWidth, height: 18)
        container.addSubview(titleLabel)
        
        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = NSFont.systemFont(ofSize: 11.5)
        subtitleLabel.textColor = LiquidGlass.secondaryText
        subtitleLabel.alignment = .center
        subtitleLabel.frame = NSRect(x: 0, y: containerHeight - tileSize - 44, width: containerWidth, height: 16)
        container.addSubview(subtitleLabel)
        
        return container
    }
    
    fileprivate func makeFooter(text: String) -> NSView {
        let footer = NSView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: footerHeight))
        footer.wantsLayer = true
        
        let divider = CALayer()
        divider.frame = CGRect(x: 16, y: footerHeight - 1, width: windowWidth - 32, height: LiquidGlass.hairline)
        divider.backgroundColor = LiquidGlass.separator.cgColor
        footer.layer?.addSublayer(divider)
        
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        label.textColor = LiquidGlass.tertiaryText
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 7, width: windowWidth, height: 16)
        footer.addSubview(label)
        
        return footer
    }
}

// MARK: - DropZoneNSView

class DropZoneNSView: NSView {
    var onFilesDropped: (([URL]) -> Void)?
    private var isDragging = false
    private var dropOverlay: NSView?
    private var dropLabel: NSTextField?
    
    /// Color used for the drop highlight. Defaults to the user's macOS accent color
    /// so it adapts to whatever they've set in System Settings.
    static var accent: NSColor { NSColor.controlAccentColor }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
        registerForDraggedTypes([.fileURL])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        updateAppearance(animated: false)
    }
    
    private func updateAppearance(animated: Bool) {
        let bg: CGColor = isDragging
            ? Self.accent.withAlphaComponent(0.14).cgColor
            : NSColor.clear.cgColor
        let border: CGColor = isDragging
            ? Self.accent.withAlphaComponent(0.55).cgColor
            : NSColor.clear.cgColor
        let borderWidth: CGFloat = isDragging ? 1.5 : 0
        
        if animated, let layer = layer {
            let bgAnim = CABasicAnimation(keyPath: "backgroundColor")
            bgAnim.fromValue = layer.backgroundColor
            bgAnim.toValue = bg
            bgAnim.duration = 0.18
            layer.add(bgAnim, forKey: "bg")
            
            let borderAnim = CABasicAnimation(keyPath: "borderColor")
            borderAnim.fromValue = layer.borderColor
            borderAnim.toValue = border
            borderAnim.duration = 0.18
            layer.add(borderAnim, forKey: "border")
        }
        
        layer?.backgroundColor = bg
        layer?.borderColor = border
        layer?.borderWidth = borderWidth
        
        // Hide other content (empty state, list rows) while dragging so nothing overlaps
        for sub in subviews where sub !== dropOverlay {
            sub.alphaValue = isDragging ? 0 : 1
        }
        
        // Show / hide the drop indicator
        if isDragging {
            showDropOverlay()
        } else {
            hideDropOverlay()
        }
    }
    
    private func showDropOverlay() {
        if dropOverlay != nil { return }
        
        let overlay = NSView(frame: bounds)
        overlay.wantsLayer = true
        overlay.autoresizingMask = [.width, .height]
        addSubview(overlay)
        dropOverlay = overlay
        
        // Centered icon + label, both tinted with the accent color
        let iconSize: CGFloat = 38
        let icon = NSImageView(frame: NSRect(
            x: (bounds.width - iconSize) / 2,
            y: bounds.height / 2 - 6,
            width: iconSize,
            height: iconSize
        ))
        let cfg = NSImage.SymbolConfiguration(pointSize: 28, weight: .regular)
        icon.image = NSImage(systemSymbolName: "tray.and.arrow.down.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
        icon.contentTintColor = Self.accent
        icon.imageAlignment = .alignCenter
        overlay.addSubview(icon)
        
        let label = NSTextField(labelWithString: "Drop to add to Tray")
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = Self.accent
        label.alignment = .center
        label.frame = NSRect(
            x: 0,
            y: bounds.height / 2 - 36,
            width: bounds.width,
            height: 18
        )
        overlay.addSubview(label)
        dropLabel = label
        
        // Fade in
        overlay.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            overlay.animator().alphaValue = 1
        }
    }
    
    private func hideDropOverlay() {
        guard let overlay = dropOverlay else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            overlay.animator().alphaValue = 0
        }, completionHandler: {
            overlay.removeFromSuperview()
        })
        dropOverlay = nil
        dropLabel = nil
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDragging = true
        updateAppearance(animated: true)
        return .copy
    }
    
    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDragging = false
        updateAppearance(animated: true)
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDragging = false
        updateAppearance(animated: true)
        let pasteboard = sender.draggingPasteboard
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
        return false
        }
        onFilesDropped?(urls)
        return true
    }
}

// MARK: - NSClickableView (flat-row hover + keyboard highlight)

class NSClickableView: NSView {
    var onClick: (() -> Void)?
    private var isHighlighted: Bool = false
    private var isHovering: Bool = false
    
    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
    
    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        applyState(animated: true)
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovering = false
        applyState(animated: true)
    }
    
    /// Set by the parent window when the row is selected via keyboard navigation.
    func setHighlighted(_ highlighted: Bool) {
        isHighlighted = highlighted
        applyState(animated: true)
    }
    
    private func applyState(animated: Bool) {
        let target: NSColor
        if isHighlighted {
            target = isHovering ? LiquidGlass.rowHighlightHover : LiquidGlass.rowHighlight
        } else {
            target = isHovering ? LiquidGlass.rowHover : .clear
        }
        if animated {
            animateBackground(to: target)
        } else {
            layer?.backgroundColor = target.cgColor
        }
    }
    
    private func animateBackground(to color: NSColor) {
        guard let layer = layer else { return }
        let anim = CABasicAnimation(keyPath: "backgroundColor")
        anim.fromValue = layer.backgroundColor
        anim.toValue = color.cgColor
        anim.duration = 0.12
        layer.add(anim, forKey: "bg")
        layer.backgroundColor = color.cgColor
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        addTrackingArea(NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil))
    }
}

// MARK: - DraggableTrayItemView (flat row + drag-to-export)

class DraggableTrayItemView: NSView, NSDraggingSource {
    var trayItem: TrayItem?
    var onClick: (() -> Void)?
    private var dragStartLocation: NSPoint?
    
    override var mouseDownCanMoveWindow: Bool { false }
    
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }
    
    override func mouseDown(with event: NSEvent) {
        dragStartLocation = event.locationInWindow
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let item = trayItem, let start = dragStartLocation else { return }
        let current = event.locationInWindow
        let dragThreshold: CGFloat = 5.0
        let dx = abs(current.x - start.x), dy = abs(current.y - start.y)
        if dx > dragThreshold || dy > dragThreshold {
            startDragOperation(with: item, event: event)
            dragStartLocation = nil
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        if dragStartLocation != nil {
            onClick?()
        }
        dragStartLocation = nil
    }
    
    private func startDragOperation(with item: TrayItem, event: NSEvent) {
        if item.type == .file, let fileURL = item.getFileURL() {
            let draggingItem = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
            let dragImage = NSWorkspace.shared.icon(forFile: fileURL.path)
            dragImage.size = NSSize(width: 60, height: 60)
            draggingItem.setDraggingFrame(NSRect(x: 0, y: 0, width: 60, height: 60), contents: dragImage)
            beginDraggingSession(with: [draggingItem], event: event, source: self)
            return
        }

        let tempDir = FileManager.default.temporaryDirectory
        let fileName: String
        let fileURL: URL
        
        if item.isImage {
            fileName = "\(item.name.replacingOccurrences(of: " ", with: "_")).png"
            fileURL = tempDir.appendingPathComponent(fileName)
            if let image = item.nsImage(), let tiffData = image.tiffRepresentation {
                let bitmap = NSBitmapImageRep(data: tiffData)
                let pngData = bitmap?.representation(using: .png, properties: [:])
                try? pngData?.write(to: fileURL)
            }
        } else if let text = item.text() {
            fileName = "\(item.name.replacingOccurrences(of: " ", with: "_")).txt"
            fileURL = tempDir.appendingPathComponent(fileName)
            try? text.write(to: fileURL, atomically: true, encoding: .utf8)
        } else {
            return
        }
        
        let draggingItem = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
        let dragImage: NSImage
        if item.isImage, let img = item.nsImage() {
            dragImage = img.resized(to: CGSize(width: 60, height: 60))
        } else {
            dragImage = NSWorkspace.shared.icon(forFile: fileURL.path)
            dragImage.size = NSSize(width: 60, height: 60)
        }
        draggingItem.setDraggingFrame(NSRect(x: 0, y: 0, width: 60, height: 60), contents: dragImage)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }
    
    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = LiquidGlass.rowHover.cgColor
    }
    
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        addTrackingArea(NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil))
    }
}

// MARK: - FlippedView

class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Hover-aware controls

/// Tab pill button: only handles selected/hover tint of its symbol – the sliding pill indicator lives one layer down.
class HoverButton: NSButton {
    private var isSelectedState: Bool = false
    private var isHovering: Bool = false
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        addTrackingArea(NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil))
    }
    
    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        applyTint(animated: true)
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovering = false
        applyTint(animated: true)
    }
    
    func setIsSelected(_ selected: Bool, animated: Bool) {
        isSelectedState = selected
        applyTint(animated: animated)
    }
    
    private func applyTint(animated: Bool) {
        let tint: NSColor
        if isSelectedState {
            tint = LiquidGlass.primaryText
        } else if isHovering {
            tint = LiquidGlass.secondaryText
        } else {
            tint = LiquidGlass.tertiaryText
        }
        contentTintColor = tint
    }
}

/// Compact circular hover button used for header actions and row menus.
class HoverIconButton: NSButton {
    var symbolName: String = "circle"
    var symbolPointSize: CGFloat = 13
    var symbolWeight: NSFont.Weight = .regular
    var normalTint: NSColor = LiquidGlass.iconMuted
    var hoverTint: NSColor = LiquidGlass.iconPrimary
    var hoverBackground: NSColor = LiquidGlass.rowHover
    
    private var isHovering: Bool = false
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        title = ""
        bezelStyle = .inline
        isBordered = false
        wantsLayer = true
        imageScaling = .scaleProportionallyDown
        layer?.cornerRadius = bounds.height / 2
        layer?.cornerCurve = .continuous
        refreshAppearance()
    }
    
    func applySymbol() {
        let cfg = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: symbolWeight)
        self.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(cfg)
    }
    
    func refreshAppearance() {
        layer?.cornerRadius = bounds.height / 2
        layer?.backgroundColor = (isHovering ? hoverBackground : NSColor.clear).cgColor
        contentTintColor = isHovering ? hoverTint : normalTint
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        addTrackingArea(NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil))
    }
    
    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        animate()
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovering = false
        animate()
    }
    
    private func animate() {
        guard let layer = layer else { return }
        let target = (isHovering ? hoverBackground : NSColor.clear).cgColor
        let anim = CABasicAnimation(keyPath: "backgroundColor")
        anim.fromValue = layer.backgroundColor
        anim.toValue = target
        anim.duration = 0.14
        layer.add(anim, forKey: "bg")
        layer.backgroundColor = target
        contentTintColor = isHovering ? hoverTint : normalTint
    }
}

/// Emoji grid cell with a soft hover background.
class HoverEmojiButton: NSButton {
    private var isHovering: Bool = false
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        addTrackingArea(NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil))
    }
    
    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        layer?.backgroundColor = LiquidGlass.rowHover.cgColor
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovering = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

// MARK: - AI Invocation

/// Bundle of (input text, AI action [, custom prompt]) carried via NSMenuItem.representedObject.
fileprivate final class AIInvocation: NSObject {
    let text: String
    let action: AIAction
    let customPrompt: String?
    init(text: String, action: AIAction, customPrompt: String? = nil) {
        self.text = text
        self.action = action
        self.customPrompt = customPrompt
    }
}
