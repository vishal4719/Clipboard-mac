# Clipboard Manager for macOS

A powerful, native macOS Clipboard Manager and Drag & Drop Tray application built with SwiftUI and AppKit.

## Features

- **Clipboard History**: Automatically tracks your clipboard history (text and images).
- **Drag & Drop Tray**: A dedicated "Tray" zone to temporarily store files, images, and text snippets via drag & drop.
- **Global Hotkey**: Toggle the clipboard window instantly with `Option + V` (default).
- **Paste on Click**: Automatically pastes selected items into the active application.
- **Pin Items**: Pin important clipboard or tray items so they are never auto-deleted.
- **Glassmorphism UI**: A beautiful, native macOS interface with transparency and blur effects.
- **Launch at Login**: Option to start the app automatically when you log in.

## Installation

1.  Download the latest release (or build from source).
2.  Move `Clipboard.app` to your Applications folder.
3.  Open the app. You may need to grant Accessibility permissions for the "Paste on Click" feature to work.

## Development

### Requirements

- macOS 13.0 or later
- Xcode 14.0 or later

### Building

1.  Clone the repository.
2.  Open `DynamicIsland.xcodeproj` in Xcode.
3.  Ensure the "Clipboard" scheme is selected.
4.  Build and Run (Cmd+R).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
