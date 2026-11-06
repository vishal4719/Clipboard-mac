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
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
        // .common so monitoring keeps running while the user scrolls / tracks in UI
        RunLoop.main.add(t, forMode: .common)
        timer = t
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
    
    /// True when the pasteboard carries a *real* bitmap image (not an HTML/PDF preview
    /// that `NSImage(pasteboard:)` would happily render as an image).
    private func pasteboardHasBitmapImage(_ pb: NSPasteboard) -> Bool {
        let imageTypes: [NSPasteboard.PasteboardType] = [
            .tiff, .png,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.heic"),
            NSPasteboard.PasteboardType("com.compuserve.gif"),
        ]
        guard let types = pb.types else { return false }
        return types.contains(where: { imageTypes.contains($0) })
    }
    
    private func captureClipboardItem() {
        let pb = NSPasteboard.general
        
        // Prefer real bitmap images. Use original PNG/TIFF bytes when available so
        // we don't re-encode and lose quality.
        if pasteboardHasBitmapImage(pb) {
            if let png = pb.data(forType: .png), !png.isEmpty {
                addImageData(png, fallbackImage: NSImage(data: png))
                return
            }
            if let tiff = pb.data(forType: .tiff), !tiff.isEmpty {
                // Re-wrap TIFF as PNG for compact lossless storage.
                if let image = NSImage(data: tiff), let png = image.pngData() {
                    addImageData(png, fallbackImage: image)
                    return
                }
            }
            let jpegType = NSPasteboard.PasteboardType("public.jpeg")
            if let jpeg = pb.data(forType: jpegType), !jpeg.isEmpty {
                addImageData(jpeg, fallbackImage: NSImage(data: jpeg))
                return
            }
            if let image = NSImage(pasteboard: pb) {
                addImageItem(image)
                return
            }
        }
        
        if let text = pb.string(forType: .string), !text.isEmpty {
            addTextItem(text)
            return
        }
        
        if let rtfData = pb.data(forType: .rtf),
           let attributedString = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            let text = attributedString.string
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                addTextItem(text)
                return
            }
        }
        
        if let htmlData = pb.data(forType: .html),
           let attributedString = NSAttributedString(html: htmlData, options: [:], documentAttributes: nil) {
            let text = attributedString.string
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                addTextItem(text)
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
    
    /// Soft ceiling so a 40MP photo doesn't blow up UserDefaults. Screenshots
    /// and normal copies stay untouched below this.
    private static let maxImageEdge: CGFloat = 4096

    private func addImageItem(_ image: NSImage) {
        guard let data = Self.encodeImagePreservingQuality(image) else { return }
        addImageData(data, fallbackImage: image)
    }

    /// Stores already-encoded image bytes (PNG/JPEG) when we got them straight
    /// from the pasteboard — zero re-compression.
    private func addImageData(_ data: Data, fallbackImage: NSImage?) {
        // Duplicate check against raw bytes (cheap + accurate).
        if let first = items.first,
           case .image(let existing) = first.content,
           existing.prefix(2048) == data.prefix(2048),
           existing.count == data.count {
            return
        }

        let item = ClipboardItem(content: .image(data))

        DispatchQueue.main.async {
            self.items.insert(item, at: 0)
            self.trimItems()
            self.saveItems()
        }

        // OCR on the highest-res image we have.
        let ocrSource = fallbackImage ?? NSImage(data: data)
        if let ocrSource {
            runOCR(on: ocrSource, itemID: item.id)
        }
    }

    /// Encode for history: PNG (lossless) preferred; only downscale above 4k edge.
    private static func encodeImagePreservingQuality(_ image: NSImage) -> Data? {
        let capped = image.capped(toMaxEdge: maxImageEdge)
        if let png = capped.pngData() { return png }
        return capped.jpegData(compressionQuality: 0.92)
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
    
    // MARK: - Public Methods for File Drops / AI results
    func addFileImage(_ image: NSImage) {
        addImageItem(image)
    }
    
    func addFileText(_ text: String, filename: String? = nil) {
        // Add filename as prefix if provided
        let content = if let filename = filename {
            "\(filename)\n\n\(text)"
        } else {
            text
        }
        addTextItem(content)
    }
    
    /// Insert an Apple Intelligence result into history without writing the
    /// system pasteboard (so we don't overwrite whatever the user has copied).
    func addAIResult(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        addTextItem(trimmed)
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
