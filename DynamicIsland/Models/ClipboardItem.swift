import Foundation
import AppKit
   
struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let content: Content
    let date: Date
    let preview: String // Text preview or image description
    var isPinned: Bool = false
    
    init(id: UUID = UUID(), content: Content, date: Date = Date(), isPinned: Bool = false) {
        self.id = id
        self.content = content
        self.date = date
        self.isPinned = isPinned
        
        switch content {
        case .text(let str):
            self.preview = str.trimmingCharacters(in: .whitespacesAndNewlines)
        case .image:
            self.preview = "📷 Image"
        }
    }
    
    enum Content: Codable, Equatable {
        case text(String)
        case image(Data) // Stored as compressed JPEG/PNG thumbnail
        
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
                let string = try container.decode(String.self, forKey: .data)
                self = .text(string)
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
    
    // Generate preview text
    static func makePreview(from content: Content) -> String {
        switch content {
        case .text(let string):
            // First 100 characters or first 2 lines
            let lines = string.components(separatedBy: .newlines)
            let previewLines = lines.prefix(2).joined(separator: " ")
            return String(previewLines.prefix(100))
        case .image:
            return "Image"
        }
    }
    
    init(id: UUID = UUID(), content: Content, date: Date = Date()) {
        self.id = id
        self.content = content
        self.date = date
        self.preview = Self.makePreview(from: content)
    }
    
    // Get NSImage from image content
    func nsImage() -> NSImage? {
        if case .image(let data) = content {
            return NSImage(data: data)
        }
        return nil
    }
    
    // Get text from text content
    func text() -> String? {
        if case .text(let string) = content {
            return string
        }
        return nil
    }
}

// MARK: - Image Utilities
extension NSImage {
    // Resize image to fit within maxSize while maintaining aspect ratio
    func resized(to maxSize: CGSize) -> NSImage {
        let widthRatio = maxSize.width / size.width
        let heightRatio = maxSize.height / size.height
        let ratio = min(widthRatio, heightRatio)
        
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
    
    // Convert to JPEG data with compression
    func jpegData(compressionQuality: CGFloat = 0.7) -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }
}
