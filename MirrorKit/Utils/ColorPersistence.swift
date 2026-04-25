import SwiftUI
import AppKit

/// Color ↔ hex string round-trip helpers used by `@AppStorage` properties.
/// On parse failure, the caller falls back to a sensible default (.black).
enum ColorPersistence {
    /// Parses "#RRGGBB" or "RRGGBB" into a SwiftUI `Color`.
    /// Alpha is always 1.0 (we never persist transparency).
    static func color(fromHex hex: String) -> Color? {
        var trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") {
            trimmed.removeFirst()
        }
        guard trimmed.count == 6 else { return nil }
        var rgb: UInt64 = 0
        guard Scanner(string: trimmed).scanHexInt64(&rgb) else { return nil }
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    /// Encodes an `NSColor` (the type emitted by NSColorPanel) as "#RRGGBB".
    static func hex(from nsColor: NSColor) -> String {
        let converted = nsColor.usingColorSpace(.sRGB) ?? nsColor
        let r = Int((converted.redComponent * 255.0).rounded())
        let g = Int((converted.greenComponent * 255.0).rounded())
        let b = Int((converted.blueComponent * 255.0).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

extension Color {
    /// Convenience initializer used at SwiftUI binding sites.
    init?(hex: String) {
        guard let color = ColorPersistence.color(fromHex: hex) else { return nil }
        self = color
    }
}
