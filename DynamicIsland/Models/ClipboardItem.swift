import Foundation
import AppKit
   
struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let content: Content
    let date: Date
    let preview: String
    var isPinned: Bool = false
    /// Text extracted from images via on-device Vision OCR (nil if not yet processed or no text detected).
    var ocrText: String? = nil
    
    init(id: UUID = UUID(), content: Content, date: Date = Date(), isPinned: Bool = false, ocrText: String? = nil) {
        self.id = id
        self.content = content
        self.date = date
        self.isPinned = isPinned
        self.ocrText = ocrText
        self.preview = Self.makePreview(from: content)
    }
    
    /// All text that should match a search query for this item.
    var searchableText: String {
        if let ocr = ocrText, !ocr.isEmpty {
            return preview + "\n" + ocr
        }
        return preview
    }
    
    /// True if OCR has produced any usable text for an image item.
    var hasOCRText: Bool {
        guard let ocr = ocrText else { return false }
        return !ocr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    enum Content: Codable, Equatable {
        case text(String)
        case image(Data) // Full-quality PNG (preferred) or high-quality JPEG
        
        enum CodingKeys: String, CodingKey {
            case type, data
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let string):
                try container.encode("text", forKey: .type)
                try container.encode(string, forKey: .data)
            case .image(let data):
                try container.encode("image", forKey: .type)
                try container.encode(data, forKey: .data)
            }
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            
            if type == "text" {
                let text = try container.decode(String.self, forKey: .data)
                self = .text(text)
            } else {
                let data = try container.decode(Data.self, forKey: .data)
                self = .image(data)
            }
        }
    }
    
    var isText: Bool {
        if case .text = content { return true }
        return false
    }
    
    var isImage: Bool {
        if case .image = content { return true }
        return false
    }
    
    static func makePreview(from content: Content) -> String {
        switch content {
        case .text(let string):
            let lines = string.components(separatedBy: .newlines)
            let previewLines = lines.prefix(2).joined(separator: " ")
            return String(previewLines.prefix(100))
        case .image:
            return "Image"
        }
    }
    
    func nsImage() -> NSImage? {
        if case .image(let data) = content {
            return NSImage(data: data)
        }
        return nil
    }
    
    func text() -> String? {
        if case .text(let string) = content {
            return string
        }
        return nil
    }
}

// MARK: - Image Utilities
extension NSImage {
    func resized(to maxSize: CGSize) -> NSImage {
        guard size.width > 0, size.height > 0 else { return self }
        
        let widthRatio = maxSize.width / size.width
        let heightRatio = maxSize.height / size.height
        let ratio = min(widthRatio, heightRatio, 1.0)
        
        let newSize = CGSize(
            width: size.width * ratio,
            height: size.height * ratio
        )
        
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        
        let rect = CGRect(origin: .zero, size: newSize)
        draw(in: rect, from: CGRect(origin: .zero, size: size), operation: .copy, fraction: 1.0)
        
        newImage.unlockFocus()
        return newImage
    }
    
    func jpegData(compressionQuality: CGFloat = 0.92) -> Data? {
        guard let bitmap = bitmapRepForExport() else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }

    /// Lossless PNG — preferred for screenshots / UI captures.
    func pngData() -> Data? {
        guard let bitmap = bitmapRepForExport() else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    /// Pixel-accurate bitmap at the image's native pixel size (not just point size).
    private func bitmapRepForExport() -> NSBitmapImageRep? {
        // Prefer an existing bitmap rep when the image came from pasteboard/file.
        if let existing = representations.compactMap({ $0 as? NSBitmapImageRep }).first,
           existing.pixelsWide > 0, existing.pixelsHigh > 0 {
            return existing
        }

        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            // Fallback: draw into a bitmap at point size * backing scale.
            guard let tiffData = tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData) else {
                return nil
            }
            return bitmap
        }

        return NSBitmapImageRep(cgImage: cgImage)
    }

    /// Downscale only when the longest edge exceeds `maxEdge` (points/pixels).
    func capped(toMaxEdge maxEdge: CGFloat) -> NSImage {
        let pixelW: CGFloat
        let pixelH: CGFloat
        if let rep = representations.compactMap({ $0 as? NSBitmapImageRep }).first {
            pixelW = CGFloat(rep.pixelsWide)
            pixelH = CGFloat(rep.pixelsHigh)
        } else {
            pixelW = size.width
            pixelH = size.height
        }
        let longest = max(pixelW, pixelH)
        guard longest > maxEdge, longest > 0 else { return self }
        let scale = maxEdge / longest
        return resized(to: CGSize(width: pixelW * scale, height: pixelH * scale))
    }
}
