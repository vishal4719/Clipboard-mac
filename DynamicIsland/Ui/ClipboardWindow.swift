import AppKit

class ClipboardWindow: NSPanel {
    
    private var clickMonitor: Any?
    private var currentTab: Tab = .clipboard
    private var tabButtons: [Tab: NSButton] = [:]
    
    enum Tab {
        case clipboard
        case tray
        case emoji
    }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 550),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        setupWindow()
        setupContent()
        setupClickMonitor()
        registerForDraggedTypes([.fileURL])
    }
    
    
    private func setupWindow() {
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.isFloatingPanel = true
        self.becomesKeyOnlyIfNeeded = false
        // self.hasShadow = true // VisualEffectView handles shadow better usually, or we keep it
        self.styleMask.insert(.fullSizeContentView) 
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isMovableByWindowBackground = true
    }
    
    private func setupContent() {
        // Glassmorphism Effect
        let visualEffectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 400, height: 550))
        visualEffectView.material = .hudWindow // Dark, heavily blurred, like Control Center
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 16
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.layer?.borderWidth = 1
        visualEffectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        
        self.contentView = visualEffectView
        
        // Create tab bar
        createTabBar(in: visualEffectView)
        
        // Create content area
        updateContent(in: visualEffectView)
    }
    
    private func createTabBar(in container: NSView) {
        // Tab container
        let tabBar = NSView(frame: NSRect(x: 0, y: 510, width: 400, height: 40))
        tabBar.wantsLayer = true
        container.addSubview(tabBar)
        
        // App Icon / Logo
        let logoImageView = NSImageView(frame: NSRect(x: 15, y: 8, width: 24, height: 24))
        logoImageView.image = NSImage(named: "AppIcon") ?? NSImage(systemSymbolName: "doc.on.clipboard.fill", accessibilityDescription: "Logo")
        logoImageView.imageScaling = .scaleProportionallyUpOrDown
        tabBar.addSubview(logoImageView)
        
        // App Title
        let titleLabel = NSTextField(labelWithString: "VClipboard")
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.frame = NSRect(x: 45, y: 10, width: 100, height: 20)
        tabBar.addSubview(titleLabel)
        
        // Clipboard tab button (Icon) - Shifted Right
        let clipboardButton = createTabButton(
            iconName: "list.bullet.clipboard",
            tab: .clipboard,
            x: 160,
            isSelected: currentTab == .clipboard
        )
        tabBar.addSubview(clipboardButton)
        tabButtons[.clipboard] = clipboardButton
        
        // Tray tab button (Icon) - Shifted Right
        let trayButton = createTabButton(
            iconName: "tray.full", // or "archivebox"
            tab: .tray,
            x: 210, 
            isSelected: currentTab == .tray
        )
        tabBar.addSubview(trayButton)
        tabButtons[.tray] = trayButton
        
        // Emoji tab button (Icon) - Shifted Right
        let emojiButton = createTabButton(
            iconName: "face.smiling",
            tab: .emoji,
            x: 260, 
            isSelected: currentTab == .emoji
        )
        tabBar.addSubview(emojiButton)
        tabButtons[.emoji] = emojiButton
        

        
        // Clear All Button (Right aligned)
        let clearButton = NSButton(frame: NSRect(x: 350, y: 5, width: 40, height: 30))
        clearButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Clear All")
        clearButton.bezelStyle = .rounded
        clearButton.isBordered = false
        clearButton.wantsLayer = true
        clearButton.contentTintColor = .systemRed // Specific Red tint for danger action
        clearButton.target = self
        clearButton.action = #selector(clearAllClicked)
        tabBar.addSubview(clearButton)
    }
    
    @objc private func clearAllClicked() {
        if currentTab == .clipboard {
            ClipboardManager.shared.clearAll()
        } else if currentTab == .tray {
            TrayManager.shared.clearAll()
        }
        // Emoji tab has no clear all
        
        // Refresh
        if let contentView = self.contentView {
            updateContent(in: contentView)
        }
    }
    
    
    private func createTabButton(iconName: String, tab: Tab, x: CGFloat, isSelected: Bool) -> NSButton {
        let button = NSButton(frame: NSRect(x: x, y: 5, width: 40, height: 30))
        button.title = "" // No text
        button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
        button.bezelStyle = .rounded
        button.isBordered = false // Cleaner look without border maybe? Or keep border for selection?
        // Let's keep a subtle background for selection
        button.wantsLayer = true
        button.layer?.backgroundColor = isSelected ? NSColor.white.withAlphaComponent(0.2).cgColor : NSColor.clear.cgColor
        button.layer?.cornerRadius = 6
        
        button.contentTintColor = isSelected ? .white : .gray
        button.target = self
        button.action = #selector(tabButtonClicked(_:))
        
        if tab == .clipboard {
            button.tag = 0
        } else if tab == .tray {
            button.tag = 1
        } else {
            button.tag = 2
        }
        
        return button
    }
    
    @objc private func tabButtonClicked(_ sender: NSButton) {
        var newTab: Tab = .clipboard
        if sender.tag == 0 { newTab = .clipboard }
        else if sender.tag == 1 { newTab = .tray }
        else if sender.tag == 2 { newTab = .emoji }
        
        switchToTab(newTab)
    }
    
    func switchToTab(_ tab: Tab) {
        currentTab = tab
        
        // Update button states
        for (tabType, button) in tabButtons {
            let isSelected = tabType == tab
            // button.font = NSFont.systemFont(ofSize: 13, weight: isSelected ? .semibold : .regular) // Removed
            button.contentTintColor = isSelected ? .white : .gray
            button.layer?.backgroundColor = isSelected ? NSColor.white.withAlphaComponent(0.2).cgColor : NSColor.clear.cgColor
        }
        
        // Refresh content
        if let contentView = self.contentView {
            updateContent(in: contentView)
        }
    }
    
    private func updateContent(in container: NSView) {
        // Remove old content (keep tab bar)
        container.subviews.forEach { view in
            if view.frame.origin.y < 510 {
                view.removeFromSuperview()
            }
        }
        
        switch currentTab {
        case .clipboard:
            showClipboardContent(in: container)
        case .clipboard:
            showClipboardContent(in: container)
        case .tray:
           showTrayContent(in: container)
        case .emoji:
           showEmojiContent(in: container)
        }
    }
    
    private func showClipboardContent(in container: NSView) {
        let items = ClipboardManager.shared.items
        
        if items.isEmpty {
            let emptyLabel = NSTextField(labelWithString: "No clipboard history\n\nCopy something to get started")
            emptyLabel.font = NSFont.systemFont(ofSize: 14)
            emptyLabel.textColor = .gray
            emptyLabel.alignment = .center
            emptyLabel.frame = NSRect(x: 50, y: 220, width: 300, height: 60)
            container.addSubview(emptyLabel)
        } else {
            // Show up to 12 items
            var yPosition: CGFloat = 430 // Matched to Tray padding (was 455)
            let itemHeight: CGFloat = 35
            
            for (index, item) in items.prefix(12).enumerated() {
                let itemView = createClipboardItemView(item: item, index: index, yPosition: yPosition)
                itemView.frame.size.height = itemHeight
                container.addSubview(itemView)
                yPosition -= (itemHeight + 5)
            }
        }
        
        // Instructions
        let instructionLabel = NSTextField(labelWithString: "Click item to copy • Click outside to close")
        instructionLabel.font = NSFont.systemFont(ofSize: 11)
        instructionLabel.textColor = .gray
        instructionLabel.alignment = .center
        instructionLabel.frame = NSRect(x: 0, y: 10, width: 400, height: 20)
        container.addSubview(instructionLabel)
    }
    
    private func showTrayContent(in container: NSView) {
        let items = TrayManager.shared.items
        
        // Make the ENTIRE tray area a drop zone
        let fullDropZone = DropZoneNSView(frame: NSRect(x: 0, y: 30, width: 400, height: 480))
        fullDropZone.onFilesDropped = { [weak self] urls in
            for url in urls {
                TrayManager.shared.addFile(url)
            }
            // Refresh view
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard let self = self, let contentView = self.contentView else { return }
                self.updateContent(in: contentView)
            }
        }
        container.addSubview(fullDropZone)
        
        // Add items on top of drop zone
        if items.isEmpty {
            let emptyLabel = NSTextField(labelWithString: "Drop files anywhere here to store them")
            emptyLabel.font = NSFont.systemFont(ofSize: 14)
            emptyLabel.textColor = .gray
            emptyLabel.alignment = .center
            emptyLabel.frame = NSRect(x: 50, y: 220, width: 300, height: 40)
            fullDropZone.addSubview(emptyLabel)
        } else {
            // Show up to 12 items
            var yPosition: CGFloat = 430
            let itemHeight: CGFloat = 35
            
            for (index, item) in items.prefix(12).enumerated() {
                let itemView = createTrayItemView(item: item, index: index, yPosition: yPosition)
                itemView.frame.size.height = itemHeight
                itemView.frame.origin.x = 10
                itemView.frame.origin.y = yPosition - 30 // Adjust for drop zone offset
                fullDropZone.addSubview(itemView)
                yPosition -= (itemHeight + 5) // Was 3, now 5 for consistency
            }
        }
        
        // Instructions
        let instructionLabel = NSTextField(labelWithString: "Click item to copy • Drop files anywhere")
        instructionLabel.font = NSFont.systemFont(ofSize: 11)
        instructionLabel.textColor = .gray
        instructionLabel.alignment = .center
        instructionLabel.frame = NSRect(x: 0, y: 10, width: 400, height: 20)
        container.addSubview(instructionLabel)
    }

    private func showEmojiContent(in container: NSView) {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 40, width: 400, height: 460))
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.automaticallyAdjustsContentInsets = false
        
        let clipView = NSClipView()
        clipView.drawsBackground = false
        scrollView.contentView = clipView
        
        let documentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 0)) // Height will be adjusted
        
        var yPosition: CGFloat = 0
        let categories = EmojiManager.shared.categories
        
        // Iterate backwards because y=0 is bottom in macOS (but for document view we usually build top down and flip, or build bottom up)
        // Let's use isFlipped for easier top-down layout if possible, or just build standard.
        // Standard NSView: (0,0) is bottom-left.
        // So we need to calculate total height first or build from top?
        // Simpler: Use a flipped view for document view.
        
        let flippedDocView = FlippedView(frame: NSRect(x: 0, y: 0, width: 400, height: 1000)) // Initial height
        
        var currentY: CGFloat = 10
        
        for category in categories {
            // Category Header
            let header = NSTextField(labelWithString: category.name)
            header.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
            header.textColor = .white.withAlphaComponent(0.8)
            header.frame = NSRect(x: 20, y: currentY, width: 360, height: 20)
            flippedDocView.addSubview(header)
            
            currentY += 30
            
            // Emojis Grid
            let itemSize: CGFloat = 35
            let spacing: CGFloat = 10
            let columns = 8
            let startX: CGFloat = 20
            
            var col = 0
            var rowStart = currentY
            
            for emoji in category.emojis {
                let btn = NSButton(frame: NSRect(x: startX + CGFloat(col) * (itemSize + spacing), y: currentY, width: itemSize, height: itemSize))
                btn.title = emoji
                btn.font = NSFont.systemFont(ofSize: 24)
                btn.bezelStyle = .shadowlessSquare
                btn.isBordered = false
                btn.wantsLayer = true
                btn.layer?.backgroundColor = NSColor.clear.cgColor
                btn.contentTintColor = .white // Text color, though emoji has its own colors usually
                
                // Remove default button styling issues
                // Using a closure/wrapper to capture emoji
                class EmojiButton: NSButton {
                    var emojiValue: String = ""
                }
                
                let emojiBtn = EmojiButton(frame: NSRect(x: startX + CGFloat(col) * (itemSize + spacing), y: currentY, width: itemSize, height: itemSize))
                emojiBtn.title = emoji
                emojiBtn.emojiValue = emoji
                emojiBtn.font = NSFont.systemFont(ofSize: 22)
                emojiBtn.bezelStyle = .inline
                emojiBtn.isBordered = false
                emojiBtn.wantsLayer = true
                emojiBtn.target = self
                emojiBtn.action = #selector(emojiClicked(_:))
                
                flippedDocView.addSubview(emojiBtn)
                
                col += 1
                if col >= columns {
                    col = 0
                    currentY += itemSize + spacing
                }
            }
            
            if col != 0 {
                currentY += itemSize + spacing
            }
            
            currentY += 10 // Padding between categories
        }
        
        flippedDocView.frame.size.height = currentY
        scrollView.documentView = flippedDocView
        
        // Scroll to top
        flippedDocView.scroll(NSPoint(x: 0, y: 0))
        
        container.addSubview(scrollView)
    }

    @objc private func emojiClicked(_ sender: NSButton) {
        guard let title = sender.title as String? else { return }
         // Hide APPLICATION first to restore focus
        NSApp.hide(nil)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            PasteManager.shared.pasteString(title)
            // PasteManager.shared.simulateCmdV() // pasteString usually handles it? Let's check PasteManager.
        }
    }
    
    private func createDropZone() -> NSView {
        let dropZone = DropZoneNSView(frame: NSRect(x: 0, y: 0, width: 300, height: 150))
        dropZone.onFilesDropped = { [weak self] urls in
            // Add all files
            for url in urls {
                TrayManager.shared.addFile(url)
            }
            
            // Refresh view after a short delay to ensure TrayManager has finished
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard let self = self, let contentView = self.contentView else { return }
                self.updateContent(in: contentView)
            }
        }
        return dropZone
    }
}

// MARK: - DropZoneNSView
class DropZoneNSView: NSView {
    var onFilesDropped: (([URL]) -> Void)?
    private var isDragging = false
    
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
        updateAppearance()
    }
    
    private func updateAppearance() {
        if isDragging {
            layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.3).cgColor
            layer?.borderColor = NSColor.systemGreen.cgColor
            layer?.borderWidth = 3
        } else {
            // Transparent background - blends with window
            layer?.backgroundColor = .clear
            layer?.borderColor = nil
            layer?.borderWidth = 0
        }
        layer?.cornerRadius = 8
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Only draw text when dragging
        if isDragging {
            let text = "Drop to Store!"
            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 20, weight: .bold),
                .foregroundColor: NSColor.systemGreen
            ]
            let textString = NSAttributedString(string: text, attributes: textAttributes)
            let textSize = textString.size()
            let textPoint = NSPoint(x: (bounds.width - textSize.width) / 2, y: bounds.height / 2 - 10)
            textString.draw(at: textPoint)
        }
    }
    
    // MARK: - Drag and Drop
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDragging = true
        updateAppearance()
        needsDisplay = true
        return .copy
    }
    
    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDragging = false
        updateAppearance()
        needsDisplay = true
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDragging = false
        updateAppearance()
        needsDisplay = true
        
        let pasteboard = sender.draggingPasteboard
        
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return false
        }
        
        print("📥 Dropped \(urls.count) file(s)")
        onFilesDropped?(urls)
        return true
    }
}

// MARK: - ClipboardWindow Item Views Extension
extension ClipboardWindow {
    func createClipboardItemView(item: ClipboardItem, index: Int, yPosition: CGFloat) -> NSView {
        let itemView = NSClickableView(frame: NSRect(x: 10, y: yPosition, width: 380, height: 45))
        itemView.wantsLayer = true
        itemView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        itemView.layer?.cornerRadius = 8
        
        itemView.onClick = { [weak self] in
            self?.pasteClipboardItem(item)
        }
        
        if item.isImage, let image = item.nsImage() {
            // Center image vertically in 35px height: (35-26)/2 = 4.5
            let imageView = NSImageView(frame: NSRect(x: 10, y: 4, width: 26, height: 26))
            imageView.image = image
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.wantsLayer = true
            imageView.layer?.cornerRadius = 4
            imageView.layer?.masksToBounds = true
            itemView.addSubview(imageView)
            
            let textLabel = NSTextField(labelWithString: "Screenshot")
            textLabel.font = NSFont.systemFont(ofSize: 13)
            textLabel.textColor = .white
            textLabel.lineBreakMode = .byTruncatingTail
            textLabel.frame = NSRect(x: 45, y: 8, width: 275, height: 20) // Centered y=8
            itemView.addSubview(textLabel)
        } else {
            let textLabel = NSTextField(labelWithString: item.preview)
            textLabel.font = NSFont.systemFont(ofSize: 13) // Keep size
            textLabel.textColor = .white
            textLabel.lineBreakMode = .byTruncatingTail
            textLabel.backgroundColor = .clear 
            textLabel.frame = NSRect(x: 14, y: 8, width: 316, height: 20) // Centered y=8
            itemView.addSubview(textLabel)
        }
        
        let indexLabel = NSTextField(labelWithString: "\(index + 1)")
        indexLabel.font = NSFont.systemFont(ofSize: 11)
        indexLabel.textColor = .white.withAlphaComponent(0.5)
        indexLabel.alignment = .right
        indexLabel.frame = NSRect(x: 320, y: 8, width: 25, height: 20) // Centered y=8
        itemView.addSubview(indexLabel)
        
        // Pin Icon (if pinned)
        if item.isPinned {
            let pinIcon = NSImageView(frame: NSRect(x: 300, y: 10, width: 14, height: 14)) // Centered y=10
            pinIcon.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinned")
            pinIcon.contentTintColor = .systemYellow
            itemView.addSubview(pinIcon)
        }
        
        // 3-Dot Menu Button
        let menuButton = NSButton(frame: NSRect(x: 350, y: 5, width: 25, height: 25)) // Centered y=5
        menuButton.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Menu")
        menuButton.bezelStyle = .inline
        menuButton.isBordered = false
        menuButton.wantsLayer = true
        menuButton.contentTintColor = .white
        menuButton.target = self
        menuButton.action = #selector(showItemMenu(_:))
        
        // Store item ID in a way we can retrieve it? Or just use tag for index
        menuButton.tag = index 
        itemView.addSubview(menuButton)
        
        return itemView
    }
    
    @objc private func showItemMenu(_ sender: NSButton) {
        let index = sender.tag
        let items = ClipboardManager.shared.items
        guard index < items.count else { return }
        let item = items[index]
        
        let menu = NSMenu()
        
        // Copy (Manual)
        let copyItem = NSMenuItem(title: "Copy to Clipboard", action: #selector(menuCopyItem(_:)), keyEquivalent: "c")
        copyItem.target = self
        copyItem.representedObject = item
        menu.addItem(copyItem)
        
        // Pin/Unpin
        let pinTitle = item.isPinned ? "Unpin" : "Pin"
        let pinItem = NSMenuItem(title: pinTitle, action: #selector(menuPinItem(_:)), keyEquivalent: "p")
        pinItem.target = self
        pinItem.representedObject = item
        menu.addItem(pinItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Delete
        let deleteItem = NSMenuItem(title: "Delete", action: #selector(menuDeleteItem(_:)), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.representedObject = item
        menu.addItem(deleteItem)
        
        // Show menu anchored to the button
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
        } else if let item = sender.representedObject as? TrayItem {
             TrayManager.shared.togglePin(for: item)
        }
        // Refresh
        if let contentView = self.contentView { updateContent(in: contentView) }
    }
     
    @objc private func menuDeleteItem(_ sender: NSMenuItem) {
        if let item = sender.representedObject as? ClipboardItem {
             ClipboardManager.shared.deleteItem(item)
        } else if let item = sender.representedObject as? TrayItem {
             TrayManager.shared.removeItem(item)
        }
        // Refresh
        if let contentView = self.contentView { updateContent(in: contentView) }
    }
    
    // MARK: - Tray Item Menu
    @objc private func showTrayItemMenu(_ sender: NSButton) {
        let index = sender.tag
        let items = TrayManager.shared.items
        guard index < items.count else { return }
        let item = items[index]
        
        let menu = NSMenu()
        
        // Copy
        let copyItem = NSMenuItem(title: "Copy to Clipboard", action: #selector(menuCopyItem(_:)), keyEquivalent: "c")
        copyItem.target = self
        copyItem.representedObject = item
        menu.addItem(copyItem)
        
        // Pin/Unpin
        let pinTitle = item.isPinned ? "Unpin" : "Pin"
        let pinItem = NSMenuItem(title: pinTitle, action: #selector(menuPinItem(_:)), keyEquivalent: "p")
        pinItem.target = self
        pinItem.representedObject = item
        menu.addItem(pinItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Delete
        let deleteItem = NSMenuItem(title: "Delete", action: #selector(menuDeleteItem(_:)), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.representedObject = item
        menu.addItem(deleteItem)
        
        // Show menu anchored to the button
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: sender)
    }

    private func createTrayItemView(item: TrayItem, index: Int, yPosition: CGFloat) -> NSView {
        let itemView = DraggableTrayItemView(frame: NSRect(x: 10, y: yPosition, width: 380, height: 45))
        itemView.wantsLayer = true
        itemView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        itemView.layer?.cornerRadius = 8
        itemView.trayItem = item  // Set the tray item for dragging
        
        itemView.onClick = { [weak self] in
            self?.copyTrayItem(item)
        }
        
        // Pin Icon (if pinned) - Added
        if item.isPinned {
            let pinIcon = NSImageView(frame: NSRect(x: 300, y: 10, width: 14, height: 14)) // Centered y=10
            pinIcon.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinned")
            pinIcon.contentTintColor = .systemYellow
            itemView.addSubview(pinIcon)
        }
        
        if item.isImage, let image = item.nsImage() {
            let imageView = NSImageView(frame: NSRect(x: 10, y: 4, width: 26, height: 26)) // 26x26 centered
            imageView.image = image
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.wantsLayer = true
            imageView.layer?.cornerRadius = 4
            imageView.layer?.masksToBounds = true
            itemView.addSubview(imageView)
            
            let textLabel = NSTextField(labelWithString: item.name)
            textLabel.font = NSFont.systemFont(ofSize: 13)
            textLabel.textColor = .white
            textLabel.lineBreakMode = .byTruncatingTail
            textLabel.frame = NSRect(x: 55, y: 8, width: 240, height: 20) // Centered y=8
            itemView.addSubview(textLabel)
        } else if item.type == .file {
            // File Icon
            let imageView = NSImageView(frame: NSRect(x: 10, y: 4, width: 26, height: 26)) // 26x26 centered
            if let fileURL = item.getFileURL() {
                imageView.image = NSWorkspace.shared.icon(forFile: fileURL.path)
            } else {
                imageView.image = NSImage(systemSymbolName: "doc.fill", accessibilityDescription: nil)
            }
            itemView.addSubview(imageView)
            
            let textLabel = NSTextField(labelWithString: item.name)
            textLabel.font = NSFont.systemFont(ofSize: 13)
            textLabel.textColor = .white
            textLabel.lineBreakMode = .byTruncatingTail
            textLabel.frame = NSRect(x: 55, y: 8, width: 240, height: 20) // Centered y=8
            itemView.addSubview(textLabel)
        } else {
            // Text/Other Item - Add Default Icon
            let imageView = NSImageView(frame: NSRect(x: 10, y: 4, width: 26, height: 26))
            imageView.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
            imageView.wantsLayer = true
            itemView.addSubview(imageView)

            let textLabel = NSTextField(labelWithString: item.name)
            textLabel.font = NSFont.systemFont(ofSize: 13)
            textLabel.textColor = .white
            textLabel.lineBreakMode = .byTruncatingTail
            textLabel.frame = NSRect(x: 55, y: 8, width: 240, height: 20) // Centered y=8
            itemView.addSubview(textLabel)
        }
        
        // 3-Dot Menu Button - Added
        let menuButton = NSButton(frame: NSRect(x: 350, y: 5, width: 25, height: 25)) // Centered y=5
        menuButton.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Menu")
        menuButton.bezelStyle = .inline
        menuButton.isBordered = false
        menuButton.wantsLayer = true
        menuButton.contentTintColor = .white
        menuButton.target = self
        menuButton.action = #selector(showTrayItemMenu(_:))
        menuButton.tag = index
        itemView.addSubview(menuButton)
        
        return itemView
    }
    

    
    private func pasteClipboardItem(_ item: ClipboardItem) {
        // Hide APPLICATION first to restore focus
        NSApp.hide(nil)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            PasteManager.shared.pasteItem(item)
            PasteManager.shared.simulateCmdV()
        }
    }
    
    private func copyTrayItem(_ item: TrayItem) {
        // Hide APPLICATION first to restore focus
        NSApp.hide(nil)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            TrayManager.shared.copyToClipboard(item)
            PasteManager.shared.simulateCmdV()
        }
    }
    
    // MARK: - Drag and Drop
    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        // Switch to Tray tab when drag detected
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
        
        // Refresh tray view
        if let contentView = self.contentView {
            updateContent(in: contentView)
        }
        
        return true
    }
    
    // MARK: - Click Monitor
    private func setupClickMonitor() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self else { return }
            
            let clickLocation = NSEvent.mouseLocation
            let windowFrame = self.frame
            
            if !NSPointInRect(clickLocation, windowFrame) {
                self.close()
            }
        }
        
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC key
                self?.close()
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
        super.close()
    }
    
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return false
    }
}

// MARK: - NSClickableView
class NSClickableView: NSView {
    var onClick: (() -> Void)?
    
    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
    
    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
    }
    
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        trackingAreas.forEach { removeTrackingArea($0) }
        
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }
}

// MARK: - DraggableTrayItemView
class DraggableTrayItemView: NSView, NSDraggingSource {
    var trayItem: TrayItem?
    var onClick: (() -> Void)?
    private var dragStartLocation: NSPoint?
    
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return context == .outsideApplication ? .copy : .copy
    }
    
    override func mouseDown(with event: NSEvent) {
        dragStartLocation = event.locationInWindow
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let item = trayItem, let startLocation = dragStartLocation else { return }
        
        let currentLocation = event.locationInWindow
        let dragThreshold: CGFloat = 5.0
        
        // Check if dragged enough to start drag
        let dx = abs(currentLocation.x - startLocation.x)
        let dy = abs(currentLocation.y - startLocation.y)
        
        if dx > dragThreshold || dy > dragThreshold {
            startDragOperation(with: item, event: event)
            dragStartLocation = nil
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        // If mouse up without significant drag, it's a click
        if dragStartLocation != nil {
            onClick?()
        }
        dragStartLocation = nil
    }
    
    private func startDragOperation(with item: TrayItem, event: NSEvent) {
        // Handle .file type (direct file drag)
        if item.type == .file, let fileURL = item.getFileURL() {
            let draggingItem = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
            
            let dragImage = NSWorkspace.shared.icon(forFile: fileURL.path)
            dragImage.size = NSSize(width: 60, height: 60)
            
            let dragFrame = NSRect(x: 0, y: 0, width: 60, height: 60)
            draggingItem.setDraggingFrame(dragFrame, contents: dragImage)
            
            beginDraggingSession(with: [draggingItem], event: event, source: self)
            print("🔄 Started drag for file: \(item.name)")
            return
        }

        // Create a temp file for the drag operation
        let tempDir = FileManager.default.temporaryDirectory
        let fileName: String
        let fileURL: URL
        
        if item.isImage {
            fileName = "\(item.name.replacingOccurrences(of: " ", with: "_")).png"
            fileURL = tempDir.appendingPathComponent(fileName)
            
            // Save image to temp file
            if let image = item.nsImage(), let tiffData = image.tiffRepresentation {
                let bitmap = NSBitmapImageRep(data: tiffData)
                let pngData = bitmap?.representation(using: .png, properties: [:])
                try? pngData?.write(to: fileURL)
            }
        } else if let text = item.text() {
            fileName = "\(item.name.replacingOccurrences(of: " ", with: "_")).txt"
            fileURL = tempDir.appendingPathComponent(fileName)
            
            // Save text to temp file
            try? text.write(to: fileURL, atomically: true, encoding: .utf8)
        } else {
            return
        }
        
        // Create dragging item with file URL
        let draggingItem = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
        
        // Create drag image
        let dragImage: NSImage
        if item.isImage, let img = item.nsImage() {
            dragImage = img.resized(to: CGSize(width: 60, height: 60))
        } else {
            dragImage = NSWorkspace.shared.icon(forFile: fileURL.path)
            dragImage.size = NSSize(width: 60, height: 60)
        }
        
        let dragFrame = NSRect(x: 0, y: 0, width: 60, height: 60)
        draggingItem.setDraggingFrame(dragFrame, contents: dragImage)
        
        beginDraggingSession(with: [draggingItem], event: event, source: self)
        print("🔄 Started drag for: \(fileName)")
    }
    
    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
    }
    
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        trackingAreas.forEach { removeTrackingArea($0) }
        
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }
}

// MARK: - FlippedView
class FlippedView: NSView {
    override var isFlipped: Bool {
        return true
    }
}
