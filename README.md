The biggest update yet. **VClipboard is now Clippy** — rebuilt from the ground up with a modern macOS aesthetic, on-device AI, and image text recognition.

> ⚠️ **Heads up:** the app bundle is now `Clippy.app`. If you're upgrading from v1, drag the new `Clippy.app` into `/Applications` and remove the old `Clipboard.app`.

---

## ✨ What's new

### 🧠 Apple Intelligence (on-device AI)
Right-click any text in your history → **Apple Intelligence** to instantly:
- **Summarize** long passages
- **Fix grammar & spelling**
- **Translate** between languages
- **Explain** technical jargon
- **Rewrite** in a different tone
- **Make a list** from prose

Results stream in **inline** in a beautiful frosted-glass panel — no new window, no context switch. Hit **Open Full** if you want a bigger workspace.

> 100% on-device. Nothing ever leaves your Mac. No API keys. No accounts. Free.

### 🔎 Live search + keyboard control
- Press `⌥V` to open Clippy and just start typing — instant fuzzy search across your entire history
- `↑` / `↓` to navigate, `Return` to paste
- `Esc` to clear search or close the panel

### ⚡ Quick-paste hotkeys
- `⌘1` – `⌘9` while Clippy is open
- **`⌥⌘1` – `⌥⌘9` globally** — paste from your last 9 items into *any* app, no need to even open Clippy

### 🖼️ OCR for copied images
Copy a screenshot, a meme, or a PDF screen-grab and Clippy automatically reads the text out of it using Apple's Vision framework. Then:
- Search by the text inside the image
- "Paste as Text" or "Paste as Image" — your choice
- Smart paste auto-uses text when you target a text field

### 🎨 Brand-new UI
- Crystal-glass aesthetic inspired by macOS Tahoe Control Center
- Continuous corner curves, refined typography, SF Symbols throughout
- New animated glow on the active row, smoother hover states
- Tray drop-zone now uses your system accent color (no more green clash)

---

## 🐛 Bug fixes

- **Fixed:** pasting an item used to silently duplicate it back into history
- **Fixed:** items dragged to the tray were re-recorded into the main clipboard
- **Fixed:** consecutive duplicates on app launch are now cleaned up automatically
- **Fixed:** OCR images now paste their *text* (not the image) when you use number hotkeys in a text field

---

## 📦 Installation

1. Download **`Clippy.zip`** below
2. Unzip and drag **`Clippy.app`** to `/Applications`
3. Right-click → **Open** the first time (Gatekeeper warning is normal — ad-hoc signed)
4. Grant **Accessibility** permission when prompted (needed for paste simulation)
5. Press `⌥V` anywhere to summon Clippy

---

## 💻 Requirements

| Feature | Requirement |
|---|---|
| Core app | macOS 15.0+ • Apple Silicon |
| OCR | macOS 15.0+ (Vision) |
| Apple Intelligence | macOS 26.0+ • M1 or later • Apple Intelligence enabled in Settings |

---

## 🙏 Credits

Built by [@vishal4719](https://github.com/vishal4719). If Clippy saves you time, [buy me a coffee](https://buymeacoffee.com/) ☕

**Full changelog:** v1.0.0...v3.0

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
