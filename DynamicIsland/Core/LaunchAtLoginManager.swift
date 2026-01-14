import ServiceManagement
import SwiftUI

class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()
    
    func enable() {
        if #available(macOS 13.0, *) {
            do {
                let service = SMAppService.mainApp
                if service.status == .enabled {
                    print("Launch at login is already enabled")
                    return
                }
                
                try service.register()
                print("App successfully registered for launch at login")
            } catch {
                print(" Failed to register app for launch at login: \(error)")
            }
        } else {
             print("Launch at login setup requires macOS 13 or later for this implementation")
        }
    }
    
    func disable() {
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.unregister()
                print("App successfully unregistered from launch at login")
            } catch {
                print(" Failed to unregister app from launch at login: \(error)")
            }
        }
    }
}
