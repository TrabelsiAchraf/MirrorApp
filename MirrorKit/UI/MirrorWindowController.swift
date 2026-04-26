import AppKit
import SwiftUI

/// Mirror window controller
final class MirrorWindowController: NSWindowController {
    private let deviceManager: DeviceManager

    private(set) var isAlwaysOnTop = false {
        didSet { window?.level = isAlwaysOnTop ? .floating : .normal }
    }

    /// Native (unrotated) iPhone resolution, cached so rotation can recompute the aspect ratio.
    private var baseResolution: NSSize?

    /// Width reserved for the annotation tools side panel when active.
    private let annotationPanelWidth: CGFloat = 72
    private(set) var isAnnotationPanelVisible: Bool = false

    init(deviceManager: DeviceManager) {
        self.deviceManager = deviceManager

        let defaultSize = NSSize(width: 390, height: 844)
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let origin = NSPoint(
            x: screenFrame.midX - defaultSize.width / 2,
            y: screenFrame.midY - defaultSize.height / 2
        )

        // Fully borderless window — the content IS the device
        let window = BorderlessWindow(
            contentRect: NSRect(origin: origin, size: defaultSize),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.minSize = NSSize(width: 200, height: 400)
        window.aspectRatio = defaultSize
        window.styleMask.insert(.miniaturizable)
        window.collectionBehavior = [.fullScreenPrimary]

        super.init(window: window)

        let captureEngine = CaptureEngine()
        let contentView = MirrorContentView(
            deviceManager: deviceManager,
            captureEngine: captureEngine,
            onResolutionDetected: { [weak self] resolution in
                self?.handleResolutionDetected(resolution)
            },
            onRotationChanged: { [weak self] isLandscape in
                self?.handleRotationChanged(isLandscape: isLandscape)
            },
            onAnnotationModeChanged: { [weak self] active in
                self?.setAnnotationPanelVisible(active)
            }
        )
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.layer?.backgroundColor = .clear
        window.contentView = hostingView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func toggleAlwaysOnTop() {
        isAlwaysOnTop.toggle()
    }

    // Make the borderless window able to receive events
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
    }

    private func handleRotationChanged(isLandscape: Bool) {
        guard let window, let base = baseResolution else { return }
        let deviceAspect = isLandscape
            ? NSSize(width: base.height, height: base.width)
            : base
        let panelW = isAnnotationPanelVisible ? annotationPanelWidth : 0

        // Solve for new device dimensions that preserve the current window
        // area (device area + panel area). Aspect of device = aspect.w / aspect.h.
        // Equation: (deviceH * aspectRatio + panelW) * deviceH = area
        let area = window.frame.width * window.frame.height
        let r = deviceAspect.width / deviceAspect.height
        let discriminant = panelW * panelW + 4 * r * area
        let deviceH = (-panelW + sqrt(discriminant)) / (2 * r)
        let deviceW = deviceH * r
        let newWidth = deviceW + panelW
        let newHeight = deviceH

        window.aspectRatio = NSSize(width: newWidth, height: newHeight)

        let newOrigin = NSPoint(
            x: window.frame.midX - newWidth / 2,
            y: window.frame.midY - newHeight / 2
        )
        let newFrame = NSRect(origin: newOrigin, size: NSSize(width: newWidth, height: newHeight))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }
    }

    /// Expand the window to make room for the annotation side panel (or shrink
    /// it back). Updates `aspectRatio` so subsequent user resizes preserve the
    /// new device + panel proportions.
    private func setAnnotationPanelVisible(_ visible: Bool) {
        guard isAnnotationPanelVisible != visible, let window else { return }
        isAnnotationPanelVisible = visible
        let delta: CGFloat = visible ? annotationPanelWidth : -annotationPanelWidth

        var newFrame = window.frame
        newFrame.size.width = max(window.minSize.width, newFrame.size.width + delta)
        newFrame.origin.x -= delta / 2  // keep window centered around its midpoint

        window.aspectRatio = NSSize(width: newFrame.width, height: newFrame.height)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.20
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }
    }

    private func handleResolutionDetected(_ resolution: NSSize) {
        baseResolution = resolution
        window?.aspectRatio = resolution

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

        let currentFrame = window.frame
        let newOrigin = NSPoint(
            x: currentFrame.midX - targetWidth / 2,
            y: currentFrame.midY - targetHeight / 2
        )
        var newFrame = NSRect(origin: newOrigin, size: NSSize(width: targetWidth, height: targetHeight))
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

// MARK: - BorderlessWindow

/// Borderless NSWindow that accepts keyboard and mouse events
final class BorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
