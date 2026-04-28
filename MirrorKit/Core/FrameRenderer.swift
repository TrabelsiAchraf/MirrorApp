import SwiftUI
import AppKit
import CoreImage
import CoreMedia
import CoreVideo
import IOSurface
import os

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

    /// Pending pixel buffer written from the capture queue, read from main.
    /// Protected by `pendingLock`.
    private let pendingLock = OSAllocatedUnfairLock(initialState: PendingState())

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

    /// Schedules a pixel buffer for display, coalescing calls from the capture
    /// queue. Only one `DispatchQueue.main.async` is in flight at a time —
    /// intermediate frames are skipped, matching the display refresh rate
    /// instead of the camera's (which can be 120fps on ProMotion iPhones).
    /// Safe to call from any thread.
    func scheduleSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // CVPixelBuffer is not Sendable on macOS 14 SDK but the lock
        // serialises all access, so the transfer is safe.
        nonisolated(unsafe) let pb = pixelBuffer
        let needsDispatch = pendingLock.withLock { state -> Bool in
            state.pixelBuffer = pb
            if state.dispatched { return false }
            state.dispatched = true
            return true
        }
        if needsDispatch {
            // Safe: VideoDisplayLayer is @unchecked Sendable and drainPending
            // runs exclusively on the main thread.
            nonisolated(unsafe) let layer = self
            DispatchQueue.main.async {
                layer.drainPending()
            }
        }
    }

    /// Called on the main thread to display the latest pending buffer.
    private func drainPending() {
        let wrapped: SendableBuffer? = pendingLock.withLock { state in
            state.dispatched = false
            guard let pb = state.pixelBuffer else { return nil }
            state.pixelBuffer = nil
            return SendableBuffer(pb)
        }
        guard let pixelBuffer = wrapped?.buffer else { return }
        displayPixelBuffer(pixelBuffer)
    }

    /// Displays a CMSampleBuffer — must be called on the main thread
    func displaySampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        displayPixelBuffer(pixelBuffer)
    }

    /// Displays a CVPixelBuffer directly — must be called on the main thread
    func displayPixelBuffer(_ pixelBuffer: CVPixelBuffer) {
        // Zero-copy: hand the IOSurface backing the pixel buffer directly
        // to the CALayer. No CIContext, no CGImage, no GPU round-trip.
        if let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() {
            self.contents = surface
        } else {
            // Fallback: use a shared CIContext (never allocate per frame)
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            guard let cgImage = Self.sharedCIContext.createCGImage(ciImage, from: ciImage.extent) else { return }
            self.contents = cgImage
        }
        self.lastPixelBuffer = pixelBuffer
    }

    private static let sharedCIContext = CIContext()
}

// MARK: - PendingState

/// Mutable state protected by the display layer's unfair lock.
/// @unchecked because CVPixelBuffer is not Sendable on macOS 14 SDK,
/// but access is fully serialised by the lock.
private struct PendingState: @unchecked Sendable {
    var pixelBuffer: CVPixelBuffer?
    var dispatched = false
}

/// Thin wrapper to ferry a CVPixelBuffer across Sendable boundaries.
/// Safe because the buffer is consumed once on the main thread.
private struct SendableBuffer: @unchecked Sendable {
    let buffer: CVPixelBuffer
    init(_ buffer: CVPixelBuffer) { self.buffer = buffer }
}
