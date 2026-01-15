import Foundation
import AppKit
import Combine

class TrayManager: ObservableObject {
    static let shared = TrayManager()
    
    @Published var items: [TrayItem] = []
    
    private let storageKey = "TrayItems"
    private let maxItems = 50
    
    private init() {
        loadItems()
    }
    
    // MARK: - File Storage
    private func getStorageDirectory() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let directory = appSupport.appendingPathComponent("Clipboard/TrayStorage")
        
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        
        return directory
    }
    
    // MARK: - Add Items
    func addImage(_ image: NSImage, filename: String = "Image") {
        let thumbnail = image.resized(to: CGSize(width: 200, height: 200))
        guard let data = thumbnail.jpegData(compressionQuality: 0.7) else { return }
        
        let item = TrayItem(name: filename, type: .image, data: data)
        saveAndPublish(item)
        print(" Added image to tray: \(filename)")
    }
    
    func addText(_ text: String, filename: String = "Text") {
        guard let data = text.data(using: .utf8) else { return }
        
        let item = TrayItem(name: filename, type: .text, data: data)
        saveAndPublish(item)
        print(" Added text to tray: \(filename)")
    }
    
    func addFile(_ url: URL) {
        let filename = url.lastPathComponent
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic"]
        let fileExtension = url.pathExtension.lowercased()
        
        if imageExtensions.contains(fileExtension) {
            if let image = NSImage(contentsOf: url) {
                addImage(image, filename: filename)
            }
        } else if fileExtension == "txt" {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                addText(text, filename: filename)
            }
        } else {
            // General file storage
            guard let storageDir = getStorageDirectory() else { return }
            let destinationURL = storageDir.appendingPathComponent(filename)
            
            // Generate unique name if exists
            var uniqueURL = destinationURL
            var counter = 1
            while FileManager.default.fileExists(atPath: uniqueURL.path) {
                let name = (filename as NSString).deletingPathExtension
                let ext = (filename as NSString).pathExtension
                uniqueURL = storageDir.appendingPathComponent("\(name)_\(counter).\(ext)")
                counter += 1
            }
            
            do {
                try FileManager.default.copyItem(at: url, to: uniqueURL)
                // Store the relative filename in data
                guard let pathData = uniqueURL.lastPathComponent.data(using: .utf8) else { return }
                
                let item = TrayItem(name: filename, type: .file, data: pathData)
                saveAndPublish(item)
                print("Added file to tray: \(filename)")
            } catch {
                print("Failed to copy file: \(error)")
            }
        }
    }
    
    private func saveAndPublish(_ item: TrayItem) {
        DispatchQueue.main.async {
            self.items.insert(item, at: 0)
            self.trimItems()
            self.saveItems()
        }
    }
    

    
    // MARK: - Copy to Clipboard
    func copyToClipboard(_ item: TrayItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        
        switch item.type {
        case .text:
            if let text = String(data: item.data, encoding: .utf8) {
                pb.setString(text, forType: .string)
                print("Copied text from tray: \(item.name)")
            }
        case .image:
            if let image = NSImage(data: item.data) {
                pb.writeObjects([image])
                print("Copied image from tray: \(item.name)")
            }
        case .file:
            if let filename = String(data: item.data, encoding: .utf8),
               let storageDir = getStorageDirectory() {
                let fileURL = storageDir.appendingPathComponent(filename)
                pb.writeObjects([fileURL as NSURL])
                print("Copied file from tray: \(item.name)")
            }
        }
    }
    
    // MARK: - Persistence
    private func saveItems() {
        if let encoded = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
    
    func removeItem(_ item: TrayItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items.remove(at: index)
            // If file, delete from disk
            if item.type == .file, let url = item.getFileURL() {
                try? FileManager.default.removeItem(at: url)
            }
            saveItems()
        }
    }
    
    // MARK: - Pinning & Management
    func togglePin(for item: TrayItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            var updatedItem = items[index]
            updatedItem.isPinned.toggle()
            items[index] = updatedItem
            saveItems()
        }
    }
    
    func clearAll() {
        // Keep only pinned items
        let pinnedItems = items.filter { $0.isPinned }
        
        // Delete unpinned files
        let unpinnedItems = items.filter { !$0.isPinned }
        for item in unpinnedItems {
            if item.type == .file, let url = item.getFileURL() {
                try? FileManager.default.removeItem(at: url)
            }
        }
        
        items = pinnedItems
        saveItems()
    }


    

    
    private func loadItems() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([TrayItem].self, from: data) {
            items = decoded // No prefix limit here, allow full load (trim happens on add)
        }
    }
    
    private func trimItems() {
        // Don't trim pinned items if possible, or just strict limit?
        // Let's strict limit but prioritize pinned? 
        // For simplicity: strict limit, oldest unpinned go first?
        // Current logic: prefix(max) -> just cuts off bottom.
        // Let's keep it simple for now: strict FIFO but maybe pins persist?
        // User asked for "Clear All" logic mainly. Pinning usually implies "don't auto-delete".
        // Let's leave trimItems simple for now. 
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
    }
}

// MARK: - Tray Item Model
struct TrayItem: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let type: ItemType
    let data: Data
    let date: Date
    var isPinned: Bool = false
    
    enum ItemType: String, Codable {
        case text
        case image
        case file 
    }
    
    init(id: UUID = UUID(), name: String, type: ItemType, data: Data, date: Date = Date(), isPinned: Bool = false) {
        self.id = id
        self.name = name
        self.type = type
        self.data = data
        self.date = date
        self.isPinned = isPinned
    }
    
    var isImage: Bool {
        type == .image
    }
    
    func nsImage() -> NSImage? {
        guard type == .image else { return nil }
        return NSImage(data: data)
    }
    
    func text() -> String? {
        guard type == .text else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    func getFileURL() -> URL? {
        guard type == .file, let filename = String(data: data, encoding: .utf8) else { return nil }
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return appSupport.appendingPathComponent("Clipboard/TrayStorage").appendingPathComponent(filename)
    }
}
