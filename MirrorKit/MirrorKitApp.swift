import SwiftUI

/// Point d'entrée principal de l'application MirrorKit
@main
struct MirrorKitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Scène vide — la fenêtre est gérée manuellement via MirrorWindowController
        Settings {
            EmptyView()
        }
    }
}
