import SwiftUI

struct ClipboardListView: View {
    
    @ObservedObject private var clipboard: ClipboardManager
    @State private var selectedIndex: Int = 0
    
    init() {
        self.clipboard = ClipboardManager.shared
    }
    
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider().background(Color.white.opacity(0.2))
            contentView
        }
        .frame(width: 400, height: 500)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.95)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .onAppear {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        HStack {
            Text("Clipboard Manager")
                .font(.headline)
                .foregroundColor(.white)
            
            Spacer()
            
            if !clipboard.items.isEmpty {
                Button(action: { clipboard.clearAll() }) {
                    Text("Clear All")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color.black.opacity(0.95))
    }
    
    // MARK: - Content View
    private var contentView: some View {
        Group {
            if clipboard.items.isEmpty {
                emptyStateView
            } else {
                itemsListView
            }
        }
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            Text("No clipboard history")
                .foregroundColor(.gray)
                .font(.body)
            Text("Copy something to get started")
                .foregroundColor(.gray.opacity(0.7))
                .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.9))
    }
    
    // MARK: - Items List
    private var itemsListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(Array(clipboard.items.enumerated()), id: \.element.id) { index, item in
                    ClipboardItemRow(
                        item: item,
                        index: index,
                        isSelected: index == selectedIndex,
                        onSelect: { selectedIndex = index },
                        onPaste: { pasteItem(item) }
                    )
                }
            }
            .padding()
        }
        .background(Color.black.opacity(0.9))
    }

    
    // MARK: - Paste Item
    private func pasteItem(_ item: ClipboardItem) {
        // Use PasteManager to paste
        PasteManager.shared.pasteItem(item)
        
        // Close the window after pasting
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.keyWindow?.close()
        }
    }
}

// MARK: - Clipboard Item Row
struct ClipboardItemRow: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onPaste: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            Image(systemName: item.isText ? "doc.text" : "photo")
                .font(.title2)
                .foregroundColor(item.isText ? .blue : .green)
                .frame(width: 40)
            
            // Content preview
            VStack(alignment: .leading, spacing: 4) {
                if item.isText {
                    Text(item.preview)
                        .foregroundColor(.white)
                        .font(.body)
                        .lineLimit(2)
                } else if let image = item.nsImage() {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 80)
                        .cornerRadius(8)
                }
                
                Text(timeAgo(from: item.date))
                    .foregroundColor(.gray)
                    .font(.caption2)
            }
            
            Spacer()
            
            // Index number
            Text("\\(index + 1)")
                .foregroundColor(.gray)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.1))
                .cornerRadius(4)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected || isHovering ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
        )
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                onSelect()
            }
        }
        .onTapGesture {
            onPaste()
        }
    }
    
    // Format time ago
    private func timeAgo(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        
        if seconds < 60 {
            return "Just now"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\\(minutes)m ago"
        } else if seconds < 86400 {
            let hours = seconds / 3600
            return "\\(hours)h ago"
        } else {
            let days = seconds / 86400
            return "\\(days)d ago"
        }
    }
}
