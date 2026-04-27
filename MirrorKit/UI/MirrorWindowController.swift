import AppKit
import SwiftUI

/// Mirror window controller
final class MirrorWindowController: NSWindowController, NSWindowDelegate {
    private let deviceManager: DeviceManager

    private(set) var isAlwaysOnTop = false {
        didSet { window?.level = isAlwaysOnTop ? .floating : .normal }
    }

    /// Native (unrotated) iPhone resolution, cached so rotation can recompute the aspect ratio.
    private var baseResolution: NSSize?

    /// Width added to the window when the annotation tools side panel is visible.
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
        // Initial floor before resolution detection — keeps the window above
        // a usable threshold even if the user resizes pre-connection.
        // updateMinSize tightens this further once the spec is known.
        window.minSize = NSSize(width: 480, height: 480 * defaultSize.height / defaultSize.width)
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
        window.delegate = self
    }

    /// Borderless windows with locked aspectRatio sometimes let the user drag
    /// past minSize. Clamp explicitly here so the device can't shrink to 1cm.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let minS = sender.minSize
        return NSSize(
            width: max(frameSize.width, minS.width),
            height: max(frameSize.height, minS.height)
        )
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
        let device = isLandscape
            ? NSSize(width: base.height, height: base.width)
            : base
        let panelW = isAnnotationPanelVisible ? annotationPanelWidth : 0

        // Solve for new device dimensions that preserve the current window
        // area, factoring in the side panel.
        // (deviceH × scale × r + panelW) × (deviceH × scale) = area
        let area = window.frame.width * window.frame.height
        let r = device.width / device.height
        let a = device.height * device.height * r
        let b = panelW * device.height
        let scale = (-b + sqrt(b * b + 4 * a * area)) / (2 * a)
        let newDeviceW = device.width * scale
        let newDeviceH = device.height * scale
        let newWidth = newDeviceW + panelW
        let newHeight = newDeviceH

        window.aspectRatio = NSSize(width: newWidth, height: newHeight)
        updateMinSize(for: NSSize(width: newWidth, height: newHeight))

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

    /// Expand/shrink the window so the annotation side panel sits beside the
    /// bezel without shrinking it. Updates `aspectRatio` so subsequent user
    /// resizes preserve the device + panel proportions.
    private func setAnnotationPanelVisible(_ visible: Bool) {
        guard isAnnotationPanelVisible != visible, let window else { return }
        isAnnotationPanelVisible = visible
        let delta: CGFloat = visible ? annotationPanelWidth : -annotationPanelWidth

        var newFrame = window.frame
        newFrame.size.width += delta
        newFrame.origin.x -= delta / 2  // keep window centered

        window.aspectRatio = NSSize(width: newFrame.width, height: newFrame.height)
        updateMinSize(for: NSSize(width: newFrame.width, height: newFrame.height))

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }
    }

    private func handleResolutionDetected(_ resolution: NSSize) {
        baseResolution = resolution
        window?.aspectRatio = resolution
        updateMinSize(for: resolution)

        // Reshape the window to the real device aspect. Aim for the largest
        // aspect-matching size that fits in 90% of the visible screen, but
        // don't shrink the user's existing window if they already resized
        // bigger.
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let current = window.frame
        let aspect = resolution.width / resolution.height

        let maxW = screen.visibleFrame.width * 0.90
        let maxH = screen.visibleFrame.height * 0.90
        // Fit the device aspect inside the 90% box: pick whichever dimension
        // is the limiter, derive the other from the aspect.
        var newW: CGFloat
        var newH: CGFloat
        if maxW / maxH > aspect {
            newH = maxH
            newW = newH * aspect
        } else {
            newW = maxW
            newH = newW / aspect
        }

        // Respect a bigger user-chosen window if they already enlarged it.
        let currentArea = current.width * current.height
        let candidateArea = newW * newH
        if currentArea > candidateArea {
            newH = sqrt(currentArea / aspect)
            newW = aspect * newH
        }

        let newOrigin = NSPoint(
            x: current.midX - newW / 2,
            y: current.midY - newH / 2
        )
        var newFrame = NSRect(origin: newOrigin, size: NSSize(width: newW, height: newH))
        let visible = screen.visibleFrame
        newFrame.origin.x = max(visible.minX, min(newFrame.origin.x, visible.maxX - newFrame.width))
        newFrame.origin.y = max(visible.minY, min(newFrame.origin.y, visible.maxY - newFrame.height))

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
        // The minimum is driven by the toolbar's natural width (~440pt for
        // traffic lights + 4 capture buttons + device pill), expressed in
        // screen points — NOT a fraction of the iPhone's pixel resolution
        // (which would yield ~1180pt height, taller than most Mac screens).
        let minWidth: CGFloat = 460
        let aspectRatio = aspect.width / aspect.height
        var finalMin = NSSize(width: minWidth, height: minWidth / aspectRatio)

        // Cap the minimum to 90 % of the available screen so the window can
        // always fit. Necessary for portrait iPhone aspects on small Macs:
        // 460pt × (1/0.46) = 1000pt height, which would exceed a 13" MBP.
        if let screen = window.screen ?? NSScreen.main {
            let maxH = screen.visibleFrame.height * 0.90
            if finalMin.height > maxH {
                finalMin = NSSize(width: maxH * aspectRatio, height: maxH)
            }
        }

        window.minSize = finalMin

        // NSWindow.minSize doesn't grow a window that's already smaller — it
        // only blocks future shrink. Force the resize so the bump takes
        // effect even on already-undersized windows.
        let frame = window.frame
        if frame.width < finalMin.width || frame.height < finalMin.height {
            let newFrame = NSRect(
                x: frame.midX - finalMin.width / 2,
                y: frame.midY - finalMin.height / 2,
                width: finalMin.width,
                height: finalMin.height
            )
            window.setFrame(newFrame, display: true, animate: true)
        }
    }
}

// MARK: - BorderlessWindow

/// Borderless NSWindow that accepts keyboard and mouse events
final class BorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
