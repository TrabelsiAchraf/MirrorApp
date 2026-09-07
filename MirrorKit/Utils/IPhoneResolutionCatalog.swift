import CoreGraphics

/// Maps native iPhone screen resolutions to a display name and bezel geometry.
///
/// AVFoundation reports `modelID = "iOS Device"` for USB screen-capture
/// devices, so the stream resolution is the only signal we have. Several
/// models share a panel; the entry names the most recent one and the notch
/// style shared by the whole group.
enum IPhoneResolutionCatalog {
    struct Entry {
        /// Native portrait panel size in pixels.
        let width: Int
        let height: Int
        let displayName: String
        let notchStyle: DeviceFrameSpec.NotchStyle
        let cornerRadius: CGFloat
        let bezelWidth: CGFloat
    }

    /// The capture stream can round an odd native width up to an even number
    /// (the 1179×2556 iPhone 14 Pro streams as 1180×2556), so the lookup
    /// accepts a small per-dimension slack.
    static let tolerance = 2

    private static let entries: [Entry] = [
        // Dynamic Island generation
        Entry(width: 1320, height: 2868, displayName: "iPhone 17 Pro Max", notchStyle: .dynamicIsland, cornerRadius: 55, bezelWidth: 5), // 16 Pro Max
        Entry(width: 1206, height: 2622, displayName: "iPhone 17 Pro", notchStyle: .dynamicIsland, cornerRadius: 55, bezelWidth: 5),     // 17, 16 Pro
        Entry(width: 1260, height: 2736, displayName: "iPhone Air", notchStyle: .dynamicIsland, cornerRadius: 55, bezelWidth: 5),
        Entry(width: 1290, height: 2796, displayName: "iPhone 16 Plus", notchStyle: .dynamicIsland, cornerRadius: 55, bezelWidth: 6),    // 15 Plus, 15 Pro Max, 14 Pro Max
        Entry(width: 1179, height: 2556, displayName: "iPhone 16", notchStyle: .dynamicIsland, cornerRadius: 55, bezelWidth: 6),         // 15, 15 Pro, 14 Pro
        // Notch generation
        Entry(width: 1170, height: 2532, displayName: "iPhone 14", notchStyle: .notch, cornerRadius: 47, bezelWidth: 6),                 // 13, 12 (16e shares it)
        Entry(width: 1284, height: 2778, displayName: "iPhone 14 Plus", notchStyle: .notch, cornerRadius: 47, bezelWidth: 6),            // 13 Pro Max, 12 Pro Max
        Entry(width: 1080, height: 2340, displayName: "iPhone 13 mini", notchStyle: .notch, cornerRadius: 47, bezelWidth: 6),            // 12 mini
        Entry(width: 1125, height: 2436, displayName: "iPhone 11 Pro", notchStyle: .notch, cornerRadius: 47, bezelWidth: 6),             // XS, X
        Entry(width: 1242, height: 2688, displayName: "iPhone 11 Pro Max", notchStyle: .notch, cornerRadius: 47, bezelWidth: 6),         // XS Max
        Entry(width: 828, height: 1792, displayName: "iPhone 11", notchStyle: .notch, cornerRadius: 47, bezelWidth: 7),                  // XR
        // Home button generation
        Entry(width: 750, height: 1334, displayName: "iPhone SE", notchStyle: .none, cornerRadius: 40, bezelWidth: 8),                   // 8, 7, 6s
        Entry(width: 1080, height: 1920, displayName: "iPhone 8 Plus", notchStyle: .none, cornerRadius: 40, bezelWidth: 8),
    ]

    /// Orientation-insensitive lookup with `tolerance` px of slack per
    /// dimension. Returns `nil` for unknown sizes.
    static func match(_ resolution: CGSize) -> Entry? {
        let w = Int(min(resolution.width, resolution.height).rounded())
        let h = Int(max(resolution.width, resolution.height).rounded())
        return entries.first { abs($0.width - w) <= tolerance && abs($0.height - h) <= tolerance }
    }
}
