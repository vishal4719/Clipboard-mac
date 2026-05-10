import Foundation
import AppKit
import Carbon

final class HotkeyManager {
    
    static let shared = HotkeyManager()
    
    /// Internal record of a registered Carbon hotkey.
    private struct Registration {
        let id: UInt32
        let ref: EventHotKeyRef
    }
    
    /// Identifier scheme: id == 1 is the primary toggle hotkey, id 100…108 are
    /// the quick-paste 1…9 hotkeys. Reserved range 100..199 for quick-paste.
    private static let primaryHotkeyID: UInt32 = 1
    private static let quickPasteIDBase: UInt32 = 100
    private static let signature: FourCharCode = FourCharCode(0x43424D47) // 'CBMG'
    
    private var registrations: [Registration] = []
    private var eventHandler: EventHandlerRef?
    
    /// Callback for the primary hotkey (Option+V).
    private var onPrimaryPressed: (() -> Void)?
    /// Callback for quick-paste hotkeys. Argument is a 1-based index (1…9).
    private var onQuickPasteIndex: ((Int) -> Void)?
    
    private init() {}
    
    // MARK: - Public API
    
    /// Register the primary toggle hotkey (Option+V).
    func registerHotkey(onPressed: @escaping () -> Void) {
        self.onPrimaryPressed = onPressed
        installEventHandlerIfNeeded()
        // Option+V (kVK_ANSI_V = 0x09)
        register(keyCode: 0x09, modifiers: UInt32(optionKey), id: Self.primaryHotkeyID)
    }
    
    /// Register Option+Cmd+1…Option+Cmd+9 as global quick-paste hotkeys.
    /// The callback receives a 1-based index (1…9) corresponding to the digit pressed.
    func registerQuickPasteHotkeys(onPressed: @escaping (Int) -> Void) {
        self.onQuickPasteIndex = onPressed
        installEventHandlerIfNeeded()
        
        // kVK_ANSI_1…9 keycodes are not consecutive – use the official constants.
        let digitKeyCodes: [UInt32] = [
            UInt32(kVK_ANSI_1),
            UInt32(kVK_ANSI_2),
            UInt32(kVK_ANSI_3),
            UInt32(kVK_ANSI_4),
            UInt32(kVK_ANSI_5),
            UInt32(kVK_ANSI_6),
            UInt32(kVK_ANSI_7),
            UInt32(kVK_ANSI_8),
            UInt32(kVK_ANSI_9)
        ]
        let modifiers = UInt32(optionKey | cmdKey)
        for (i, code) in digitKeyCodes.enumerated() {
            register(keyCode: code, modifiers: modifiers, id: Self.quickPasteIDBase + UInt32(i))
        }
        print("Quick-paste hotkeys registered: ⌥⌘1 … ⌥⌘9")
    }
    
    /// Unregister every hotkey and tear down the event handler.
    func unregisterAll() {
        for reg in registrations {
            UnregisterEventHotKey(reg.ref)
        }
        registrations.removeAll()
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            self.eventHandler = nil
        }
    }
    
    /// Backwards-compat convenience.
    func unregisterHotkey() { unregisterAll() }
    
    deinit {
        unregisterAll()
    }
    
    // MARK: - Internals
    
    private func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) {
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref = ref {
            registrations.append(Registration(id: id, ref: ref))
        } else {
            print("[HotkeyManager] Failed to register hotkey id=\(id) status=\(status)")
        }
    }
    
    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        
        let eventSpec = [EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )]
        
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        
        let handler: EventHandlerUPP = { (_, theEvent, userData) -> OSStatus in
            guard let userData = userData, let theEvent = theEvent else {
                return OSStatus(eventNotHandledErr)
            }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            
            // Pull the EventHotKeyID out of the event payload to figure out which hotkey fired.
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                theEvent,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return OSStatus(eventNotHandledErr) }
            
            DispatchQueue.main.async {
                if hotKeyID.id == HotkeyManager.primaryHotkeyID {
                    manager.onPrimaryPressed?()
                } else if hotKeyID.id >= HotkeyManager.quickPasteIDBase,
                          hotKeyID.id < HotkeyManager.quickPasteIDBase + 9 {
                    let oneBasedIndex = Int(hotKeyID.id - HotkeyManager.quickPasteIDBase) + 1
                    manager.onQuickPasteIndex?(oneBasedIndex)
                }
            }
            
            return noErr
        }
        
        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            eventSpec,
            selfPtr,
            &eventHandler
        )
    }
}
