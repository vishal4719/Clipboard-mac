import AppKit

class DropAcceptingStatusBarButton: NSButton {
    weak var appDelegate: AppDelegate?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        // Highlight button
        layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.3).cgColor
        return .copy
    }
    
    override func draggingExited(_ sender: NSDraggingInfo?) {
        // Remove highlight
        layer?.backgroundColor = .clear
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        layer?.backgroundColor = .clear
        
        let pasteboard = sender.draggingPasteboard
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return false
        }
        
        // Add files to tray
        for url in urls {
            TrayManager.shared.addFile(url)
        }
        
        // Open clipboard window on Tray tab
        appDelegate?.showClipboardWindowOnTray()
        
        return true
    }
}
