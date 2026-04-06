import Foundation
import CoreGraphics

/// Décrit la forme du cadre iPhone à dessiner
struct DeviceFrameSpec {
    /// Nom du modèle pour l'affichage
    let displayName: String
    /// Rayon des coins extérieurs du cadre (en points, à l'échelle native)
    let cornerRadius: CGFloat
    /// Épaisseur du cadre autour de l'écran (en points)
    let bezelWidth: CGFloat
    /// Couleur du cadre
    let frameColor: FrameColor
    /// Type d'encoche / Dynamic Island
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
        /// Encoche classique (iPhone X à 14)
        case notch
        /// Pas d'encoche (iPhone SE, anciens modèles)
        case none
    }
}

/// Fournit les spécifications de cadre pour chaque modèle d'iPhone
enum DeviceFrameProvider {

    /// Retourne la spécification du cadre pour un modelID donné
    static func frameSpec(for modelID: String) -> DeviceFrameSpec {
        // Extraire le numéro de modèle (ex: "iPhone17,3" → 17)
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

        // Modèles plus anciens ou SE
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

    /// Extrait le numéro de version majeur du modelID (ex: "iPhone17,3" → 17)
    private static func extractMajorVersion(from modelID: String) -> Int {
        let cleaned = modelID.replacingOccurrences(of: "iPhone", with: "")
        let parts = cleaned.split(separator: ",")
        return Int(parts.first ?? "") ?? 0
    }
}
