import SwiftUI
import AppKit
import CoreMedia
import CoreVideo

/// NSViewRepresentable view that displays video frames via a CALayer
struct FrameRenderer: NSViewRepresentable {
    /// Reference to the display layer for external updates
    let displayLayer: VideoDisplayLayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer = displayLayer
        displayLayer.contentsGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // No SwiftUI update needed — the layer is updated directly
    }
}

/// Specialized CALayer for displaying video frames.
///
/// Thread safety: marked `@unchecked Sendable` because the only mutable
/// property (`contents`) is exclusively written from the main thread via
/// `displaySampleBuffer(_:)`. All call sites must dispatch to the main
/// thread before invoking display methods.
final class VideoDisplayLayer: CALayer, @unchecked Sendable {

    /// Last pixel buffer displayed — used for snapshotting.
    /// Written and read exclusively on the main thread.
    private(set) var lastPixelBuffer: CVPixelBuffer?

    /// Current zoom / pan / rotation applied to the displayed content.
    /// Main-thread only.
    var videoTransform: CGAffineTransform = .identity {
        didSet { setAffineTransform(videoTransform) }
    }

    override init() {
        super.init()
        // Disable implicit animations to avoid lag
        self.actions = [
            "contents": NSNull(),
            "bounds": NSNull(),
            "position": NSNull(),
            "transform": NSNull()
        ]
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// Displays a CMSampleBuffer — must be called on the main thread
    func displaySampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        displayPixelBuffer(pixelBuffer)
    }

    /// Displays a CVPixelBuffer directly
    func displayPixelBuffer(_ pixelBuffer: CVPixelBuffer) {
        // Build a CIImage then a CGImage for display via CALayer
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        self.contents = cgImage
        self.lastPixelBuffer = pixelBuffer
    }
}
