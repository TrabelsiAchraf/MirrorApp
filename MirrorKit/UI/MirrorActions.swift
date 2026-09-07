import Foundation

/// Shared action bag bridging the SwiftUI `MirrorContentView` methods to
/// the AppKit-level keyboard monitor and menu items in `AppDelegate`.
///
/// The view fills in the closures on `onAppear`; AppDelegate invokes them
/// from Cmd+R / Cmd+S / etc.
@MainActor
final class MirrorActions {
    var toggleRecording: (() -> Void)?
    var takeSnapshot: (() -> Void)?
    var toggleRotation: (() -> Void)?
    var rotateLeft: (() -> Void)?
    var rotateRight: (() -> Void)?
    var resetZoom: (() -> Void)?
    var toggleAnnotationMode: (() -> Void)?
    /// Opens the SwiftUI Settings scene. Backed by the `openSettings`
    /// environment action — the legacy `showSettingsWindow:` selector is
    /// rejected by SwiftUI on macOS 15+ and silently does nothing.
    var openSettings: (() -> Void)?

    static let shared = MirrorActions()
    private init() {}
}
