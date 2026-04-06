import AppKit
import SwiftUI

/// Contrôleur de la fenêtre miroir — fenêtre borderless avec coins arrondis et ombre
final class MirrorWindowController: NSWindowController {
    private let deviceManager: DeviceManager

    init(deviceManager: DeviceManager) {
        self.deviceManager = deviceManager

        // Taille par défaut : ratio iPhone (390×844 en points logiques)
        let defaultSize = NSSize(width: 390, height: 844)
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let origin = NSPoint(
            x: screenFrame.midX - defaultSize.width / 2,
            y: screenFrame.midY - defaultSize.height / 2
        )
        let frame = NSRect(origin: origin, size: defaultSize)

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Configuration de la fenêtre
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .normal
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 195, height: 422)
        window.aspectRatio = defaultSize

        // Coins arrondis
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.cornerRadius = 20
        window.contentView?.layer?.masksToBounds = true
        window.contentView?.layer?.cornerCurve = .continuous

        super.init(window: window)

        // Héberger la vue SwiftUI
        let captureEngine = CaptureEngine()
        let contentView = MirrorContentView(
            deviceManager: deviceManager,
            captureEngine: captureEngine,
            onResolutionDetected: { [weak window] resolution in
                // Verrouiller le ratio d'aspect selon la résolution du flux
                window?.aspectRatio = resolution
            }
        )
        let hostingView = NSHostingView(rootView: contentView)
        window.contentView = hostingView

        // Réappliquer les coins arrondis sur la hosting view
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 20
        hostingView.layer?.masksToBounds = true
        hostingView.layer?.cornerCurve = .continuous
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) non supporté")
    }

    /// Met à jour le ratio d'aspect de la fenêtre
    func updateAspectRatio(_ size: NSSize) {
        window?.aspectRatio = size
    }
}
