import Foundation
import AppKit

class PasteManager {
    static let shared = PasteManager()
    
    private init() {}
    
    // MARK: - Paste Item (Just Copy to Clipboard)
    func pasteItem(_ item: ClipboardItem) {
        // Simply copy the item to clipboard
        copyToClipboard(item)
        print(" Copied to clipboard - Press Cmd+V to paste")
    }
    
    /// Pastes the "primary" representation of the item into the active app and auto-types ⌘V.
    /// For images that have OCR'd text available, this pastes the recognized text instead
    /// (mirrors the in-window click behavior). Used by the global quick-paste hotkeys.
    func pasteItemSmart(_ item: ClipboardItem) {
        if item.isImage, item.hasOCRText, let ocr = item.ocrText, !ocr.isEmpty {
            pasteString(ocr) // pasteString already simulates ⌘V
            return
        }
        copyToClipboard(item)
        // Tiny delay so the pasteboard change has settled before we synthesize ⌘V.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            self?.simulateCmdV()
        }
    }
    
    // MARK: - Paste String
    func pasteString(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
        // Tell the monitor this write came from us so it doesn't re-record it.
        ClipboardManager.shared.acknowledgeSelfWrite()
        print(" String copied to clipboard: \(string)")
        
        // Simulate Paste
        simulateCmdV()
    }
    
    // MARK: - Copy to Clipboard
    private func copyToClipboard(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        
        switch item.content {
        case .text(let string):
            pb.setString(string, forType: .string)
            print("📋 Text copied to clipboard")
            
        case .image(let data):
            guard let image = NSImage(data: data) else {
                print("Failed to decode image")
                return
            }
            pb.writeObjects([image])
            print("Image copied to clipboard")
        }
        
        // Tell the monitor this write came from us so it doesn't re-record it.
        ClipboardManager.shared.acknowledgeSelfWrite()
    }
    // MARK: - Simulate Cmd+V
    func simulateCmdV() {
        // Accessibility check (handled by UI now)
        let source = CGEventSource(stateID: .combinedSessionState)
        
        let vKeyCode: CGKeyCode = 0x09 // 'v'
        
        // 1. Command Down
        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true) else { return }
        cmdDown.flags = .maskCommand
        cmdDown.post(tap: .cghidEventTap)
        
        // 2. V Down
        guard let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true) else { return }
        vDown.flags = .maskCommand
        vDown.post(tap: .cghidEventTap)
        
        // 3. V Up
        guard let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else { return }
        vUp.flags = .maskCommand
        vUp.post(tap: .cghidEventTap)
        
        // 4. Command Up
        guard let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else { return }
        cmdUp.post(tap: .cghidEventTap)
        
        print("Simulated Cmd+V (CGEvent)")
    }
}
