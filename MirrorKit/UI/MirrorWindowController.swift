import AppKit
import SwiftUI

/// Contrôleur de la fenêtre miroir — traffic lights, always-on-top, ombre
final class MirrorWindowController: NSWindowController, NSWindowDelegate {
    private let deviceManager: DeviceManager

    /// Résolution native du flux vidéo
    private var nativeResolution: NSSize?

    /// État always-on-top
    private(set) var isAlwaysOnTop = false {
        didSet { applyWindowLevel() }
    }

    init(deviceManager: DeviceManager) {
        self.deviceManager = deviceManager

        // Taille par défaut : ratio iPhone (390×844 en points logiques)
        let defaultSize = NSSize(width: 390, height: 844)
        let mirrorWindow = MirrorWindow(defaultSize: defaultSize)

        super.init(window: mirrorWindow)
        mirrorWindow.delegate = self

        // Héberger la vue SwiftUI
        let captureEngine = CaptureEngine()
        let contentView = MirrorContentView(
            deviceManager: deviceManager,
            captureEngine: captureEngine,
            onResolutionDetected: { [weak self] resolution in
                self?.handleResolutionDetected(resolution)
            }
        )
        let hostingView = NSHostingView(rootView: contentView)
        mirrorWindow.contentView = hostingView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) non supporté")
    }

    // MARK: - Always-on-top

    /// Bascule le mode always-on-top
    func toggleAlwaysOnTop() {
        isAlwaysOnTop.toggle()
    }

    private func applyWindowLevel() {
        window?.level = isAlwaysOnTop ? .floating : .normal
    }

    // MARK: - Interne

    private func handleResolutionDetected(_ resolution: NSSize) {
        nativeResolution = resolution
        window?.aspectRatio = resolution

        // Adapter la taille initiale : 50% de la résolution native, max 80% de l'écran
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let maxWidth = screen.visibleFrame.width * 0.8
        let maxHeight = screen.visibleFrame.height * 0.8

        var targetWidth = resolution.width * 0.5
        var targetHeight = resolution.height * 0.5

        if targetWidth > maxWidth || targetHeight > maxHeight {
            let ratio = min(maxWidth / targetWidth, maxHeight / targetHeight)
            targetWidth *= ratio
            targetHeight *= ratio
        }

        let targetSize = NSSize(width: targetWidth, height: targetHeight)
        animateResize(to: targetSize, window: window)
    }

    private func animateResize(to size: NSSize, window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }

        let currentFrame = window.frame
        let newOrigin = NSPoint(
            x: currentFrame.midX - size.width / 2,
            y: currentFrame.midY - size.height / 2
        )
        var newFrame = NSRect(origin: newOrigin, size: size)

        // Contraindre dans l'écran visible
        let visibleFrame = screen.visibleFrame
        newFrame.origin.x = max(visibleFrame.minX, min(newFrame.origin.x, visibleFrame.maxX - newFrame.width))
        newFrame.origin.y = max(visibleFrame.minY, min(newFrame.origin.y, visibleFrame.maxY - newFrame.height))

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }
    }
}

// MARK: - MirrorWindow

/// NSWindow avec boutons traffic light (rouge/jaune/vert), titlebar transparente, ombre
final class MirrorWindow: NSWindow {

    init(defaultSize: NSSize) {
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let origin = NSPoint(
            x: screenFrame.midX - defaultSize.width / 2,
            y: screenFrame.midY - defaultSize.height / 2
        )
        let frame = NSRect(origin: origin, size: defaultSize)

        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Titlebar transparente — les traffic lights restent visibles
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true

        // Fond noir pour le contenu vidéo
        backgroundColor = .black

        // Contraintes de taille
        minSize = NSSize(width: 180, height: 320)
        aspectRatio = defaultSize

        // Ombre
        hasShadow = true
        invalidateShadow()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
