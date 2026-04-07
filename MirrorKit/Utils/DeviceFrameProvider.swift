import Foundation
import CoreGraphics

/// Describes the iPhone frame to draw
struct DeviceFrameSpec {
    /// Display name of the model
    let displayName: String
    /// Outer corner radius of the frame (in points, at native scale)
    let cornerRadius: CGFloat
    /// Bezel thickness around the screen (in points)
    let bezelWidth: CGFloat
    /// Frame color
    let frameColor: FrameColor
    /// Notch / Dynamic Island style
    let notchStyle: NotchStyle

    enum FrameColor {
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

/// Provides frame specifications for each iPhone model
enum DeviceFrameProvider {

    /// Returns the frame specification for a given modelID
    static func frameSpec(for modelID: String) -> DeviceFrameSpec {
        // Extract the model number (e.g. "iPhone17,3" → 17)
        let majorVersion = extractMajorVersion(from: modelID)

        switch majorVersion {
        // iPhone 16 / 16 Plus / 16 Pro / 16 Pro Max
        case 17:
            return DeviceFrameSpec(
                displayName: "iPhone 16",
                cornerRadius: 55,
                bezelWidth: 6,
                frameColor: .black,
                notchStyle: .dynamicIsland
            )

        // iPhone 15 Pro / 15 Pro Max
        case 16:
            return DeviceFrameSpec(
                displayName: "iPhone 15 Pro",
                cornerRadius: 55,
                bezelWidth: 5,
                frameColor: .black,
                notchStyle: .dynamicIsland
            )

        // iPhone 15 / 15 Plus / iPhone 14 Pro / 14 Pro Max
        case 15:
            return DeviceFrameSpec(
                displayName: "iPhone 15",
                cornerRadius: 55,
                bezelWidth: 6,
                frameColor: .black,
                notchStyle: .dynamicIsland
            )

        // iPhone 14 / 14 Plus / iPhone 13 / 13 mini
        case 14:
            return DeviceFrameSpec(
                displayName: "iPhone 14",
                cornerRadius: 47,
                bezelWidth: 6,
                frameColor: .black,
                notchStyle: .notch
            )

        // Older models or SE
        default:
            return DeviceFrameSpec(
                displayName: "iPhone",
                cornerRadius: 40,
                bezelWidth: 8,
                frameColor: .black,
                notchStyle: .none
            )
        }
    }

    /// Extracts the major version number from the modelID (e.g. "iPhone17,3" → 17)
    private static func extractMajorVersion(from modelID: String) -> Int {
        let cleaned = modelID.replacingOccurrences(of: "iPhone", with: "")
        let parts = cleaned.split(separator: ",")
        return Int(parts.first ?? "") ?? 0
    }
}
