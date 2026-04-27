import Foundation
import CoreGraphics

/// Describes the iPhone / iPad frame to draw
struct DeviceFrameSpec {
    /// Display name of the model
    let displayName: String
    /// Device family — drives the bezel geometry in `DeviceFrameView`.
    let kind: Kind
    /// Outer corner radius of the frame (in points, at native scale)
    let cornerRadius: CGFloat
    /// Bezel thickness around the screen (in points)
    let bezelWidth: CGFloat
    /// Frame color
    let frameColor: FrameColor
    /// Notch / Dynamic Island style
    let notchStyle: NotchStyle

    enum Kind {
        case iPhone
        case iPad
    }

    enum FrameColor: String, CaseIterable {
        case black
        case silver
        case gold

        var hex: String {
            switch self {
            case .black: return "#1C1C1E"
            case .silver: return "#E3E3E8"
            case .gold: return "#F5E6CE"
            }
        }
    }

    enum NotchStyle {
        /// Dynamic Island (iPhone 14 Pro+, 15, 16)
        case dynamicIsland
        /// Classic notch (iPhone X to 14)
        case notch
        /// No notch (iPhone SE, older models)
        case none
    }
}

extension DeviceFrameSpec {
    /// Returns a copy of this spec with the frame color replaced.
    func with(frameColor: FrameColor) -> DeviceFrameSpec {
        DeviceFrameSpec(
            displayName: displayName,
            kind: kind,
            cornerRadius: cornerRadius,
            bezelWidth: bezelWidth,
            frameColor: frameColor,
            notchStyle: notchStyle
        )
    }
}

/// Provides frame specifications for each iPhone model
enum DeviceFrameProvider {

    /// Aspect ratio (W:H) the captureView container should be locked to (via
    /// `.aspectRatio(_, contentMode: .fit)`) so the bezel renderer's inner
    /// screen rect — after the spec's symmetric bezel inset — exactly matches
    /// the device's native aspect. Result: `.resizeAspect` fills with no
    /// letterbox AND no stretch.
    ///
    /// We can't lock this on the window itself because the layout above the
    /// captureView (floating toolbar) steals vertical space — the device area
    /// has a different aspect than the window.
    ///
    /// For non-classic styles (no bezel) returns the raw resolution.
    /// Math: (W - 2αW)/(H - 2αW) = ρ → W/H = ρ / (1 - 2α(1-ρ))
    /// where α = bezelWidth / reference and ρ = resolution.width / resolution.height
    /// (assumes portrait — W < H — which is how AVFoundation reports iPhone resolutions).
    static func bezelCorrectedAspect(for spec: DeviceFrameSpec, resolution: CGSize, hasBezel: Bool) -> CGSize {
        guard hasBezel, resolution.width > 0, resolution.height > 0 else { return resolution }
        let ρ = resolution.width / resolution.height
        let reference: CGFloat = spec.kind == .iPad ? 820 : 390
        let α = spec.bezelWidth / reference
        let factor = 1 - 2 * α * (1 - ρ)
        guard factor > 0 else { return resolution }
        let correctedRatio = ρ / factor
        return CGSize(width: resolution.height * correctedRatio, height: resolution.height)
    }

    /// Returns the frame specification for a given modelID. If the modelID
    /// identifies an iPad, an iPad-shaped spec is returned. When `resolution`
    /// is provided, the aspect ratio is used as a secondary heuristic — AVFoundation
    /// often reports generic modelIDs for USB-connected devices, so the 4:3-ish
    /// ratio of iPads is the most reliable signal.
    static func frameSpec(for modelID: String, resolution: CGSize? = nil) -> DeviceFrameSpec {
        let iPad = modelID.hasPrefix("iPad") || isIPadResolution(resolution)
        return iPad ? iPadSpec(for: modelID) : iPhoneSpec(for: modelID)
    }

    /// iPads are ~4:3 (1.33) or ~3:4 (0.75). iPhones are ~19.5:9 (2.17) or ~9:19.5 (0.46).
    /// A threshold of 1.5 / 0.67 cleanly separates the two families.
    private static func isIPadResolution(_ size: CGSize?) -> Bool {
        guard let size, size.width > 0, size.height > 0 else { return false }
        let ratio = max(size.width, size.height) / min(size.width, size.height)
        return ratio < 1.7  // iPads: ~1.33, iPhones: ~2.17
    }

    /// Returns an iPhone spec (previous behavior).
    private static func iPhoneSpec(for modelID: String) -> DeviceFrameSpec {
        let majorVersion = extractMajorVersion(from: modelID, prefix: "iPhone")
        switch majorVersion {
        case 17:
            return DeviceFrameSpec(
                displayName: "iPhone 16",
                kind: .iPhone,
                cornerRadius: 55,
                bezelWidth: 6,
                frameColor: .black,
                notchStyle: .dynamicIsland
            )
        case 16:
            return DeviceFrameSpec(
                displayName: "iPhone 15 Pro",
                kind: .iPhone,
                cornerRadius: 55,
                bezelWidth: 5,
                frameColor: .black,
                notchStyle: .dynamicIsland
            )
        case 15:
            return DeviceFrameSpec(
                displayName: "iPhone 15",
                kind: .iPhone,
                cornerRadius: 55,
                bezelWidth: 6,
                frameColor: .black,
                notchStyle: .dynamicIsland
            )
        case 14:
            return DeviceFrameSpec(
                displayName: "iPhone 14",
                kind: .iPhone,
                cornerRadius: 47,
                bezelWidth: 6,
                frameColor: .black,
                notchStyle: .notch
            )
        default:
            return DeviceFrameSpec(
                displayName: "iPhone",
                kind: .iPhone,
                cornerRadius: 40,
                bezelWidth: 8,
                frameColor: .black,
                notchStyle: .none
            )
        }
    }

    /// Returns an iPad spec — uniform thin bezels, modest corner radius, no notch.
    private static func iPadSpec(for modelID: String) -> DeviceFrameSpec {
        // iPad families: iPadPro (>=13"), iPad Air / iPad Pro 11", iPad mini, base iPad.
        // We only reliably know "iPad" vs "iPadPro" from the prefix; for the rest
        // we fall back on a single "iPad" name. A later refinement can use the
        // detected resolution to pick between Mini / Air / Pro 13.
        let displayName: String
        if modelID.hasPrefix("iPadPro") {
            displayName = "iPad Pro"
        } else if modelID.hasPrefix("iPadMini") {
            displayName = "iPad mini"
        } else if modelID.hasPrefix("iPadAir") {
            displayName = "iPad Air"
        } else {
            displayName = "iPad"
        }

        return DeviceFrameSpec(
            displayName: displayName,
            kind: .iPad,
            cornerRadius: 28,
            bezelWidth: 10,
            frameColor: .black,
            notchStyle: .none
        )
    }

    /// Extracts the major version number from a modelID (e.g. "iPhone17,3" → 17)
    private static func extractMajorVersion(from modelID: String, prefix: String) -> Int {
        let cleaned = modelID.replacingOccurrences(of: prefix, with: "")
        let parts = cleaned.split(separator: ",")
        return Int(parts.first ?? "") ?? 0
    }
}
