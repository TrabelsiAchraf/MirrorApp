import SwiftUI

/// Main entry point of the MirrorKit application
@main
struct MirrorKitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // All windows are managed via AppDelegate. The Settings scene is required
        // by SwiftUI but our custom menu opens SettingsView in its own NSWindow.
        Settings { EmptyView() }
    }
}
