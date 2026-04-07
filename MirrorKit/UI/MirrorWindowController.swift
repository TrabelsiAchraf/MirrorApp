import AppKit
import SwiftUI

/// Mirror window controller
final class MirrorWindowController: NSWindowController {
    private let deviceManager: DeviceManager

    private(set) var isAlwaysOnTop = false {
        didSet { window?.level = isAlwaysOnTop ? .floating : .normal }
    }

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

    private func handleResolutionDetected(_ resolution: NSSize) {
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
