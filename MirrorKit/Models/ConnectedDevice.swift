import Foundation
import CoreGraphics

/// Represents an iPhone connected via USB and detected through CoreMediaIO
struct ConnectedDevice: Identifiable, Hashable {
    /// Unique device identifier (AVCaptureDevice.uniqueID)
    let id: String
    /// Localized device name (e.g. "Achraf's iPhone")
    let name: String
    /// Model identifier (e.g. "iPhone15,2")
    let modelID: String
    /// Native video stream resolution (set after capture starts)
    var resolution: CGSize?
}
