import Cocoa
import UserNotifications
import ServiceManagement

/// Manages all system permissions and features for the app
class AccessibilityManager {
    
    // MARK: - Singleton
    static let shared = AccessibilityManager()
    
    private init() {}
    
    // MARK: - Accessibility Permissions
    
    /// Check if accessibility permissions are currently granted
    /// - Returns: True if the app has accessibility permissions
    func hasAccessibilityPermissions() -> Bool {
        return AXIsProcessTrusted()
    }
    
    /// Request accessibility permissions (opens System Preferences/Settings)
    /// This will show a system dialog prompting the user to grant permissions
    func requestAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options)
    }
    
    /// Check and request permissions if needed
    /// - Returns: True if permissions are already granted, false if they need to be requested
    @discardableResult
    func ensureAccessibilityPermissions() -> Bool {
        let trusted = AXIsProcessTrusted()
        
        if !trusted {
            // This will show a system dialog prompting the user
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options)
        }
        
        return trusted
    }
    
    // MARK: - Input Monitoring Permissions
    
    /// Check if input monitoring permissions are granted (needed for global hotkeys)
    /// - Returns: True if the app can monitor input events
    func hasInputMonitoringPermissions() -> Bool {
        // On macOS 10.15+, we need to check if we can monitor input
        if #available(macOS 10.15, *) {
            // Try to create an event tap to test permissions
            let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            guard let eventTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: eventMask,
                callback: { (proxy, type, event, refcon) in return Unmanaged.passUnretained(event) },
                userInfo: nil
            ) else {
                return false
            }
            
            // Event tap is automatically released in Swift
            return true
        }
        
        return true // Older macOS versions don't require this permission
    }
    
    /// Request input monitoring permissions
    func requestInputMonitoringPermissions() {
        // Opening Security & Privacy will prompt the user
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }
    
    // MARK: - Notification Permissions
    
    /// Request notification permissions
    func requestNotificationPermissions(completion: ((Bool) -> Void)? = nil) {
        let center = UNUserNotificationCenter.current()
        
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    print(" Notification permissions granted")
                } else {
                    print("Notification permissions denied")
                }
                completion?(granted)
            }
        }
    }
    
    /// Check current notification authorization status
    func checkNotificationPermissions(completion: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus)
            }
        }
    }
    
    /// Send a test notification
    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Clipboard"
        content.body = "Notifications are working!"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print(" Error sending notification: \(error)")
            }
        }
    }
    
    // MARK: - Launch at Login
    
    /// Check if the app is set to launch at login
    /// - Returns: True if launch at login is enabled
    func isLaunchAtLoginEnabled() -> Bool {
        // For macOS 13+
        if #available(macOS 13, *) {
            return SMAppService.mainApp.status == .enabled
        }
        
        // Legacy method for older macOS versions
        return UserDefaults.standard.bool(forKey: "launchAtLogin")
    }
    
    /// Toggle launch at login
    func toggleLaunchAtLogin() {
        if #available(macOS 13, *) {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                    print(" Launch at login disabled")
                } else {
                    try SMAppService.mainApp.register()
                    print(" Launch at login enabled")
                }
            } catch {
                print("Failed to toggle launch at login: \(error)")
            }
        } else {
            // Legacy method for older macOS
            let isEnabled = UserDefaults.standard.bool(forKey: "launchAtLogin")
            UserDefaults.standard.set(!isEnabled, forKey: "launchAtLogin")
            print(isEnabled ? "Launch at login disabled" : "Launch at login enabled")
        }
    }
    
    // MARK: - User Alerts
    
    /// Show a custom alert explaining why accessibility permissions are needed
    /// - Returns: True if user clicked "Open System Settings", false otherwise
    @discardableResult
    func showAccessibilityPermissionAlert() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
        Clipboard needs accessibility permissions to:
        • Monitor clipboard changes in real-time
        • Provide quick paste functionality
        • Simulate keyboard shortcuts (Cmd+V)
        
        Click "Open System Settings" to grant permissions.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            requestAccessibilityPermissions()
            return true
        }
        
        return false
    }
    
    /// Show comprehensive permission status
    func showPermissionStatus() {
        let accessibilityGranted = hasAccessibilityPermissions()
        let inputMonitoringGranted = hasInputMonitoringPermissions()
        
        checkNotificationPermissions { notificationStatus in
            let alert = NSAlert()
            alert.messageText = "Permission Status"
            
            var statusText = ""
            statusText += "Accessibility: \(accessibilityGranted ? " Granted" : " Not Granted")\n"
            statusText += "Input Monitoring: \(inputMonitoringGranted ? "Granted" : " Not Granted")\n"
            statusText += "Notifications: \(notificationStatus == .authorized ? "Granted" : " Not Granted")\n"
            statusText += "Launch at Login: \(self.isLaunchAtLoginEnabled() ? "Enabled" : "Disabled")"
            
            alert.informativeText = statusText
            alert.alertStyle = .informational
            
            if !accessibilityGranted || !inputMonitoringGranted || notificationStatus != .authorized {
                alert.addButton(withTitle: "Grant Permissions")
                alert.addButton(withTitle: "Close")
                
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    if !accessibilityGranted {
                        self.requestAccessibilityPermissions()
                    } else if !inputMonitoringGranted {
                        self.requestInputMonitoringPermissions()
                    } else if notificationStatus != .authorized {
                        self.requestNotificationPermissions()
                    }
                }
            } else {
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
    
    /// Open System Preferences/Settings directly to Accessibility panel
    func openAccessibilityPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
    
    // MARK: - Comprehensive Permission Check
    
    /// Check all required permissions on launch
    func checkAllPermissions() {
        // Check accessibility
        if hasAccessibilityPermissions() {
            print(" Accessibility permissions granted")
        } else {
            print(" Accessibility permissions not granted")
        }
        
        // Check input monitoring
        if hasInputMonitoringPermissions() {
            print(" Input monitoring permissions granted")
        } else {
            print(" Input monitoring permissions not granted")
        }
        
        // Check notifications
        checkNotificationPermissions { status in
            switch status {
            case .authorized:
                print("Notification permissions granted")
            case .denied:
                print(" Notification permissions denied")
            case .notDetermined:
                print("Notification permissions not determined")
            default:
                print(" Notification permissions: \(status.rawValue)")
            }
        }
    }
    
    /// Check permissions and show alert if not granted
    /// - Returns: True if permissions are granted (or user is being prompted)
    func checkAndPromptIfNeeded() -> Bool {
        if hasAccessibilityPermissions() {
            return true
        }
        
        // Show custom alert first
        showAccessibilityPermissionAlert()
        return false
    }
}
