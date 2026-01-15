import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    
    var statusItem: NSStatusItem?
    var clipboardWindow: ClipboardWindow?
    var dragMonitor: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up as background/menu bar app
        NSApp.setActivationPolicy(.accessory)
        
        // Create menu bar icon
        setupMenuBar()
        
        // Setup drag monitoring - opens tray when dragging files near menu bar
        setupDragMonitor()
        
        // Register global hotkey (Option+V)
        HotkeyManager.shared.registerHotkey { [weak self] in
            self?.toggleClipboardWindow()
        }
        
        // Request Accessibility Permissions on Launch
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        
        print("Clipboard Manager launched")
        print("Drag files near menu bar to open tray")
        
        // Ensure app launches on login
        LaunchAtLoginManager.shared.enable()
        
        // internal check for updates
        UpdateManager.shared.checkForUpdates(quietly: true)
    }
    
    // MARK: - Drag Monitor
    private var isWindowOpening = false
    
    private func setupDragMonitor() {
        // Monitor for drag operations globally
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            self?.checkDragPosition(event)
        }
    }
    
    private func checkDragPosition(_ event: NSEvent) {
        guard let screen = NSScreen.main else { return }
        guard !isWindowOpening else { return } // Debounce
        
        let mouseLocation = NSEvent.mouseLocation
        let menuBarHeight: CGFloat = 40
        let triggerZone = screen.frame.maxY - menuBarHeight
        
        // If mouse is near the top of the screen (menu bar area)
        if mouseLocation.y > triggerZone {
            // Open window on tray if not already visible
            if clipboardWindow == nil || !clipboardWindow!.isVisible {
                isWindowOpening = true
                DispatchQueue.main.async {
                    self.showClipboardWindowOnTray()
                    // Reset flag after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.isWindowOpening = false
                    }
                }
            }
        }
    }
    
    // MARK: - Menu Bar Setup
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            // Use SF Symbol for menu bar icon
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard")
        }
        
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "Show Clipboard", action: #selector(showClipboard), keyEquivalent: "v"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        
        statusItem?.menu = menu
        
        print("✅ Hotkey registered: Option+V")
    }
    
    // MARK: - Menu Actions
    @objc private func showClipboard() {
        if let window = clipboardWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            showClipboardWindow()
        }
    }
    
    @objc private func clearHistory() {
        ClipboardManager.shared.clearAll()
    }
    
    @objc private func requestPermissions() {
        // Show accessibility permission dialog
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let _ = AXIsProcessTrustedWithOptions(options)
        
        print("Permission dialog triggered - check System Settings")
    }
    
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
    
    @objc private func checkForUpdates() {
        UpdateManager.shared.checkForUpdates(quietly: false)
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "About VClipboard"
        alert.informativeText = "Developed by Vishal Gupta\n\nThe ultimate clipboard manager for macOS."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "How to Use")
        
        // Set app icon if available
        alert.icon = NSImage(named: "AppIcon")
        
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            if let url = URL(string: "https://vclipboard.vsite.tech/how-to-use") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    // MARK: - Toggle Clipboard Window
    private func toggleClipboardWindow() {
        // Check if window exists and is visible
        if let window = clipboardWindow, window.isVisible {
            // Window is visible, close it
            window.close()
            clipboardWindow = nil
            return
        }
        
        // Show new window (either first time or after being closed)
        showClipboardWindow()
    }
    
    private func showClipboardWindow() {
        // Close existing window if any
        clipboardWindow?.close()
        clipboardWindow = nil
        
        // Create new window
        let window = ClipboardWindow()
        clipboardWindow = window
        
        // Center on screen
        window.center()
        
        // Show window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func showClipboardWindowOnTray() {
        showClipboardWindow()
        
        // Switch to Tray tab
        clipboardWindow?.switchToTab(.tray)
    }
}
