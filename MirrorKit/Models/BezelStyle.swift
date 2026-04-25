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
