import SwiftUI

/// Main entry point of the MirrorKit application
@main
struct MirrorKitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}
