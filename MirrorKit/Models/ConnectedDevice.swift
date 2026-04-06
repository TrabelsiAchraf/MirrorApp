import Foundation
import CoreGraphics

/// Représente un iPhone connecté en USB détecté par CoreMediaIO
struct ConnectedDevice: Identifiable, Hashable {
    /// Identifiant unique de l'appareil (AVCaptureDevice.uniqueID)
    let id: String
    /// Nom localisé de l'appareil (ex: "iPhone de Achraf")
    let name: String
    /// Identifiant du modèle (ex: "iPhone15,2")
    let modelID: String
    /// Résolution native du flux vidéo (renseignée après le début de la capture)
    var resolution: CGSize?
}
