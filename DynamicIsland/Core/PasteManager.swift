import Foundation
import AppKit

class PasteManager {
    static let shared = PasteManager()
    
    private init() {}
    
    // MARK: - Paste Item (Just Copy to Clipboard)
    func pasteItem(_ item: ClipboardItem) {
        // Simply copy the item to clipboard
        copyToClipboard(item)
        print("✅ Copied to clipboard - Press Cmd+V to paste")
    }
    
    // MARK: - Paste String
    func pasteString(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
        print("📋 String copied to clipboard: \(string)")
        
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
                print("❌ Failed to decode image")
                return
            }
            pb.writeObjects([image])
            print("📋 Image copied to clipboard")
        }
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
        
        print("⌨️ Simulated Cmd+V (CGEvent)")
    }
}
