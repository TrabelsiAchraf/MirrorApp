import AppKit
import CoreImage
import CoreVideo
import ImageIO
import UniformTypeIdentifiers
import Foundation

/// Renders pixel buffers and NSImages to PNG data.
enum SnapshotEncoder {
    private static let ciContext = CIContext()

    /// Renders a CVPixelBuffer to an NSImage at native pixel dimensions.
    /// Used by AnnotationCompositor to layer annotations on top before PNG encoding.
    static func makeNSImage(pixelBuffer: CVPixelBuffer) -> NSImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = CGRect(
            x: 0,
            y: 0,
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
        guard let cgImage = ciContext.createCGImage(ciImage, from: extent) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: extent.size)
    }

    /// Encodes an NSImage as PNG data using CGImageDestination (no TIFF round-trip).
    static func encodePNG(image: NSImage) -> Data? {
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return nil
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }

        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
