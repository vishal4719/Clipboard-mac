import SwiftUI
import AppKit
import Combine
import Vision

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
        // Run OCR for any image items that were saved before the OCR feature
        // existed (or that finished partially). Cheap because history is bounded.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let snapshot = DispatchQueue.main.sync { self.items }
            for item in snapshot where item.isImage && !item.hasOCRText {
                self.ensureOCR(for: item)
            }
        }
    }

    // MARK: - Monitoring
    private func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
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
        // Then try text (standard)
        else if let text = pb.string(forType: .string), !text.isEmpty {
            addTextItem(text)
        }
        // Fallback: Try to read RTF or HTML and convert to string
        else if let rtfData = pb.data(forType: .rtf) {
            if let attributedString = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
                addTextItem(attributedString.string)
            }
        }
        else if let htmlData = pb.data(forType: .html) {
             if let attributedString = NSAttributedString(html: htmlData, options: [:], documentAttributes: nil) {
                addTextItem(attributedString.string)
            }
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
        
        // Kick off OCR in the background. Uses the FULL image (not the thumbnail)
        // so we don't lose detail for text recognition.
        runOCR(on: image, itemID: item.id)
    }
    
    // MARK: - OCR (on-device, free, via Vision)
    
    /// Performs text recognition on the given image and updates the corresponding
    /// `ClipboardItem.ocrText` on the main queue when complete.
    private func runOCR(on image: NSImage, itemID: UUID) {
        // Convert to CGImage for Vision
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }
        
        // Run on a background queue so we don't block the clipboard timer
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let request = VNRecognizeTextRequest { [weak self] request, error in
                guard let self = self,
                      error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation] else {
                    return
                }
                
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let recognized = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                
                guard !recognized.isEmpty else { return }
                self.applyOCRText(recognized, to: itemID)
            }
            
            // .accurate is slower but much better quality on screenshots/UI text.
            // Apple Silicon handles a 200x200 thumbnail in ~50-150ms.
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                print("[OCR] \(error.localizedDescription)")
            }
        }
    }
    
    /// Updates an item's OCR text on the main queue and persists.
    private func applyOCRText(_ text: String, to itemID: UUID) {
        DispatchQueue.main.async {
            guard let index = self.items.firstIndex(where: { $0.id == itemID }) else { return }
            self.items[index].ocrText = text
            self.saveItems()
            // Notify observers so the UI can update if the window is open.
            NotificationCenter.default.post(name: .clipboardOCRDidUpdate, object: itemID)
        }
    }
    
    /// Run OCR on demand for an item that didn't have it yet (e.g. items saved before this feature).
    func ensureOCR(for item: ClipboardItem) {
        guard item.isImage, !item.hasOCRText, let image = item.nsImage() else { return }
        runOCR(on: image, itemID: item.id)
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
    
    /// Tells the manager that we just wrote to the system pasteboard ourselves
    /// (e.g. a "paste from history" action). Call this *immediately after* the
    /// `pb.setString(...)` / `pb.writeObjects(...)` so the next monitor tick
    /// doesn't re-record our own write as a fresh history entry.
    ///
    /// Without this call, pasting item #2 would re-copy that text to the
    /// pasteboard, the monitor would catch the change, and a duplicate would
    /// be inserted at position #1 — pushing every other item one slot down.
    func acknowledgeSelfWrite() {
        changeCount = NSPasteboard.general.changeCount
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
            // Collapse runs of consecutive identical items. This cleans up any
            // duplicates accumulated before the self-write suppression existed,
            // while preserving real "I copied X, then later copied X again" entries.
            let cleaned = Self.removeConsecutiveDuplicates(decoded)
            items = cleaned
            if cleaned.count != decoded.count {
                saveItems()
            }
        }
    }
    
    private static func removeConsecutiveDuplicates(_ source: [ClipboardItem]) -> [ClipboardItem] {
        var result: [ClipboardItem] = []
        result.reserveCapacity(source.count)
        for item in source {
            if let last = result.last, sameContent(last, item) {
                // Pinned state from either copy is preserved on the kept entry.
                if item.isPinned, !last.isPinned {
                    result[result.count - 1].isPinned = true
                }
                continue
            }
            result.append(item)
        }
        return result
    }
    
    private static func sameContent(_ a: ClipboardItem, _ b: ClipboardItem) -> Bool {
        switch (a.content, b.content) {
        case (.text(let s1), .text(let s2)):
            return s1 == s2
        case (.image(let d1), .image(let d2)):
            return d1.prefix(1024) == d2.prefix(1024)
        default:
            return false
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

// MARK: - Notifications

extension Notification.Name {
    /// Posted (on the main queue) when OCR finishes for a clipboard item.
    /// `object` is the item's `UUID`.
    static let clipboardOCRDidUpdate = Notification.Name("ClipboardManager.OCRDidUpdate")
}
