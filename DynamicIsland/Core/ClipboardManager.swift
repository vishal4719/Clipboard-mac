import SwiftUI
import AppKit
import Combine

final class ClipboardManager: ObservableObject {

    static let shared = ClipboardManager()

    @Published var items: [ClipboardItem] = []

    private var changeCount = NSPasteboard.general.changeCount
    private var timer: Timer?
    private let maxItems = 15
    private let storageKey = "ClipboardHistory"
    
    // Apps to ignore (Privacy Mode)
    private let sensitiveApps = [
        "com.apple.keychainaccess",
        "com.agilebits.onepassword",
        "com.bitwarden.desktop",
        "com.lastpass.LastPass",
        "org.keepassxc.keepassxc",
        "com.apple.Passwords" 
    ]

    private init() {
        loadItems()
        startMonitoring()
    }

    // MARK: - Monitoring
    private func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }
    
    private func checkClipboard() {
        let pb = NSPasteboard.general

        if pb.changeCount != changeCount {
            changeCount = pb.changeCount
            
            // Privacy Check: Don't capture from sensitive apps
            if let frontApp = NSWorkspace.shared.frontmostApplication,
               let bundleId = frontApp.bundleIdentifier {
                
                if sensitiveApps.contains(where: { bundleId.caseInsensitiveCompare($0) == .orderedSame }) {
                    print(" Privacy: Ignored copy from \(frontApp.localizedName ?? bundleId)")
                    return
                }
            }
            
            captureClipboardItem()
        }
    }
    
    private func captureClipboardItem() {
        let pb = NSPasteboard.general
        
        // Try to capture image first (higher priority)
        if let image = NSImage(pasteboard: pb) {
            addImageItem(image)
        }
        // Then try text
        else if let text = pb.string(forType: .string), !text.isEmpty {
            addTextItem(text)
        }
    }
    
    // MARK: - Add Items
    private func addTextItem(_ text: String) {
        // Check for duplicate (don't add if already exists at top)
        if let first = items.first,
           first.isText,
           first.text() == text {
            return
        }
        
        let item = ClipboardItem(content: .text(text))
        
        DispatchQueue.main.async {
            self.items.insert(item, at: 0)
            self.trimItems()
            self.saveItems()
        }
    }
    
    private func addImageItem(_ image: NSImage) {
        // Create thumbnail (max 200x200)
        let thumbnail = image.resized(to: CGSize(width: 200, height: 200))
        
        guard let data = thumbnail.jpegData(compressionQuality: 0.7) else {
            return
        }
        
        // Check for duplicate (compare first 1KB of data)
        if let first = items.first,
           first.isImage,
           let firstData = first.nsImage()?.jpegData(),
           firstData.prefix(1024) == data.prefix(1024) {
            return
        }
        
        let item = ClipboardItem(content: .image(data))
        
        DispatchQueue.main.async {
            self.items.insert(item, at: 0)
            self.trimItems()
            self.saveItems()
        }
    }
    
    // MARK: - Item Management
    private func trimItems() {
        while items.count > maxItems {
            // Priority: Remove oldest unpinned item
            if let index = items.lastIndex(where: { !$0.isPinned }) {
                items.remove(at: index)
            } else {
                // If all are pinned, remove the absolute oldest
                items.removeLast()
            }
        }
    }
    

    
    // MARK: - Copy to Clipboard
    func copyToClipboard(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        
        switch item.content {
        case .text(let string):
            pb.setString(string, forType: .string)
        case .image(let data):
            if let image = NSImage(data: data) {
                pb.writeObjects([image])
            }
        }
        
        // Update change count to prevent re-adding this item
        changeCount = pb.changeCount
    }
    
    // MARK: - Pinning & Management
    func togglePin(for item: ClipboardItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            var updatedItem = items[index]
            updatedItem.isPinned.toggle()
            items[index] = updatedItem
            saveItems()
        }
    }
    
    func clearAll() {
        // Keep only pinned items
        items = items.filter { $0.isPinned }
        saveItems()
    }
    
    func deleteItem(_ item: ClipboardItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items.remove(at: index)
            saveItems()
        }
    }

    // MARK: - Persistence
    private func saveItems() {
        if let encoded = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
    
    private func loadItems() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            items = decoded // Remove prefix(limit) to allow pins to stay
        }
    }
    
    // MARK: - Public Methods for File Drops
    func addFileImage(_ image: NSImage) {
        addImageItem(image)
    }
    
    func addFileText(_ text: String, filename: String? = nil) {
        // Add filename as prefix if provided
        let content = if let filename = filename {
            " \(filename)\n\n\(text)"
        } else {
            text
        }
        addTextItem(content)
    }
    
    deinit {
        timer?.invalidate()
    }
}
