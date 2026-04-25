import Foundation

/// User-selectable rendering style for the iPhone bezel around the mirror video.
/// `none` is the v1.0 `showDeviceFrame=false` behavior preserved by the
/// Task 7 legacy migration.
enum BezelStyle: String, CaseIterable, Identifiable {
    case classic
    case floating
    case none

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic:  return "Classic"
        case .floating: return "Floating"
        case .none:     return "Frameless"
        }
    }
}

/// One-shot UserDefaults migrations from v1.0 to v1.1.
/// Idempotent — safe to call multiple times.
enum LegacyMigration {
    /// Migrates v1.0's `showDeviceFrame` Bool to v1.1's `bezelStyle` String key.
    /// Returns `true` if a migration was performed (i.e. `bezelStyle` was newly written).
    @discardableResult
    static func migrateBezelStyleIfNeeded(in defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: "bezelStyle") == nil else { return false }
        if let legacy = defaults.object(forKey: "showDeviceFrame") as? Bool {
            defaults.set(legacy ? "classic" : "none", forKey: "bezelStyle")
        } else {
            defaults.set("classic", forKey: "bezelStyle")
        }
        return true
    }
}
