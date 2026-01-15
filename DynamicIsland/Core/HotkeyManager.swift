import Foundation
import AppKit
import Carbon

final class HotkeyManager {
    
    static let shared = HotkeyManager()
    
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var onHotkeyPressed: (() -> Void)?
    
    private init() {}
    
    // MARK: - Register Hotkey
    func registerHotkey(onPressed: @escaping () -> Void) {
        self.onHotkeyPressed = onPressed
        
        // Option+V (keyCode 9 = V, optionKey modifier)
        let keyCode: UInt32 = 9  // 'V' key
        let modifiers: UInt32 = UInt32(optionKey)
        
        var hotKeyID = EventHotKeyID(signature: FourCharCode(0x43424D47), id: 1) // 'CBMG'
        
        // Create event handler callback
        let eventSpec = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))]
        
        // Install event handler
        var eventHandlerUPP: EventHandlerUPP?
        
        eventHandlerUPP = { (nextHandler, theEvent, userData) -> OSStatus in
            // Extract self from userData
            guard let manager = unsafeBitCast(userData, to: HotkeyManager?.self) else {
                return OSStatus(eventNotHandledErr)
            }
            
            // Trigger callback on main thread
            DispatchQueue.main.async {
                manager.onHotkeyPressed?()
            }
            
            return noErr
        }
        
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            eventHandlerUPP,
            1,
            eventSpec,
            selfPtr,
            &eventHandler
        )
        
        guard status == noErr else {
            print("Failed to install event handler: \(status)")
            return
        }
        
        // Register hotkey
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if registerStatus == noErr {
            print(" Hotkey registered: Option+V")
        } else {
            print(" Failed to register hotkey: \(registerStatus)")
        }
    }
    
    // MARK: - Unregister Hotkey
    func unregisterHotkey() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        
        print("Hotkey unregistered")
    }
    
    deinit {
        unregisterHotkey()
    }
}
