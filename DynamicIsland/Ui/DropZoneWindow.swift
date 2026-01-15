import AppKit

class DropZoneWindow: NSPanel {
    
    private var dropView: DropZoneView!
    private let normalHeight: CGFloat = 50
    private let expandedHeight: CGFloat = 80
    
    init() {
        // Get screen dimensions
        guard let screen = NSScreen.main else {
            super.init(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
            return
        }
        
        let screenFrame = screen.visibleFrame
        let width: CGFloat = 200
        
        // Position at top center of screen
        let xPos = screenFrame.midX - (width / 2)
        let yPos = screenFrame.maxY - normalHeight - 10 // 10px from top
        
        let frame = NSRect(x: xPos, y: yPos, width: width, height: normalHeight)
        
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        setupWindow()
        setupDropView()
    }
    
    private func setupWindow() {
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.isFloatingPanel = true
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    }
    
    private func setupDropView() {
        dropView = DropZoneView(frame: self.contentView!.bounds)
        dropView.onDragEntered = { [weak self] in
            self?.expandDropZone()
        }
        dropView.onDragExited = { [weak self] in
            self?.contractDropZone()
        }
        dropView.onFilesDropped = { [weak self] urls in
            self?.handleDroppedFiles(urls)
            self?.contractDropZone()
        }
        
        self.contentView = dropView
    }
    
    private func expandDropZone() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            
            var frame = self.frame
            frame.size.height = expandedHeight
            frame.origin.y -= (expandedHeight - normalHeight)
            self.animator().setFrame(frame, display: true)
        }
    }
    
    private func contractDropZone() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            
            var frame = self.frame
            frame.size.height = normalHeight
            frame.origin.y += (expandedHeight - normalHeight)
            self.animator().setFrame(frame, display: true)
        }
    }
    
    private func handleDroppedFiles(_ urls: [URL]) {
        print("Files dropped: \(urls.count)")
        
        for url in urls {
            processFile(url)
        }
        
        // Flash feedback
        flashFeedback()
    }
    
    private func processFile(_ url: URL) {
        // Check if it's an image
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic"]
        let fileExtension = url.pathExtension.lowercased()
        
        if imageExtensions.contains(fileExtension) {
            // Load image and add to clipboard
            if let image = NSImage(contentsOf: url) {
                ClipboardManager.shared.addFileImage(image)
                print("Added image: \(url.lastPathComponent)")
            }
        } else if fileExtension == "txt" {
            // Read text file
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                ClipboardManager.shared.addFileText(text, filename: url.lastPathComponent)
                print("Added text file: \(url.lastPathComponent)")
            }
        } else {
            // For other files, just add the filename/path as reference
            let fileInfo = " \(url.lastPathComponent)\nPath: \(url.path)"
            ClipboardManager.shared.addFileText(fileInfo, filename: url.lastPathComponent)
            print("Added file reference: \(url.lastPathComponent)")
        }
    }
    
    private func flashFeedback() {
        dropView.showSuccessFeedback()
    }
    
    override var canBecomeKey: Bool {
        return false
    }
    
    override var canBecomeMain: Bool {
        return false
    }
}

// MARK: - Drop Zone View
class DropZoneView: NSView {
    
    var onDragEntered: (() -> Void)?
    var onDragExited: (() -> Void)?
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
        layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.3).cgColor
        layer?.cornerRadius = 25
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.6).cgColor
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Draw icon and text
        let icon = "📎"
        let text = isDragging ? "Drop Here!" : "Drop Files"
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: isDragging ? 16 : 14, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        
        let iconAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20)
        ]
        
        let iconString = NSAttributedString(string: icon, attributes: iconAttributes)
        let textString = NSAttributedString(string: text, attributes: attributes)
        
        let iconSize = iconString.size()
        let textSize = textString.size()
        
        let iconX = (bounds.width - iconSize.width) / 2
        let iconY = (bounds.height - iconSize.height) / 2 + 8
        
        let textX = (bounds.width - textSize.width) / 2
        let textY = (bounds.height - textSize.height) / 2 - 10
        
        iconString.draw(at: NSPoint(x: iconX, y: iconY))
        textString.draw(at: NSPoint(x: textX, y: textY))
    }
    
    // MARK: - Drag and Drop
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDragging = true
        layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.5).cgColor
        layer?.borderColor = NSColor.systemGreen.cgColor
        needsDisplay = true
        onDragEntered?()
        return .copy
    }
    
    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDragging = false
        layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.3).cgColor
        layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.6).cgColor
        needsDisplay = true
        onDragExited?()
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return false
        }
        
        isDragging = false
        onFilesDropped?(urls)
        
        return true
    }
    
    func showSuccessFeedback() {
        // Flash green
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.8).cgColor
        } completionHandler: { [weak self] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                self?.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.3).cgColor
            }
        }
        
        needsDisplay = true
    }
}
