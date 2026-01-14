import SwiftUI
import AppKit

@main
struct ClipboardManagerApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate

    var body: some Scene {
        // No WindowGroup needed - we create windows programmatically
        Settings {
            EmptyView()
        }
    }
}

