import CoreImage
import CoreVideo
import ImageIO
import UniformTypeIdentifiers
import Foundation

/// Encodes a CVPixelBuffer as PNG data.
enum SnapshotEncoder {
    private static let ciContext = CIContext()

    static func encodePNG(pixelBuffer: CVPixelBuffer) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }

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
