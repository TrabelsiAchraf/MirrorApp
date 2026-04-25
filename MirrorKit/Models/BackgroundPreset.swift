import SwiftUI

/// Visual presets for the expanded-mode background. The current v1.0 hardcoded
/// gradient corresponds to `.midnight` (the default), preserving v1.0 behavior
/// for users with no stored preference.
enum BackgroundPreset: String, CaseIterable, Identifiable {
    case midnight
    case charcoal
    case snow
    case sunset
    case ocean
    case aurora
    case black
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .midnight:  return "Midnight"
        case .charcoal:  return "Charcoal"
        case .snow:      return "Snow"
        case .sunset:    return "Sunset"
        case .ocean:     return "Ocean"
        case .aurora:    return "Aurora"
        case .black:     return "Black"
        case .custom:    return "Custom"
        }
    }

    /// Returns the SwiftUI background view for this preset.
    /// `customColor` is only used when `self == .custom`.
    @ViewBuilder
    func makeBackground(customColor: Color) -> some View {
        switch self {
        case .midnight:
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.11, blue: 0.25),
                    Color(red: 0.08, green: 0.08, blue: 0.18),
                    Color(red: 0.05, green: 0.05, blue: 0.12)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        case .charcoal:
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.16, blue: 0.19),
                    Color(red: 0.11, green: 0.11, blue: 0.12),
                    Color(red: 0.06, green: 0.06, blue: 0.06)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        case .snow:
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.96, blue: 0.97),
                    Color(red: 0.88, green: 0.88, blue: 0.91),
                    Color(red: 0.78, green: 0.78, blue: 0.80)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        case .sunset:
            LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.55, blue: 0.26),
                    Color(red: 0.93, green: 0.27, blue: 0.50),
                    Color(red: 0.53, green: 0.20, blue: 0.60)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        case .ocean:
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.16, blue: 0.29),
                    Color(red: 0.05, green: 0.36, blue: 0.72),
                    Color(red: 0.05, green: 0.09, blue: 0.15)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        case .aurora:
            LinearGradient(
                colors: [
                    Color(red: 0.55, green: 0.36, blue: 0.96),
                    Color(red: 0.93, green: 0.28, blue: 0.60),
                    Color(red: 0.02, green: 0.71, blue: 0.83)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        case .black:
            Color.black
        case .custom:
            customColor
        }
    }
}
