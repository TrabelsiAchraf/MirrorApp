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
        let target = isLandscape
            ? NSSize(width: base.height, height: base.width)
            : base
        window.aspectRatio = target
        updateMinSize(for: target)

        // Resize to preserve approx current area while matching the new ratio.
        let current = window.frame
        let area = current.width * current.height
        let ratio = target.width / target.height
        let newHeight = sqrt(area / ratio)
        let newWidth = newHeight * ratio
        let newOrigin = NSPoint(
            x: current.midX - newWidth / 2,
            y: current.midY - newHeight / 2
        )
        let newFrame = NSRect(origin: newOrigin, size: NSSize(width: newWidth, height: newHeight))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }
    }

    private func handleResolutionDetected(_ resolution: NSSize) {
        baseResolution = resolution
        window?.aspectRatio = resolution
        updateMinSize(for: resolution)

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

    /// Update minSize so it matches the current aspect ratio. Without this, the
    /// user can resize past minSize and break the aspect lock — the window
    /// ends up taller-than-aspect-allows with the bezel marooned at the top
    /// and a huge empty area below.
    private func updateMinSize(for aspect: NSSize) {
        guard let window else { return }
        // Roughly half the default device-aspect window. Picked so the bezel
        // stays large enough for the toolbar to remain readable.
        let minScaleFactor: CGFloat = 0.30
        let absoluteMin: CGFloat = 240
        let minW = max(absoluteMin, aspect.width * minScaleFactor)
        let minH = max(absoluteMin, aspect.height * minScaleFactor)
        // Preserve the aspect ratio in the minimum: pick whichever dimension
        // hits the absolute floor first and scale the other from it.
        let aspectRatio = aspect.width / aspect.height
        let finalMin: NSSize
        if minW / minH < aspectRatio {
            finalMin = NSSize(width: minH * aspectRatio, height: minH)
        } else {
            finalMin = NSSize(width: minW, height: minW / aspectRatio)
        }
        window.minSize = finalMin
    }
}

// MARK: - BorderlessWindow

/// Borderless NSWindow that accepts keyboard and mouse events
final class BorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
